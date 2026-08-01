# NL pointwise-curve assessment — p03

**Primary A-B-A verdict: FAIL**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 2.59082° | 0.00662° | 1.61227° | -0.97855° | 0.10861° | 0.02063° |
| B | JIG4 | 3 | 2.58412° | 0.02545° | 1.56407° | -1.02005° | 0.12951° | 0.01581° |
| A2 | JIG1 | 3 | 2.60362° | 0.01415° | 1.64743° | -0.95620° | 0.13575° | 0.04895° |

## A-B-A effects

- A1→A2 NL drift: `+0.01281°`.
- B−mean(A1,A2) NL effect: `-0.01310°`.
- B−A top-tail effect: `-0.06578°`.
- B−A bottom-tail effect: `-0.05268°`.
- Zero-shift curve correlation: `0.98829`.
- Zero-shift centered RMSE: `0.10662°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.98829`, `RMSE=0.10662°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.02545 | <= 0.03000 deg | **PASS** |
| cross_jig_nl_delta | 0.01310 | 0.05000 | **PASS** |
| top_tail_delta | -0.06578 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | -0.05268 | abs <= 0.10000 deg | **PASS** |
| zero_shift_curve_correlation | 0.98829 | >= 0.98000 | **PASS** |
| zero_shift_centered_rmse | 0.10662 | <= 0.10000 deg | **FAIL** |
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
| B | H1 | 0.13698° | -84.32° | 0.00210° |
| B | H2 | 0.15645° | -133.59° | 0.00150° |
| B | H4 | 0.05179° | -127.75° | 0.00109° |
| B | H8 | 0.00607° | 131.21° | 0.00078° |
| B | H9 | 0.16290° | 92.26° | 0.00066° |
| B | H18 | 0.10675° | -83.22° | 0.00139° |
| B | H36 | 0.90595° | 98.55° | 0.00189° |
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
