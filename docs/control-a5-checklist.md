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

- [ ] Keep the same motor/mount; no removal during the batch.
- [ ] Capture five files with two physical runs each.
- [ ] Cover four electrical start quadrants.
- [ ] Include one first run after at least 15 minutes powered off.
- [ ] Confirm exact A5 manifest/config on every independent boot.
- [ ] Achieve 10/10 hard structural validity.
- [ ] Review statistical investigation bands without filtering raw evidence.

A5.5 gate: **PENDING**.

## A5.6 — Confirmation and lock

- [ ] Capture a second independent 10-run batch including cold start.
- [ ] Compare cold/warm, first/second and between-batch means.
- [ ] Document within-window and across-run RawAngle limits from 20 valid runs.
- [ ] Explain any PWM-phase, drift or distribution dependency.
- [ ] Lock RawAngle stability and retain only a small health monitor later.

A5.6 gate: **PENDING**.

## Phase-level exit rule

Do not advance after a failed gate by changing multiple variables. Preserve
the failing raw evidence, classify transport/timing/PWM/mechanical/controller
causes, and modify only the responsible layer under a new profile identity.
