#!/usr/bin/env python3
"""Find repeatable rules inside one 360-degree jigmotor DATA sweep.

The analysis works on the first ``META.AnalysisPoints`` DATA rows of each valid
official sweep.  It reports the full harmonic spectrum, reconstructs the curve
from selected harmonics, and folds a revolution by the dominant periodic order
to show whether successive mechanical sectors repeat.

With no arguments, the P03/JIG1 test-20 A1/B/A2 logs in the current directory
are discovered automatically.
"""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from analyze_nl_stability import (
    MetricRun,
    infer_default_logs,
    infer_leg,
    load_sweeps,
    validate_and_compute,
)


EXTENDED_ORDERS = (1, 2, 3, 6, 9, 12, 18, 27, 36, 45, 72, 108)
ELECTRICAL_FAMILY = (36, 72, 108)


@dataclass
class Harmonic:
    order: int
    a: float
    b: float
    amplitude: float
    phase_deg: float
    energy_ratio: float


def coefficients(errors: Sequence[float], order: int) -> Tuple[float, float]:
    n = len(errors)
    mean = statistics.fmean(errors)
    a = 0.0
    b = 0.0
    for index, value in enumerate(errors):
        phase = 2.0 * math.pi * order * index / n
        centered = value - mean
        a += centered * math.cos(phase)
        b += centered * math.sin(phase)
    return 2.0 * a / n, 2.0 * b / n


def spectrum(errors: Sequence[float]) -> Dict[int, Harmonic]:
    mean = statistics.fmean(errors)
    variance = statistics.fmean((value - mean) ** 2 for value in errors)
    result: Dict[int, Harmonic] = {}
    # Nyquist (N/2) uses a different one-sided energy convention, so omit it.
    for order in range(1, len(errors) // 2):
        a, b = coefficients(errors, order)
        amplitude = math.hypot(a, b)
        result[order] = Harmonic(
            order=order,
            a=a,
            b=b,
            amplitude=amplitude,
            phase_deg=math.degrees(math.atan2(b, a)),
            energy_ratio=(0.5 * amplitude * amplitude / variance if variance > 0.0 else 0.0),
        )
    return result


def reconstruct(errors: Sequence[float], spec: Dict[int, Harmonic], orders: Sequence[int]) -> List[float]:
    mean = statistics.fmean(errors)
    n = len(errors)
    values: List[float] = []
    for index in range(n):
        value = mean
        for order in orders:
            harmonic = spec.get(order)
            if harmonic is None:
                continue
            phase = 2.0 * math.pi * order * index / n
            value += harmonic.a * math.cos(phase) + harmonic.b * math.sin(phase)
        values.append(value)
    return values


def explained_ratio(errors: Sequence[float], fitted: Sequence[float]) -> float:
    mean = statistics.fmean(errors)
    total = sum((value - mean) ** 2 for value in errors)
    residual = sum((value - estimate) ** 2 for value, estimate in zip(errors, fitted))
    return 1.0 - residual / total if total > 0.0 else 1.0


def fold_by_order(errors: Sequence[float], order: int) -> Tuple[List[List[float]], List[float], float]:
    if len(errors) % order != 0:
        raise ValueError(f"{len(errors)} points cannot be folded into {order} equal cycles")
    width = len(errors) // order
    mean = statistics.fmean(errors)
    centered = [value - mean for value in errors]
    cycles = [centered[index * width:(index + 1) * width] for index in range(order)]
    template = [statistics.fmean(cycle[index] for cycle in cycles) for index in range(width)]
    total = sum(value * value for value in centered)
    residual = sum((cycle[index] - template[index]) ** 2
                   for cycle in cycles for index in range(width))
    ratio = 1.0 - residual / total if total > 0.0 else 1.0
    return cycles, template, ratio


def load_official_runs(logfiles: Sequence[Path], labels: Optional[Sequence[str]]) -> List[MetricRun]:
    runs: List[MetricRun] = []
    for file_index, path in enumerate(logfiles):
        leg = labels[file_index] if labels else infer_leg(path, file_index)
        sweeps, _ = load_sweeps(path, leg, file_index)
        for sweep in sweeps:
            metric_run, _ = validate_and_compute(sweep, include_precondition=False)
            if metric_run is not None:
                runs.append(metric_run)
    runs.sort(key=lambda run: (
        run.sweep.file_index,
        run.sweep.run_order if run.sweep.run_order is not None else 10**9,
        run.sweep.test_id,
    ))
    return runs


def circular_summary(harmonics: Sequence[Harmonic]) -> Tuple[float, float]:
    vectors = [(h.a / h.amplitude, h.b / h.amplitude)
               for h in harmonics if h.amplitude > 0.0]
    if not vectors:
        return 0.0, 0.0
    x = statistics.fmean(vector[0] for vector in vectors)
    y = statistics.fmean(vector[1] for vector in vectors)
    return math.degrees(math.atan2(y, x)), math.hypot(x, y)


def harmonic_rows(runs: Sequence[MetricRun], spectra: Sequence[Dict[int, Harmonic]]) -> List[Dict[str, object]]:
    groups: List[Tuple[str, List[int]]] = [("ALL", list(range(len(runs))))]
    for leg in dict.fromkeys(run.sweep.leg for run in runs):
        groups.append((leg, [i for i, run in enumerate(runs) if run.sweep.leg == leg]))
    rows: List[Dict[str, object]] = []
    for group, indices in groups:
        for order in range(1, len(runs[indices[0]].errors) // 2):
            harmonics = [spectra[index][order] for index in indices]
            amplitudes = [harmonic.amplitude for harmonic in harmonics]
            phase, coherence = circular_summary(harmonics)
            rows.append({
                "Group": group,
                "Order": order,
                "PeriodMechanicalDeg": 360.0 / order,
                "AmplitudeMeanDeg": statistics.fmean(amplitudes),
                "AmplitudeSDDeg": statistics.stdev(amplitudes) if len(amplitudes) > 1 else 0.0,
                "EnergyRatioMean": statistics.fmean(h.energy_ratio for h in harmonics),
                "PhaseCircularMeanDeg": phase,
                "PhaseCoherence": coherence,
            })
    return rows


def write_csv(path: Path, rows: Sequence[Dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def plot_spectrum(rows: Sequence[Dict[str, object]], out_path: Path) -> None:
    pooled = [row for row in rows if row["Group"] == "ALL"]
    orders = [int(row["Order"]) for row in pooled]
    amplitudes = [float(row["AmplitudeMeanDeg"]) for row in pooled]
    fig, ax = plt.subplots(figsize=(12, 5.8))
    ax.plot(orders, amplitudes, color="#777777", linewidth=0.8)
    ax.scatter(orders, amplitudes, color="#777777", s=10)
    for color, order in zip(("#d62728", "#ff7f0e", "#9467bd"), ELECTRICAL_FAMILY):
        row = pooled[order - 1]
        amplitude = float(row["AmplitudeMeanDeg"])
        ax.scatter([order], [amplitude], color=color, s=58, zorder=4)
        offset = (10, -36) if order == 36 else (8, 8)
        ax.annotate(f"H{order}={amplitude:.3f}°\nperiod={360/order:.1f}°",
                    (order, amplitude), xytext=offset, textcoords="offset points", fontsize=9)
    ax.set_xlim(0, 120)
    ax.set_xlabel("Harmonic order per mechanical revolution")
    ax.set_ylabel("Mean amplitude (deg)")
    ax.set_title("Full harmonic spectrum across official input sweeps")
    ax.grid(True, alpha=0.23)
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_reconstruction(run: MetricRun, spec: Dict[int, Harmonic], out_path: Path) -> None:
    errors = run.errors
    x = [360.0 * index / len(errors) for index in range(len(errors))]
    fit36 = reconstruct(errors, spec, (36,))
    fit_family = reconstruct(errors, spec, ELECTRICAL_FAMILY)
    fit_extended = reconstruct(errors, spec, EXTENDED_ORDERS)
    fig, (ax, residual_ax) = plt.subplots(2, 1, figsize=(13, 8), sharex=True,
                                          gridspec_kw={"height_ratios": [2, 1]})
    ax.plot(x, errors, color="#1f77b4", linewidth=1.2, label="measured DATA error")
    ax.plot(x, fit36, color="#d62728", linewidth=1.0,
            label=f"H36 only ({explained_ratio(errors, fit36)*100:.1f}% variance)")
    ax.plot(x, fit_family, color="#ff7f0e", linewidth=1.1,
            label=f"H36+H72+H108 ({explained_ratio(errors, fit_family)*100:.1f}%)")
    ax.plot(x, fit_extended, color="#2ca02c", linewidth=1.0,
            label=f"12-order model ({explained_ratio(errors, fit_extended)*100:.1f}%)")
    ax.set_ylabel("Error (deg)")
    ax.set_title(f"One-turn reconstruction: {run.sweep.leg}, official run {run.sweep.run_order}")
    ax.grid(True, alpha=0.22)
    ax.legend(loc="best", fontsize=9)
    residual_ax.plot(x, [value - estimate for value, estimate in zip(errors, fit_family)],
                     color="#9467bd", linewidth=1.0, label="residual after electrical family")
    residual_ax.axhline(0.0, color="#555555", linewidth=0.8)
    residual_ax.set_xlabel("Mechanical angle / sweep progress (deg)")
    residual_ax.set_ylabel("Residual (deg)")
    residual_ax.grid(True, alpha=0.22)
    residual_ax.legend(loc="best", fontsize=9)
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_folded(run: MetricRun, order: int, out_path: Path) -> float:
    cycles, template, ratio = fold_by_order(run.errors, order)
    width = len(template)
    x = [360.0 * index / len(run.errors) for index in range(width)]
    fig, ax = plt.subplots(figsize=(10, 5.8))
    for index, cycle in enumerate(cycles):
        ax.plot(x, cycle, color="#777777", alpha=0.16, linewidth=0.8,
                label="individual 10° sectors" if index == 0 else None)
    ax.plot(x, template, color="#d62728", linewidth=2.4, marker="o",
            label=f"36-sector mean; explained={ratio*100:.1f}%")
    ax.set_xlabel("Position inside each 10° mechanical sector (deg)")
    ax.set_ylabel("Mean-removed error (deg)")
    ax.set_title(f"One revolution folded into {order} repeated sectors")
    ax.grid(True, alpha=0.22)
    ax.legend(loc="best")
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)
    return ratio


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logfiles", nargs="*", type=Path)
    parser.add_argument("--labels", nargs="*")
    parser.add_argument("--out-dir", type=Path, default=Path("analysis-out/test20-one-turn"))
    args = parser.parse_args(argv)
    logfiles = list(args.logfiles) if args.logfiles else infer_default_logs(Path.cwd())
    if not logfiles:
        parser.error("no input logs and no test-20 logs auto-discovered")
    if args.labels and len(args.labels) != len(logfiles):
        parser.error("--labels count must equal input-log count")
    runs = load_official_runs(logfiles, args.labels)
    if not runs:
        parser.error("no valid official 360-degree sweeps found")
    spectra = [spectrum(run.errors) for run in runs]
    rows = harmonic_rows(runs, spectra)
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    write_csv(out_dir / "one_turn_harmonics.csv", rows)
    plot_spectrum(rows, out_dir / "one_turn_harmonic_spectrum.png")

    representative_index = next((i for i, run in enumerate(runs)
                                 if run.sweep.leg == "A1"), 0)
    representative = runs[representative_index]
    representative_spec = spectra[representative_index]
    plot_reconstruction(representative, representative_spec,
                        out_dir / "one_turn_reconstruction.png")
    fold_ratio = plot_folded(representative, 36, out_dir / "one_turn_folded_10deg.png")

    fit36 = reconstruct(representative.errors, representative_spec, (36,))
    fit_family = reconstruct(representative.errors, representative_spec, ELECTRICAL_FAMILY)
    fit_extended = reconstruct(representative.errors, representative_spec, EXTENDED_ORDERS)
    reconstruction_rows = [
        {
            "MechanicalAngleDeg": 360.0 * index / len(representative.errors),
            "MeasuredErrorDeg": value,
            "H36FitDeg": fit36[index],
            "ElectricalFamilyFitDeg": fit_family[index],
            "Extended12OrderFitDeg": fit_extended[index],
            "ElectricalFamilyResidualDeg": value - fit_family[index],
        }
        for index, value in enumerate(representative.errors)
    ]
    write_csv(out_dir / "one_turn_reconstruction.csv", reconstruction_rows)
    cycles, template, _ = fold_by_order(representative.errors, 36)
    folded_rows = [
        {
            "SectorIndex": sector_index,
            "PositionInsideSectorDeg": position,
            "CenteredErrorDeg": cycle[position],
            "SectorMeanTemplateDeg": template[position],
        }
        for sector_index, cycle in enumerate(cycles)
        for position in range(len(template))
    ]
    write_csv(out_dir / "one_turn_folded_10deg.csv", folded_rows)

    pooled = [row for row in rows if row["Group"] == "ALL"]
    ranked = sorted(pooled, key=lambda row: float(row["AmplitudeMeanDeg"]), reverse=True)
    dominant_counts: Dict[int, int] = {}
    for spec in spectra:
        dominant = max(spec.values(), key=lambda harmonic: harmonic.amplitude).order
        dominant_counts[dominant] = dominant_counts.get(dominant, 0) + 1
    family_explained = [explained_ratio(run.errors, reconstruct(run.errors, spec, ELECTRICAL_FAMILY))
                        for run, spec in zip(runs, spectra)]
    extended_explained = [explained_ratio(run.errors, reconstruct(run.errors, spec, EXTENDED_ORDERS))
                          for run, spec in zip(runs, spectra)]
    report = [
        "ONE-TURN PATTERN REPORT",
        "=======================",
        f"Official 360-degree sweeps: {len(runs)}",
        f"Dominant-order count: {dominant_counts}",
        f"Representative sweep: {representative.sweep.leg} RunOrder={representative.sweep.run_order}",
        f"Representative 36-sector folding explained ratio: {fold_ratio:.6f}",
        f"H36/H72/H108 explained ratio mean: {statistics.fmean(family_explained):.6f}",
        f"12-order model explained ratio mean: {statistics.fmean(extended_explained):.6f}",
        "",
        "Top pooled harmonics:",
    ]
    for row in ranked[:15]:
        report.append(
            f"H{int(row['Order']):3d}: amplitude={float(row['AmplitudeMeanDeg']):.6f} deg "
            f"period={float(row['PeriodMechanicalDeg']):.3f} deg "
            f"energy={100*float(row['EnergyRatioMean']):.3f}% "
            f"phaseCoherence={float(row['PhaseCoherence']):.5f}"
        )
    (out_dir / "one_turn_report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    print(f"Outputs: {out_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
