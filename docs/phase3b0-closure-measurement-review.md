# Phase 3B0 - Closure and Measurement-Validity Design Review

Status: **B0-A software and initial hardware logging complete. An exploratory
one-precondition plus ten-official-run protocol is implemented for fixed-jig
repeatability; B0-B/B0-C/B0-D, canonical promotion, and formal qualification
remain open.**

Updated: 2026-07-14

## Decision summary

The passive closure investigation remains diagnostic and point 0 versus point
256 equivalence is not yet proved. At the user's direction, a 10-run batch is
now enabled only as an exploratory repeatability study: one complete
precondition sweep is audited but excluded, followed by a validated 120-second
motor-off interval and ten statistic-eligible sweeps. This does not qualify the
measurement or change closure/acceptance policy. The exact execution checklist
is in `preconditioned-10run-checklist.md`.

The current measurement remains:

```text
WHOLE_SYSTEM_OPEN_LOOP_TRACKING_V1
= open-loop electrical command versus MA600A mechanical-angle response
```

It is not MA600A sensor-only INL. MPS defines sensor INL using the sensor
output averaged over many samples (for example 1000) against a high-precision
mechanical encoder below 0.001 degree. The present jig has no independent
reference encoder. See the official
[MA600A datasheet](https://www.monolithicpower.com/en/documentview/productdocument/index/version/2/document_type/Datasheet/lang/en/sku/MA600A/document_id/12989/).

## B0-A implementation checklist

- [x] Passive probe is attached only to full-turn Point 256.
- [x] `INITIAL` copies the existing Point-256 canonical shadow sample; it is
  not re-read or overwritten.
- [x] Holds use the same command, power, immutable point anchor, canonical
  sampler budget, and `shadowUnwrap` context.
- [x] Actual capture start/end times are recorded for nominal 0/50/100/200 ms
  stages.
- [x] Each window records canonical mean, closure, whole-window P2P,
  first-to-last drift, and acquisition counters.
- [x] `Official=0`; probe numeric values do not enter schema-v5 `RESULT`,
  `measurementValid`, `Motor OK`, or batch disposition.
- [x] A probe acquisition failure exits through the existing sweep safe-stop
  path.
- [x] UART formatting remains deferred until after motor disable.
- [x] `PostTurnTimingComparable=0` is emitted once the extra hold starts.
- [x] Analyzer enforces four-stage identity/timing/command invariants and
  exports individual hold values/deltas without averaging.
- [x] Positive fixture and negative baseline/command-corruption tests pass.
- [x] Deterministic sampler tests cover first/last, alternating-window P2P,
  monotonic drift, and raw wrap crossing.
- [x] All six host regression scripts pass.
- [x] Debug build passes with 0 errors/warnings: text 107,620 B, data 96 B,
  BSS 132,672 B.
- [x] Release build passes with 0 errors/warnings: text 66,796 B, data 96 B,
  BSS 132,656 B.
- [x] Release HEX SHA-256 is
  `D2B4A66FFA4266BB3E9226FD0EF3347A0FBE1D9FD8AC4BF086A4AE68426F1586`.
- [x] CCM workspace remains 10,504 B; main-SRAM linker margin after reserved
  heap/stack is 8,824 B.
- [x] Debug worst visible logging call chain is 4,448 B
  (`NonlinearEngine_Task` + `RunBatchSweep` + `NonlinearTest_Run` +
  `PrintSweepLog` + `PrintClosureProbeLog` + `LogLineLarge`) inside the
  6,656-B engine task stack. Runtime high-water remains a hardware gate.
- [ ] Flash the final rebuilt HEX and confirm runtime stack high-water,
  complete non-truncated records, and safe motor disable.
- [ ] Capture three no-remount sweeps on one fixed motor/jig with the same
  thermal/start protocol.
- [ ] Classify closure as decaying, stable-offset, or noisy from the four
  stages and window P2P/drift.
- [ ] Decide whether B0-B equivalent approach is required from that evidence.

## Correction to the previous review

Phase 3A verified acquisition continuity, ramp feedback, settle logging, pole
configuration, and transport health. It did not verify the following required
measurement invariant:

```text
point 0 state == point 256 state + exactly one mechanical revolution
```

`SettleValid=1` currently means that the shaft became locally stable and was
inside a wide 910-raw-count (about 5 degree) motion-integrity envelope. It does
not mean the shaft returned within the 0.20 degree closure envelope. The sweep
also observes position during settle but does not actuate a correction toward
the mechanical target.

Therefore the corrected status is:

| Layer | Status | Meaning |
| --- | --- | --- |
| Policy-A sensor configuration | PASS for logged known jigs | Same locked zero/filter/correction profile |
| SPI/unwrap/acquisition continuity | PASS on the reviewed logs | No transport error, jump reject, or context reacquisition |
| Ramp and local settle observability | PASS | Every motion phase is measured and logged |
| Endpoint equivalence, point 0 versus point 256 | FAIL | Closure is not consistently within the pilot 0.20 degree envelope |
| One-jig repeatability qualification | BLOCKED | Ten-run data would characterize an uncontrolled endpoint condition |
| Sensor-only trueness/INL | NOT MEASURABLE | Requires an independent reference encoder |

## Evidence from the current logs

The reviewed schema-v5 Phase-3A logs contain nine relevant sweeps:

- P03/JIG1: `P03 JIG 1 test 5.txt`, three sweeps.
- P05/JIG3: `p05 jig 3 test 5.txt`, three sweeps.
- P05/JIG3 repeat batch: `p05 jig3 test 5 lần 2.txt`, three sweeps.

| Motor/Jig | Run | Point-256 position error (deg) | Closure (deg) | Closure pass at 0.20 deg |
| --- | ---: | ---: | ---: | --- |
| P03/JIG1 | 1 | 0.74158 | 0.76106 | FAIL |
| P03/JIG1 | 2 | 0.40649 | 0.41113 | FAIL |
| P03/JIG1 | 3 | 0.30212 | 0.35414 | FAIL |
| P05/JIG3 batch 1 | 1 | 0.27466 | 0.29603 | FAIL |
| P05/JIG3 batch 1 | 2 | 0.16479 | 0.18024 | PASS |
| P05/JIG3 batch 1 | 3 | 0.13184 | 0.15080 | PASS |
| P05/JIG3 batch 2 | 1 | 0.16479 | 0.16291 | PASS |
| P05/JIG3 batch 2 | 2 | 0.19775 | 0.21492 | FAIL |
| P05/JIG3 batch 2 | 3 | 0.20874 | 0.20333 | FAIL |

Across these nine sweeps:

- correlation between point-256 position error and closure is `0.99633`;
- mean absolute difference between those two values is `0.01738 degree`;
- every reviewed sweep has zero SPI failure, zero jump reject, and zero
  context reacquisition.

This is strong evidence that closure is presently dominated by the actual
return-to-target behavior at the end of the open-loop sweep, not by the Q16
closure formula or SPI/unwrap corruption.

There is also a repeatable run-order effect that must be controlled rather
than averaged away:

| Data set | Motor-active duration, run 1/2/3 (ms) | StartRaw, run 1/2/3 |
| --- | --- | --- |
| P03/JIG1 | 16310 / 14625 / 13454 | 62517 / 62582 / 62599 |
| P05/JIG3 batch 1 | 17056 / 14983 / 13791 | 2684 / 2704 / 2710 |
| P05/JIG3 batch 2 | 17183 / 14674 / 13839 | 2720 / 2713 / 2711 |

Run 1 is not exchangeable with runs 2 and 3 under the current protocol. A
future study must explicitly select either a cold-start protocol or a defined
preconditioned protocol. It must not silently discard run 1 and call the
remaining average repeatability.

## End-to-end measurement model

```text
firmware command
  -> PWM waveform and electrical phase
  -> motor torque / cogging / load angle
  -> shaft, magnet, bearing, fixture, air gap
  -> MA600A magnetic response and digital filter
  -> SPI transaction / timestamp / unwrap
  -> settle decision and point mean
  -> relative-error / closure / RMS / harmonic metrics
  -> validity and statistical decision
```

Every layer above can change the result. Passing a downstream calculation test
does not validate an uncontrolled upstream state.

## Blocking semantic decision: what does closure mean?

Two valid measurements are possible, but they must not share one validity
policy:

### Policy option 1 - `PERIODIC_MAP_V1` (recommended for jig repeatability)

The purpose is a repeatable periodic angle-error map. Point 0 and point 256
must be samples of the same steady periodic state. The protocol therefore
needs an equivalent CW approach, potentially including a full pre-roll/fly-in
revolution before point 0 if a short local approach is insufficient. Closure
can then be an integrity gate because a non-closing map violates the assumed
periodic model.

Tradeoff: pre-roll adds motor-on time and heat, so the thermal state must be
measured or tightly standardized. The pre-roll data is not silently mixed with
the analyzed 0..255 map.

### Policy option 2 - `FIRST_PASS_TRAJECTORY_V1`

The purpose is the actual first revolution after the existing dither/start
sequence. Point 0 and point 256 intentionally have different histories. In
this policy, closure is a physical response metric containing transient
settling, friction, hysteresis, and thermal/load-angle change. It must be
reported and studied for repeatability, but a generic 0.20-degree integrity
gate cannot be assumed without a product/process requirement.

Tradeoff: this policy is representative of first-pass behavior but cannot use
periodic DFT/model assumptions uncritically when the curve does not close.

Phase 3B0 must select and log one policy ID. It is invalid to retain the
first-pass trajectory while forcing point 256 to zero with MA600A feedback and
then claim the original open-loop process is repeatable. For the user's current
goal (a stable one-jig measurement process), `PERIODIC_MAP_V1` is the default
recommendation; `FIRST_PASS_TRAJECTORY_V1` can remain a separate engineering
test if first-cycle behavior matters to the product.

## Factors that must be controlled or recorded

### 1. Measurand and reference

- Keep the current result named as whole-system open-loop tracking.
- Do not compare `Motor_System_INL_Deg` with the MA600A `<0.6 degree` sensor
  INL limit.
- Do not use the MA600A simultaneously as the feedback reference and then
  claim that the corrected result proves MA600A trueness. A trim using the
  device under test is useful only as a control diagnostic.
- Keep point 0 as a relative reference; record its absolute raw mean so that
  run-to-run movement of the starting equilibrium remains visible.

### 2. Command and control state

- Motor pole count and pole pairs must be locked and logged.
- Log commanded electrical phase, power, direction, ramp step/delay, and the
  exact command at point 0 and point 256.
- Reset state, integrator state, home duration, home final error, dither
  sequence, and start-lock duration must be explicit.
- Phase 3B0-R implements the isolated `RESET_BEFORE_EACH_HOME_V1` experiment:
  controller and PID acquisition state are reset and audited before every
  physical test. This may contribute to the observed run-order/home-duration
  effect, but hardware A/B evidence is still pending. It is not mixed with
  closure-control or equivalent-approach changes; see
  `controller-state-synchronization-checklist.md`.
- Point 0 and point 256 must be approached with equivalent direction/history
  before closure can be treated as a return-to-reference check.
- The present point-0 dither approach and the CW-only point-256 approach are
  not equivalent and may expose friction, cogging, and hysteresis.

### 3. Settle state

- Separate these concepts in logs and validity:
  `LocallyStable`, `NearGrossTarget`, and `ClosureEquivalent`.
- The current pairwise rule (`abs(sample[n]-sample[n-1]) <= 9 raw`) can pass a
  slow monotonic drift. Eight individually valid steps could still span much
  more than 9 raw counts across the complete window.
- Before production code, define a versioned settle window with whole-window
  P2P, first-to-last drift, and optional slope limits. Numeric limits must be
  selected from stationary-noise/hold data, not guessed.
- Tightening the current target tolerance without adding corrective actuation
  would mainly create timeouts; it would not make the rotor return correctly.

### 4. Mechanical and magnetic state

- Keep the motor mounted for a pure repeatability study; remount is a separate
  reproducibility factor.
- Record fixture ID, mount cycle, fastener/seat condition, shaft axial play,
  bearing condition, cable load, and rotation direction.
- Record magnet part, magnetization, air gap, concentricity, tilt, and field
  strength when equipment is available.
- H1 changes are treated as a mounting/low-order signature. A36 is treated as
  a motor/electrical-periodic signature; neither is automatically sensor INL.

### 5. Thermal and electrical state

- Record ambient, motor, sensor/PCB, and driver temperature when sensors are
  available. If not measured, the run cannot be labelled thermally controlled.
- Record supply voltage and, if available, current or current-limit state.
- Define either `COLD_START_V1` or `PRECONDITIONED_V1`; do not mix them in one
  repeatability population.
- The current 120-second cooldown is a placeholder. It is not a validated
  equal-temperature condition.
- Preserve motor-active duration and actual cooldown duration per run.

### 6. Sensor and acquisition state

- Continue the locked read-only MA600A profile and correction-table CRC gate.
- Record filter mode, direction/zero, status, sampling count, timing mode,
  accepted/attempted counts, SPI failures, jump rejects, timing overruns, and
  context reacquisitions.
- Quantify stationary canonical-mean noise before selecting a closure or
  settle threshold.
- PWM/SPI phase dependence remains an open Phase-6 experiment; a clean SPI
  transaction alone does not prove absence of PWM-correlated angle bias.

### 7. Analysis and decision state

- Preserve points 0..255 for RMS/P2P/DFT and point 256 for closure.
- Never replace individual run results with only a batch average. Report mean,
  standard deviation, min, max, range, CV, and closure pass count.
- Control limits derived from a stable population are not product
  specification limits.
- The pilot `0.20 degree` closure limit is not prescribed by ISO or the
  datasheet and must not be loosened merely to pass existing data.

## Pre-code decisions

The following are frozen for the first diagnostic implementation review:

1. Do not change legacy/schema-v5 result math.
2. Do not change PID gains, PWM power, ramp step, filter, pole count, closure
   limit, or official validity in the same change.
3. Do not promote canonical/schema v6.
4. Keep the current point-256 closure as the unmodified baseline value.
5. New numeric probe outcomes use `Diagnostic_` names and cannot change
   legacy `Motor OK` or batch continuation during the initial engineering
   experiment. A transport/acquisition/motor safety failure still forces the
   existing safe-stop and batch-abort behavior.
6. Do not average a failed closure into a passing batch result.
7. Do not call a MA600A-feedback trim an accuracy or INL validation.
8. Abort safely on any acquisition failure; all probe reads use the existing
   canonical shadow unwrap context (no new context/re-zero) and bounded
   budgets.
9. Do not assign `ClosureValid` official meaning until `PERIODIC_MAP_V1` versus
   `FIRST_PASS_TRAJECTORY_V1` is selected.

## Staged experiment plan

Only one behavioral factor is changed in each stage.

### Stage B0-A - Passive endpoint hold probe

Purpose: separate insufficient settling/slow drift from a stable static
open-loop equilibrium error.

At point 256, after the current official/shadow closure has already been
captured:

1. Keep the same electrical command and power.
2. Capture diagnostic canonical means at actual elapsed times approximately
   50, 100, and 200 ms from the original point-256 capture.
3. Log actual elapsed time, mean, position error, closure, full-window P2P,
   first-to-last drift, sample count, and acquisition counters.
4. Do not overwrite the baseline point-256 value.
5. Mark points 257..264 as not timing-comparable to older firmware because the
   diagnostic hold changes their acquisition time.

Analyzer CSV export names:

```text
ClosureProbeInitialDeg
ClosureProbeHold50Deg
ClosureProbeHold100Deg
ClosureProbeHold200Deg
ClosureProbeDelta50InitialDeg
ClosureProbeDelta100InitialDeg
ClosureProbeDelta200InitialDeg
ClosureProbeInitialWindowP2PRaw
ClosureProbeHold200WindowP2PRaw
ClosureProbeInitialWindowDriftRaw
ClosureProbeHold200WindowDriftRaw
```

Implemented record contract (still schema-v5 diagnostic, never official):

```text
CLOSURE_PROBE,
SchemaVersion=5,
Official=0,
Protocol=CLOSURE_HOLD_V1,
TestID,SweepID,JigID,MotorID,Direction,
Stage=INITIAL|HOLD_50|HOLD_100|HOLD_200,
Point=256,
CommandRaw,Power,
NominalHoldMs,CaptureStartElapsedMs,CaptureEndElapsedMs,
PointMeanRawQ16,
ClosureErrorRawQ16,ClosureErrorDeg,
WindowP2PRaw,WindowP2PDeg,WindowDriftRaw,WindowDriftDeg,
Transactions,AcceptedSamples,SpiFailures,JumpRejects,
MetadataInvalid,SkippedSlots,TimingOverruns,
MaxConsecutiveFailuresObserved,AcquisitionResult,Valid

CLOSURE_PROBE_RESULT,
SchemaVersion=5,Official=0,Protocol=CLOSURE_HOLD_V1,
Enabled,Started,Complete,ExpectedStages,AttemptedStages,ValidStages,
PostTurnTimingComparable,AcquisitionResult,Status
```

Implementation boundaries to preserve measurement correctness:

- Capture `INITIAL` with the existing canonical point-256 path before any
  extra hold.
- Advance the existing canonical `shadowUnwrap` context from point 256; do not
  create a new unwrap context, reacquire, or re-zero. Keep the original
  point-256 settled anchor immutable for the diagnostic means.
- Store only streaming sums/min/max/first/last/counters for the probe; do not
  add large point arrays, heap allocation, or task-stack buffers.
- Bound total added energized hold time and every acquisition budget.
- Defer UART formatting until after motor disable.
- A numeric closure probe failure does not rewrite legacy results; an I/O or
  motor-safety failure still safe-stops and aborts.
- Parser fixtures must prove unknown/diagnostic records cannot be mistaken for
  official schema-v5 `RESULT` data.

Required deterministic tests before hardware:

- initial closure remains bit-for-bit identical with the probe enabled;
- elapsed stages are monotonic and use actual timestamps;
- whole-window P2P catches alternating movement;
- first-to-last drift catches slow monotonic movement that passes pairwise
  delta checks;
- wrap crossing at point 256 remains continuous;
- injected SPI/jump failures preserve unwrap atomicity and safe-stop behavior;
- post-turn points are explicitly flagged timing-noncomparable;
- buffer-size, static-memory, and stack gates remain within the existing
  margins.

First run three no-remount sweeps. Interpret the result only after stationary
read noise is available:

- material decay with hold time -> settle/dynamic problem;
- stable non-zero error -> static open-loop equilibrium or approach-history
  problem;
- noisy windows -> sensor/acquisition/electrical-noise problem.

### Stage B0-B - Equivalent approach experiment

Purpose: isolate friction/cogging/hysteresis caused by unequal point-0 and
point-256 approach histories.

Compare the existing dither-start protocol with an engineering protocol that
approaches both reference states from the same direction and with the same
ramp profile. Do not mix both protocols in one batch. Each protocol requires
its own ID and at least three no-remount sweeps.

Test the least invasive same-direction local approach first. If it does not
produce a stable periodic state, evaluate a separately versioned full
pre-roll/fly-in revolution. Pre-roll changes heat and total motor-on time and
therefore cannot be combined silently with the local-approach data.

### Stage B0-C - Post-baseline closed-loop trim diagnostic

Purpose: determine whether active correction can remove the endpoint error.

This stage is allowed only after B0-A/B results are reviewed. It runs after
the unmodified closure has been stored. It must log pre-trim closure,
post-trim closure, trim iterations, elapsed time, and actuator command change.
It remains diagnostic because the MA600A is both the feedback device and the
measured device.

### Stage B0-D - Freeze the measurement protocol

Select one protocol based on evidence, give it a new explicit version, and
rerun three no-remount sweeps. Required pilot gate:

- acquisition and motion structural checks pass 3/3;
- for `PERIODIC_MAP_V1`, closure passes the unchanged pilot limit 3/3;
- for `FIRST_PASS_TRAJECTORY_V1`, closure remains an individual response
  metric and passes a predeclared repeatability rule rather than being averaged
  into another metric;
- no result is hidden by averaging;
- start state, run order, thermal state, and approach protocol are complete;
- legacy/canonical metric changes are explained and within the predeclared
  comparison policy.

Only after this gate passes may the 10-run repeatability batch be enabled.

## Ten-run qualification after Phase 3B0

The 10-run batch remains ten independent results. It must add a batch summary
without replacing individual results:

```text
RunCountValid
Mean / StdDev / Min / Max / Range / CV
ClosurePassCount
FirstRunSeparated
ThermalProtocol
ProtocolVersion
```

Initial `PERIODIC_MAP_V1` qualification requires 10/10 structural-valid and
10/10 closure-valid runs. `FIRST_PASS_TRAJECTORY_V1` requires 10/10
structural-valid runs plus a separately declared closure-repeatability rule;
it must not reuse the periodic-map closure validity field. Population control
limits and measurement capability are selected only after a larger stable
study (target at least 30 results) and a defined product tolerance.

ISO 5725-1 supplies the distinction between trueness and precision and the
controlled repeatability conditions; ISO 22514-7 addresses capability for a
specific measurement task; ISO 10012 addresses controlled measurement
processes and change management. These standards do not supply the jig's
numeric 0.20-degree closure limit:

- [ISO 5725-1:2023](https://www.iso.org/standard/69418.html)
- [ISO 22514-7:2021](https://www.iso.org/standard/80624.html)
- [ISO 10012:2026](https://www.iso.org/standard/10012)

## Phase 3B0 exit gate

B0-A diagnostic software is complete. Repeatability qualification may start
only when all of the following are true:

- [x] Measurand and B0-A diagnostic protocol version are explicit.
- [ ] Closure semantics are selected: periodic integrity gate or first-pass
  response metric.
- [ ] Point-0/point-256 approach equivalence is defined.
- [ ] Settle-window metrics and limits are defined from measured stationary
  behavior.
- [ ] Thermal protocol is named and observable.
- [ ] B0-A evidence distinguishes dynamic drift from static endpoint error.
- [ ] Any B0-B/B0-C change is isolated in a separate A/B experiment.
- [ ] Three pilot runs pass structural and closure gates without averaging.
- [x] Parser/test requirements and rollback behavior are reviewed.
- [x] No claim exceeds the available reference architecture.
