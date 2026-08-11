# Sweep-point-creep V5.1 — target-crossing guard

Status: IMPLEMENTED — AWAITING HARDWARE PILOT
Date: 2026-08-05
Scope: `ENABLE_SWEEP_POINT_CREEP` in `Core/Src/nonlinear_test.c`

## 1. Evidence and decision

The first V5 hardware batch on JIG7 is not identified as P03 by firmware
(`MotorID=UNKNOWN`) and must be treated as an unknown product.  Compared with
the immediately preceding V4 batch from the same named remount session:

- V4 official `BudgetExceeded`: 49, 52, 52; V5: 48, 51, 52 — only 1.3%
  reduction in the mean;
- V5 EXTENDED success: 83/101 = 82.2%, below the locked 90% pilot gate;
- V4 `RobustP2P` SD was 0.0173 deg; V5 SD rose to 0.4877 deg;
- V5 official Raw P2P progressed 0.5701 -> 1.9145 -> 3.8162 deg;
- target crossing outside deadband was observed at zero, one and three
  budget-exhausted points in official runs 1, 2 and 3 respectively.

Examples tied directly to the NL extremes:

```text
Run 2 point 195: initial gap +54  -> final gap -327 raw; DATA error -1.8105 deg
Run 3 point 66 : initial gap -233 -> final gap +315 raw; DATA error +1.7191 deg
Run 3 point 284: initial gap +213 -> final gap -376 raw; DATA error -2.0971 deg
```

`CreepToUnwrappedTarget()` freezes direction from the initial gap.  Once a
stick-slip/breakaway event moves the rotor past the target, the next creep
command still uses the original direction and can drive the rotor farther
away.  Increasing budget again is therefore rejected.

## 2. Locked V5.1 motion change

After every creep micro-step and settle:

1. update the live signed gap;
2. if `abs(gap) <= deadband`, return `OK` exactly as before;
3. if the new gap sign is opposite the initial creep direction and remains
   outside deadband, stop immediately with `TARGET_CROSSED`;
4. issue no reverse command and no additional command after the crossing.

The guard is a caller-selectable parameter:

- main-sweep V5.1 call: guard enabled;
- the two B0-B approach-creep calls: guard disabled, preserving their
  existing behavior and protocol.

Unchanged V5 parameters:

| Parameter | Value |
|---|---:|
| EXTENDED trigger | `abs(initialGapRaw) > 200` |
| BASE budget / iterations | 220 raw / 15 |
| EXTENDED budget / iterations | 320 raw / 21 |
| Step / deadband / power | 16 raw / 16 raw / 1.0 |
| Ramp, settle and canonical NL formulas | unchanged |

## 3. Validity and batch policy

`TARGET_CROSSED` means the point did not reach a validated equilibrium.  A
numeric NL produced by that sweep must not become an official motor result.

For the diagnostic FAST3 build:

- capture continues after the guarded stop so the remaining curve and later
  crossings can be observed;
- the sweep receives `SweepPointCreepIntegrityValid=0`;
- `END.Status=INVALID`;
- `EligibleForStatistics=0` and the legacy result lines are suppressed;
- `Motor OK` is suppressed for that physical cycle;
- the batch is nevertheless allowed to continue through one precondition and
  three official attempts, so the diagnostic does not stop at the first
  precondition crossing;
- if the precondition crosses, subsequent META records carry
  `PreconditionValid=0` and remain ineligible.

This continuation is diagnostic-only.  `BATCH Status=COMPLETE` means the
requested sequence was collected; it does not override per-sweep INVALID.
Transport, settle and tracking failures retain their existing hard-stop path.

## 4. Telemetry additions

Protocol ID:

```text
ADAPTIVE_GAP_BUDGET_CROSS_GUARD_V1
```

`SWEEP_CREEP_CONFIG` adds:

- `TargetCrossingGuard=STOP_BEFORE_NEXT_COMMAND_V1`

`SWEEP_CREEP_POINT` uses `Result=TARGET_CROSSED` and already contains the
signed initial/final gaps, class, budget, iterations and correction.

`END` adds:

- `SweepPointCreepTargetCrossed`
- `SweepPointCreepBaseTargetCrossed`
- `SweepPointCreepExtendedTargetCrossed`
- `SweepPointCreepIntegrityValid`

## 5. Software gates

- Guard is evaluated only after a fresh settled encoder sample.
- Deadband success has priority over crossing classification.
- No motor command exists between crossing detection and function return.
- B0-B call sites pass guard disabled.
- Main-sweep call passes guard enabled.
- Point/result telemetry remains post-capture; no UART in `CaptureSweep()`.
- Default-off build and FAST3 feature-on build both compile.
- Default test suite remains green; FAST3 retains only the intentional
  10-run-contract mismatch.

## 6. Hardware pilot and decision

Build label:

```text
sweep-point-creep-v5-1-crossing-guard-fast3-20260805
```

Run one precondition plus three official attempts on the same JIG7/motor and
mounting as the V5 batch.

Interpretation:

- `TargetCrossed=0` on all three official runs and stable NL: proceed to
  repeat confirmation;
- crossing remains but large NL spikes disappear: guard mechanism confirmed;
  design V5.2 controlled recovery separately;
- crossing remains and NL spikes remain at the guarded final gap: do not use
  those sweeps; V5.2 needs a bounded recovery/re-settle operation;
- no crossing but NL remains unstable: target crossing was not the only
  mechanism; stop creep tuning and investigate the remaining motion path.

No V5.1 sweep with `SweepPointCreepIntegrityValid=0` may be used for product
classification or V4/V5 performance averages.

After packaging, restore source defaults to sweep creep OFF and the
10-official-run batch.

## 7. Implementation checklist

- [x] Add `NL_CREEP_TARGET_CROSSED` and caller-selectable guard.
- [x] Keep B0-B creep unchanged by passing guard disabled at both call sites.
- [x] Enable guard only for main-sweep adaptive creep.
- [x] Stop after the fresh post-step settle sample, with deadband priority and
  no reverse/next command after crossing.
- [x] Add total, BASE, EXTENDED and integrity telemetry to `END`.
- [x] Keep crossing separate from acquisition `MeasurementValid` so FAST3 can
  collect all four cycles.
- [x] Suppress eligibility, legacy result and `Motor OK` for invalid creep
  integrity; propagate a crossed precondition to later official attempts.
- [x] Extend the creep contract test for the motion and validity invariants.
- [x] Default Release build and 31/31 default tests pass.
- [x] FAST3 Release build passes; 30/31 tests pass, with only the intentional
  ten-run-contract mismatch.
- [x] Package checked artifact at
  `builds/sweep-point-creep-v5-1-crossing-guard-fast3-20260805/`.
- [x] Restore source defaults: sweep creep OFF, ten official runs.
- [ ] Run the locked JIG7 hardware pilot and evaluate the decision branches in
  section 6.
