#!/usr/bin/env python3
"""Analyze a Siglent SDS1000X-U oscilloscope waveform CSV export.

Handles the large multi-million-row exports this scope produces at deep
memory depth (tested up to 14M rows / ~400MB) via pandas' C parser, which
loads that size in a few seconds rather than minutes.

Parses the file's own header block (Record Length, Sample Interval,
Vertical Scale/Offset per channel, Horizontal Scale, Source channels) so
units/scale come from the capture itself, not assumptions. For a
digital-ish signal (e.g. the MOTOR_ENA GPIO line), detects each
low<->high transition via a 50%-of-range threshold with hysteresis,
reports transition timestamps, 10-90% edge duration, and the high/low
dwell time between consecutive edges -- exactly what's needed to confirm
a capture spans one full motor-active window (rising edge = enable,
falling edge = disable) before trusting it for further analysis.

Usage:
    python tools/analyze_scope_capture.py CAPTURE.csv
    python tools/analyze_scope_capture.py CAPTURE.csv --channel CH1
    python tools/analyze_scope_capture.py CAPTURE.csv --threshold 1.65
    python tools/analyze_scope_capture.py CAPTURE.csv --export-transitions edges.csv
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

import numpy as np
import pandas as pd


@dataclass
class ScopeHeader:
    record_length: int
    sample_interval_s: float
    horizontal_scale: float
    horizontal_units: str
    channels: List[str]
    vertical_units: dict
    vertical_scale: dict
    vertical_offset: dict
    model: str = ""
    serial: str = ""


@dataclass
class Transition:
    index: int
    time_s: float
    direction: str  # "RISING" or "FALLING"
    edge_duration_s: Optional[float]  # 10%-90% (or 90%-10%) crossing time


def parse_header(path: Path) -> tuple[ScopeHeader, int]:
    """Read the text header block, return (header, data_start_line_index)."""
    record_length = 0
    sample_interval_s = 0.0
    horizontal_scale = 0.0
    horizontal_units = ""
    channels: List[str] = []
    vertical_units: dict = {}
    vertical_scale: dict = {}
    vertical_offset: dict = {}
    model = ""
    serial = ""

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        line_index = 0
        for line in f:
            line_index += 1
            stripped = line.rstrip("\r\n")
            if stripped.startswith("Second,"):
                break
            fields = stripped.split(",")
            if not fields:
                continue
            key = fields[0].strip()
            if key == "Record Length":
                # "Analog:14000000"
                for part in fields[1:]:
                    part = part.strip()
                    if part.startswith("Analog:"):
                        record_length = int(part.split(":", 1)[1])
            elif key == "Sample Interval":
                for part in fields[1:]:
                    part = part.strip()
                    if part.startswith("Analog:"):
                        sample_interval_s = float(part.split(":", 1)[1])
            elif key == "Vertical Units":
                for part in fields[1:]:
                    part = part.strip()
                    if ":" in part:
                        ch, unit = part.split(":", 1)
                        vertical_units[ch.strip()] = unit.strip()
            elif key == "Vertical Scale":
                for part in fields[1:]:
                    part = part.strip()
                    if ":" in part:
                        ch, val = part.split(":", 1)
                        vertical_scale[ch.strip()] = float(val.strip())
            elif key == "Vertical Offset":
                for part in fields[1:]:
                    part = part.strip()
                    if ":" in part:
                        ch, val = part.split(":", 1)
                        vertical_offset[ch.strip()] = float(val.strip())
            elif key == "Horizontal Units":
                horizontal_units = fields[1].strip() if len(fields) > 1 else ""
            elif key == "Horizontal Scale":
                horizontal_scale = float(fields[1].strip()) if len(fields) > 1 else 0.0
            elif key == "Model Number":
                model = fields[1].strip() if len(fields) > 1 else ""
            elif key == "Serial Number":
                serial = fields[1].strip() if len(fields) > 1 else ""
            elif key == "Source":
                channels = [c.strip() for c in fields[1:] if c.strip()]

    header = ScopeHeader(
        record_length=record_length,
        sample_interval_s=sample_interval_s,
        horizontal_scale=horizontal_scale,
        horizontal_units=horizontal_units,
        channels=channels,
        vertical_units=vertical_units,
        vertical_scale=vertical_scale,
        vertical_offset=vertical_offset,
        model=model,
        serial=serial,
    )
    return header, line_index


def load_waveform(path: Path, header: ScopeHeader, data_start_line: int) -> pd.DataFrame:
    n_channels = max(1, len(header.channels))
    col_names = ["t"] + [f"v{i}" for i in range(n_channels)]
    df = pd.read_csv(
        path,
        skiprows=data_start_line,
        names=col_names,
        engine="c",
        dtype={c: "float64" for c in col_names},
    )
    return df


def detect_transitions(
    t: np.ndarray,
    v: np.ndarray,
    threshold: Optional[float] = None,
    smooth_s: Optional[float] = None,
    sample_interval_s: Optional[float] = None,
) -> List[Transition]:
    """Detect low<->high crossings of `v` around `threshold` (defaults to the
    midpoint of the observed min/max), vectorized with numpy (a pure-Python
    per-sample loop is far too slow at multi-million-row scope exports).

    A real GPIO edge (e.g. MOTOR_ENA) is one clean step held for a long
    time; fast PWM switching or ringing near the threshold otherwise
    produces thousands of spurious sub-microsecond transitions. To tell
    them apart, threshold detection runs on a moving-average-smoothed copy
    of `v` (window = `smooth_s`, default 1000x the sample interval) --
    smoothing averages out anything that doesn't hold for at least roughly
    that long, so only sustained transitions survive; edge duration is then
    measured against the *unsmoothed* signal for an accurate 10-90% time.
    """
    vmin, vmax = float(np.min(v)), float(np.max(v))
    span = vmax - vmin
    if threshold is None:
        threshold = (vmin + vmax) / 2.0

    # Prefer the scope header's declared sample interval over re-deriving it
    # from t[1]-t[0] -- floating-point noise in the CSV's scientific-notation
    # timestamps can otherwise make adjacent deltas inconsistent (seen in
    # practice: computed from data gave 0.0 for one real capture, silently
    # disabling smoothing entirely).
    if sample_interval_s is None or sample_interval_s <= 0:
        sample_interval_s = float(t[1] - t[0]) if len(t) > 1 else 0.0
    if smooth_s is None:
        smooth_s = sample_interval_s * 1000.0
    window = max(1, int(round(smooth_s / sample_interval_s))) if sample_interval_s > 0 else 1

    if window > 1:
        kernel = np.ones(window) / window
        # 'same'-length convolution; edges are less accurate but this tool
        # cares about transitions in the interior of a multi-million-sample
        # capture, not the first/last `window` samples.
        v_smooth = np.convolve(v, kernel, mode="same")
    else:
        v_smooth = v

    state = (v_smooth > threshold).astype(np.int8)
    change_points = np.flatnonzero(np.diff(state) != 0) + 1

    transitions: List[Transition] = []
    for i in change_points:
        direction = "RISING" if state[i] == 1 else "FALLING"
        transitions.append(Transition(index=int(i), time_s=float(t[i]), direction=direction, edge_duration_s=None))

    # Refine each transition's 10%-90% edge duration by walking outward
    # from the detected crossing index.
    lo10 = vmin + 0.1 * span
    hi90 = vmin + 0.9 * span
    for tr in transitions:
        i = tr.index
        if tr.direction == "RISING":
            i_lo = i
            while i_lo > 0 and v[i_lo] > lo10:
                i_lo -= 1
            i_hi = i
            while i_hi < len(v) - 1 and v[i_hi] < hi90:
                i_hi += 1
        else:
            i_lo = i
            while i_lo > 0 and v[i_lo] < hi90:
                i_lo -= 1
            i_hi = i
            while i_hi < len(v) - 1 and v[i_hi] > lo10:
                i_hi += 1
        tr.edge_duration_s = float(t[i_hi] - t[i_lo]) if i_hi > i_lo else None

    return transitions


def format_si_time(seconds: float) -> str:
    a = abs(seconds)
    if a >= 1.0:
        return f"{seconds:.6f} s"
    if a >= 1e-3:
        return f"{seconds * 1e3:.4f} ms"
    if a >= 1e-6:
        return f"{seconds * 1e6:.4f} us"
    return f"{seconds * 1e9:.4f} ns"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("csv_path", type=Path, help="Siglent waveform CSV export")
    parser.add_argument("--channel", default=None, help="Channel to analyze if the file has more than one (e.g. CH1). Defaults to the first channel.")
    parser.add_argument("--threshold", type=float, default=None, help="Digital threshold in volts (default: midpoint of observed min/max)")
    parser.add_argument("--smooth", type=float, default=None, help="Moving-average smoothing window in seconds before threshold detection (default: 1000x the sample interval). Increase this if fast switching noise near the threshold is still producing spurious transitions.")
    parser.add_argument("--max-print", type=int, default=40, help="Max transitions to print individually before switching to summary-only (default 40). Full list is always available via --export-transitions.")
    parser.add_argument("--export-transitions", type=Path, default=None, help="Write detected transitions to this CSV path")
    args = parser.parse_args()

    if not args.csv_path.exists():
        print(f"[FAIL] File not found: {args.csv_path}", file=sys.stderr)
        return 1

    header, data_start_line = parse_header(args.csv_path)

    print(f"=== {args.csv_path.name} ===")
    print(f"Model: {header.model}  Serial: {header.serial}")
    print(f"Record length: {header.record_length:,} points")
    print(f"Sample interval: {format_si_time(header.sample_interval_s)}  "
          f"(effective sample rate: {1.0 / header.sample_interval_s / 1e6:.3f} MSa/s)" if header.sample_interval_s else "")
    print(f"Horizontal scale: {header.horizontal_scale} {header.horizontal_units}/div  "
          f"(total window across 14 div: {format_si_time(header.horizontal_scale * (1e-6 if header.horizontal_units == 'us' else 1) * 14)})")
    print(f"Channels in file: {header.channels}")
    for ch in header.channels:
        print(f"  {ch}: unit={header.vertical_units.get(ch)}  scale={header.vertical_scale.get(ch)}/div  offset={header.vertical_offset.get(ch)}")

    df = load_waveform(args.csv_path, header, data_start_line)
    total_span = float(df["t"].iloc[-1] - df["t"].iloc[0])
    print(f"\nLoaded {len(df):,} samples. Actual time span in file: {format_si_time(total_span)}")

    channel_index = 0
    if args.channel and header.channels:
        try:
            channel_index = header.channels.index(args.channel)
        except ValueError:
            print(f"[WARN] Channel {args.channel} not found in {header.channels}; using first channel.")

    t = df["t"].to_numpy()
    v = df[f"v{channel_index}"].to_numpy()

    vmin, vmax = float(np.min(v)), float(np.max(v))
    vmean = float(np.mean(v))
    print(f"\nChannel value range: min={vmin:.4f}  max={vmax:.4f}  mean={vmean:.4f}")

    # Quick bimodality check: if the value spends most of its time near two
    # distinct levels, this looks like a real digital-ish signal worth
    # transition-detecting. If it's smeared across the full range, flag it.
    hist, edges = np.histogram(v, bins=20)
    top2 = np.argsort(hist)[-2:]
    frac_in_top2 = hist[top2].sum() / hist.sum()
    print(f"Fraction of samples in the 2 most common value bins: {frac_in_top2 * 100:.1f}% "
          f"({'looks digital/bimodal' if frac_in_top2 > 0.6 else 'NOT clearly bimodal -- may not be a clean digital signal, interpret transitions with caution'})")

    smooth_s = args.smooth if args.smooth is not None else header.sample_interval_s * 1000.0
    transitions = detect_transitions(t, v, threshold=args.threshold, smooth_s=smooth_s, sample_interval_s=header.sample_interval_s)
    print(f"\nDetected {len(transitions)} transition(s) after smoothing (window={format_si_time(smooth_s)}).")

    if len(transitions) > args.max_print:
        n_rising = sum(1 for tr in transitions if tr.direction == "RISING")
        n_falling = len(transitions) - n_rising
        dwells = [transitions[i].time_s - transitions[i - 1].time_s for i in range(1, len(transitions))]
        print(f"  Too many to print individually ({len(transitions)} > --max-print={args.max_print}). Summary:")
        print(f"  RISING={n_rising}  FALLING={n_falling}")
        if dwells:
            print(f"  Dwell between consecutive edges: min={format_si_time(min(dwells))}  "
                  f"max={format_si_time(max(dwells))}  mean={format_si_time(sum(dwells)/len(dwells))}")
        print(f"  This many transitions on a signal expected to be a single clean GPIO edge (e.g. MOTOR_ENA) "
              f"usually means either (a) --smooth needs to be larger, or (b) this channel is not actually "
              f"the clean digital signal you intended -- verify probe connection before trusting this capture.")
        print(f"  First 5:")
        for tr in transitions[:5]:
            edge_str = format_si_time(tr.edge_duration_s) if tr.edge_duration_s is not None else "n/a"
            print(f"    t={format_si_time(tr.time_s):>14}  {tr.direction:<8}  10-90% edge duration={edge_str}")
        print(f"  Last 5:")
        for tr in transitions[-5:]:
            edge_str = format_si_time(tr.edge_duration_s) if tr.edge_duration_s is not None else "n/a"
            print(f"    t={format_si_time(tr.time_s):>14}  {tr.direction:<8}  10-90% edge duration={edge_str}")
        print(f"  Use --export-transitions to get the full list, or increase --smooth to suppress noise.")
    else:
        prev_t = None
        for tr in transitions:
            dwell = f"  (dwell since prev edge: {format_si_time(tr.time_s - prev_t)})" if prev_t is not None else ""
            edge_str = format_si_time(tr.edge_duration_s) if tr.edge_duration_s is not None else "n/a"
            print(f"  t={format_si_time(tr.time_s):>14}  {tr.direction:<8}  10-90% edge duration={edge_str}{dwell}")
            prev_t = tr.time_s

    if args.export_transitions:
        with open(args.export_transitions, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["Index", "TimeSeconds", "Direction", "EdgeDurationSeconds"])
            for tr in transitions:
                w.writerow([tr.index, tr.time_s, tr.direction, tr.edge_duration_s])
        print(f"\n[ OK ] Transitions written to {args.export_transitions}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
