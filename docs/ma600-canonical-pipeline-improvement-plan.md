# MA600A Canonical Acquisition Improvement Plan

## Objective

Evolve the current schema-v5 nonlinear test into a canonical, failure-aware
MA600A acquisition pipeline without losing the working two-jig baseline.

The measurement policy remains `WHOLE_SYSTEM_REPORT_ONLY_V1`. The jig has no
independent precision reference encoder, so this work improves acquisition
validity and repeatability; it does not introduce a product-quality or
sensor-only INL threshold.

The canonical implementation will use **schema v6**. Schema v5 is already in
use by hardware logs and must not be redefined.

## Baseline and non-goals

Read-only hardware baselines:

- JIG1 UID `003C00273234470438353535`: three valid P03 sweeps, nonlinear
  results 3.52/3.07/3.00 deg.
- JIG2 UID `0025002C3234470438353535`: three valid P03 sweeps, nonlinear
  results 2.51/2.47/2.46 deg.
- Both jigs: `ZERO_TABLE`, `CorrNonZeroCount=0`, CRC `0x190A55AD`, no SPI
  retry/error/jump reject, and approximately 91 KB free heap.

Do not enable SPI DMA, write MA600A NVM/LUT, introduce a nonlinear pass/fail
threshold, or run the full Phase-B matrix until the preceding gates pass.

## Phase 0 — Freeze baseline and schema contract

### Work

1. Preserve schema-v4 and schema-v5 logs as immutable fixtures.
2. Define the schema-v6 META/DATA/ACQ/RESULT/END contract before changing
   capture math.
3. Add an offline regression check that extracts jig identity from META/UID,
   not the filename.
4. Record current Debug/Release size, stack usage, free heap, motor-active
   duration, point count, and legacy numerical results.
5. Define explicit tolerances for calculations that should remain unchanged.
6. Freeze `CANONICAL_Q16_V1` in
   `docs/nonlinear-metric-contract-v1.md`, including exact signed rounding,
   index sets, closure, P99, DFT sign/normalization, fitted grid, and the rule
   that signed negative values are multiplied by `65536LL`, never shifted.

### Gate

- Historical v4/v5 logs parse without modification.
- Swapped or misleading filenames cannot override META JigID/UID.
- A schema-v6 fixture can coexist with v4/v5 without field ambiguity.
- Every schema-v6 metric can be independently reproduced from its documented
  inputs without relying on compiler-specific rounding or signed shifts.

## Phase 1 — Checked I/O and Policy-A configuration gate

### Work

1. Extend accepted-sample updates to store `meta.csAssertCycle`, rather than a
   later `DWT->CYCCNT` value.
2. Capture CS-cycle and PWM-counter metadata before each HAL SPI transaction,
   set `meta.metaValid`, and preserve that metadata even when the transaction
   times out or otherwise fails.
3. Read and log the complete read-only configuration snapshot, including
   RMAPID and decoded ZERO/DIR/FILT/PRT/STATUS fields.
4. First run an audit build on both jigs to establish the expected values.
5. Add a UID-aware expected-configuration table only after both hardware
   audits establish the exact register values.
6. Before `Motor_Enable()`, reject the batch on:
   - configuration read failure;
   - non-zero correction table;
   - NVMB/error flags after the existing clear/re-read policy;
   - unexpected protected/filter/direction/zero/map values, but only after
     those values have been locked by the two-jig audit policy.
7. Log `ExpectedCalibrationState=ZERO_TABLE`, `ConfigValid`, and a specific
   rejection reason.

Audited locked profile (both known UIDs, observed 2026-07-13):
`ZERO=0x0000`, `DIR=0x00`, `FILT=0x05`, `STATUS=0x00`, `PRT=0x00`,
`RMAPID=0x00`, zero correction table, CRC32 `0x190A55AD`. The locked build
uses `POLICY_A_LOCKED_V1`; an unknown UID has no expected profile and cannot
energize the motor.

### Tests

- Unit/static tests for config decode and CRC.
- Test-build fault injection for register/raw transaction failures.
- Hardware audit on both UIDs before enabling hard gates.

### Gate

- Bad/unknown configuration cannot energize the motor.
- Both known jigs pass the same documented Policy-A rules.
- Debug and Release builds remain warning-free.

## Phase 2 — Canonical point sampler

### Work

1. Introduce `MA600_PointSample_t` with int64 Q16 means, accepted/attempted
   counts, SPI/jump/timing counters, and sample-quality data.
2. Implement `MA600_ReadAveragedPoint()` with caller-supplied
   `pointAnchorUnwrapped`, captured immediately after settle.
3. Implement every mean/error/closure calculation exactly as specified by
   `CANONICAL_Q16_V1`: int64 Q16, nearest-half-away-from-zero, multiplication
   by `65536LL`, and no signed negative left shift.
4. Enforce the scheduler transaction-slot contract:
   - initialize from the first transaction attempt's valid CS metadata,
     whether that attempt succeeds or fails;
   - a failed attempt consumes its slot and is never retried immediately;
   - after a missed slot, advance until `nextSampleCycle` is in the future,
     count every skipped slot, and never issue a catch-up burst.
5. Support explicit `BACK_TO_BACK` and start-to-start scheduled modes.
6. Bound every acquisition by accepted samples, total transactions,
   consecutive failures, and elapsed time.
7. Set the initial official candidate to `CanonicalMeanSource=ALL_TIER1` and
   `MadFilteringEnabled=0`. The acquisition loop stores only integer sums,
   extrema, counters, and optional engineering scratch data. Robust/MAD
   results are offline or post-capture engineering diagnostics and cannot
   become the Phase-2 official mean.
8. Precompute interval/jump/time constants and keep the timing-sensitive loop
   integer/fixed-point only. Use one static sweep workspace; do not allocate a
   large task-stack array or per-sweep heap memory.
9. Remove the extra point read whose raw/timestamp currently does not
   represent the 64-sample mean used by nonlinear math.

### Phase 2A: deterministic host tests

- CW and CCW wrap crossing.
- DWT counter wrap.
- Immediate sample 0.
- First transaction failure.
- Missed slots and skipped-slot accounting.
- Accumulator/Q16 rounding limits.
- MAD candidate/rejected accounting.
- Point-0 canonical mean gives `Error_0=0`.
- 360-degree closure uses the exact `65536LL * 65536LL` target.
- Failed attempt metadata remains valid and initializes the schedule.
- A failed attempt consumes one slot; missed slots never produce a catch-up
  burst.

### Phase 2B: hardware shadow mode

- Capture legacy and canonical values from the same settled point/sweep.
- Keep `OfficialResultSource=LEGACY` and log canonical values under explicit
  `ShadowCanonical*` names only.
- Log at least canonical RMS/A36/P2P/closure and legacy-minus-canonical
  RMS/A36 deltas.
- Do not emit schema-v6 official results until Phase 2A and 2B gates pass.

### Gate

- All deterministic sampler tests pass.
- The new sampler remains non-official during Phase 2B; shadow results cannot
  affect legacy output or pass/fail behavior.
- Memory/stack growth is measured before integration.

Implementation checkpoint (2026-07-13): Phase 2A passed source/host tests and
locked-profile boot evidence on JIG1/JIG3. Phase-2B shadow code is integrated
while schema 5 legacy remains official. It emits separate canonical
META/DATA/ACQ/RESULT/END records, uses separate counters/context, and is parsed
by the host analyzer. Debug and Release build warning-free. The Phase-2B
hardware matrix and runtime stack/closure evidence remain open in
`docs/phase2b-shadow-checklist.md`; schema 6 canonical output is still not
official.

## Phase 3 — Continuous sweep context and motion health

### Work

1. Create one `sweepCtx` after lock/start acquisition and use it through
   ramp, settle, and point sampling. PID homing keeps its own earlier context.
2. Make ramp read feedback at every micro-step.
3. Compute moving-mode max jump from elapsed cycles since the last accepted
   sample plus a documented speed margin.
4. Make settle use the same context and switch to the static threshold.
5. Require both settle-window stability and target proximity in the same
   unwrapped coordinate frame. A stable but off-target point is
   `SETTLED_WRONG_POSITION` and is invalid.
6. Make unwrap acceptance atomic: only an accepted sample may update
   `lastRaw`, `unwrappedRaw`, `lastAcceptedCycle`, and `acceptedCount` using
   that transaction's CS timestamp. A reject changes reject counters only.
7. Add bounded ramp health counters for transport failures and jump rejects.
8. Production policy initially aborts and disables the motor after the pilot
   consecutive-failure threshold.
9. Keep controlled cluster reacquisition behind an engineering build flag.
   Any reacquired sweep is diagnostic-only and never official-valid.
10. Make PID integration/derivative explicitly dt-aware with clamps while
   preserving existing tuning behavior at the nominal 2 ms update interval.

### Tests

- Inject transport failures during PID, ramp, settle, and point acquisition.
- Inject isolated and consecutive jump rejects.
- Verify unwrap state never advances on rejected input.
- Verify `SETTLED_WRONG_POSITION` when stability passes but target proximity
  fails.
- Verify motor-disable latency is bounded after the failure budget is reached.
- Engineering reacquisition accepts only a consistent three-sample cluster
  within the physically possible displacement envelope.

### Gate

- No ramp continues blind beyond the documented bound.
- Every recovery/abort decision is represented in counters and logs.
- Healthy two-jig smoke results remain within the Phase-0 comparison policy.

Phase 3A closes the acquisition-observability portion of this gate only. It
does not prove that the full-turn endpoint returns to the same mechanical
state as point 0. Hardware evidence collected on 2026-07-14 showed closure
tracking point-256 position error with correlation `0.99633` across nine
sweeps. The resulting endpoint/protocol issue is isolated as Phase 3B0 below.

## Phase 3B0 — Closure and measurement-validity qualification

Current status (2026-07-14): B0-A passive hold firmware, log/analyzer
contract, deterministic tests, and Debug/Release builds are complete. Hardware
three-run evidence is pending. Equivalent approach, active trim, final policy
selection, and 10-run qualification remain blocked behind that evidence.

### Objective

Validate the complete measurement state before enabling the 10-run
repeatability study. Point 0 and point 256 must represent equivalent command,
approach, settle, thermal, and mechanical states separated by exactly one
mechanical revolution.

### Work

1. Freeze the measurand as whole-system open-loop command tracking; do not
   describe the current result as MA600A sensor-only INL.
2. Select one explicit closure policy before official validity work:
   `PERIODIC_MAP_V1`, where equivalent periodic states make closure an
   integrity gate, or `FIRST_PASS_TRAJECTORY_V1`, where closure is a physical
   response metric and not automatically an invalidation rule. The periodic
   policy is recommended for one-jig repeatability.
3. Preserve the current point-256 closure as an unmodified baseline.
4. Add a diagnostic-only passive hold probe at point 256 to record closure at
   approximately 50, 100, and 200 ms without changing command or power.
5. Record whole-window settle P2P and first-to-last drift. The existing
   pairwise-delta rule can accept slow monotonic drift and is not sufficient
   to select the final settle contract.
6. Run a separately versioned A/B experiment that gives point 0 and point 256
   equivalent approach direction/history. If a local same-direction approach
   is insufficient, test a separate full pre-roll/fly-in protocol and account
   for its added heat.
7. Allow a post-baseline closed-loop trim only as a later diagnostic. Because
   the MA600A would be both feedback device and measured device, that trim
   cannot establish sensor trueness or datasheet INL.
8. Select either a cold-start or preconditioned thermal protocol and log its
   observable state. The current 120-second cooldown is not yet validated as
   equal temperature.
9. Audit run-boundary controller state. Phase 3B0-R now applies the isolated
   `RESET_BEFORE_EACH_HOME_V1` policy and logs before/after reset plus Home
   convergence state. Hardware A/B evidence is still required before this
   policy can be selected; see `controller-state-synchronization-checklist.md`.
10. Keep PID tuning, PWM/ramp changes, capture math, schema promotion, closure
   limit changes, and experiment-factor changes in separate reviewable change
   sets.

Detailed evidence, factor audit, experiment order, required diagnostic fields,
and decision rules are frozen in
`docs/phase3b0-closure-measurement-review.md`.

### Gate

- Passive hold data separates dynamic drift from a static endpoint error.
- Closure is explicitly defined as either a periodic integrity gate or a
  first-pass response metric; the two policies never share one validity field.
- Point-0/point-256 approach equivalence is explicitly defined.
- Settle-window metrics and numeric limits are selected from measured
  stationary behavior, not guessed.
- Three no-remount pilot runs pass structural checks and the unchanged pilot
  closure limit 3/3 without result averaging.
- No diagnostic result changes legacy/schema-v5 output semantics.
- Only after this gate passes may the 10-run repeatability mode be enabled.

## Phase 4 — Capture/analyze boundary and quality contract

### Work

1. Split `CaptureRawSweep()` from `AnalyzeCapturedSweep()`.
2. Disable the motor immediately after capture, before harmonic fitting,
   sorting, formatting, or UART output.
3. Define `NL_QUALITY_VALID`, `NL_QUALITY_DEGRADED`, and
   `NL_QUALITY_INVALID` with explicit conditions.
4. Define `OfficialMeasurementValid` independently from model validity.
5. Include acquisition completeness, settling, tracking integrity, config
   validity, closure integrity, zero reacquisitions, and zero motor faults in
   official validity. Compute a bitwise `OfficialInvalidReasonMask` so
   simultaneous failures remain visible.
6. For invalid sweeps, emit only `Diagnostic_*` numerical fields; never emit
   official RMS/harmonic/INL names or legacy numeric result lines.
7. Preserve the existing gross tracking guard as a motion-integrity check,
   not a product threshold.
8. Apply the pilot closure-integrity limit of 0.20 degrees as defined by
   `CANONICAL_Q16_V1`; it is not a product-quality threshold.
9. Analyze points 0..255 only for MeanDC/RMS/P2P/DFT/fit. Treat point 256 as
   closure and 257..264 as post-turn diagnostics.
10. Use direct selected-order DFT for orders
    `1|2|3|6|9|12|18|27|36|45|72|108`, with the frozen `2/N` normalization
    and phase convention. An optional 256-entry sin/cos LUT may run only
    after capture and must pass synthetic metric tests; do not add an FFT.

### Gate

- Invalid capture cannot print `Motor OK` or official measurement fields.
- Analysis duration is excluded from motor-active duration.
- Safe-stop is verified on every error exit.

## Phase 5 — Schema v6, analyzer, and timing observability

### Work

1. Emit schema-v6 fields including:
   - `ReferenceDefinition=POINT0_CANONICAL_MEAN`;
   - `MathContractVersion=CANONICAL_Q16_V1` and
     `SignedRoundingMode=NEAREST_AWAY_FROM_ZERO`;
   - `MeanDCComparableToLegacy=0`;
   - point-0 and closure raw/degree/limit/valid fields;
   - settle stability, target-proximity, and combined validity;
   - `OfficialInvalidReasonMask` and motor-fault count;
   - quality and official-valid fields;
   - context reacquire count;
   - expected/actual configuration state;
   - sampler mode/interval, metadata-valid, schedule initialization,
     failure/slot/timing counters, and explicit disabled MAD state.
2. Update the analyzer to parse META/RESULT/END, honor validity, and use
   MCU UID/JigID before filename metadata.
3. Preserve a legacy parser path for v4/v5 fixtures.
4. Add `SESSION_START`, `BATCH_START`, `BATCH_ABORT`, and `BATCH_COMPLETE`.
   Group structured records by SessionID/BatchID/TestID/SweepID and discard
   interrupted fragments that have no authoritative META.
5. Snapshot the data needed to compute active TIM1 switching-edge and PWM
   phase coverage. Exclude disabled channels and CCR values at 0 or outside
   ARR; report 16-bin counts/coverage, near-edge count, mean edge distance,
   and minimum edge distance rather than only a minimum.
6. Add a logic-analyzer calibration field for the fixed DWT-to-physical-CS
   offset once measured.

### Gate

- Automated parser tests pass for v4, v5, valid v6, invalid v6, and misleading
  filenames.
- Every v6 record closes with a consistent END status.
- RESULT/ACQ lines cannot silently truncate their configured buffers.

## Phase 6 — Hardware verification and experiments

### Phase A: correctness and safety

1. Verify 16 SPI clocks per frame and measure snapshot-to-physical-CS delay.
2. Confirm immediate sample 0 and scheduled start-to-start interval.
3. Run Phase-2B shadow comparison on both jig UIDs while legacy remains the
   official result source.
4. Confirm the single sweep context advances through ramp, settle, and sample.
5. Run controlled transport-error and jump-reject fault tests.
6. Verify early motor disable, invalid schema output, and batch abort.
7. Run three healthy sweeps on each known jig and record heap/stack/timing.

### Phase B: sampling pilot

Run a small factorial pilot first (representative K, interval, and motor
ON/OFF conditions with periodic reference cases). Expand to the proposed
144-combination, R=20 matrix only if the pilot shows the extra factors are
informative and operationally practical.

Compare back-to-back, fixed-interval, and PWM-phase-stratified sampling as
engineering modes. Compute lag-1/lag-2 autocorrelation, an explicitly
approximate effective sample count, point-mean variance, and acquisition time.
Use these to evaluate repeatability per unit acquisition time; do not treat
nominal sample count as independent sample count.

Primary responses are `SD_PointMean`, `SD_RMS_AC`, `SD_A36`, `SD_Closure`,
accepted-sample rate, timing-overrun rate, PWM phase coverage/dependence,
cross-jig RMS/A36 deltas, effective sample count, acquisition time, CPU, and
memory.

Select a candidate in this order: no transport/jump failure, stable closure,
point-mean and RMS/A36 repeatability, low PWM-phase dependence, cross-jig
consistency, shorter acquisition time, lower memory/CPU, and simplicity. Do
not select a configuration merely because it reports lower NL, RMS, P2P, or
INL without an independent reference encoder.

Mechanical-OFF angles remain separate operator-controlled batches unless the
real jig is confirmed to have an automatic lock/brake.

### Phase C/D: comparison

Interleave reference conditions and old/new firmware runs. Separate sampling
repeatability from remount/reacquisition repeatability.

### Gate

- Phase-A safety and correctness tests all pass before Phase B.
- No production parameter is selected from a single jig or a single motor.
- Phase-B selection is supported by repeatability/robustness evidence, not by
  the lowest reported nonlinear magnitude.

## Phase 7 — Production decision and release

1. Select production sample count, interval, jump margins, MAD policy, and
   DEGRADED handling only from Phase-B/C evidence.
2. Re-evaluate DMA only if measured timing variance affects results.
3. Validate board reset/output behavior before enabling a hardware watchdog.
4. Run final Debug/Release builds, static stack reports, and hardware smoke
   tests on both jig UIDs.
5. Update the operator checklist, schema documentation, error-code table, and
   rollback instructions.

## Change-control rule

Each phase is a separate reviewable change set. Do not mix capture-math,
controller tuning, schema semantics, and experimental parameter selection in
one change. A phase may proceed only after its gate passes and its hardware
logs are archived.

## Implementation checkpoint - 2026-07-14

Phase 3A software is now implemented. It covers one continuous sweep unwrap
context, encoder feedback during every ramp microstep, combined
stability-plus-target settle validation, a canonical anchor frozen from the
post-settle observation, and separate motion counters/log records. It does not
promote canonical output or schema 6, and it does not include the later
delta-time-aware PID work.

Motor geometry was added to the same change because it directly defines the
open-loop commutation mapping being audited. The existing PIXY setting
`MOTOR_NUM_POLSE=12` means 6 pole pairs. Firmware now logs both values and
computes a dynamic six-per-electrical-cycle diagnostic at mechanical harmonic
order 36 while retaining historical A36.

Software/host and Release build gates pass. Hardware gate status and the exact
commands/fields to verify are tracked in `phase3a-motion-settle-checklist.md`.
Motor ID remains operator-managed after each test by explicit user decision;
it was not added to the measurement-valid gate.

Post-implementation hardware review corrected the phase status: SPI/unwrap,
ramp feedback, and local settle observability pass on the reviewed data, but
endpoint equivalence does not. P03/JIG1 closure passed 0/3 and P05/JIG3 passed
3/6 at the pilot 0.20-degree limit. Phase 3B0 is therefore the blocking gate;
the 10-run qualification and Phase 4 official-validity promotion must not
start until Phase 3B0 closes.
