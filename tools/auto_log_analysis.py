#!/usr/bin/env python3
"""Automatic UART batch capture and nonlinear-log analysis.

This module is deliberately independent from Tkinter so the serial framing,
file boundaries, and analysis contract can be unit-tested without hardware.
The GUI feeds arbitrary UART byte chunks into :class:`BatchLogRecorder`.
Completed captures are saved as plain UTF-8 text and analyzed directly with
``analyze_motor_logs``; no external Python process is required by the EXE.
"""

from __future__ import annotations

import codecs
import csv
import io
import math
import re
import statistics
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import analyze_motor_logs as motor_analyzer


TERMINAL_BATCH_STATUSES = frozenset({"COMPLETE", "FAILED", "ABORTED"})
MAX_PREAMBLE_LINES = 1000


def parse_kv_record(line: str) -> tuple[str, Dict[str, str]]:
    """Parse a firmware CSV record without interpreting positional DATA rows."""
    parts = [part.strip() for part in line.strip().split(",")]
    if not parts:
        return "", {}
    fields: Dict[str, str] = {}
    for token in parts[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key.strip()] = value.strip()
    return parts[0], fields


def _safe_int(value: Optional[str]) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def _safe_name(value: Optional[str], fallback: str) -> str:
    candidate = (value or fallback).strip() or fallback
    candidate = re.sub(r"[^A-Za-z0-9._-]+", "-", candidate)
    return candidate.strip("-._") or fallback


def _safe_requested_stem(value: str, fallback: str) -> str:
    """Return a Windows-safe leaf stem while preserving readable Unicode."""
    candidate = Path(value.strip()).name
    if candidate.lower().endswith(".txt"):
        candidate = candidate[:-4]
    candidate = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "-", candidate)
    candidate = candidate.rstrip(" .")
    if not candidate:
        return fallback
    reserved = {"CON", "PRN", "AUX", "NUL"}
    reserved.update(f"COM{index}" for index in range(1, 10))
    reserved.update(f"LPT{index}" for index in range(1, 10))
    if candidate.split(".", 1)[0].upper() in reserved:
        candidate = "_" + candidate
    return candidate


@dataclass(frozen=True)
class CompletedCapture:
    text: str
    started_at: datetime
    completed_at: datetime
    terminal_status: str
    batch_id: Optional[int]
    expected_official_runs: Optional[int]
    motor_id: str
    jig_id: str
    build_id: str
    implicit_start: bool = False


@dataclass(frozen=True)
class AnalysisOutcome:
    passed: bool
    capture_integrity_valid: bool
    summary: str
    log_path: Path
    csv_path: Path
    json_path: Path
    report_path: Path
    official_valid: int
    official_expected: Optional[int]
    response_csv_path: Optional[Path]
    response_timing_rows: int


@dataclass(frozen=True)
class MotorResponseTimingAnalysis:
    rows: List[Dict[str, object]]
    report_lines: List[str]
    summary_fragment: Optional[str]
    complete: bool


class BatchLogRecorder:
    """Turn arbitrary UART chunks into one capture per firmware batch.

    Normal operation starts on ``BATCH,Status=START`` and finishes on a
    terminal BATCH status. If the monitor is opened after START was emitted,
    a META record creates an implicit capture which still finishes on the
    later BATCH terminal record. Legacy non-batch sweeps finish at END.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self.reset_session()

    def reset_session(self) -> None:
        with self._lock:
            self._decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
            self._pending_text = ""
            self._idle_lines: List[str] = []
            self._active_lines: Optional[List[str]] = None
            self._started_at: Optional[datetime] = None
            self._batch_id: Optional[int] = None
            self._expected_runs: Optional[int] = None
            self._motor_id = "UNKNOWN_MOTOR"
            self._jig_id = "UNKNOWN_JIG"
            self._build_id = "UNKNOWN_BUILD"
            self._implicit_start = False
            self._declared_role_seen = False

    @property
    def capture_active(self) -> bool:
        return self._active_lines is not None

    def feed(self, data: bytes) -> List[CompletedCapture]:
        if not data:
            return []
        with self._lock:
            self._pending_text += self._decoder.decode(data, final=False)
            completed: List[CompletedCapture] = []
            while "\n" in self._pending_text:
                raw_line, self._pending_text = self._pending_text.split("\n", 1)
                completed.extend(self._process_line(raw_line.rstrip("\r")))
            return completed

    def flush_incomplete(self) -> List[CompletedCapture]:
        """Flush a partial UART line and preserve an interrupted active batch."""
        with self._lock:
            completed: List[CompletedCapture] = []
            self._pending_text += self._decoder.decode(b"", final=True)
            if self._pending_text:
                completed.extend(self._process_line(self._pending_text.rstrip("\r")))
                self._pending_text = ""
            if self.capture_active:
                completed.append(self._finalize("INCOMPLETE"))
            return completed

    def _remember_idle(self, line: str) -> None:
        self._idle_lines.append(line)
        if len(self._idle_lines) > MAX_PREAMBLE_LINES:
            del self._idle_lines[: len(self._idle_lines) - MAX_PREAMBLE_LINES]

    def _start_capture(self, line: str, implicit: bool) -> None:
        self._active_lines = [*self._idle_lines, line]
        self._idle_lines = []
        self._started_at = datetime.now()
        self._batch_id = None
        self._expected_runs = None
        self._motor_id = "UNKNOWN_MOTOR"
        self._jig_id = "UNKNOWN_JIG"
        self._build_id = "UNKNOWN_BUILD"
        self._implicit_start = implicit
        self._declared_role_seen = False
        self._update_identity(line)

    def _update_identity(self, line: str) -> None:
        record, fields = parse_kv_record(line)
        if record == "BATCH":
            batch_id = _safe_int(fields.get("BatchID"))
            expected_runs = _safe_int(fields.get("RunCount"))
            if batch_id is not None:
                self._batch_id = batch_id
            if expected_runs is not None:
                self._expected_runs = expected_runs
        if record in {"CONFIG", "META"}:
            if fields.get("JigID"):
                self._jig_id = fields["JigID"]
            if fields.get("BuildID"):
                self._build_id = fields["BuildID"]
        if record == "META":
            if fields.get("MotorID"):
                self._motor_id = fields["MotorID"]
            if "RunRole" in fields or "EligibleForStatistics" in fields:
                self._declared_role_seen = True

    def _process_line(self, line: str) -> List[CompletedCapture]:
        completed: List[CompletedCapture] = []
        record, fields = parse_kv_record(line)
        status = fields.get("Status", "").upper() if record == "BATCH" else ""

        if record == "BATCH" and status == "START":
            if self.capture_active:
                completed.append(self._finalize("INCOMPLETE"))
            self._start_capture(line, implicit=False)
            return completed

        if not self.capture_active and record == "META":
            # The monitor may have been connected after BATCH START. Keep the
            # sweep instead of silently losing the entire test.
            self._start_capture(line, implicit=True)
        elif self.capture_active:
            assert self._active_lines is not None
            self._active_lines.append(line)
            self._update_identity(line)
        else:
            self._remember_idle(line)

        if record == "BATCH" and status in TERMINAL_BATCH_STATUSES:
            if not self.capture_active:
                # The terminal line was just retained as idle preamble above.
                # Remove it before starting so it appears exactly once.
                if self._idle_lines and self._idle_lines[-1] == line:
                    self._idle_lines.pop()
                self._start_capture(line, implicit=True)
            completed.append(self._finalize(status))
        elif record == "END" and self.capture_active and self._implicit_start:
            # Legacy logs have no batch role. New batch logs must wait for the
            # BATCH terminal record because END appears after every sweep.
            if not self._declared_role_seen:
                completed.append(self._finalize(fields.get("Status", "END")))
        return completed

    def _finalize(self, status: str) -> CompletedCapture:
        lines = self._active_lines or []
        capture = CompletedCapture(
            text="\n".join(lines).rstrip("\n") + "\n",
            started_at=self._started_at or datetime.now(),
            completed_at=datetime.now(),
            terminal_status=status,
            batch_id=self._batch_id,
            expected_official_runs=self._expected_runs,
            motor_id=self._motor_id,
            jig_id=self._jig_id,
            build_id=self._build_id,
            implicit_start=self._implicit_start,
        )
        self._active_lines = None
        self._started_at = None
        self._batch_id = None
        self._expected_runs = None
        self._motor_id = "UNKNOWN_MOTOR"
        self._jig_id = "UNKNOWN_JIG"
        self._build_id = "UNKNOWN_BUILD"
        self._implicit_start = False
        self._declared_role_seen = False
        self._idle_lines = []
        return capture


def suggested_capture_filename(capture: CompletedCapture) -> str:
    """Build the editable default filename shown to the operator."""
    stamp = capture.started_at.strftime("%Y%m%d-%H%M%S")
    motor = _safe_name(capture.motor_id, "UNKNOWN_MOTOR")
    jig = _safe_name(capture.jig_id, "UNKNOWN_JIG")
    batch = f"batch{capture.batch_id:03d}" if capture.batch_id is not None else "batchNA"
    status = _safe_name(capture.terminal_status.lower(), "unknown")
    return f"{stamp}_{motor}_{jig}_{batch}_{status}.txt"


def save_capture(
    capture: CompletedCapture,
    output_dir: Path,
    requested_filename: Optional[str] = None,
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    suggested_name = suggested_capture_filename(capture)
    fallback_stem = Path(suggested_name).stem
    base = _safe_requested_stem(requested_filename or suggested_name, fallback_stem)
    path = output_dir / f"{base}.txt"
    suffix = 2
    while path.exists():
        path = output_dir / f"{base}_{suffix:02d}.txt"
        suffix += 1
    path.write_text(capture.text, encoding="utf-8", newline="\n")
    return path


def _configuration_health(log_path: Path) -> tuple[int, int, int]:
    gated_total = 0
    gated_invalid = 0
    boot_invalid = 0
    for raw_line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        record, fields = parse_kv_record(raw_line)
        if record != "CONFIG":
            continue
        invalid = fields.get("ConfigValid") == "0" or fields.get("PolicyAGatePassed") == "0"
        if fields.get("ConfigContext") == "BOOT_SMOKE":
            boot_invalid += int(invalid)
        else:
            gated_total += 1
            gated_invalid += int(invalid)
    return gated_total, gated_invalid, boot_invalid


def _safe_float(value: Optional[str]) -> Optional[float]:
    if value is None or value.strip().upper() == "NA":
        return None
    try:
        parsed = float(value)
    except ValueError:
        return None
    return parsed if math.isfinite(parsed) else None


def _cycles_to_ms(cycles: Optional[int], clock_hz: Optional[int]) -> Optional[float]:
    if cycles is None or clock_hz is None or clock_hz <= 0:
        return None
    return 1000.0 * cycles / clock_hz


def _percentile(values: List[float], percentile: float) -> Optional[float]:
    clean = sorted(value for value in values if math.isfinite(value))
    if not clean:
        return None
    if len(clean) == 1:
        return clean[0]
    position = (len(clean) - 1) * percentile
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return clean[lower]
    weight = position - lower
    return clean[lower] * (1.0 - weight) + clean[upper] * weight


def _format_timing_stats(label: str, values: List[float]) -> Optional[str]:
    clean = [value for value in values if math.isfinite(value)]
    if not clean:
        return None
    p95 = _percentile(clean, 0.95)
    return (
        f"{label}: n={len(clean)},mean={statistics.fmean(clean):.3f}ms,"
        f"median={statistics.median(clean):.3f}ms,p95={p95:.3f}ms,"
        f"max={max(clean):.3f}ms"
    )


def analyze_motor_response_timing(log_text: str) -> MotorResponseTimingAnalysis:
    """Parse V5.8 point timing and derive command/response metrics.

    The calculation deliberately keeps a stopped-outside-deadband point out of
    TimeToDeadband statistics. Such a point has a valid stop latency, but it
    never reached the requested position during the measured command budget.
    """
    timing_records: List[Dict[str, str]] = []
    end_records: Dict[tuple[int, int], Dict[str, str]] = {}
    for line in log_text.splitlines():
        record, fields = parse_kv_record(line)
        if record == "SWEEP_POINT_TIMING":
            timing_records.append(fields)
        elif record == "SWEEP_POINT_TIMING_END":
            test_id = _safe_int(fields.get("TestID"))
            sweep_id = _safe_int(fields.get("SweepID"))
            if test_id is not None and sweep_id is not None:
                end_records[(test_id, sweep_id)] = fields

    if not timing_records:
        return MotorResponseTimingAnalysis([], [], None, False)

    rows: List[Dict[str, object]] = []
    for fields in timing_records:
        clock_hz = _safe_int(fields.get("ClockHz"))
        test_id = _safe_int(fields.get("TestID"))
        sweep_id = _safe_int(fields.get("SweepID"))
        point = _safe_int(fields.get("Point"))
        has_command = _safe_int(fields.get("HasCommand")) == 1
        timing_valid = _safe_int(fields.get("TimingValid")) == 1
        reached = _safe_int(fields.get("ReachedDeadband")) == 1

        nominal_target = _safe_int(fields.get("NominalTargetRaw"))
        nominal_step = _safe_int(fields.get("NominalStepCommandRaw"))
        initial_gap = _safe_int(fields.get("InitialGapRaw"))
        final_gap = _safe_int(fields.get("FinalGapRaw"))
        correction_command = _safe_int(fields.get("CreepCorrectionCommandRaw"))
        creep_iterations = _safe_int(fields.get("CreepIterations"))
        settle_polls = _safe_int(fields.get("SettlePollCount"))

        cycle_names = {
            "RampMs": "RampCycles",
            "InitialSettleMs": "InitialSettleCycles",
            "CreepMs": "CreepCycles",
            "CommandToStopMs": "CommandToStopCycles",
            "TimeToDeadbandMs": "TimeToDeadbandCycles",
            "LegacyCaptureMs": "LegacyCaptureCycles",
            "ShadowCaptureMs": "ShadowCaptureCycles",
            "CommandToDataFrozenMs": "CommandToDataFrozenCycles",
            "CommandToAllCaptureDoneMs": "CommandToAllCaptureDoneCycles",
        }
        durations = {
            output_name: _cycles_to_ms(_safe_int(fields.get(input_name)), clock_hz)
            for output_name, input_name in cycle_names.items()
        }

        observed_toward = None
        creep_efficiency = None
        response_per_second = None
        if initial_gap is not None and final_gap is not None:
            observed_toward = abs(initial_gap) - abs(final_gap)
            if correction_command is not None and correction_command > 0:
                creep_efficiency = 1000.0 * observed_toward / correction_command
            creep_ms = durations["CreepMs"]
            if creep_ms is not None and creep_ms > 0:
                response_per_second = 1000.0 * observed_toward / creep_ms

        row: Dict[str, object] = {
            "TestID": test_id,
            "SweepID": sweep_id,
            "JigID": fields.get("JigID", ""),
            "MotorID": fields.get("MotorID", ""),
            "Direction": fields.get("Direction", ""),
            "Point": point,
            "ClockHz": clock_hz,
            "HasCommand": int(has_command),
            "TimingValid": int(timing_valid),
            "ReachedDeadband": int(reached),
            "CreepResult": fields.get("CreepResult", ""),
            "NominalTargetRaw": nominal_target,
            "NominalStepCommandRaw": nominal_step,
            "InitialGapRaw": initial_gap,
            "FinalGapRaw": final_gap,
            "CreepIterations": creep_iterations,
            "CreepCorrectionCommandRaw": correction_command,
            "SettlePollCount": settle_polls,
            "ObservedTowardTargetRaw": observed_toward,
            "CreepResponseEfficiencyPermille": creep_efficiency,
            "ObservedTowardTargetRawPerSecond": response_per_second,
            **durations,
            "ActualPointDeltaRaw": None,
            "NominalStepTrackingPermille": None,
        }
        rows.append(row)

    # Overall point response is derived from consecutive final positions:
    # observed_position = nominal_target - signed_final_gap. Point 0 defines
    # the local origin, so its final position equals its nominal target.
    by_sweep: Dict[tuple[object, object], List[Dict[str, object]]] = {}
    for row in rows:
        by_sweep.setdefault((row["TestID"], row["SweepID"]), []).append(row)
    for sweep_rows in by_sweep.values():
        sweep_rows.sort(key=lambda row: int(row["Point"] or 0))
        previous_position: Optional[int] = None
        for row in sweep_rows:
            target = row["NominalTargetRaw"]
            final_gap = row["FinalGapRaw"]
            if not isinstance(target, int):
                previous_position = None
                continue
            position = target if not isinstance(final_gap, int) else target - final_gap
            nominal_step = row["NominalStepCommandRaw"]
            if previous_position is not None and isinstance(nominal_step, int) \
                    and nominal_step != 0:
                actual_delta = position - previous_position
                row["ActualPointDeltaRaw"] = actual_delta
                row["NominalStepTrackingPermille"] = 1000.0 * actual_delta / nominal_step
            previous_position = position

    command_rows = [row for row in rows if row["HasCommand"] == 1 and row["TimingValid"] == 1]
    reached_rows = [row for row in command_rows if row["ReachedDeadband"] == 1]
    failed_rows = [row for row in command_rows if row["ReachedDeadband"] == 0]
    report_lines = ["MOTOR RESPONSE TIMING (V5.8)"]

    all_complete = bool(end_records)
    for fields in end_records.values():
        all_complete = all_complete and _safe_int(fields.get("Complete")) == 1
        all_complete = all_complete and _safe_int(fields.get("ExpectedPoints")) \
            == _safe_int(fields.get("EmittedPoints"))
    observed_sweeps = {(row["TestID"], row["SweepID"]) for row in rows}
    all_complete = all_complete and observed_sweeps == set(end_records)
    reach_rate = 100.0 * len(reached_rows) / len(command_rows) if command_rows else 0.0
    report_lines.append(
        f"TimingRows={len(rows)},CommandPoints={len(command_rows)},"
        f"ReachedDeadband={len(reached_rows)},StoppedOutsideDeadband={len(failed_rows)},"
        f"ReachedRate={reach_rate:.2f}%,TelemetryComplete={int(all_complete)}"
    )

    stats_to_report = [
        ("CommandToStop", command_rows, "CommandToStopMs"),
        ("TimeToDeadband(reached-only)", reached_rows, "TimeToDeadbandMs"),
        ("StopLatency(not-reached)", failed_rows, "CommandToStopMs"),
        ("Ramp", command_rows, "RampMs"),
        ("InitialSettle", command_rows, "InitialSettleMs"),
        ("Creep", command_rows, "CreepMs"),
        ("Legacy64+anchor", rows, "LegacyCaptureMs"),
        ("Shadow64", rows, "ShadowCaptureMs"),
        ("CommandToDataFrozen", command_rows, "CommandToDataFrozenMs"),
    ]
    for label, selected_rows, field_name in stats_to_report:
        values = [row[field_name] for row in selected_rows if isinstance(row[field_name], float)]
        line = _format_timing_stats(label, values)
        if line:
            report_lines.append(line)

    creep_efficiency_values = [
        row["CreepResponseEfficiencyPermille"] for row in command_rows
        if isinstance(row["CreepResponseEfficiencyPermille"], float)
    ]
    tracking_values = [
        row["NominalStepTrackingPermille"] for row in command_rows
        if isinstance(row["NominalStepTrackingPermille"], float)
    ]
    if creep_efficiency_values:
        report_lines.append(
            "CreepResponseEfficiencyPermille: "
            f"mean={statistics.fmean(creep_efficiency_values):.1f},"
            f"median={statistics.median(creep_efficiency_values):.1f},"
            f"p05={_percentile(creep_efficiency_values, 0.05):.1f},"
            f"p95={_percentile(creep_efficiency_values, 0.95):.1f}"
        )
    if tracking_values:
        report_lines.append(
            "NominalStepTrackingPermille: "
            f"mean={statistics.fmean(tracking_values):.1f},"
            f"median={statistics.median(tracking_values):.1f},"
            f"p05={_percentile(tracking_values, 0.05):.1f},"
            f"p95={_percentile(tracking_values, 0.95):.1f}"
        )

    slowest = sorted(
        (row for row in command_rows if isinstance(row["CommandToStopMs"], float)),
        key=lambda row: float(row["CommandToStopMs"]), reverse=True,
    )[:10]
    if slowest:
        report_lines.append(
            "SlowestCommandPoints=" + "|".join(
                f"T{row['TestID']}/S{row['SweepID']}/P{row['Point']}:"
                f"{row['CommandToStopMs']:.3f}ms/{row['CreepResult']}"
                for row in slowest
            )
        )
    if failed_rows:
        report_lines.append(
            "NotReachedPoints=" + "|".join(
                f"T{row['TestID']}/S{row['SweepID']}/P{row['Point']}:"
                f"{row['CommandToStopMs']:.3f}ms/{row['CreepResult']}"
                for row in failed_rows[:20]
            )
        )

    summary_fragment = (
        f"Response={len(reached_rows)}/{len(command_rows)} "
        f"({reach_rate:.1f}%)"
    ) if command_rows else None
    return MotorResponseTimingAnalysis(rows, report_lines, summary_fragment, all_complete)


def write_motor_response_csv(analysis: MotorResponseTimingAnalysis, path: Path) -> None:
    if not analysis.rows:
        return
    fieldnames = list(analysis.rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(analysis.rows)


def analyze_saved_log(
    log_path: Path,
    expected_official_runs: Optional[int] = None,
    terminal_status: str = "COMPLETE",
) -> AnalysisOutcome:
    """Recompute metrics, write machine-readable artifacts, and return a GUI summary."""
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    decode_error_count = log_text.count("\ufffd")
    response_timing = analyze_motor_response_timing(log_text)
    sweeps, warnings = motor_analyzer.load_sweeps(log_path)
    reports = [motor_analyzer.build_report(sweep) for sweep in sweeps]
    motor_analyzer.infer_run_order(reports)

    by_group: Dict[tuple[str, str], List[motor_analyzer.SweepReport]] = {}
    for report in reports:
        by_group.setdefault(motor_analyzer.group_key(report.sweep), []).append(report)
    summaries = [
        motor_analyzer.summarize_group(motor_id, jig_id, group_reports)
        for (motor_id, jig_id), group_reports in sorted(by_group.items())
    ]

    csv_path = log_path.with_name(log_path.stem + ".metrics.csv")
    json_path = log_path.with_name(log_path.stem + ".analysis.json")
    report_path = log_path.with_name(log_path.stem + ".analysis.txt")
    response_csv_path: Optional[Path] = None
    motor_analyzer.write_csv(reports, csv_path)
    motor_analyzer.write_json(reports, summaries, json_path)
    if response_timing.rows:
        response_csv_path = log_path.with_name(log_path.stem + ".response.csv")
        write_motor_response_csv(response_timing, response_csv_path)

    gated_configs, invalid_configs, boot_invalid = _configuration_health(log_path)
    official_reports = [r for r in reports if r.sweep.run_role == "OFFICIAL"]
    if not official_reports:
        official_reports = [r for r in reports if not r.sweep.uses_declared_role_contract]
    valid_official = [r for r in official_reports if r.officially_valid]
    diagnostic_mode = bool(response_timing.rows)
    diagnostic_valid_official = [
        report for report in official_reports
        if report.sweep.meta_measurement_valid is True
        and report.sweep.end_status == "VALID"
    ]
    expected = expected_official_runs
    if expected is None and official_reports:
        expected = len(official_reports)

    expected_count_valid = expected is None or len(official_reports) == expected
    sweep_stream_complete = bool(reports) and all(
        report.sweep.has_meta
        and report.sweep.end_status is not None
        and report.metrics is not None
        and not report.metrics.missing_indices
        and report.metrics.closure_available
        for report in reports
    )
    capture_integrity_valid = (
        terminal_status.upper() == "COMPLETE"
        and decode_error_count == 0
        and expected_count_valid
        and sweep_stream_complete
        and (not response_timing.rows or response_timing.complete)
    )

    common_pass = (
        capture_integrity_valid
        and invalid_configs == 0
    )
    if diagnostic_mode:
        passed = (
            common_pass
            and len(diagnostic_valid_official) == len(official_reports)
            and (expected is None or len(diagnostic_valid_official) == expected)
            and response_timing.complete
        )
        verdict = "DIAGNOSTIC PASS" if passed else (
            "CAPTURE INVALID" if not capture_integrity_valid else "DIAGNOSTIC FAIL"
        )
    else:
        passed = (
            common_pass
            and len(valid_official) == len(official_reports)
            and (expected is None or len(valid_official) == expected)
        )
        verdict = "PASS" if passed else (
            "CAPTURE INVALID" if not capture_integrity_valid else "MEASUREMENT FAIL"
        )

    report_buffer = io.StringIO()
    report_buffer.write("AUTO-CAPTURE ANALYSIS\n")
    report_buffer.write(f"Source={log_path}\n")
    report_buffer.write(f"TerminalStatus={terminal_status}\n")
    report_buffer.write(
        f"AnalysisMode={'RESPONSE_TIMING_DIAGNOSTIC' if diagnostic_mode else 'OFFICIAL_MEASUREMENT'}\n"
    )
    report_buffer.write(
        f"OfficialValid={len(valid_official)}/{expected if expected is not None else 'NA'}\n"
    )
    report_buffer.write(
        f"GatedConfigInvalid={invalid_configs}/{gated_configs},BootSmokeInvalid={boot_invalid}\n"
    )
    report_buffer.write(
        f"CaptureIntegrityValid={int(capture_integrity_valid)},"
        f"DecodeErrors={decode_error_count},ExpectedOfficialCountValid={int(expected_count_valid)}\n"
    )
    report_buffer.write(f"AutoVerdict={verdict}\n\n")
    motor_analyzer.print_text_report(reports, summaries, warnings, out=report_buffer)
    if response_timing.report_lines:
        report_buffer.write("\n" + "\n".join(response_timing.report_lines) + "\n")
    report_path.write_text(report_buffer.getvalue(), encoding="utf-8", newline="\n")

    summary_count = len(diagnostic_valid_official) if diagnostic_mode else len(valid_official)
    summary_label = "OFFICIAL_MEASUREMENT" if diagnostic_mode else "OFFICIAL"
    summary_parts: List[str] = [
        verdict,
        f"{summary_label} {summary_count}/{expected if expected is not None else 'NA'}",
    ]
    if summaries:
        summary = summaries[0]
        nl = summary.fields.get("robust_p2p", {}).get("mean")
        nl_sd = summary.fields.get("robust_p2p", {}).get("sd")
        rms = summary.fields.get("rms_ac", {}).get("mean")
        closure_values = [
            abs(r.metrics.closure_error_deg)
            for r in valid_official
            if r.metrics is not None and r.metrics.closure_error_deg is not None
        ]
        summary_parts.insert(1, f"{summary.motor_id}/{summary.jig_id}")
        if nl is not None:
            summary_parts.append(f"NL={nl:.4f} deg")
        if nl_sd is not None:
            summary_parts.append(f"SD={nl_sd:.4f} deg")
        if rms is not None:
            summary_parts.append(f"RMS_AC={rms:.4f} deg")
        if closure_values:
            summary_parts.append(f"ClosureMax={max(closure_values):.4f} deg")
    if invalid_configs:
        summary_parts.append(f"CONFIG_INVALID={invalid_configs}")
    if warnings:
        summary_parts.append(f"WARN={len(warnings)}")
    if decode_error_count:
        summary_parts.append(f"UTF8_REPLACEMENT={decode_error_count}")
    if response_timing.summary_fragment:
        summary_parts.append(response_timing.summary_fragment)

    return AnalysisOutcome(
        passed=passed,
        capture_integrity_valid=capture_integrity_valid,
        summary=" | ".join(summary_parts),
        log_path=log_path,
        csv_path=csv_path,
        json_path=json_path,
        report_path=report_path,
        official_valid=len(valid_official),
        official_expected=expected,
        response_csv_path=response_csv_path,
        response_timing_rows=len(response_timing.rows),
    )
