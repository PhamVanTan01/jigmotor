# Session summary — 2026-08-20

## NL mounting-vector model — full dataset evaluation

### Classification and contract

- Change classification: `OPEN_LOOP_MEASUREMENT` (offline analysis only).
- Purpose: improve traceability and validity of the mounting-induced component of the pure Gremsy-compatible open-loop NL curve.
- The firmware, motor command, canonical 64-sample point mean, official `Error[i]`, and `OpenLoopNL = max(Error)-min(Error)` are unchanged.
- The model does not correct official DATA, does not create an adjusted NL, and does not define any product pass/fail threshold.

### Inputs and checks

- Request: temporary `README_vector_model_request.md` supplied on 2026-08-20.
- Dataset: `nl_vector_model_curves.csv` from the same request package.
- Loaded 13 complete 360-point average curves: four baselines and nine config-minus-baseline pairs; no missing or duplicate angular indices were found.
- Dataset scope is one physical jig (`JIG7`) and one MCU. Therefore this evaluation does not close the repository's cross-jig comparability objective.
- Reliability weighting uses the effective sweep count of each config/baseline difference. Sweep-level variance is not recoverable from the already averaged input curves.
- The supplied preliminary P08/path2_old result was independently reproduced: H1 `0.1757 deg @ +45.23 deg`, H2 `0.3496 deg @ -56.03 deg`, H3 `0.0594 deg`, and H1-H3 `R²=0.9675`.

### Evidence and findings

1. Low-order Fourier structure is real, but H1-H2 alone is not a precision model across all pairs:
   - H1: weighted `R²=0.3976`, RMSE `0.1233 deg`.
   - H1-H2: weighted `R²=0.8131`, RMSE `0.0625 deg`.
   - H1-H3: weighted `R²=0.8459`, RMSE `0.0545 deg`.
   - H1-H6: weighted `R²=0.9017`, RMSE `0.0404 deg`.
   - H1-H18: weighted `R²=0.9591`, RMSE `0.0251 deg`.
   - H1 is dominant in 5/9 pairs and H2 in 4/9 pairs. The largest structured residual is H4 in 5/9 pairs and H12 in 4/9 pairs. Current data therefore supports additional harmonic terms before any non-harmonic step/pulse model.

2. A config-only mounting vector does not transfer to an unseen motor:
   - `path1`: common coefficient fraction `0.509`, interaction fraction `0.491`; leave-one-motor-out correction worsens RMSE by `51.0%` versus applying no correction.
   - `path2_new`: common `0.401`, interaction `0.599`; leave-one-motor-out correction worsens RMSE by `25.4%`.
   - `path2_old`: common `0.289`, interaction `0.711`; leave-one-motor-out correction worsens RMSE by `23.6%`.
   - A shared correction table indexed only by path/sensor config is therefore rejected by this dataset. The observed response contains a material motor×config interaction.

3. The proposed absolute phase reference `theta_start_deg + index` failed an internal falsification check:
   - The motor-intrinsic H36 should cancel in a valid shared physical-angle frame.
   - Mean config-minus-baseline H36 amplitude is only `0.0049 deg` in the common command/index frame, but rises to `0.5102 deg` after applying the proposed sensor-raw "absolute" frame.
   - Therefore `theta_start_deg` is a local sensor/raw origin, not a demonstrated external mechanical-angle reference across sensor/mount changes.
   - H1/H2 phase cannot yet identify the physical guide-magnet N/S direction. That requires a marked magnet/mechanical fiducial or an independent field reference.

4. PCA confirms more than one response mode:
   - PC1 `55.0%`, PC2 `26.4%`, PC3 `13.4%`; cumulative PC1-PC3 `94.8%`.
   - This is descriptive evidence for a low-dimensional but multi-mode interaction, not proof of a universal eccentricity vector.

### Outputs and reproducibility

- Analyzer: `tools/analyze_nl_mount_vector_model.py`.
- Output folder: `analysis-out/nl-mount-vector-model-2026-08-20/`.
- Main report: `analysis-out/nl-mount-vector-model-2026-08-20/nl_mount_vector_model_report.md`.
- The analyzer exports per-pair Fourier coefficients, fit-order metrics, interaction/LOO summaries, PCA, H1-H60 spectra, reference-frame diagnostics, and five plots.
- Verification completed with Python bytecode compilation, built-in synthetic Fourier/interpolation self-test, full 13-curve execution, and visual inspection of the generated command-frame fit plot.

### Decision advanced

- The request's three questions are answered for the available JIG7 dataset:
  1. H1-H2 is a useful primary physical model, but H1-H6 is required for better curve reconstruction; H4/H12 are recurring residuals.
  2. `H_mount` is not a config-only invariant and cannot currently support a per-config correction table across motors.
  3. Physical N/S orientation is not identifiable from the current phase metadata because the claimed absolute frame is invalidated by H36.
- Next controlled experiment, if pursued: add a real mechanical/magnetic fiducial and collect balanced repeated sweeps for each motor×config cell. Cross-jig qualification remains a separate mandatory step.

## Metrology verdict — current open-loop NL method and error budget

### Classification

- `OPEN_LOOP_MEASUREMENT`, evaluation-only. No firmware, command, capture, formula, schema, or official DATA was changed.
- Purpose: assess accuracy, repeatability, traceability, and cross-jig comparability of the current whole-system open-loop NL method.

### Verdict

- The schema-v6 S4 path is structurally correct for its declared measurand: fixed open-loop actuation, stability-only readiness, one canonical 64-sample mean per point, 360 official points, and `OpenLoopNL=max(Error)-min(Error)`.
- It is repeatable within the same motor+jig+mount instance: prior JIG7/JIG8 batches showed scalar CV `0.41–1.61%` and mean full-curve correlation `0.9976–0.9995`.
- It is not yet a qualified motor-only measurement system. The current result is the reproducible response of the complete motor–magnet–sensor–mount–jig assembly.
- Remount reproducibility, cross-jig comparability, physical-angle traceability, and trueness against an independent reference remain unsatisfied or unknown.

### Proven error mechanisms

1. Low-order mount/sensor/config structure changes the measured curve and its extrema. The 2026-08-20 model gives weighted `R²=0.8131` for H1-H2 and `0.9017` for H1-H6 on config-minus-baseline curves.
2. This effect is not a transferable config-only vector. Leave-one-motor-out config correction worsens prediction by `23.6–51.0%`, proving material motor×config interaction.
3. Cross-jig mismatch exceeds within-batch noise: prior JIG7/JIG8 data showed `2.09–16.59%` product-dependent NL differences, cross-jig curve correlation `0.9430–0.9851`, and exploratory product-rank Spearman `rho≈0.30`, despite A36 matching within `0.06–0.76%`.
4. Remount can change NL by up to `17.47%` in observed batches, so mounting-instance error can equal or exceed the cross-jig gap.
5. `theta_start_deg + index` is not a validated shared physical-angle frame: mean residual H36 grows from `0.0049 deg` in command coordinates to `0.5102 deg` in that sensor-raw frame. Absolute extrema and H1/H2 axes cannot be mapped to physical N/S orientation from current metadata.
6. Raw P2P is correctly implemented but intrinsically extrema-sensitive. Low-order envelopes select which H36/local peak and trough become the global extrema; therefore small structured fixture changes can move the scalar more than they move most of the 360-point curve.

### Remaining unquantified contributors

- Sensor gap, tilt, eccentricity, die-to-die response, clamp torque, bearing load, guide-magnet orientation/field, supply/driver gain, phase current, and temperature are plausible contributors but are not uniquely identifiable from the existing single-MA600 observation.
- The current averaged-curve dataset has unequal `n_sweeps` and no individual-sweep variance, so it cannot provide a complete uncertainty budget or a valid balanced mixed-effects/Gage R&R result.
- The project uses the Gremsy formula but not an identical acquisition contract (64 versus 5 samples, 1.0 versus about 1.406 degree grid, stability polling versus fixed 5 ms delay, 10 versus 1 sweep). Gremsy product limits cannot be transferred without calibration.
- A 1-degree sampled P2P is the maximum/minimum on that discrete grid, not a certified continuous-angle peak-to-peak value. Any interpolation/oversampling result must remain a supporting metric unless the measurement contract is deliberately versioned.

### Measurement-system decision

- Freeze the current S4 firmware/schema/analyzer; retuning power/ramp/dwell to force jig agreement would change the measurand.
- Do not apply a shared scalar or config-only correction learned from DUTs.
- Qualification requires an independent rotary/reference encoder or a fixed transfer-standard assembly with a marked mechanical/magnetic orientation, followed by randomized Gage R&R over motor × jig × remount with controlled gap/torque/orientation and environmental telemetry.
- Preserve and report raw 360-point curves, extrema, harmonics, acquisition validity, and raw `OpenLoopNL`; any jig calibration must be independently derived, versioned, applied only after DATA is frozen, and stored separately from the raw result.

## Detailed cross-jig calibration and Gage R&R execution plan

### Classification and scope

- Classification: `OPEN_LOOP_MEASUREMENT`, planning/metrology only.
- Purpose: improve accuracy, repeatability, traceability, validity, acquisition integrity, and especially
  JIG7/JIG8 comparability without changing the declared S4 measurand.
- No firmware, motor command, canonical 64-sample window, point grid, raw DATA, error formula, or official
  `OpenLoopNL` was changed in this step.
- No product pass/fail NL threshold was created. Any future equivalence margin is a versioned measurement-
  system requirement and must be declared independently before qualification data are inspected.

### Deliverable

- Created `docs/open-loop-nl-jig-calibration-gage-rr-plan-2026-08-20.md`.
- The plan freezes S4, establishes serialized jig/sensor-head/config identity, specifies an independent
  coaxial angle-reference or relative transfer-standard fallback, and requires mounting DOE/SOP control
  for gap, torque, orientation, tilt, eccentricity, field, temperature, and supply.
- It separates raw official whole-system NL from a secondary offline
  `JigCalibratedResponseEstimate`; raw logs and raw `OpenLoopNL` remain immutable and correction can never
  feed the command or rescue invalid DATA.
- It defines a 12-batch raw pilot, a simulation-sized crossed motor×jig×operator-day×remount study,
  hierarchical scalar and functional-curve analysis, uncertainty propagation, independent holdouts,
  calibration retirement, check-standard surveillance, and explicit hard-stop rules.
- Four allowed outcomes are locked: `RAW_INTERCHANGEABLE`, `DERIVED_CALIBRATED_COMPARABLE`,
  `NOT_INTERCHANGEABLE`, or `INCONCLUSIVE`; none is a motor product disposition. Raw V1 remains the sole
  official measurand; a derived output requires its own measurement-contract version and cannot be called
  motor-only NL.

### Decision advanced

- The next executable step is Q0: freeze the exact S4 artifact/analyzer/config registry and approve
  `MSR_V1`. Then qualify the independent reference chain before collecting additional qualification DUT
  batches. Running more uncontrolled S4 batches now would add repetitions without resolving the missing
  physical-angle reference or motor×jig×mount identifiability.
- No hardware check was performed in this planning step.

## Independent audit of the vector-model report conclusion

- Classification: `OPEN_LOOP_MEASUREMENT`, review-only. No DATA, firmware, or analyzer changed.
- Re-verified the headline numbers in `analysis-out/nl-mount-vector-model-2026-08-20/nl_mount_vector_model_report.md`
  directly against the underlying CSVs rather than trusting the prose:
  - `config_interaction_summary.csv`: common/interaction fractions and LOO-vs-zero degradation
    (path1 `-51.0%`, path2_new `-25.4%`, path2_old `-23.6%`) match the report exactly.
  - `reference_frame_diagnostics.csv`: recomputing the mean of the 9 rows gives H36 delta
    `0.0049 deg` (command frame) and `0.5102 deg` (sensor-absolute frame), matching the report exactly.
  - Curve/pair/motor counts (13 curves, 9 pairs, 2/3/4 motors per config) reproduce from
    `export_vector_model_dataset.py`'s own file list.
- No fabricated or rounded-away numbers found. Two findings for the report author to tighten, not
  correctness errors:
  1. The weighted H1-H2/H1-H6 R^2 figures are aggregated over 9 non-independent pairs (shared baselines,
     confounded sensor+path in path2_new vs path2_old) with unequal weights; the report's own Limitations
     section says so, but the executive-summary bullet does not repeat the caveat inline.
  2. Section 4's phase-axis narrative ("identifies an error-field axis") is more confident than one of its
     own rows supports: H1 command-frame R drops to `0.110` for path2_old, i.e. genuinely inconsistent
     clustering for that harmonic/config, not just an uncalibrated-but-real axis.
- Verdict: report is well-supported and appropriately conservative (no DATA correction, no threshold
  implied); the two notes above should travel with the numbers if quoted outside this doc.

## `docs/open-loop-nl-jig-calibration-gage-rr-plan-2026-08-20.md` reviewed against RULE 0

- Classification: `OPEN_LOOP_MEASUREMENT`, review-only.
- Checked every RULE 0 clause in `AGENTS.md` against the plan text line by line (no-threshold, per-change
  impact statement, open-loop/no-feedback-actuation, no creep/PID/feedforward, invalidate-don't-rescue,
  diagnostic-profile isolation for feedback experiments, canonical-mean-only, measurand-formula immutability,
  contract-impact/versioning on any change, full-curve+extrema+harmonics validation, before/after
  classification, daily-log discipline) — all satisfied; the plan's own `theta_start` ban and LOO-as-hard-gate
  language directly encode this session's H36-falsification and LOO-transferability findings.
- Confirmed the plan does **not** change the official S4 algorithm: the raw formula/canonical-mean/LUT are
  explicitly frozen (`ZERO_TABLE vẫn là official S4 state`, `Không đổi firmware RESULT.OpenLoopNL_Deg`). The
  only new algorithm introduced is the offline, separately-versioned inverse calibration map (Q6.1), gated
  behind its own contract (`DerivedMeasurementContractVersion`) that never auto-replaces raw V1.
- Flagged two non-blocking items for the user: the "remount up to 17.47%" baseline figure has no traced
  source run in this conversation yet; and Q5 alone plans 168 batches, a multi-week/month program requiring
  hardware (independent reference encoder, gaussmeter/Hall probe, calibrated torque tool, >=2 development
  assemblies) not yet on hand — recommend treating Q0+Q1 as the near-term start, not the full roadmap at once.

## N-S transition / magnet field-strength hypothesis — reviewed, not confirmed

- User hypothesis: NL depends on the Tesla value of the item-8 magnet because field changes at the N-S
  pole transition. Assessed against MA600 operating principle and today's own vector-addition evidence:
  MA600 derives angle from field *direction* (arctan of two Hall axes), not magnitude, so absolute field
  strength should not drive a low-order angular error as long as the sensor stays in its valid range.
  Item 8 was the same physical magnet across every config compared today (baseline/path1/path2_old/
  path2_new); if the N-S-zone error were an intrinsic, config-invariant magnet property it would cancel in
  the config-minus-baseline differences, but the differences show real structure (H1/H2 dominant,
  R^2 0.81-0.90). Conclusion: current data favors "mounting/eccentricity sensitivity is amplified near the
  N-S transition" over "NL depends on magnet Tesla value." Not directly testable with current firmware
  (MA600 has no field-strength register); would need a gaussmeter/Hall-probe field map or a magnet swap at
  fixed mount, both already scoped into Q1.1 of the Gage R&R plan.

## P011 remount repeatability, path-1, 3 independent remounts (R1/R2/R3)

- Classification: `OPEN_LOOP_MEASUREMENT`, `QuickScreen3Run` (`DIAGNOSTIC_ONLY`, `PreconditionProtocol=
  ONE_FULL_SWEEP_120S_V1_FAST3`), same physical path-1 slot, full teardown/reassembly between each.
- Logs: `S4-P011-JIG7-openloop-v1-remountR1-path-1.txt`, `...remountR2-path-1.txt`, `...remountR3-path-1.txt`.
- A36 fingerprint 0.878-0.880 deg across all 3 confirms motor identity (matches known P011 band); no
  mislabeling.
- Remount-to-remount: all 3 pairs r0=0.996-0.999, best_shift=0, RMSE 0.058-0.084 deg; RawP2P 3.39-3.48 deg
  (cv=1.07%, n=3); idxMax/idxMin identical (354/97) in all 3; H36 cv=0.11% (rock solid); H1 cv=2.95%; H2
  cv=10.03% (least stable harmonic across remounts, consistent with the N-S-zone sensitivity note above).
- All 3 remounts vs the earlier path-1 baseline (`run011-2300mm-path-1`, captured 2026-08-19): r0=0.915-0.928,
  best_shift=40 deg needed every time, RMSE 0.60-0.66 deg — 8-10x larger than the remount-to-remount RMSE,
  and consistent across all 3 independent remounts, so this is a systematic difference, not remount noise.
- Verdict: today's path-1 mounting is highly repeatable within itself; `run011` is the outlier relative to
  it, not path-1 in general. Open item for next session: check what (if anything) changed in the path-1
  fixture between 2026-08-19 (`run011`) and today.
