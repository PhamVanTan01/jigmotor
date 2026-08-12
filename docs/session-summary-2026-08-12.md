# Session summary — 2026-08-12

## V5.9 EXTENDED terminal correction — implementation complete, V5.9a pilot packaged

Continuation of `docs/sweep-point-terminal-correction-v5-9-plan.md`. Firmware (S0-S2),
tooling (S3), and regression/packaging (S4) are all done. Nothing has been run on real
hardware yet — this is the software-side close-out; the A/B pilot on P08/JIG8 is the next
physical step.

### S2 — firmware (`Core/Src/nonlinear_test.c`)

- `ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION` (default 0), with `#error`
  guards requiring V5.4+V5.5 and excluding V5.6/V5.7/V5.4a.
- EXTENDED points that are still outside deadband after the validated 320-raw primary cap
  get a bounded 80-raw terminal allowance (400-raw hard cap), same 4-raw fine step,
  101-iteration guard. BASE points never receive this extension.
- Per-sweep guard: max 10 terminal points / 800 raw total, checked against prior-points-only
  counts (cannot look ahead to a not-yet-run point).
- `TerminalObservedTowardTargetRaw` is a signed subtraction
  (`(int64_t)AbsI64ToU64(entryGap) - (int64_t)AbsI64ToU64(finalGap)`), so a point that ends up
  farther from target after terminal correction reports negative, not an unsigned wraparound.
  `TerminalResponseEfficiencyPermille` defaults to `"NA"`, only computed when
  `terminalAttempted && terminalCorrectionRaw > 0`, and keeps negative values (not clamped).
- `terminalSucceeded` requires strictly `NL_CREEP_OK` (not `OK_RECOVERED`) — a crossing/
  recovery during terminal is a mechanism failure per the locked plan even if the point lands
  inside deadband afterward.
- Shared V5.4 trace buffer widened 100→120 entries only when V5.9 is on (real RAM-safety
  fix, caught before it reached hardware — the buffer must hold 101 ordinary + 17 recovery
  iterations).
- `SWEEP_CREEP_CONFIG`/`POINT` bumped to schema 10; `END` gets 8 new `SweepPointTerminal*`
  aggregate fields.
- Compile-verified: V5.4+V5.5+V5.9 (Debug, text=152660) and the full V5.9a combo
  V5.4+V5.5+V5.8+V5.9 (Debug, text=157188; CCM 0xD088 used, 12,152 bytes / ~11.9KB headroom,
  above the required ≥8KB gate). Default all-off baseline reconfirmed byte-for-byte after
  every flip: `text=139444, data=96, bss=140792`.

### S3 — analysis tooling

- Python (`auto_log_analysis.py`, `motor_quality_polar.py`, `analyze_motor_logs.py`):
  fully generic key=value parsing with no `SchemaVersion` gating — confirmed already
  forward-compatible with schema 10, no changes needed. 11/11 existing unit tests still pass.
- MATLAB `analysis/matlab/nl/parse_sweep_creep_log.m`: added the 6 new CONFIG fields, 10 new
  POINT fields, 8 new summary fields to its fixed field-name lists (this parser is
  schema-tolerant via `isfield()` but schema-EXPLICIT — new fields are silently dropped
  unless added to these lists).
- `analysis/matlab/nl/analyze_sweep_creep_batch.m`: new `build_terminal_by_label()` /
  `TerminalByLabel` output. Deliberately keeps `Primary320OnlySuccessRatePct` (points that
  reached deadband within the 320-raw primary cap alone) and `Terminal400SuccessRatePct`
  (points that needed and succeeded at the 400-raw terminal) as two separate columns, per
  the plan's explicit "không được gộp thành một tỷ lệ mơ hồ" requirement.
- New regression test `test_sweep_point_creep_v5_9_terminal()`, nested inside
  `analysis/matlab/tests/test_nl_stability_analysis.m` (matching this repo's existing
  convention — every prior V5.x MATLAB test lives there, not in a standalone file). Five
  synthetic POINT rows cover: BASE (never terminal-eligible), EXTENDED-succeeds-at-320-alone,
  terminal-attempted-success, terminal-attempted-**failure with negative efficiency** (the
  core signed-arithmetic property), and guard-suppressed. Can't execute MATLAB in this
  environment (not installed) — verified by hand-tracing the arithmetic and via the
  contract script's static source checks.

### S4 — regression + packaging

- New `scripts/test_sweep_point_creep_v5_9_contract.ps1`, following the existing
  static-source-regex contract-script pattern (v5.3 through v5.8). Passes both flag-off
  (default) and `-FeatureBuild` (flag-on) states.
- Running it exposed that `test_sweep_point_creep_v5_3_contract.ps1` and
  `..._v5_4_contract.ps1` had gone stale: `CreepToUnwrappedTargetProfiled()` gained an
  unconditional trailing `terminal` parameter for V5.9, so every call site's exact text
  changed (a `NULL` now follows `&fineLandingConfig` everywhere). Not a functional
  regression — fixed both scripts' regexes to tolerate the new trailing argument. Full
  suite now 8/8 green (V5.3 through V5.9).
- Python: 11/11 (`test_auto_log_analysis.py` 8, `test_analyze_creep_difficulty_spatial.py` 3).
- Packaged `builds/sweep-point-terminal-correction-v5-9a-fast3-20260812/` (Release,
  V5.4+V5.5+V5.8+V5.9 ON, FAST3 3-run mode) per plan section 12.1 — V5.8 timing stays ON in
  the V5.9a pilot artifact by design (causal motion/timing evidence, not for product NL).
  text=94316, data=96, bss=181248; CCM 0xD088 used, ~11.9KB headroom. Source flags restored
  to all-off afterward; Debug baseline reconfirmed byte-for-byte identical.

### Next physical step

V5.9a is not official (`EligibleForStatistics=0` on every run). Per plan section 12.1: flash
A = V5.5 baseline, run FAST3 on P08/JIG8 (mount prerequisite: `H2AmplitudeDeg <= 0.020°`,
`RobustP2PDeg <= 0.30°`, pilot-filter only, not general), then flash B = this V5.9a build, run
FAST3 on the **same** mount (no remount between legs), then repeat on an independent remount,
then P09 non-regression + P03 generalization (≥90% terminal success, ≤1 failure) before
considering V5.9b promotion.

## V5.9a hardware validation — sections 16.1–16.4 complete, 5 mounts, 3 products

All four hardware-validation legs from `docs/sweep-point-terminal-correction-v5-9-plan.md`
section 16 are now run. Logs in `captured-logs/v5.9/`. Verified every claim against raw
`SWEEP_CREEP_CONFIG`/`POINT`/`END` telemetry and the analyzer's harmonic decomposition
(`analysis.json`), not filenames — one derived analysis file (`P08-JIG8-remount01-test-1-v5-8.
analysis.txt`) had a stale `Source=` path pointing at the wrong raw log; the raw `.txt` logs
themselves were correctly labeled (confirmed via `SchemaVersion`/`Protocol` in `CONFIG`). One
file (`P08-JIG8-remount01-test-1-v5-9-16.2.*`) was renamed to `P08-JIG8-remount03-test-1-v5-9.*`
after confirming with the operator it was a genuine physical remount, not a same-mount rerun —
corroborated by the mount-quality fingerprint (H2 0.0099° vs 0.0125°, H18 differs ~7x).

### 16.1 — P08/JIG8, same mount, A(v5.8 cap320)/B(v5.9a cap400), remount01

| | A (v5.8, cap 320) | B (v5.9a, cap 400) |
|---|---|---|
| Reached deadband | 1462/1480 (98.78%) | **1480/1480 (100%)** |
| Stuck at BUDGET_EXCEEDED | 18 (points 147/148/149/157/158/188) | 0 |
| Terminal attempted/succeeded | — | 10/10 |
| Guard triggered | — | never |
| Crossing/jump/recovery-fail | 0/0/0 | 0/0/0 |

Every terminal-succeeded point landed `FinalGapRaw` in [-11,-16] (inside the ±16 deadband).
Point 148 was the recurring hard case (terminal-attempted in all 4 cycles, entry gap up to
-53 raw), resolved every time. remount02 (v5-8 rerun only, operator-confirmed same-A-baseline-
twice, not part of the A/B evidence) showed 6 stuck points that time — normal run-to-run
variance on the 320 baseline.

### 16.2 — Independent remount, P08/JIG8 (remount03)

Mount fingerprint confirmed distinct from remount01 (H2 0.0125° vs 0.0099°, both well inside
the `≤0.020°` pilot filter; RobustP2P 0.219° vs 0.217°). ReachedDeadband 1478/1480 (99.86%).
9 terminal attempts, **9/9 succeeded**, 0 failed/suppressed, guard never triggered. Zero
crossing/recovery/jump. Two BUDGET_EXCEEDED misses (T7/Point149, T8/Point158) — both
`BudgetClass=BASE`, `TerminalEligible=0`: the ADAPTIVE BASE/EXTENDED classifier (unchanged
from V5.5, live-gap-threshold based) put known-hard points in the BASE tier on those two
cycles, so terminal correction was never offered. Not a terminal-mechanism failure — a
pre-existing V5.5 classification-boundary effect, first surfaced here because it's now the
only remaining failure mode.

### 16.3 — P09/JIG8 non-regression (remount03)

Clean: ReachedDeadband 1480/1480 (100%), `BudgetExceeded=0` every cycle, 12 terminal attempts,
**12/12 succeeded**, zero crossing/recovery/jump, guard never triggered. No same-mount V5.8
baseline existed for this specific remount to diff point-by-point (the only historical P09 log
is a different mount, confirmed by H2 mismatch: 0.0102° vs 0.0012°, phase 146° vs -158°) — but
non-regression holds by construction: zero failures means no failure population could have
regressed, and terminal correction only ever engages after a point completes the byte-identical
unchanged V5.5 motion out to the 320-raw cap.

### 16.4 — P03/JIG8 generalization (remount01 + remount02, two independent mounts)

Numeric gate (terminal success ≥90%, ≤1 400-raw failure) clears on both mounts: 11/11 then
7/7 terminal attempts succeeded (18/18 combined), 0 terminal failures either mount.

But P03 surfaces a real, **reproduced-on-two-independent-mounts** finding, distinct from the
terminal mechanism itself:

- Points **108, 147, 187/188, 348** hit `BUDGET_EXCEEDED` in **3/3 OFFICIAL cycles on both
  mounts** (187↔188 is a one-index shift between mounts, consistent with the same physical
  angle landing on a neighboring point index due to different sweep start angles — same
  underlying region, not two problems). All `BudgetClass=BASE`, `TerminalEligible=0` — same
  classifier-boundary effect as 16.2's P08 remount03, but systematic here rather than
  occasional.
- Target crossing (`SweepPointCreepTargetCrossed=1`, `RecoverySucceeded=1`) occurred in
  **3 of 6 official cycles** across the two mounts (T15 on remount01; T18 and T20 on
  remount02) — all on `BudgetClass=BASE` points, i.e. pre-existing V5.5 motion behavior V5.9
  never touches. This is not a fluke; it reproduced and got more frequent on the second mount.

Mount fingerprints confirm both P03 mounts are genuinely distinct and not obviously
eccentric/bad (RobustP2P 0.268°/0.220°, H2 0.0066°/0.0113°, both within the range seen on
clean P08/P09 mounts) — this looks like product-level (P03-specific) behavior, not mount noise.

### Combined terminal-mechanism total across all 5 mounts, 3 products

**49/49 terminal attempts succeeded, 0 failed, 0 suppressed, guard never triggered.**
`TerminalObservedTowardTargetRaw`/`TerminalResponseEfficiencyPermille` signed-arithmetic
behaved correctly on real hardware (values observed in [-16,1500]‰ range, matching the design).

### Decision

Two separate conclusions, not one:

1. **V5.9 terminal correction is validated** — recommend promoting to V5.9b (plan section
   12.2: terminal ON, V5.8 timing diagnostic OFF or a separate A/B, source defaults restored
   after packaging). Not yet packaged this session.
2. **P03's BASE-classifier gap + crossing frequency is separate, pre-existing, and out of
   V5.9's scope** (V5.9's own non-goals explicitly exclude MID/PID/current-loop/classifier
   changes). Per plan section 18 ("crossing/jump xuất hiện... lặp lại trên mount hợp lệ"),
   this is exactly the trigger condition for opening V6.0 evidence — logged, not chased with
   a cap increase.

The V5.9a→V5.9b promotion call and the V6.0-scoping response are the project owner's decision,
not made unilaterally here — this section records the evidence both decisions would rest on.

## V6.0 scoping note — this is NOT a new architecture proposal

Important finding before any V6.0 planning: **a detailed closed-loop-control implementation
plan already exists and is actively in progress**, most likely by a parallel session on this
same branch (`codex/motion-control-v2-dma`):

- `docs/stm32f405-dual-mode-implementation-plan.md` — the actual "V6.0" architecture. Phases
  P0 (baseline freeze) and P1 (build identity/compile-time isolation) are complete. Phase C0
  (Control image open-loop plant characterization) is complete at the source/build-gate level,
  but its first hardware gate found HOME_WRONG_WAY (5/10 runs) and HOME_TIMEOUT (5/10 runs)
  failures — visible jerk/vibration during the enable sequence, before the 1° trajectory ever
  ran. Phase C1 (hardware-timed 1kHz control pipeline, TIM5-based) and C2 (P-only controller)
  — the phases that would actually let a closed-loop controller address points like P03's
  108/147/187/348 or eliminate BASE-motion crossing — are **explicitly blocked** until this is
  fixed.
- `docs/control-c0-alignment-enable-fix-plan.md` — the active fix plan for that hardware gate.
  Status line: *"A1 và firmware A2 alignment-only đã được triển khai dưới profile
  `CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1`; hardware gate A2 vẫn đang chờ."* Root-cause hypothesis:
  enabling the driver directly at 35% power from an arbitrary electrical phase creates a
  phase/power discontinuity that yanks the rotor to the nearest equilibrium. Plan runs A0→A5
  (freeze baseline → separate reset/prime → fixed-phase alignment-only → encoder/phase offset
  calibration → alignment+home → restore C0's 1° open-loop), each gated on 10/10 hardware runs
  with no visible jerk, before C0's 1° trajectory can even be considered validated again — let
  alone C1/C2.

**Implication**: writing a new V6.0 architecture doc here would duplicate or conflict with this
in-progress work. What this session's V5.9a pilot contributes to V6.0 is evidence, not
architecture:

- The P03 108/147/187/348 BASE-classifier-gap + repeated-crossing finding (see previous
  section) is now the concrete, hardware-confirmed motivating case for why C1/C2 eventually
  matters — a live command-tracking loop with real feedback correction is the only way to fix
  a classifier-boundary/crossing problem that V5.9's bounded terminal-correction patch
  structurally cannot reach (V5.9's own explicit non-goals rule out MID/PID/current-loop/
  classifier changes).
- This evidence is **queued, not actionable yet** — C1/C2 cannot start until the A2+ alignment
  gate passes on real hardware, which is a separate, already-active track.
- Action taken here: none to the alignment/C0/C1/C2 plans themselves. This note exists so the
  P03 finding isn't lost, and so a future session doesn't propose a redundant V6.0 architecture
  without first checking these two docs' current status.

## Open-loop NL direction correction — RULE 0 locked, S0-S4 executed, first clean hardware pilot

The V6.0-scoping note above turned out to be premature in one specific way: while investigating
what "V6.0" should mean, a much more fundamental problem surfaced — the project's actual NL
measurement (V5.1-V5.9, including this session's own V5.9a pilot) had drifted from **open-loop**
NL (Gremsy-comparable: fixed command, observe where the rotor naturally settles) into
**closed-loop position-response** measurement (creep/recovery/terminal correction use the same
MA600 encoder to correct the command *before* the point is captured). This is a measurand change,
not a bug — but it means none of this session's V5.9a NL numbers (including the 49/49
terminal-correction pilot) represent true open-loop NL.

### Root-cause audit (ALG-001/004/005 re-examined against current code)

- **ALG-005** ("ramp has no feedback") — interpretation corrected, not a defect.
  `RampCommandToTarget()` reads MA600 every micro-step for observability/backtrack-detection only;
  the sample never feeds back into the command. Still genuinely open-loop.
- **ALG-001** (dual-read: `Error` from a 64-sample mean, `DATA.AngleRaw`/extrema from a separate
  65th SPI transaction) — **fixed**: `CaptureSweep()` now derives both from one canonical
  `meanUnwrappedRaw` accumulated in the same 64-sample loop (round-to-nearest-away-from-zero,
  modulo 65536), removing the extra transaction entirely. Verified by compile (both profiles) and
  a negative test (deliberately broke the line, confirmed the new contract script catches it).
- **ALG-004** (`OfficialResultSource=LEGACY` hardcoded, canonical Q16 only a parallel "shadow"
  capture) — confirmed real, deliberately **not** patched by just flipping a string (the plan's own
  rule 14 forbids "promoting" schema v6 that way). Left as the correctly-scoped S2/S3 work.
- **The real scope-drift cause**: `CreepToUnwrappedTargetProfiled()` and all recovery/terminal
  correction — genuine closed-loop feedback actuation, not observation.

### RULE 0 locked (`AGENTS.md` + `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md`)

The repository's primary and authoritative objective is now formally `GREMSY_COMPAT_OPEN_LOOP_NL_V1`.
Feedback actuation (creep, recovery, terminal correction, encoder-derived feedforward) is
permanently barred from the official measurement path; any such experiment must run under a
separate `POSITION_RESPONSE_DIAGNOSTIC_V5X` profile with `EligibleForStatistics=0`.

### S0/S1 implemented and verified this session

- `NL_MEASUREMENT_PROFILE` (`NL_PROFILE_GREMSY_OPEN_LOOP` default) with a compile-time `#error`
  guard rejecting any feedback-actuation flag under the open-loop profile.
- `eligibleForStatistics` rewritten to be profile-gated instead of a flag-by-flag exclusion list
  (the old form is exactly how a V5.9-era flag could have silently leaked into official statistics
  — confirmed the gap existed, fixed it).
- New `MeasurementProfile`/`OfficialOpenLoopNL`/`RampEncoderObservationEnabled`/
  `RampFeedbackActuationEnabled` telemetry; retired the misleading `RampFeedbackEnabled=1`.
- New `scripts/test_open_loop_nl_profile_isolation_contract.ps1`, negative-tested.

### Independent review caught two real gaps, both fixed

1. `ENABLE_B0B_APPROACH_FEEDFORWARD` was missing from the `#error` guard, and the guard itself was
   placed *before* that flag's `#define` in the file (undefined-in-`#if` silently reads as 0, so it
   compiled fine today but would have stopped protecting if the flag order ever changed). Its own
   protocol ID, `CREEP_DERIVED_BIAS_V2`, confirms the bias constant it applies was learned from
   prior encoder-response data — exactly RULE 0's forbidden category even though the mechanism
   itself never reads MA600 while running. Guard relocated after the flag's definition, flag added,
   verified firing correctly.
2. The project's headline number since before schema v2 ("Nonlinear Final Average") used
   `RobustP2P`, not `RawP2P` — RULE 0 requires `RawP2P` (`max(Error)-min(Error)`) as the primary
   metric. Flagged as a measurement-definition decision too large to make unilaterally; the schema
   v6 doc and firmware built afterward (by a parallel process this same day) resolved it: RawP2P is
   now `OpenLoopNL_Deg`, reported alongside `RobustP2P_Deg` as a labeled supporting metric.

### S2/S3 rebuilt, S4 hardware pilot run — first real open-loop schema-v6 data

Since the review above, the firmware was rebuilt through S2 (single canonical Q16 sampler,
`CaptureCanonicalPointFromSweepContext()`, no legacy/shadow split for the official path) and S3
(genuine `GREMSY_COMPAT_OPEN_LOOP_NL_V1` capture path: `SettleContract=STABILITY_ONLY_CAPTURE_V1`,
`SettleTargetRequired=0` — target proximity stays a logged diagnostic/guard, never a correction
trigger). `docs/nonlinear-log-schema-v6.md` is now an implemented contract, not a draft.

Two hardware pilots followed, both `P03/JIG8/remount01`:

- **run01**: `CAPTURE INVALID`, `OfficialValid=0/10` — a capture-tooling failure, not a firmware
  measurement problem (`captured-logs/v5.9/S4-P03-JIG8-remount01-openloop-v1-run01.*`).
- **run02**: **clean pass** (`tools/dist/captured-logs/S4-P03-JIG8-remount01-openloop-v1-run02.*`).
  `AutoVerdict=PASS`, `OfficialValid=10/10`, zero SPI/transport/jump/failed-sample errors across all
  11 sweeps, zero creep activity (`SweepPointCreep*=0` throughout, confirming genuinely open-loop),
  every point's canonical window had its full 64/64 accepted samples
  (`AcceptedSampleCount=23808 / CapturedPoints=372 = 64.0` exactly).

  | Metric | Mean | SD | CV |
  |---|---:|---:|---:|
  | `RawP2P` / `OpenLoopNL_Deg` (primary) | 2.8611° | 0.0350° | 1.22% |
  | `RobustP2P_Deg` (supporting) | 2.7388° | 0.0239° | 0.87% |
  | `A36` (6-pole-pair harmonic signature) | 0.8976° | 0.0010° | 0.11% |
  | Closure | -0.0366° | 0.0158° | (well inside the 0.20° limit, `ClosureValid=1` every sweep) |

  `A36`'s 0.11% CV is the strongest evidence this is real physical signal, not acquisition noise —
  matches the 6-pole-pair (12-pole) harmonic family identified early in this whole project.

### Status and next step

This run02 result is the first hardware evidence toward unblocking the schema-v6 promotion the
doc's own header names as pending ("hardware promotion remains blocked on S4/S5 verification and
pilot evidence"). Per the plan's own S5 order: repeat on an independent remount next, then A/B/A
against the legacy/diagnostic build on the same mount to rule out session drift, before extending
to P08/P09.

## MATLAB tooling catch-up for schema v6 + independent polar-chart cross-check

Pulled the above into a fresh session (branch `codex/motion-control-v2-dma`), read RULE 0 and the
run02 result, then closed a real gap: `parse_nl_log.m` (schema v4/v5) cannot read schema v6 at all
-- its DATA parser requires exactly 12 comma fields and schema v6 DATA lines have 15 (12 legacy
positional + 3 appended `CommandRawQ16`/`MeanUnwrappedRawQ16`/`ErrorRawQ16` key=value fields), so
every DATA line would have been silently skipped, and RESULT's field set changed completely
(`OpenLoopNL_Deg` as primary, full A1..A108/H*_PhaseSweepDeg harmonic set, tracking/model fields).

### New tools (commit `9f95ac7`, already pushed)

- `analysis/matlab/nl/parse_openloop_nl_log.m` -- dedicated schema-v6 parser, deliberately
  separate from `parse_nl_log.m` per the schema doc's own rule ("a parser must never infer v6
  semantics from a v5 record"). Recomputes `ErrorDeg` from `ErrorRawQ16` for schema>=6
  (`error_deg = ErrorRawQ16 * 360 / (65536 * 65536)`, matching `analyze_motor_logs.py` exactly)
  rather than trusting the legacy positional field. Exposes `IsOpenLoopOfficial` per sweep: the
  full RULE-0 gate (`MeasurementProfile=GREMSY_COMPAT_OPEN_LOOP_NL_V1` AND `OfficialOpenLoopNL=1`
  AND `FeedbackActuationEnabled=0` AND `RunRole=OFFICIAL` AND `EligibleForStatistics=1`).
- `analysis/matlab/nl/analyze_openloop_nl_batch.m` -- pools multiple v6 files behind that gate,
  prints every exclusion reason instead of dropping silently, and additionally asserts open-loop
  *purity* per included sweep (`SweepPointCreepIntegrityValid=1`, every `SweepPointCreep*` counter
  zero) -- refuses a sweep that claims open-loop but shows any leaked feedback-actuation evidence.
- Verified against the real newest S4 log
  (`tools/dist/captured-logs/S4-P03-JIG8-remount01-openloop-v1-run02.txt`): reproduces this doc's
  own numbers above exactly (`OpenLoopNL_Deg` mean 2.8611°/SD 0.0350°/CV 1.22%, `A36` 0.8976°/CV
  0.11%). Paired run01 (`CAPTURE INVALID`) correctly yields zero included sweeps.
- New `test_openloop_nl_batch()` in `test_nl_stability_analysis.m`, three synthetic sweeps
  covering PRECONDITION exclusion, clean inclusion, and purity-violation exclusion. Full 5-suite
  MATLAB regression (`test_a2_analysis`, `test_a3_a4_a5_analysis`, `test_b0b_analysis`,
  `test_nl_stability_analysis`, `test_health_analysis`) still green.

### Polar chart, independent MATLAB implementation vs the existing Python one

`tools/motor_quality_polar.py` (updated by a parallel session, forward-compatible with schema v6)
had already auto-generated `S4-P03-JIG8-remount01-openloop-v1-run02.polar.png` at capture time --
single error-curve panel only, correctly no gap/timing panels since a genuine open-loop log has
zero `SWEEP_CREEP_POINT`/`SWEEP_POINT_TIMING` records by construction.

Built `analysis/matlab/nl/plot_openloop_nl_polar.m` as an independent MATLAB cross-check (separate
codebase, same authoritative `ErrorRawQ16` source): averages `IsOpenLoopOfficial` sweeps per
label, circular-smooths + offsets the curve for the polar plot, marks the order-2 (motor-locked
eccentricity/tilt) peak angles. Result on the same file: **motor-locked angles 276°/96° -- exact
match with the Python chart's own computed value**, and visually identical curve shape (two large
lobes around 240-315°). Two independently-written implementations agreeing on both the angle and
the shape is a real correctness cross-check for both tools, not just a duplicate chart.

### Attempted (and correctly abandoned) cross-reference to closed-loop response data

Asked whether this open-loop chart also identifies "low response capability" angle ranges. Tried
to check by comparing the open-loop run02 H2 fingerprint against the nearest closed-loop V5.9 data
on the same jig (`captured-logs/v5.9/P03-JIG8-remount01-test-1-v5-9-16.4.txt` and
`...-remount02-test-1-v5-9-16-4.txt`, same `MCU_UID` = same JIG8 unit):

| Source | H2 amplitude | H2 phase |
|---|---:|---|
| Open-loop run02 | 0.163° | -168.3° |
| V5.9 closed-loop remount01 | 0.011° | -179.9° |
| V5.9 closed-loop remount02 | 0.010° | +177.7° |

The comparison is **not methodologically valid**: closed-loop H2 is ~16x smaller purely because
creep/terminal correction actively closes the gap before capture, not because the mount is
better -- open-loop and closed-loop magnitudes are not comparable on the same scale (this is
exactly the measurand-drift problem RULE 0 was written to prevent). Also, matching `MCU_UID` only
proves same jig, not same physical motor mount/clocking as this specific open-loop run; the
closed-loop H2 amplitudes here are small enough to be noise-floor, so their phase is not a
reliable mount fingerprint either (same caveat established earlier for P09's low-H2 remounts).
**Conclusion given to the user**: this open-loop chart characterizes where the motor's own NL
concentrates (static/mechanical), not response capability (a closed-loop/dynamic property);
answering "which angle range responds poorly" requires a diagnostic closed-loop run on the *same*
physical mount as an open-loop run, which does not exist yet as a matched pair.

### Answered: does a different jig always produce a "bad" angle range somewhere?

Yes, expected by construction, not by new evidence: the order-2 motor-locked defect rotates with
the rotor (remount-phase-lock evidence from 2026-08-10) so its absolute angle shifts with each
remount/jig (no locating pin fixes clocking); jig-locked friction/hard-points (P09's 3-remount
common-point fingerprint, also 2026-08-10) are fixed for a given physical jig unit but differ
between jig units. Since both real motors and real jigs always carry some asymmetry, a perfectly
flat E(theta) is not realistic on any hardware -- some angular non-uniformity is expected on every
jig, just at a different location each time. This does not by itself mean "defective": no
calibrated pass/fail threshold exists yet to separate normal angular variation from a real
problem (same open gap noted throughout this project's H2 investigation).
