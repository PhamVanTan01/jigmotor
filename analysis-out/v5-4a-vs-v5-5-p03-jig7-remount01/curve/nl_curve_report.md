# NL pointwise-curve assessment — UNKNOWN

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: PASS**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG7 | 3 | 0.53398° | 0.01591° | 0.10807° | -0.42591° | 0.20564° | 0.10352° |
| B | JIG7 | 2 | 0.39366° | 0.07940° | 0.10582° | -0.28783° | 0.13438° | 0.09454° |
| A2 | JIG7 | 3 | 0.53398° | 0.01591° | 0.10807° | -0.42591° | 0.20564° | 0.10352° |

## A-B-A effects

- A1→A2 NL drift: `+0.00000°`.
- A1→A2 curve correlation/RMSE: `r=1.00000`, `0.00000°`.
- B−mean(A1,A2) NL effect: `-0.14032°`.
- B−A top-tail effect: `-0.00224°`.
- B−A bottom-tail effect: `+0.13807°`.
- Zero-shift curve correlation: `0.87190`.
- Zero-shift centered RMSE: `0.06245°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.87190`, `RMSE=0.06245°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.07940 | <= 0.03000 deg | **FAIL** |
| a_return_nl_shift | 0.00000 | 0.05000 | **PASS** |
| a_return_curve_correlation | 1.00000 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.00000 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.14032 | 0.10596 | **FAIL** |
| top_tail_delta | -0.00224 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | 0.13807 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.87190 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.06245 | <= 0.10000 deg | **PASS** |
| closure | 0.10352 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=1; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **FAIL** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.02274° | -102.18° | 0.00358° |
| A1 | H2 | 0.00441° | -73.62° | 0.00245° |
| A1 | H4 | 0.00422° | 75.58° | 0.00014° |
| A1 | H8 | 0.00130° | 131.04° | 0.00065° |
| A1 | H9 | 0.02879° | 75.01° | 0.00106° |
| A1 | H18 | 0.02654° | -64.81° | 0.00135° |
| A1 | H36 | 0.14381° | 90.32° | 0.00362° |
| B | H1 | 0.01562° | -100.43° | 0.00111° |
| B | H2 | 0.00290° | -21.11° | 0.00048° |
| B | H4 | 0.00326° | 72.34° | 0.00056° |
| B | H8 | 0.00749° | 17.17° | 0.00145° |
| B | H9 | 0.01635° | 75.01° | 0.00126° |
| B | H18 | 0.01534° | -81.99° | 0.00260° |
| B | H36 | 0.10744° | 90.04° | 0.00432° |
| A2 | H1 | 0.02274° | -102.18° | 0.00358° |
| A2 | H2 | 0.00441° | -73.62° | 0.00245° |
| A2 | H4 | 0.00422° | 75.58° | 0.00014° |
| A2 | H8 | 0.00130° | 131.04° | 0.00065° |
| A2 | H9 | 0.02879° | 75.01° | 0.00106° |
| A2 | H18 | 0.02654° | -64.81° | 0.00135° |
| A2 | H36 | 0.14381° | 90.32° | 0.00362° |

## Data health

- CONFIG gate scan: **PASS** (12 CONFIG records).
- Invalid declared-OFFICIAL sweeps: `1`.
- Statistically eligible OFFICIAL sweeps: `8`.
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
