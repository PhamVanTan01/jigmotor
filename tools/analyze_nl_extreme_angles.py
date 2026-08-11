#!/usr/bin/env python3
"""Locate the angles that determine robust NL and compare them across jigs.

The input path is the same DATA/META/END log format consumed by
analyze_motor_logs.py. Only declared OFFICIAL + EligibleForStatistics sweeps
(or explicitly labeled legacy records without role fields) are used.

For every motor/jig group the tool:

* averages the point-by-point error curve over eligible runs;
* reports the top-K and bottom-K points that determine robust NL;
* counts how often each point is selected in the per-run top/bottom K;
* compares same-motor curves across jigs using circular cross-correlation.

Important: MA600 raw zero is local to each sensor/jig. Raw angle from JIG1 and
raw angle from JIG4 are not a shared mechanical datum. Cross-jig comparison
therefore uses sweep-relative angles and a reported best circular alignment;
it never claims that equal raw codes on different sensors are equal physical
angles.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import math
import re
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from analyze_motor_logs import (
    HARMONIC_ORDERS,
    SweepReport,
    build_report,
    compute_harmonic,
    load_sweeps,
)

# H4/H8 ("geometric" harmonics) are logged by firmware as phase-only fields
# (H4_PhaseSweepDeg/H8_PhaseSweepDeg) and are not part of analyze_motor_logs'
# HARMONIC_ORDERS (which mirrors firmware's NL_HARMONIC_ORDERS array used for
# the "motor" harmonic family, e.g. H36 = 6 x pole-pairs for the platform
# tested so far). Both families are computed here with the exact same
# compute_harmonic() formula so all 14 orders that appear anywhere in a
# RESULT line's H{n}_PhaseSweepDeg fields can be cross-checked and charted
# together, without editing analyze_motor_logs.py's own constant.
EXTRA_HARMONIC_ORDERS: Tuple[int, ...] = (4, 8)
ALL_HARMONIC_ORDERS: Tuple[int, ...] = tuple(
    sorted(set(HARMONIC_ORDERS) | set(EXTRA_HARMONIC_ORDERS)))

# Fixed categorical slot order (dataviz skill palette, validated ordering --
# see palette.md). JIG1/JIG4 keep reserved slots 1/2 since that is this
# project's primary comparison; any other label (e.g. per-remount groups)
# is assigned the next unused slot in sorted-label order, so a 3rd/4th group
# never silently collides with another group's color.
CATEGORICAL_PALETTE: Tuple[str, ...] = (
    "#2a78d6",  # slot 1 blue     (reserved: JIG1)
    "#eb6834",  # slot 2 orange   (reserved: JIG4)
    "#1baf7a",  # slot 3 aqua
    "#eda100",  # slot 4 yellow
    "#e87ba4",  # slot 5 magenta
    "#008300",  # slot 6 green
    "#4a3aa7",  # slot 7 violet
    "#e34948",  # slot 8 red
)
RESERVED_JIG_SLOTS: Dict[str, int] = {"JIG1": 0, "JIG4": 1}
CHART_SURFACE = "#fcfcfb"
CHART_INK_PRIMARY = "#0b0b0b"
CHART_INK_SECONDARY = "#52514e"
CHART_INK_MUTED = "#898781"
CHART_GRID = "#e1e0d9"
CHART_AXIS = "#c3c2b7"


def assign_jig_colors(jig_ids: Sequence[str]) -> Dict[str, str]:
    """Deterministic color per label for ONE render_charts() call: JIG1/JIG4
    keep their reserved slots when present; every other label gets the next
    unused slot in sorted order, so colors never depend on plot order and
    never repeat within the same set of labels."""
    assigned: Dict[str, str] = {}
    used_slots = set()
    for jig_id in jig_ids:
        if jig_id in RESERVED_JIG_SLOTS:
            slot = RESERVED_JIG_SLOTS[jig_id]
            assigned[jig_id] = CATEGORICAL_PALETTE[slot]
            used_slots.add(slot)
    next_slot = 0
    for jig_id in sorted(jig_ids):
        if jig_id in assigned:
            continue
        while next_slot in used_slots:
            next_slot += 1
        slot = next_slot if next_slot < len(CATEGORICAL_PALETTE) else len(CATEGORICAL_PALETTE) - 1
        assigned[jig_id] = CATEGORICAL_PALETTE[slot]
        used_slots.add(slot)
    return assigned


@dataclass
class GroupCurve:
    motor_id: str
    jig_id: str
    analysis_points: int
    reports: List[SweepReport]
    mean_error: List[float]
    sd_error: List[float]
    top_indices: List[int]
    bottom_indices: List[int]
    top_frequency: Counter
    bottom_frequency: Counter
    run_top_means: List[float]
    run_bottom_means: List[float]
    harmonic_amplitude_mean: Dict[int, float] = field(default_factory=dict)
    harmonic_amplitude_sd: Dict[int, float] = field(default_factory=dict)


def pearson(a: Sequence[float], b: Sequence[float]) -> float:
    if len(a) != len(b) or not a:
        return float("nan")
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    da = [x - ma for x in a]
    db = [x - mb for x in b]
    denom = math.sqrt(sum(x * x for x in da) * sum(x * x for x in db))
    if denom == 0.0:
        return float("nan")
    return sum(x * y for x, y in zip(da, db)) / denom


def centered_rmse(a: Sequence[float], b: Sequence[float]) -> float:
    ma = sum(a) / len(a)
    mb = sum(b) / len(b)
    return math.sqrt(sum(((x - ma) - (y - mb)) ** 2
                         for x, y in zip(a, b)) / len(a))


def circular_distance(a: int, b: int, n: int) -> int:
    delta = abs(a - b) % n
    return min(delta, n - delta)


def best_set_matching(a_indices: Sequence[int], b_indices: Sequence[int],
                      n: int) -> Tuple[float, int, Tuple[int, ...]]:
    """Minimum mean/max circular distance for two small equal-size sets."""
    if len(a_indices) != len(b_indices) or not a_indices:
        return float("nan"), -1, tuple()
    best: Optional[Tuple[int, int, Tuple[int, ...]]] = None
    for perm in itertools.permutations(b_indices):
        distances = [circular_distance(a, b, n)
                     for a, b in zip(a_indices, perm)]
        score = (sum(distances), max(distances), perm)
        if best is None or score[:2] < best[:2]:
            best = score
    assert best is not None
    return best[0] / len(a_indices), best[1], best[2]


def build_group_curve(motor_id: str, jig_id: str,
                      reports: List[SweepReport], k: int) -> GroupCurve:
    eligible = [r for r in reports if r.officially_valid and r.metrics]
    if not eligible:
        raise ValueError(f"{motor_id}/{jig_id}: no statistically eligible sweeps")
    counts = {r.sweep.analysis_point_count for r in eligible}
    if len(counts) != 1:
        raise ValueError(
            f"{motor_id}/{jig_id}: mixed AnalysisPoints values {sorted(counts)}")
    n = counts.pop()
    curves = [[r.sweep.points[i].error_deg for i in range(n)]
              for r in eligible]
    mean_error = [statistics.fmean(curve[i] for curve in curves)
                  for i in range(n)]
    sd_error = [
        statistics.stdev(curve[i] for curve in curves)
        if len(curves) > 1 else 0.0
        for i in range(n)
    ]
    k = min(max(k, 1), n)
    top_indices = sorted(range(n), key=lambda i: mean_error[i], reverse=True)[:k]
    bottom_indices = sorted(range(n), key=lambda i: mean_error[i])[:k]
    top_frequency: Counter = Counter()
    bottom_frequency: Counter = Counter()
    run_top_means: List[float] = []
    run_bottom_means: List[float] = []
    for curve in curves:
        run_top_indices = sorted(
            range(n), key=lambda i: curve[i], reverse=True)[:k]
        run_bottom_indices = sorted(range(n), key=lambda i: curve[i])[:k]
        top_frequency.update(run_top_indices)
        bottom_frequency.update(run_bottom_indices)
        run_top_means.append(statistics.fmean(curve[i] for i in run_top_indices))
        run_bottom_means.append(
            statistics.fmean(curve[i] for i in run_bottom_indices))

    # Per-sweep harmonic amplitude, aggregated mean/SD across eligible
    # sweeps -- same aggregation shape as robust NL (per-run first, then
    # statistics across runs), not computed from the already-averaged
    # mean_error curve. Orders already in a sweep's recomputed metrics
    # (analyze_motor_logs.HARMONIC_ORDERS) are reused as-is; H4/H8 are
    # computed here directly with the identical formula.
    harmonic_amplitude_mean: Dict[int, float] = {}
    harmonic_amplitude_sd: Dict[int, float] = {}
    for order in ALL_HARMONIC_ORDERS:
        per_sweep_amplitudes: List[float] = []
        for report, curve in zip(eligible, curves):
            if order in HARMONIC_ORDERS and report.metrics and order in report.metrics.harmonics:
                per_sweep_amplitudes.append(report.metrics.harmonics[order].amplitude)
            else:
                curve_mean = statistics.fmean(curve)
                per_sweep_amplitudes.append(
                    compute_harmonic(curve, curve_mean, order, n,
                                      report.sweep.step_raw).amplitude)
        harmonic_amplitude_mean[order] = statistics.fmean(per_sweep_amplitudes)
        harmonic_amplitude_sd[order] = (
            statistics.stdev(per_sweep_amplitudes)
            if len(per_sweep_amplitudes) > 1 else 0.0)

    return GroupCurve(
        motor_id=motor_id,
        jig_id=jig_id,
        analysis_points=n,
        reports=eligible,
        mean_error=mean_error,
        sd_error=sd_error,
        top_indices=top_indices,
        bottom_indices=bottom_indices,
        top_frequency=top_frequency,
        bottom_frequency=bottom_frequency,
        run_top_means=run_top_means,
        run_bottom_means=run_bottom_means,
        harmonic_amplitude_mean=harmonic_amplitude_mean,
        harmonic_amplitude_sd=harmonic_amplitude_sd,
    )


def compare_groups(a: GroupCurve, b: GroupCurve) -> Dict[str, object]:
    if a.analysis_points != b.analysis_points:
        raise ValueError(
            f"{a.motor_id}: cannot compare N={a.analysis_points} and "
            f"N={b.analysis_points}")
    n = a.analysis_points
    correlations: List[Tuple[float, int]] = []
    for shift in range(n):
        shifted_b = [b.mean_error[(i + shift) % n] for i in range(n)]
        correlations.append((pearson(a.mean_error, shifted_b), shift))
    correlations.sort(reverse=True)
    best_corr, best_shift = correlations[0]
    second_corr, second_shift = correlations[1]
    aligned_b = [b.mean_error[(i + best_shift) % n] for i in range(n)]

    # With b_aligned[i] = b[i+shift], an original B index j maps to
    # A-coordinate (j-shift) mod N.
    mapped_top_b = [(i - best_shift) % n for i in b.top_indices]
    mapped_bottom_b = [(i - best_shift) % n for i in b.bottom_indices]
    top_mean_dist, top_max_dist, _ = best_set_matching(
        a.top_indices, mapped_top_b, n)
    bottom_mean_dist, bottom_max_dist, _ = best_set_matching(
        a.bottom_indices, mapped_bottom_b, n)
    # Average each run's own tail mean. This preserves the firmware metric
    # identity exactly: mean(run_top-run_bottom) =
    # mean(run_top)-mean(run_bottom), even when tail membership changes.
    top_mean_a = statistics.fmean(a.run_top_means)
    top_mean_b = statistics.fmean(b.run_top_means)
    bottom_mean_a = statistics.fmean(a.run_bottom_means)
    bottom_mean_b = statistics.fmean(b.run_bottom_means)
    robust_a = top_mean_a - bottom_mean_a
    robust_b = top_mean_b - bottom_mean_b

    return {
        "motor_id": a.motor_id,
        "jig_a": a.jig_id,
        "jig_b": b.jig_id,
        "analysis_points": n,
        "runs_a": len(a.reports),
        "runs_b": len(b.reports),
        "zero_shift_correlation": pearson(a.mean_error, b.mean_error),
        "best_shift_deg": best_shift * 360.0 / n,
        "best_shift_points": best_shift,
        "best_shift_correlation": best_corr,
        "second_shift_deg": second_shift * 360.0 / n,
        "second_shift_correlation": second_corr,
        "correlation_margin": best_corr - second_corr,
        "shifts_within_0_001_of_best": sum(
            1 for corr, _ in correlations if best_corr - corr <= 0.001),
        "centered_rmse_zero_shift_deg": centered_rmse(
            a.mean_error, b.mean_error),
        "centered_rmse_aligned_deg": centered_rmse(
            a.mean_error, aligned_b),
        "top5_mean_a_deg": top_mean_a,
        "top5_mean_b_deg": top_mean_b,
        "top5_delta_b_minus_a_deg": top_mean_b - top_mean_a,
        "bottom5_mean_a_deg": bottom_mean_a,
        "bottom5_mean_b_deg": bottom_mean_b,
        "bottom5_delta_b_minus_a_deg": bottom_mean_b - bottom_mean_a,
        "robust_nl_a_deg": robust_a,
        "robust_nl_b_deg": robust_b,
        "robust_nl_delta_b_minus_a_deg": robust_b - robust_a,
        "top5_mean_distance_aligned_deg": top_mean_dist * 360.0 / n,
        "top5_max_distance_aligned_deg": top_max_dist * 360.0 / n,
        "bottom5_mean_distance_aligned_deg": bottom_mean_dist * 360.0 / n,
        "bottom5_max_distance_aligned_deg": bottom_max_dist * 360.0 / n,
    }


def write_extremes(groups: Sequence[GroupCurve], path: Path) -> None:
    fields = [
        "motor_id", "jig_id", "eligible_runs", "kind", "rank",
        "point_index", "sweep_angle_deg", "mean_error_deg", "sd_error_deg",
        "selection_count", "selection_rate",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for group in groups:
            for kind, indices, frequency in (
                    ("TOP", group.top_indices, group.top_frequency),
                    ("BOTTOM", group.bottom_indices, group.bottom_frequency)):
                for rank, index in enumerate(indices, start=1):
                    count = frequency[index]
                    writer.writerow({
                        "motor_id": group.motor_id,
                        "jig_id": group.jig_id,
                        "eligible_runs": len(group.reports),
                        "kind": kind,
                        "rank": rank,
                        "point_index": index,
                        "sweep_angle_deg": index * 360.0 / group.analysis_points,
                        "mean_error_deg": group.mean_error[index],
                        "sd_error_deg": group.sd_error[index],
                        "selection_count": count,
                        "selection_rate": count / len(group.reports),
                    })


def write_harmonics(groups: Sequence[GroupCurve], path: Path) -> None:
    fields = [
        "motor_id", "jig_id", "eligible_runs", "harmonic_order", "family",
        "amplitude_mean_deg", "amplitude_sd_deg",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for group in groups:
            for order in ALL_HARMONIC_ORDERS:
                writer.writerow({
                    "motor_id": group.motor_id,
                    "jig_id": group.jig_id,
                    "eligible_runs": len(group.reports),
                    "harmonic_order": order,
                    "family": "geometric" if order in (1, 2, 4, 8) else "motor",
                    "amplitude_mean_deg": group.harmonic_amplitude_mean[order],
                    "amplitude_sd_deg": group.harmonic_amplitude_sd[order],
                })


def write_pairs(rows: Sequence[Dict[str, object]], path: Path) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def fmt_indices(group: GroupCurve, indices: Iterable[int]) -> str:
    return ", ".join(
        f"{i * 360.0 / group.analysis_points:.0f}°"
        f"({group.mean_error[i]:+.4f}°)"
        for i in indices
    )


def write_report(groups: Sequence[GroupCurve],
                 pairs: Sequence[Dict[str, object]], path: Path) -> None:
    lines = [
        "# NL extreme-angle and cross-jig curve analysis",
        "",
        "Only statistically eligible sweeps are included. `DATA.Error` is used "
        "with its logged sign; robust NL is unchanged by reversing the sign.",
        "",
        "> MA600 raw zero is local to each sensor/jig. Equal raw codes across "
        "two jigs are not a shared physical angle. The comparison below uses "
        "sweep-relative angle and reports any circular alignment explicitly.",
        "",
        "## Extreme points on each batch-mean curve",
        "",
    ]
    for group in groups:
        top_selection_rate = statistics.fmean(
            group.top_frequency[i] / len(group.reports)
            for i in group.top_indices)
        bottom_selection_rate = statistics.fmean(
            group.bottom_frequency[i] / len(group.reports)
            for i in group.bottom_indices)
        lines.extend([
            f"### {group.motor_id} / {group.jig_id}",
            "",
            f"- Eligible runs: {len(group.reports)}",
            f"- Mean repeat-selection rate: top={top_selection_rate:.1%}, "
            f"bottom={bottom_selection_rate:.1%}",
            f"- Top 5: {fmt_indices(group, group.top_indices)}",
            f"- Bottom 5: {fmt_indices(group, group.bottom_indices)}",
            "",
        ])

    lines.extend([
        "## Same-motor cross-jig comparison",
        "",
        "Tail deltas below are differences between the batch means of each "
        "run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` "
        "matches the per-run robust-NL definition exactly.",
        "",
        "| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | "
        "Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | "
        "Bottom angle distance |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | "
        "---: | ---: |",
    ])
    for row in pairs:
        lines.append(
            f"| {row['motor_id']} | {row['jig_a']}→{row['jig_b']} | "
            f"{row['zero_shift_correlation']:.4f} | "
            f"{row['best_shift_deg']:.1f}° | "
            f"{row['best_shift_correlation']:.4f} | "
            f"{row['centered_rmse_aligned_deg']:.4f}° | "
            f"{row['top5_delta_b_minus_a_deg']:+.4f}° | "
            f"{row['bottom5_delta_b_minus_a_deg']:+.4f}° | "
            f"{row['robust_nl_delta_b_minus_a_deg']:+.4f}° | "
            f"{row['top5_mean_distance_aligned_deg']:.2f}° | "
            f"{row['bottom5_mean_distance_aligned_deg']:.2f}° |"
        )
    lines.extend([
        "",
        "Interpretation guard: high correlation after a shift supports a common "
        "periodic shape, but does not by itself assign that shape to the motor. "
        "Low correlation or large aligned extreme distances indicates a "
        "jig/mount/drive interaction or a localized event not preserved across "
        "the two setups.",
        "",
    ])
    path.write_text("\n".join(lines), encoding="utf-8")


def _style_axes(ax) -> None:
    ax.set_facecolor(CHART_SURFACE)
    ax.figure.set_facecolor(CHART_SURFACE)
    for spine_name, spine in ax.spines.items():
        if spine_name in ("top", "right"):
            spine.set_visible(False)
        else:
            spine.set_color(CHART_AXIS)
    ax.tick_params(colors=CHART_INK_SECONDARY, labelsize=9)
    ax.grid(True, color=CHART_GRID, linewidth=0.8, zorder=0)
    ax.set_axisbelow(True)
    ax.xaxis.label.set_color(CHART_INK_SECONDARY)
    ax.yaxis.label.set_color(CHART_INK_SECONDARY)
    ax.title.set_color(CHART_INK_PRIMARY)


def render_charts(groups: Sequence[GroupCurve], out_dir: Path) -> List[Path]:
    """Renders 3 static PNGs per motor (raw curve, centered mean+/-SD with
    tail markers, harmonic amplitude spectrum), overlaying every jig that
    has data for that motor. Colors are fixed per jig (JIG1/JIG4), never
    reassigned by which jig happens to be plotted first."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("WARN: matplotlib not available, skipping chart export",
              file=sys.stderr)
        return []

    charts_dir = out_dir / "charts"
    charts_dir.mkdir(parents=True, exist_ok=True)
    written: List[Path] = []

    by_motor: Dict[str, List[GroupCurve]] = defaultdict(list)
    for group in groups:
        by_motor[group.motor_id].append(group)

    for motor, motor_groups in sorted(by_motor.items()):
        motor_groups = sorted(motor_groups, key=lambda g: g.jig_id)
        colors = assign_jig_colors([g.jig_id for g in motor_groups])

        # --- Chart 1: raw error curve (DC offset kept) ---
        fig, ax = plt.subplots(figsize=(9, 4.5), dpi=150)
        for g in motor_groups:
            angles = [i * 360.0 / g.analysis_points for i in range(g.analysis_points)]
            ax.plot(angles, g.mean_error, color=colors[g.jig_id], linewidth=2,
                     label=f"{g.jig_id} (n={len(g.reports)})", zorder=3)
        ax.axhline(0, color=CHART_AXIS, linewidth=1, zorder=1)
        ax.set_xlim(0, motor_groups[0].analysis_points)
        ax.set_xlabel("Sweep angle (deg)")
        ax.set_ylabel("Raw error e(i) = measured - ideal (deg)")
        ax.set_title(f"{motor} -- raw error curve (batch mean, DC kept)")
        legend = ax.legend(frameon=False, labelcolor=CHART_INK_PRIMARY, fontsize=9)
        _style_axes(ax)
        fig.tight_layout()
        path = charts_dir / f"{motor}_raw_curve.png"
        fig.savefig(path, facecolor=CHART_SURFACE)
        plt.close(fig)
        written.append(path)

        # --- Chart 2: centered mean +/- SD, with top5/bottom5 markers ---
        fig, ax = plt.subplots(figsize=(9, 4.5), dpi=150)
        for g in motor_groups:
            n = g.analysis_points
            angles = [i * 360.0 / n for i in range(n)]
            gmean = statistics.fmean(g.mean_error)
            centered = [e - gmean for e in g.mean_error]
            color = colors[g.jig_id]
            ax.plot(angles, centered, color=color, linewidth=2,
                     label=f"{g.jig_id} (n={len(g.reports)})", zorder=3)
            upper = [c + sd for c, sd in zip(centered, g.sd_error)]
            lower = [c - sd for c, sd in zip(centered, g.sd_error)]
            ax.fill_between(angles, lower, upper, color=color, alpha=0.15,
                             linewidth=0, zorder=2)
            top_x = [i * 360.0 / n for i in g.top_indices]
            top_y = [centered[i] for i in g.top_indices]
            bottom_x = [i * 360.0 / n for i in g.bottom_indices]
            bottom_y = [centered[i] for i in g.bottom_indices]
            ax.scatter(top_x, top_y, marker="^", color=color, s=45,
                       edgecolors=CHART_INK_PRIMARY, linewidths=0.6, zorder=4)
            ax.scatter(bottom_x, bottom_y, marker="v", color=color, s=45,
                       edgecolors=CHART_INK_PRIMARY, linewidths=0.6, zorder=4)
        ax.axhline(0, color=CHART_AXIS, linewidth=1, zorder=1)
        ax.set_xlim(0, motor_groups[0].analysis_points)
        ax.set_xlabel("Sweep angle (deg)")
        ax.set_ylabel("Centered error, mean removed (deg)")
        ax.set_title(f"{motor} -- centered curve, mean +/-1SD band, "
                     "▲ top-5 / ▼ bottom-5")
        ax.legend(frameon=False, labelcolor=CHART_INK_PRIMARY, fontsize=9)
        _style_axes(ax)
        fig.tight_layout()
        path = charts_dir / f"{motor}_centered_curve.png"
        fig.savefig(path, facecolor=CHART_SURFACE)
        plt.close(fig)
        written.append(path)

        # --- Chart 3: harmonic amplitude spectrum ---
        fig, ax = plt.subplots(figsize=(9, 4.5), dpi=150)
        n_orders = len(ALL_HARMONIC_ORDERS)
        n_jigs = len(motor_groups)
        bar_width = 0.8 / max(n_jigs, 1)
        x = list(range(n_orders))
        for j, g in enumerate(motor_groups):
            offsets = [xi + (j - (n_jigs - 1) / 2.0) * bar_width for xi in x]
            heights = [g.harmonic_amplitude_mean[o] for o in ALL_HARMONIC_ORDERS]
            errs = [g.harmonic_amplitude_sd[o] for o in ALL_HARMONIC_ORDERS]
            ax.bar(offsets, heights, width=bar_width * 0.92,
                   color=colors[g.jig_id], label=f"{g.jig_id} (n={len(g.reports)})",
                   yerr=errs, capsize=2,
                   error_kw={"ecolor": CHART_INK_SECONDARY, "linewidth": 1},
                   zorder=3)
        ax.set_xticks(x)
        ax.set_xticklabels([f"H{o}" for o in ALL_HARMONIC_ORDERS], fontsize=8)
        ax.set_xlabel("Harmonic order (H1/H2/H4/H8 geometric, H9/H18/H36... motor)")
        ax.set_ylabel("Amplitude, mean +/-1SD across runs (deg)")
        ax.set_title(f"{motor} -- harmonic amplitude spectrum")
        ax.legend(frameon=False, labelcolor=CHART_INK_PRIMARY, fontsize=9)
        _style_axes(ax)
        ax.grid(axis="x", visible=False)
        fig.tight_layout()
        path = charts_dir / f"{motor}_harmonic_spectrum.png"
        fig.savefig(path, facecolor=CHART_SURFACE)
        plt.close(fig)
        written.append(path)

    return written


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logfiles", nargs="+", type=Path)
    parser.add_argument("--out-dir", type=Path,
                        default=Path("analysis-out/nl-extreme-angles"))
    parser.add_argument("--extreme-count", type=int, default=5)
    parser.add_argument("--no-charts", action="store_true",
                        help="skip PNG chart export, CSV/markdown only")
    parser.add_argument("--group-label-regex", type=str, default=None,
                        help="Same-jig studies (e.g. S1 remounts) log the "
                        "real, unchanged JigID in every file, so grouping "
                        "by JigID would merge all files into one group. If "
                        "set, this regex is matched against each file's "
                        "stem and its first capture group REPLACES that "
                        "file's jig grouping key (e.g. 'remount(\\d+)' on "
                        "S1-P03-JIG1-remount01.txt -> group key '01'). "
                        "Files that don't match keep their logged JigID.")
    parser.add_argument("--motor-label", type=str, default=None,
                        help="Override MotorID for every loaded sweep (e.g. "
                        "when the firmware build doesn't know the mounted "
                        "product and logs MotorID=UNKNOWN). Only safe when "
                        "every input file is known to be the same product.")
    args = parser.parse_args(argv)

    grouped: Dict[Tuple[str, str], List[SweepReport]] = defaultdict(list)
    warnings: List[str] = []
    for path in args.logfiles:
        sweeps, parse_warnings = load_sweeps(path)
        warnings.extend(parse_warnings)
        for sweep in sweeps:
            if args.motor_label:
                sweep.motor_id = args.motor_label
            if args.group_label_regex:
                match = re.search(args.group_label_regex, path.stem)
                if match:
                    sweep.jig_id = match.group(1)
            report = build_report(sweep)
            grouped[(sweep.motor_id or "UNKNOWN_MOTOR",
                     sweep.jig_id or "UNKNOWN_JIG")].append(report)
    if warnings:
        for warning in warnings:
            print(f"WARN: {warning}", file=sys.stderr)

    groups = [
        build_group_curve(motor, jig, reports, args.extreme_count)
        for (motor, jig), reports in sorted(grouped.items())
    ]
    by_motor: Dict[str, List[GroupCurve]] = defaultdict(list)
    for group in groups:
        by_motor[group.motor_id].append(group)
    pairs: List[Dict[str, object]] = []
    for motor, motor_groups in sorted(by_motor.items()):
        for a, b in itertools.combinations(
                sorted(motor_groups, key=lambda x: x.jig_id), 2):
            pairs.append(compare_groups(a, b))

    args.out_dir.mkdir(parents=True, exist_ok=True)
    extremes_path = args.out_dir / "extreme_points.csv"
    pairs_path = args.out_dir / "cross_jig_curve_comparison.csv"
    harmonics_path = args.out_dir / "harmonic_spectrum.csv"
    report_path = args.out_dir / "nl_extreme_angle_report.md"
    write_extremes(groups, extremes_path)
    write_pairs(pairs, pairs_path)
    write_harmonics(groups, harmonics_path)
    write_report(groups, pairs, report_path)
    print(f"Wrote {extremes_path}")
    print(f"Wrote {pairs_path}")
    print(f"Wrote {harmonics_path}")
    print(f"Wrote {report_path}")
    if not args.no_charts:
        chart_paths = render_charts(groups, args.out_dir)
        for path in chart_paths:
            print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
