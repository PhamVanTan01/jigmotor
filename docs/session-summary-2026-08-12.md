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

## AGENTS.md RULE 0 extended: two objectives, explicit no-threshold rule

Added to `AGENTS.md` (not yet committed as of this section): the project's authoritative
objectives are now stated as two, in order -- (1) pure open-loop NL, (2) **synchronize NL
measurement across jigs** (the original JIG1-vs-JIG4 governing question; not satisfied just
because open-loop works on one jig). Also added an explicit rule: **no product pass/fail NL
threshold has been calculated or calibrated** -- do not assert, imply, hardcode, or promote any
NL value as a spec limit/acceptance criterion; angular non-uniformity is expected on every real
jig/motor and is not by itself evidence of a threshold. Mirrored as an update note in the
handoff doc's section 2.

## S5.1 (A/B/A, same mount, no remount) — legacy vs open-loop, P03/JIG8/remount01

Corrected the plan order from an earlier turn: S5's actual written order is A/B/A **first**, then
remount, then cross-jig -- not remount before A/B/A as stated earlier in this doc.

Built the "legacy" comparator via an isolated `git worktree` at commit `11b0c0c` (the exact HEAD
before today's RULE 0/ALG-001/S0-S3 work), Release config, compiled clean
(`text=85028`, same 2 pre-existing warnings). Packaged as
`builds/gremsy-legacy-baseline-11b0c0c-aba-pilot-20260812/`. Confirmed via direct source
inspection this build predates every fix made today: `SchemaVersion=5`,
`MeasurementDefinition=WHOLE_SYSTEM_COMMAND_TRACKING` (the retired name),
`RampFeedbackEnabled=1`, `OfficialResultSource=LEGACY` hardcoded, ALG-001's dual-read still
present.

Flashed on the same P03/JIG8/remount01 mount as run02 (not disturbed), captured
`S4-P03-JIG8-remount01-openloop-v1-run01-flags-off.txt`. Confirmed same physical setup:
identical `MCU_UID`, `StartRaw` within 11217-11222 across all four META reads (legacy
precondition/legacy-run and open-loop precondition/run02), zero acquisition errors either side.

### Scalar comparison

| Metric | Legacy (flags-off) | Open-loop (run02) | Delta |
|---|---:|---:|---:|
| RawP2P mean / SD / CV | 2.9677° / 0.0816° / 2.75% | 2.8611° / 0.0350° / 1.22% | -3.6%, SD >2x tighter |
| RobustP2P mean | 2.7880° | 2.7388° | -1.8% |
| A1 / A2 / A9 / A36 | 0.2173 / 0.1668 / 0.1732 / 0.9045 | 0.2110 / 0.1633 / 0.1741 / 0.8976 | -2.9% / -2.1% / +0.5% / -0.8% |
| Closure mean | -0.0368° | -0.0366° | ~identical |

Initial write-up in `build_info.txt` predicted the ALG-001 fix would explain the scalar gap --
**that prediction was wrong and corrected in this session**: ALG-001 only ever affected
`DATA.AngleRaw`/extrema *location* metadata (the stray 65th SPI transaction), never
`error`/`errorSamples[]` itself, which both the pre- and post-fix code compute identically from
the 64-sample mean. So ALG-001 cannot be the mechanism behind a `RawP2P`/`RobustP2P`/`A36` scalar
difference.

### Direct 360-point curve correlation (this turn's actual diagnostic)

Wrote a standalone script (`scratchpad/curve_correlation.py`) parsing `DATA` records directly
from both raw logs (schema-aware: recomputes `ErrorDeg` from `ErrorRawQ16` for the schema-6 file,
matching `parse_openloop_nl_log.m`'s convention; uses the legacy `ErrorDeg` field as-is for the
schema-5 file), averaging the 10 official sweeps into one 360-point curve per file, then
comparing:

- **Pearson r = 0.9993 at zero shift** (searched shifts -10..+10, zero remained best) --
  essentially the same physical curve, no clocking/sector offset, consistent with "not
  remounted."
- **RMSE after mean-centering = 0.027°** -- tiny relative to the curve's ~2.9° peak-to-peak span.
- **Top-5 (max-error) indices: 5/5 identical** between legacy and open-loop (244, 254, 274, 294,
  334). **Bottom-5 (min-error): 4/5 identical** (106, 107, 346, 347 common; legacy's 5th is 187,
  open-loop's is 27 -- both near the tightly-clustered bottom of the curve).
- Per-point delta (open-loop minus legacy): mean ~ -0.0006° (no systematic DC shift across the
  curve), SD 0.027°.

**Reconciles the scalar gap**: `RawP2P` is a 2-point (max/min) statistic, inherently higher-
variance than a full-curve correlation or a K-point-averaged statistic like `RobustP2P` --
exactly why `RawP2P`'s relative gap (3.6%) was larger than `RobustP2P`'s (1.8%) even though the
underlying curves are near-identical. The two extreme points shrank slightly in both directions
under open-loop (max 1.818°->1.779°, min -1.141°->-1.071°), consistent with (not proof of) the
canonical-vs-legacy acquisition-window-timing hypothesis noted earlier, but the dominant, robust
finding is that this is the same physical defect curve, not a different one.

**S5.1 verdict: PASS.** Same physical curve (r=0.9993), scalar differences fall within known
single-point-statistic noise, not evidence of a broken pipeline. Proceeding to S5.2 (remount with
controlled torque).

## S5.2 (remount, controlled torque) — P03/JIG8/remount02, PASS

Same open-loop build as S5.1's "B" leg (`BuildID=Aug 12 2026 16:45:25`, unchanged, isolating
remount as the only variable). Log: `S4-P03-JIG8-remount02-openloop-v1-run01.txt`.

Physical-remount evidence checked directly (not trusted from filename, per this project's
standing verification discipline): `MCU_UID` matches (same JIG8), `StartRaw` shifted 11218/11219
-> 11410/11410 (~192 raw, clearly larger than the 1-5 raw same-mount noise seen elsewhere this
session), mount fingerprint moved (`RobustP2P` 2.703 deg -> 2.802 deg, `H2` amplitude 0.163 ->
0.157 deg, phase -167.5 -> -171.4 deg). `OfficialValid=10/10`, `AutoVerdict=PASS`,
`CaptureIntegrityValid=1`.

360-point curve correlation (remount01/run02 vs remount02/run01, same script as S5.1, first
attempt had a sed-substitution bug that pointed both variables at the same file -- caught via the
suspicious r=1.0000 exact match, fixed, rerun):

- **r = 0.9993 at zero shift** -- identical to the S5.1 same-mount value; remounting did not
  measurably reduce curve correlation for this unit.
- RMSE after centering = 0.026 deg, same order as S5.1.
- Bottom-5 (min-error) indices: **5/5 identical** across the remount (27, 106, 107, 346, 347).
  Top-5 (max-error): 4/5 identical (244, 254, 294, 334 common; 274 vs 253 differ by one nearby
  index).
- Notable: the single largest per-point delta in *both* independent comparisons (S5.1's
  same-mount A/B/A and this remount comparison) lands at the same index, 56 (-0.130 deg in S5.1,
  +0.117 deg here) -- flagged as a location to keep watching, not yet interpreted as a defect.

**S5.2 verdict: PASS**, stronger than expected -- the physical NL curve for this P03/JIG8
combination is essentially unchanged by a real remount (same r as pure same-mount noise).
Proceeding to S5.3 (cross-jig, same motor) next, which per `AGENTS.md`'s newly-added objective 2
(cross-jig synchronization) is no longer just an S5 checklist item but the direct test of the
project's second authoritative objective.

## S5.3 (cross-jig, same motor) — P03 moved JIG8 -> JIG7, objective 2 NOT YET met

Same open-loop build (`BuildID=Aug 12 2026 16:45:25`), motor P03 physically moved to JIG7.
Log: `S4-P03-JIG7-openloop-v1-run01.txt`.

Identity confirmed directly: `MCU_UID=0046...` (JIG7, distinct from JIG8's `003E...`),
`JigID=JIG7,JigKnown=1`. `OfficialValid=10/10`, `AutoVerdict=PASS`, `CaptureIntegrityValid=1`,
zero acquisition errors.

### Scalar/harmonic comparison (JIG8 remount02 vs JIG7)

| Metric | JIG8 | JIG7 | Delta |
|---|---:|---:|---:|
| RawP2P | 2.932 deg | 2.843 deg | -3.0% |
| RobustP2P | 2.773 deg | 2.656 deg | -4.2% |
| A1 | 0.219 deg | 0.193 deg | -12.2% |
| A2 | 0.158 deg | 0.065 deg | **-58.7%** |
| A9 | 0.175 deg | 0.157 deg | -10.5% |
| A36 | 0.899 deg | 0.903 deg | **+0.5%** |

`A36` (36th-order, tied to the motor's own 6 pole pairs -- the "motor family" harmonic per this
project's long-standing framework) stayed essentially unchanged across jigs. `A1`/`A2` (the
"geometric/mounting family") shifted heavily -- consistent with, and now reproduced at
cross-jig scale, the same motor-vs-geometric harmonic split this project established from
cross-mount data back on 2026-08-10 (A36 cv~1.88%, A1/H1 cv~46%, A2/H2 cv~26%).

### 360-point curve correlation, full +/-180 shift search (not assuming 0 this time)

Ran the same correlation script, widened the shift search from +/-10 to +/-180 since cross-jig
has no shared mechanical datum (MA600 raw zero is local per sensor -- established finding from
the 2026-08-03 JIG1-vs-JIG4 root-cause plan). Note: the script's printed label text still says
"[-10,10]" (stale string, not updated) -- the actual loop range used was confirmed as -180..180
before running; the result is not an artifact of a narrow search.

- **r = 0.9683 at shift = 0** (0 remained optimal across the full search) -- markedly lower than
  S5.1/S5.2's same-jig value of 0.9993.
- RMSE after centering = **0.178 deg**, about 6-7x the same-jig value (0.026-0.027 deg).
- Top-5 (max-error) overlap: only 2/5 (294, 334); JIG8's 244/253/254 do not appear in JIG7's
  top-5 at all (JIG7: 174, 214, 293 instead).
- Bottom-5 (min-error) overlap: 3/5 (27, 106, 107).
- Per-point delta (JIG7 minus JIG8): mean **-0.219 deg** (a real systematic offset, unlike the
  ~0 mean seen in both same-jig comparisons), SD 0.178 deg, max deviation **0.68 deg** at index
  246.

### S5.3 verdict

**Objective 2 (cross-jig NL synchronization) is not yet demonstrated.** Not a pass/fail
statement about the product (no threshold exists, per AGENTS.md) -- an objective measurement of
how much curve correlation degrades cross-jig (0.9993 -> 0.9683) versus same-jig remount
(0.9993 -> 0.9993, unchanged). The degradation concentrates in the low-order/geometric harmonics
(A1/A2), not the motor-intrinsic A36 -- consistent with, not new evidence against, this
project's original governing question remaining open. This is the first clean open-loop
(non-creep-contaminated) data point quantifying that gap's actual size.

## A1/A2 cross-jig deep dive — evidence points to jig-locked, not motor-locked

Applied the 2026-08-03 JIG1-vs-JIG4 root-cause plan's reference-frame correction (section 2):
`phase_absolute = (H_PhaseSweepDeg + N * theta_start) mod 360`, `theta_start =
AnalysisStartRaw/65536*360`, computed for H1 (A1) and H2 (A2) across all three logs so far
(JIG8 remount01, JIG8 remount02, JIG7). Caveat: the firmware's phase sign convention isn't
independently confirmed, so absolute values carry that uncertainty -- but all three logs share
the same convention, so the *relative* comparison below is sound regardless.

| | theta_start | A1 | H1_abs | A2 | H2_abs |
|---|---:|---:|---:|---:|---:|
| JIG8 remount01 | 61.6 deg | 0.210 deg | 329.3 deg | 0.163 deg | **315.8 deg** |
| JIG8 remount02 | 62.7 deg | 0.214 deg | 327.7 deg | 0.157 deg | **314.0 deg** |
| JIG7           | 62.3 deg | 0.191 deg | 306.6 deg | 0.061 deg | **39.8 deg** |

**Finding**: `H2_abs` (A2's absolute phase) is nearly identical across two *independent* JIG8
remounts (315.8 vs 314.0 deg, 1.8 deg apart) but jumps ~276 deg when the same motor (P03) moves
to JIG7. `H1_abs` shows the same pattern more weakly (1.7 deg apart within JIG8, ~22 deg apart
cross-jig) -- consistent with A1's smaller amplitude swing (-12%) versus A2's (-59%).

**Interpretation**: stable-within-jig-but-different-across-jig is the signature of a
**jig-locked**, not motor-locked, component. This is the opposite of what a casual reading of
the earlier polar-chart order-2 "motor-locked tilt angle" cross-check (276/96 deg, computed with
a different tool/reference convention) might suggest -- **flagged as an open contradiction to
reconcile, not resolved here**, since the two methods' reference frames haven't been confirmed
equivalent. Taken at face value, this pattern explains why A36 (36th order, tied directly to
the motor's own 6 pole-pair electrical structure -- travels with the rotor regardless of jig)
stayed stable cross-jig while A1/A2 (mechanical-scale, order 1-2) did not: A1/A2 are plausibly
dominated by each jig's own MA600 sensor-mount eccentricity, which is fixed per jig, not
something that travels with the motor.

**Practical implication for objective 2**: if A1/A2 are genuinely jig-locked, synchronizing
low-order NL across jigs is not fixable by better motor-mounting procedure -- it needs
per-jig sensor/mount eccentricity characterization and correction, which is exactly the
direction the existing (not-yet-calibrated) `MountValid` effort was already pointed at, not a
new work item.

**Not yet done**: reconciling this with the earlier polar-chart "motor-locked" cross-check's
own reference convention; a third jig or a second JIG7 remount would strengthen (or break) the
jig-locked hypothesis, since two data points per jig is the minimum, not confirmation.

## Reconciled with the polar-chart method — was a unit bug on this session's side, not a real contradiction

Root cause: `motor_quality_polar.py`'s `_order2_locked_angles()` computes `phi2 =
atan2(b,a)/2` -- the final `/2` converts from the order-2 "doubled" DFT-phase space back to a
physical mechanical angle (order-2 advances twice as fast as true angle). Confirmed numerically:
`H2_PhaseSweepDeg/2` for run02 = -167.4817/2 = -83.74 deg -> pair (276.26, 96.26) deg, exactly
matching the polar chart's earlier reported 276/96 deg. So `H2_PhaseSweepDeg` itself lives in
that same doubled-phase space -- the earlier "H2_abs" table in this doc added `2*theta_start`
(correct for the doubled space) but never took the final `/2` back to physical angle, so its
values were not physical angles at all.

Corrected table (theta-start-corrected AND order-divided):

| | theta_start | H2 (frame-corrected, doubled space) | Physical angle pair |
|---|---:|---:|---|
| JIG8 remount01 | 61.6 deg | 315.8 deg | **157.9 / 337.9 deg** |
| JIG8 remount02 | 62.7 deg | 314.0 deg | **157.0 / 337.0 deg** |
| JIG7           | 62.3 deg | 39.8 deg  | **19.9 / 199.9 deg** |

The jig-locked-not-motor-locked finding **holds**: physical angle is stable to <1 deg across two
independent JIG8 remounts (157.9 vs 157.0 deg). The cross-jig shift is real but smaller than
first computed: **~42 deg** (nearest pair distance), not the previously mis-stated 276 deg.
A1 (order 1) needed no correction -- order-1 has no doubling, so the earlier H1_abs values
(329.3/327.7/306.6 deg) were already physical angles.

The polar chart's own 276/96 deg for run02 is not wrong -- it is the **sweep-relative** angle
(no `theta_start` correction), valid only for describing where the peak falls within that one
log's own sweep, not comparable across logs/jigs directly (exactly the warning in the
2026-08-03 root-cause plan). It happened to look close to a physically-meaningful number here
only because today's three runs' `theta_start` values were coincidentally similar (61.6-62.7
deg) -- not something to rely on in general.

## New product P010 on JIG7 -- independent test of the jig-locked hypothesis

First log from a different product this session: `S4-P010-JIG7-openloop-v1-run01.txt`. Confirmed
compliant (`SchemaVersion=6`, `MeasurementProfile=GREMSY_COMPAT_OPEN_LOOP_NL_V1`, same
`BuildID=Aug 12 2026 16:45:25`, `MotorPoleCount=12`/`MotorPolePairs=6` -- same 6-pole-pair
geometry as P03, so `A36` stays comparable). `OfficialValid=10/10`, `AutoVerdict=PASS`, clean
integrity.

| Metric | P010/JIG7 | P03/JIG7 (reference) |
|---|---:|---:|
| RawP2P | 3.572 deg | 2.843 deg |
| RobustP2P | 3.340 deg | 2.656 deg |
| A1 | 0.267 deg | 0.191 deg |
| A2 | 0.230 deg | 0.061 deg |
| A9 | 0.423 deg | 0.157 deg |
| A36 | 0.916 deg | 0.903 deg |

P010 reads objectively higher on nearly every scalar -- not interpreted as pass/fail (no
threshold exists per AGENTS.md), just noted as a different product with no direct comparison
basis yet.

**Jig-locked hypothesis check with independent data**: computed P010's A2 physical angle the
same corrected way -- `theta_start=46.5 deg`, doubled-space corrected value 75.3 deg, physical
angle pair **37.65 / 217.65 deg**. Compared to P03/JIG7's own pair (19.9 / 199.9 deg): **minimum
separation ~17.8 deg**.

This is supporting evidence, not proof: **two different motors (P010, P03) on the same jig
(JIG7) land ~18 deg apart**, noticeably closer than **the same motor (P03) moved between two
jigs (JIG8->JIG7), which was ~42 deg apart**. That is the direction the jig-locked hypothesis
predicts (different-motor-same-jig closer than same-motor-different-jig) -- one more data point
consistent with it, still not confirmation (would need more products/jigs to rule out
coincidence).

## P08 on JIG8 -- 5th data point complicates the jig-locked hypothesis, does not confirm it

`S4-P08-JIG8-openloop-v1-run01.txt`: confirmed compliant (schema 6, same build, 6 pole pairs),
`OfficialValid=10/10`, `PASS`, clean integrity. `RawP2P=3.152 deg`, `RobustP2P=2.918 deg`,
`A1=0.148 deg`, `A2=0.151 deg`, `A9=0.433 deg`, `A36=0.900 deg` (not interpreted as pass/fail --
no threshold exists).

A2 physical angle (same corrected method): `theta_start=85.1 deg`, doubled-space corrected
44.65 deg, physical pair **22.3 / 202.3 deg**.

| Comparison | Type | Angular separation |
|---|---|---:|
| P03/JIG8 vs P03/JIG7 | same motor, different jig | ~42 deg |
| P03/JIG7 vs P010/JIG7 | different motor, same jig | ~17.8 deg |
| **P03/JIG8 vs P08/JIG8** | **different motor, same jig** | **~44.8 deg** |
| P08/JIG8 vs P010/JIG7 | different motor, different jig | ~15.3 deg |

The bolded row breaks the simple story: two different motors (P03, P08) on the **same** JIG8
show almost as large an angular separation (~44.8 deg) as the same motor moved **between**
jigs (~42 deg) -- if A2 were purely jig-locked, same-jig-different-motor should have stayed
small, like the P03/P010 JIG7 pair did. Instead P08/JIG8 (22.3 deg) sits close to the *JIG7*
cluster (~20-38 deg: P03/JIG7 19.9, P010/JIG7 37.65), not close to P03's own JIG8 angle
(~157.5 deg).

**Honest read**: the "pure jig-locked" hypothesis does not survive this 5th point. More likely
A2 is a **vector sum of a jig component and a motor/clocking component**, and P03's <1 deg
stability across two JIG8 remounts may be specific to P03 (small motor-component, or its
clocking happened to repeat) rather than a general JIG8 signature every motor would show. Five
points (3 motors, not a full 2-jig factorial for each) is too few to separate the two
components -- this has effectively become a variance-components / Gage R&R question, which is
exactly what roadmap milestone S6 already anticipated needing, not something resolvable from a
handful of opportunistic points.

**Most informative next point**: P08 on JIG7 (user is already testing there) -- if it lands
near the ~20-38 deg JIG7 cluster, that further supports a real jig-component; if it lands near
P08/JIG8's own 22.3 deg regardless of jig, that would instead suggest a motor/product-specific
component dominates for P08.

## Cross-tab P03 x P08 on JIG7/JIG8 -- same-jig correlation beats same-motor cross-jig correlation

Computed the missing same-jig, cross-product correlations to complete the first 2x2 (2
products x 2 jigs) block: `JIG8: P03 vs P08` and `JIG7: P03 vs P08`.

| Comparison | Type | r |
|---|---|---:|
| P03: JIG8 vs JIG7 | same motor, different jig | 0.9683 |
| P08: JIG8 vs JIG7 | same motor, different jig | 0.9851 |
| JIG8: P03 vs P08 | same jig, different motor | 0.9234 |
| JIG7: P03 vs P08 | same jig, different motor | 0.9371 |

Also: P08's RawP2P reads ~7.5-8.5% higher than P03's **on both jigs** (JIG8: 2.932->3.152,
JIG7: 2.843->3.086) -- same direction, similar magnitude on both jigs, i.e. both jigs agree on
the relative ranking of these two products.

**Read at this point (2 products only)**: cross-jig same-product correlation (0.968-0.985) was
higher than same-jig cross-product correlation (0.923-0.937) -- suggesting most of what's
measured was real product-to-product difference, not jig artifact. This reading did not survive
the third product (see below).

## P010 on JIG8 -- reverses the read above, P010 correlates poorly everywhere

`S4-P010-JIG8-openloop-v1-run01.txt`. Confirmed compliant (schema 6, same build,
`AnalysisStartRaw=8076`), `OfficialValid=10/10`, `AutoVerdict=PASS`, clean integrity.

### Scalar: P010's cross-jig gap is much larger than P03's or P08's

| Metric | JIG7 (prior) | JIG8 (new) | Delta |
|---|---:|---:|---:|
| RawP2P | 3.572 deg | 4.177 deg | **+16.9%** |
| RobustP2P | 3.340 deg | 3.961 deg | **+18.6%** |
| A1 | 0.267 deg | 0.330 deg | +23.6% |
| A2 | 0.230 deg | 0.620 deg | **+169.6%** |
| A9 | 0.423 deg | 0.430 deg | +1.7% |
| A36 | 0.916 deg | 0.908 deg | -0.9% |

A36 stayed stable as in every prior comparison. RawP2P and A2 moved far more than the equivalent
P03 (-3.0%/A2 down 58.7%) or P08 (-2.1%/A2 down 19.3%) cross-jig deltas -- first time the
primary scalar itself shifted this much (~17%) cross-jig.

### Correlation: P010 correlates weakly with everything, not just cross-jig

| Comparison | r |
|---|---:|
| P010: JIG8 vs JIG7 (cross-jig, same motor) | **0.7682** |
| JIG8: P03 vs P010 | 0.7945 |
| JIG8: P08 vs P010 | 0.7230 |
| JIG7: P03 vs P010 | 0.8363 |
| JIG7: P08 vs P010 | 0.7875 |
| (reference) P03 vs P08, either jig | 0.923-0.985 |

P010's within-batch repeatability is not degraded (A2 cv=1.29%, RawP2P cv=1.11% on JIG8 --
comparable to P03/P08's own tight repeatability), so this is not sweep-to-sweep measurement
noise: P010's error-curve *shape* is genuinely, consistently different from P03's and P08's,
and does not reproduce well across jigs either.

### A2 physical angle: P010/JIG8 clusters with P03/JIG8, not with P08/JIG8

`theta_start=44.36 deg`, physical pair **146.7 / 326.7 deg**.

| | Physical angle on JIG8 |
|---|---:|
| P03/JIG8 | ~157.5 deg |
| P010/JIG8 | 146.7 deg (10.8 deg from P03) |
| P08/JIG8 | 22.3 deg (55.6 deg from P010) |

This reverses the previous entry's tentative read ("P03/JIG8 is the outlier"): with P010 added,
**P03 and P010 now cluster together on JIG8 (~150 deg), and P08 is the one that differs**
(~22 deg). JIG7 still shows all three products clustered (19.9-37.65 deg).

### Where this leaves the picture

No longer a single clean story. JIG7 shows fairly consistent cross-product correlation; JIG8
splits (P03/P010 cluster, P08 differs). P010 itself correlates weakly against every other
curve compared so far despite being internally repeatable -- open whether this is a genuine
product-shape difference or a mounting-instance artifact specific to this P010/JIG8 capture.
**Next most informative step**: a P010 remount on the same jig (mirroring the P03
remount01/remount02 pair) to separate "P010's own repeatable shape" from "this particular
mounting's artifact" -- without that, P010's low correlation numbers can't yet be attributed to
either cause.

## P010 JIG8 remount (run02) -- confirms run01 was a mounting artifact, but reveals a new finding

`S4-P010-JIG8-openloop-v1-run02.txt`, same motor remounted on JIG8. `OfficialValid=10/10`,
`AutoVerdict=PASS`, clean.

### Scalars land in the same range as JIG7 now (unlike run01)

| Metric | run01 (JIG8) | run02 (JIG8, remount) | JIG7 | Delta run02 vs JIG7 |
|---|---:|---:|---:|---:|
| RawP2P | 4.177 deg | **3.448 deg** | 3.572 deg | **-3.5%** |
| RobustP2P | 3.961 deg | 3.252 deg | 3.340 deg | -2.6% |
| A1 | 0.330 deg | 0.288 deg | 0.267 deg | +7.9% |
| A2 | 0.620 deg | **0.216 deg** | 0.230 deg | **-6.1%** |
| A36 | 0.908 deg | 0.911 deg | 0.916 deg | -0.5% |

Run02's cross-jig deltas (-3.5%/-2.6%/-6.1%) now sit in the same magnitude range as P03's
(-3.0%) and P08's (-2.1%), instead of run01's anomalous +16.9%/+169.6%. **Confirms run01 was an
atypical mounting instance for P010, not its repeatable signature.**

### Curve correlation confirms the user's direct observation

| Comparison | r |
|---|---:|
| P010 JIG8 run02 vs JIG7 | **0.9385** (was 0.7682 for run01) |
| P010 JIG8 run01 vs run02 (same jig, remount) | 0.9277 |
| JIG8: P03 vs P010(run02) | 0.8257 (was 0.7945) |
| JIG8: P08 vs P010(run02) | 0.7712 (was 0.7230) |

Run02 correlates much better with JIG7 and with the other JIG8 products than run01 did --
matches the user's direct read of the polar chart.

### New finding: P010's own remount repeatability is looser than P03's

run01-to-run02 (same motor, same jig, just remounted) gives r=0.9277 -- compare P03's
remount01-to-remount02 result of **0.9993**. P010's A2 physical angle also moved a real amount
between mounts (146.7 deg -> 165.2 deg, ~18.5 deg), and even after the improvement, run02's A2
angle (165.2 deg) is still ~52 deg from JIG7's (37.65 deg) -- closer than run01's ~71 deg gap,
but not tight. This does not contradict the scalar/curve-shape improvement (A36's amplitude,
~0.91 deg, dominates overall correlation far more than A2's, ~0.22 deg, so overall r can look
good even while the low-order A1/A2 phase story stays unresolved).

**Read**: run01 was genuinely atypical (confirmed by remount), which is reassuring for the
project overall -- but P010 itself now looks like it has more inherent remount-to-remount
sensitivity than P03. Not yet known whether that's a property of this specific motor unit
(shaft/coupling tolerance) or coincidence from two data points. A third P010 mount would
distinguish "P010 has a real wider mount-repeatability spread" from "run01/run02 just happened
to differ."

## P010 JIG7 remount (run02) -- best-mount pair shows P010 converges to P03/P08's cross-jig quality

`S4-P010-JIG7-openloop-v1-run02.txt`, same motor remounted on JIG7. `OfficialValid=10/10`,
`AutoVerdict=PASS`, clean.

### JIG7 remount also shifted, but less than JIG8's did

| Metric | run01 (JIG7) | run02 (JIG7, remount) | Delta |
|---|---:|---:|---:|
| RawP2P | 3.572 deg | 3.178 deg | -11.0% |
| A2 | 0.230 deg | 0.043 deg | **-81.3%** |
| A36 | 0.916 deg | 0.918 deg | +0.2% |

Remount correlation run01->run02 on JIG7: **r=0.9749** -- tighter than JIG8's remount result
(0.9277). P010's remount looseness is not symmetric across jigs: looser on JIG8, fairly tight
on JIG7.

### Best-mount cross-jig comparison (run02 vs run02) -- the key result

| Comparison | r |
|---|---:|
| **P010: JIG8(run02) vs JIG7(run02)** | **0.9708** |
| P010: JIG8(run01) vs JIG7(run01) | 0.7682 |
| P010: JIG8(run02) vs JIG7(run01) | 0.9385 |
| (reference) P03 cross-jig | 0.9683 |
| (reference) P08 cross-jig | 0.9851 |

When both sides use a "good" mount, **P010 reaches cross-jig curve correlation (0.97) matching
P03 (0.968) and approaching P08 (0.985)**. Strong evidence that P010's earlier inconsistency was
dominated by mounting-instance quality, not a genuinely different NL shape for this product.

A2 physical angle for run02/JIG7: `theta_start=46.03 deg`, pair **13.8 / 193.8 deg**. Cross-jig
gap using both good mounts (run02 vs run02): **~28.6 deg** -- better than run01-run01's ~71 deg,
between P08's 8.6 deg and P03's 42 deg.

### Where this leaves objective 2

All three products, when well-mounted, now show cross-jig curve correlation in the **0.97-0.99
range** -- a real convergence, not an isolated result. The practical lesson this batch of P010
data adds: **mounting quality affects the result more than which jig (JIG7 vs JIG8) is used** --
consistent with, and now better evidenced than, the mount-sensitivity concern flagged earlier
this session. Still not a designed experiment (opportunistic remounts, not a controlled Gage
R&R), but the signal is now consistent across two independent products (P03, P010).

## Why correlation is high but the NL scalar still differs -- and does averaging more points fix it

User asked to reconcile "if mounting matters more than jig identity, why don't the NL values
themselves match" and to quantify what happens if the primary metric used a broader window (5
points) instead of a strict single max/min point.

**Reconciliation**: Pearson r is computed on mean-centered data, so it is mathematically blind
to absolute amplitude/offset -- it only measures whether the relative shape (peaks/troughs in
the same places) co-varies. The dominant shape driver is A36 (motor-family, stable ~0.87-0.92
deg across every jig/mount seen today), so high r is expected regardless of mount. RawP2P, in
contrast, IS an amplitude statistic (max-min) -- it directly picks up the smaller but real
A1/A2 mount-eccentricity contribution, which does change with each physical mount. High
correlation + different NL scalar is therefore the expected combination, not a contradiction.

**1-point vs 5-point NL, computed directly on today's parsed curves** (`nl_1pt = max-min`,
`nl_5pt = mean(top5) - mean(bottom5)`):

| Dataset | NL 1pt | NL 5pt | Reduction |
|---|---:|---:|---:|
| P03/JIG8 | 2.921 deg | 2.768 deg | 5.2% |
| P03/JIG7 | 2.828 deg | 2.655 deg | 6.1% |
| P08/JIG8 | 3.146 deg | 2.917 deg | 7.3% |
| P08/JIG7 | 3.064 deg | 2.965 deg | 3.3% |
| P010/JIG8 run02 | 3.435 deg | 3.247 deg | 5.5% |
| P010/JIG7 run02 | 3.166 deg | 3.023 deg | 4.5% |

Cross-jig delta, 1pt vs 5pt:

| | 1pt delta | 5pt delta |
|---|---:|---:|
| P03 | -3.2% | -4.1% |
| P08 | -2.6% | +1.6% |
| P010 (bad mounts) | -14.2% | -15.7% |
| P010 (good mounts) | -7.8% | -6.9% |

**Result: switching from 1 point to 5 points does not reduce the cross-jig delta** -- it stays
the same order of magnitude (sometimes slightly worse). This confirms the cross-jig NL gap is a
real whole-curve amplitude effect (A1/A2 content genuinely differing by mount), not single-point
sampling noise that a broader statistic would average away. Broadening the window only shrinks
the absolute number (~5% smaller, from trimming the sharpest single outlier), it does not make
the value more stable across jigs/mounts.

## P011 -- 4th product, first test on both jigs

`S4-P011-JIG8-openloop-v1-run01.txt` and `S4-P011-JIG7-openloop-v1-run01.txt`. Both confirmed
compliant, `OfficialValid=10/10`, `AutoVerdict=PASS`, clean.

### Scalars

| Metric | JIG8 | JIG7 | Delta |
|---|---:|---:|---:|
| RawP2P | 3.212 deg | 2.679 deg | -16.6% |
| RobustP2P | 2.969 deg | 2.581 deg | -13.1% |
| A1 | 0.328 deg | 0.073 deg | -77.9% |
| A2 | 0.101 deg | 0.036 deg | -64.4% |
| A36 | 0.869 deg | 0.875 deg | +0.7% |

A36 stable as always. RawP2P delta (-16.6%) is on the larger side (comparable to P010's bad-mount
run), but this is P011's first test on either jig -- no remount data yet to know if this
mounting was typical.

### Curve correlation

`P011: JIG8 vs JIG7 = r=0.9511` -- lands in the same 0.95-0.99 band as P03 (0.968), P08 (0.985),
and P010's best mounts (0.971). Fourth product now supporting "well-mounted products sync well
cross-jig at the shape level."

### A2 physical angle -- JIG8 cluster now has 3 of 4 products

`theta_start(JIG8)=53.03 deg` -> pair **165.7 / 345.7 deg**.
`theta_start(JIG7)=53.27 deg` -> pair **30.3 / 210.3 deg**.

| | Physical angle on JIG8 |
|---|---:|
| P03 | 157.5 deg |
| P010 (run02, good mount) | 165.2 deg |
| **P011** | **165.7 deg** |
| P08 | 22.3 deg (still the outlier) |

**Three of four products now cluster tightly (157.5-165.7 deg, ~8 deg spread) on JIG8.** Only
P08 remains apart (~22 deg, ~135-144 deg from the cluster). On JIG7, all four products remain
clustered (13.8-30.9 deg, ~17 deg spread), no outlier.

**Updated read**: this is the strongest evidence yet for a genuine JIG8-specific angular
signature that most motors pick up -- P08 is now the specific anomaly requiring explanation
(motor-specific trait, or an unverified atypical mount for that one unit), not JIG8 lacking a
signature at all. A P08 remount on JIG8 would be the most informative next check: landing near
the ~160 deg cluster would confirm P08's first result was atypical; staying near ~22 deg would
mean P08 itself is a genuine exception to the JIG8 signature.

## P013 -- 5th product, both jigs tested together; confirms JIG8 cluster, breaks JIG7 cluster

`S4-P013-JIG8-openloop-v1-run01.txt` and `S4-P013-JIG7-openloop-v1-run01.txt`. Both confirmed
compliant, `OfficialValid=10/10`, `AutoVerdict=PASS`, clean.

### Scalars -- one of the tightest cross-jig scalar matches today

| Metric | JIG8 | JIG7 | Delta |
|---|---:|---:|---:|
| RawP2P | 3.024 deg | 3.112 deg | **+2.9%** |
| RobustP2P | 2.899 deg | 2.968 deg | +2.4% |
| A1 | 0.373 deg | 0.125 deg | -66.5% |
| A2 | 0.176 deg | 0.410 deg | +132.4% |
| A36 | 0.858 deg | 0.862 deg | +0.5% |

RawP2P/RobustP2P deltas (+2.9%/+2.4%) are in the smallest group seen today, alongside P03
(-3.0%) and P08 (-2.1%). A1/A2 percentage swings look large only because their absolute values
are small; they don't dominate total RawP2P.

### Curve correlation

| Comparison | r |
|---|---:|
| **P013: JIG8 vs JIG7 (cross-jig)** | **0.9315** |
| JIG8: P011 vs P013 | 0.9172 |
| JIG8: P03 vs P013 | 0.8352 |
| JIG8: P010 vs P013 | 0.7504 |
| JIG8: P08 vs P013 | 0.6798 |

Fifth product landing in the established 0.93-0.99 cross-jig band. Notably high same-jig
cross-product correlation between P011 and P013 (0.917) -- higher than any other cross-product
pair seen today.

### A2 physical angle -- JIG8 cluster strengthens, JIG7 cluster breaks for the first time

`theta_start(JIG8)=79.00 deg` -> pair **158.3 / 338.3 deg**.
`theta_start(JIG7)=79.19 deg` -> pair **141.2 / 321.2 deg**.

JIG8 update:

| | Physical angle on JIG8 |
|---|---:|
| P03 | 157.5 deg |
| P010 (good mount) | 165.2 deg |
| P011 | 165.7 deg |
| **P013** | **158.3 deg** (only 0.84 deg from P03) |
| P08 | 22.3 deg (still the outlier) |

**4 of 5 products now cluster within 157.5-165.7 deg (~8 deg spread) on JIG8.**

JIG7 -- first break in an otherwise-stable pattern:

| | Physical angle on JIG7 |
|---|---:|
| P03 | 19.9 deg |
| P08 | 30.9 deg |
| P010 | 13.8 deg |
| P011 | 30.3 deg |
| **P013** | **141.2 deg** -- well outside the 14-31 deg cluster |

P013 on JIG7 breaks the tight cluster four straight products had held -- and its value (141.2
deg) sits closer to JIG8's cluster region (~158 deg) than to JIG7's own established cluster.

### Read

The JIG8-signature evidence keeps strengthening (4/5 products, ~8 deg spread). But P013 on
JIG7 breaks the pattern in the opposite direction from P08's break on JIG8 -- P08 was the
outlier on JIG8 while matching JIG7's cluster; P013 is the outlier on JIG7 while matching
JIG8's cluster region. This argues against a simple "each jig adds one fixed phase vector"
model, since that model predicts every product should land near each jig's own cluster
regardless of which product it is. **Most informative next step**: remount P013 on JIG7 --
consistent with today's repeated pattern (P08/JIG8, P010/JIG8, P010/JIG7 all turned out to be
mounting-instance artifacts on first test), the first-order guess is this is another atypical
mount rather than a genuine P013-specific trait, but that needs verification, not assumption.

## P013 remounted on both jigs (JIG8 run02, JIG7 run03) -- refutes the "mounting artifact" guess

`S4-P013-JIG8-openloop-v1-run02.txt` and `S4-P013-JIG7-openloop-v1-run03.txt`. Both confirmed
compliant, `OfficialValid=10/10`, `AutoVerdict=PASS`, clean.

### Remount repeatability is tight on BOTH jigs -- not a mounting-artifact case

| Comparison | r |
|---|---:|
| P013 JIG8 remount (run01 vs run02) | **0.9946** |
| P013 JIG7 remount (run01 vs run03) | **0.9824** |

Both are tight -- JIG8's is close to P03's own remount ceiling (0.9993), and JIG7's is tighter
than P010's JIG7 remount (0.9749). **P013 repeats reliably on both jigs.** The prior entry's
guess (that P013/JIG7's outlier angle was probably an atypical mount, per this session's usual
pattern) does not hold up -- the value repeats.

### A2 physical angle -- all four P013 readings cluster together, none match the JIG7 group

`theta_start(JIG8 run02)=77.43 deg` -> pair **152.1 / 332.1 deg**.
`theta_start(JIG7 run03)=78.09 deg` -> pair **150.8 / 330.8 deg**.

**Cross-jig gap using the two repeatable mounts: only 1.29 deg** -- the tightest cross-jig A2
agreement seen for any product today.

All four P013 readings so far:

| | Angle |
|---|---:|
| JIG7 run01 | 141.2 deg |
| JIG8 run01 | 158.3 deg |
| JIG8 run02 | 152.1 deg |
| JIG7 run03 | 150.8 deg |

All four sit in **141-166 deg** -- none land near the ~14-31 deg cluster that P03/P08/P010/P011
all shared on JIG7. Curve correlation for the repeatable pair (run02 JIG8 vs run03 JIG7):
**r=0.9430**, still within today's established 0.93-0.99 band.

### Read -- reverses the prior tentative guess

P013's ~141-166 deg angle is not a mounting artifact -- it is a **real, repeatable, product-
specific trait**, confirmed by two independent, tightly-repeating mounts on each jig. The most
coherent model now: A2's observed angle is a **vector sum of a jig-side component and a
motor-side component**. For P03/P08/P010/P011, the jig-side component apparently dominates on
JIG7 (pulling all four toward the same ~14-31 deg region regardless of motor). For P013, the
motor-side component is apparently large enough to dominate on **both** jigs, keeping the
resultant angle nearly jig-independent (~141-166 deg everywhere). This is the first clean
empirical case this session where a genuine motor-locked component is distinguishable from the
jig-locked one, rather than one hypothesis needing to explain every product uniformly -- which
product dominates depends on the specific motor, not a fixed rule.

## P08 on JIG7 -- 6th point lands the cluster, reframes the hypothesis again

`S4-P08-JIG7-openloop-v1-run01.txt`. Same build. `AutoVerdict=CAPTURE INVALID` -- but the cause
is benign: 1 of 360 points missing (index 14) in one sweep (TestID=10), everything else clean
(`DecodeErrors=0`, `AcqFailedSamples=0`); result **9/10 official sweeps valid** rather than the
usual 10/10. Treated the 9 valid sweeps as usable data, not discarded.

### Scalar/harmonic: P08 JIG8 -> JIG7

| Metric | JIG8 | JIG7 | Delta |
|---|---:|---:|---:|
| RawP2P | 3.152 deg | 3.086 deg | -2.1% |
| RobustP2P | 2.918 deg | 2.970 deg | +1.8% |
| A1 | 0.146 deg | 0.217 deg | **+49.1%** |
| A2 | 0.144 deg | 0.116 deg | -19.3% |
| A9 | 0.433 deg | 0.431 deg | -0.6% |
| A36 | 0.888 deg | 0.888 deg | +0.1% |

A36 again essentially unchanged cross-jig, consistent with every prior comparison. A1 moved the
*opposite direction* from P03's cross-jig A1 shift (+49% here vs -12% for P03) -- a new wrinkle,
not yet explained.

### Curve correlation: P08 syncs cross-jig much better than P03 did

`r = 0.9851`, RMSE(centered) = 0.130 deg, mean per-point delta = **-0.021 deg** (essentially no
systematic offset). Compare P03's cross-jig result: r = 0.9683, RMSE = 0.178 deg, mean delta =
**-0.219 deg** (a real systematic offset). P08's whole 360-point curve reproduces across jigs
noticeably more faithfully than P03's did -- the first evidence that cross-jig sync quality is
not uniform across products.

### A2 physical angle: P08/JIG7 = 30.9/210.9 deg

Using the validated method (`theta_start=86.08 deg`, order-2 division): pair **30.9 / 210.9
deg**. Cross-jig shift for P08 itself (JIG8->JIG7): only **~8.6 deg** -- an order of magnitude
smaller than P03's ~42 deg cross-jig shift.

Full physical-angle table so far:

| | Physical angle pair |
|---|---|
| P03/JIG8 (both remounts) | 157.9 / 337.9 deg |
| P03/JIG7 | 19.9 / 199.9 deg |
| P010/JIG7 | 37.65 / 217.65 deg |
| P08/JIG8 | 22.3 / 202.3 deg |
| P08/JIG7 | 30.9 / 210.9 deg |

### Reframed hypothesis

This walks back the previous entry's "vector sum of jig + motor component" framing. With this
6th point, **four of five readings (P03/JIG7, P010/JIG7, P08/JIG8, P08/JIG7) cluster tightly in
a ~20-38 deg band regardless of jig or motor**, and curve correlation confirms P08's whole curve
(not just A2) travels cross-jig with much smaller distortion than P03's did. **The only outlier
in the dataset is P03/JIG8 at ~157 deg**, isolated ~120-140 deg from every other reading.

The sharper, more falsifiable question this now raises: is P03/JIG8's ~157 deg reading a
one-off specific to that motor+JIG8 mounting event (clocking, seating, torque), rather than
JIG8 having a general "signature" -- since P08 on the *same* JIG8 did not reproduce it? A
second motor tested on JIG8 would settle this directly: landing near 157 deg would revive the
jig-locked reading for JIG8 specifically; landing in the ~20-38 deg cluster like P08 did would
point to P03/JIG8 being the anomaly instead. Still only 6 opportunistic points, not a designed
experiment -- this remains a variance-components / Gage R&R question for S6, not something to
conclude from ad hoc data.
