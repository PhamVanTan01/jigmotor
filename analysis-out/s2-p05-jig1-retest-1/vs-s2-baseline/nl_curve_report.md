# NL pointwise-curve assessment — p05

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: FAIL / CONFOUNDED**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 3.06151° | 0.04014° | 1.45249° | -1.60902° | 0.06527° | 0.10309° |
| B | JIG1 | 3 | 3.05773° | 0.00523° | 1.39453° | -1.66320° | 0.05323° | 0.06018° |
| A2 | JIG1 | 3 | 3.10286° | 0.00917° | 1.56601° | -1.53686° | 0.05545° | 0.11603° |

## A-B-A effects

- A1→A2 NL drift: `+0.04136°`.
- A1→A2 curve correlation/RMSE: `r=0.97704`, `0.15815°`.
- B−mean(A1,A2) NL effect: `-0.02445°`.
- B−A top-tail effect: `-0.11472°`.
- B−A bottom-tail effect: `-0.09026°`.
- Zero-shift curve correlation: `0.70820`.
- Zero-shift centered RMSE: `0.55745°`.
- Best circular alignment (diagnostic only): `300.0°`, `r=0.89690`, `RMSE=0.33137°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.04014 | <= 0.03000 deg | **FAIL** |
| a_return_nl_shift | 0.04136 | 0.05000 | **PASS** |
| a_return_curve_correlation | 0.97704 | >= 0.98000 | **FAIL** |
| a_return_centered_rmse | 0.15815 | <= 0.10000 deg | **FAIL** |
| cross_jig_nl_delta | 0.02445 | 0.06638 | **PASS** |
| top_tail_delta | -0.11472 | abs <= 0.10000 deg | **FAIL** |
| bottom_tail_delta | -0.09026 | abs <= 0.10000 deg | **PASS** |
| zero_shift_curve_correlation | 0.70820 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.55745 | <= 0.10000 deg | **FAIL** |
| closure | 0.11603 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.41389° | -46.71° | 0.01295° |
| A1 | H2 | 0.05321° | -61.58° | 0.02612° |
| A1 | H4 | 0.03960° | -135.94° | 0.00188° |
| A1 | H8 | 0.02111° | -107.06° | 0.00158° |
| A1 | H9 | 0.27568° | 161.47° | 0.00089° |
| A1 | H18 | 0.10862° | 112.63° | 0.00291° |
| A1 | H36 | 0.85760° | 93.58° | 0.00175° |
| B | H1 | 0.23130° | -74.80° | 0.00155° |
| B | H2 | 0.36198° | 104.74° | 0.00058° |
| B | H4 | 0.03560° | 114.02° | 0.00023° |
| B | H8 | 0.01390° | -90.75° | 0.00112° |
| B | H9 | 0.28437° | -25.15° | 0.00044° |
| B | H18 | 0.09159° | 117.38° | 0.00107° |
| B | H36 | 0.85327° | 93.44° | 0.00174° |
| A2 | H1 | 0.45827° | -71.18° | 0.00366° |
| A2 | H2 | 0.10676° | -91.97° | 0.00229° |
| A2 | H4 | 0.06138° | -93.47° | 0.00173° |
| A2 | H8 | 0.01584° | -117.61° | 0.00095° |
| A2 | H9 | 0.28190° | 159.27° | 0.00082° |
| A2 | H18 | 0.10587° | 116.93° | 0.00019° |
| A2 | H36 | 0.84989° | 93.34° | 0.00123° |

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
