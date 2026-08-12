#!/usr/bin/env python3
"""Independent nonlinear-sweep log analyzer for the jigmotor project.

Does NOT trust firmware-emitted RESULT lines. Every metric is recomputed
directly from DATA rows, using formulas that mirror
Core/Src/nonlinear_test.c's ComputeHarmonicFull/ComputeSweepStats exactly
(see docs/nonlinear_algorithm_audit.md, ALG-018, for why RESULT alone
cannot be trusted: it is printed unconditionally regardless of sweep
validity and carries no self-contained MeasurementValid flag).

Log line shapes handled (schema v4/v5/v6, positional DATA/ACQ, key=value
META/RESULT/END/CONFIG/BATCH/SHADOW_*):

    META,SchemaVersion=...,TestID=...,SweepID=...,JigID=...,...
    DATA,<schema>,<testId>,<sweepId>,<jigId>,<motorId>,<dir>,<index>,<targetRawAbs>,<angleRaw>,<angleDeg>,<errorDeg>
    ACQ,<schema>,<testId>,<sweepId>,<dir>,<index>,<csAssertCycle>,<pwmCounter>,<attempts>,<flagsHex>
    RESULT,SchemaVersion=...,...  (NOT trusted -- diagnostic only, see --dump-firmware-result)
    END,SchemaVersion=...,TestID=...,SweepID=...,...,Status=VALID|INVALID

A sweep is only "official-analyzable" if it has a META record identifying
it, an END record with Status=VALID, MeasurementValid=1, and -- whenever
the batch-role fields exist -- RunRole=OFFICIAL plus
EligibleForStatistics=1. Sweeps without those conditions are still parsed
and reported, but excluded from cross-run/cross-jig statistics.

Usage:
    python tools/analyze_motor_logs.py LOGFILE [LOGFILE ...] [--csv OUT.csv] [--json OUT.json]
    python tools/analyze_motor_logs.py --self-test
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Contract defaults. Current logs declare AnalysisPoints in META and use
# CANONICAL_Q16_1DEG360_V2. The 256-point values below are only a legacy
# fallback for old records that predate AnalysisPoints.
# ---------------------------------------------------------------------------

FULL_TURN_RAW = 65536.0
Q16_SCALE = 65536
LEGACY_ANALYSIS_POINT_COUNT = 256
LEGACY_STEP_RAW = 256
CURRENT_ANALYSIS_POINT_COUNT = 360
HARMONIC_ORDERS = (1, 2, 3, 6, 9, 12, 18, 27, 36, 45, 72, 108)  # NL_HARMONIC_ORDERS
ROBUST_EXTREME_COUNT = 5  # NL_ROBUST_EXTREME_COUNT


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class DataPoint:
    index: int
    target_raw_abs: int
    angle_raw: int
    angle_deg: float
    error_deg: float
    command_raw_q16: Optional[int] = None
    mean_unwrapped_raw_q16: Optional[int] = None
    error_raw_q16: Optional[int] = None


@dataclass
class Sweep:
    """Everything collected under one (TestID, SweepID)."""
    test_id: Optional[int] = None
    sweep_id: Optional[int] = None
    schema_version: Optional[int] = None
    jig_id: Optional[str] = None
    motor_id: Optional[str] = None
    direction: Optional[str] = None
    run_order: Optional[int] = None            # from META RunOrder, if batch mode
    run_role: Optional[str] = None             # META RunRole: "PRECONDITION"/"OFFICIAL" (new schema only)
    eligible_for_statistics: Optional[bool] = None  # META EligibleForStatistics (new schema only)
    step_raw: Optional[int] = None
    shadow_contract_version: Optional[str] = None
    meta_measurement_valid: Optional[bool] = None
    meta_tracking_valid: Optional[bool] = None
    end_status: Optional[str] = None            # "VALID" / "INVALID" / None if no END seen
    captured_points: Optional[int] = None
    analysis_points: Optional[int] = None
    points: Dict[int, DataPoint] = field(default_factory=dict)
    source_file: str = ""
    parse_warnings: List[str] = field(default_factory=list)

    @property
    def has_meta(self) -> bool:
        return self.test_id is not None and self.sweep_id is not None and self.jig_id is not None

    @property
    def analysis_point_count(self) -> int:
        if self.analysis_points is not None and self.analysis_points > 0:
            return self.analysis_points
        return LEGACY_ANALYSIS_POINT_COUNT

    @property
    def closure_index(self) -> int:
        return self.analysis_point_count

    @property
    def uses_declared_role_contract(self) -> bool:
        return self.run_role is not None or self.eligible_for_statistics is not None

    def analysis_angle_deg(self, index: int) -> float:
        """Returns the analysis coordinate for one point.

        Legacy fixed-step logs use StepRaw=256. Current one-degree logs
        deliberately emit StepRaw=0 because their rounded 182/183-raw
        increments cannot be represented by one fixed raw step.
        """
        if self.step_raw is not None and self.step_raw > 0:
            return 360.0 * index * self.step_raw / FULL_TURN_RAW
        return 360.0 * index / self.analysis_point_count

    @property
    def is_official_valid(self) -> bool:
        """True only when META, END, and declared batch-role semantics agree.

        Deliberately does NOT fall back to firmware's RESULT-line presence
        or to "no END seen but looks fine" -- an incomplete/truncated
        capture (crash, UART drop, power loss mid-batch) must never be
        silently treated as valid.
        """
        base_valid = (
            self.has_meta
            and self.end_status == "VALID"
            and (self.meta_measurement_valid is True)
        )
        if not base_valid:
            return False
        if self.uses_declared_role_contract:
            return (
                self.run_role == "OFFICIAL"
                and self.eligible_for_statistics is True
            )
        # Legacy logs have no role fields. Keep them analyzable, but callers
        # label their eligibility source as legacy instead of guessing that
        # "the first run" was a precondition.
        return True

    @property
    def eligibility_source(self) -> str:
        return "DECLARED_ROLE" if self.uses_declared_role_contract else "LEGACY_NO_ROLE"

    def sorted_points(self) -> List[DataPoint]:
        return [self.points[i] for i in sorted(self.points.keys())]


# ---------------------------------------------------------------------------
# Line parsing
# ---------------------------------------------------------------------------

def _parse_kv_line(line: str) -> Tuple[str, Dict[str, str]]:
    """META/RESULT/END/CONFIG/BATCH/SHADOW_* lines: RECORD,key=val,key=val,...

    Values are never split further here (kept as strings); callers convert
    the specific fields they need. A malformed key=val token (no '=') is
    kept under a synthetic key so it is visible in parse_warnings rather
    than silently dropped.
    """
    parts = line.rstrip("\r\n").split(",")
    record = parts[0]
    fields: Dict[str, str] = {}
    for i, tok in enumerate(parts[1:]):
        if "=" in tok:
            k, _, v = tok.partition("=")
            fields[k] = v
        else:
            fields[f"_unparsed_{i}"] = tok
    return record, fields


def parse_data_line(line: str) -> Optional[Tuple[int, int, int, str, str, str, DataPoint]]:
    """DATA,<schema>,<testId>,<sweepId>,<jigId>,<motorId>,<dir>,<index>,<targetRawAbs>,<angleRaw>,<angleDeg>,<errorDeg>

    Returns (schema, testId, sweepId, jigId, motorId, direction, DataPoint)
    Schema 4/5 has exactly 12 positional fields. Schema 6 retains those
    fields for readability and appends canonical key=value fields. For
    schema 6 ErrorRawQ16 is authoritative over positional ErrorDeg.
    """
    parts = line.rstrip("\r\n").split(",")
    if len(parts) < 12 or parts[0] != "DATA":
        return None
    try:
        schema = int(parts[1])
        test_id = int(parts[2])
        sweep_id = int(parts[3])
        jig_id = parts[4]
        motor_id = parts[5]
        direction = parts[6]
        index = int(parts[7])
        target_raw_abs = int(parts[8])
        angle_raw = int(parts[9])
        angle_deg = float(parts[10])
        error_deg = float(parts[11])
    except ValueError:
        return None
    extras: Dict[str, str] = {}
    for token in parts[12:]:
        if "=" not in token:
            return None
        key, _, value = token.partition("=")
        extras[key] = value
    command_raw_q16: Optional[int] = None
    mean_unwrapped_raw_q16: Optional[int] = None
    error_raw_q16: Optional[int] = None
    if schema >= 6:
        try:
            command_raw_q16 = int(extras["CommandRawQ16"])
            mean_unwrapped_raw_q16 = int(extras["MeanUnwrappedRawQ16"])
            error_raw_q16 = int(extras["ErrorRawQ16"])
        except (KeyError, ValueError):
            return None
        error_deg = error_raw_q16 * 360.0 / (FULL_TURN_RAW * Q16_SCALE)
    point = DataPoint(index=index, target_raw_abs=target_raw_abs, angle_raw=angle_raw,
                       angle_deg=angle_deg, error_deg=error_deg,
                       command_raw_q16=command_raw_q16,
                       mean_unwrapped_raw_q16=mean_unwrapped_raw_q16,
                       error_raw_q16=error_raw_q16)
    return schema, test_id, sweep_id, jig_id, motor_id, direction, point


def _to_bool01(s: Optional[str]) -> Optional[bool]:
    if s is None:
        return None
    if s == "1":
        return True
    if s == "0":
        return False
    return None


def _to_int(s: Optional[str]) -> Optional[int]:
    if s is None:
        return None
    try:
        return int(s)
    except ValueError:
        return None


# ---------------------------------------------------------------------------
# File loading -> Sweep objects
# ---------------------------------------------------------------------------

def load_sweeps(path: Path) -> Tuple[List[Sweep], List[str]]:
    """Parses one log file into a list of Sweep records, grouped by
    (TestID, SweepID). Never raises on a malformed line -- collects a
    warning and continues, so one corrupted line cannot hide the rest of a
    (possibly large) log file.
    """
    sweeps: Dict[Tuple[int, int], Sweep] = {}
    warnings: List[str] = []

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        return [], [f"{path}: could not read file: {exc}"]

    for line_no, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue

        if line.startswith("META,"):
            _, f = _parse_kv_line(line)
            test_id = _to_int(f.get("TestID"))
            sweep_id = _to_int(f.get("SweepID"))
            if test_id is None or sweep_id is None:
                warnings.append(f"{path}:{line_no}: META missing TestID/SweepID, skipped")
                continue
            key = (test_id, sweep_id)
            sw = sweeps.setdefault(key, Sweep(source_file=str(path)))
            sw.test_id = test_id
            sw.sweep_id = sweep_id
            sw.schema_version = _to_int(f.get("SchemaVersion"))
            sw.jig_id = f.get("JigID")
            sw.motor_id = f.get("MotorID")
            sw.direction = f.get("Direction")
            sw.run_order = _to_int(f.get("RunOrder"))
            sw.run_role = f.get("RunRole")
            sw.eligible_for_statistics = _to_bool01(f.get("EligibleForStatistics"))
            step_raw = _to_int(f.get("StepRaw"))
            if step_raw is not None:
                sw.step_raw = step_raw
            sw.shadow_contract_version = f.get("ShadowContractVersion")
            measurement_valid = f.get("OfficialMeasurementValid")
            if measurement_valid is None:
                measurement_valid = f.get("MeasurementValid")
            sw.meta_measurement_valid = _to_bool01(measurement_valid)
            sw.meta_tracking_valid = _to_bool01(f.get("TrackingValid"))
            sw.captured_points = _to_int(f.get("CapturedPoints"))
            sw.analysis_points = _to_int(f.get("AnalysisPoints"))

        elif line.startswith("DATA,"):
            parsed = parse_data_line(line)
            if parsed is None:
                warnings.append(f"{path}:{line_no}: malformed DATA line, skipped: {line[:80]}")
                continue
            schema, test_id, sweep_id, jig_id, motor_id, direction, point = parsed
            key = (test_id, sweep_id)
            sw = sweeps.setdefault(key, Sweep(source_file=str(path)))
            # Backfill identity from DATA only if META hasn't been seen yet for
            # this key -- META, when present, is authoritative (matches the
            # schema-v6 contract's identity-precedence rule even though this
            # tool also accepts v4/v5 logs that predate that contract).
            if sw.test_id is None:
                sw.test_id, sw.sweep_id = test_id, sweep_id
            if sw.jig_id is None:
                sw.jig_id = jig_id
            if sw.motor_id is None:
                sw.motor_id = motor_id
            if sw.direction is None:
                sw.direction = direction
            if point.index in sw.points:
                warnings.append(
                    f"{path}:{line_no}: duplicate DATA index {point.index} for "
                    f"TestID={test_id} SweepID={sweep_id}, keeping first occurrence")
                continue
            sw.points[point.index] = point

        elif line.startswith("END,"):
            _, f = _parse_kv_line(line)
            test_id = _to_int(f.get("TestID"))
            sweep_id = _to_int(f.get("SweepID"))
            if test_id is None or sweep_id is None:
                warnings.append(f"{path}:{line_no}: END missing TestID/SweepID, skipped")
                continue
            key = (test_id, sweep_id)
            sw = sweeps.setdefault(key, Sweep(source_file=str(path)))
            sw.end_status = f.get("Status")

        # RESULT/CONFIG/BATCH/SHADOW_*/ACQ/NL curve/legacy lines: deliberately
        # not parsed for metric purposes (RESULT is diagnostic-only here, see
        # module docstring); ACQ carries per-point acquisition health, not
        # needed for the metric recomputation this tool exists to do.

    for sw in sweeps.values():
        sw.source_file = str(path)
        if not sw.has_meta:
            warnings.append(
                f"{path}: sweep with TestID={sw.test_id} SweepID={sw.sweep_id} has "
                f"DATA rows but no META record -- identity is unauthoritative, "
                f"will be reported but excluded from official statistics")
        if sw.end_status is None:
            warnings.append(
                f"{path}: sweep TestID={sw.test_id} SweepID={sw.sweep_id} has no END "
                f"record (truncated log?) -- treated as not officially valid")

    return list(sweeps.values()), warnings


# ---------------------------------------------------------------------------
# Metric recomputation (mirrors nonlinear_test.c exactly; see
# docs/nonlinear_algorithm_audit.md for the line-by-line correspondence)
# ---------------------------------------------------------------------------

@dataclass
class HarmonicResult:
    order: int
    a: float
    b: float
    amplitude: float
    phase_deg: float


@dataclass
class RecomputedMetrics:
    analysis_count: int
    mean_dc: float
    rms_ac: float
    raw_p2p: float
    system_inl_deg: float
    robust_p2p: float
    p99_abs_deviation: float
    harmonics: Dict[int, HarmonicResult]
    closure_error_deg: Optional[float]
    closure_available: bool
    tracking_rms_deg: float
    tracking_max_abs_deg: float
    missing_indices: List[int]


def wrap_signed_deg(deg: float) -> float:
    """Matches WrapSignedDeg() in nonlinear_test.c exactly."""
    while deg > 180.0:
        deg -= 360.0
    while deg < -180.0:
        deg += 360.0
    return deg


def analysis_angle_deg(index: int, analysis_points: int,
                       step_raw: Optional[int] = None) -> float:
    if step_raw is not None and step_raw > 0:
        return 360.0 * index * step_raw / FULL_TURN_RAW
    return 360.0 * index / analysis_points


def compute_harmonic(errors: List[float], mean: float, order: int,
                     analysis_points: int,
                     step_raw: Optional[int] = None) -> HarmonicResult:
    """Matches ComputeHarmonicFull() in nonlinear_test.c.

    Fixed-step legacy logs use theta=360*i*StepRaw/65536. Current
    one-degree logs use theta=360*i/AnalysisPoints because StepRaw=0 is an
    explicit marker for the rounded 182/183-raw target grid.

    a = (2/N)*sum(centered*cos(order*theta)), b = (2/N)*sum(centered*sin(order*theta)),
    amplitude=hypot(a,b), phase=atan2(b,a) in degrees.
    """
    n = len(errors)
    if n == 0:
        return HarmonicResult(order=order, a=0.0, b=0.0, amplitude=0.0, phase_deg=0.0)
    sum_cos = 0.0
    sum_sin = 0.0
    for i, e in enumerate(errors):
        angle_deg = analysis_angle_deg(i, analysis_points, step_raw)
        angle_rad = math.radians(angle_deg)
        h_rad = order * angle_rad
        centered = e - mean
        sum_cos += centered * math.cos(h_rad)
        sum_sin += centered * math.sin(h_rad)
    a = (2.0 / n) * sum_cos
    b = (2.0 / n) * sum_sin
    amplitude = math.hypot(a, b)
    phase = math.degrees(math.atan2(b, a))
    return HarmonicResult(order=order, a=a, b=b, amplitude=amplitude, phase_deg=phase)


def recompute_metrics(sweep: Sweep) -> Optional[RecomputedMetrics]:
    """Recomputes every official metric from sweep.points directly -- never
    reads a RESULT line. The META AnalysisPoints field defines both the
    analysis range (0..N-1) and closure index N. Returns None if no analysis
    points are present; missing points are reported and make the record
    ineligible instead of being silently accepted.
    """
    analysis_count = sweep.analysis_point_count
    missing = [i for i in range(analysis_count) if i not in sweep.points]
    present_indices = [i for i in range(analysis_count) if i in sweep.points]
    if len(present_indices) < analysis_count:
        if not present_indices:
            return None
    errors = [sweep.points[i].error_deg for i in present_indices]
    n = len(errors)

    mean_dc = sum(errors) / n
    sum_sq_ac = sum((e - mean_dc) ** 2 for e in errors)
    rms_ac = math.sqrt(sum_sq_ac / n)

    sorted_errors = sorted(errors)
    raw_p2p = sorted_errors[-1] - sorted_errors[0]
    system_inl_deg = raw_p2p / 2.0
    k = min(ROBUST_EXTREME_COUNT, n)
    bottom = sorted_errors[:k]
    top = sorted_errors[-k:]
    robust_p2p = (sum(top) / k) - (sum(bottom) / k)

    abs_dev_sorted = sorted(abs(e - mean_dc) for e in errors)
    p99_idx = max(0, min(n - 1, math.ceil(0.99 * n) - 1))
    p99 = abs_dev_sorted[p99_idx]

    harmonics = {
        order: compute_harmonic(
            errors, mean_dc, order, analysis_count, sweep.step_raw)
        for order in HARMONIC_ORDERS
    }

    closure_index = sweep.closure_index
    closure_available = closure_index in sweep.points
    closure_error_deg = sweep.points[closure_index].error_deg if closure_available else None

    # Tracking RMS/max recomputed independently from AngleRaw/TargetRawAbs
    # columns (both present per-row in DATA), exactly mirroring the
    # WrapSignedDeg(measuredDeg - targetDeg) logic in CaptureSweep -- uses
    # ALL captured points (not just 0..255), matching firmware's own
    # capturedCount-wide tracking computation.
    track_sq_sum = 0.0
    track_max_abs = 0.0
    all_points = sweep.sorted_points()
    for p in all_points:
        measured_deg = p.angle_raw * 360.0 / FULL_TURN_RAW
        target_deg = p.target_raw_abs * 360.0 / FULL_TURN_RAW
        track_err = wrap_signed_deg(measured_deg - target_deg)
        track_sq_sum += track_err * track_err
        track_max_abs = max(track_max_abs, abs(track_err))
    tracking_rms = math.sqrt(track_sq_sum / len(all_points)) if all_points else 0.0

    return RecomputedMetrics(
        analysis_count=n,
        mean_dc=mean_dc,
        rms_ac=rms_ac,
        raw_p2p=raw_p2p,
        system_inl_deg=system_inl_deg,
        robust_p2p=robust_p2p,
        p99_abs_deviation=p99,
        harmonics=harmonics,
        closure_error_deg=closure_error_deg,
        closure_available=closure_available,
        tracking_rms_deg=tracking_rms,
        tracking_max_abs_deg=track_max_abs,
        missing_indices=missing,
    )


# ---------------------------------------------------------------------------
# Aggregation across runs / jigs / products
# ---------------------------------------------------------------------------

@dataclass
class SweepReport:
    sweep: Sweep
    metrics: Optional[RecomputedMetrics]
    officially_valid: bool
    problems: List[str]


def build_report(sweep: Sweep) -> SweepReport:
    problems: List[str] = []
    contract_compatible = True
    if not sweep.has_meta:
        problems.append("no META record (unauthoritative identity)")
    if sweep.end_status is None:
        problems.append("no END record (truncated capture?)")
    elif sweep.end_status != "VALID":
        problems.append(f"END.Status={sweep.end_status}")
    if sweep.meta_measurement_valid is False:
        problems.append("META.MeasurementValid=0")
    if sweep.meta_measurement_valid is None and sweep.has_meta:
        problems.append("META.MeasurementValid missing")
    if sweep.uses_declared_role_contract:
        if sweep.run_role != "OFFICIAL":
            problems.append(f"META.RunRole={sweep.run_role or 'MISSING'} "
                            "(excluded from official statistics)")
        if sweep.eligible_for_statistics is not True:
            eligibility = ("MISSING" if sweep.eligible_for_statistics is None
                           else "0")
            problems.append(f"META.EligibleForStatistics={eligibility} "
                            "(excluded from official statistics)")

    if sweep.shadow_contract_version:
        expected_contract = (
            "CANONICAL_Q16_1DEG360_V2"
            if sweep.analysis_point_count == CURRENT_ANALYSIS_POINT_COUNT
            else "CANONICAL_Q16_V1"
        )
        historical_alias = (
            sweep.analysis_point_count == CURRENT_ANALYSIS_POINT_COUNT
            and sweep.shadow_contract_version == "CANONICAL_Q16_V1"
        )
        if historical_alias:
            problems.append(
                "historical contract alias: CANONICAL_Q16_V1 stamped on "
                "AnalysisPoints=360; interpreted as CANONICAL_Q16_1DEG360_V2")
        elif sweep.shadow_contract_version != expected_contract:
            problems.append(
                f"META.ShadowContractVersion={sweep.shadow_contract_version} "
                f"is incompatible with AnalysisPoints={sweep.analysis_point_count}")
            contract_compatible = False

    metrics = recompute_metrics(sweep)
    analysis_count = sweep.analysis_point_count
    if metrics is None:
        problems.append(
            f"no usable DATA points (0 of 0..{analysis_count - 1} present)")
    elif metrics.missing_indices:
        problems.append(f"{len(metrics.missing_indices)} of {analysis_count} analysis points missing "
                         f"(indices {metrics.missing_indices[:10]}"
                         f"{'...' if len(metrics.missing_indices) > 10 else ''})")
    if metrics is not None and not metrics.closure_available:
        problems.append(f"point {sweep.closure_index} (closure) not captured")

    officially_valid = (
        sweep.is_official_valid
        and contract_compatible
        and metrics is not None
        and not metrics.missing_indices
    )
    return SweepReport(sweep=sweep, metrics=metrics, officially_valid=officially_valid, problems=problems)


def group_key(sw: Sweep) -> Tuple[str, str]:
    return (sw.motor_id or "UNKNOWN_MOTOR", sw.jig_id or "UNKNOWN_JIG")


def infer_run_order(reports: List[SweepReport]) -> None:
    """Fills in run_order from file order when META has no RunOrder (schema
    v4 / non-batch logs): first sweep encountered per (motor,jig) group in
    file order is display run 1, etc. This does not infer a precondition or
    statistical role. Mutates sweep.run_order in place and never overwrites
    a real META RunOrder.
    """
    by_group: Dict[Tuple[str, str], List[SweepReport]] = {}
    for r in reports:
        by_group.setdefault(group_key(r.sweep), []).append(r)
    for group_reports in by_group.values():
        # Stable order: as encountered (dict preserves insertion order from load).
        next_order = 1
        for r in group_reports:
            if r.sweep.run_order is None:
                r.sweep.run_order = next_order
            next_order = max(next_order, r.sweep.run_order) + 1


def mean_sd_cv(values: List[float]) -> Tuple[Optional[float], Optional[float], Optional[float]]:
    if not values:
        return None, None, None
    m = statistics.mean(values)
    if len(values) < 2:
        return m, 0.0, (0.0 if m == 0 else 0.0)
    sd = statistics.stdev(values)
    cv = (sd / abs(m) * 100.0) if m != 0 else None
    return m, sd, cv


@dataclass
class GroupSummary:
    motor_id: str
    jig_id: str
    run_count: int
    conditioned_run_count: int  # declared official/eligible, or explicit legacy fallback
    fields: Dict[str, Dict[str, Optional[float]]]  # field name -> {mean, sd, cv, run2, run3, ...}
    invalid_runs: List[str]


TRACKED_FIELDS = ("rms_ac", "raw_p2p", "system_inl_deg", "robust_p2p", "closure_error_deg",
                   "tracking_rms_deg", "tracking_max_abs_deg", "mean_dc", "p99_abs_deviation")
TRACKED_HARMONICS = (1, 2, 9, 36)  # A1, A2, A9, A36 per the requested focus set


def summarize_group(motor_id: str, jig_id: str, reports: List[SweepReport]) -> GroupSummary:
    valid_reports = [r for r in reports if r.officially_valid]
    invalid_runs = [
        f"TestID={r.sweep.test_id} SweepID={r.sweep.sweep_id} RunOrder={r.sweep.run_order}: "
        f"{'; '.join(r.problems)}"
        for r in reports if not r.officially_valid
    ]
    # is_official_valid already applies the declared RunRole and
    # EligibleForStatistics contract. Do not add a second, positional
    # definition such as RunOrder>=2 here.
    conditioned = valid_reports

    fields: Dict[str, Dict[str, Optional[float]]] = {}
    for name in TRACKED_FIELDS:
        values = [getattr(r.metrics, name) for r in conditioned if getattr(r.metrics, name) is not None]
        m, sd, cv = mean_sd_cv(values)
        run_values = {
            f"run{r.sweep.run_order}": getattr(r.metrics, name)
            for r in conditioned
        }
        fields[name] = {"mean": m, "sd": sd, "cv_pct": cv, **run_values}

    for order in TRACKED_HARMONICS:
        values = [r.metrics.harmonics[order].amplitude for r in conditioned if order in r.metrics.harmonics]
        m, sd, cv = mean_sd_cv(values)
        run_values = {
            f"run{r.sweep.run_order}": r.metrics.harmonics[order].amplitude
            for r in conditioned if order in r.metrics.harmonics
        }
        fields[f"A{order}"] = {"mean": m, "sd": sd, "cv_pct": cv, **run_values}

    return GroupSummary(
        motor_id=motor_id, jig_id=jig_id,
        run_count=len(reports), conditioned_run_count=len(conditioned),
        fields=fields, invalid_runs=invalid_runs,
    )


def cross_jig_delta(summaries: List[GroupSummary]) -> List[str]:
    """Text lines comparing every jig pair for the same motor, for every
    tracked field -- absolute delta and percentage (relative to the first
    jig's mean). Does not attempt any offset correction (see
    docs/cross_jig_measurement_analysis.md for why a scalar offset cannot
    reconcile amplitude/phase/closure differences).
    """
    by_motor: Dict[str, List[GroupSummary]] = {}
    for s in summaries:
        by_motor.setdefault(s.motor_id, []).append(s)

    lines: List[str] = []
    for motor_id, group in sorted(by_motor.items()):
        if len(group) < 2:
            continue
        group_sorted = sorted(group, key=lambda s: s.jig_id)
        for i in range(len(group_sorted)):
            for j in range(i + 1, len(group_sorted)):
                a, b = group_sorted[i], group_sorted[j]
                lines.append(f"--- {motor_id}: {a.jig_id} vs {b.jig_id} ---")
                for field_name in list(TRACKED_FIELDS) + [f"A{o}" for o in TRACKED_HARMONICS]:
                    ma = a.fields.get(field_name, {}).get("mean")
                    mb = b.fields.get(field_name, {}).get("mean")
                    if ma is None or mb is None:
                        lines.append(f"  {field_name}: insufficient data")
                        continue
                    delta = mb - ma
                    pct = (delta / ma * 100.0) if ma != 0 else float("nan")
                    lines.append(f"  {field_name}: {a.jig_id}={ma:.4f} {b.jig_id}={mb:.4f} "
                                 f"delta={delta:+.4f} ({pct:+.1f}% rel. to {a.jig_id})")
    return lines


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def print_text_report(reports: List[SweepReport], summaries: List[GroupSummary],
                       warnings: List[str], out=sys.stdout) -> None:
    print("=" * 78, file=out)
    print("PARSE WARNINGS", file=out)
    print("=" * 78, file=out)
    if warnings:
        for w in warnings:
            print(f"  WARN: {w}", file=out)
    else:
        print("  (none)", file=out)

    print(file=out)
    print("=" * 78, file=out)
    print("PER-SWEEP STATUS", file=out)
    print("=" * 78, file=out)
    for r in reports:
        sw = r.sweep
        if r.officially_valid:
            status = ("OFFICIAL-VALID" if sw.uses_declared_role_contract
                      else "LEGACY-VALID")
        else:
            status = "EXCLUDED"
        print(f"  [{status}] Motor={sw.motor_id} Jig={sw.jig_id} TestID={sw.test_id} "
              f"SweepID={sw.sweep_id} RunOrder={sw.run_order} "
              f"Role={sw.run_role or 'LEGACY'} Eligible={sw.eligible_for_statistics} "
              f"AnalysisPoints={sw.analysis_point_count} file={sw.source_file}", file=out)
        for p in r.problems:
            print(f"      - {p}", file=out)
        if r.metrics:
            m = r.metrics
            print(f"      RMS_AC={m.rms_ac:.4f} RawP2P={m.raw_p2p:.4f} "
                  f"System_INL={m.system_inl_deg:.4f} RobustP2P={m.robust_p2p:.4f} "
                  f"Closure={m.closure_error_deg if m.closure_available else 'N/A'} "
                  f"TrackRMS={m.tracking_rms_deg:.4f} TrackMax={m.tracking_max_abs_deg:.4f}", file=out)

    print(file=out)
    print("=" * 78, file=out)
    print("GROUP SUMMARY (declared OFFICIAL + EligibleForStatistics, legacy explicitly labeled)", file=out)
    print("=" * 78, file=out)
    for s in summaries:
        print(f"\n  Motor={s.motor_id} Jig={s.jig_id}  "
              f"(runs total={s.run_count}, statistically eligible={s.conditioned_run_count})", file=out)
        if s.invalid_runs:
            print("    Excluded runs:", file=out)
            for line in s.invalid_runs:
                print(f"      - {line}", file=out)
        for field_name, stats in s.fields.items():
            mean = stats.get("mean")
            sd = stats.get("sd")
            cv = stats.get("cv_pct")
            if mean is None:
                print(f"    {field_name}: no statistically eligible runs", file=out)
                continue
            cv_str = f"{cv:.2f}%" if cv is not None else "N/A"
            print(f"    {field_name}: mean={mean:.4f} sd={sd:.4f} cv={cv_str}", file=out)

    print(file=out)
    print("=" * 78, file=out)
    print("CROSS-JIG DELTA (same motor, different jig)", file=out)
    print("=" * 78, file=out)
    for line in cross_jig_delta(summaries):
        print(f"  {line}", file=out)


def write_csv(reports: List[SweepReport], path: Path) -> None:
    fieldnames = ["motor_id", "jig_id", "test_id", "sweep_id", "run_order",
                  "run_role", "eligible_for_statistics", "eligibility_source",
                  "analysis_points", "closure_index", "shadow_contract_version",
                  "officially_valid",
                  "problems", "rms_ac", "raw_p2p", "system_inl_deg", "robust_p2p",
                  "closure_error_deg", "tracking_rms_deg", "tracking_max_abs_deg", "mean_dc",
                  "p99_abs_deviation"] + [f"A{o}" for o in HARMONIC_ORDERS]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in reports:
            row = {
                "motor_id": r.sweep.motor_id, "jig_id": r.sweep.jig_id,
                "test_id": r.sweep.test_id, "sweep_id": r.sweep.sweep_id,
                "run_order": r.sweep.run_order, "run_role": r.sweep.run_role,
                "eligible_for_statistics": r.sweep.eligible_for_statistics,
                "eligibility_source": r.sweep.eligibility_source,
                "analysis_points": r.sweep.analysis_point_count,
                "closure_index": r.sweep.closure_index,
                "shadow_contract_version": r.sweep.shadow_contract_version,
                "officially_valid": r.officially_valid,
                "problems": "; ".join(r.problems),
            }
            if r.metrics:
                row.update({
                    "rms_ac": r.metrics.rms_ac, "raw_p2p": r.metrics.raw_p2p,
                    "system_inl_deg": r.metrics.system_inl_deg, "robust_p2p": r.metrics.robust_p2p,
                    "closure_error_deg": r.metrics.closure_error_deg,
                    "tracking_rms_deg": r.metrics.tracking_rms_deg,
                    "tracking_max_abs_deg": r.metrics.tracking_max_abs_deg,
                    "mean_dc": r.metrics.mean_dc, "p99_abs_deviation": r.metrics.p99_abs_deviation,
                })
                for o in HARMONIC_ORDERS:
                    row[f"A{o}"] = r.metrics.harmonics[o].amplitude
            writer.writerow(row)


def write_json(reports: List[SweepReport], summaries: List[GroupSummary], path: Path) -> None:
    def metrics_to_dict(m: Optional[RecomputedMetrics]) -> Optional[dict]:
        if m is None:
            return None
        return {
            "analysis_count": m.analysis_count, "mean_dc": m.mean_dc, "rms_ac": m.rms_ac,
            "raw_p2p": m.raw_p2p, "system_inl_deg": m.system_inl_deg, "robust_p2p": m.robust_p2p,
            "p99_abs_deviation": m.p99_abs_deviation,
            "harmonics": {str(o): {"amplitude": h.amplitude, "phase_deg": h.phase_deg}
                          for o, h in m.harmonics.items()},
            "closure_error_deg": m.closure_error_deg, "closure_available": m.closure_available,
            "tracking_rms_deg": m.tracking_rms_deg, "tracking_max_abs_deg": m.tracking_max_abs_deg,
            "missing_indices": m.missing_indices,
        }

    payload = {
        "sweeps": [
            {
                "motor_id": r.sweep.motor_id, "jig_id": r.sweep.jig_id,
                "test_id": r.sweep.test_id, "sweep_id": r.sweep.sweep_id,
                "run_order": r.sweep.run_order,
                "run_role": r.sweep.run_role,
                "eligible_for_statistics": r.sweep.eligible_for_statistics,
                "eligibility_source": r.sweep.eligibility_source,
                "analysis_points": r.sweep.analysis_point_count,
                "closure_index": r.sweep.closure_index,
                "shadow_contract_version": r.sweep.shadow_contract_version,
                "officially_valid": r.officially_valid,
                "problems": r.problems, "metrics": metrics_to_dict(r.metrics),
                "source_file": r.sweep.source_file,
            }
            for r in reports
        ],
        "group_summaries": [
            {
                "motor_id": s.motor_id, "jig_id": s.jig_id,
                "run_count": s.run_count, "conditioned_run_count": s.conditioned_run_count,
                "fields": s.fields, "invalid_runs": s.invalid_runs,
            }
            for s in summaries
        ],
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


# ---------------------------------------------------------------------------
# Self-test: reproduces NlSelfTestCase1/Case2 from nonlinear_test.c so the
# Python DFT math is proven to match the firmware's, independent of any
# real log file.
# ---------------------------------------------------------------------------

def _self_test_case(name: str, x_fn, expected: Dict[str, float],
                    analysis_points: int,
                    step_raw: Optional[int] = None,
                    tol: float = 0.01) -> bool:
    n = analysis_points
    errors = []
    for i in range(n):
        theta_deg = analysis_angle_deg(i, analysis_points, step_raw)
        errors.append(x_fn(theta_deg))
    mean = sum(errors) / n
    rms_ac = math.sqrt(sum((e - mean) ** 2 for e in errors) / n)
    ok = True

    def check(label: str, actual: float, exp: float) -> None:
        nonlocal ok
        passed = abs(actual - exp) <= tol
        ok = ok and passed
        status = "OK" if passed else "FAIL"
        print(f"    [{status}] {label}: actual={actual:.4f} expected={exp:.4f} tol={tol}")

    check("mean", mean, expected["mean"])
    check("rms_ac", rms_ac, expected["rms_ac"])
    for order, exp_amp in expected.get("amplitudes", {}).items():
        h = compute_harmonic(errors, mean, order, analysis_points, step_raw)
        check(f"A{order}", h.amplitude, exp_amp)

    print(f"  Case '{name}': {'PASS' if ok else 'FAIL'}")
    return ok


def run_self_test() -> bool:
    print("Self-test: reproducing NlSelfTestCase1/Case2 from nonlinear_test.c")
    print("(synthetic curves with known closed-form DFT coefficients)\n")

    case1_ok = _self_test_case(
        "Legacy 256: x=1.5+2.0*cos(6*theta+30deg)",
        lambda theta_deg: 1.5 + 2.0 * math.cos(math.radians(6 * theta_deg + 30.0)),
        expected={"mean": 1.5000, "rms_ac": 1.4142, "amplitudes": {6: 2.0000, 1: 0.0, 2: 0.0}},
        analysis_points=LEGACY_ANALYSIS_POINT_COUNT,
        step_raw=LEGACY_STEP_RAW,
    )
    case2_ok = _self_test_case(
        "Current 360: x=0.4+1.2*cos(6*theta)+0.3*cos(12*theta)-0.2*sin(3*theta)",
        lambda theta_deg: (0.4 + 1.2 * math.cos(math.radians(6 * theta_deg))
                            + 0.3 * math.cos(math.radians(12 * theta_deg))
                            - 0.2 * math.sin(math.radians(3 * theta_deg))),
        expected={"mean": 0.4000, "rms_ac": math.sqrt(0.5 * (1.2 ** 2 + 0.3 ** 2 + 0.2 ** 2)),
                  "amplitudes": {3: 0.2000, 6: 1.2000, 12: 0.3000, 1: 0.0}},
        analysis_points=CURRENT_ANALYSIS_POINT_COUNT,
        step_raw=0,
    )

    # Regression for the historical silent failure: a 360-point record must
    # use all points 0..359 and point 360 as closure, never point 256.
    dynamic = Sweep(
        test_id=1, sweep_id=1, jig_id="JIG_TEST", motor_id="P_TEST",
        run_order=1, run_role="OFFICIAL", eligible_for_statistics=True,
        step_raw=0, analysis_points=CURRENT_ANALYSIS_POINT_COUNT,
        meta_measurement_valid=True, end_status="VALID",
    )
    for i in range(CURRENT_ANALYSIS_POINT_COUNT + 1):
        dynamic.points[i] = DataPoint(
            index=i,
            target_raw_abs=round(i * FULL_TURN_RAW / CURRENT_ANALYSIS_POINT_COUNT) % 65536,
            angle_raw=round(i * FULL_TURN_RAW / CURRENT_ANALYSIS_POINT_COUNT) % 65536,
            angle_deg=float(i),
            error_deg=-5.0 if i == LEGACY_ANALYSIS_POINT_COUNT else 0.0,
        )
    dynamic.points[CURRENT_ANALYSIS_POINT_COUNT].error_deg = -0.09
    dynamic_metrics = recompute_metrics(dynamic)
    dynamic_ok = (
        dynamic_metrics is not None
        and dynamic_metrics.analysis_count == CURRENT_ANALYSIS_POINT_COUNT
        and not dynamic_metrics.missing_indices
        and dynamic_metrics.closure_available
        and abs((dynamic_metrics.closure_error_deg or 0.0) - (-0.09)) < 1e-12
    )
    print(f"  Case 'Dynamic AnalysisPoints/closure': "
          f"{'PASS' if dynamic_ok else 'FAIL'}")

    precondition = Sweep(
        test_id=2, sweep_id=1, jig_id="JIG_TEST", motor_id="P_TEST",
        run_order=0, run_role="PRECONDITION", eligible_for_statistics=False,
        meta_measurement_valid=True, end_status="VALID",
    )
    role_ok = dynamic.is_official_valid and not precondition.is_official_valid
    print(f"  Case 'RunRole/EligibleForStatistics': "
          f"{'PASS' if role_ok else 'FAIL'}")

    # Schema-v6 extends DATA with canonical Q16 values. Deliberately put a
    # wrong compatibility ErrorDeg in the positional column and verify the
    # parser uses ErrorRawQ16 as the official source of truth.
    one_raw_q16 = Q16_SCALE
    schema6_line = (
        "DATA,6,9,10,JIG8,p03,CW,1,182,182,0.99976,99.00000,"
        f"CommandRawQ16={182 * Q16_SCALE},MeanUnwrappedRawQ16={181 * Q16_SCALE},"
        f"ErrorRawQ16={one_raw_q16}"
    )
    schema6_parsed = parse_data_line(schema6_line)
    schema6_expected_deg = 360.0 / FULL_TURN_RAW
    schema6_ok = (
        schema6_parsed is not None
        and schema6_parsed[-1].error_raw_q16 == one_raw_q16
        and abs(schema6_parsed[-1].error_deg - schema6_expected_deg) < 1e-12
    )
    print(f"  Case 'Schema-v6 canonical DATA/Q16': "
          f"{'PASS' if schema6_ok else 'FAIL'}")

    # P2P shift-invariance identity used in docs/cross_jig_measurement_analysis.md
    # section 8: P2P(e - c) == P2P(e) for any constant c.
    sample = [-3.0, -2.0, -0.5, 1.0, 2.5]
    shifted = [e - 7.25 for e in sample]
    p2p_a = max(sample) - min(sample)
    p2p_b = max(shifted) - min(shifted)
    shift_ok = abs(p2p_a - p2p_b) < 1e-9
    print(f"  Case 'P2P shift-invariance': {'PASS' if shift_ok else 'FAIL'} "
          f"(P2P(e)={p2p_a:.4f}, P2P(e-c)={p2p_b:.4f})")

    all_ok = case1_ok and case2_ok and dynamic_ok and role_ok and schema6_ok and shift_ok
    print(f"\nSelf-test overall: {'PASS' if all_ok else 'FAIL'}")
    return all_ok


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logfiles", nargs="*", type=Path, help="Nonlinear sweep log file(s) to analyze")
    parser.add_argument("--csv", type=Path, help="Write per-sweep metrics to this CSV file")
    parser.add_argument("--json", type=Path, help="Write full report (sweeps + summaries) to this JSON file")
    parser.add_argument("--self-test", action="store_true",
                         help="Run the built-in DFT/statistics self-test and exit (no log files needed)")
    args = parser.parse_args(argv)

    if args.self_test:
        return 0 if run_self_test() else 1

    if not args.logfiles:
        parser.error("at least one LOGFILE is required unless --self-test is given")

    all_sweeps: List[Sweep] = []
    all_warnings: List[str] = []
    for path in args.logfiles:
        if not path.exists():
            all_warnings.append(f"{path}: file does not exist, skipped")
            continue
        sweeps, warnings = load_sweeps(path)
        all_sweeps.extend(sweeps)
        all_warnings.extend(warnings)

    if not all_sweeps:
        print("No sweeps parsed from any input file.", file=sys.stderr)
        for w in all_warnings:
            print(f"  WARN: {w}", file=sys.stderr)
        return 1

    reports = [build_report(sw) for sw in all_sweeps]
    infer_run_order(reports)
    # Validity never depends on inferred file position. Inference is only for
    # stable display keys on legacy records without META.RunOrder.

    by_group: Dict[Tuple[str, str], List[SweepReport]] = {}
    for r in reports:
        by_group.setdefault(group_key(r.sweep), []).append(r)
    summaries = [summarize_group(motor_id, jig_id, group_reports)
                 for (motor_id, jig_id), group_reports in sorted(by_group.items())]

    print_text_report(reports, summaries, all_warnings)

    if args.csv:
        write_csv(reports, args.csv)
        print(f"\nCSV written to {args.csv}")
    if args.json:
        write_json(reports, summaries, args.json)
        print(f"JSON written to {args.json}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
