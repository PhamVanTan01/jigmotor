# NL pointwise-curve assessment — p03

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: PASS**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 2.59082° | 0.00662° | 1.61227° | -0.97855° | 0.10861° | 0.02063° |
| B | JIG1 | 3 | 2.73765° | 0.01205° | 1.78936° | -0.94829° | 0.16458° | 0.03146° |
| A2 | JIG1 | 3 | 2.60362° | 0.01415° | 1.64743° | -0.95620° | 0.13575° | 0.04895° |

## A-B-A effects

- A1→A2 NL drift: `+0.01281°`.
- A1→A2 curve correlation/RMSE: `r=0.99855`, `0.03740°`.
- B−mean(A1,A2) NL effect: `+0.14043°`.
- B−A top-tail effect: `+0.15951°`.
- B−A bottom-tail effect: `+0.01908°`.
- Zero-shift curve correlation: `0.99331`.
- Zero-shift centered RMSE: `0.08289°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.99331`, `RMSE=0.08289°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.01415 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.01281 | 0.05000 | **PASS** |
| a_return_curve_correlation | 0.99855 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.03740 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.14043 | 0.05000 | **FAIL** |
| top_tail_delta | 0.15951 | abs <= 0.10000 deg | **FAIL** |
| bottom_tail_delta | 0.01908 | abs <= 0.10000 deg | **PASS** |
| zero_shift_curve_correlation | 0.99331 | >= 0.98000 | **PASS** |
| zero_shift_centered_rmse | 0.08289 | <= 0.10000 deg | **PASS** |
| closure | 0.04895 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.17756° | -101.48° | 0.00292° |
| A1 | H2 | 0.11390° | -156.73° | 0.00585° |
| A1 | H4 | 0.05499° | -135.60° | 0.00331° |
| A1 | H8 | 0.01307° | 152.70° | 0.00118° |
| A1 | H9 | 0.17106° | 92.27° | 0.00378° |
| A1 | H18 | 0.11099° | -85.34° | 0.00028° |
| A1 | H36 | 0.89919° | 98.54° | 0.00135° |
| B | H1 | 0.25426° | -91.96° | 0.00554° |
| B | H2 | 0.16333° | -169.32° | 0.00312° |
| B | H4 | 0.07435° | -158.84° | 0.00096° |
| B | H8 | 0.01507° | 123.93° | 0.00063° |
| B | H9 | 0.17433° | 92.36° | 0.00083° |
| B | H18 | 0.11207° | -86.27° | 0.00208° |
| B | H36 | 0.89508° | 98.30° | 0.00217° |
| A2 | H1 | 0.18190° | -109.28° | 0.00071° |
| A2 | H2 | 0.12243° | -166.59° | 0.00193° |
| A2 | H4 | 0.05782° | -134.01° | 0.00100° |
| A2 | H8 | 0.01334° | 145.74° | 0.00155° |
| A2 | H9 | 0.17205° | 92.05° | 0.00185° |
| A2 | H18 | 0.10865° | -85.48° | 0.00117° |
| A2 | H36 | 0.89706° | 98.45° | 0.00062° |

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
