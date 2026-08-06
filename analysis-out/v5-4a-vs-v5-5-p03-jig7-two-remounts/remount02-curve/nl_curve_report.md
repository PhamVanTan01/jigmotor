# NL pointwise-curve assessment — UNKNOWN

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: PASS**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG7 | 2 | 0.58693° | 0.00544° | 0.10794° | -0.47899° | 0.26231° | 0.09201° |
| B | JIG7 | 3 | 0.47481° | 0.01345° | 0.10655° | -0.36826° | 0.10328° | 0.10577° |
| A2 | JIG7 | 2 | 0.58693° | 0.00544° | 0.10794° | -0.47899° | 0.26231° | 0.09201° |

## A-B-A effects

- A1→A2 NL drift: `+0.00000°`.
- A1→A2 curve correlation/RMSE: `r=1.00000`, `0.00000°`.
- B−mean(A1,A2) NL effect: `-0.11212°`.
- B−A top-tail effect: `-0.00139°`.
- B−A bottom-tail effect: `+0.11073°`.
- Zero-shift curve correlation: `0.87092`.
- Zero-shift centered RMSE: `0.06805°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.87092`, `RMSE=0.06805°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.01345 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.00000 | 0.05000 | **PASS** |
| a_return_curve_correlation | 1.00000 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.00000 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.11212 | 0.05000 | **FAIL** |
| top_tail_delta | -0.00139 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | 0.11073 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.87092 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.06805 | <= 0.10000 deg | **PASS** |
| closure | 0.10577 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=2; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **FAIL** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.02462° | -100.26° | 0.00211° |
| A1 | H2 | 0.00488° | -6.27° | 0.00040° |
| A1 | H4 | 0.00609° | 92.66° | 0.00327° |
| A1 | H8 | 0.00355° | 60.56° | 0.00139° |
| A1 | H9 | 0.03097° | 77.30° | 0.00259° |
| A1 | H18 | 0.02615° | -63.09° | 0.00155° |
| A1 | H36 | 0.15741° | 93.98° | 0.00776° |
| B | H1 | 0.01269° | -108.79° | 0.00117° |
| B | H2 | 0.00354° | -56.28° | 0.00143° |
| B | H4 | 0.00733° | 70.32° | 0.00152° |
| B | H8 | 0.00759° | 17.49° | 0.00132° |
| B | H9 | 0.02105° | 78.08° | 0.00049° |
| B | H18 | 0.01992° | -76.09° | 0.00080° |
| B | H36 | 0.10993° | 88.87° | 0.00160° |
| A2 | H1 | 0.02462° | -100.26° | 0.00211° |
| A2 | H2 | 0.00488° | -6.27° | 0.00040° |
| A2 | H4 | 0.00609° | 92.66° | 0.00327° |
| A2 | H8 | 0.00355° | 60.56° | 0.00139° |
| A2 | H9 | 0.03097° | 77.30° | 0.00259° |
| A2 | H18 | 0.02615° | -63.09° | 0.00155° |
| A2 | H36 | 0.15741° | 93.98° | 0.00776° |

## Data health

- CONFIG gate scan: **PASS** (11 CONFIG records).
- Invalid declared-OFFICIAL sweeps: `2`.
- Statistically eligible OFFICIAL sweeps: `7`.
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
- At least one leg has fewer than 3 eligible runs; SD/gates are low-confidence.
