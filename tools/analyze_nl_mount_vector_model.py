#!/usr/bin/env python3
"""Fit a low-order mounting-error vector model to open-loop NL curves.

The input is the long-format ``nl_vector_model_curves.csv`` described by
``README_vector_model_request.md``.  Each non-baseline curve is first moved to
an absolute mechanical-angle grid using ``theta_start_deg``.  The mounting
response is then defined without changing the official NL measurand::

    delta(motor, config, theta) = error(config, theta) - error(baseline, theta)

The tool performs only offline analysis.  It never modifies DATA points or
recomputes an "adjusted" official NL value.  It reports:

* per-pair Fourier fits (orders 1..6, plus 12/18 diagnostics),
* a weighted joint config-only model versus motor-by-config interaction,
* leave-one-motor-out prediction for each config,
* absolute H1/H2 phase concentration and inferred error-axis direction,
* PCA of the order-1..6 complex coefficient vectors,
* CSV tables, PNG figures, and a reproducible Markdown report.

Weights are effective sweep counts ``1 / (1/n_config + 1/n_baseline)``.  They
are reliability weights only: the exported dataset contains averaged curves,
not the individual sweeps needed for a valid inferential ANOVA p-value.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd


PAIR_ORDERS = (1, 2, 3, 4, 5, 6, 12, 18)
PRIMARY_MAX_ORDER = 6
COMMON_CONFIGS = ("path1", "path2_old", "path2_new")


@dataclass(frozen=True)
class Curve:
    motor: str
    config: str
    n_sweeps: int
    theta_start_deg: float
    values_index: np.ndarray
    values_abs: np.ndarray


@dataclass(frozen=True)
class PairCurve:
    motor: str
    config: str
    n_config: int
    n_baseline: int
    weight: float
    theta_deg: np.ndarray
    delta_deg: np.ndarray
    delta_sensor_abs_deg: np.ndarray


def periodic_interpolate(theta_deg: np.ndarray, values: np.ndarray,
                         target_deg: np.ndarray) -> np.ndarray:
    """Interpolate one periodic revolution onto ``target_deg``."""
    valid = np.isfinite(theta_deg) & np.isfinite(values)
    if int(np.count_nonzero(valid)) < 3:
        raise ValueError("curve has fewer than three valid points")
    x = np.mod(theta_deg[valid], 360.0)
    y = values[valid]
    order = np.argsort(x)
    x = x[order]
    y = y[order]
    # Average accidental duplicate absolute angles before interpolation.
    unique_x, inverse = np.unique(x, return_inverse=True)
    if len(unique_x) != len(x):
        sums = np.zeros(len(unique_x), dtype=float)
        counts = np.zeros(len(unique_x), dtype=float)
        np.add.at(sums, inverse, y)
        np.add.at(counts, inverse, 1.0)
        x = unique_x
        y = sums / counts
    x_ext = np.concatenate((x - 360.0, x, x + 360.0))
    y_ext = np.concatenate((y, y, y))
    return np.interp(np.mod(target_deg, 360.0), x_ext, y_ext)


def load_curves(path: Path) -> Dict[Tuple[str, str], Curve]:
    frame = pd.read_csv(path)
    required = {
        "motor", "config", "index_deg", "error_deg", "theta_start_deg",
        "analysis_start_raw", "n_sweeps",
    }
    missing = required - set(frame.columns)
    if missing:
        raise ValueError(f"missing input columns: {sorted(missing)}")
    if frame.duplicated(["motor", "config", "index_deg"]).any():
        raise ValueError("duplicate motor/config/index rows found")

    target = np.arange(360, dtype=float)
    curves: Dict[Tuple[str, str], Curve] = {}
    for (motor, config), group in frame.groupby(["motor", "config"], sort=True):
        theta_start_values = group["theta_start_deg"].dropna().unique()
        n_values = group["n_sweeps"].dropna().unique()
        if len(theta_start_values) != 1 or len(n_values) != 1:
            raise ValueError(f"non-constant metadata for {motor}/{config}")
        theta_start = float(theta_start_values[0])
        index = group["index_deg"].to_numpy(dtype=float)
        values = group["error_deg"].to_numpy(dtype=float)
        absolute_theta = index + theta_start
        values_index = periodic_interpolate(index, values, target)
        values_abs = periodic_interpolate(absolute_theta, values, target)
        curves[(str(motor), str(config))] = Curve(
            motor=str(motor),
            config=str(config),
            n_sweeps=int(n_values[0]),
            theta_start_deg=theta_start,
            values_index=values_index,
            values_abs=values_abs,
        )
    return curves


def build_pairs(curves: Mapping[Tuple[str, str], Curve]) -> List[PairCurve]:
    theta = np.arange(360, dtype=float)
    pairs: List[PairCurve] = []
    motors = sorted({motor for motor, _ in curves})
    for motor in motors:
        baseline = curves.get((motor, "baseline"))
        if baseline is None:
            continue
        configs = sorted(config for m, config in curves if m == motor and config != "baseline")
        for config in configs:
            curve = curves[(motor, config)]
            n_eff = 1.0 / (1.0 / curve.n_sweeps + 1.0 / baseline.n_sweeps)
            pairs.append(PairCurve(
                motor=motor,
                config=config,
                n_config=curve.n_sweeps,
                n_baseline=baseline.n_sweeps,
                weight=n_eff,
                theta_deg=theta,
                # Command/sweep-progress frame is primary for decomposing a
                # config change: it preserves the common open-loop command
                # history and lets the known motor-intrinsic H36 cancel.
                delta_deg=curve.values_index - baseline.values_index,
                # Sensor-raw frame is retained only to test whether
                # theta_start_deg really acts as a shared physical reference.
                delta_sensor_abs_deg=curve.values_abs - baseline.values_abs,
            ))
    if not pairs:
        raise ValueError("no config-baseline pairs found")
    return pairs


def design_matrix(theta_deg: np.ndarray, max_order: int) -> np.ndarray:
    theta = np.deg2rad(theta_deg)
    columns = [np.ones_like(theta)]
    for order in range(1, max_order + 1):
        columns.append(np.cos(order * theta))
        columns.append(np.sin(order * theta))
    return np.column_stack(columns)


def fit_fourier(theta_deg: np.ndarray, values: np.ndarray,
                max_order: int) -> Tuple[np.ndarray, np.ndarray, Dict[str, float]]:
    valid = np.isfinite(theta_deg) & np.isfinite(values)
    x = design_matrix(theta_deg[valid], max_order)
    y = values[valid]
    beta, _, _, _ = np.linalg.lstsq(x, y, rcond=None)
    fitted_valid = x @ beta
    fitted = design_matrix(theta_deg, max_order) @ beta
    residual = y - fitted_valid
    sse = float(residual @ residual)
    centered = y - float(np.mean(y))
    sst = float(centered @ centered)
    n = int(len(y))
    p = int(len(beta))
    variance = max(sse / max(n, 1), np.finfo(float).tiny)
    aic = n * math.log(variance) + 2.0 * p
    aicc = aic + (2.0 * p * (p + 1) / (n - p - 1) if n > p + 1 else math.inf)
    bic = n * math.log(variance) + p * math.log(n)
    metrics = {
        "rmse_deg": math.sqrt(sse / n),
        "r2": 1.0 - sse / sst if sst > 0.0 else 1.0,
        "aicc": aicc,
        "bic": bic,
        "max_abs_residual_deg": float(np.max(np.abs(residual))),
    }
    return beta, fitted, metrics


def coefficient(beta: np.ndarray, order: int) -> Tuple[float, float, float, float, float]:
    a = float(beta[2 * order - 1])
    b = float(beta[2 * order])
    amplitude = math.hypot(a, b)
    # Project convention (matches analyze_one_turn_pattern.py):
    # a*cos(k*theta) + b*sin(k*theta) = A*cos(k*theta - phase).
    phase_deg = math.degrees(math.atan2(b, a))
    axis_period = 360.0 / order
    max_axis_deg = (phase_deg / order) % axis_period
    return a, b, amplitude, phase_deg, max_axis_deg


def energy_localization(residual: np.ndarray, fraction: float = 0.10) -> float:
    energy = residual * residual
    total = float(np.sum(energy))
    if total <= 0.0:
        return 0.0
    count = max(1, int(math.ceil(len(residual) * fraction)))
    return float(np.sum(np.sort(energy)[-count:]) / total)


def pair_tables(pairs: Sequence[PairCurve]) -> Tuple[pd.DataFrame, pd.DataFrame,
                                                     Dict[Tuple[str, str], np.ndarray],
                                                     Dict[Tuple[str, str], np.ndarray]]:
    harmonic_rows: List[Dict[str, object]] = []
    metric_rows: List[Dict[str, object]] = []
    beta6: Dict[Tuple[str, str], np.ndarray] = {}
    beta6_sensor_abs: Dict[Tuple[str, str], np.ndarray] = {}
    model_orders = (1, 2, 3, 4, 5, 6, 12, 18)
    for pair in pairs:
        fits: Dict[int, Tuple[np.ndarray, np.ndarray, Dict[str, float]]] = {}
        for max_order in model_orders:
            fits[max_order] = fit_fourier(pair.theta_deg, pair.delta_deg, max_order)
            beta, fitted, metrics = fits[max_order]
            residual = pair.delta_deg - fitted
            metric_rows.append({
                "motor": pair.motor,
                "config": pair.config,
                "n_config": pair.n_config,
                "n_baseline": pair.n_baseline,
                "effective_weight": pair.weight,
                "max_order": max_order,
                **metrics,
                "top10pct_residual_energy_fraction": energy_localization(residual),
            })
        beta, _, _ = fits[PRIMARY_MAX_ORDER]
        beta6[(pair.motor, pair.config)] = beta
        beta_abs, _, _ = fit_fourier(pair.theta_deg, pair.delta_sensor_abs_deg,
                                     PRIMARY_MAX_ORDER)
        beta6_sensor_abs[(pair.motor, pair.config)] = beta_abs
        for order in range(1, PRIMARY_MAX_ORDER + 1):
            a, b, amplitude, phase, axis = coefficient(beta, order)
            abs_a, abs_b, abs_amplitude, abs_phase, abs_axis = coefficient(beta_abs, order)
            harmonic_rows.append({
                "motor": pair.motor,
                "config": pair.config,
                "n_config": pair.n_config,
                "n_baseline": pair.n_baseline,
                "effective_weight": pair.weight,
                "dc_deg": float(beta[0]),
                "order": order,
                "cos_coeff_deg": a,
                "sin_coeff_deg": b,
                "amplitude_deg": amplitude,
                "phase_command_deg": phase,
                "max_error_axis_command_deg": axis,
                "sensor_abs_cos_coeff_deg": abs_a,
                "sensor_abs_sin_coeff_deg": abs_b,
                "sensor_abs_amplitude_deg": abs_amplitude,
                "phase_sensor_abs_deg": abs_phase,
                "max_error_axis_sensor_abs_deg": abs_axis,
                "axis_period_deg": 360.0 / order,
            })
    return (pd.DataFrame(harmonic_rows), pd.DataFrame(metric_rows), beta6,
            beta6_sensor_abs)


def weighted_mean(vectors: np.ndarray, weights: np.ndarray) -> np.ndarray:
    return np.sum(vectors * weights[:, None], axis=0) / float(np.sum(weights))


def config_interaction_tables(
        pairs: Sequence[PairCurve], beta6: Mapping[Tuple[str, str], np.ndarray],
        beta6_sensor_abs: Mapping[Tuple[str, str], np.ndarray],
) -> Tuple[pd.DataFrame, pd.DataFrame, Dict[str, np.ndarray]]:
    summaries: List[Dict[str, object]] = []
    common_rows: List[Dict[str, object]] = []
    common_beta: Dict[str, np.ndarray] = {}
    by_config = {config: [pair for pair in pairs if pair.config == config]
                 for config in sorted({pair.config for pair in pairs})}
    for config, group in by_config.items():
        vectors = np.vstack([beta6[(pair.motor, pair.config)] for pair in group])
        abs_vectors = np.vstack([
            beta6_sensor_abs[(pair.motor, pair.config)] for pair in group
        ])
        weights = np.asarray([pair.weight for pair in group], dtype=float)
        mean_beta = weighted_mean(vectors, weights)
        common_beta[config] = mean_beta
        total_energy = float(np.sum(weights[:, None] * vectors * vectors))
        interaction_energy = float(np.sum(weights[:, None] * (vectors - mean_beta) ** 2))
        common_fraction = 1.0 - interaction_energy / total_energy if total_energy > 0.0 else 1.0

        zero_rmse: List[float] = []
        loo_rmse: List[float] = []
        pair_rmse: List[float] = []
        for index, pair in enumerate(group):
            zero_rmse.append(float(np.sqrt(np.mean(pair.delta_deg ** 2))))
            _, fitted_pair, metrics = fit_fourier(pair.theta_deg, pair.delta_deg,
                                                   PRIMARY_MAX_ORDER)
            pair_rmse.append(float(metrics["rmse_deg"]))
            if len(group) > 1:
                keep = np.arange(len(group)) != index
                loo_beta = weighted_mean(vectors[keep], weights[keep])
                predicted = design_matrix(pair.theta_deg, PRIMARY_MAX_ORDER) @ loo_beta
                loo_rmse.append(float(np.sqrt(np.mean((pair.delta_deg - predicted) ** 2))))

        summaries.append({
            "config": config,
            "motor_count": len(group),
            "coefficient_common_fraction": common_fraction,
            "coefficient_interaction_fraction": 1.0 - common_fraction,
            "zero_prediction_rmse_mean_deg": float(np.mean(zero_rmse)),
            "loo_config_only_rmse_mean_deg": float(np.mean(loo_rmse)) if loo_rmse else math.nan,
            "pair_specific_h1_h6_rmse_mean_deg": float(np.mean(pair_rmse)),
            "loo_improvement_vs_zero_fraction": (
                1.0 - float(np.mean(loo_rmse)) / float(np.mean(zero_rmse))
                if loo_rmse and float(np.mean(zero_rmse)) > 0.0 else math.nan
            ),
        })

        for order in range(1, PRIMARY_MAX_ORDER + 1):
            a, b, amplitude, phase, axis = coefficient(mean_beta, order)
            phases = []
            complex_values = []
            for vector in vectors:
                va, vb, vamp, vphase, _ = coefficient(vector, order)
                if vamp > 0.0:
                    phases.append(np.exp(1j * math.radians(vphase)))
                complex_values.append(complex(va, vb))
            phase_r = abs(sum(phases) / len(phases)) if phases else 0.0
            denom = sum(abs(value) for value in complex_values)
            amplitude_weighted_r = abs(sum(complex_values)) / denom if denom > 0.0 else 0.0

            abs_phases = []
            abs_complex_values = []
            for vector in abs_vectors:
                va, vb, vamp, vphase, _ = coefficient(vector, order)
                if vamp > 0.0:
                    abs_phases.append(np.exp(1j * math.radians(vphase)))
                    abs_complex_values.append(complex(va, vb))
            abs_phase_r = abs(sum(abs_phases) / len(abs_phases)) if abs_phases else 0.0
            abs_denom = sum(abs(value) for value in abs_complex_values)
            abs_amplitude_r = (abs(sum(abs_complex_values)) / abs_denom
                               if abs_denom > 0.0 else 0.0)
            abs_mean = weighted_mean(abs_vectors, weights)
            _, _, abs_amp, abs_phase, abs_axis = coefficient(abs_mean, order)
            common_rows.append({
                "config": config,
                "motor_count": len(group),
                "order": order,
                "mean_cos_coeff_deg": a,
                "mean_sin_coeff_deg": b,
                "mean_vector_amplitude_deg": amplitude,
                "mean_vector_phase_abs_deg": phase,
                "mean_max_error_axis_abs_deg": axis,
                "phase_only_resultant_r": phase_r,
                "amplitude_weighted_resultant_r": amplitude_weighted_r,
                "sensor_abs_mean_vector_amplitude_deg": abs_amp,
                "sensor_abs_mean_vector_phase_deg": abs_phase,
                "sensor_abs_mean_error_axis_deg": abs_axis,
                "sensor_abs_phase_only_resultant_r": abs_phase_r,
                "sensor_abs_amplitude_weighted_resultant_r": abs_amplitude_r,
            })
    return pd.DataFrame(summaries), pd.DataFrame(common_rows), common_beta


def pca_tables(pairs: Sequence[PairCurve],
               beta6: Mapping[Tuple[str, str], np.ndarray]) -> Tuple[pd.DataFrame, pd.DataFrame]:
    # Exclude DC: PCA is specifically on complex H1..H6 mounting vectors.
    matrix = np.vstack([beta6[(pair.motor, pair.config)][1:] for pair in pairs])
    weights = np.asarray([pair.weight for pair in pairs], dtype=float)
    weights = weights / float(np.sum(weights))
    center = np.sum(matrix * weights[:, None], axis=0)
    centered = matrix - center
    weighted_matrix = centered * np.sqrt(weights[:, None])
    _, singular, vt = np.linalg.svd(weighted_matrix, full_matrices=False)
    variance = singular * singular
    ratio = variance / float(np.sum(variance)) if float(np.sum(variance)) > 0.0 else variance
    scores = centered @ vt.T
    score_rows = []
    for row, pair in enumerate(pairs):
        score_rows.append({
            "motor": pair.motor,
            "config": pair.config,
            "effective_weight": pair.weight,
            **{f"PC{pc + 1}_score": float(scores[row, pc])
               for pc in range(min(4, scores.shape[1]))},
        })
    summary_rows = []
    cumulative = 0.0
    for pc in range(min(6, len(ratio))):
        cumulative += float(ratio[pc])
        summary_rows.append({
            "component": pc + 1,
            "explained_variance_fraction": float(ratio[pc]),
            "cumulative_fraction": cumulative,
        })
    return pd.DataFrame(score_rows), pd.DataFrame(summary_rows)


def full_spectrum_rows(pairs: Sequence[PairCurve], max_order: int = 60) -> pd.DataFrame:
    rows: List[Dict[str, object]] = []
    for pair in pairs:
        beta, _, _ = fit_fourier(pair.theta_deg, pair.delta_deg, max_order)
        for order in range(1, max_order + 1):
            _, _, amplitude, phase, axis = coefficient(beta, order)
            rows.append({
                "motor": pair.motor,
                "config": pair.config,
                "order": order,
                "amplitude_deg": amplitude,
                "phase_abs_deg": phase,
                "max_error_axis_abs_deg": axis,
            })
    return pd.DataFrame(rows)


def reference_frame_diagnostics(pairs: Sequence[PairCurve]) -> pd.DataFrame:
    """Use the known motor-intrinsic H36 to audit candidate phase frames."""
    rows: List[Dict[str, object]] = []
    for pair in pairs:
        command_beta, _, _ = fit_fourier(pair.theta_deg, pair.delta_deg, 36)
        sensor_beta, _, _ = fit_fourier(pair.theta_deg, pair.delta_sensor_abs_deg, 36)
        _, _, command_h36, command_phase, _ = coefficient(command_beta, 36)
        _, _, sensor_h36, sensor_phase, _ = coefficient(sensor_beta, 36)
        rows.append({
            "motor": pair.motor,
            "config": pair.config,
            "theta_frame_note": "delta(config-baseline)",
            "h36_delta_amplitude_command_frame_deg": command_h36,
            "h36_delta_phase_command_frame_deg": command_phase,
            "h36_delta_amplitude_sensor_abs_frame_deg": sensor_h36,
            "h36_delta_phase_sensor_abs_frame_deg": sensor_phase,
            "sensor_abs_to_command_h36_ratio": (
                sensor_h36 / command_h36 if command_h36 > 1.0e-12 else math.inf
            ),
        })
    return pd.DataFrame(rows)


def plot_pair_fits(pairs: Sequence[PairCurve], out_path: Path) -> None:
    columns = 3
    rows = int(math.ceil(len(pairs) / columns))
    fig, axes = plt.subplots(rows, columns, figsize=(15, 3.5 * rows), sharex=True)
    axes_flat = np.atleast_1d(axes).ravel()
    for ax, pair in zip(axes_flat, pairs):
        _, fit3, metrics3 = fit_fourier(pair.theta_deg, pair.delta_deg, 3)
        _, fit6, metrics6 = fit_fourier(pair.theta_deg, pair.delta_deg, 6)
        ax.plot(pair.theta_deg, pair.delta_deg, color="#444444", linewidth=1.0,
                label="config-baseline")
        ax.plot(pair.theta_deg, fit3, color="#d62728", linewidth=1.3,
                label=f"H1-H3 R2={metrics3['r2']:.3f}")
        ax.plot(pair.theta_deg, fit6, color="#1f77b4", linewidth=1.0, linestyle="--",
                label=f"H1-H6 R2={metrics6['r2']:.3f}")
        ax.set_title(f"{pair.motor} / {pair.config}")
        ax.set_ylabel("Delta error (deg)")
        ax.grid(True, alpha=0.2)
        ax.legend(fontsize=7)
    for ax in axes_flat[len(pairs):]:
        ax.axis("off")
    for ax in axes_flat[-columns:]:
        ax.set_xlabel("Sweep command index (deg)")
    fig.suptitle("Mounting response in common open-loop command frame", y=1.002)
    fig.tight_layout()
    fig.savefig(out_path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def plot_harmonic_heatmap(harmonics: pd.DataFrame, out_path: Path) -> None:
    labels = list(dict.fromkeys(
        f"{row.motor}/{row.config}" for row in harmonics.itertuples(index=False)
        if int(row.order) == 1
    ))
    matrix = np.zeros((len(labels), PRIMARY_MAX_ORDER), dtype=float)
    for row in harmonics.itertuples(index=False):
        label = f"{row.motor}/{row.config}"
        if int(row.order) <= PRIMARY_MAX_ORDER:
            matrix[labels.index(label), int(row.order) - 1] = float(row.amplitude_deg)
    fig, ax = plt.subplots(figsize=(9, 0.55 * len(labels) + 2.2))
    image = ax.imshow(matrix, aspect="auto", cmap="magma")
    ax.set_yticks(range(len(labels)), labels=labels)
    ax.set_xticks(range(PRIMARY_MAX_ORDER), labels=[f"H{i}" for i in range(1, 7)])
    for row in range(matrix.shape[0]):
        for col in range(matrix.shape[1]):
            ax.text(col, row, f"{matrix[row, col]:.3f}", ha="center", va="center",
                    color="white" if matrix[row, col] > 0.45 * np.max(matrix) else "black",
                    fontsize=7)
    fig.colorbar(image, ax=ax, label="Amplitude (deg)")
    ax.set_title("Low-order mounting-vector amplitudes")
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_phase_vectors(harmonics: pd.DataFrame, out_path: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(12, 5.5), subplot_kw={"projection": "polar"})
    colors = {"path1": "#1f77b4", "path2_old": "#d62728", "path2_new": "#2ca02c"}
    for ax, order in zip(axes, (1, 2)):
        subset = harmonics[harmonics["order"] == order]
        for row in subset.itertuples(index=False):
            phase = math.radians(float(row.phase_sensor_abs_deg))
            amplitude = float(row.sensor_abs_amplitude_deg)
            ax.plot([phase, phase], [0.0, amplitude], color=colors.get(row.config, "#777777"),
                    alpha=0.75, linewidth=1.5)
            ax.scatter([phase], [amplitude], color=colors.get(row.config, "#777777"), s=28)
            ax.annotate(row.motor, (phase, amplitude), fontsize=7)
        ax.set_title(f"Absolute complex phase H{order}")
    handles = [plt.Line2D([0], [0], color=color, label=config)
               for config, color in colors.items()]
    fig.legend(handles=handles, loc="lower center", ncol=3)
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_pca(scores: pd.DataFrame, summary: pd.DataFrame, out_path: Path) -> None:
    if "PC2_score" not in scores:
        return
    fig, ax = plt.subplots(figsize=(8, 6))
    colors = {"path1": "#1f77b4", "path2_old": "#d62728", "path2_new": "#2ca02c"}
    for row in scores.itertuples(index=False):
        ax.scatter(row.PC1_score, row.PC2_score, color=colors.get(row.config, "#777777"), s=55)
        ax.annotate(f"{row.motor}/{row.config}", (row.PC1_score, row.PC2_score),
                    xytext=(5, 4), textcoords="offset points", fontsize=8)
    ev1 = 100.0 * float(summary.iloc[0]["explained_variance_fraction"])
    ev2 = 100.0 * float(summary.iloc[1]["explained_variance_fraction"])
    ax.set_xlabel(f"PC1 ({ev1:.1f}%)")
    ax.set_ylabel(f"PC2 ({ev2:.1f}%)")
    ax.axhline(0.0, color="#999999", linewidth=0.7)
    ax.axvline(0.0, color="#999999", linewidth=0.7)
    ax.grid(True, alpha=0.2)
    ax.set_title("PCA of command-frame H1-H6 mounting-vector coefficients")
    fig.tight_layout()
    fig.savefig(out_path, dpi=170)
    plt.close(fig)


def plot_model_order(metrics: pd.DataFrame, out_path: Path) -> None:
    subset = metrics[metrics["max_order"].isin([1, 2, 3, 4, 5, 6])]
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 4.8))
    for (motor, config), group in subset.groupby(["motor", "config"], sort=True):
        label = f"{motor}/{config}"
        ax1.plot(group["max_order"], group["r2"], marker="o", label=label)
        ax2.plot(group["max_order"], group["rmse_deg"], marker="o", label=label)
    ax1.set_xlabel("Maximum Fourier order")
    ax1.set_ylabel("R²")
    ax2.set_xlabel("Maximum Fourier order")
    ax2.set_ylabel("Residual RMSE (deg)")
    for ax in (ax1, ax2):
        ax.grid(True, alpha=0.2)
    ax2.legend(fontsize=7, bbox_to_anchor=(1.02, 1), loc="upper left")
    fig.suptitle("Low-order model sufficiency")
    fig.tight_layout()
    fig.savefig(out_path, dpi=170, bbox_inches="tight")
    plt.close(fig)


def weighted_average(frame: pd.DataFrame, column: str) -> float:
    weights = frame["effective_weight"].to_numpy(dtype=float)
    values = frame[column].to_numpy(dtype=float)
    return float(np.sum(weights * values) / np.sum(weights))


def write_report(path: Path, source: Path, pairs: Sequence[PairCurve],
                 harmonics: pd.DataFrame, metrics: pd.DataFrame,
                 interactions: pd.DataFrame, common: pd.DataFrame,
                 pca_summary: pd.DataFrame, spectrum: pd.DataFrame,
                 frame_diagnostics: pd.DataFrame) -> None:
    m1 = metrics[metrics["max_order"] == 1]
    m2 = metrics[metrics["max_order"] == 2]
    m3 = metrics[metrics["max_order"] == 3]
    m6 = metrics[metrics["max_order"] == 6]
    m18 = metrics[metrics["max_order"] == 18]
    weighted_r2 = {order: weighted_average(frame, "r2")
                   for order, frame in ((1, m1), (2, m2), (3, m3), (6, m6), (18, m18))}
    weighted_rmse = {order: weighted_average(frame, "rmse_deg")
                     for order, frame in ((1, m1), (2, m2), (3, m3), (6, m6), (18, m18))}
    h_amp = harmonics.pivot_table(index=["motor", "config"], columns="order",
                                  values="amplitude_deg")
    h_dominant = {
        f"{motor}/{config}": int(row.idxmax())
        for (motor, config), row in h_amp.iterrows()
    }
    dominant_counts = pd.Series(list(h_dominant.values())).value_counts().sort_index()

    residual_spectrum = spectrum[spectrum["order"] >= 4].copy()
    top_residual = []
    for (motor, config), group in residual_spectrum.groupby(["motor", "config"], sort=True):
        row = group.loc[group["amplitude_deg"].idxmax()]
        top_residual.append((motor, config, int(row["order"]), float(row["amplitude_deg"])))

    mean_command_h36 = float(frame_diagnostics[
        "h36_delta_amplitude_command_frame_deg"].mean())
    mean_abs_h36 = float(frame_diagnostics[
        "h36_delta_amplitude_sensor_abs_frame_deg"].mean())
    loo_improvement_min = float(interactions["loo_improvement_vs_zero_fraction"].min())
    loo_improvement_max = float(interactions["loo_improvement_vs_zero_fraction"].max())
    pc3_cumulative = float(pca_summary.iloc[min(2, len(pca_summary) - 1)][
        "cumulative_fraction"])
    residual_orders = pd.Series([order for _, _, order, _ in top_residual]).value_counts()
    residual_summary = ", ".join(
        f"H{int(order)}={int(count)} pair(s)"
        for order, count in residual_orders.sort_index().items()
    )

    lines = [
        "# NL mounting-vector model assessment",
        "",
        "## Scope and measurement contract",
        "",
        f"- Source: `{source}`",
        f"- Curves: {len(pairs) + len({pair.motor for pair in pairs})}; config-baseline pairs: {len(pairs)}.",
        "- Classification: `OPEN_LOOP_MEASUREMENT` offline analysis.",
        "- Official measurand is unchanged: this report does not correct DATA or publish an adjusted NL.",
        "- Primary shape decomposition uses the common sweep-command/index frame so the known motor H36 fingerprint can cancel.",
        "- A second sensor-raw frame (`theta_start_deg + index`) is evaluated separately for absolute-phase claims.",
        "- Effective sweep count is used only as a reliability weight; individual-sweep variance is unavailable.",
        "- Phase convention: `a*cos(k*theta)+b*sin(k*theta)=A*cos(k*theta-phase)`, matching the existing project analyzer.",
        "",
        "## Executive conclusions",
        "",
        f"1. **H1-H2 is the correct first-order mounting model, but is not sufficient for precision:** "
        f"it explains `{weighted_r2[2]:.1%}` of weighted curve variance; H1-H6 reaches "
        f"`{weighted_r2[6]:.1%}`, and H1-H18 reaches `{weighted_r2[18]:.1%}`.",
        f"2. **A config-only correction is not transferable to an unseen motor:** leave-one-motor-out "
        f"prediction is worse than applying no correction for every tested config "
        f"(`{loo_improvement_min:.1%}` to `{loo_improvement_max:.1%}` improvement). "
        "The motor×mount/config interaction is therefore part of the measured response.",
        f"3. **The supplied `theta_start_deg + index` coordinate is not a validated shared physical-angle "
        f"reference:** mean H36 cancellation error grows from `{mean_command_h36:.4f} deg` in the command "
        f"frame to `{mean_abs_h36:.4f} deg` in that sensor-raw frame. Absolute H1/H2 axes cannot yet be "
        "mapped to the magnet N/S direction without an external fiducial or field reference.",
        f"4. **The response is multi-mode, not one universal eccentricity vector:** the first three PCA "
        f"components explain `{pc3_cumulative:.1%}` together. The strongest residual orders are "
        f"{residual_summary}; current evidence favors additional harmonics over a non-harmonic step/pulse model.",
        "5. **No official NL value is corrected by this work.** These models decompose and test the "
        "mounting response only; they do not create a product pass/fail threshold.",
        "",
        "## 1. How many harmonics are needed?",
        "",
        "Weighted aggregate fit quality:",
        "",
        "| Model | Weighted R² | Weighted residual RMSE (deg) |",
        "|---|---:|---:|",
    ]
    for order in (1, 2, 3, 6, 18):
        lines.append(f"| H1-H{order} | {weighted_r2[order]:.4f} | {weighted_rmse[order]:.4f} |")
    lines += [
        "",
        "Dominant order among H1-H6 by pair: " + ", ".join(
            f"H{int(order)}={int(count)} pair(s)" for order, count in dominant_counts.items()),
        "",
        "Per-pair details are in `pair_model_metrics.csv` and `pair_harmonic_coefficients.csv`.",
        "A large H3-to-H6 or H18 improvement indicates structure beyond a pure H1/H2 eccentricity vector.",
        "The residual-localization column tests whether remaining energy is concentrated in a small angular window.",
        "",
        "## 2. Config-only model versus motor×config interaction",
        "",
        "| Config | Motors | Common coefficient fraction | Interaction fraction | Zero RMSE | LOO config-only RMSE | Pair-specific H1-H6 RMSE | LOO improvement |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in interactions.itertuples(index=False):
        lines.append(
            f"| {row.config} | {row.motor_count} | {row.coefficient_common_fraction:.3f} | "
            f"{row.coefficient_interaction_fraction:.3f} | {row.zero_prediction_rmse_mean_deg:.4f} | "
            f"{row.loo_config_only_rmse_mean_deg:.4f} | {row.pair_specific_h1_h6_rmse_mean_deg:.4f} | "
            f"{row.loo_improvement_vs_zero_fraction:.1%} |"
        )
    lines += [
        "",
        "Interpretation rule: a config-only correction is transferable only when its leave-one-motor-out RMSE",
        "is materially below the zero-correction RMSE. A negative LOO improvement means the shared config table",
        "would make an unseen motor worse, which is direct evidence of motor×config interaction.",
        "",
        "## 3. Reference-frame validity check using motor-intrinsic H36",
        "",
        "If `theta_start_deg + index` were a shared physical-angle reference across mounting/sensor changes,",
        "the known motor-intrinsic H36 should cancel at least as well there as in the common command frame.",
        "",
        "| Pair | H36 delta in command frame (deg) | H36 delta in sensor-absolute frame (deg) | Ratio |",
        "|---|---:|---:|---:|",
    ]
    for row in frame_diagnostics.itertuples(index=False):
        ratio = row.sensor_abs_to_command_h36_ratio
        ratio_text = f"{ratio:.2f}" if math.isfinite(ratio) else "inf"
        lines.append(
            f"| {row.motor}/{row.config} | "
            f"{row.h36_delta_amplitude_command_frame_deg:.4f} | "
            f"{row.h36_delta_amplitude_sensor_abs_frame_deg:.4f} | {ratio_text} |"
        )
    lines += [
        "",
        f"Mean H36 delta amplitude: command frame `{mean_command_h36:.4f}°`; "
        f"sensor-absolute frame `{mean_abs_h36:.4f}°`.",
        "This is an internal falsification test for the proposed absolute reference; it does not alter official NL.",
        "",
        "## 4. H1/H2 phase and the N-S transition hypothesis",
        "",
        "| Config | Order | Motors | Command-frame R | Sensor-absolute R | Sensor-absolute mean axis (deg) |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    phase_subset = common[common["order"].isin([1, 2])]
    for row in phase_subset.itertuples(index=False):
        lines.append(
            f"| {row.config} | H{row.order} | {row.motor_count} | "
            f"{row.phase_only_resultant_r:.3f} | {row.sensor_abs_phase_only_resultant_r:.3f} | "
            f"{row.sensor_abs_mean_error_axis_deg:.2f} |"
        )
    lines += [
        "",
        "`R≈1` means phases cluster; `R≈0` means they disperse/cancel. H2 axis is modulo 180°.",
        "The phase identifies an error-field axis, not the physical N/S magnet direction by itself.",
        "If the H36 check above rejects the sensor-absolute frame, these absolute axes must be treated as uncalibrated.",
        "A marked magnet orientation or an independent magnetic-field reference is still required to map that axis",
        "to the actual N-S transition.",
        "",
        "## 5. PCA",
        "",
        "| PC | Explained variance | Cumulative |",
        "|---:|---:|---:|",
    ]
    for row in pca_summary.itertuples(index=False):
        lines.append(
            f"| {row.component} | {row.explained_variance_fraction:.3f} | {row.cumulative_fraction:.3f} |"
        )
    lines += [
        "",
        "PCA is descriptive only: there are nine pair curves and no balanced four-config design.",
        "A strong PC1 shows a low-dimensional response family, but it does not prove a universal config correction.",
        "",
        "## 6. Largest residual spectral terms after the low-order region",
        "",
        "| Pair | Largest order in H4-H60 | Amplitude (deg) |",
        "|---|---:|---:|",
    ]
    for motor, config, order, amplitude in top_residual:
        lines.append(f"| {motor}/{config} | H{order} | {amplitude:.4f} |")
    lines += [
        "",
        "## Limitations",
        "",
        "- Only one physical jig/MCU is present; no cross-jig statement can be made.",
        "- Each config is already an averaged curve. Sweep-level variance and a valid mixed-effects p-value cannot be reconstructed.",
        "- The design is unbalanced: path1 has two motors, path2_new three, path2_old four.",
        "- Baseline is shared within each motor, so pair differences are statistically correlated.",
        "- Sensor replacement and mounting path are confounded in `path2_new` versus `path2_old` unless additional controlled swaps are run.",
        "",
        "## Generated evidence",
        "",
        "- `pair_harmonic_coefficients.csv`",
        "- `pair_model_metrics.csv`",
        "- `config_interaction_summary.csv`",
        "- `common_config_harmonics.csv`",
        "- `pca_scores.csv`, `pca_summary.csv`",
        "- `full_pair_spectrum_h1_h60.csv`",
        "- `reference_frame_diagnostics.csv`",
        "- `pair_command_frame_fits.png`, `harmonic_amplitude_heatmap.png`, `absolute_phase_vectors_h1_h2.png`",
        "- `model_order_sufficiency.png`, `pca_scores.png`",
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def self_test() -> None:
    theta = np.arange(360, dtype=float)
    expected = 0.3 + 0.2 * np.cos(np.deg2rad(theta + 30.0)) \
        + 0.4 * np.cos(np.deg2rad(2.0 * theta - 40.0))
    beta, fitted, metrics = fit_fourier(theta, expected, 2)
    if metrics["rmse_deg"] > 1.0e-10:
        raise AssertionError("Fourier self-test reconstruction failed")
    _, _, h1, phase1, _ = coefficient(beta, 1)
    _, _, h2, phase2, _ = coefficient(beta, 2)
    if abs(h1 - 0.2) > 1.0e-10 or abs(h2 - 0.4) > 1.0e-10:
        raise AssertionError("Fourier self-test amplitude failed")
    if abs(phase1 + 30.0) > 1.0e-9 or abs(phase2 - 40.0) > 1.0e-9:
        raise AssertionError("Fourier self-test phase failed")
    shifted_theta = np.mod(theta + 17.25, 360.0)
    shifted_values = 0.3 + 0.2 * np.cos(np.deg2rad(shifted_theta + 30.0)) \
        + 0.4 * np.cos(np.deg2rad(2.0 * shifted_theta - 40.0))
    sampled = periodic_interpolate(shifted_theta, shifted_values, theta)
    # The sample values belong to shifted_theta; interpolation must recover the
    # same periodic function on theta to normal interpolation accuracy.
    truth = 0.3 + 0.2 * np.cos(np.deg2rad(theta + 30.0)) \
        + 0.4 * np.cos(np.deg2rad(2.0 * theta - 40.0))
    if float(np.max(np.abs(sampled - truth))) > 2.0e-4:
        raise AssertionError("absolute-angle interpolation self-test failed")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_csv", type=Path)
    parser.add_argument("--out-dir", type=Path,
                        default=Path("analysis-out/nl-mount-vector-model"))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        self_test()

    curves = load_curves(args.input_csv)
    pairs = build_pairs(curves)
    harmonics, metrics, beta6, beta6_sensor_abs = pair_tables(pairs)
    interactions, common, _ = config_interaction_tables(
        pairs, beta6, beta6_sensor_abs)
    pca_scores, pca_summary = pca_tables(pairs, beta6)
    spectrum = full_spectrum_rows(pairs)
    frame_diagnostics = reference_frame_diagnostics(pairs)

    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    harmonics.to_csv(out_dir / "pair_harmonic_coefficients.csv", index=False)
    metrics.to_csv(out_dir / "pair_model_metrics.csv", index=False)
    interactions.to_csv(out_dir / "config_interaction_summary.csv", index=False)
    common.to_csv(out_dir / "common_config_harmonics.csv", index=False)
    pca_scores.to_csv(out_dir / "pca_scores.csv", index=False)
    pca_summary.to_csv(out_dir / "pca_summary.csv", index=False)
    spectrum.to_csv(out_dir / "full_pair_spectrum_h1_h60.csv", index=False)
    frame_diagnostics.to_csv(out_dir / "reference_frame_diagnostics.csv", index=False)

    plot_pair_fits(pairs, out_dir / "pair_command_frame_fits.png")
    plot_harmonic_heatmap(harmonics, out_dir / "harmonic_amplitude_heatmap.png")
    plot_phase_vectors(harmonics, out_dir / "absolute_phase_vectors_h1_h2.png")
    plot_pca(pca_scores, pca_summary, out_dir / "pca_scores.png")
    plot_model_order(metrics, out_dir / "model_order_sufficiency.png")
    write_report(out_dir / "nl_mount_vector_model_report.md", args.input_csv, pairs,
                 harmonics, metrics, interactions, common, pca_summary, spectrum,
                 frame_diagnostics)

    print(f"Loaded {len(curves)} curves; analyzed {len(pairs)} config-baseline pairs")
    print(interactions.to_string(index=False, float_format=lambda value: f"{value:.4f}"))
    print(f"Outputs: {out_dir.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
