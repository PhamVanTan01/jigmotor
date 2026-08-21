# NL mounting-vector model assessment

## Scope and measurement contract

- Source: `C:\Users\PHAMVA~1\AppData\Local\Temp\claude\d--tanpham-QAtoool-jigtest-motor-jigmotor\79304c97-307b-4bab-90ad-b554bac88497\scratchpad\nl_vector_model_curves.csv`
- Curves: 13; config-baseline pairs: 9.
- Classification: `OPEN_LOOP_MEASUREMENT` offline analysis.
- Official measurand is unchanged: this report does not correct DATA or publish an adjusted NL.
- Primary shape decomposition uses the common sweep-command/index frame so the known motor H36 fingerprint can cancel.
- A second sensor-raw frame (`theta_start_deg + index`) is evaluated separately for absolute-phase claims.
- Effective sweep count is used only as a reliability weight; individual-sweep variance is unavailable.
- Phase convention: `a*cos(k*theta)+b*sin(k*theta)=A*cos(k*theta-phase)`, matching the existing project analyzer.

## Executive conclusions

1. **H1-H2 is the correct first-order mounting model, but is not sufficient for precision:** it explains `81.3%` of weighted curve variance; H1-H6 reaches `90.2%`, and H1-H18 reaches `95.9%`.
2. **A config-only correction is not transferable to an unseen motor:** leave-one-motor-out prediction is worse than applying no correction for every tested config (`-51.0%` to `-23.6%` improvement). The motor×mount/config interaction is therefore part of the measured response.
3. **The supplied `theta_start_deg + index` coordinate is not a validated shared physical-angle reference:** mean H36 cancellation error grows from `0.0049 deg` in the command frame to `0.5102 deg` in that sensor-raw frame. Absolute H1/H2 axes cannot yet be mapped to the magnet N/S direction without an external fiducial or field reference.
4. **The response is multi-mode, not one universal eccentricity vector:** the first three PCA components explain `94.8%` together. The strongest residual orders are H4=5 pair(s), H12=4 pair(s); current evidence favors additional harmonics over a non-harmonic step/pulse model.
5. **No official NL value is corrected by this work.** These models decompose and test the mounting response only; they do not create a product pass/fail threshold.

## 1. How many harmonics are needed?

Weighted aggregate fit quality:

| Model | Weighted R² | Weighted residual RMSE (deg) |
|---|---:|---:|
| H1-H1 | 0.3976 | 0.1233 |
| H1-H2 | 0.8131 | 0.0625 |
| H1-H3 | 0.8459 | 0.0545 |
| H1-H6 | 0.9017 | 0.0404 |
| H1-H18 | 0.9591 | 0.0251 |

Dominant order among H1-H6 by pair: H1=5 pair(s), H2=4 pair(s)

Per-pair details are in `pair_model_metrics.csv` and `pair_harmonic_coefficients.csv`.
A large H3-to-H6 or H18 improvement indicates structure beyond a pure H1/H2 eccentricity vector.
The residual-localization column tests whether remaining energy is concentrated in a small angular window.

## 2. Config-only model versus motor×config interaction

| Config | Motors | Common coefficient fraction | Interaction fraction | Zero RMSE | LOO config-only RMSE | Pair-specific H1-H6 RMSE | LOO improvement |
|---|---:|---:|---:|---:|---:|---:|---:|
| path1 | 2 | 0.509 | 0.491 | 0.2535 | 0.3829 | 0.0410 | -51.0% |
| path2_new | 3 | 0.401 | 0.599 | 0.1991 | 0.2496 | 0.0442 | -25.4% |
| path2_old | 4 | 0.289 | 0.711 | 0.1924 | 0.2377 | 0.0377 | -23.6% |

Interpretation rule: a config-only correction is transferable only when its leave-one-motor-out RMSE
is materially below the zero-correction RMSE. A negative LOO improvement means the shared config table
would make an unseen motor worse, which is direct evidence of motor×config interaction.

## 3. Reference-frame validity check using motor-intrinsic H36

If `theta_start_deg + index` were a shared physical-angle reference across mounting/sensor changes,
the known motor-intrinsic H36 should cancel at least as well there as in the common command frame.

| Pair | H36 delta in command frame (deg) | H36 delta in sensor-absolute frame (deg) | Ratio |
|---|---:|---:|---:|
| P011/path1 | 0.0030 | 0.6660 | 219.69 |
| P011/path2_new | 0.0062 | 0.2971 | 47.80 |
| P011/path2_old | 0.0032 | 0.0102 | 3.22 |
| P013/path2_new | 0.0047 | 0.0904 | 19.41 |
| P013/path2_old | 0.0060 | 0.5800 | 96.85 |
| P03/path2_old | 0.0061 | 0.6326 | 104.50 |
| P08/path1 | 0.0012 | 0.5105 | 432.62 |
| P08/path2_new | 0.0062 | 0.7692 | 123.78 |
| P08/path2_old | 0.0074 | 1.0357 | 140.29 |

Mean H36 delta amplitude: command frame `0.0049°`; sensor-absolute frame `0.5102°`.
This is an internal falsification test for the proposed absolute reference; it does not alter official NL.

## 4. H1/H2 phase and the N-S transition hypothesis

| Config | Order | Motors | Command-frame R | Sensor-absolute R | Sensor-absolute mean axis (deg) |
|---|---:|---:|---:|---:|---:|
| path1 | H1 | 2 | 0.949 | 0.991 | 323.37 |
| path1 | H2 | 2 | 0.734 | 0.978 | 145.56 |
| path2_new | H1 | 3 | 0.702 | 0.786 | 279.38 |
| path2_new | H2 | 3 | 0.072 | 0.328 | 64.71 |
| path2_old | H1 | 4 | 0.110 | 0.022 | 122.08 |
| path2_old | H2 | 4 | 0.853 | 0.649 | 49.33 |

`R≈1` means phases cluster; `R≈0` means they disperse/cancel. H2 axis is modulo 180°.
The phase identifies an error-field axis, not the physical N/S magnet direction by itself.
If the H36 check above rejects the sensor-absolute frame, these absolute axes must be treated as uncalibrated.
A marked magnet orientation or an independent magnetic-field reference is still required to map that axis
to the actual N-S transition.

## 5. PCA

| PC | Explained variance | Cumulative |
|---:|---:|---:|
| 1 | 0.550 | 0.550 |
| 2 | 0.264 | 0.814 |
| 3 | 0.134 | 0.948 |
| 4 | 0.023 | 0.972 |
| 5 | 0.016 | 0.988 |
| 6 | 0.006 | 0.994 |

PCA is descriptive only: there are nine pair curves and no balanced four-config design.
A strong PC1 shows a low-dimensional response family, but it does not prove a universal config correction.

## 6. Largest residual spectral terms after the low-order region

| Pair | Largest order in H4-H60 | Amplitude (deg) |
|---|---:|---:|
| P011/path1 | H4 | 0.0880 |
| P011/path2_new | H4 | 0.0709 |
| P011/path2_old | H12 | 0.0317 |
| P013/path2_new | H4 | 0.0446 |
| P013/path2_old | H4 | 0.0265 |
| P03/path2_old | H12 | 0.0493 |
| P08/path1 | H4 | 0.0526 |
| P08/path2_new | H12 | 0.0343 |
| P08/path2_old | H12 | 0.0365 |

## Limitations

- Only one physical jig/MCU is present; no cross-jig statement can be made.
- Each config is already an averaged curve. Sweep-level variance and a valid mixed-effects p-value cannot be reconstructed.
- The design is unbalanced: path1 has two motors, path2_new three, path2_old four.
- Baseline is shared within each motor, so pair differences are statistically correlated.
- Sensor replacement and mounting path are confounded in `path2_new` versus `path2_old` unless additional controlled swaps are run.

## Generated evidence

- `pair_harmonic_coefficients.csv`
- `pair_model_metrics.csv`
- `config_interaction_summary.csv`
- `common_config_harmonics.csv`
- `pca_scores.csv`, `pca_summary.csv`
- `full_pair_spectrum_h1_h60.csv`
- `reference_frame_diagnostics.csv`
- `pair_command_frame_fits.png`, `harmonic_amplitude_heatmap.png`, `absolute_phase_vectors_h1_h2.png`
- `model_order_sufficiency.png`, `pca_scores.png`
