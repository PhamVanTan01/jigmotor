#!/usr/bin/env python3
"""Analyze repeatability of the nonlinear (NL) result from jigmotor TXT logs.

The tool recomputes the core NL metrics from DATA rows instead of trusting the
rounded human-readable ``Nonlinear 1 Angle`` line.  PRECONDITION runs and any
invalid/incomplete sweep are excluded from official statistics by default.

Outputs:
  * nl_runs.csv                 one row per accepted sweep
  * nl_stability.csv            mean/SD/CV/range/repeatability by leg and pooled
  * nl_linear_fits.csv          NL-versus-metric linear regression diagnostics
  * nl_report.txt               concise text report
  * nl_trend.png                run-order stability and linear drift
  * nl_linear_relationships.png six proposed NL relationship plots
  * nl_error_curve.png          mean error shape for each input leg

Examples:
  python tools/analyze_nl_stability.py "P03 jig 1 test 20 A.txt" \
      "p03 jig 1 test 20 B.txt" "p03 jig 1 test 20 A 2.txt" \
      --labels A1 B A2 --out-dir analysis-out/test20-nl-stability

When run without log arguments from the project root, the three P03/JIG1/
test-20 logs are discovered automatically in A1 -> B -> A2 order.  This keeps
the common desktop invocation useful instead of failing with a missing-argument
message.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


FULL_TURN_RAW = 65536.0
ROBUST_EXTREME_COUNT = 5
DEFAULT_RELATION_METRICS = (
    "ShadowP2P_Deg",
    "RMS_AC_Deg",
    "A36_Deg",
    "ClosureErrorDeg",
    "ApproachReturnErrorDeg",
    "AnalysisStartRawCentered",
)


def parse_kv(line: str) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for token in line.rstrip("\r\n").split(",")[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def as_int(value: Optional[str]) -> Optional[int]:
    try:
        return int(value) if value is not None else None
    except ValueError:
        return None


def as_float(value: Optional[str]) -> Optional[float]:
    try:
        return float(value) if value is not None else None
    except ValueError:
        return None


@dataclass
class DataPoint:
    index: int
    target_raw: int
    angle_raw: int
    angle_deg: float
    error_deg: float


@dataclass
class Sweep:
    source: Path
    leg: str
    file_index: int
    test_id: int
    sweep_id: int
    meta: Dict[str, str] = field(default_factory=dict)
    result: Dict[str, str] = field(default_factory=dict)
    shadow: Dict[str, str] = field(default_factory=dict)
    approach: Dict[str, str] = field(default_factory=dict)
    end: Dict[str, str] = field(default_factory=dict)
    points: Dict[int, DataPoint] = field(default_factory=dict)
    firmware_nl_deg: Optional[float] = None

    @property
    def run_order(self) -> Optional[int]:
        return as_int(self.meta.get("RunOrder"))

    @property
    def run_role(self) -> str:
        return self.meta.get("RunRole", "OFFICIAL")

    @property
    def eligible(self) -> bool:
        return self.meta.get("EligibleForStatistics", "1") == "1"


@dataclass
class MetricRun:
    sweep: Sweep
    metrics: Dict[str, float]
    errors: List[float]


@dataclass
class Fit:
    n: int
    slope: float
    intercept: float
    r: float
    r2: float
    residual_sd: float
    slope_se: float
    slope_ci95_low: float
    slope_ci95_high: float


def parse_data(line: str) -> Optional[Tuple[int, int, DataPoint]]:
    parts = line.rstrip("\r\n").split(",")
    if len(parts) != 12 or parts[0] != "DATA":
        return None
    try:
        test_id = int(parts[2])
        sweep_id = int(parts[3])
        point = DataPoint(
            index=int(parts[7]),
            target_raw=int(parts[8]),
            angle_raw=int(parts[9]),
            angle_deg=float(parts[10]),
            error_deg=float(parts[11]),
        )
    except ValueError:
        return None
    return test_id, sweep_id, point


def load_sweeps(path: Path, leg: str, file_index: int) -> Tuple[List[Sweep], List[str]]:
    sweeps: Dict[Tuple[int, int], Sweep] = {}
    warnings: List[str] = []
    active_key: Optional[Tuple[int, int]] = None
    nl_pattern = re.compile(r"^Nonlinear\s+\d+\s+Angle:\s*(-?\d+(?:\.\d+)?)\s+degree")

    with path.open(encoding="utf-8", errors="replace") as stream:
        for line_no, raw in enumerate(stream, start=1):
            line = raw.strip()
            if not line:
                continue
            if line.startswith("META,"):
                fields = parse_kv(line)
                test_id = as_int(fields.get("TestID"))
                sweep_id = as_int(fields.get("SweepID"))
                if test_id is None or sweep_id is None:
                    warnings.append(f"{path.name}:{line_no}: META lacks TestID/SweepID")
                    continue
                active_key = (test_id, sweep_id)
                sweep = sweeps.setdefault(
                    active_key, Sweep(path, leg, file_index, test_id, sweep_id)
                )
                sweep.meta = fields
                continue

            if line.startswith("DATA,"):
                parsed = parse_data(line)
                if parsed is None:
                    warnings.append(f"{path.name}:{line_no}: malformed DATA row")
                    continue
                test_id, sweep_id, point = parsed
                key = (test_id, sweep_id)
                active_key = key
                sweep = sweeps.setdefault(key, Sweep(path, leg, file_index, test_id, sweep_id))
                if point.index in sweep.points:
                    warnings.append(
                        f"{path.name}:{line_no}: duplicate DATA index {point.index} "
                        f"for TestID={test_id}/SweepID={sweep_id}"
                    )
                else:
                    sweep.points[point.index] = point
                continue

            record_name = line.split(",", 1)[0]
            if record_name in {"RESULT", "SHADOW_RESULT", "APPROACH_RESULT", "END"}:
                fields = parse_kv(line)
                test_id = as_int(fields.get("TestID"))
                sweep_id = as_int(fields.get("SweepID"))
                key = ((test_id, sweep_id) if test_id is not None and sweep_id is not None
                       else active_key)
                if key is None:
                    warnings.append(f"{path.name}:{line_no}: orphan {record_name}")
                    continue
                sweep = sweeps.setdefault(key, Sweep(path, leg, file_index, key[0], key[1]))
                if record_name == "RESULT":
                    sweep.result = fields
                elif record_name == "SHADOW_RESULT":
                    sweep.shadow = fields
                elif record_name == "APPROACH_RESULT":
                    sweep.approach = fields
                else:
                    sweep.end = fields
                active_key = key
                continue

            match = nl_pattern.match(line)
            if match and active_key is not None:
                sweeps[active_key].firmware_nl_deg = float(match.group(1))

    ordered = sorted(
        sweeps.values(),
        key=lambda sw: (
            sw.run_order if sw.run_order is not None else 10**9,
            sw.test_id,
            sw.sweep_id,
        ),
    )
    return ordered, warnings


def dft_amplitude(errors: Sequence[float], order: int) -> float:
    n = len(errors)
    if n == 0:
        return float("nan")
    mean = statistics.fmean(errors)
    a = 0.0
    b = 0.0
    for index, value in enumerate(errors):
        phase = 2.0 * math.pi * order * index / n
        centered = value - mean
        a += centered * math.cos(phase)
        b += centered * math.sin(phase)
    return math.hypot(2.0 * a / n, 2.0 * b / n)


def validate_and_compute(sweep: Sweep, include_precondition: bool) -> Tuple[Optional[MetricRun], List[str]]:
    reasons: List[str] = []
    analysis_points = as_int(sweep.meta.get("AnalysisPoints"))
    if analysis_points is None or analysis_points <= 0:
        reasons.append("missing/invalid META.AnalysisPoints")
        return None, reasons
    if not include_precondition and not sweep.eligible:
        reasons.append("precondition excluded")
        return None, reasons
    if sweep.meta.get("MeasurementValid") != "1":
        reasons.append("META.MeasurementValid != 1")
    if sweep.end.get("Status") != "VALID":
        reasons.append("END.Status != VALID")
    missing = [index for index in range(analysis_points) if index not in sweep.points]
    if missing:
        reasons.append(f"missing {len(missing)}/{analysis_points} analysis DATA rows")
    if reasons:
        return None, reasons

    errors = [sweep.points[index].error_deg for index in range(analysis_points)]
    mean_dc = statistics.fmean(errors)
    rms_ac = math.sqrt(statistics.fmean((value - mean_dc) ** 2 for value in errors))
    sorted_errors = sorted(errors)
    k = min(ROBUST_EXTREME_COUNT, len(sorted_errors))
    robust_p2p = statistics.fmean(sorted_errors[-k:]) - statistics.fmean(sorted_errors[:k])
    raw_p2p = sorted_errors[-1] - sorted_errors[0]

    shadow_p2p = as_float(sweep.shadow.get("P2P"))
    closure = as_float(sweep.shadow.get("ClosureErrorDeg"))
    return_error_raw = as_float(sweep.approach.get("ApproachReturnErrorRaw"))
    analysis_start_raw = as_float(sweep.meta.get("AnalysisStartRaw"))
    firmware_rms = as_float(sweep.shadow.get("RMS_AC"))
    firmware_a36 = as_float(sweep.shadow.get("A36"))

    metrics: Dict[str, float] = {
        "NL_RobustP2P_Deg": robust_p2p,
        "RMS_AC_Deg": rms_ac,
        "A36_Deg": dft_amplitude(errors, 36),
        "RawP2P_Deg": raw_p2p,
        "SystemINL_Deg": raw_p2p / 2.0,
        "MeanDC_Deg": mean_dc,
    }
    optional = {
        "ShadowP2P_Deg": shadow_p2p,
        "ClosureErrorDeg": closure,
        "ApproachReturnErrorRaw": return_error_raw,
        "ApproachReturnErrorDeg": (
            return_error_raw * 360.0 / FULL_TURN_RAW
            if return_error_raw is not None else None
        ),
        "AnalysisStartRaw": analysis_start_raw,
        "FirmwareNL_Deg": sweep.firmware_nl_deg,
        "FirmwareShadowRMS_AC_Deg": firmware_rms,
        "FirmwareShadowA36_Deg": firmware_a36,
    }
    for name, value in optional.items():
        if value is not None:
            metrics[name] = value
    if sweep.firmware_nl_deg is not None:
        metrics["NL_MinusFirmwareRounded_Deg"] = robust_p2p - sweep.firmware_nl_deg
    if firmware_rms is not None:
        metrics["RMS_RecomputeDelta_Deg"] = rms_ac - firmware_rms
    if firmware_a36 is not None:
        metrics["A36_RecomputeDelta_Deg"] = metrics["A36_Deg"] - firmware_a36
    return MetricRun(sweep=sweep, metrics=metrics, errors=errors), reasons


def t_critical_975(df: int) -> float:
    # Two-sided 95% Student-t critical values.  df>=30 is close enough to the
    # asymptotic normal value for this diagnostic tool.
    table = {
        1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571,
        6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228,
        11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145, 15: 2.131,
        16: 2.120, 17: 2.110, 18: 2.101, 19: 2.093, 20: 2.086,
        21: 2.080, 22: 2.074, 23: 2.069, 24: 2.064, 25: 2.060,
        26: 2.056, 27: 2.052, 28: 2.048, 29: 2.045, 30: 2.042,
    }
    return table.get(max(1, min(df, 30)), 1.960 if df > 30 else 12.706)


def linear_fit(x: Sequence[float], y: Sequence[float]) -> Optional[Fit]:
    n = len(x)
    if n != len(y) or n < 2:
        return None
    mean_x = statistics.fmean(x)
    mean_y = statistics.fmean(y)
    sxx = sum((value - mean_x) ** 2 for value in x)
    syy = sum((value - mean_y) ** 2 for value in y)
    sxy = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    if sxx <= 0.0:
        return None
    slope = sxy / sxx
    intercept = mean_y - slope * mean_x
    residuals = [yi - (slope * xi + intercept) for xi, yi in zip(x, y)]
    ss_res = sum(value * value for value in residuals)
    r = sxy / math.sqrt(sxx * syy) if syy > 0.0 else 0.0
    r2 = 1.0 - ss_res / syy if syy > 0.0 else 1.0
    residual_sd = math.sqrt(ss_res / (n - 2)) if n > 2 else 0.0
    slope_se = residual_sd / math.sqrt(sxx) if n > 2 else 0.0
    margin = t_critical_975(n - 2) * slope_se if n > 2 else 0.0
    return Fit(
        n=n,
        slope=slope,
        intercept=intercept,
        r=r,
        r2=r2,
        residual_sd=residual_sd,
        slope_se=slope_se,
        slope_ci95_low=slope - margin,
        slope_ci95_high=slope + margin,
    )


def describe(values: Sequence[float]) -> Dict[str, float]:
    mean = statistics.fmean(values)
    sd = statistics.stdev(values) if len(values) >= 2 else 0.0
    median = statistics.median(values)
    mad = statistics.median(abs(value - median) for value in values)
    minimum = min(values)
    maximum = max(values)
    return {
        "n": float(len(values)),
        "mean": mean,
        "sample_sd": sd,
        "cv_pct": 100.0 * sd / abs(mean) if mean != 0.0 else float("nan"),
        "median": median,
        "mad": mad,
        "robust_sigma": 1.4826 * mad,
        "min": minimum,
        "max": maximum,
        "range": maximum - minimum,
        # ISO 5725-style repeatability limit convention for the expected
        # absolute difference between two results at roughly 95% probability.
        "repeatability_limit_2_77sd": 2.77 * sd,
    }


def csv_write(path: Path, fieldnames: Sequence[str], rows: Iterable[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def infer_default_logs(cwd: Path) -> List[Path]:
    matches = [
        path for path in cwd.glob("*.txt")
        if re.search(r"p03\s+jig\s*1\s+test\s*20", path.name, re.IGNORECASE)
    ]

    def order(path: Path) -> Tuple[int, str]:
        name = path.stem.casefold()
        if re.search(r"test\s*20\s+a\s*2$", name):
            rank = 2
        elif re.search(r"test\s*20\s+b$", name):
            rank = 1
        elif re.search(r"test\s*20\s+a$", name):
            rank = 0
        else:
            rank = 3
        return rank, name

    return sorted(matches, key=order)


def infer_leg(path: Path, index: int) -> str:
    name = path.stem
    if re.search(r"test\s*20\s+a\s*2$", name, re.IGNORECASE):
        return "A2"
    if re.search(r"test\s*20\s+b$", name, re.IGNORECASE):
        return "B"
    if re.search(r"test\s*20\s+a$", name, re.IGNORECASE):
        return "A1"
    return f"L{index + 1}"


def make_run_rows(runs: Sequence[MetricRun]) -> Tuple[List[str], List[Dict[str, object]]]:
    metric_names = sorted(set().union(*(run.metrics.keys() for run in runs)))
    fields = [
        "SequentialRun", "Leg", "SourceFile", "TestID", "SweepID", "RunOrder",
        "RunRole", "EligibleForStatistics", "BuildID", "ApproachProtocol",
        "PreconditionProtocol",
    ] + metric_names
    rows: List[Dict[str, object]] = []
    start_values = [run.metrics["AnalysisStartRaw"] for run in runs
                    if "AnalysisStartRaw" in run.metrics]
    start_mean = statistics.fmean(start_values) if start_values else 0.0
    for sequential, run in enumerate(runs, start=1):
        if "AnalysisStartRaw" in run.metrics:
            run.metrics["AnalysisStartRawCentered"] = run.metrics["AnalysisStartRaw"] - start_mean
        row: Dict[str, object] = {
            "SequentialRun": sequential,
            "Leg": run.sweep.leg,
            "SourceFile": run.sweep.source.name,
            "TestID": run.sweep.test_id,
            "SweepID": run.sweep.sweep_id,
            "RunOrder": run.sweep.run_order,
            "RunRole": run.sweep.run_role,
            "EligibleForStatistics": 1 if run.sweep.eligible else 0,
            "BuildID": run.sweep.meta.get("BuildID", ""),
            "ApproachProtocol": run.sweep.meta.get("ApproachProtocol", ""),
            "PreconditionProtocol": run.sweep.meta.get("PreconditionProtocol", ""),
        }
        row.update(run.metrics)
        rows.append(row)
    metric_names = sorted(set().union(*(run.metrics.keys() for run in runs)))
    return fields[:11] + metric_names, rows


def group_runs(runs: Sequence[MetricRun]) -> List[Tuple[str, List[MetricRun]]]:
    ordered: List[Tuple[str, List[MetricRun]]] = []
    for run in runs:
        if not ordered or ordered[-1][0] != run.sweep.leg:
            ordered.append((run.sweep.leg, []))
        ordered[-1][1].append(run)
    return ordered


def build_stability_rows(runs: Sequence[MetricRun]) -> List[Dict[str, object]]:
    groups = group_runs(runs) + [("ALL", list(runs))]
    rows: List[Dict[str, object]] = []
    for leg, members in groups:
        values = [run.metrics["NL_RobustP2P_Deg"] for run in members]
        stats = describe(values)
        trend = linear_fit(list(range(1, len(values) + 1)), values)
        row: Dict[str, object] = {"Group": leg, **stats}
        if trend:
            row.update({
                "slope_deg_per_run": trend.slope,
                "slope_pct_of_mean_per_run": 100.0 * trend.slope / stats["mean"],
                "trend_r2": trend.r2,
                "trend_residual_sd": trend.residual_sd,
                "slope_ci95_low": trend.slope_ci95_low,
                "slope_ci95_high": trend.slope_ci95_high,
            })
        rows.append(row)
    return rows


def build_fit_rows(runs: Sequence[MetricRun]) -> List[Dict[str, object]]:
    groups = [("ALL", list(runs))] + group_runs(runs)
    rows: List[Dict[str, object]] = []
    for group_name, members in groups:
        for metric in DEFAULT_RELATION_METRICS:
            pairs = [
                (run.metrics[metric], run.metrics["NL_RobustP2P_Deg"])
                for run in members if metric in run.metrics
            ]
            fit = linear_fit([pair[0] for pair in pairs], [pair[1] for pair in pairs])
            if fit is None:
                continue
            rows.append({
                "Group": group_name,
                "XMetric": metric,
                "YMetric": "NL_RobustP2P_Deg",
                "n": fit.n,
                "slope": fit.slope,
                "intercept": fit.intercept,
                "pearson_r": fit.r,
                "r2": fit.r2,
                "residual_sd": fit.residual_sd,
                "slope_se": fit.slope_se,
                "slope_ci95_low": fit.slope_ci95_low,
                "slope_ci95_high": fit.slope_ci95_high,
            })
    return rows


def plot_trend(runs: Sequence[MetricRun], out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(11, 5.8))
    groups = group_runs(runs)
    colors = plt.get_cmap("tab10")
    start = 1
    all_x: List[float] = []
    all_y: List[float] = []
    for group_index, (leg, members) in enumerate(groups):
        xs = list(range(start, start + len(members)))
        ys = [run.metrics["NL_RobustP2P_Deg"] for run in members]
        all_x.extend(xs)
        all_y.extend(ys)
        color = colors(group_index)
        ax.plot(xs, ys, marker="o", linewidth=1.3, color=color, label=leg)
        local_fit = linear_fit(list(range(1, len(ys) + 1)), ys)
        if local_fit and len(ys) >= 2:
            fit_y = [local_fit.slope * local_x + local_fit.intercept
                     for local_x in (1, len(ys))]
            ax.plot([xs[0], xs[-1]], fit_y, linestyle="--", linewidth=1.2, color=color)
        if start > 1:
            ax.axvline(start - 0.5, color="0.65", linewidth=0.8)
        start += len(members)

    pooled = linear_fit(all_x, all_y)
    if pooled:
        fit_y = [pooled.slope * x + pooled.intercept for x in (all_x[0], all_x[-1])]
        ax.plot([all_x[0], all_x[-1]], fit_y, color="0.2", linewidth=1.6,
                label=f"pooled fit: slope={pooled.slope:+.4f} deg/run, R²={pooled.r2:.3f}")
    ax.set_xlabel("Official run sequence across A1 → B → A2")
    ax.set_ylabel("NL robust P2P (deg)")
    ax.set_title("NL repeatability and linear drift")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best", fontsize=9)
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_relationships(runs: Sequence[MetricRun], out_path: Path) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(15, 9))
    groups = group_runs(runs)
    colors = plt.get_cmap("tab10")
    labels = {
        "ShadowP2P_Deg": "Canonical P2P (deg)",
        "RMS_AC_Deg": "RMS_AC (deg)",
        "A36_Deg": "A36 (deg)",
        "ClosureErrorDeg": "Closure error (deg)",
        "ApproachReturnErrorDeg": "B0-B return error (deg)",
        "AnalysisStartRawCentered": "AnalysisStartRaw - pooled mean (raw)",
    }
    for ax, metric in zip(axes.flat, DEFAULT_RELATION_METRICS):
        pooled_x: List[float] = []
        pooled_y: List[float] = []
        for group_index, (leg, members) in enumerate(groups):
            pairs = [(run.metrics[metric], run.metrics["NL_RobustP2P_Deg"])
                     for run in members if metric in run.metrics]
            if not pairs:
                continue
            xs = [pair[0] for pair in pairs]
            ys = [pair[1] for pair in pairs]
            pooled_x.extend(xs)
            pooled_y.extend(ys)
            ax.scatter(xs, ys, s=34, color=colors(group_index), label=leg, alpha=0.9)
        fit = linear_fit(pooled_x, pooled_y)
        if fit:
            low, high = min(pooled_x), max(pooled_x)
            ax.plot([low, high], [fit.slope * low + fit.intercept,
                                  fit.slope * high + fit.intercept],
                    color="0.2", linewidth=1.4)
            ax.text(0.03, 0.97, f"r={fit.r:+.3f}\nR²={fit.r2:.3f}\nn={fit.n}",
                    transform=ax.transAxes, va="top", fontsize=9,
                    bbox={"boxstyle": "round,pad=0.25", "facecolor": "white", "alpha": 0.75,
                          "edgecolor": "0.8"})
        ax.set_xlabel(labels[metric])
        ax.set_ylabel("NL robust P2P (deg)")
        ax.grid(True, alpha=0.22)
    handles, legend_labels = axes.flat[0].get_legend_handles_labels()
    if handles:
        fig.legend(handles, legend_labels, loc="upper center", ncol=len(handles), frameon=False)
    fig.suptitle("Linear relationships proposed for NL diagnosis", y=0.995)
    fig.tight_layout(rect=(0, 0, 1, 0.965))
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_error_curves(runs: Sequence[MetricRun], out_path: Path) -> None:
    fig, ax = plt.subplots(figsize=(12, 6.2))
    colors = plt.get_cmap("tab10")
    for group_index, (leg, members) in enumerate(group_runs(runs)):
        count = min(len(run.errors) for run in members)
        mean_curve = [statistics.fmean(run.errors[index] for run in members)
                      for index in range(count)]
        sd_curve = [statistics.stdev(run.errors[index] for run in members)
                    if len(members) >= 2 else 0.0 for index in range(count)]
        x = [360.0 * index / count for index in range(count)]
        color = colors(group_index)
        ax.plot(x, mean_curve, color=color, linewidth=1.4, label=f"{leg} mean")
        ax.fill_between(x,
                        [m - s for m, s in zip(mean_curve, sd_curve)],
                        [m + s for m, s in zip(mean_curve, sd_curve)],
                        color=color, alpha=0.12)
    ax.axhline(0.0, color="0.4", linewidth=0.8)
    ax.set_xlim(0, 360)
    ax.set_xlabel("Sweep progress / mechanical angle (deg)")
    ax.set_ylabel("Error (deg)")
    ax.set_title("Mean NL error curve by leg (band = ±1 SD across official runs)")
    ax.grid(True, alpha=0.22)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def write_report(path: Path, runs: Sequence[MetricRun], stability_rows: Sequence[Dict[str, object]],
                 fit_rows: Sequence[Dict[str, object]], warnings: Sequence[str],
                 exclusions: Sequence[str]) -> None:
    def max_abs_metric(name: str) -> Optional[float]:
        values = [abs(run.metrics[name]) for run in runs if name in run.metrics]
        return max(values) if values else None

    nl_crosscheck = max_abs_metric("NL_MinusFirmwareRounded_Deg")
    rms_crosscheck = max_abs_metric("RMS_RecomputeDelta_Deg")
    a36_crosscheck = max_abs_metric("A36_RecomputeDelta_Deg")
    lines = [
        "NL STABILITY REPORT",
        "===================",
        f"Accepted official sweeps: {len(runs)}",
        f"Excluded sweeps: {len(exclusions)}",
        "NL definition: mean(top 5 DATA error values) - mean(bottom 5), first AnalysisPoints rows.",
        "Precondition policy: excluded unless --include-precondition is used.",
        "The 2.77*SD value is a repeatability diagnostic, not an ISO pass claim without a qualified study.",
        "",
        "STABILITY",
        "---------",
    ]
    for row in stability_rows:
        lines.append(
            f"{row['Group']}: n={int(float(row['n']))} mean={float(row['mean']):.6f} deg "
            f"SD={float(row['sample_sd']):.6f} CV={float(row['cv_pct']):.3f}% "
            f"range={float(row['range']):.6f} r(2.77s)={float(row['repeatability_limit_2_77sd']):.6f} deg "
            f"slope={float(row.get('slope_deg_per_run', 0.0)):+.6f} deg/run "
            f"R2={float(row.get('trend_r2', 0.0)):.4f}"
        )
    lines.extend(["", "DATA/FIRMWARE CROSS-CHECK", "-------------------------"])
    if nl_crosscheck is not None:
        lines.append(f"max |recomputed NL - firmware rounded NL| = {nl_crosscheck:.8f} deg")
    if rms_crosscheck is not None:
        lines.append(f"max |recomputed RMS_AC - shadow RMS_AC| = {rms_crosscheck:.8f} deg")
    if a36_crosscheck is not None:
        lines.append(f"max |recomputed A36 - shadow A36| = {a36_crosscheck:.8f} deg")
    lines.extend(["", "POOLED LINEAR RELATIONSHIPS (Y = NL)", "------------------------------------"])
    pooled = [row for row in fit_rows if row["Group"] == "ALL"]
    for row in pooled:
        lines.append(
            f"{row['XMetric']}: n={row['n']} r={float(row['pearson_r']):+.4f} "
            f"R2={float(row['r2']):.4f} slope={float(row['slope']):+.6f} "
            f"residualSD={float(row['residual_sd']):.6f}"
        )
    if warnings:
        lines.extend(["", "WARNINGS", "--------", *warnings])
    if exclusions:
        lines.extend(["", "EXCLUSIONS", "----------", *exclusions])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run_self_test() -> int:
    values = [-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5]
    robust = statistics.fmean(sorted(values)[-5:]) - statistics.fmean(sorted(values)[:5])
    fit = linear_fit([1.0, 2.0, 3.0], [3.0, 5.0, 7.0])
    checks = [
        (abs(robust - 2.5) < 1e-12, "robust top5-bottom5"),
        (fit is not None and abs(fit.slope - 2.0) < 1e-12, "linear-fit slope"),
        (fit is not None and abs(fit.intercept - 1.0) < 1e-12, "linear-fit intercept"),
        (fit is not None and abs(fit.r2 - 1.0) < 1e-12, "linear-fit R2"),
    ]
    for passed, label in checks:
        print(f"[{'PASS' if passed else 'FAIL'}] {label}")
    return 0 if all(passed for passed, _ in checks) else 1


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logfiles", nargs="*", type=Path, help="Input TXT logs in test order")
    parser.add_argument("--labels", nargs="*", help="Optional labels, one per input log (e.g. A1 B A2)")
    parser.add_argument("--out-dir", type=Path, default=Path("analysis-out/nl-stability"))
    parser.add_argument("--include-precondition", action="store_true")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return run_self_test()

    logfiles = list(args.logfiles) if args.logfiles else infer_default_logs(Path.cwd())
    if not logfiles:
        parser.error("no logs supplied and no P03 JIG1 test-20 logs were auto-discovered")
    if args.labels and len(args.labels) != len(logfiles):
        parser.error("--labels count must match the number of input logs")
    missing = [path for path in logfiles if not path.is_file()]
    if missing:
        parser.error("file not found: " + ", ".join(str(path) for path in missing))

    all_sweeps: List[Sweep] = []
    warnings: List[str] = []
    for file_index, path in enumerate(logfiles):
        leg = args.labels[file_index] if args.labels else infer_leg(path, file_index)
        sweeps, file_warnings = load_sweeps(path, leg, file_index)
        all_sweeps.extend(sweeps)
        warnings.extend(file_warnings)

    runs: List[MetricRun] = []
    exclusions: List[str] = []
    for sweep in all_sweeps:
        metric_run, reasons = validate_and_compute(sweep, args.include_precondition)
        if metric_run is None:
            exclusions.append(
                f"{sweep.source.name} TestID={sweep.test_id} SweepID={sweep.sweep_id} "
                f"RunOrder={sweep.run_order}: {'; '.join(reasons)}"
            )
        else:
            runs.append(metric_run)
    runs.sort(key=lambda run: (
        run.sweep.file_index,
        run.sweep.run_order if run.sweep.run_order is not None else 10**9,
        run.sweep.test_id,
    ))
    if not runs:
        print("error: no valid sweeps available after filtering", file=sys.stderr)
        return 1

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    run_fields, run_rows = make_run_rows(runs)
    stability_rows = build_stability_rows(runs)
    fit_rows = build_fit_rows(runs)

    csv_write(out_dir / "nl_runs.csv", run_fields, run_rows)
    stability_fields = [
        "Group", "n", "mean", "sample_sd", "cv_pct", "median", "mad",
        "robust_sigma", "min", "max", "range", "repeatability_limit_2_77sd",
        "slope_deg_per_run", "slope_pct_of_mean_per_run", "trend_r2",
        "trend_residual_sd", "slope_ci95_low", "slope_ci95_high",
    ]
    csv_write(out_dir / "nl_stability.csv", stability_fields, stability_rows)
    fit_fields = [
        "Group", "XMetric", "YMetric", "n", "slope", "intercept", "pearson_r",
        "r2", "residual_sd", "slope_se", "slope_ci95_low", "slope_ci95_high",
    ]
    csv_write(out_dir / "nl_linear_fits.csv", fit_fields, fit_rows)
    plot_trend(runs, out_dir / "nl_trend.png")
    plot_relationships(runs, out_dir / "nl_linear_relationships.png")
    plot_error_curves(runs, out_dir / "nl_error_curve.png")
    write_report(out_dir / "nl_report.txt", runs, stability_rows, fit_rows, warnings, exclusions)

    print(f"Accepted {len(runs)} official sweep(s) from {len(logfiles)} log(s).")
    print(f"Excluded {len(exclusions)} sweep(s) (normally PRECONDITION runs).")
    for row in stability_rows:
        print(
            f"{row['Group']:>4}: n={int(float(row['n'])):2d} "
            f"mean={float(row['mean']):.5f} SD={float(row['sample_sd']):.5f} "
            f"CV={float(row['cv_pct']):.2f}% range={float(row['range']):.5f} "
            f"slope={float(row.get('slope_deg_per_run', 0.0)):+.5f}/run"
        )
    print(f"Outputs: {out_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
