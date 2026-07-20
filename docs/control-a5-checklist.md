# A5 implementation and validation checklist

Overall status: **A5.4 COMPLETE — A5.5 NOT STARTED**  
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

- [~] Keep the same motor/mount; no removal during the batch (round 1: not
  disturbed per operator; endpoint spread of 82 raw is consistent with this
  but does not itself prove it).
- [x] Capture five files with two physical runs each (round 1 complete).
- [ ] Cover four electrical start quadrants — **Q1 (0-90 deg elec) missing**,
  round 1 only hit Q2/Q3/Q4 (see table below). Round 2 needed.
- [ ] Include one first run after at least 15 minutes powered off — not yet
  explicitly confirmed for any of the 10 round-1 runs.
- [x] Confirm exact A5 manifest/config on every independent boot.
- [x] Achieve 10/10 hard structural validity.
- [x] Review statistical investigation bands without filtering raw evidence.

A5.5 gate: **PARTIAL — structural/statistical bands PASS 10/10; quadrant and
cold-start coverage still open.**

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
round 2 and then a separate A5.6 batch, the next 10-run batch (files 6-10)
serves both: it closes A5.5's three open items (Q1 coverage, cold start,
explicit same-mount confirmation) AND is A5.6's own required "second
independent 10-run batch, including cold start." A5.5's gate closes
retroactively once that batch lands clean; A5.6 then compares it against
round 1 as its 20-run confirmation. This is a scheduling merge, not a
criteria relaxation — every item either gate originally required is still
produced by round 2, just in one hardware session instead of two.

Round 2 requirements (files `A5 test 6.txt` .. `A5 test 10.txt`):

- Same motor/mount as round 1; confirm explicitly whether it was disturbed
  at any point between round 1 and round 2 (if disturbed, offset 7971 needs
  re-measurement before this round is comparable, and the batch is a new
  mount identity rather than a continuation).
- File 6, run 1 must be a genuine cold start: >=15 minutes powered off
  immediately before pressing start.
- At least one run's baseline seeded into Q1: rotate the rotor by hand so
  `BaselineRaw mod 10923` lands roughly in 0-2730 raw before that run.
- Flash `builds/control-a5-offset7971-n2048-20260720/jigmotor_control.hex`
  (SHA-256 `D5EE4DAFCFC63832421EB230973DDA5BED4BDA3CB503292FAA0F633A26F81C79`,
  identical source to round 1, re-tagged to commit `5bfd8ce`).

## A5.6 — Confirmation and lock

Per the A5.5 merge decision above, this batch is files `A5 test 6.txt` ..
`A5 test 10.txt` — the same hardware session closes A5.5 and produces A5.6's
required second batch.

- [ ] Capture a second independent 10-run batch including cold start.
- [ ] Compare cold/warm, first/second and between-batch means.
- [ ] Document within-window and across-run RawAngle limits from 20 valid runs.
- [ ] Explain any PWM-phase, drift or distribution dependency.
- [ ] Lock RawAngle stability and retain only a small health monitor later.

A5.6 gate: **PENDING** — awaiting round 2.

## Phase-level exit rule

Do not advance after a failed gate by changing multiple variables. Preserve
the failing raw evidence, classify transport/timing/PWM/mechanical/controller
causes, and modify only the responsible layer under a new profile identity.
