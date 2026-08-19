# System Architecture Review — NL + Power Component Split (2026-08-18)

**Status: APPROVED for implementation (Revision 3).** Two closing conditions attached by the
reviewer are folded into acceptance criteria below (§11) and must be satisfied by the contract
tests in implementation step 6, not assumed. `nonlinear_test.c` and the official NL image are
unchanged by this approval and remain untouched throughout Power's implementation (§4.4, §9
decision 4).

**Role:** System architecture review, as requested, performed before further firmware work.
**Scope decision (per stakeholder instruction):** split the jig's measurement responsibility
into exactly the two functions Gremsy's own original jig implements — **Nonlinear (NL)** and
**Power-minimum (Power)** — and explicitly **exclude phase-resistance testing** from this
project's scope. Coding standard target: **MISRA C:2012**.

This document is the architecture-level artifact. It does not change any code. Every numeric
threshold carried over from Gremsy's original firmware is marked **reference-only, not
adopted** — re-validation against this project's own pipeline (64-sample canonical mean, 1°
grid, `SettleContract=STABILITY_ONLY_CAPTURE_V1`) is required before any value here becomes a
pass/fail spec, per the existing no-threshold rule in `AGENTS.md`.

**Revision 2 (same day):** an independent architecture counter-review challenged Revision 1 on
11 points. Every code citation in that counter-review was independently re-verified against
this repository before being accepted — see §10 for the full accept/reject/refine audit trail.
Ten of eleven points were accepted and are folded into the sections below; two were accepted
with a scope refinement (§10, #3 and #11); one (#2) is noted as resolved-by-side-effect rather
than independently actioned. Sections 3, 5, and 9 changed materially from Revision 1.

**Revision 3 (same day):** a second counter-review round, after the reviewer accepted this
document's #2/#3/#11 rebuttals, raised 3 further findings plus a schema suggestion. All were
independently re-verified against source before disposition — see §10 for the full trail. Two
were accepted outright (complete worst-case timing bound; duty-proxy environmental contract and
"first passing level" semantics); one was accepted on diagnosis but resolved with a lighter fix
than proposed (motor/PID decoupling via `motor_pwm.h` directly, not a new facade file); the
schema suggestion was accepted in intent, refined in implementation (no NL-vocabulary fields on
`POWER_RESULT` records). Sections 5.1, 5.2 (FR-PWR-2, FR-PWR-5, FR-PWR-6), 5.3 (NFR-PWR-1), 6,
7, and 8 changed materially in this revision.

---

## 1. As-is assessment

| Area | Finding |
|---|---|
| `Core/Src/nonlinear_test.c` | 531 KB, 131 top-level functions in one translation unit. Sweep engine, MA600 canonical capture, error/NL math, harmonic analysis, schema-v6 logging, and batch orchestration are all interleaved in this one file. |
| `Core/Inc/nonlinear_test.h` | Clean, minimal public surface: `NonlinearEngineState_t` (IDLE→PRECHECK→HOME→LOCK→RAMP→SETTLE→ACQUIRE→ANALYZE→REPORT→COOLDOWN→SAFE_STOP), `NonlinearEngine_Init/RequestStart/IsBusy/GetState`. This is a good pattern — the problem is entirely on the `.c` side, not the interface. |
| `Core/Src/motor.c` / `motor_pwm.c` | Already provide the actuation primitive a Power component needs: `Motor_SetElectricalPos(uint16_t pos, float power)` (open-loop electrical-angle + power command — exactly Gremsy's `gremsyMotorMovePos` primitive). **No new low-level motor-driver code is required for the Power component.** `position_controller.c` (closed-loop PID) is deliberately **not** a Power dependency — see §5.4. |
| `Core/Src/ma600.c` / `ma600_acquisition.c` | MA600 driver, Policy-A config gate, canonical multi-sample acquisition. `MA600_AcquireSample()` already implements retry, transport-error flagging, and unwrap-with-jump-rejection (`ma600_acquisition.c:19-60`) — this is the acquisition primitive Power's stall detection must reuse (§5.2). |
| Power-measurement code | **Does not exist in this project.** `grep` for `PowerMin`/`PwrMin`/`POWER_MIN` across `Core/Src` and `Core/Inc` returns nothing. This is a net-new component, not a refactor. |
| Resistance-measurement code | Does not exist in this project either (Gremsy's original `resistorA/B/C` checks use separate ADC hardware this jig does not have). Confirms it is out of scope by construction, not just by choice. |
| ADC1 | Configured in `main.c` (`ADC_CHANNEL_1`, `ADC_CHANNEL_4`, DMA continuous, 2 conversions) but **never started or read anywhere** — `grep` for `HAL_ADC_Start`/`HAL_ADC_GetValue`/`HAL_ADC_PollForConversion` across `Core/Src` returns nothing. Relevant to §5.1's measurand-naming finding. |
| `app_mode.h` / `app_engine.c` | Build-time `JIG_APP_MODE` (`CONTROL` / `MEASUREMENT`) selects **exactly one** compiled engine via `#if`/`#else` — confirmed by reading `app_engine.c` directly, there is no third branch and no runtime mode switch. `app_engine.h:10-11` states this explicitly: "Implementations are compile-time selected; there is no runtime transition between modes." Revision 1 of this document proposed a runtime-selected shared image, which contradicts this established precedent — corrected in §3. |
| RTOS allocation | `NonlinearEngine_Init()` and `ControlEngine_Init()` both call `osMessageQueueNew(1U, sizeof(uint8_t), NULL)` and `osThreadNew(..., &attributes)` with no `.cb_mem`/`.stack_mem`/`.mq_mem` supplied — this draws from the FreeRTOS heap (`configSUPPORT_DYNAMIC_ALLOCATION`), once, at `Init()`, not during any measurement loop. `main.c`'s `USER CODE BEGIN/END RTOS_MUTEX` block is empty — no mutex exists yet anywhere in this firmware. Revision 1's "no dynamic memory allocation observed" claim conflated MISRA Rule 21.3 (no C-library heap functions in application logic — true) with a system-wide no-allocation claim (not true, though the allocation is one-time and checked for failure in both call sites). |
| MISRA-relevant baseline | Fixed-width types (`stdint.h`) used throughout; `bool` from `stdbool.h` used consistently; state machines are `switch`-based enums, not function-pointer tables. This is a MISRA-friendly starting point. The monolithic file size and interleaving of concerns is the main structural gap, not the coding style. |

---

## 2. Reference requirements source: Gremsy's original implementation

Read directly from `datacty/gremsyTaskManager.c` and `datacty/gremsyProfiles_PM1505.h` (Gremsy's
own jig firmware, found in this repo's working tree). Cited here as the **requirements source**
for the Power component (which this project has never implemented) and as a **cross-check**
for the NL component (which this project already implements independently).

### 2.1 NL — confirms this project's existing formula, differs on sampling/grid detail

```c
selftest.motorNL_PosAngle = 360.0f * selftest.motorNL_Pos / 65535.0f;
selftest.motorNL_EncAngle = selftest.motorNL_EncAngleSum / selftest.motorNL_Count;
selftest.motorNL_ErrorTmp = selftest.motorNL_PosAngle
                           - (selftest.motorNL_EncAngle - selftest.motorNL_EncAngleOffset);
...
selftest.motorNL_Error = selftest.motorNL_ErrorMax - selftest.motorNL_ErrorMin;
```

Identical measurand definition to `AGENTS.md`'s RULE 0 formula and this project's
`OpenLoopNL_Deg`. Differences from this project's current pipeline (methodology deltas to
carry into Component 1 requirements, §4):

| Parameter | Gremsy original (`gremsyProfiles_PM1505.h`) | This project (S4, schema v6) |
|---|---:|---:|
| Samples averaged per point | `MOTOR_NONLINEAR_SAMPLES = 5` | 64 (canonical mean, ALG-001-fixed) |
| Angular step | `MOTOR_NONLINEAR_POS_INCREASE = 256` raw ⇒ ≈1.406° | 1.000° (`UNIFORM_1_DEG_ROUNDED_RAW_V1`) |
| Settle method | fixed `MOTOR_NONLINEAR_SLEEP_TIME = 5 ms` delay | active stability polling (`SettleContract=STABILITY_ONLY_CAPTURE_V1`) |
| Repeats per test | `GREMSY_NL_TEST_REPEAT_COUNT = 1` | 10 official sweeps/batch |
| Pass/fail threshold | `GREMSY_QC_PROFILES_NONLINEAR_ANGLE_MAX = 5.0°` (comment: PAN123 variant 3.5°, default 1.7°) | **none calibrated yet** (`AGENTS.md` rule) |

**Reference-only, not adopted.** The threshold cannot be carried over as-is: this project's
64-sample/1°-grid pipeline measures a systematically less noisy, finer-grid curve than
Gremsy's 5-sample/1.406°-grid original, so the same physical motor would not necessarily
produce the same `RawP2P` value on both pipelines. Re-validate against reference units before
treating 1.7–5.0° as a spec range for this jig.

### 2.2 Power — full algorithm, re-derived and independently verified against the source

```c
// ST_STATE_POWER_MOVE_MIN_CW_INIT
power = MOTOR_PWR_MIN_POWER_START;                    // 0.075 (7.5%), not yet commanded

// ST_STATE_POWER_MOVE_MIN_CW_LOCK  (re-entered on every stall)
pos = (currentRawEncoder - motorOffset) % MOTOR_COUNT_PER_POLSE;   // re-synced to actual position,
                                                                     // wrapped to one electrical cycle
if (power < MOTOR_PWR_MIN_MAXIMUM_CHECK) {            // 0.15 (15%) ceiling
    power += MOTOR_PWR_MIN_POWER_INCREASE;             // 0.001 (0.1%) — so the FIRST power
                                                         // actually commanded is 7.6%, not 7.5%
    gremsyMotorMovePos(pos, power);
    osDelay(MOTOR_PWR_MIN_TIME_LOCK);                  // 50 ms
    encAngleOffset = gremsyEncoderReadAngle();          // progress reference reset
    goto MOVE;
} else {
    goto CALCULATE;                                     // ceiling reached without success: FAIL
}

// ST_STATE_POWER_MOVE_MIN_CW_MOVE
pos += MOTOR_PWR_MIN_POS_INCREASE;                     // 2048 raw ⇒ 11.25 deg/step
gremsyMotorMovePos(pos, power);
osDelay(MOTOR_PWR_MIN_TIME_LOCK);                       // 50 ms
posAngle = 360.0f * pos / 65535.0f;                     // cumulative SINCE LAST LOCK RE-ENTRY,
                                                         // not since test start (pos was rewrapped)
encAngle = gremsyEncoderReadAngle() - encAngleOffset;   // progress SINCE LAST STEP
if (posAngle > MOTOR_PWR_MIN_ANGLE_ROTATION)            // 1080 deg = 3 full turns at THIS power
    goto CALCULATE;                                     // success at this power level
else if (encAngle < MOTOR_PWR_MIN_ANGLE_ERROR)          // 0.1 deg: no progress since last step
    goto LOCK;                                          // stall -> escalate power, restart the
                                                         // 1080 deg counter at the new power level
else
    encAngleOffset = gremsyEncoderReadAngle();           // progressed enough: reset step reference,
                                                          // stay in MOVE, keep accumulating pos
```

Result: `motorPwrMinCW_PowerPercent` = the lowest open-loop PWM duty fraction at which the motor
sustains three full open-loop-commanded revolutions **counted fresh at that power level**
(the 1080° counter restarts on every stall because `pos` is rewrapped in `LOCK`), without any
single 50 ms step producing less than 0.1° of encoder progress. Compared against
`GREMSY_QC_PROFILES_PWR_MIN_NORMAL_PERCENT = 14.0%`.

**Confirmed: Gremsy's own original implementation never reads voltage or current.** `grep` for
`ADC`/`Voltage`/`Current`/`Vbus` across `datacty/gremsyMotor.c`, `gremsyMotor.h`, and
`gremsyTaskManager.c` returns nothing. Gremsy's own production QC treated PWM duty fraction as
the "power" measurand and shipped it that way — see §5.1 for what this means for this
project's naming.

**This is a torque/actuation-margin test, not a position-accuracy test.** It answers "can this
motor's magnet/commutation/bearing assembly reliably produce enough torque at reduced drive,"
which is exactly the class of defect (weak magnet, excess friction, commutation fault) that NL
alone cannot see — matching the earlier finding this session that Gremsy uses NL and Power as
two independent, parallel gates, not one metric standing in for the other.

---

## 3. Target architecture (revised)

### 3.1 Three compile-time images, not two engines in one image

Revision 1 proposed one firmware image containing both engines, runtime-selected. This
contradicted the codebase's own established precedent (§1) and was withdrawn during audit
(§10, #1). Corrected model — a third value for the existing mode switch:

```c
/* app_mode.h */
#define JIG_APP_CONTROL                 1
#define JIG_APP_MEASUREMENT_NL          2   /* was JIG_APP_MEASUREMENT */
#define JIG_APP_MEASUREMENT_POWER       3   /* new */
```

`app_engine.c` gains a third `#elif` branch dispatching to `PowerEngine_*`, following the exact
shape it already uses for `ControlEngine_*` vs `NonlinearEngine_*`. Each image contains exactly
one engine's code. **NL and Power can never coexist in the same binary**, which removes the
runtime-ownership/race problem Revision 1's shared-image design would have created — there is
no cross-engine `IsBusy()` check to get wrong, no supervisor/mutex arbitration to build, because
the two engines are never linked together in the first place. (Revision 1 proposed a
`MeasurementOwner_t` arbitration primitive for this; it is not needed once the image split is
adopted, and is deliberately omitted here rather than built to guard against a scenario that
cannot occur.)

```
                    Shared board support (compiled into every image)
        MA600 driver + Policy A gate | Motor open-loop primitive | Logging/schema
                                      |
        +----------------------------+----------------------------+
        |                            |                             |
  JIG_APP_CONTROL          JIG_APP_MEASUREMENT_NL        JIG_APP_MEASUREMENT_POWER
  (existing)                (existing, unchanged)         (new, §5)
```

### 3.2 Component boundary rule

Both measurement images depend on Shared Services; neither depends on the other, and this is
now enforced by the linker (separate binaries), not just by convention or a runtime check.

---

## 4. Component 1 — NL Measurement Engine (existing, requirements restated for the split)

### 4.1 Functional requirements

- FR-NL-1: Compute `Error[i] = CommandAngle[i] - (EncoderMeanAngle[i] - EncoderOffset)` from a
  canonical multi-sample mean per point. (Already implemented; ALG-001-compliant.)
- FR-NL-2: Compute `OpenLoopNL_Deg = max(Error) - min(Error)` over the full analysis grid, with
  no filtering, exclusion, or harmonic reconstruction applied to the primary value. (Already
  implemented, verified against `nonlinear_test.c:2294`.)
- FR-NL-3: Motor actuation during the official sweep MUST remain open-loop; encoder samples
  MUST NOT modify the command before the point is frozen. (`AGENTS.md` RULE 0; already enforced
  by the `NL_PROFILE_GREMSY_OPEN_LOOP` compile-time guard.)
- FR-NL-4: Emit schema-v6-compliant `RESULT` records with `MeasurementProfile`,
  `OfficialOpenLoopNL`, `FeedbackActuationEnabled`, full harmonic set as supporting fields only.

### 4.2 Non-functional requirements

- NFR-NL-1: CCM RAM headroom ≥ 8 KB out of 64 KB total (established budget; currently ~11.9 KB
  free at `0xD088` used).
- NFR-NL-2: **Within-mount** repeatability CV ≤ 2% on `RawP2P` across 10 official sweeps, same
  physical mount, same jig (already met: 0.41–1.61% observed across every product tested this
  session). This is a **provisional pilot target for a single, narrow claim** — same-mount
  repeatability — and is not evidence toward, and must not be read as implying, cross-jig
  qualification, which is a separate, currently unmet objective (§9, decision 2).
- NFR-NL-3: No dynamic memory allocation in measurement/data-plane logic (MISRA Rule 21.3);
  all sweep-point buffers statically sized to `NL_MAX_SWEEP_POINTS`. RTOS task/queue objects
  created once at `Init()` via CMSIS-RTOS2 defaults draw from the FreeRTOS heap — this is a
  distinct, one-time, failure-checked allocation outside the measurement loop, not a Rule 21.3
  violation, and should be described as such rather than folded into a blanket "no dynamic
  allocation" claim (§1, RTOS allocation row).

### 4.3 Isolation from Power

- FR-NL-5: NL and Power are separate compile-time images (§3.1). No runtime mutual-exclusion
  logic between them is required or should be built.
- FR-NL-6 (new): NL and Power tests on the same physical unit MUST NOT be treated as thermally
  independent. Power's search (§5.2) can run for tens of seconds to several minutes and directly
  heats the motor/driver; running NL immediately afterward on the same unit measures a
  different thermal state than a cold-start NL run. Operating rule: run NL before Power on any
  given unit, and treat any NL run performed after a Power run on the same unit as a distinct,
  separately-labeled condition, not interchangeable data. (This mirrors a finding already
  observed empirically this session: creep/correction success rate on one unit degraded from
  14.8% to 48.5% across three consecutive sweeps, consistent with thermal state affecting
  actuation-margin behavior — the same mechanism Power's search is designed to probe.)

### 4.4 Refactor requirement — sequencing changed

`nonlinear_test.c`'s internal seams (sweep orchestration, canonical acquisition math, harmonic
analysis, schema-v6 formatting) remain worth splitting into separate translation units for
maintainability. **This is explicitly deferred until after Power exists and is validated**
(§9, decision 4) — reversed from Revision 1. Rationale: `nonlinear_test.c` is the
hardware-validated official measurement path this project has spent a full day of hardware
testing confirming; restructuring it for a reason unrelated to NL itself (making room for
Power) is an avoidable regression surface (linkage, stack depth, floating-point evaluation
order, CCM/section placement, and logging order can all shift under a mechanical file split).
Once Power lives in its own image (§3.1), it no longer needs `nonlinear_test.c` reorganized to
"make room" — the two never share a translation unit. If/when the NL split is done later, it
must be validated by golden-log numerical equivalence and a hardware A/B run confirming the
360-point curve is unchanged, not treated as a pure mechanical no-op.

---

## 5. Component 2 — Power Measurement Engine (new)

### 5.1 Measurand naming

Without voltage/current sensing (§1: ADC1 configured but never read; §2.2: confirmed absent
from Gremsy's own original implementation too), this component measures and must be named as:

```
MinimumCommandedDutyPermille   (primary result)
ActuationMarginSearchTrace     (supporting diagnostic — see §5.3 for what is actually retained)
```

Not `PowerMinPercent` or any name implying a measured electrical quantity (W, V, A). This is a
naming/documentation fix, not a hardware gap that blocks implementation: Gremsy's own
production QC used exactly this duty-fraction proxy, unmeasured against real power, and shipped
it. Adding real V/I sensing (using the two already-configured but unread ADC1 channels, if they
are in fact wired to voltage/current sense points — needs schematic confirmation, not assumed)
is a legitimate future enhancement that would exceed Gremsy's own original rigor; it is not
required to reach parity with the reference implementation and is not a precondition for this
component to ship.

**Result semantics — first passing level, not a physical minimum.** The search (§2.2) is a
discrete, monotonic-ascending sweep at 1‰ resolution that stops at the first level completing
the full commanded rotation; it never re-verifies by descending and never re-tests a level twice.
The reported value is therefore `FirstPassingDutyPermille`, an order-dependent result of one
specific discrete search, not a continuous physical minimum-sustaining-torque value. Use this as
the field name (or document `MinimumCommandedDutyPermille` with this exact caveat inline) so a
future reader does not treat it as a lab-grade minimum. Record alongside it:
`SearchResolutionPermille=1`, `SearchDirection=ASCENDING`, `MotionDirection` (CW/CCW).

**Cross-jig/cross-unit comparability requires an explicit environmental contract.** A duty
fraction is not a physical constant — the same physical motor can produce different torque at
the same commanded duty if supply voltage, PWM frequency/dead-time, or thermal state differ
between test rigs. This is the same class of instrument-dependence this session spent all day
establishing for NL (§9, decision 2); it applies identically here and must not be assumed away.
Every `POWER_RESULT` record must carry: nominal supply voltage and tolerance, PWM
frequency/timer ARR, dead-time compensation state (`ENABLE_DEADTIME_COMPENSATION_FEEDFORWARD`
and any related flags), motor pole-pair count, and starting/ambient thermal state. Without these
recorded, a duty-fraction result from one jig cannot be meaningfully compared to another's, same
as `RawP2P` cannot.

### 5.2 Functional requirements

- FR-PWR-1: Determine the minimum open-loop PWM duty fraction at which the motor sustains a
  commanded multi-revolution open-loop sweep without stalling, per the algorithm in §2.2,
  including its two subtle behaviors independently re-derived from source: (a) the actually
  first-commanded duty is `POWER_MIN_START + POWER_MIN_INCREASE` (7.6% under Gremsy's
  reference constants, not 7.5%), and (b) the rotation counter restarts at each new duty level
  because position is rewrapped modulo one electrical cycle on every stall re-entry.
- FR-PWR-2: Stall detection MUST distinguish three outcomes at each step, not two, and every
  bound below MUST be a named compile-time constant, not left implicit:
  - **Motion confirmed** — encoder progress since the last reference reset ≥ threshold.
  - **Stall confirmed** — `MA600_AcquireSample()` returned `MA600_RESULT_OK` (valid, in-range
    reading) for the check, and progress is below threshold for `PWR_STALL_CONFIRM_COUNT`
    consecutive checks (re-reads at the same commanded position, not new commands), not a
    single sample. A single-sample threshold-cross MUST NOT by itself trigger escalation.
  - **Acquisition invalid** — `MA600_AcquireSample()` reported a transport error, retry
    exhaustion, or a jump rejected by `maxJumpRaw` (reusing the existing acquisition primitive
    at `ma600_acquisition.c:19-60`, not a new one). Retried up to `PWR_MAX_ACQUIRE_ATTEMPTS`
    within the call and up to `PWR_MAX_INVALID_READS_PER_STEP` at the step level; exceeding the
    latter is a hard `ACQUISITION_FAILED` abort, not an indefinite hold. MUST NOT be interpreted
    as a stall and MUST NOT drive duty escalation.
- FR-PWR-3: On confirmed stall, increase duty by a fixed step and retry from the current
  position (matching Gremsy's re-sync-not-restart-from-zero behavior in §2.2) up to a defined
  ceiling; exceeding the ceiling without completing the full commanded rotation is a hard FAIL
  for that unit, not a retry-forever condition.
- FR-PWR-4: On success, report `MinimumCommandedDutyPermille`. The full step-by-step trace is a
  bounded diagnostic artifact, not a stored-in-full primary result — see §5.3 for the memory
  budget this constrains it to.
- FR-PWR-5: Motor actuation MUST use `motor_pwm.h`'s primitives directly
  (`MotorPwm_Init/Enable/Disable/SetElectricalPos`) — **not** the `motor.c` facade. Verified by
  reading source: `motor.c` unconditionally includes `position_controller.h` and both
  `Motor_Init()`/`Motor_RunControllerSelfTest()` unconditionally initialize and self-test the
  PID (`motor.c:9,63,70`), and `main.c` calls both with no `#if JIG_APP_MODE` guard — so a Power
  image built on top of `motor.c` would still link the closed-loop controller despite never
  calling it. `motor_pwm.h`/`motor_pwm.c` were confirmed by direct read to have zero
  dependency on `position_controller.h` — Power can reach the exact primitive it needs
  (`MotorPwm_SetElectricalPos`, matching Gremsy's `gremsyMotorMovePos`) through this lower layer
  with no new files and no changes to existing ones. Acceptance test: the Power image's linker
  map MUST contain no `PositionController_*` symbols.
- FR-PWR-6: Emit its own measurement-contract identity, distinct from NL's
  `NL_MEASUREMENT_PROFILE` — e.g. `MeasurementDefinition=ACTUATION_DUTY_MARGIN_V1` — so a log
  consumer can never conflate a Power record with an NL record. Power is a **third, independent**
  measurand category alongside NL's `OPEN_LOOP_MEASUREMENT`/`DIAGNOSTIC_ONLY` split, not a
  variant of either. Its own record type (`POWER_RESULT`, distinct from NL's `RESULT` — SVC-3)
  already makes it structurally unreachable by any NL log parser; do not additionally borrow
  NL-specific field names like `OfficialOpenLoopNL`/`EligibleForStatistics` into a
  `POWER_RESULT` record — that vocabulary belongs to NL's own classification, and importing it
  into a structurally distinct record type implies Power was considered for and excluded from
  NL statistics, which is not accurate; it was never in that category. Use
  `MeasurementClass=ACTUATION_DUTY_MARGIN_V1` as Power's own, independent classification field.

### 5.3 Non-functional requirements — worst-case bound, independently computed and verified

- NFR-PWR-1: **Worst-case runtime bound, derived from every bounded operation, not just
  commanded-step dwell.** Duty range 7.6%–15.0% at 0.1% steps ⇒ ≤ 75 duty levels
  (`PWR_MAX_DUTY_LEVELS`). Each level's rotation counter restarts (§2.2), so a level where the
  motor moves just above the stall threshold for the entire 1080° (96 steps of 11.25° at
  `POS_INCREASE=2048` raw, `PWR_MAX_STEPS_PER_LEVEL`) before the *next* level finally succeeds
  or the ceiling is hit costs up to 96 steps; this can recur across levels. Each step's dwell is
  not just the 50 ms `MOTOR_PWR_MIN_TIME_LOCK` — it also includes the encoder acquisition call,
  which can itself retry: `MA600_DMA_TIMEOUT_US = 10000U` (10 ms) per transaction attempt
  (confirmed in `ma600.c`), times `PWR_MAX_ACQUIRE_ATTEMPTS`. This project already uses 3
  attempts as its standard retry count elsewhere (`MOTOR_PID_READ_ATTEMPTS = 3U` in `motor.c`);
  adopting the same value here gives a per-step worst case of `50 ms + 3 × 10 ms = 80 ms`.
  Complete provable bound: `75 levels × 96 steps × 80 ms ≈ 576 s (~9.6 minutes)`, plus the
  initial `LOCK` entry per level (negligible, ≤75 × 50 ms ≈ 3.75 s) and `PWR_STALL_CONFIRM_COUNT`
  consecutive-check overhead if that confirmation re-reads rather than reusing the same sample.
  **576 s, not 360 s, is the number that must drive watchdog/timeout design** — this document's
  own prior draft omitted acquisition-retry time and understated the bound by ~60%. A motor that
  stalls near-immediately at every failing level, succeeding only at the last, would finish in
  roughly 12–15 s; the architecture must be designed against the ~576 s worst case, not the
  typical case.
- NFR-PWR-2: **Trace memory bound, derived, not assumed.** Worst case per NFR-PWR-1 is
  `75 × 96 = 7200` step records. Even a compact 16-byte record is ≈115 KB — far beyond the
  ~11.9 KB CCM headroom this project budgets (§4.2, NFR-NL-1). Therefore the full per-step
  trace MUST NOT be held as a monolithic static array. Required design: retain only an O(1)
  rolling aggregate (current duty, current step count, best-known passing duty) as the primary
  live state, plus a small bounded diagnostic ring (32–128 most-recent transition events —
  duty changes and stall confirmations only, not every 50 ms step) sized and justified
  explicitly in the implementation, not left as "TBD."
- NFR-PWR-3: The ceiling duty (`POWER_MIN_MAXIMUM_CHECK`, reference value 15%) MUST be derived
  from this project's own motor-driver current/thermal limits before being adopted — Gremsy's
  PM1505 value is reference-only (§2.1's caveat applies equally here), and per NFR-PWR-1's
  6-minute worst-case bound, sustained operation near this ceiling for an extended run is a
  real thermal-load scenario to validate against, not just an instantaneous current check.
- NFR-PWR-4: Any diagnostic logging emitted **during** the search loop MUST NOT use blocking
  UART transmission on the measurement-critical path. `HAL_UART_Transmit(...)` with an explicit
  timeout is used elsewhere in this project (`nonlinear_test.c:1704`, `control_engine.c:317`,
  both confirmed blocking calls) — reusing that pattern inside the 50 ms step cadence would let
  UART drain time perturb the timing Power itself measures. Required: defer trace emission to
  after the motor is disabled (post-`SEARCH` state), or use a queued/DMA path with explicit
  backpressure handling that cannot stall the motion loop.

### 5.4 Interface (mirrors `nonlinear_test.h`'s existing pattern for consistency)

```c
/* power_test.h */
typedef enum
{
    PWR_ENGINE_IDLE = 0,
    PWR_ENGINE_PRECHECK,
    PWR_ENGINE_HOME,
    PWR_ENGINE_SEARCH,      /* duty-escalation loop, FR-PWR-1..3, bounded per NFR-PWR-1 */
    PWR_ENGINE_REPORT,
    PWR_ENGINE_COOLDOWN,
    PWR_ENGINE_SAFE_STOP,
} PowerEngineState_t;

bool PowerEngine_Init(void);
bool PowerEngine_RequestStart(void);
bool PowerEngine_IsBusy(void);
PowerEngineState_t PowerEngine_GetState(void);
```

Deliberately the same shape as `NonlinearEngine_*`. `IsBusy()` is retained for the normal
single-engine reason every engine in this codebase already needs it (rejecting a second start
request while one test is running) — not for cross-engine arbitration, which §3.1 establishes
is unnecessary.

### 5.5 RTOS execution contract — required before implementation, not optional

`NonlinearEngine_Init()` sets a concrete, justified execution contract for its task
(`stack_size = 12288`, `priority = osPriorityAboveNormal`, with the sizing rationale documented
inline from `.su` stack-usage reports). Power's task needs the equivalent, derived for its own
call depth and duration, not copied blindly:

- Task priority and justification (Power's search runs far longer than an NL sweep — §5.3 — so
  its interaction with default/idle tasks reading MA600 periodically needs explicit review, not
  an assumed-safe default).
- Stack size, backed by a `.su`/static-analysis figure once the implementation exists, matching
  the precedent already set for the NL task.
- Queue depth for its command interface (NL's precedent: depth 1, matches the "reject a second
  start while busy" contract already required in §5.4).
- Abort/cancel latency bound, and a hard requirement that **every** exit path — success, FAIL,
  abort, watchdog trip — calls `Motor_Disable()` before the state machine leaves `SEARCH`.
- Explicit ownership handoff of the MA600 SPI/DMA resource: `ma600.c`'s DMA state
  (`ma600DmaState`) is a singleton, not reentrant — Power must not begin a new acquisition while
  a prior one is still `MA600_DMA_BUSY`, matching the discipline NL's capture loop already
  follows.

---

## 6. Shared Services — requirements carried over, stated explicitly for the split

- SVC-1: MA600 driver and Policy-A config gate (`ma600.c`) are consumed read-only by both
  measurement images; neither engine may write MA600 configuration registers directly — only
  through the existing gated init path.
- SVC-2: NL and Control use the `motor.c` facade (which always links `position_controller.c` —
  confirmed unconditional in `Motor_Init()`/`Motor_RunControllerSelfTest()` and in `main.c`'s
  calls to them, pre-existing in this codebase, not introduced by this split). Power uses
  `motor_pwm.c` directly, bypassing the facade entirely (§5.2, FR-PWR-5) — confirmed by reading
  `motor_pwm.h`/`motor_pwm.c` to have no dependency on `position_controller.h`. No new facade
  file is needed; `motor_pwm.c` is compiled into both the NL/Control images (via `motor.c`) and
  the Power image (directly), never at runtime by more than one engine since they are never in
  the same binary (§3.1).
- SVC-3: Logging/schema layer accepts records from both engines but MUST keep their record
  types visually and programmatically distinct (`RESULT` for NL, a new `POWER_RESULT` for
  Power) so existing NL log parsers (this project's Python/PowerShell/MATLAB analyzers) are not
  silently fed Power data or vice versa.

---

## 7. MISRA C:2012 compliance requirements for this split

Applies to both new/refactored components. The existing codebase already satisfies several of
these; listed for completeness so the split doesn't regress them.

| Rule / Directive | Requirement for this work | Current status |
|---|---|---|
| Rule 21.3 | No `malloc`/`free`/`calloc`/`realloc` in application/measurement logic | Met in code inspected. CMSIS-RTOS2 task/queue creation at `Init()` uses the FreeRTOS heap once, outside the measurement loop — document this as a stated, deliberate exception (or move to static `osThreadAttr_t`/`osMessageQueueAttr_t` allocation) rather than claiming zero dynamic allocation system-wide (§1). |
| Rule 17.2 | No direct or indirect recursion | Met (state-machine `switch` pattern, no recursive calls observed) |
| Directive 4.1 | Every loop with a retry/escalation structure must have a compile-time-provable bound | Power's search loop bound is now derived explicitly across every nested retry level (§5.3, NFR-PWR-1: ~576 s worst case) — must be expressed as compile-time constants (`PWR_MAX_DUTY_LEVELS`, `PWR_MAX_STEPS_PER_LEVEL`, `PWR_MAX_ACQUIRE_ATTEMPTS`, `PWR_MAX_INVALID_READS_PER_STEP`, `PWR_STALL_CONFIRM_COUNT`) with a static assertion or equivalent, not left implicit in loop logic |
| Rule 8.7 | Functions/objects used only within one file must be `static` | Follow existing convention already used in `nonlinear_test.c` |
| Rule 8.13 | Pointer parameters that are not modified by the callee must be `const`-qualified | Apply to all new Power engine function signatures |
| Rule 10.1/10.3/10.4 | No implicit conversions across the essential type model (signed/unsigned, float/int) without an explicit cast | Audit new Power arithmetic (duty-fraction float vs. raw-position integer math) at each boundary |
| Rule 15.5 | Prefer a single point of exit per function | Apply to all new Power functions |
| Rule 2.7 / 2.8 | No unused parameters or objects without documented justification | Applies to both; keep the existing codebase's practice of commenting non-obvious "unused for now" cases |
| Directive 4.9 | Function-like macros only where a real function cannot achieve the same safety/clarity | Power's `MeasurementDefinition` macro should follow the existing `NL_MEASUREMENT_PROFILE` compile-time guard style, not invent a new macro idiom |

A full MISRA static-analysis pass (e.g. via whatever checker this project's toolchain already
has access to) should run against both new/refactored translation units before they're treated
as done — this table is a design-time checklist, not a substitute for that tooling.

---

## 8. Recommended module layout

```
Core/Src/nl/                    (deferred until after Power exists — see §4.4, §9 decision 4)
    nl_engine.c
    nl_capture.c
    nl_harmonics.c
    nl_log.c
Core/Src/power/
    power_engine.c        (new: PowerEngineState_t state machine, §5.4)
    power_search.c         (new: FR-PWR-1..4 escalation-search algorithm, bounded per §5.3)
    power_log.c            (new: POWER_RESULT formatting, §6 SVC-3)
Core/Inc/nl/nl_engine.h    (public surface: unchanged from current nonlinear_test.h)
Core/Inc/power/power_engine.h  (public surface: §5.4)
```

`power_search.c` must include only `motor_pwm.h` and `ma600_acquisition.h` directly — not
`motor.h` (the facade) and not `position_controller.h` (§5.2, FR-PWR-5; §6, SVC-2). No new
`motor_open_loop.c`-style facade file is required; `motor_pwm.h`/`motor_pwm.c` already provide
everything Power needs, confirmed independent of the PID by direct source read. Resistance-
measurement files are deliberately absent from this layout — out of scope per the stakeholder
decision in this session, and this project has no resistance-sensing hardware to support it
regardless.

---

## 9. Open decisions before implementation starts

1. **Duty ceiling safety bound (§5.3, NFR-PWR-3)**: needs an actual current/thermal limit from
   this project's motor driver hardware, validated against the 6-minute worst-case sustained-run
   scenario (NFR-PWR-1), not Gremsy's PM1505 value carried over blindly.
2. **NL threshold (§2.1 table)**: 1.7–5.0° is reference-only; needs re-validation on this
   project's own 64-sample/1° pipeline against known-good/known-bad reference units before
   being adopted as a spec, per the existing `AGENTS.md` no-threshold rule. Cross-jig
   synchronization (a separate, currently-unmet objective per this session's earlier findings)
   is not required for this threshold work if the project adopts a single golden-jig-for-
   decisions operating model, but any threshold calibrated on one jig must not be silently
   assumed to transfer to another.
3. **Power threshold**: same caveat as NL — Gremsy's 14.0% is reference-only until validated on
   this hardware, and must be expressed in the corrected `MinimumCommandedDutyPermille` terms
   (§5.1), not as a physical power percentage.
4. **Refactor sequencing — reversed from Revision 1**: implement Power first, as its own image,
   using `nonlinear_test.c` exactly as it stands today. Only split `nonlinear_test.c` afterward,
   and only with golden-log numerical equivalence plus a hardware A/B run proving the 360-point
   curve is unchanged — not as a prerequisite for Power to exist.
5. **ADC1 channel wiring** (§5.1): whether `ADC_CHANNEL_1`/`ADC_CHANNEL_4` are in fact connected
   to voltage/current sense points on this board needs a schematic check before any future
   decision to add real electrical-power measurement — not assumed from the channel
   configuration alone.

---

## 10. Audit trail — counter-review of Revision 1

An independent architecture counter-review raised 11 findings against Revision 1. Every code
citation below was independently re-read from this repository (not taken on trust) before a
verdict was recorded.

| # | Finding | Verdict | Basis |
|---|---|---|---|
| 1 | Runtime engine selection inside one image contradicts `app_mode.h`/`app_engine.c`'s compile-time-only precedent | **Accepted** | Read `app_engine.c` directly: `#if JIG_APP_MODE == JIG_APP_CONTROL ... #else ...`, no third branch, no runtime switch. `app_engine.h:10-11` states the invariant explicitly. |
| 2 | `IsBusy()` cross-engine check is a TOCTOU race, needs a supervisor/mutex | **Accepted as a critique of Revision 1's draft; resolved by side-effect of #1, not independently built.** | Once NL and Power are separate images (#1), they never share a binary, so no cross-engine race can occur — no arbitration primitive is needed for this specific pair. |
| 3 | "Power" is PWM duty, not measured electrical power; needs V/I sensing or a rename | **Accepted the naming fix; declined to require V/I sensing as a blocker.** | ADC1 configured but never read anywhere in this project (`grep` returned nothing). Also confirmed Gremsy's own original (`datacty/gremsyMotor.c`, `gremsyTaskManager.c`) never reads ADC/voltage/current either — their shipped "power" was the same duty proxy. Rename is required (§5.1); V/I sensing is a future enhancement beyond Gremsy's own reference bar, not a parity requirement. |
| 4 | Stall detection must distinguish acquisition failure from real stall, and reuse existing acquisition primitives | **Accepted** | Read `ma600_acquisition.c:19-60`: `MA600_AcquireSample()` already implements retry, transport-error flagging, and jump-rejected unwrap — exactly what FR-PWR-2 needed and originally lacked. |
| 5 | Worst-case runtime/memory not proven; ~6 minutes / ~7200 records / ~115 KB | **Accepted, independently re-derived and confirmed matching.** | Re-derived from `gremsyTaskManager.c`'s actual state machine (not just trusted the citation): confirmed `pos` is rewrapped modulo pole-count on every `LOCK` re-entry, so the 1080° counter restarts per duty level — this is what makes the 75-level × 96-step worst case real, not hypothetical. |
| 6 | "No dynamic allocation" claim is inaccurate for CMSIS-RTOS2 object creation | **Accepted, severity reduced.** | Confirmed `osMessageQueueNew(..., NULL)` / `osThreadNew` without static attributes in both `nonlinear_test.c` and `control_engine.c`, and an empty `RTOS_MUTEX` block in `main.c`. The allocation is real but one-time, at `Init()`, outside the measurement loop — a wording fix (§1, §4.2, §7), not a newly discovered measurement-time defect. |
| 7 | Power needs an explicit RTOS execution contract (priority, stack, abort latency, DMA ownership) | **Accepted** | Nothing in Revision 1 specified this; NL's own `Init()` already sets a documented, justified contract that Power must match in kind, not by copying numbers (§5.5). |
| 8 | Power and NL are not thermally independent; running them back-to-back on one unit contaminates results | **Accepted, and independently corroborated.** | This session's own PG07 finding (creep/correction success degrading 14.8%→48.5% across three consecutive sweeps) is direct empirical evidence of exactly this mechanism on this project's own hardware — not cited in Revision 1 despite being available. |
| 9 | Refactoring the qualified `nonlinear_test.c` before Power exists adds unrelated regression risk | **Accepted, recommendation reversed.** | Once #1 is adopted (separate images), Revision 1's original justification for splitting NL first — so Power's and NL's logging code could "coordinate" — no longer applies, since the two are never compiled together. Power does not need the NL split to exist (§4.4, §9 decision 4). |
| 10 | Gremsy's algorithm description was imprecise: first duty is 7.6% not 7.5%, and the rotation counter restarts per duty level | **Accepted, independently re-verified against source.** | Re-read `gremsyTaskManager.c:1147-1216` directly; confirmed both details exactly as described (§2.2). |
| 11 | CV ≤ 2% should not be treated as an architecture gate for jig synchronization | **Partially accepted — scope clarified, requirement not withdrawn.** | NFR-NL-2 was specifically scoped to same-mount, same-jig repeatability, which this session has strong repeated evidence for; it was never intended to claim cross-jig qualification, which this session's own broader findings repeatedly state is unmet. Wording tightened to make that scope explicit (§4.2) rather than removing the requirement. |

### Round 2 (Revision 3)

| # | Finding | Verdict | Basis |
|---|---|---|---|
| 12 | Power cannot actually exclude `position_controller.c` while using `motor.c`'s `Motor_SetElectricalPos` as FR-PWR-5 required | **Diagnosis accepted; proposed fix (new `motor_open_loop.c` facade) replaced with a lighter one.** | Read `motor.c` directly: unconditional `#include "position_controller.h"`, unconditional `PositionController_Init()`/`RunSelfTest()` calls in `Motor_Init()`/`Motor_RunControllerSelfTest()`, and `main.c:154-155` calls both with no mode guard — confirmed, and pre-existing in this codebase already. But `motor_pwm.h`/`motor_pwm.c`, read directly, have zero dependency on `position_controller.h` and already expose the exact primitive needed (`MotorPwm_SetElectricalPos`). FR-PWR-5 revised to require Power use `motor_pwm.h` directly instead of the `motor.c` facade — same isolation guarantee, zero new files (§5.2, §6 SVC-2, §8). |
| 13 | The 360 s worst-case bound omits acquisition/retry time; "hold and retry the read" is currently unbounded | **Accepted in full.** | Confirmed `MA600_DMA_TIMEOUT_US = 10000U` (10 ms) in `ma600.c`. Confirmed this project's own existing precedent for retry count: `MOTOR_PID_READ_ATTEMPTS = 3U`, used twice in `motor.c`. Recomputed: `75 × 96 × (50 ms + 3×10 ms) ≈ 576 s`, matching the reviewer's figure. NFR-PWR-1 rewritten with the complete bound and the previously-missing named constants (§5.3, §7). |
| 14 | Duty-fraction results need an explicit environmental-comparability contract, and "minimum" is actually "first passing level of a discrete ascending search" | **Accepted in full.** | Direct extension of this session's own central finding (measurement-instrument state affects raw readings, established exhaustively for NL) to the newly-designed Power measurand — internally consistent with the rest of this document. §5.1 rewritten with `FirstPassingDutyPermille` semantics and required environmental-contract fields. |
| — | Schema suggestion: add `OfficialOpenLoopNL=0`/`EligibleForNLStatistics=0` to `POWER_RESULT` | **Accepted in intent, refined in implementation.** | `POWER_RESULT` is already a structurally distinct record type from NL's `RESULT` (SVC-3) — no NL parser will ever encounter it. Borrowing NL-specific field names into a different record type is redundant and misleadingly implies Power was considered for and excluded from NL statistics, rather than never being in that category. Power keeps its own independent classification field, `MeasurementClass=ACTUATION_DUTY_MARGIN_V1` (§5.2, FR-PWR-6). |

**Reviewer sign-off (same day):** Revision 3 accepted as architecture-ready for implementation,
conditioned on two closing criteria — both promoted to §11 acceptance criteria below, not left
as informal understanding.

---

## 11. Approval, closing acceptance criteria, and locked implementation order

### 11.1 Closing acceptance criteria (attached at sign-off, must be satisfied by §11.2 step 6)

- AC-1: A build/link-time contract test proving the `JIG_APP_MEASUREMENT_POWER` image's linker
  map contains **zero** `PositionController_*` symbols (already required at FR-PWR-5; restated
  here as a formal acceptance gate, not an aspiration).
- AC-2: A contract test proving `POWER_RESULT` records are unreachable by every existing NL log
  analyzer (Python/PowerShell/MATLAB) through strict record-type allowlisting — i.e. each
  analyzer only ever parses lines matching its own expected record type(s) and demonstrably
  ignores or rejects `POWER_RESULT` lines, so Power data can never silently enter an NL
  statistics computation. This supersedes any per-field isolation mechanism (§10 round 2,
  schema suggestion) — isolation is enforced by parser discipline plus record-type naming, not
  by borrowed NL fields on the Power record.

### 11.2 Implementation order (locked)

1. Add `JIG_APP_MEASUREMENT_POWER` to `app_mode.h`, wire the third `#elif` branch in
   `app_engine.c` (§3.1).
2. Extend the build tooling from dual-image to three-image (whatever currently builds
   `JIG_APP_CONTROL`/`JIG_APP_MEASUREMENT` must gain a third target).
3. Implement the Power engine depending only on `motor_pwm.h` and `ma600_acquisition.h` (§5.2
   FR-PWR-5, §6 SVC-2, §8) — no dependency on `motor.h` or `position_controller.h`.
4. Lock every retry/stall/acquisition bound as named compile-time constants
   (`PWR_MAX_DUTY_LEVELS`, `PWR_MAX_STEPS_PER_LEVEL`, `PWR_MAX_ACQUIRE_ATTEMPTS`,
   `PWR_MAX_INVALID_READS_PER_STEP`, `PWR_STALL_CONFIRM_COUNT`) and a global watchdog/timeout
   set **at or above the ~576 s derived worst case** (§5.3 NFR-PWR-1) — not the earlier,
   incomplete 360 s figure.
5. Add the `POWER_RESULT` record type with its own contract/version identity
   (`MeasurementDefinition=ACTUATION_DUTY_MARGIN_V1`, `MeasurementClass=ACTUATION_DUTY_MARGIN_V1`,
   `FirstPassingDutyPermille`, `SearchResolutionPermille`, `SearchDirection`, `MotionDirection`,
   plus the environmental-contract fields from §5.1) — distinct from and never mixed into NL's
   `RESULT` schema.
6. Contract tests (bound constants + timeout, per step 4), parser-isolation test (AC-2), and
   linker-map test (AC-1).
7. Build/package the Power artifact, then run the first hardware pilot — on the Power image
   only. The official NL image and `nonlinear_test.c` are not touched at any point in this
   sequence (§4.4, §9 decision 4).
