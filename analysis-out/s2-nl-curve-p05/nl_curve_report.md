# NL pointwise-curve assessment — p05

**Primary A-B-A verdict: FAIL**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 3.06151° | 0.04014° | 1.45249° | -1.60902° | 0.06527° | 0.10309° |
| B | JIG4 | 3 | 2.92531° | 0.01379° | 1.68155° | -1.24376° | 0.10343° | 0.10730° |
| A2 | JIG1 | 3 | 3.10286° | 0.00917° | 1.56601° | -1.53686° | 0.05545° | 0.11603° |

## A-B-A effects

- A1→A2 NL drift: `+0.04136°`.
- B−mean(A1,A2) NL effect: `-0.15688°`.
- B−A top-tail effect: `+0.17230°`.
- B−A bottom-tail effect: `+0.32918°`.
- Zero-shift curve correlation: `0.96482`.
- Zero-shift centered RMSE: `0.19269°`.
- Best circular alignment (diagnostic only): `320.0°`, `r=0.98640`, `RMSE=0.12012°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.04014 | <= 0.03000 deg | **FAIL** |
| cross_jig_nl_delta | 0.15688 | 0.08335 | **FAIL** |
| top_tail_delta | 0.17230 | abs <= 0.10000 deg | **FAIL** |
| bottom_tail_delta | 0.32918 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.96482 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.19269 | <= 0.10000 deg | **FAIL** |
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
| B | H1 | 0.34935° | -91.56° | 0.00270° |
| B | H2 | 0.06481° | -121.87° | 0.00104° |
| B | H4 | 0.03727° | 41.06° | 0.00700° |
| B | H8 | 0.00780° | -124.91° | 0.00193° |
| B | H9 | 0.27330° | 160.45° | 0.00158° |
| B | H18 | 0.10195° | 115.52° | 0.00188° |
| B | H36 | 0.87437° | 93.64° | 0.00364° |
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
