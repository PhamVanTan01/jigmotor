# Phase 3B0-R - Controller-State Synchronization Checklist

Status: software implementation complete; host/build verification and hardware
A/B data are tracked below.

Updated: 2026-07-14

## Fixed experiment contract

Policy ID: `RESET_BEFORE_EACH_HOME_V1`

Each physical test must execute this exact order:

```text
force output driver disabled
  -> snapshot persistent controller/output state
  -> reset position-controller state, PID acquisition, and retained PWM command
  -> snapshot and validate the reset state
  -> enable the output driver
  -> closed-loop MoveToZero
  -> open-loop dither lock
  -> unchanged open-loop sweep and MA600A capture
```

This experiment isolates one factor only: persistent state versus reset state.
The PID gains, PID update equation, PWM waveform/commutation math, pole
configuration, home loop period, dither, ramp, sweep grid, settle contract,
MA600A acquisition, result math, and closure limit remain unchanged.

This phase is named `B0-R`. `B0-B` remains reserved for the separate
point-0/point-256 equivalent-approach experiment.

## Software checklist

- [x] `Motor_ResetPositionController()` clears the position controller and its
  PID feedback acquisition/unwrap context together.
- [x] A read-only snapshot exposes integral, previous error, accumulated
  command, feedback initialization, accepted-sample count, retained PWM
  phase/power command, and driver-enable state.
- [x] The retained PWM command is cleared to phase 0/power 0 while the driver
  is disabled, before enable; a later test cannot briefly replay the previous
  sweep endpoint.
- [x] Every physical test snapshots before reset, resets, snapshots after,
  validates zero state, then starts Home.
- [x] A failed reset-state validation stops the test before Home and motor
  sweep capture.
- [x] Home result, duration, update count, initial/final error, and
  initial/final command are captured.
- [x] `META` identifies the controller-state policy and reset validity.
- [x] `CONTROL_STATE` preserves detailed before/after/home diagnostics without
  overloading the existing long `META` record.
- [x] Boot self-test mutates and resets the real controller/acquisition state
  before motor enable, and fails closed on mismatch.
- [x] PID gains and update math are deliberately unchanged.
- [x] Motion, settle, encoder acquisition, and result math are deliberately
  unchanged.
- [x] Controller-state contract test passes.
- [x] All eight host regression tests pass.
- [x] Debug build passes with zero errors/warnings: text 112,124 B, data 96 B,
  BSS 132,776 B.
- [x] Release build passes with zero errors/warnings: text 69,948 B, data 96 B,
  BSS 132,760 B.
- [x] Release HEX SHA-256 is
  `2AA66363BD223BE4F9AD1FAD28D96268AEDBC6118E0DE6ACDE51433AD8F4D66E`.

## Required hardware A/B data

Use JIG1 and P03 first, without removing or remounting the motor. This keeps
the fixture/motor combination consistent with the existing test-7 baseline.
Flash one final Release HEX and keep it unchanged for the whole data set.

- [ ] Record firmware build timestamp and Release HEX SHA-256.
- [ ] Confirm every official run has
  `ControllerStatePolicy=RESET_BEFORE_EACH_HOME_V1`.
- [ ] Confirm every `CONTROL_STATE` has `ResetApplied=1` and
  `ResetStateValid=1`.
- [ ] Confirm every after-reset field is zero/uninitialized and
  `AfterOutputEnabled=0`.
- [ ] Run one precondition plus ten official runs with the existing 120-second
  cooldown; do not remount the motor and do not change supply or parameters.
- [ ] Record motor/PCB/ambient temperature when available. If unavailable,
  label thermal state `UNMEASURED`; do not call it thermally controlled.
- [ ] Preserve every run individually; do not average away run 1 or a failed
  closure.
- [ ] Repeat the complete batch once after at least 15 minutes motor-off to
  measure the cold/restart effect under the same reset policy.
- [ ] Only after the JIG1/P03 decision, repeat the selected protocol on JIG3
  as a reproducibility check.

## Decision rules

- State synchronization passes only when every attempted physical test reports
  a valid after-reset state and starts Home from `HomeInitialCommandRaw=0`.
- If Home duration/update count become more repeatable but closure does not,
  persistent PID state affected Home but is not the dominant closure cause.
- If the first official run remains different after deterministic reset,
  classify that difference as thermal/mechanical until temperature evidence
  proves otherwise; do not retune PID from this data alone.
- If Home itself remains unstable with identical reset state, the next
  controller experiment must separately address units, sample period,
  anti-windup, and convergence. It requires a new controller-policy ID.
- If Home stabilizes but closure remains biased, proceed to the already
  planned B0-B equal-approach experiment. The open-loop sweep/endpoint path,
  not this Home reset, is then the primary target.
- No result is qualified as MA600A datasheet INL without an independent
  precision reference encoder.
