"""Post-save polar quality chart for one motor's log -- E(theta) fingerprint.

Generates a single PNG next to a saved log: a polar plot of the per-angle
error curve, averaged across the file's OFFICIAL sweeps (falls back to
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
panel 1 alone. Same diagnostic used in
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


def _mean_official_error_curve(sweeps: Sequence[motor_analyzer.Sweep]) -> List[Optional[float]]:
    sums = [0.0] * ANALYSIS_POINTS
    counts = [0] * ANALYSIS_POINTS
    has_official = any(sw.run_role == "OFFICIAL" for sw in sweeps)
    for sw in sweeps:
        if has_official and sw.run_role != "OFFICIAL":
            continue
        for idx, pt in sw.points.items():
            if 0 <= idx < ANALYSIS_POINTS:
                sums[idx] += pt.error_deg
                counts[idx] += 1
    return [sums[i] / counts[i] if counts[i] else None for i in range(ANALYSIS_POINTS)]


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
    ax1.set_title("Error curve E(theta)\n(smoothed, DC-removed, offset radius)")

    if gap_curve is not None:
        gap_smooth = _circular_smooth(gap_curve, SMOOTH_WINDOW)
        gap_plot = [v if v is not None else 0.0 for v in gap_smooth]
        ax2 = fig.add_subplot(1, n_panels, panel, projection="polar")
        panel += 1
        ax2.plot(theta, gap_plot, linewidth=2, color="tab:orange")
        ax2.set_theta_zero_location("N")
        ax2.set_theta_direction(-1)
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
        ax3.set_title("Time to deadband per point (ms)\nred = exceeded time budget at that angle")

    motor_id = next((sw.motor_id for sw in sweeps if sw.motor_id and sw.motor_id != "UNKNOWN"), None)
    jig_id = next((sw.jig_id for sw in sweeps if sw.jig_id and sw.jig_id != "UNKNOWN"), None)
    tag = " ".join(part for part in [f"motor={motor_id}" if motor_id else "", f"jig={jig_id}" if jig_id else ""] if part)
    fig.suptitle(f"Motor quality fingerprint -- {log_path.name}" + (f"  ({tag})" if tag else ""))
    fig.tight_layout()

    if output_path is None:
        output_path = log_path.with_name(log_path.stem + ".polar.png")
    fig.savefig(output_path, dpi=150)
    plt.close(fig)
    return output_path
