# V5.3 — point-66 fine landing and stick-slip jump guard

Date: 2026-08-05

Status: implementation and FAST3 hardware pilot

## 1. Evidence and objective

V5.2 removed most ordinary target-crossing failures, but three P03/JIG7
mountings still showed a repeatable point-66 bistability. With nearly the same
initial gap (about -232 to -234 raw), point 66 either landed inside the
+/-16-raw deadband or snapped from about -40 raw to +276 raw. A subsequent
V5.2 recovery could then re-cross to about -141 raw. The giant 296-316-raw
observed movement is not a normal response to one 16-raw command.

V5.3 is a diagnostic, single-variable experiment. It tests whether a smaller
landing command avoids exciting that local breakaway event. It does not change
power, global budget, ramp, settle, sampling, or the other 359 analysis points.

## 2. Locked V5.3 motion contract

The V5.2 adaptive algorithm remains the default for every point except point
66:

- coarse step: 16 raw;
- deadband: +/-16 raw;
- base budget: 220 raw;
- extended trigger: abs(initial gap) > 200 raw;
- extended budget: 320 raw;
- power: 1.0;
- one bounded recovery after a normal target crossing.

Point 66 alone uses this landing profile:

1. Use the unchanged 16-raw coarse step while abs(live gap) > 64 raw.
2. Once abs(live gap) <= 64 raw, latch fine mode for the rest of that point.
3. Fine mode and any normal crossing recovery use a 4-raw step.
4. Keep the original selected raw budget (220 or 320). Increase only the
   iteration guard to 81 so the 4-raw step can consume the same 320-raw limit;
   this is not a larger motion budget.
5. Bound a normal fine recovery to 64 raw / 17 iterations and one reversal.
6. After every command, compare the fresh settled encoder position with the
   previous anchor. If a fine command produces abs(observed delta) > 96 raw,
   classify `STICK_SLIP_JUMP` and stop point-66 creep immediately. Do not issue
   a recovery command and do not chase the rotor through repeated reversals.
7. A `STICK_SLIP_JUMP` makes the sweep creep-integrity-invalid and suppresses
   `EligibleForStatistics`, even when acquisition itself remains clean.

Protocol IDs:

- `SweepPointCreepProtocol=ADAPTIVE_GAP_BUDGET_POINT66_FINE_LANDING_V1`
- `FineLandingProtocol=POINT66_FINE_STEP4_JUMP_GUARD_V1`
- `RecoveryProtocol=POINT66_FINE_SINGLE_REVERSAL_V1`

The B0-B approach creep continues through the unchanged compatibility wrapper
with fine landing disabled and recovery budget zero.

## 3. Telemetry contract

All UART output remains deferred until after `Motor_Disable()`.

`SWEEP_CREEP_CONFIG` schema 6 adds target point, entry window, fine step, jump
threshold, trace capacity, and fine-recovery limits.

The point-66 `SWEEP_CREEP_POINT` schema 6 record adds:

- `FineLandingAttempted`, `FineLandingSucceeded`;
- `FineIterations`, `FineCorrectionRaw`;
- `StickSlipJumpDetected`, `MaxObservedStepDeltaRaw`;
- `TraceCount`.

Each issued point-66 command is recorded after capture as
`SWEEP_CREEP_STEP` with command phase, signed command, gap before, observed
encoder delta, gap after, and jump classification. A fixed 100-entry CPU-only
buffer covers the worst-case 81 ordinary plus 17 recovery iterations.

`END` adds aggregate fine-landing and stick-slip counts. Integrity is valid
only when both recovery-failure count and stick-slip-jump count are zero.

## 4. Software gates

- default feature-off Release build passes;
- V5.2 feature-on mode still compiles with its original constants/IDs;
- V5.3 FAST3 feature-on Release build passes;
- B0-B call sites retain the original public wrapper and behavior;
- point 66 is the only caller that supplies a fine profile;
- jump detection is evaluated before crossing recovery;
- no UART call exists inside `CaptureSweep`;
- all contract tests pass;
- `graphify update .` passes;
- packaged source defaults are restored to creep off and 10 official runs.

## 5. Hardware pilot

Build label: `sweep-point-creep-v5-3-point66-fine-landing-fast3-20260805`

Use P03 on JIG7. Run one complete batch: one precondition plus three official
runs. Keep the mounting unchanged for the first batch. If the batch is clean,
repeat after one remount to test whether the improvement survives mounting.

Primary decision:

- PASS: 4/4 cycles have no `STICK_SLIP_JUMP`, no recovery failure, point 66
  ends inside +/-16 raw, and all 3 official runs are eligible;
- MECHANISM CONFIRMED BUT NOT SOLVED: a jump still occurs after a 4-raw command.
  Stop tuning step size; the local equilibrium/breakaway event needs a
  different control or mechanical intervention;
- MOTION IMPROVED, MEASURAND NOT STABLE: point 66 is valid but the full curve
  or NL signature remains unstable. Do not promote V5.3; motion validity and
  NL repeatability are separate gates;
- any transport/acquisition fault: rerun the same build before changing motion
  constants.

## 6. V5.3 stack fix after the first hardware run

Three independent captures completed a valid precondition and printed
`COOLDOWN_START`, but never reached official run 1 after the 120-second target.
The motion result was not the cause: point 66 ended at -13/-14 raw in two of
those captures with no jump or recovery failure.

The V5.3 Release `.su` files expose the failure mechanism. The deepest static
task call chain uses about 7656 bytes before interrupt/context margin, while
`TestTask` had only 8192 bytes. That leaves 536 bytes and the first context
switch after `COOLDOWN_START` is exactly where FreeRTOS
`configCHECK_FOR_STACK_OVERFLOW=2` can stop the system in `Error_Handler`.

Corrective action:

- increase `TestTask` from 8192 to 12288 bytes;
- retain more than 4.5 KiB margin above the static call-chain estimate;
- log `RUNTIME_CHECKPOINT` at cooldown start with the real stack high-water;
- log `COOLDOWN_PROGRESS` every 30 seconds so a live cooldown is distinguishable
  from a stopped task;
- do not alter any V5.3 motion constant or validity rule.
