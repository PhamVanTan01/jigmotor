# NL pointwise-curve assessment — p03

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: FAIL / CONFOUNDED**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 2.64587° | 0.02238° | 1.73687° | -0.90901° | 0.19881° | 0.03622° |
| B | JIG1 | 3 | 2.60012° | 0.02797° | 1.63545° | -0.96467° | 0.20057° | 0.06952° |
| A2 | JIG1 | 3 | 2.58113° | 0.00780° | 1.66127° | -0.91986° | 0.10744° | 0.05957° |

## A-B-A effects

- A1→A2 NL drift: `-0.06474°`.
- A1→A2 curve correlation/RMSE: `r=0.99897`, `0.03251°`.
- B−mean(A1,A2) NL effect: `-0.01338°`.
- B−A top-tail effect: `-0.06362°`.
- B−A bottom-tail effect: `-0.05024°`.
- Zero-shift curve correlation: `0.99883`.
- Zero-shift centered RMSE: `0.03375°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.99883`, `RMSE=0.03375°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.02797 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.06474 | 0.05000 | **FAIL** |
| a_return_curve_correlation | 0.99897 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.03251 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.01338 | 0.05863 | **PASS** |
| top_tail_delta | -0.06362 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | -0.05024 | abs <= 0.10000 deg | **PASS** |
| zero_shift_curve_correlation | 0.99883 | >= 0.98000 | **PASS** |
| zero_shift_centered_rmse | 0.03375 | <= 0.10000 deg | **PASS** |
| closure | 0.06952 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.17858° | -113.51° | 0.00275° |
| A1 | H2 | 0.14083° | -173.01° | 0.00486° |
| A1 | H4 | 0.04766° | -139.90° | 0.00097° |
| A1 | H8 | 0.01364° | 119.40° | 0.00006° |
| A1 | H9 | 0.17369° | 91.88° | 0.00048° |
| A1 | H18 | 0.11200° | -85.79° | 0.00147° |
| A1 | H36 | 0.90214° | 98.61° | 0.00270° |
| B | H1 | 0.17393° | -108.22° | 0.00107° |
| B | H2 | 0.13903° | -167.65° | 0.00080° |
| B | H4 | 0.05093° | -135.37° | 0.00092° |
| B | H8 | 0.01151° | 141.12° | 0.00057° |
| B | H9 | 0.17158° | 92.20° | 0.00056° |
| B | H18 | 0.11045° | -85.01° | 0.00103° |
| B | H36 | 0.89939° | 98.48° | 0.00179° |
| A2 | H1 | 0.16933° | -111.20° | 0.00202° |
| A2 | H2 | 0.12768° | -165.05° | 0.00086° |
| A2 | H4 | 0.04848° | -145.26° | 0.00200° |
| A2 | H8 | 0.01338° | 131.73° | 0.00052° |
| A2 | H9 | 0.17489° | 91.89° | 0.00064° |
| A2 | H18 | 0.11272° | -85.97° | 0.00055° |
| A2 | H36 | 0.89395° | 98.62° | 0.00106° |

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
