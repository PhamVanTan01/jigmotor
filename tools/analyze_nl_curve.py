#!/usr/bin/env python3
"""Analyze the complete pointwise error curve for an A1-B-A2 jig study.

The robust NL scalar is retained as the firmware-compatible run metric:

    mean(largest K errors) - mean(smallest K errors)

It is not assigned to individual points.  Per-point values in this tool are
called the *pointwise error curve*.  The closure sample at index
``AnalysisPoints`` is checked separately and is never included in the
360-point curve, robust NL, or harmonic spectrum.

Example:

    python tools/analyze_nl_curve.py \
      --a1 "S2-P03-JIG1-A1.txt" \
      --b "S2-P03-JIG4-B.txt" \
      --a2 "S2-P03-JIG1-A2.txt" \
      --out-dir analysis-out/s2-p03-nl-curve
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from analyze_motor_logs import (
    ROBUST_EXTREME_COUNT,
    SweepReport,
    build_report,
    compute_harmonic,
    load_sweeps,
)
from analyze_nl_extreme_angles import centered_rmse, pearson


DEFAULT_HIGHLIGHT_ORDERS = (1, 2, 4, 8, 9, 18, 36)


@dataclass
class Thresholds:
    within_sd_limit_deg: float = 0.03
    remount_shift_limit_deg: float = 0.05
    minimum_cross_jig_limit_deg: float = 0.05
    repeatability_multiplier: float = 2.77
    tail_limit_deg: float = 0.10
    correlation_min: float = 0.98
    centered_rmse_limit_deg: float = 0.10
    closure_limit_deg: float = 0.20


@dataclass
class LegData:
    label: str
    paths: List[Path]
    reports: List[SweepReport]
    invalid_official_reports: int
    warnings: List[str]
    motor_id: str
    jig_id: str
    analysis_points: int
    raw_curves: List[List[float]]
    centered_curves: List[List[float]]
    raw_mean: List[float]
    raw_sd: List[float]
    centered_mean: List[float]
    centered_sd: List[float]
    top_frequency: Counter
    bottom_frequency: Counter
    top_means: List[float]
    bottom_means: List[float]

    @property
    def nl_values(self) -> List[float]:
        return [r.metrics.robust_p2p for r in self.reports if r.metrics]

    @property
    def closure_values(self) -> List[float]:
        return [
            r.metrics.closure_error_deg
            for r in self.reports
            if r.metrics and r.metrics.closure_error_deg is not None
        ]


def mean_sd(values: Sequence[float]) -> Tuple[float, float]:
    if not values:
        return float("nan"), float("nan")
    return statistics.fmean(values), (
        statistics.stdev(values) if len(values) > 1 else 0.0
    )


def pointwise_mean_sd(curves: Sequence[Sequence[float]]) -> Tuple[List[float], List[float]]:
    if not curves:
        raise ValueError("cannot summarize an empty curve collection")
    n = len(curves[0])
    if any(len(curve) != n for curve in curves):
        raise ValueError("curve lengths differ inside one leg")
    means = [statistics.fmean(curve[i] for curve in curves) for i in range(n)]
    sds = [
        statistics.stdev(curve[i] for curve in curves)
        if len(curves) > 1 else 0.0
        for i in range(n)
    ]
    return means, sds


def center_curve(curve: Sequence[float]) -> List[float]:
    mean = statistics.fmean(curve)
    return [value - mean for value in curve]


def circular_shift(curve: Sequence[float], shift: int) -> List[float]:
    n = len(curve)
    return [curve[(i + shift) % n] for i in range(n)]


def find_best_circular_alignment(
        reference: Sequence[float], candidate: Sequence[float]
) -> Dict[str, float]:
    if len(reference) != len(candidate) or not reference:
        raise ValueError("alignment requires two non-empty equal-length curves")
    ranked = [
        (pearson(reference, circular_shift(candidate, shift)), shift)
        for shift in range(len(reference))
    ]
    ranked.sort(key=lambda item: (-math.inf if math.isnan(item[0]) else item[0]),
                reverse=True)
    best_corr, best_shift = ranked[0]
    second_corr, second_shift = ranked[1] if len(ranked) > 1 else ranked[0]
    return {
        "best_shift_points": best_shift,
        "best_shift_deg": best_shift * 360.0 / len(reference),
        "best_shift_correlation": best_corr,
        "second_shift_points": second_shift,
        "second_shift_deg": second_shift * 360.0 / len(reference),
        "second_shift_correlation": second_corr,
        "correlation_margin": best_corr - second_corr,
    }


def pooled_within_leg_sd(groups: Sequence[Sequence[float]]) -> float:
    """Pool only within-leg variance; never let A1->A2 drift inflate the gate."""
    usable = [list(values) for values in groups if len(values) >= 2]
    degrees_of_freedom = sum(len(values) - 1 for values in usable)
    if degrees_of_freedom == 0:
        return 0.0
    sum_squares = sum(
        (len(values) - 1) * statistics.variance(values)
        for values in usable
    )
    return math.sqrt(sum_squares / degrees_of_freedom)


def inspect_config(paths: Sequence[Path]) -> Dict[str, object]:
    """Return a conservative CONFIG/acquisition health assessment."""
    config_seen = 0
    config_failures: List[str] = []
    motor_errors: List[str] = []
    for path in paths:
        with path.open("r", encoding="utf-8", errors="replace") as handle:
            for line_no, line in enumerate(handle, start=1):
                if line.startswith("CONFIG,"):
                    config_seen += 1
                    if "ConfigValid=0" in line or "PolicyAGatePassed=0" in line:
                        config_failures.append(f"{path.name}:{line_no}")
                elif "Motor ERROR:" in line:
                    motor_errors.append(f"{path.name}:{line_no}:{line.strip()}")
    state = "PASS"
    if config_failures or motor_errors:
        state = "FAIL"
    elif config_seen == 0:
        state = "UNKNOWN"
    return {
        "state": state,
        "config_records_seen": config_seen,
        "config_failures": config_failures,
        "motor_errors": motor_errors,
    }


def load_leg(label: str, paths: Sequence[Path], k: int) -> LegData:
    reports: List[SweepReport] = []
    warnings: List[str] = []
    for path in paths:
        sweeps, parse_warnings = load_sweeps(path)
        warnings.extend(parse_warnings)
        reports.extend(build_report(sweep) for sweep in sweeps)

    eligible = [
        report for report in reports
        if report.officially_valid and report.metrics is not None
    ]
    invalid_official = [
        report for report in reports
        if (
            report.sweep.run_role == "OFFICIAL"
            or not report.sweep.uses_declared_role_contract
        )
        and not report.officially_valid
    ]
    if not eligible:
        excluded = "; ".join(
            f"{Path(r.sweep.source_file).name}:"
            f"run={r.sweep.run_order}:{' | '.join(r.problems)}"
            for r in reports
        )
        raise ValueError(f"{label}: no eligible OFFICIAL sweeps. {excluded}")

    counts = {report.sweep.analysis_point_count for report in eligible}
    motors = {report.sweep.motor_id or "UNKNOWN_MOTOR" for report in eligible}
    jigs = {report.sweep.jig_id or "UNKNOWN_JIG" for report in eligible}
    if len(counts) != 1:
        raise ValueError(f"{label}: mixed AnalysisPoints values {sorted(counts)}")
    if len(motors) != 1:
        raise ValueError(f"{label}: mixed MotorID values {sorted(motors)}")
    if len(jigs) != 1:
        raise ValueError(f"{label}: mixed JigID values {sorted(jigs)}")

    n = counts.pop()
    curves = [
        [report.sweep.points[i].error_deg for i in range(n)]
        for report in eligible
    ]
    centered = [center_curve(curve) for curve in curves]
    raw_mean, raw_sd = pointwise_mean_sd(curves)
    centered_mean, centered_sd = pointwise_mean_sd(centered)
    top_frequency: Counter = Counter()
    bottom_frequency: Counter = Counter()
    top_means: List[float] = []
    bottom_means: List[float] = []
    k = min(max(k, 1), n)
    for curve in curves:
        top = sorted(range(n), key=lambda index: curve[index], reverse=True)[:k]
        bottom = sorted(range(n), key=lambda index: curve[index])[:k]
        top_frequency.update(top)
        bottom_frequency.update(bottom)
        top_means.append(statistics.fmean(curve[index] for index in top))
        bottom_means.append(statistics.fmean(curve[index] for index in bottom))

    return LegData(
        label=label,
        paths=list(paths),
        reports=eligible,
        invalid_official_reports=len(invalid_official),
        warnings=warnings,
        motor_id=motors.pop(),
        jig_id=jigs.pop(),
        analysis_points=n,
        raw_curves=curves,
        centered_curves=centered,
        raw_mean=raw_mean,
        raw_sd=raw_sd,
        centered_mean=centered_mean,
        centered_sd=centered_sd,
        top_frequency=top_frequency,
        bottom_frequency=bottom_frequency,
        top_means=top_means,
        bottom_means=bottom_means,
    )


def leg_summary(leg: LegData) -> Dict[str, object]:
    nl_mean, nl_sd = mean_sd(leg.nl_values)
    top_mean, top_sd = mean_sd(leg.top_means)
    bottom_mean, bottom_sd = mean_sd(leg.bottom_means)
    closure_mean, closure_sd = mean_sd(leg.closure_values)
    max_shape_sd_index = max(
        range(leg.analysis_points), key=lambda i: leg.centered_sd[i])
    return {
        "leg": leg.label,
        "motor_id": leg.motor_id,
        "jig_id": leg.jig_id,
        "eligible_runs": len(leg.reports),
        "analysis_points": leg.analysis_points,
        "nl_mean_deg": nl_mean,
        "nl_sd_deg": nl_sd,
        "top_mean_deg": top_mean,
        "top_sd_deg": top_sd,
        "bottom_mean_deg": bottom_mean,
        "bottom_sd_deg": bottom_sd,
        "closure_mean_deg": closure_mean,
        "closure_sd_deg": closure_sd,
        "closure_max_abs_deg": max(map(abs, leg.closure_values), default=float("nan")),
        "centered_pointwise_sd_mean_deg": statistics.fmean(leg.centered_sd),
        "centered_pointwise_sd_max_deg": leg.centered_sd[max_shape_sd_index],
        "centered_pointwise_sd_max_angle_deg": (
            max_shape_sd_index * 360.0 / leg.analysis_points),
    }


def harmonic_rows(legs: Sequence[LegData]) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for leg in legs:
        n = leg.analysis_points
        for order in range(1, n // 2 + 1):
            mean_result = compute_harmonic(
                leg.raw_mean, statistics.fmean(leg.raw_mean), order, n, None
            )
            run_amplitudes = [
                compute_harmonic(
                    curve, statistics.fmean(curve), order, n, None
                ).amplitude
                for curve in leg.raw_curves
            ]
            amplitude_mean, amplitude_sd = mean_sd(run_amplitudes)
            rows.append({
                "leg": leg.label,
                "motor_id": leg.motor_id,
                "jig_id": leg.jig_id,
                "order": order,
                "mean_curve_amplitude_deg": mean_result.amplitude,
                "mean_curve_phase_deg": mean_result.phase_deg,
                "run_amplitude_mean_deg": amplitude_mean,
                "run_amplitude_sd_deg": amplitude_sd,
            })
    return rows


def write_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def build_analysis(
    a1: LegData, b: LegData, a2: LegData, thresholds: Thresholds
) -> Dict[str, object]:
    legs = (a1, b, a2)
    counts = {leg.analysis_points for leg in legs}
    motors = {leg.motor_id for leg in legs}
    if len(counts) != 1:
        raise ValueError(f"A1/B/A2 use different AnalysisPoints: {sorted(counts)}")
    if len(motors) != 1:
        raise ValueError(f"A1/B/A2 use different MotorID values: {sorted(motors)}")
    if a1.jig_id != a2.jig_id:
        raise ValueError(
            f"A1 and A2 must use the same jig, got {a1.jig_id} and {a2.jig_id}")

    n = a1.analysis_points
    a_raw = [(x + y) / 2.0 for x, y in zip(a1.raw_mean, a2.raw_mean)]
    a_centered = [
        (x + y) / 2.0 for x, y in zip(a1.centered_mean, a2.centered_mean)
    ]
    zero_corr = pearson(a_centered, b.centered_mean)
    zero_rmse = centered_rmse(a_centered, b.centered_mean)
    alignment = find_best_circular_alignment(a_centered, b.centered_mean)
    best_shift = int(alignment["best_shift_points"])
    b_aligned = circular_shift(b.centered_mean, best_shift)
    aligned_rmse = centered_rmse(a_centered, b_aligned)

    a_nl = a1.nl_values + a2.nl_values
    b_nl = b.nl_values
    a_nl_mean = (statistics.fmean(a1.nl_values) + statistics.fmean(a2.nl_values)) / 2.0
    b_nl_mean = statistics.fmean(b_nl)
    # The repeatability term is pooled from variance *inside* A1, B, and A2.
    # Concatenating A1+A2 before calculating SD would treat baseline drift as
    # random repeatability and incorrectly make the cross-jig gate easier.
    repeatability_sd = pooled_within_leg_sd(
        [a1.nl_values, b.nl_values, a2.nl_values])
    cross_limit = max(
        thresholds.minimum_cross_jig_limit_deg,
        thresholds.repeatability_multiplier * repeatability_sd,
    )
    top_a = (statistics.fmean(a1.top_means) + statistics.fmean(a2.top_means)) / 2.0
    bottom_a = (
        statistics.fmean(a1.bottom_means) + statistics.fmean(a2.bottom_means)
    ) / 2.0
    top_b = statistics.fmean(b.top_means)
    bottom_b = statistics.fmean(b.bottom_means)
    all_closures = [value for leg in legs for value in leg.closure_values]
    a_return_nl_drift = (
        statistics.fmean(a2.nl_values) - statistics.fmean(a1.nl_values))
    a_return_corr = pearson(a1.centered_mean, a2.centered_mean)
    a_return_rmse = centered_rmse(a1.centered_mean, a2.centered_mean)

    gates = {
        "within_batch_nl_sd": {
            "value_deg": max(mean_sd(leg.nl_values)[1] for leg in legs),
            "limit": f"<= {thresholds.within_sd_limit_deg:.5f} deg",
            "passed": all(
                mean_sd(leg.nl_values)[1] <= thresholds.within_sd_limit_deg
                for leg in legs
            ),
        },
        "a_return_nl_shift": {
            "value_deg": a_return_nl_drift,
            "absolute_value_deg": abs(a_return_nl_drift),
            "limit_deg": thresholds.remount_shift_limit_deg,
            "passed": abs(a_return_nl_drift) <= thresholds.remount_shift_limit_deg,
        },
        "a_return_curve_correlation": {
            "value": a_return_corr,
            "limit": f">= {thresholds.correlation_min:.5f}",
            "passed": a_return_corr >= thresholds.correlation_min,
        },
        "a_return_centered_rmse": {
            "value_deg": a_return_rmse,
            "limit": f"<= {thresholds.centered_rmse_limit_deg:.5f} deg",
            "passed": a_return_rmse <= thresholds.centered_rmse_limit_deg,
        },
        "cross_jig_nl_delta": {
            "value_deg": b_nl_mean - a_nl_mean,
            "absolute_value_deg": abs(b_nl_mean - a_nl_mean),
            "limit_deg": cross_limit,
            "passed": abs(b_nl_mean - a_nl_mean) <= cross_limit,
        },
        "top_tail_delta": {
            "value_deg": top_b - top_a,
            "limit": f"abs <= {thresholds.tail_limit_deg:.5f} deg",
            "passed": abs(top_b - top_a) <= thresholds.tail_limit_deg,
        },
        "bottom_tail_delta": {
            "value_deg": bottom_b - bottom_a,
            "limit": f"abs <= {thresholds.tail_limit_deg:.5f} deg",
            "passed": abs(bottom_b - bottom_a) <= thresholds.tail_limit_deg,
        },
        "zero_shift_curve_correlation": {
            "value": zero_corr,
            "limit": f">= {thresholds.correlation_min:.5f}",
            "passed": zero_corr >= thresholds.correlation_min,
        },
        "zero_shift_centered_rmse": {
            "value_deg": zero_rmse,
            "limit": f"<= {thresholds.centered_rmse_limit_deg:.5f} deg",
            "passed": zero_rmse <= thresholds.centered_rmse_limit_deg,
        },
        "closure": {
            "max_abs_deg": max(map(abs, all_closures), default=float("inf")),
            "available": len(all_closures) == sum(len(leg.reports) for leg in legs),
            "limit": f"abs <= {thresholds.closure_limit_deg:.5f} deg",
            "passed": (
                len(all_closures) == sum(len(leg.reports) for leg in legs)
                and all(abs(value) <= thresholds.closure_limit_deg
                        for value in all_closures)
            ),
        },
    }
    gates["all_primary_gates"] = {
        "passed": all(item["passed"] for item in gates.values())
    }

    raw_diff = [bv - av for av, bv in zip(a_raw, b.raw_mean)]
    centered_diff = [
        bv - av for av, bv in zip(a_centered, b.centered_mean)
    ]
    aligned_diff = [bv - av for av, bv in zip(a_centered, b_aligned)]
    return {
        "motor_id": a1.motor_id,
        "analysis_points": n,
        "jig_a": a1.jig_id,
        "jig_b": b.jig_id,
        "a_raw_mean": a_raw,
        "a_centered_mean": a_centered,
        "b_aligned_centered_mean": b_aligned,
        "raw_diff": raw_diff,
        "centered_diff": centered_diff,
        "aligned_diff": aligned_diff,
        "zero_shift_correlation": zero_corr,
        "zero_shift_centered_rmse_deg": zero_rmse,
        "aligned_centered_rmse_deg": aligned_rmse,
        "alignment": alignment,
        "a1_to_a2_nl_drift_deg": a_return_nl_drift,
        "a1_to_a2_curve_correlation": a_return_corr,
        "a1_to_a2_centered_rmse_deg": a_return_rmse,
        "a_baseline_return_valid": all(
            gates[name]["passed"] for name in (
                "a_return_nl_shift",
                "a_return_curve_correlation",
                "a_return_centered_rmse",
            )
        ),
        "a_nl_mean_deg": a_nl_mean,
        "b_nl_mean_deg": b_nl_mean,
        "nl_delta_b_minus_a_deg": b_nl_mean - a_nl_mean,
        "pooled_nl_sd_deg": repeatability_sd,
        "cross_jig_nl_limit_deg": cross_limit,
        "top_a_mean_deg": top_a,
        "top_b_mean_deg": top_b,
        "top_delta_b_minus_a_deg": top_b - top_a,
        "bottom_a_mean_deg": bottom_a,
        "bottom_b_mean_deg": bottom_b,
        "bottom_delta_b_minus_a_deg": bottom_b - bottom_a,
        "gates": gates,
    }


def pointwise_rows(
    a1: LegData, b: LegData, a2: LegData, analysis: Dict[str, object]
) -> List[Dict[str, object]]:
    n = a1.analysis_points
    shift = int(analysis["alignment"]["best_shift_points"])
    rows: List[Dict[str, object]] = []
    for i in range(n):
        j = (i + shift) % n
        row: Dict[str, object] = {
            "point_index": i,
            "sweep_angle_deg": i * 360.0 / n,
        }
        for leg in (a1, b, a2):
            prefix = leg.label.lower()
            row.update({
                f"{prefix}_raw_mean_error_deg": leg.raw_mean[i],
                f"{prefix}_raw_pointwise_sd_deg": leg.raw_sd[i],
                f"{prefix}_centered_mean_error_deg": leg.centered_mean[i],
                f"{prefix}_centered_pointwise_sd_deg": leg.centered_sd[i],
                f"{prefix}_top_selection_rate": (
                    leg.top_frequency[i] / len(leg.reports)),
                f"{prefix}_bottom_selection_rate": (
                    leg.bottom_frequency[i] / len(leg.reports)),
            })
        row.update({
            "a_average_raw_mean_error_deg": analysis["a_raw_mean"][i],
            "a_average_centered_mean_error_deg": analysis["a_centered_mean"][i],
            "b_minus_a_raw_error_deg": analysis["raw_diff"][i],
            "b_minus_a_centered_error_deg": analysis["centered_diff"][i],
            "b_aligned_source_index": j,
            "b_aligned_source_angle_deg": j * 360.0 / n,
            "b_aligned_centered_mean_error_deg": (
                analysis["b_aligned_centered_mean"][i]),
            "b_minus_a_aligned_centered_error_deg": analysis["aligned_diff"][i],
        })
        rows.append(row)
    return rows


def run_rows(legs: Sequence[LegData], k: int) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    selected = DEFAULT_HIGHLIGHT_ORDERS
    for leg in legs:
        for report in leg.reports:
            sweep = report.sweep
            metrics = report.metrics
            assert metrics is not None
            curve = [sweep.points[i].error_deg for i in range(leg.analysis_points)]
            top = sorted(curve, reverse=True)[:k]
            bottom = sorted(curve)[:k]
            row: Dict[str, object] = {
                "leg": leg.label,
                "source_file": sweep.source_file,
                "test_id": sweep.test_id,
                "sweep_id": sweep.sweep_id,
                "run_order": sweep.run_order,
                "motor_id": sweep.motor_id,
                "jig_id": sweep.jig_id,
                "analysis_points": leg.analysis_points,
                "robust_nl_deg": metrics.robust_p2p,
                "top_tail_mean_deg": statistics.fmean(top),
                "bottom_tail_mean_deg": statistics.fmean(bottom),
                "rms_ac_deg": metrics.rms_ac,
                "raw_p2p_deg": metrics.raw_p2p,
                "closure_error_deg": metrics.closure_error_deg,
            }
            for order in selected:
                if order <= leg.analysis_points // 2:
                    row[f"h{order}_amplitude_deg"] = compute_harmonic(
                        curve, statistics.fmean(curve), order,
                        leg.analysis_points, sweep.step_raw).amplitude
            rows.append(row)
    return rows


def extreme_rows(legs: Sequence[LegData], k: int) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for leg in legs:
        n = leg.analysis_points
        top = sorted(range(n), key=lambda i: leg.raw_mean[i], reverse=True)[:k]
        bottom = sorted(range(n), key=lambda i: leg.raw_mean[i])[:k]
        for kind, indices, frequency in (
            ("TOP", top, leg.top_frequency),
            ("BOTTOM", bottom, leg.bottom_frequency),
        ):
            for rank, index in enumerate(indices, start=1):
                rows.append({
                    "leg": leg.label,
                    "motor_id": leg.motor_id,
                    "jig_id": leg.jig_id,
                    "kind": kind,
                    "rank": rank,
                    "point_index": index,
                    "sweep_angle_deg": index * 360.0 / n,
                    "mean_error_deg": leg.raw_mean[index],
                    "pointwise_sd_deg": leg.raw_sd[index],
                    "selection_count": frequency[index],
                    "selection_rate": frequency[index] / len(leg.reports),
                })
    return rows


def make_plots(
    out_dir: Path,
    legs: Sequence[LegData],
    analysis: Dict[str, object],
    harmonics: Sequence[Dict[str, object]],
    highlight_orders: Sequence[int],
) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colors = {"A1": "#2563eb", "B": "#dc2626", "A2": "#16a34a"}
    n = legs[0].analysis_points
    angles = [i * 360.0 / n for i in range(n)]

    def finish(path: Path, title: str) -> None:
        plt.suptitle(title, fontsize=12)
        plt.tight_layout()
        plt.savefig(path, dpi=180, bbox_inches="tight")
        plt.close()

    plt.figure(figsize=(11, 5.8))
    for leg in legs:
        color = colors[leg.label]
        lower = [m - s for m, s in zip(leg.raw_mean, leg.raw_sd)]
        upper = [m + s for m, s in zip(leg.raw_mean, leg.raw_sd)]
        plt.plot(angles, leg.raw_mean, color=color, linewidth=1.4,
                 label=f"{leg.label} {leg.jig_id} mean")
        plt.fill_between(angles, lower, upper, color=color, alpha=0.12)
    plt.xlabel("Sweep-relative angle (deg)")
    plt.ylabel("Logged error (deg)")
    plt.xlim(0, angles[-1])
    plt.grid(alpha=0.25)
    plt.legend(ncol=3, fontsize=8)
    finish(out_dir / "raw_error_curve.png",
           "Raw pointwise error curve (mean ± pointwise SD)")

    plt.figure(figsize=(11, 5.8))
    for leg in legs:
        color = colors[leg.label]
        lower = [m - s for m, s in zip(leg.centered_mean, leg.centered_sd)]
        upper = [m + s for m, s in zip(leg.centered_mean, leg.centered_sd)]
        plt.plot(angles, leg.centered_mean, color=color, linewidth=1.4,
                 label=f"{leg.label} {leg.jig_id} centered")
        plt.fill_between(angles, lower, upper, color=color, alpha=0.12)
    plt.axhline(0.0, color="#111827", linewidth=0.7)
    plt.xlabel("Sweep-relative angle (deg)")
    plt.ylabel("Centered error (deg)")
    plt.xlim(0, angles[-1])
    plt.grid(alpha=0.25)
    plt.legend(ncol=3, fontsize=8)
    finish(out_dir / "centered_error_curve.png",
           "Centered pointwise error curve (shape comparison)")

    fig, axes = plt.subplots(2, 1, figsize=(11, 7.2), sharex=True)
    axes[0].plot(angles, analysis["raw_diff"], color="#7c3aed", linewidth=1.2)
    axes[0].axhline(0.0, color="#111827", linewidth=0.7)
    axes[0].set_ylabel("B − mean(A1,A2) (deg)")
    axes[0].set_title("Raw A-B-A differential (includes DC shift)")
    axes[0].grid(alpha=0.25)
    axes[1].plot(angles, analysis["centered_diff"], color="#ea580c",
                 linewidth=1.2, label="zero-shift (primary)")
    axes[1].plot(angles, analysis["aligned_diff"], color="#0891b2",
                 linewidth=1.0, alpha=0.85, label="best circular alignment (diagnostic)")
    axes[1].axhline(0.0, color="#111827", linewidth=0.7)
    axes[1].set_xlabel("Sweep-relative angle (deg)")
    axes[1].set_ylabel("Centered difference (deg)")
    axes[1].set_xlim(0, angles[-1])
    axes[1].grid(alpha=0.25)
    axes[1].legend(fontsize=8)
    finish(out_dir / "aba_differential_curve.png",
           "A1-B-A2 differential: zero-shift is the interchangeability gate")

    by_leg: Dict[str, List[Dict[str, object]]] = {
        leg.label: [row for row in harmonics if row["leg"] == leg.label]
        for leg in legs
    }
    plt.figure(figsize=(11, 5.8))
    for leg in legs:
        rows = by_leg[leg.label]
        orders = [int(row["order"]) for row in rows]
        values = [float(row["mean_curve_amplitude_deg"]) for row in rows]
        plt.plot(orders, values, color=colors[leg.label], linewidth=1.0,
                 label=f"{leg.label} {leg.jig_id}")
        for order in highlight_orders:
            if 1 <= order <= len(values):
                plt.scatter(order, values[order - 1], color=colors[leg.label],
                            s=20, zorder=3)
    plt.xlabel("Mechanical harmonic order per revolution")
    plt.ylabel("Amplitude (deg)")
    plt.xlim(1, n // 2)
    plt.grid(alpha=0.25)
    plt.legend(ncol=3, fontsize=8)
    finish(out_dir / "harmonic_spectrum.png",
           "Harmonic spectrum of the mean pointwise error curve")


def gate_rows(analysis: Dict[str, object]) -> List[Dict[str, object]]:
    rows: List[Dict[str, object]] = []
    for name, gate in analysis["gates"].items():
        if name == "all_primary_gates":
            continue
        value = next((
            gate[key] for key in (
                "absolute_value_deg", "value_deg", "max_abs_deg", "value"
            ) if key in gate
        ), (
            f"invalid={gate.get('invalid_official_reports')}; "
            f"config={gate.get('config_state')}"
            if "config_state" in gate else ""
        ))
        limit = gate.get("limit", gate.get("limit_deg", ""))
        rows.append({
            "gate": name,
            "value": value,
            "limit": limit,
            "result": "PASS" if gate["passed"] else "FAIL",
        })
    return rows


def fmt(value: object, digits: int = 5) -> str:
    if isinstance(value, float):
        if math.isnan(value):
            return "N/A"
        return f"{value:.{digits}f}"
    return str(value)


def write_report(
    path: Path,
    legs: Sequence[LegData],
    summaries: Sequence[Dict[str, object]],
    analysis: Dict[str, object],
    harmonics: Sequence[Dict[str, object]],
    config_health: Dict[str, object],
    warnings: Sequence[str],
) -> None:
    passed = analysis["gates"]["all_primary_gates"]["passed"]
    a_return = analysis["a_baseline_return_valid"]
    lines = [
        f"# NL pointwise-curve assessment — {analysis['motor_id']}",
        "",
        f"**Primary A-B-A verdict: {'PASS' if passed else 'FAIL'}**",
        "",
        f"**A1→A2 baseline return: {'PASS' if a_return else 'FAIL / CONFOUNDED'}**",
        "",
        f"This report evaluates the 0..{analysis['analysis_points'] - 1} "
        "pointwise error curve. `Robust NL` "
        "remains the run-level top-5 minus bottom-5 statistic; no individual "
        f"point is labeled as NL. Closure at index "
        f"{analysis['analysis_points']} is checked separately.",
        "",
        "## Batch summary",
        "",
        "| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in summaries:
        lines.append(
            f"| {row['leg']} | {row['jig_id']} | {row['eligible_runs']} | "
            f"{fmt(row['nl_mean_deg'])}° | {fmt(row['nl_sd_deg'])}° | "
            f"{fmt(row['top_mean_deg'])}° | {fmt(row['bottom_mean_deg'])}° | "
            f"{fmt(row['centered_pointwise_sd_max_deg'])}° | "
            f"{fmt(row['closure_max_abs_deg'])}° |")

    lines += [
        "",
        "## A-B-A effects",
        "",
        f"- A1→A2 NL drift: `{analysis['a1_to_a2_nl_drift_deg']:+.5f}°`.",
        f"- A1→A2 curve correlation/RMSE: "
        f"`r={analysis['a1_to_a2_curve_correlation']:.5f}`, "
        f"`{analysis['a1_to_a2_centered_rmse_deg']:.5f}°`.",
        f"- B−mean(A1,A2) NL effect: `{analysis['nl_delta_b_minus_a_deg']:+.5f}°`.",
        f"- B−A top-tail effect: `{analysis['top_delta_b_minus_a_deg']:+.5f}°`.",
        f"- B−A bottom-tail effect: `{analysis['bottom_delta_b_minus_a_deg']:+.5f}°`.",
        f"- Zero-shift curve correlation: `{analysis['zero_shift_correlation']:.5f}`.",
        f"- Zero-shift centered RMSE: `{analysis['zero_shift_centered_rmse_deg']:.5f}°`.",
        f"- Best circular alignment (diagnostic only): "
        f"`{analysis['alignment']['best_shift_deg']:.1f}°`, "
        f"`r={analysis['alignment']['best_shift_correlation']:.5f}`, "
        f"`RMSE={analysis['aligned_centered_rmse_deg']:.5f}°`.",
        "",
        "The zero-shift values are the primary interchangeability result. "
        "Best circular alignment is reported explicitly as a diagnostic and "
        "is never applied silently.",
        "",
        "## Frozen pilot gates",
        "",
        "| Gate | Value | Limit | Result |",
        "|---|---:|---:|---|",
    ]
    for row in gate_rows(analysis):
        lines.append(
            f"| {row['gate']} | {fmt(row['value'])} | "
            f"{fmt(row['limit'])} | **{row['result']}** |")
    lines += [
        "",
        "## Selected harmonic fingerprint",
        "",
        "| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |",
        "|---|---:|---:|---:|---:|",
    ]
    for row in harmonics:
        if row["order"] in DEFAULT_HIGHLIGHT_ORDERS:
            lines.append(
                f"| {row['leg']} | H{row['order']} | "
                f"{fmt(row['mean_curve_amplitude_deg'])}° | "
                f"{fmt(row['mean_curve_phase_deg'], 2)}° | "
                f"{fmt(row['run_amplitude_sd_deg'])}° |")
    lines += [
        "",
        "## Data health",
        "",
        f"- CONFIG gate scan: **{config_health['state']}** "
        f"({config_health['config_records_seen']} CONFIG records).",
        f"- Invalid declared-OFFICIAL sweeps: "
        f"`{sum(leg.invalid_official_reports for leg in legs)}`.",
        f"- Statistically eligible OFFICIAL sweeps: "
        f"`{sum(len(leg.reports) for leg in legs)}`.",
        "- Closure samples are excluded from all pointwise and harmonic calculations.",
        "",
        "## Files produced",
        "",
        "- `run_metrics.csv`: one row per eligible OFFICIAL sweep.",
        "- `pointwise_curves.csv`: raw/centered curves, SD, selection rates, and A-B-A differences.",
        "- `harmonic_spectrum.csv`: all mechanical orders through Nyquist.",
        "- `extreme_points.csv`: top/bottom tail locations and repeat frequency.",
        "- `gate_results.csv` and `analysis_manifest.json`: machine-readable verdict.",
        "- Four PNG plots: raw, centered, A-B-A differential, and harmonic spectrum.",
        "",
        "## Interpretation boundary",
        "",
        "A PASS supports jig interchangeability for the current whole-system "
        "command-tracking measurand. It does not prove absolute MA600/motor "
        "nonlinearity without an independent angle reference.",
    ]
    if warnings:
        lines += ["", "## Warnings", ""]
        lines.extend(f"- {warning}" for warning in warnings)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def self_test() -> int:
    base = [0.0, 1.0, 0.0, -1.0]
    shifted = [1.0, 0.0, -1.0, 0.0]
    alignment = find_best_circular_alignment(base, shifted)
    assert alignment["best_shift_points"] == 3
    assert math.isclose(alignment["best_shift_correlation"], 1.0, abs_tol=1e-12)
    assert math.isclose(centered_rmse(base, base), 0.0, abs_tol=1e-12)
    means, sds = pointwise_mean_sd([base, base])
    assert means == base and sds == [0.0] * 4
    assert center_curve([1.0, 2.0, 3.0]) == [-1.0, 0.0, 1.0]
    assert math.isclose(pooled_within_leg_sd([[1.0, 2.0], [1.0, 2.0]]),
                        math.sqrt(0.5), abs_tol=1e-12)
    assert math.isclose(
        pooled_within_leg_sd([[0.0, 0.0], [10.0, 10.0], [5.0, 5.0]]),
        0.0,
        abs_tol=1e-12,
    ), "between-leg drift must not inflate pooled repeatability"
    print("[ OK ] NL pointwise-curve math/self-test passed.")
    return 0


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze a 360-point NL error curve with explicit A1-B-A2 legs.")
    parser.add_argument("--a1", nargs="+", type=Path,
                        help="A1 baseline log(s), same jig as A2")
    parser.add_argument("--b", nargs="+", type=Path,
                        help="B comparison-jig log(s)")
    parser.add_argument("--a2", nargs="+", type=Path,
                        help="A2 return-baseline log(s)")
    parser.add_argument("--out-dir", type=Path,
                        help="Output directory")
    parser.add_argument("--within-sd-limit", type=float, default=0.03)
    parser.add_argument("--remount-shift-limit", type=float, default=0.05)
    parser.add_argument("--minimum-cross-jig-limit", type=float, default=0.05)
    parser.add_argument("--repeatability-multiplier", type=float, default=2.77)
    parser.add_argument("--tail-limit", type=float, default=0.10)
    parser.add_argument("--correlation-min", type=float, default=0.98)
    parser.add_argument("--rmse-limit", type=float, default=0.10)
    parser.add_argument("--closure-limit", type=float, default=0.20)
    parser.add_argument("--highlight-orders", default="1,2,4,8,9,18,36")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if not args.self_test:
        missing = [
            name for name in ("a1", "b", "a2", "out_dir")
            if getattr(args, name) is None
        ]
        if missing:
            parser.error("required for analysis: " + ", ".join(
                f"--{name.replace('_', '-')}" for name in missing))
    return args


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    for path in args.a1 + args.b + args.a2:
        if not path.is_file():
            raise SystemExit(f"Input log not found: {path}")
    k = ROBUST_EXTREME_COUNT

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    thresholds = Thresholds(
        within_sd_limit_deg=args.within_sd_limit,
        remount_shift_limit_deg=args.remount_shift_limit,
        minimum_cross_jig_limit_deg=args.minimum_cross_jig_limit,
        repeatability_multiplier=args.repeatability_multiplier,
        tail_limit_deg=args.tail_limit,
        correlation_min=args.correlation_min,
        centered_rmse_limit_deg=args.rmse_limit,
        closure_limit_deg=args.closure_limit,
    )

    try:
        a1 = load_leg("A1", args.a1, k)
        b = load_leg("B", args.b, k)
        a2 = load_leg("A2", args.a2, k)
        analysis = build_analysis(a1, b, a2, thresholds)
    except ValueError as exc:
        raise SystemExit(f"Analysis rejected: {exc}") from exc

    legs = (a1, b, a2)
    summaries = [leg_summary(leg) for leg in legs]
    harmonics = harmonic_rows(legs)
    pointwise = pointwise_rows(a1, b, a2, analysis)
    extremes = extreme_rows(legs, k)
    runs = run_rows(legs, k)
    all_paths = args.a1 + args.b + args.a2
    config_health = inspect_config(all_paths)
    invalid_official_count = sum(leg.invalid_official_reports for leg in legs)
    analysis["gates"]["data_health"] = {
        "invalid_official_reports": invalid_official_count,
        "config_state": config_health["state"],
        "limit": "0 invalid OFFICIAL; CONFIG=PASS",
        "passed": (
            invalid_official_count == 0
            and config_health["state"] == "PASS"
        ),
    }
    analysis["gates"]["all_primary_gates"]["passed"] = all(
        gate["passed"]
        for name, gate in analysis["gates"].items()
        if name != "all_primary_gates"
    )
    gates = gate_rows(analysis)
    warnings = [warning for leg in legs for warning in leg.warnings]
    if a1.jig_id == b.jig_id:
        warnings.append("A and B report the same JigID; this is not a cross-jig study.")
    if any(len(leg.reports) < 3 for leg in legs):
        warnings.append("At least one leg has fewer than 3 eligible runs; SD/gates are low-confidence.")
    if config_health["state"] != "PASS":
        warnings.append(
            f"CONFIG health is {config_health['state']}; do not claim full data-health PASS.")

    write_csv(out_dir / "run_metrics.csv", runs)
    write_csv(out_dir / "leg_summary.csv", summaries)
    write_csv(out_dir / "pointwise_curves.csv", pointwise)
    write_csv(out_dir / "harmonic_spectrum.csv", harmonics)
    write_csv(out_dir / "extreme_points.csv", extremes)
    write_csv(out_dir / "gate_results.csv", gates)

    highlight_orders = [
        int(token.strip()) for token in args.highlight_orders.split(",")
        if token.strip()
    ]
    make_plots(out_dir, legs, analysis, harmonics, highlight_orders)
    write_report(
        out_dir / "nl_curve_report.md",
        legs, summaries, analysis, harmonics, config_health, warnings)

    manifest = {
        "tool": "analyze_nl_curve.py",
        "metric_contract": {
            "pointwise_quantity": "logged DATA.Error curve",
            "robust_nl": (
                f"mean(top {ROBUST_EXTREME_COUNT}) - "
                f"mean(bottom {ROBUST_EXTREME_COUNT}) per run"),
            "analysis_indices": f"0..{a1.analysis_points - 1}",
            "closure_index": a1.analysis_points,
            "closure_in_curve": False,
            "alignment_policy": (
                "zero-shift is primary; best circular alignment is diagnostic only"),
            "repeatability_pooling": (
                "within-leg variance only; A1-to-A2 drift is not pooled into SD"),
        },
        "inputs": {
            "A1": [str(path.resolve()) for path in args.a1],
            "B": [str(path.resolve()) for path in args.b],
            "A2": [str(path.resolve()) for path in args.a2],
        },
        "thresholds": asdict(thresholds),
        "leg_summary": summaries,
        "analysis": {
            key: value for key, value in analysis.items()
            if key not in {
                "a_raw_mean", "a_centered_mean", "b_aligned_centered_mean",
                "raw_diff", "centered_diff", "aligned_diff",
            }
        },
        "config_health": config_health,
        "warnings": warnings,
    }
    (out_dir / "analysis_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8")

    verdict = "PASS" if analysis["gates"]["all_primary_gates"]["passed"] else "FAIL"
    print(
        f"{analysis['motor_id']}: {verdict}; "
        f"NL B-A={analysis['nl_delta_b_minus_a_deg']:+.5f} deg; "
        f"r0={analysis['zero_shift_correlation']:.5f}; "
        f"RMSE0={analysis['zero_shift_centered_rmse_deg']:.5f} deg")
    print(f"Outputs: {out_dir.resolve()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
