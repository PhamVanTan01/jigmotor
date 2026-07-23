# A5 implementation and validation checklist

Overall status: **A5.6 COMPLETE — RawAngle stability locked**  
Approved profile: `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1`  
Parent baseline: `CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1`

The detailed design and acceptance rationale are in
`docs/control-a5-ma600-static-raw-angle-plan.md`. This checklist is the
authoritative progress tracker; an item is checked only after its evidence is
available.

## A5.0 — Freeze specification and rollback

- [x] Operator approved the detailed A5 plan on 2026-07-20.
- [x] Measurement is limited to `MA600_ANGLE_WORD_RAW16`.
- [x] Sample contract fixed at 2048 accepted samples, 1 kHz, 2.048 s.
- [x] A4B offset fixed at 7971 raw.
- [x] A4B power, ramp, S-curve, direction, capture and safety gates frozen.
- [x] Exact hardware-tested A4B Control ELF preserved.
- [x] Exact hardware-tested A4B Control HEX preserved.
- [x] Copied artifact hashes independently recomputed and matched.
- [x] A4B binary identity checked: correct A4B profile; no A5 or Measurement
  profile string.
- [x] No firmware source/runtime behavior changed during A5.0.

Rollback directory:

```text
builds/control-a4b-offset7971-20260720/
```

Rollback hashes:

```text
C3817E2A589035FB10996F08C033F25372533A48EA2E7455166BF35249E1CDE0  jigmotor_control.elf
858A17A1E22CCFAD6B92B0AA1A15533D25529D0611882E1F22728AF4CBF57186  jigmotor_control.hex
```

A5.0 gate: **PASS**.

## A5.1 — Data model and pure math

- [x] Add A5 profile/constants and compile-time locks.
- [x] Add 12-byte `ControlA5Sample_t` with a static-size assertion.
- [x] Add A5 report/result/invalid-reason structures.
- [x] Add wrap-safe relative angle calculation.
- [x] Add integer/Q16 mean and min/max/P2P/drift calculations.
- [x] Add ordered raw-sequence CRC32.
- [x] Test constant, wrap, quantized-noise, drift, impulse and overflow vectors.
- [x] Test DWT wrap and schedule arithmetic.
- [x] Prove A5.1 does not yet alter the active A4B execution path.

A5.1 gate: **PASS (2026-07-20)**.

Evidence:

- `scripts/test_control_a5_math_contract.ps1`: PASS.
- Constant, wrap, noise, drift, impulse, overflow and DWT schedule vectors:
  PASS.
- Control Release compile: 0 errors, 0 warnings; standalone A5 math also
  passes `-Wall -Wextra -Wconversion -Wsign-conversion -Wshadow -Werror`
  with GCC static analysis enabled.
- A4B alignment and dual-image isolation contracts: PASS.
- Linked Control ELF contains A4B identity once and no A5 identity/symbol.
- Control HEX SHA-256 remains
  `858A17A1E22CCFAD6B92B0AA1A15533D25529D0611882E1F22728AF4CBF57186`,
  identical to the frozen A4B hardware-tested rollback image.

## A5.2 — Capture integration

- [x] Allocate the 24,576-byte evidence buffer once during engine init.
- [x] Fail initialization safely if allocation/headroom is invalid.
- [x] Add read-only MA600 config gate.
- [x] Preserve A4B trajectory and numeric constants exactly.
- [x] Verify constant phase-0/power-35% state before capture.
- [x] Use a dedicated A5 acquisition context.
- [x] Capture exactly 2048 samples with no UART in the active window.
- [x] Record DWT cycle, TIM1 phase and SPI latency per sample.
- [x] Enforce no catch-up sampling, abort, step/travel and timing gates.
- [x] Verify state again after capture.
- [x] Route every exit through Motor_Disable before report.

A5.2 gate: **PASS (2026-07-20)**.

Evidence:

- `scripts/test_control_a5_capture_contract.ps1`: PASS.
- A5.1 math, A4B alignment, controller-state, SPI DMA and dual-image
  regression contracts: PASS.
- The timed capture module contains no motor mutation and no UART operation.
- It uses a new acquisition context, one checked attempt per slot, absolute
  `osDelayUntil` scheduling, no catch-up, DWT wrap-safe timing and all locked
  step/travel/duration gates.
- The 24,576-byte retained heap allocation enforces at least 64 KiB free heap
  after allocation; nominal A4B evidence leaves 67,112 bytes.
- Enabled-branch strict GCC/static analysis and full link: PASS; linked size
  is text 55,608, data 96, BSS 175,312 bytes before the dynamic buffer.
- Default activation and identity acknowledgement locks remain 0. The normal
  A4B Control HEX is still byte-for-byte identical to the frozen baseline:
  `858A17A1E22CCFAD6B92B0AA1A15533D25529D0611882E1F22728AF4CBF57186`.

## A5.3 — Schema and host analyzer

- [x] Emit versioned `CONTROL_A5_ARMED` and config identity.
- [x] Emit summary, timing, health and state records.
- [x] Emit exactly 2048 `CONTROL_A5_DATA` records after safe-stop.
- [x] Add `scripts/analyze_control_a5.ps1`.
- [x] Validate profile/config/count/index continuity and CRC.
- [x] Recompute all firmware summary fields from DATA.
- [x] Compute SD, MAD, drift, detrended SD, delta histogram, autocorrelation,
  Allan deviation and PWM-phase dependence offline.
- [x] Add synthetic valid, wrap, truncated, duplicate, reordered and bad-CRC
  fixtures.
- [x] Preserve A4/A4B analyzer compatibility.

A5.3 gate: **PASS (2026-07-20, software/schema boundary)**.

Evidence:

- `scripts/test_control_a5_reporting_contract.ps1`: PASS; no A5 UART before
  the converged motor-disable/safe-stop/finalize path.
- `scripts/test_analyze_control_a5.ps1`: PASS for valid, wraparound and
  multi-run fixtures; truncated, duplicate, reordered and bad-CRC fixtures
  are rejected.
- Analyzer exports one summary row/run and optional raw rows, recomputes all
  firmware summary/timing/CRC fields and adds the required distribution,
  drift, autocorrelation, Allan and PWM diagnostics.
- Enabled-branch full link and strict GCC/static analysis: PASS;
  `text=58,832`, `data=96`, `bss=175,312` bytes before the retained 24 KiB
  buffer.
- Normal A4B Control HEX remains byte-identical to the frozen rollback image:
  `858A17A1E22CCFAD6B92B0AA1A15533D25529D0611882E1F22728AF4CBF57186`.
- Existing A4B analyzer still accepts the stored complete batch 20/20.
- Hardware log equality is intentionally deferred to A5.5 after A5.4 changes
  the app identity and activation locks.

## A5.4 — Build and isolation

- [x] Update Control app profile identity only when the active capture is ready.
- [x] Update control-alignment and dual-image contracts.
- [x] Clean-build Control Debug/Release with zero warning.
- [x] Verify Measurement ELF has no A5 symbols/strings.
- [x] Record ELF/HEX hashes and link-map memory use.
- [x] Verify free heap remains above 64 KiB after buffer allocation (static
  config + firmware fail-closed gate + nominal arithmetic; runtime number
  deferred to A5.5).
- [x] Verify control stack headroom remains above 1 KiB (static
  `-fstack-usage` estimate; runtime high-water number deferred to A5.5).
- [x] Run all relevant host regression scripts.

A5.4 gate: **PASS (2026-07-20)**.

Evidence:

- `CONTROL_A5_CAPTURE_INTEGRATION_ENABLED`/`CONTROL_A5_PROFILE_ACTIVATION_ACK`
  flipped 0->1 in `Core/Inc/control_a5_capture.h`; `JIG_APP_PROFILE_ID` in
  `Core/Inc/app_mode.h` switched from the A4B string to
  `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1`. No A4B trajectory/
  timing/gate constant changed.
- `scripts/test_control_alignment_contract.ps1` and
  `scripts/test_dual_image_contract.ps1` updated to expect the A5 identity
  while keeping every A4 envelope lock byte-for-byte; the two lingering
  A5.1/A5.2-era dormancy tripwires in `test_control_a5_math_contract.ps1`,
  `test_control_a5_capture_contract.ps1` and
  `test_control_a5_reporting_contract.ps1` were flipped to assert the now-active
  state instead of dormancy.
- Full contract suite: 23/23 PASS after the switch, including all A5 tests
  and the two updated identity/isolation contracts.
- Clean Control Debug and Release builds via `build_cubeide.ps1`: 0 errors,
  0 warnings both configurations.
- Dual-image build (`build_dual_image.ps1 -Mode All`): Control
  text=58,832 data=96 bss=175,312; Measurement unchanged at
  text=80,188 data=96 bss=140,040.
- `nm`/`strings` isolation, independently checked: Control ELF contains
  `ControlA5_CaptureStaticWindow` and the A5 profile string (plus the
  expected embedded A4B `ParentProfile` string); Measurement ELF contains
  neither the A5 profile string nor any `ControlA5_` symbol.
- Control HEX SHA-256 is now
  `0492D9F0E56C37049DF6F172A57CCB192E63FBC24A0153674BDE1104E56DD265`
  (intentionally different from the frozen A4B rollback hash, since A5 is now
  the active default). Archived with the ELF and a manifest under
  `builds/control-a5-offset7971-n2048-20260720/`.
- Static `-fstack-usage`: new `ControlA5_CaptureStaticWindow` frame is 120
  bytes; `ControlRunAlignment` was inlined into `ControlRunA5` (984-byte
  combined frame). Against A4B's hardware-measured ~1600-byte peak on the
  6144-byte task stack (4544 bytes free), the added path leaves headroom far
  above the 1 KiB floor; the authoritative number is
  `ControlStackHighWaterWords` from `CONTROL_A5_RUNTIME` on real hardware
  (A5.5).
- Heap: `configTOTAL_HEAP_SIZE` unchanged at 102,400 bytes; nominal
  91,688 - 24,576 = 67,112 bytes clears the 64 KiB floor by 3,112 bytes. The
  authoritative number is `FreeHeapAfterAllocation` on real hardware (A5.5).
- No physical run has been made with this image; A5.5 hardware pilot is the
  next required step.

## A5.5 — Hardware pilot

- [x] Keep the same motor/mount; no removal during the batch. Operator
  confirmed the mount was never disturbed across round 1 + round 2.
- [x] Capture five files with two physical runs each (round 1) plus a second
  five-file/10-run batch (round 2) per the merge decision below.
- [x] Cover four electrical start quadrants. Round 2 placed run-1 starts at
  25.3 deg (`test6`) and 19.7 deg (`test8`), closing the Q1 gap round 1 left
  open; combined with round 1's Q2/Q3/Q4 coverage, all four quadrants are
  represented across the 20-run batch.
- [x] Include one first run after at least 15 minutes powered off. Operator
  confirmed a full, genuine power-off (not just an idle/powered gap while
  saving a log file) of >15 minutes between `test6` and `test7`; `test7 run1`
  is the true cold-start run.
- [x] Confirm exact A5 manifest/config on every independent boot.
- [x] Achieve 10/10 hard structural validity (round 1) — **20/20** combined
  with round 2.
- [x] Review statistical investigation bands without filtering raw evidence.

A5.5 gate: **PASS (2026-07-20).** All items closed via the round 1 + round 2
merge; see A5.6 below for the combined 20-run evidence and analysis.

Evidence (round 1, `A5 test 1.txt` .. `A5 test 5.txt`, built from
`29856e6dc8e1-dirty`, functionally identical to the `ef0025af801b-dirty`
rebuild archived at `builds/control-a5-offset7971-n2048-20260720/`):

- `scripts/analyze_control_a5.ps1`: 10/10 blocks `MeasurementValid=1`,
  2048/2048 accepted every run, 0 retry/transport/jump-reject/failed-sample.
- P2P 11-16 raw (band <=32), population SD 1.63-2.06 raw (band <=5),
  first-to-last drift -2..+6 raw (band <=16) — all comfortably inside the
  pilot investigation bands from the plan.
- Max schedule error 74 cycles (~0.44 us); SPI latency constant 1338 cycles
  every single run — timing is essentially noise-free.
- `ElectricalOffsetRaw` (the A4 alignment endpoint, a different quantity from
  A5's own within-window noise) spans 7914-7996, range 82 raw = 0.45 deg
  electrical. This is A4 drag-alignment repeatability, not A5 sensor noise;
  flagged separately from the RawAngle stability question this phase is
  about. If a tighter absolute-alignment tolerance is ever wanted, that is
  future A4 work, not an A5 gate.
- Re-derived electrical start quadrant from `BaselineRaw mod 10923` in each
  `CONTROL_A4_SUMMARY` (not the endpoint, which A4 is designed to converge
  regardless of start): 7 of 10 runs land in Q3 (~260 deg), 2 in Q4, 1 in Q2,
  **0 in Q1**. Every run-2-of-a-file lands near Q3 by construction (it starts
  where run-1's own A5 hold left the rotor); true start diversity comes only
  from the operator's manual rotation between files. Round 2 must place at
  least one run's baseline in Q1 (`BaselineRaw mod 10923` roughly 0-2730)
  before starting.
- Fixed a cosmetic `Write-Host "{0}"`-format precedence bug in
  `scripts/analyze_control_a5.ps1`'s console diagnostics (string
  concatenation split across lines was defeating `-f` substitution on the
  first half); confirmed it only affected the human-readable console text,
  not any computed/exported value, and the contract test still passes.

**Merge decision (2026-07-20):** rather than running a dedicated A5.5-only
round 2 and then a separate A5.6 batch, one 10-run batch (files 6-10) served
both: it closed A5.5's three open items (Q1 coverage, cold start, explicit
same-mount confirmation) AND was A5.6's own required "second independent
10-run batch, including cold start." Confirmed a scheduling merge, not a
criteria relaxation — every item either gate originally required was still
produced, just in one hardware session instead of two.

## A5.6 — Confirmation and lock

Round 2 (`A5 test 6.txt` .. `A5 test 10.txt`), same motor/mount as round 1,
no removal at any point (operator-confirmed):

- [x] Capture a second independent 10-run batch including cold start.
  `test7 run1` followed a genuine, fully powered-off gap of >15 minutes
  between `test6` and `test7` (operator-confirmed: full power removal, not
  an idle/powered gap while saving the log).
- [x] Compare cold/warm, first/second and between-batch means.
- [x] Document within-window and across-run RawAngle limits from 20 valid runs.
- [x] Explain any PWM-phase, drift or distribution dependency.
- [x] Lock RawAngle stability and retain only a small health monitor later.

A5.6 gate: **PASS (2026-07-20).**

### Combined 20-run evidence

All 20 runs (`test1`..`test10`, 2 runs/file): `MeasurementValid=1`,
2048/2048 accepted, 0 retry/transport/jump-reject/failed-sample, 0 skipped
slot/timing overrun. Electrical start quadrant coverage across the combined
batch: Q1 (`test6r1`=25.3 deg, `test8r1`=19.7 deg), Q2 (`test4r1`=141.8 deg,
`test7r1`=148.2 deg), Q3 (majority — every run-2-of-a-file lands here by
construction, starting where run-1's own A5 hold parked the rotor), Q4
(`test2r1`, `test3r1`, `test9r1`=332.4 deg, `test10r1`=327.3 deg).

| Metric | Round 1 (5 files) | Round 2 (5 files) | Combined (20 runs) | Investigation band |
| --- | ---: | ---: | ---: | ---: |
| P2P (raw) | 11-16 | 12-15 | 11-16 (0.060-0.088 deg) | <=32 |
| Population SD (raw) | 1.63-2.06 | 1.82-2.16 | 1.63-2.16 (0.009-0.012 deg) | <=5 |
| Mean SD (raw) | 1.878 | 1.957 | 1.918 | — |
| First-to-last drift (raw) | -2..+6 | -4..+6 | -4..+6 (-0.022..+0.033 deg) | <=16 |
| SPI latency (cycles) | constant 1338 | constant 1338 | constant 1338 | — |
| Max schedule error (cycles) | 74 | 74 | 74 (~0.44 us) | — |

Round1-vs-round2 mean-SD delta is 4.2% (1.878 vs 1.957 raw) — well inside
normal run-to-run scatter, no evidence of a systematic between-batch shift.

**Cold vs warm:** the cold run (`test7 run1`, SD=2.1599 raw, P2P=15 raw) is
16.6% higher SD than its own immediate warm follow-up (`test7 run2`,
SD=1.8529 raw). This is the single highest SD in the whole 20-run batch
(second-highest: `test8 run1`=2.1153, also chronologically close to the cold
gap) — a mild, plausible warm-up signature consistent with the rest of the
project's observed thermal drift pattern, but based on **n=1 genuine cold
sample**, confounded with `test7 run1` also being one of only two Q2 samples.
Reported as an observation, not a locked cold-start derating: the difference
is small (both values remain far inside the P2P/SD bands) and cannot be
statistically separated from ordinary run-to-run and quadrant scatter with
this sample size.

**PWM-phase dependency:** every one of the 20 runs covered all 32/32 PWM
phase bins (`PwmPhaseBinMask=0xFFFFFFFF`), so the diagnostic had full
resolution to detect a correlation. `PwmFirstHarmonicP2PRaw` is 0.075-0.16
raw across all 20 runs — under 1.5% of the total P2P budget. **No meaningful
PWM-phase dependency found.** This also closes out the conditional trigger
for a separate A5B (alternate sample-rate/phase) experiment from the plan's
section 3.2: nothing in this data calls for it.

**Distribution/drift:** delta histograms are unimodal and roughly symmetric
in every run (no bimodal/stepped pattern -> no cogging-slip or mounting-
movement signature). Allan deviation decreases monotonically from ~1 ms to
~128 ms in every run (e.g. `test10 run1`: 1.84 -> 1.33 -> 0.94 -> 0.68 ->
0.47 -> 0.39 -> 0.23 -> 0.19 raw), consistent with ordinary averaging of a
white-ish noise process, not a flicker/1-over-f floor or runaway drift.

### Locked conclusion

RawAngle stability is locked as **observed engineering envelope from 20
valid hardware runs** (deliberately not promoted to a product/ISO pass-fail
limit, per the plan's explicit non-goal): P2P 11-16 raw, population SD
1.63-2.16 raw, first-to-last drift -4..+6 raw, over a 2048-sample/2.048 s
static window at phase 0 / 35% power. All values sit far inside the pilot
investigation bands (roughly half of the P2P budget, under half of the SD
budget, under half of the drift budget) with no PWM-phase, distribution, or
long-tau drift dependency found. Per A5.6's own closing instruction, later
phases should retain only the existing structural gates (retry/transport/
step/travel/safe-stop, already enforced in firmware) as an ongoing health
check, not re-run this full statistical characterization.

Error-budget context carried into the next-phase decision: A5's per-sample
SD (~1.92 raw) implies per-measurement-point noise (64-sample average) of
~1.92/8 =~ 0.24 raw =~ 0.0013 deg, and propagated Closure noise of
~sqrt(2) x 0.0013 =~ 0.0018 deg -- roughly 10x smaller than the ~0.016-0.022
deg Closure SD observed in real production batches (test16/test17). MA600
sensor noise, now precisely characterized, is not the dominant remaining
contributor to production measurement variance.

## Phase-level exit rule

Do not advance after a failed gate by changing multiple variables. Preserve
the failing raw evidence, classify transport/timing/PWM/mechanical/controller
causes, and modify only the responsible layer under a new profile identity.
