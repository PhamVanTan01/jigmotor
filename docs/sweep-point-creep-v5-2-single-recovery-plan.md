# V5.2 — adaptive targeted budget with bounded single recovery

Date: 2026-08-05

## 1. Why V5.2 exists

V5.1 correctly stopped issuing commands after the first target crossing, but
the P03/JIG7 pilot still produced 12 crossings in four sweeps. Ten crossings
stopped close to the target; two point-66 events snapped from about -230 raw to
+280 raw and made the entire sweep invalid. The failure is a local stick-slip
event, not global encoder noise: A36 remained stable while the point-66 error
was bimodal.

V5.2 does not increase the normal budget and does not use an angle whitelist.
It adds one bounded recovery only when a crossing is physically observed.

## 2. Locked motion algorithm

The ordinary V5 adaptive selection remains unchanged:

- step: 16 raw;
- deadband: +/-16 raw;
- base budget: 220 raw / 15 iterations;
- extended trigger: abs(initial gap) > 200 raw;
- extended budget: 320 raw / 21 iterations;
- power: 1.0;
- target crossing is evaluated from a fresh settled MA600 sample.

Recovery contract:

1. A landing inside the deadband is always success, even if its sign changed.
2. A crossing outside the deadband records the pre-cross and post-cross gaps.
3. The direction is reversed exactly once.
4. Recovery uses the same 16-raw step and 1.0 power, with an independent
   maximum of 320 raw / 21 iterations.
5. A second crossing outside the deadband stops before the next motor command
   with `RECOVERY_RECROSSED`; a second reversal is forbidden.
6. Recovery timeout, budget exhaustion, re-crossing, or acquisition failure is
   an integrity failure. A recovered point is valid only when a fresh settled
   sample is inside the +/-16-raw deadband.
7. The B0-B approach call sites pass zero recovery budget and remain frozen.

Protocol IDs:

- `SweepPointCreepProtocol=ADAPTIVE_GAP_BUDGET_SINGLE_RECOVERY_V1`
- `TargetCrossingGuard=STOP_BEFORE_NEXT_COMMAND_V1`
- `RecoveryProtocol=SINGLE_REVERSAL_SAME_STEP_V1`

## 3. Required telemetry

Per crossing/recovery point, `SWEEP_CREEP_POINT` records:

- `PreCrossGapRaw`, `CrossingGapRaw`;
- `RecoveryAttempted`, `RecoverySucceeded`;
- `RecoveryIterations`, `RecoveryCorrectionRaw`;
- final `Result` and `FinalGapRaw`.

`END` records total crossing, attempted, recovered, failed and re-crossed
counts, plus recovery iteration/correction totals. Successful recovered
crossings are not integrity failures; failed recovery is.

The final `BATCH` record must report the actual precondition state, never a
hard-coded `PreconditionValid=1`.

## 4. Software gates

- both creep-disabled and creep-enabled firmware modes compile;
- B0-B call sites have recovery disabled and retain their previous behavior;
- no second recovery reversal is possible in code;
- deadband success has priority over crossing classification;
- transport/acquisition errors remain hard errors;
- all existing PowerShell contract tests pass;
- the analyzer accepts an explicitly marked diagnostic-invalid precondition or
  official cycle without promoting it to official statistics;
- `graphify update .` succeeds.

## 5. Hardware pilot (FAST3)

Build label:
`sweep-point-creep-v5-2-single-recovery-fast3-20260805`

Use the same JIG7, motor and mounting as the V5.1 pilot. Run one precondition
and three official cycles. Do not remount between V5.1 and V5.2 if avoidable.

Required PASS gates:

- acquisition clean in all four cycles;
- `RecoveryFailed=0` and `RecoveryRecrossed=0` in all four cycles;
- every recovered point ends inside +/-16 raw;
- precondition valid and all 3/3 official cycles eligible/valid;
- no recurrence of the point-66 +280-raw endpoint mode;
- no regression in total ordinary creep work relative to V5.1. Recovery work
  is reported separately and must occur only at observed crossings.

Decision after the pilot:

- PASS: compare full 360-point NL/RobustP2P/A36 against V4, V5 and V5.1;
- recovery succeeds but curve remains unstable: recovery fixed motion validity,
  not the measurand; stop tuning motion and investigate the local fixture event;
- any recovery failure/re-cross: V5.2 remains diagnostic-only and is not used
  for product acceptance; do not add a second reversal or globally increase
  the 360-point budget.

## 6. Packaging rule

Package the FAST3 `.hex/.elf/.map`, build metadata and checksums in the build
directory above, then restore source defaults to production screening mode
(`ENABLE_SWEEP_POINT_CREEP=0`, normal batch settings).
