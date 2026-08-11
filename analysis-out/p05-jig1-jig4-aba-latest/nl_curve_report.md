# NL pointwise-curve assessment — p05

**Primary A-B-A verdict: FAIL**

**A1→A2 baseline return: FAIL / CONFOUNDED**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 3.15138° | 0.00666° | 1.50354° | -1.64785° | 0.11033° | 0.11993° |
| B | JIG4 | 2 | 2.75177° | 0.02856° | 1.64059° | -1.11118° | 0.09631° | 0.11774° |
| A2 | JIG1 | 3 | 2.88776° | 0.02010° | 1.66912° | -1.21865° | 0.05600° | 0.12091° |

## A-B-A effects

- A1→A2 NL drift: `-0.26362°`.
- A1→A2 curve correlation/RMSE: `r=0.96836`, `0.18582°`.
- B−mean(A1,A2) NL effect: `-0.26780°`.
- B−A top-tail effect: `+0.05427°`.
- B−A bottom-tail effect: `+0.32207°`.
- Zero-shift curve correlation: `0.97947`.
- Zero-shift centered RMSE: `0.14519°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.97947`, `RMSE=0.14519°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.02856 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.26362 | 0.05000 | **FAIL** |
| a_return_curve_correlation | 0.96836 | >= 0.98000 | **FAIL** |
| a_return_centered_rmse | 0.18582 | <= 0.10000 deg | **FAIL** |
| cross_jig_nl_delta | 0.26780 | 0.05126 | **FAIL** |
| top_tail_delta | 0.05427 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | 0.32207 | abs <= 0.10000 deg | **FAIL** |
| zero_shift_curve_correlation | 0.97947 | >= 0.98000 | **FAIL** |
| zero_shift_centered_rmse | 0.14519 | <= 0.10000 deg | **FAIL** |
| closure | 0.12091 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=1; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **FAIL** |

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
| B | H1 | 0.24677° | -79.19° | 0.00781° |
| B | H2 | 0.14381° | -148.91° | 0.02153° |
| B | H4 | 0.01332° | 39.63° | 0.00192° |
| B | H8 | 0.00725° | -173.93° | 0.00190° |
| B | H9 | 0.26840° | 160.37° | 0.00303° |
| B | H18 | 0.10206° | 117.60° | 0.00061° |
| B | H36 | 0.86905° | 93.54° | 0.00064° |
| A2 | H1 | 0.34524° | -77.06° | 0.00434° |
| A2 | H2 | 0.10771° | 179.21° | 0.01173° |
| A2 | H4 | 0.02095° | -35.49° | 0.00384° |
| A2 | H8 | 0.02279° | -68.72° | 0.00313° |
| A2 | H9 | 0.27327° | 159.17° | 0.00039° |
| A2 | H18 | 0.10396° | 119.34° | 0.00101° |
| A2 | H36 | 0.85277° | 93.84° | 0.00248° |

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

- P05 JIG4-B.txt:7254: malformed DATA line, skipped: DATA,5,4,4,JIG4,p05,CW,152,37947,37839,ection=CW,Point=152,RampAcceptedSamples=4
- At least one leg has fewer than 3 eligible runs; SD/gates are low-confidence.
