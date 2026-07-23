# CONTROL A5 activation build (A5.4)

Status: **A5.5 HARDWARE PILOT IN PROGRESS — 10/10 structural, quadrant/cold-start coverage incomplete**
Built: 2026-07-20 (rebuilt after the A5.4 commit landed as `ef0025a`)

## Identity

| Field | Value |
| --- | --- |
| App mode | `MOTOR_CONTROL` |
| Profile | `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1` |
| Parent profile (embedded, unchanged) | `CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1` |
| Electrical offset | 7971 raw |
| Build source ID embedded in ELF | `ef0025af801b-dirty` |
| Link size | text=58,832 data=96 bss=175,312 bytes |

The `-dirty` source identity is retained honestly; only untracked hardware-log
and reference files exist in the worktree, no uncommitted change to any file
this build actually compiles from. The artifact hash is the authoritative
identity, not an assumed clean-commit rebuild.

**Provenance note:** the first 10-run hardware pilot (`A5 test 1..5.txt`,
below) was collected against an earlier build of this exact same source,
tagged `29856e6dc8e1-dirty` (the commit immediately before `ef0025a`, which
only added this documentation/checklist -- no line of Control-relevant source
differs). That evidence remains valid; this rebuild simply re-tags the
identical binary to the branch's current tip for any further hardware runs.

## What changed vs the A4B rollback baseline

Single variable at the app-identity layer: `CONTROL_A5_CAPTURE_INTEGRATION_ENABLED`
and `CONTROL_A5_PROFILE_ACTIVATION_ACK` flipped 0->1, and `JIG_APP_PROFILE_ID`
in `app_mode.h` switched from the A4B string to the A5 string. No A4B
trajectory/timing/gate constant changed; `ControlRunA5()` calls the exact same
`ControlRunAlignment()` used by the frozen A4B path before running the new
2048-sample static MA600 raw-angle capture.

## SHA-256

```text
FFF74FF05E726E9E2534ACC683878B2DE2AE52795FAEF7BB0A773FD3FE8836B0  jigmotor_control.elf
D5EE4DAFCFC63832421EB230973DDA5BED4BDA3CB503292FAA0F633A26F81C79  jigmotor_control.hex
```

Previous (still valid, `29856e6dc8e1-dirty`-tagged) hashes, used for the
first 10-run pilot below:

```text
1D005A32B741E083406EE6AAE64A2DBDF250650F2A1EA6DF9815AF252325F367  jigmotor_control.elf  (superseded copy)
0492D9F0E56C37049DF6F172A57CCB192E63FBC24A0153674BDE1104E56DD265  jigmotor_control.hex  (superseded copy)
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

## A5.5 hardware pilot, round 1 (`A5 test 1.txt` .. `A5 test 5.txt`)

10 physical runs (5 files x 2 runs), against the `29856e6dc8e1-dirty`-tagged
build above.

| Metric | Result |
| --- | --- |
| Structural validity (`MeasurementValid=1`) | 10/10 |
| Accepted samples | 2048/2048 every run |
| Retry / transport / jump-reject / failed-sample | 0 across all 10 runs |
| P2P (raw) | 11-16 (band: <=32) |
| Population SD (raw) | 1.63-2.06 (band: <=5) |
| First-to-last drift (raw) | -2 to +6 (band: <=16) |
| Max schedule-error | 74 cycles (~0.44 us) |
| SPI latency | constant 1338 cycles every run |
| ElectricalOffsetRaw (A4 endpoint) | 7914-7996 (range 82 raw = 0.45 deg elec) |

All structural gates and every investigation band are comfortably clear.

**Electrical start quadrant coverage (re-derived from `BaselineRaw mod 10923`
in each `CONTROL_A4_SUMMARY`, not just the final `ElectricalOffsetRaw`, since
A4's drag is designed to erase start-position dependency from the endpoint):**

| Run | Elec. start (deg) | Quadrant |
| --- | ---: | :---: |
| test1 r1 | 262.7 | Q3 |
| test1 r2 | 261.7 | Q3 |
| test2 r1 | 322.6 | Q4 |
| test2 r2 | 260.7 | Q3 |
| test3 r1 | 323.6 | Q4 |
| test3 r2 | 262.8 | Q3 |
| test4 r1 | 141.8 | Q2 |
| test4 r2 | 260.4 | Q3 |
| test5 r1 | 201.9 | Q3 |
| test5 r2 | 260.9 | Q3 |

**Gap: Q1 (0-90 deg elec) was never sampled.** Every run 2 of a file lands
near Q3 (~260 deg) by construction -- it starts wherever run 1's own A5 hold
left the rotor, which A4's drag always parks close to the same electrical
neighborhood. Genuine start diversity only comes from the operator's manual
rotation between files, and this round's five rotations happened to land in
Q3/Q4/Q4/Q2/Q3. Round 2 must deliberately rotate one run's baseline into Q1
(`BaselineRaw mod 10923` roughly 0-2730) before pressing start.

**Still unconfirmed procedurally (not derivable from the log data):**
cold start after >=15 minutes powered off, and continuous same-mount across
the whole batch (the tight 82-raw endpoint spread is consistent with, but
does not prove, no remount).

## What this build has NOT proven yet

RawAngle stability within one static window is now well evidenced (P2P/SD/
drift all comfortably inside the pilot bands, 10/10 structurally valid). The
outstanding A5.5 checklist items are: full four-quadrant coverage (Q1
missing), an explicit cold-start run, and explicit round-2 confirmation that
the mount was never disturbed.

## Rollback

If A5.5 fails, flash `builds/control-a4b-offset7971-20260720/jigmotor_control.hex`
directly; do not attempt to "disable" A5 by rebuilding with the flags reverted
inside this same commit lineage without re-running the full suite and
re-hashing.
