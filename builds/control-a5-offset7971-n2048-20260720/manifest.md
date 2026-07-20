# CONTROL A5 activation build (A5.4)

Status: **BUILD/CONTRACT VALIDATED — NOT YET HARDWARE TESTED (A5.5 pending)**
Built: 2026-07-20

## Identity

| Field | Value |
| --- | --- |
| App mode | `MOTOR_CONTROL` |
| Profile | `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1` |
| Parent profile (embedded, unchanged) | `CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1` |
| Electrical offset | 7971 raw |
| Build source ID embedded in ELF | `29856e6dc8e1-dirty` |
| Link size | text=58,832 data=96 bss=175,312 bytes |

The `-dirty` source identity is retained honestly; other worktree changes
existed when this binary was built. The artifact hash is the authoritative
identity, not an assumed clean-commit rebuild.

## What changed vs the A4B rollback baseline

Single variable at the app-identity layer: `CONTROL_A5_CAPTURE_INTEGRATION_ENABLED`
and `CONTROL_A5_PROFILE_ACTIVATION_ACK` flipped 0->1, and `JIG_APP_PROFILE_ID`
in `app_mode.h` switched from the A4B string to the A5 string. No A4B
trajectory/timing/gate constant changed; `ControlRunA5()` calls the exact same
`ControlRunAlignment()` used by the frozen A4B path before running the new
2048-sample static MA600 raw-angle capture.

## SHA-256

```text
1D005A32B741E083406EE6AAE64A2DBDF250650F2A1EA6DF9815AF252325F367  jigmotor_control.elf
0492D9F0E56C37049DF6F172A57CCB192E63FBC24A0153674BDE1104E56DD265  jigmotor_control.hex
```

## Verification performed (software/build only)

- Full contract suite: 23/23 PASS, including the four A5-specific tests and
  the updated `test_control_alignment_contract.ps1` /
  `test_dual_image_contract.ps1`.
- Clean Control Debug and Release builds: 0 errors, 0 warnings.
- `nm`/`strings` isolation: Control ELF contains `ControlA5_CaptureStaticWindow`
  and the A5 profile string (plus the expected embedded A4B `ParentProfile`
  string); Measurement ELF contains neither the A5 profile string nor any
  `ControlA5_` symbol.
- Static `-fstack-usage`: the new `ControlA5_CaptureStaticWindow` frame is
  120 bytes; `ControlRunAlignment` was inlined into `ControlRunA5` (984-byte
  combined frame). A4B's own hardware-measured peak on this 6144-byte task
  stack was ~1600 bytes (4544 bytes free); the new path adds a bounded few
  hundred bytes on top, leaving stack headroom far above the 1 KiB floor.
  This is a static estimate; `ControlStackHighWaterWords` from
  `CONTROL_A5_RUNTIME` on real hardware is the authoritative number (A5.5).
- Heap: `configTOTAL_HEAP_SIZE` unchanged at 102,400 bytes; the firmware's
  own `ControlA5_CaptureResourcesInit()` fails closed if free heap after the
  24,576-byte allocation would drop below 64 KiB. Nominal arithmetic from the
  A4B hardware baseline (91,688 - 24,576 = 67,112 bytes) clears the floor with
  3,112 bytes of margin. `FreeHeapAfterAllocation` on real hardware is the
  authoritative number (A5.5).

## What this build has NOT proven

No physical run has been made with this image. A5.5 (hardware pilot: five
files, two runs each, four electrical quadrants, one cold start after 15+
minutes off) is the next required step before any RawAngle stability claim.

## Rollback

If A5.5 fails, flash `builds/control-a4b-offset7971-20260720/jigmotor_control.hex`
directly; do not attempt to "disable" A5 by rebuilding with the flags reverted
inside this same commit lineage without re-running the full suite and
re-hashing.
