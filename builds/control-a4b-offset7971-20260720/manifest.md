# CONTROL A4B rollback baseline

Status: **HARDWARE VALIDATED — PRESERVED FOR A5 ROLLBACK**  
Preserved: 2026-07-20  
Artifact build time: 2026-07-20 12:01:43 (Asia/Bangkok)

## Identity

| Field | Value |
| --- | --- |
| App mode | `MOTOR_CONTROL` |
| Profile | `CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1` |
| Electrical offset | 7971 raw |
| Build source ID embedded in ELF | `29856e6dc8e1-dirty` |
| ELF size | 95,572 bytes |
| HEX size | 145,575 bytes |

The `-dirty` source identity is retained honestly because other worktree
changes existed when this binary was built. The artifact hash, not a rebuild
from an assumed clean commit, is the authoritative rollback identity.

## SHA-256

```text
C3817E2A589035FB10996F08C033F25372533A48EA2E7455166BF35249E1CDE0  jigmotor_control.elf
858A17A1E22CCFAD6B92B0AA1A15533D25529D0611882E1F22728AF4CBF57186  jigmotor_control.hex
```

The copied artifacts were independently re-hashed after preservation and
matched `SHA256SUMS.txt` exactly.

## Hardware evidence

This is the A4B binary used before and during the saved A4B log batches:

- first batch: 10/10 result/contract pass;
- repeat batch after at least 15 minutes: 10/10 result/contract pass;
- combined: 20/20 structurally valid;
- all four electrical start quadrants covered;
- final-offset mean 7958.95 raw, SD 38.76 raw, range 125 raw;
- maximum ramp creep 60 raw;
- maximum sample step 0.577 degrees, below the 0.824-degree guard;
- no deadline, retry, transport, jump-reject or failed-sample event;
- every required capture succeeded.

## Rollback procedure

1. Flash `jigmotor_control.hex` from this directory; do not rebuild it.
2. At boot/run, verify the A4B profile string above.
3. Verify `SeedOffsetRaw=7971` in `CONTROL_A4_ARMED`.
4. Run one safe smoke alignment and require `Result=OK` with clean health.

This baseline is not a generic calibration for a remounted motor. Offset 7971
is valid for the tested motor/mount state; removal or relative remounting
requires recalibration.

