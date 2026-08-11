# NL pointwise-curve assessment — p03

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: PASS**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 2.58270° | 0.02045° | 1.33522° | -1.24748° | 0.14989° | 0.04059° |
| B | JIG1 | 3 | 2.73765° | 0.01205° | 1.78936° | -0.94829° | 0.16458° | 0.03146° |
| A2 | JIG1 | 3 | 2.58270° | 0.02045° | 1.33522° | -1.24748° | 0.14989° | 0.04059° |

## A-B-A effects

- A1→A2 NL drift: `+0.00000°`.
- A1→A2 curve correlation/RMSE: `r=1.00000`, `0.00000°`.
- B−mean(A1,A2) NL effect: `+0.15495°`.
- B−A top-tail effect: `+0.45414°`.
- B−A bottom-tail effect: `+0.29919°`.
- Zero-shift curve correlation: `0.95071`.
- Zero-shift centered RMSE: `0.22083°`.
- Best circular alignment (diagnostic only): `320.0°`, `r=0.95866`, `RMSE=0.20244°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.02045 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.00000 | 0.05000 | **PASS** |
| a_return_curve_correlation | 1.00000 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.00000 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.15495 | 0.05010 | **FAIL** |
| top_tail_delta | 0.45414 | abs <= 0.10000 deg | **FAIL** |
| bottom_tail_delta | 0.29919 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.95071 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.22083 | <= 0.10000 deg | **FAIL** |
| closure | 0.04059 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.07762° | -22.90° | 0.00157° |
| A1 | H2 | 0.10853° | -142.65° | 0.00424° |
| A1 | H4 | 0.05904° | -45.64° | 0.00081° |
| A1 | H8 | 0.01342° | -34.75° | 0.00108° |
| A1 | H9 | 0.16722° | 88.57° | 0.00153° |
| A1 | H18 | 0.10987° | -87.18° | 0.00172° |
| A1 | H36 | 0.90044° | 98.57° | 0.00205° |
| B | H1 | 0.25426° | -91.96° | 0.00554° |
| B | H2 | 0.16333° | -169.32° | 0.00312° |
| B | H4 | 0.07435° | -158.84° | 0.00096° |
| B | H8 | 0.01507° | 123.93° | 0.00063° |
| B | H9 | 0.17433° | 92.36° | 0.00083° |
| B | H18 | 0.11207° | -86.27° | 0.00208° |
| B | H36 | 0.89508° | 98.30° | 0.00217° |
| A2 | H1 | 0.07762° | -22.90° | 0.00157° |
| A2 | H2 | 0.10853° | -142.65° | 0.00424° |
| A2 | H4 | 0.05904° | -45.64° | 0.00081° |
| A2 | H8 | 0.01342° | -34.75° | 0.00108° |
| A2 | H9 | 0.16722° | 88.57° | 0.00153° |
| A2 | H18 | 0.10987° | -87.18° | 0.00172° |
| A2 | H36 | 0.90044° | 98.57° | 0.00205° |

## Data health

- CONFIG gate scan: **PASS** (12 CONFIG records).
- Invalid declared-OFFICIAL sweeps: `0`.
- Statistically eligible OFFICIAL sweeps: `9`.
- Closure samples are excluded from all pointwise and harmonic calculations.

## Files produced

- `run_metrics.csv`: one row per eligible OFFICIAL sweep.
- `pointwise_curves.csv`: raw/centered curves, SD, selection rates, and A-B-A differences.
- `harmonic_spectrum.csv`: all mechanical orders through Nyquist.
- `extreme_points.csv`: top/bottom tail locations and repeat frequency.
- `gate_results.csv` and `analysis_manifest.json`: machine-readable verdict.
- Four PNG plots: raw, centered, A-B-A differential, and harmonic spectrum.

## Interpretation boundary

A PASS supports jig interchangeability for the current whole-system command-tracking measurand. It does not prove absolute MA600/motor nonlinearity without an independent angle reference.

## Warnings

- A and B report the same JigID; this is not a cross-jig study.
