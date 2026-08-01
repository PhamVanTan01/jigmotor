# NL pointwise-curve assessment — p05

**Primary A-B-A verdict: PASS**

**A1→A2 baseline return: PASS**

This report evaluates the 0..359 pointwise error curve. `Robust NL` remains the run-level top-5 minus bottom-5 statistic; no individual point is labeled as NL. Closure at index 360 is checked separately.

## Batch summary

| Leg | Jig | Runs | Robust NL mean | NL SD | Top tail | Bottom tail | Max shape SD | Closure max abs |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | JIG1 | 3 | 3.22655° | 0.01170° | 1.84962° | -1.37693° | 0.05193° | 0.10785° |
| B | JIG1 | 3 | 3.24097° | 0.00726° | 1.83604° | -1.40493° | 0.04112° | 0.11816° |
| A2 | JIG1 | 3 | 3.22858° | 0.01077° | 1.81971° | -1.40887° | 0.05544° | 0.10217° |

## A-B-A effects

- A1→A2 NL drift: `+0.00203°`.
- A1→A2 curve correlation/RMSE: `r=0.99971`, `0.01829°`.
- B−mean(A1,A2) NL effect: `+0.01341°`.
- B−A top-tail effect: `+0.00138°`.
- B−A bottom-tail effect: `-0.01203°`.
- Zero-shift curve correlation: `0.99991`.
- Zero-shift centered RMSE: `0.01063°`.
- Best circular alignment (diagnostic only): `0.0°`, `r=0.99991`, `RMSE=0.01063°`.

The zero-shift values are the primary interchangeability result. Best circular alignment is reported explicitly as a diagnostic and is never applied silently.

## Frozen pilot gates

| Gate | Value | Limit | Result |
|---|---:|---:|---|
| within_batch_nl_sd | 0.01170 | <= 0.03000 deg | **PASS** |
| a_return_nl_shift | 0.00203 | 0.05000 | **PASS** |
| a_return_curve_correlation | 0.99971 | >= 0.98000 | **PASS** |
| a_return_centered_rmse | 0.01829 | <= 0.10000 deg | **PASS** |
| cross_jig_nl_delta | 0.01341 | 0.05000 | **PASS** |
| top_tail_delta | 0.00138 | abs <= 0.10000 deg | **PASS** |
| bottom_tail_delta | -0.01203 | abs <= 0.10000 deg | **PASS** |
| zero_shift_curve_correlation | 0.99991 | >= 0.98000 | **PASS** |
| zero_shift_centered_rmse | 0.01063 | <= 0.10000 deg | **PASS** |
| closure | 0.11816 | abs <= 0.20000 deg | **PASS** |
| data_health | invalid=0; config=PASS | 0 invalid OFFICIAL; CONFIG=PASS | **PASS** |

## Selected harmonic fingerprint

| Leg | Order | Mean-curve amplitude | Mean-curve phase | Run amplitude SD |
|---|---:|---:|---:|---:|
| A1 | H1 | 0.49918° | -67.88° | 0.00368° |
| A1 | H2 | 0.17031° | -173.82° | 0.00191° |
| A1 | H4 | 0.06055° | -112.45° | 0.00439° |
| A1 | H8 | 0.01418° | -120.95° | 0.00043° |
| A1 | H9 | 0.27801° | 158.45° | 0.00089° |
| A1 | H18 | 0.10134° | 113.41° | 0.00091° |
| A1 | H36 | 0.85662° | 93.45° | 0.00088° |
| B | H1 | 0.51297° | -67.54° | 0.00177° |
| B | H2 | 0.16675° | -175.81° | 0.00211° |
| B | H4 | 0.05908° | -105.45° | 0.00052° |
| B | H8 | 0.01557° | -120.38° | 0.00062° |
| B | H9 | 0.27681° | 158.68° | 0.00142° |
| B | H18 | 0.10196° | 113.87° | 0.00058° |
| B | H36 | 0.85279° | 93.49° | 0.00049° |
| A2 | H1 | 0.50836° | -67.22° | 0.00432° |
| A2 | H2 | 0.16524° | -176.43° | 0.00088° |
| A2 | H4 | 0.05855° | -102.58° | 0.00111° |
| A2 | H8 | 0.01394° | -119.11° | 0.00027° |
| A2 | H9 | 0.27782° | 158.68° | 0.00077° |
| A2 | H18 | 0.10208° | 112.79° | 0.00007° |
| A2 | H36 | 0.85189° | 93.53° | 0.00048° |

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
