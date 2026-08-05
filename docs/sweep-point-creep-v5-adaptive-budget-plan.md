# Sweep-point-creep v5 — adaptive targeted budget

Status: IMPLEMENTED — HARDWARE PILOT PENDING
Date: 2026-08-05
Scope: `ENABLE_SWEEP_POINT_CREEP` in `Core/Src/nonlinear_test.c`

## 1. Objective

Reduce the remaining `SweepPointCreepBudgetExceeded` events without raising
creep work at every point and without hard-coding a product/JIG-specific list
of angle indices.

The v4 spatial study on P08/JIG7 showed:

- pairwise Pearson correlation of mean `abs(MOTION.PositionErrorRaw)`:
  0.9790–0.9910 across three remounts;
- top-15% overlap: 80.0–89.5% Jaccard;
- top-54 cutoff: approximately 203–204 raw;
- about 56–60 points per complete official sweep had a live pre-creep gap
  greater than 200 raw, close to the observed 56–68 aggregate
  `BudgetExceeded` events.

This rejects independent random noise as the main explanation, but does not
justify an angle whitelist. The difficulty curve contains repeated harmonic
structure and point indices remain tied to sweep origin, motor, JIG, direction
and mounting.

## 2. Locked v5 control change

Use the live signed gap immediately before `CreepToUnwrappedTarget()`:

```text
initialGapRaw = expectedTargetUnwrapped - settledEncoderUnwrapped

if abs(initialGapRaw) > 200 raw:
    class = EXTENDED
    budget = 320 raw
    maxIterations = 21
else:
    class = BASE
    budget = 220 raw
    maxIterations = 15
```

Unchanged parameters:

| Parameter | Value |
|---|---:|
| Step | 16 raw |
| Deadband | 16 raw |
| Power | 1.0 |
| Base budget | 220 raw |
| Base max iterations | 15 |
| Ramp/settle algorithm | unchanged |
| Official NL formulas/schema | unchanged |

`21` extended iterations is deliberate. `CreepToUnwrappedTarget()` checks
iteration exhaustion before budget exhaustion. For a 320-raw budget and a
16-raw step, 20 issued steps reach exactly 320 raw; iteration limit 21 lets
the following loop evaluate the budget guard and report `BUDGET_EXCEEDED`
instead of misclassifying the same condition as `TIMEOUT`.

## 3. Explicit non-goals

- Do not hard-code the 54 P08/JIG7 point indices.
- Do not change step size, deadband, power, ramp, settle or motion profile.
- Do not add UART traffic inside the capture/motion loop.
- Do not change `MeasurementValid`, `Motor OK`, schema-v5 official RESULT or
  canonical metric formulas.
- Do not add point-0 creep in this phase; the existing main-loop call site
  still covers points 1 through the captured endpoint.

## 4. Telemetry contract

Protocol ID:

```text
ADAPTIVE_GAP_BUDGET_V1
```

### 4.1 Configuration record

Emit once per sweep, after capture has completed:

```text
SWEEP_CREEP_CONFIG,...,Official=0,Enabled=1,
Protocol=ADAPTIVE_GAP_BUDGET_V1,TriggerRaw=200,
BaseBudgetRaw=220,BaseMaxIterations=15,
ExtendedBudgetRaw=320,ExtendedMaxIterations=21,
StepRaw=16,DeadbandRaw=16,Power=1.000
```

### 4.2 Per-point diagnostic record

Store diagnostics in RAM during capture and emit only after capture. Emit a
record for every EXTENDED point and for any BASE point ending in timeout,
budget exceeded or acquisition error:

```text
SWEEP_CREEP_POINT,...,Official=0,Point=<index>,
InitialGapRaw=<signed>,InitialAbsGapRaw=<unsigned>,
BudgetClass=BASE|EXTENDED,SelectedBudgetRaw=<220|320>,
SelectedMaxIterations=<15|21>,Iterations=<n>,
TotalCorrectionRaw=<n>,FinalGapRaw=<signed>,Result=<state>
```

The existing `MOTION.PositionErrorRaw` retains its pre-creep meaning.

### 4.3 END aggregates

Keep all existing aggregate fields and append:

- `SweepPointCreepBaseBudgetExceeded`
- `SweepPointCreepExtendedPoints`
- `SweepPointCreepExtendedOk`
- `SweepPointCreepExtendedTotalIterations`
- `SweepPointCreepExtendedTotalCorrectionRaw`
- `SweepPointCreepExtendedTimeouts`
- `SweepPointCreepExtendedBudgetExceeded`

## 5. RAM and timing constraints

- Per-point creep diagnostics reside in existing CPU-only CCM storage.
- They are zeroed with the existing shadow storage before every capture.
- No DMA peripheral accesses these fields.
- No diagnostic log is emitted inside `CaptureSweep()`.
- Expected additional CCM usage is below 8 KiB for the current one-sweep
  configuration, inside the STM32F405 64 KiB CCM region.

## 6. Software verification

1. Contract test asserts all locked constants and protocol ID.
2. Contract test asserts the runtime selection uses live absolute gap, not a
   point-index table.
3. Contract test asserts 320 raw is paired with 21 iterations.
4. Contract test asserts diagnostic records are emitted after capture.
5. Contract test asserts official validity/schema/result source are unchanged.
6. Compile measurement mode; keep the existing dual-image isolation contract
   green for alternate app modes.
7. Build Release artifact and inspect linker memory use.

## 7. Hardware pilot

Build protocol: one precondition plus three official runs (`FAST3`).  Start on
P08/JIG7 under the same mounting and sensor configuration used for v4.

Primary gates:

| Gate | Target |
|---|---|
| Extended points reaching `OK` | >=90% |
| Overall BudgetExceeded | clearly below v4 range 56–68/run |
| Creep timeout | 0, unless independently explained |
| Total iterations | no more than 15% above comparable v4 |
| Acquisition/settle/tracking | valid and clean |
| RobustP2P/RMS_AC/H36/P99 | must not regress materially |
| Closure | remains valid/stable |

Stop the branch if extended correction increases heat/jerkiness materially or
improves endpoint counters while NL integrity degrades.

## 8. Build label

```text
sweep-point-creep-v5-adaptive-budget-fast3-20260805
```

After packaging, restore source defaults (`ENABLE_SWEEP_POINT_CREEP=0`,
10-official-run batch) while retaining the v5 implementation behind the flag.

## 9. Implementation checklist

- [x] Runtime budget selection from live post-settle encoder gap.
- [x] BASE behavior frozen at 220 raw / 15 iterations.
- [x] EXTENDED behavior added at 320 raw / 21 iterations.
- [x] No point-index or angle whitelist.
- [x] Per-point telemetry stored in CPU-only CCM RAM.
- [x] No V5 UART output inside `CaptureSweep()`.
- [x] Acquisition-error diagnostics retain the last observed encoder gap.
- [x] Diagnostic `SWEEP_CREEP_CONFIG` and `SWEEP_CREEP_POINT` records added.
- [x] Existing END totals preserved; BASE/EXTENDED aggregates appended.
- [x] Official validity, Motor OK, schema and canonical formulas unchanged.
- [x] Default source configuration: 29/29 PowerShell tests pass.
- [x] Feature-on FAST3 configuration: 28/29 pass; only the intentional
  10-run contract mismatch fails.
- [x] Release build succeeds; CCM use is 20,840 / 65,536 bytes (31.8%).
- [x] FAST3 artifact packaged under
  `builds/sweep-point-creep-v5-adaptive-budget-fast3-20260805/`.
- [x] Source defaults restored to creep OFF + 10 official runs.
- [ ] Run P08/JIG7 hardware pilot: one precondition + three official.
- [ ] Evaluate the gates in section 7 before promoting V5.
