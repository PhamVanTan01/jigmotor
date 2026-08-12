"""Post-save NL and polar quality charts for one motor's E(theta) log.

Generates a Cartesian NL PNG and a polar PNG next to a saved log. Both use
the per-angle error curve averaged across OFFICIAL sweeps (falls back to
every sweep if none are marked OFFICIAL, e.g. legacy pre-role logs). If
the log also carries SWEEP_CREEP_POINT telemetry (ENABLE_SWEEP_POINT_CREEP
firmware builds), a second polar panel shows the per-point initial
correction gap (control effort) so an operator can see at a glance
whether the harder-to-reach points line up with the error bulges. If the
log additionally carries SWEEP_POINT_TIMING telemetry (DWT-timing
diagnostic builds, e.g. V5.7/V5.8), a third panel shows time-to-deadband
per point with a red marker, at its true value, on every angle where at
least one official sweep exceeded the response-time budget
(ReachedDeadband=0) -- i.e. the angles that took too long to settle.
Panels are added only when their source telemetry is present in the log;
a normal production build with no creep/timing diagnostics still gets
panel 1 alone.

Every panel also carries a pair of red dashed radial lines at the two
order-2 (twice-per-revolution) peak angles of this log's own error curve
-- i.e. where a real eccentricity/tilt defect that rotates WITH the rotor
would show up twice per turn. This is the same "motor-locked angle"
marker as the MATLAB multi-file comparison chart, just derived from a
single log instead of a chosen reference file.

Same diagnostic used in
analysis/matlab/nl/plot_v58_motor_quality_polar.m, reimplemented here in
pure Python/matplotlib so it runs automatically right after
stm32_uart_flasher.py saves a capture, with no MATLAB needed.

Runs headless (Agg backend) so it is safe to call from the flasher's
background save/analyze thread while the Tk mainloop is on the main
thread.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402  (backend must be set first)

import analyze_motor_logs as motor_analyzer  # noqa: E402

ANALYSIS_POINTS = 360
SMOOTH_WINDOW = 9


def _circular_smooth(values: Sequence[Optional[float]], window: int) -> List[Optional[float]]:
    n = len(values)
    half = window // 2
    out: List[Optional[float]] = [None] * n
    for i in range(n):
        acc = 0.0
        cnt = 0
        for k in range(-half, half + 1):
            v = values[(i + k) % n]
            if v is not None:
                acc += v
                cnt += 1
        out[i] = acc / cnt if cnt else None
    return out


def _order2_locked_angles(err_centered: Sequence[Optional[float]]) -> Optional[Tuple[float, float]]:
    """Two angles (deg, 180 deg apart) of the order-2 (twice-per-revolution)
    peak of a DC-removed error curve -- the direction of a real
    eccentricity/tilt defect that rotates WITH the rotor.

    Mirrors analysis/matlab/nl/plot_v58_motor_quality_polar.m's
    motorLockedAnglesDeg computation exactly (same a/b/atan2 formula on the
    unsmoothed, DC-removed curve). Returns None if there is no usable data
    (e.g. every point missing).
    """
    a = 0.0
    b = 0.0
    have_any = False
    for idx, v in enumerate(err_centered):
        if v is None:
            continue
        have_any = True
        rad = math.radians(2 * idx)
        a += v * math.cos(rad)
        b += v * math.sin(rad)
    if not have_any:
        return None
    phi2 = math.degrees(math.atan2(b, a)) / 2.0
    return (phi2 % 360.0, (phi2 + 180.0) % 360.0)


def _draw_locked_angle_lines(ax: "plt.PolarAxes", locked_angles: Optional[Tuple[float, float]]) -> None:
    """Draw the two order-2 motor-locked-angle markers as red dashed radial
    lines spanning the axis's own radial limit, matching the MATLAB chart.
    Must be called after the axis's main curve is plotted, so the radial
    limit has already been auto-scaled to that data.
    """
    if locked_angles is None:
        return
    r_max = ax.get_ylim()[1]
    for angle_deg in locked_angles:
        rad = math.radians(angle_deg)
        ax.plot([rad, rad], [0.0, r_max], "r--", linewidth=1.2)


def _mean_official_error_curve(sweeps: Sequence[motor_analyzer.Sweep]) -> List[Optional[float]]:
    sums = [0.0] * ANALYSIS_POINTS
    counts = [0] * ANALYSIS_POINTS
    for sw in _official_sweeps(sweeps):
        for idx, pt in sw.points.items():
            if 0 <= idx < ANALYSIS_POINTS:
                sums[idx] += pt.error_deg
                counts[idx] += 1
    return [sums[i] / counts[i] if counts[i] else None for i in range(ANALYSIS_POINTS)]


def _official_sweeps(sweeps: Sequence[motor_analyzer.Sweep]) -> List[motor_analyzer.Sweep]:
    """Select declared OFFICIAL sweeps; only schema-v4/v5 may fall back.

    Schema v6 requires explicit RunRole/EligibleForStatistics. Treat a v6
    file with missing role fields as corrupted telemetry, never as legacy;
    otherwise a truncated PRECONDITION META could contaminate the chart.
    """
    official = [sweep for sweep in sweeps if sweep.run_role == "OFFICIAL"]
    if official:
        return official
    if any((sweep.schema_version or 0) >= 6 for sweep in sweeps):
        return []
    return list(sweeps)


def generate_nl_curve_chart(
    log_path: Path, output_path: Optional[Path] = None
) -> Optional[Path]:
    """Render the 360-point open-loop NL curve as a Cartesian PNG.

    Every OFFICIAL sweep is shown as a thin trace and their pointwise mean
    as the bold trace. Schema-v6 values are canonical ErrorRawQ16 values
    converted by analyze_motor_logs, matching firmware OpenLoopNL_Deg.
    """
    sweeps, _warnings = motor_analyzer.load_sweeps(log_path)
    selected = _official_sweeps(sweeps)
    if not selected:
        return None

    curves: List[List[Optional[float]]] = []
    for sweep in selected:
        curve: List[Optional[float]] = [None] * ANALYSIS_POINTS
        for index, point in sweep.points.items():
            if 0 <= index < ANALYSIS_POINTS:
                curve[index] = point.error_deg
        if any(value is not None for value in curve):
            curves.append(curve)
    if not curves:
        return None

    mean_curve = _mean_official_error_curve(sweeps)
    valid_mean = [(index, value) for index, value in enumerate(mean_curve)
                  if value is not None]
    if not valid_mean:
        return None

    fig, ax = plt.subplots(figsize=(12, 6.5))
    for run_index, curve in enumerate(curves, start=1):
        x_values = [index for index, value in enumerate(curve) if value is not None]
        y_values = [value for value in curve if value is not None]
        ax.plot(x_values, y_values, linewidth=0.8, alpha=0.28,
                label=f"official {run_index}")

    mean_x = [item[0] for item in valid_mean]
    mean_y = [item[1] for item in valid_mean]
    ax.plot(mean_x, mean_y, color="black", linewidth=2.0, label="official mean")
    max_index, max_value = max(valid_mean, key=lambda item: item[1])
    min_index, min_value = min(valid_mean, key=lambda item: item[1])
    open_loop_nl = max_value - min_value
    ax.scatter([max_index, min_index], [max_value, min_value],
               color=["tab:red", "tab:blue"], zorder=5)
    ax.annotate(f"max {max_value:+.4f} deg @ {max_index} deg",
                (max_index, max_value))
    ax.annotate(f"min {min_value:+.4f} deg @ {min_index} deg",
                (min_index, min_value))
    ax.axhline(0.0, color="gray", linewidth=0.8)
    ax.set_xlim(0, ANALYSIS_POINTS - 1)
    ax.set_xlabel("Mechanical angle / point index (deg)")
    ax.set_ylabel("Open-loop error E(theta) (deg)")
    ax.set_title(
        f"Open-loop NL curve -- {log_path.name}\n"
        f"mean RawP2P = {open_loop_nl:.5f} deg"
    )
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best", fontsize=8)
    fig.tight_layout()

    if output_path is None:
        output_path = log_path.with_name(log_path.stem + ".nl.png")
    fig.savefig(output_path, dpi=150)
    plt.close(fig)
    return output_path


def _parse_sweep_creep_gap(
    log_path: Path, precondition_keys: Set[Tuple[int, int]]
) -> Optional[List[Optional[float]]]:
    """Average InitialAbsGapRaw per Point from SWEEP_CREEP_POINT records.

    Returns None (not a zero-filled curve) if the log has no such records
    at all, so the caller can skip the second panel entirely instead of
    drawing a misleading flat line.
    """
    sums = [0.0] * ANALYSIS_POINTS
    counts = [0] * ANALYSIS_POINTS
    found = False
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("SWEEP_CREEP_POINT,"):
                continue
            found = True
            fields: Dict[str, str] = {}
            for tok in line.rstrip("\r\n").split(",")[1:]:
                if "=" in tok:
                    key, _, value = tok.partition("=")
                    fields[key] = value
            try:
                test_id = int(fields["TestID"])
                sweep_id = int(fields["SweepID"])
                point = int(fields["Point"])
                gap = float(fields["InitialAbsGapRaw"])
            except (KeyError, ValueError):
                continue
            if (test_id, sweep_id) in precondition_keys:
                continue
            if 0 <= point < ANALYSIS_POINTS:
                sums[point] += gap
                counts[point] += 1
    if not found:
        return None
    return [sums[i] / counts[i] if counts[i] else None for i in range(ANALYSIS_POINTS)]


def _parse_sweep_point_timing(
    log_path: Path, precondition_keys: Set[Tuple[int, int]]
) -> Optional[Tuple[List[Optional[float]], List[Optional[float]]]]:
    """Per-point (mean TimeToDeadbandMs, ReachedDeadband rate 0..1) from
    SWEEP_POINT_TIMING records -- only present on DWT-timing diagnostic
    builds (V5.7/V5.8-style), so this returns None on ordinary logs and
    the caller skips the "exceeded time budget" panel entirely.
    """
    time_sums = [0.0] * ANALYSIS_POINTS
    time_counts = [0] * ANALYSIS_POINTS
    reached_sums = [0.0] * ANALYSIS_POINTS
    reached_counts = [0] * ANALYSIS_POINTS
    found = False
    with log_path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.startswith("SWEEP_POINT_TIMING,"):
                continue
            found = True
            fields: Dict[str, str] = {}
            for tok in line.rstrip("\r\n").split(",")[1:]:
                if "=" in tok:
                    key, _, value = tok.partition("=")
                    fields[key] = value
            try:
                test_id = int(fields["TestID"])
                sweep_id = int(fields["SweepID"])
                point = int(fields["Point"])
            except (KeyError, ValueError):
                continue
            if (test_id, sweep_id) in precondition_keys:
                continue
            if not (0 <= point < ANALYSIS_POINTS):
                continue
            reached_raw = fields.get("ReachedDeadband")
            if reached_raw in ("0", "1"):
                reached_sums[point] += float(reached_raw)
                reached_counts[point] += 1
            try:
                clock_hz = float(fields["ClockHz"])
                cycles = float(fields["TimeToDeadbandCycles"])
            except (KeyError, ValueError):
                continue
            if clock_hz > 0:
                time_sums[point] += 1000.0 * cycles / clock_hz
                time_counts[point] += 1
    if not found:
        return None
    time_curve = [time_sums[i] / time_counts[i] if time_counts[i] else None for i in range(ANALYSIS_POINTS)]
    reached_curve = [
        reached_sums[i] / reached_counts[i] if reached_counts[i] else None for i in range(ANALYSIS_POINTS)
    ]
    return time_curve, reached_curve


def generate_polar_quality_chart(
    log_path: Path, output_path: Optional[Path] = None
) -> Optional[Path]:
    """Parse one saved log and render its polar quality fingerprint PNG.

    Returns the PNG path, or None if the log has no usable DATA points
    (e.g. a genuinely INCOMPLETE capture with zero full sweeps) -- callers
    should treat None as "nothing to plot", not an error.
    """
    sweeps, _warnings = motor_analyzer.load_sweeps(log_path)
    if not sweeps:
        return None

    err_curve = _mean_official_error_curve(sweeps)
    valid_err = [v for v in err_curve if v is not None]
    if not valid_err:
        return None

    precondition_keys = {
        (sw.test_id, sw.sweep_id)
        for sw in sweeps
        if sw.run_role == "PRECONDITION" and sw.test_id is not None and sw.sweep_id is not None
    }
    gap_curve = _parse_sweep_creep_gap(log_path, precondition_keys)
    timing = _parse_sweep_point_timing(log_path, precondition_keys)
    time_curve, reached_curve = timing if timing is not None else (None, None)

    theta = [2 * math.pi * i / ANALYSIS_POINTS for i in range(ANALYSIS_POINTS)]

    err_mean = sum(valid_err) / len(valid_err)
    err_centered = [(v - err_mean) if v is not None else None for v in err_curve]
    locked_angles = _order2_locked_angles(err_centered)
    err_smooth = _circular_smooth(err_centered, SMOOTH_WINDOW)
    valid_smooth = [v for v in err_smooth if v is not None]
    floor = min(valid_smooth)
    span = max(valid_smooth) - floor
    pad = 0.02 * span if span > 0 else 0.01
    err_radius = [(v - floor + pad) if v is not None else 0.0 for v in err_smooth]

    n_panels = 1 + (gap_curve is not None) + (time_curve is not None)
    fig = plt.figure(figsize=(7 * n_panels, 6.5))
    panel = 1

    ax1 = fig.add_subplot(1, n_panels, panel, projection="polar")
    panel += 1
    ax1.plot(theta, err_radius, linewidth=2, color="tab:blue")
    ax1.set_theta_zero_location("N")
    ax1.set_theta_direction(-1)
    _draw_locked_angle_lines(ax1, locked_angles)
    ax1.set_title("Error curve E(theta)\n(smoothed, DC-removed, offset radius)")

    if gap_curve is not None:
        gap_smooth = _circular_smooth(gap_curve, SMOOTH_WINDOW)
        gap_plot = [v if v is not None else 0.0 for v in gap_smooth]
        ax2 = fig.add_subplot(1, n_panels, panel, projection="polar")
        panel += 1
        ax2.plot(theta, gap_plot, linewidth=2, color="tab:orange")
        ax2.set_theta_zero_location("N")
        ax2.set_theta_direction(-1)
        _draw_locked_angle_lines(ax2, locked_angles)
        ax2.set_title("Initial correction gap per point\n(raw ticks, control effort)")

    if time_curve is not None:
        time_smooth = _circular_smooth(time_curve, SMOOTH_WINDOW)
        time_plot = [v if v is not None else 0.0 for v in time_smooth]
        timeout_theta = [
            theta[i]
            for i in range(ANALYSIS_POINTS)
            if reached_curve[i] is not None and reached_curve[i] < 1.0
        ]
        timeout_radius = [
            time_curve[i]
            for i in range(ANALYSIS_POINTS)
            if reached_curve[i] is not None and reached_curve[i] < 1.0
        ]
        ax3 = fig.add_subplot(1, n_panels, panel, projection="polar")
        panel += 1
        ax3.plot(theta, time_plot, linewidth=2, color="tab:green")
        if timeout_theta:
            ax3.plot(
                timeout_theta,
                timeout_radius,
                "o",
                markersize=7,
                markerfacecolor="tab:red",
                markeredgecolor="black",
                linestyle="none",
                label="exceeded time budget (ReachedDeadband<100%)",
            )
            ax3.legend(loc="lower center", bbox_to_anchor=(0.5, -0.15), fontsize=8)
        ax3.set_theta_zero_location("N")
        ax3.set_theta_direction(-1)
        _draw_locked_angle_lines(ax3, locked_angles)
        ax3.set_title("Time to deadband per point (ms)\nred = exceeded time budget at that angle")

    motor_id = next((sw.motor_id for sw in sweeps if sw.motor_id and sw.motor_id != "UNKNOWN"), None)
    jig_id = next((sw.jig_id for sw in sweeps if sw.jig_id and sw.jig_id != "UNKNOWN"), None)
    tag = " ".join(part for part in [f"motor={motor_id}" if motor_id else "", f"jig={jig_id}" if jig_id else ""] if part)
    title = f"Motor quality fingerprint -- {log_path.name}" + (f"  ({tag})" if tag else "")
    if locked_angles is not None:
        title += f"\nred dashed = motor-locked tilt/eccentricity angles ({locked_angles[0]:.0f} deg, {locked_angles[1]:.0f} deg)"
    fig.suptitle(title)
    fig.tight_layout()

    if output_path is None:
        output_path = log_path.with_name(log_path.stem + ".polar.png")
    fig.savefig(output_path, dpi=150)
    plt.close(fig)
    return output_path
