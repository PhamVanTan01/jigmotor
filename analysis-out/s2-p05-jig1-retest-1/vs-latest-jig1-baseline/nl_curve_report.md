# NL pointwise-curve assessment — p05

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: FAIL / CONFOUNDED**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 3.15138° | 0.00666° | 1.50354° | -1.64785° | 0.11033° | 0.11993° |
| B | JIG1 | 3 | 3.05773° | 0.00523° | 1.39453° | -1.66320° | 0.05323° | 0.06018° |
| A2 | JIG1 | 3 | 2.88776° | 0.02010° | 1.66912° | -1.21865° | 0.05600° | 0.12091° |

## A-B-A effects

- A1→A2 NL drift: `-0.26362°`.
- A1→A2 curve correlation/RMSE: `r=0.96836`, `0.18582°`.
- B−mean(A1,A2) NL effect: `+0.03816°`.
- B−A top-tail effect: `-0.19180°`.
- B−A bottom-tail effect: `-0.22996°`.
- Zero-shift curve correlation: `0.72446`.
- Zero-shift centered RMSE: `0.53763°`.
- Best circular alignment (diagnostic only): `340.0°`, `r=0.90852`, `RMSE=0.30986°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.02010 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.26362 | 0.05000 | **FAIL** |
| a_return_curve_correlation | 0.96836 | >= 0.98000 | **FAIL** |
| a_return_centered_rmse | 0.18582 | <= 0.10000 deg | **FAIL** |
| cross_jig_nl_delta | 0.03816 | 0.05000 | **PASS** |
| top_tail_delta | -0.19180 | abs <= 0.10000 deg | **FAIL** |
| bottom_tail_delta | -0.22996 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.72446 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.53763 | <= 0.10000 deg | **FAIL** |
| closure | 0.12091 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.45738° | -63.14° | 0.00678° |
| A1 | H2 | 0.11575° | -62.19° | 0.01024° |
| A1 | H4 | 0.06744° | -101.37° | 0.00085° |
| A1 | H8 | 0.01931° | -119.97° | 0.00120° |
| A1 | H9 | 0.28144° | 159.27° | 0.00161° |
| A1 | H18 | 0.10402° | 114.64° | 0.00062° |
| A1 | H36 | 0.85064° | 93.48° | 0.00145° |
| B | H1 | 0.23130° | -74.80° | 0.00155° |
| B | H2 | 0.36198° | 104.74° | 0.00058° |
| B | H4 | 0.03560° | 114.02° | 0.00023° |
| B | H8 | 0.01390° | -90.75° | 0.00112° |
| B | H9 | 0.28437° | -25.15° | 0.00044° |
| B | H18 | 0.09159° | 117.38° | 0.00107° |
| B | H36 | 0.85327° | 93.44° | 0.00174° |
| A2 | H1 | 0.34524° | -77.06° | 0.00434° |
| A2 | H2 | 0.10771° | 179.21° | 0.01173° |
| A2 | H4 | 0.02095° | -35.49° | 0.00384° |
| A2 | H8 | 0.02279° | -68.72° | 0.00313° |
| A2 | H9 | 0.27327° | 159.17° | 0.00039° |
| A2 | H18 | 0.10396° | 119.34° | 0.00101° |
| A2 | H36 | 0.85277° | 93.84° | 0.00248° |

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
