# Phase 3A - Continuous Motion, Settle, and Motor Pole Checklist

Updated: 2026-07-14

Overall status: **software implementation passes and selected hardware logs
confirm clean acquisition/motion observability, but endpoint equivalence and
the complete hardware matrix do not pass**. Official output remains schema 5
legacy. Canonical remains a non-official shadow diagnostic. Phase 3B0 in
`phase3b0-closure-measurement-review.md` is the blocking measurement-validity
review before any 10-run qualification.

## Configuration decision

- `MOTOR_NUM_POLSE` is the physical motor pole count. The spelling is kept for
  compatibility with the existing PIXY configuration.
- Current default: `MOTOR_NUM_POLSE=12`.
- Derived pole pairs: `12 / 2 = 6`.
- Electrical ripple diagnostic order: `6 * pole-pairs = 36` per mechanical
  revolution.
- Pole count is not the same as Motor ID. Pole count changes commutation and
  must be correct before a test. Per the operator decision, Motor ID is not a
  software validity gate in Phase 3A and may be filled in after each test.

## Software checklist

- [x] One shared motor-geometry header is used by PWM commutation and nonlinear
  diagnostics.
- [x] `MOTOR_NUM_POLSE=12` derives `MOTOR_POLE_PAIRS=6`.
- [x] Build rejects a pole count below 2, above 128, or an odd pole count.
- [x] The existing 12-pole PWM mapping remains numerically unchanged.
- [x] Log records expose `MotorPoleCount`, `MotorPolePairs`, and
  `ElectricalRippleOrder`.
- [x] Fixed historical A36 remains available.
- [x] Dynamic `AElectrical6` is evaluated at order `6 * pole-pairs`; for the
  current motor this is also order 36.
- [x] `CaptureSweep()` creates exactly one checked MA600 acquisition context.
- [x] The same unwrap context advances through initial reference, ramp,
  settle, and official point capture.
- [x] Every 8-count ramp command is followed by an encoder feedback read.
- [x] A normal 265-point sweep has 264 ramps x 32 reads = 8,448 accepted ramp
  samples when no retry/fault occurs.
- [x] Settle requires stability and target proximity in the same eight-sample
  consecutive window.
- [x] Stable but out-of-target behavior is classified as `WRONG_POSITION`.
- [x] Point 0 requires stability and then defines the sweep origin; its target
  error is exactly zero by definition.
- [x] Canonical point anchor is frozen from the final post-settle sample.
- [x] The unused ramp after the final >370-degree point was removed.
- [x] Legacy `Acq*` counters retain their frozen point-capture meaning; ramp,
  settle, and total-context counters are reported separately.
- [x] Per-point `MOTION` and aggregate `MOTION_RESULT` records are emitted only
  after the motor is disabled.
- [x] Analyzer validates the Phase-3A identity/contract and exports pole,
  ramp, settle, and continuous-context fields.
- [x] Schema remains 5 and `OfficialResultSource=LEGACY`.
- [x] Motor ID is not included in `measurementValid`.
- [x] `test_phase3a_motion_contract.ps1` passes, including deterministic
  OK/WRONG_POSITION/TIMEOUT settle cases and parser fixture coverage.
- [x] Current Phase-3B0-A Release build passes with 0 errors and 0 warnings:
  text 66,796 B, data 96 B, BSS 132,656 B including CCM.
- [x] Release `jigmotor.hex` SHA-256:
  `D2B4A66FFA4266BB3E9226FD0EF3347A0FBE1D9FD8AC4BF086A4AE68426F1586`.
- [x] Current Phase-3B0-A Debug build passes with 0 errors and 0 warnings:
  text 107,620 B, data 96 B, BSS 132,672 B including CCM.
- [x] Phase-3A/Phase-2B point workspace is 10,504 B in CCM `NOLOAD`; main SRAM
  has 8,824 B linker margin after the reserved heap/stack.
- [x] Debug static worst visible B0-A logging chain is 4,448 B, including
  `PrintSweepLog` 2,000 B, `PrintClosureProbeLog` 368 B, and `LogLineLarge`
  1,920 B; this remains inside the 6,656-B test-task stack. Runtime high-water
  remains a hardware gate.

## Hardware gate for each new sweep

- [ ] Use the same HEX on all compared jigs. Record its checksum.
- [ ] META reports `MotorPoleCount=12`, `MotorPolePairs=6`,
  `ElectricalRippleOrder=36` for the current PIXY motor.
- [ ] META reports `ContinuousSweepContext=SWEEP_CONTEXT_V1`,
  `ContextReacquireCount=0`, and `RampFeedbackEnabled=1`.
- [ ] META reports `SettleContract=STABILITY_AND_TARGET_V1`, stability limit
  9 raw counts, and target tolerance 910 raw counts (pilot motion-integrity
  envelope, not a product-quality limit).
- [ ] Legacy `AcqReadAttempts=17226`, with zero retries, transport errors,
  jump rejects, and failed samples on a healthy sweep.
- [ ] `MOTION_RESULT` reports `RampAcceptedSamples=8448` and no ramp faults.
- [ ] `SettlePoints=265`, `StabilityValidPoints=265`,
  `TargetProximityValidPoints=265`, and `SettleValidPoints=265`.
- [ ] `SettleTimeoutPoints=0` and `SettleWrongPositionPoints=0`.
- [ ] Point 0 has `RampAcceptedSamples=0`; points 1..264 each have 32 on a
  fault-free sweep.
- [ ] Context arithmetic is consistent:
  `ContextReadAttempts = AcqReadAttempts + RampReadAttempts + SettleReadAttempts`.
- [ ] `MeasurementValid=1`, `TrackingValid=1`, `AcquisitionResult=OK`, and END
  status is `VALID`.
- [ ] `MOTION`, `RESULT`, `SHADOW_*`, and END records are complete and not UART
  truncated.
- [ ] Runtime stack high-water remains at least 256 words.
- [ ] Motor disables normally; no reset, HardFault, or stack overflow occurs.

Passing every item above proves structural acquisition and local motion health;
it does not prove full-turn endpoint equivalence. In particular,
`SettleValid=1` currently accepts a locally stable shaft inside the wide
910-raw-count target envelope. Closure remains a separate gate at point 256.

## Hardware evidence and corrected gate status

The following Phase-3A data has now been reviewed:

| Cell | Structural-valid sweeps | Closure pass at 0.20 deg | Status |
| --- | ---: | ---: | --- |
| P03/JIG1 | 3/3 | 0/3 | endpoint gate FAIL |
| P05/JIG3 batch 1 | 3/3 | 2/3 | endpoint gate FAIL |
| P05/JIG3 batch 2 | 3/3 | 1/3 | endpoint gate FAIL |

Across all nine sweeps, point-256 position error and canonical closure have a
correlation of `0.99633`; their mean absolute difference is `0.01738 degree`.
Transport/acquisition counters are clean. This localizes the open issue to the
return-to-reference motion/protocol state rather than SPI/unwrap or Q16 closure
math.

The settle implementation also remains narrower than the future schema-v6
metric contract: it checks consecutive pairwise deltas but does not yet record
whole-window P2P or first-to-last drift. That gap is intentional pending
stationary-noise/hold evidence in Phase 3B0; it must not be marked passed by
software tests alone.

## Comparison matrix

Run at least three sweeps per motor/jig cell. Do not combine motors with
different physical pole counts in the same summary.

| Motor | JIG1 | JIG2 | JIG3 |
| --- | --- | --- | --- |
| P03 | [x] motion 3/3; closure 0/3 | [ ] 0/3 | [ ] 0/3 |
| P05 | [ ] 0/3 | [ ] 0/3 | [x] motion 6/6; closure 3/6 |

JIG2 UID is `0025002C3234470438353535`. The firmware/parser mapping must report
`JIG2`; do not infer it from the filename.

## Host verification

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase1_baseline_integrity.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_canonical_sampler_contract.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase2b_shadow_contract.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase3a_motion_contract.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_phase3b0_closure_probe_contract.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test_analyze_nonlinear_logs.ps1
```
