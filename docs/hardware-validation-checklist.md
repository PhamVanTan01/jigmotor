# Architecture Migration Hardware Validation

Use the same motor/jig setup and preserve the complete UART log for every run.
The firmware's nonlinear policy remains `WHOLE_SYSTEM_REPORT_ONLY_V1`; this
checklist validates the implementation, not a product-quality limit.

Measurement-status note (2026-07-14): clean acquisition and local settle are
not sufficient for repeatability qualification. Reviewed Phase-3A logs show
that point-256 position error dominates closure, and closure passes only 3/6
for P05/JIG3 and 0/3 for P03/JIG1 at the pilot 0.20-degree limit. Complete
`phase3b0-closure-measurement-review.md` before promoting canonical validity.
The separately controlled exploratory 10-run study is tracked in
`preconditioned-10run-checklist.md`; it is not a qualification or validity
promotion.

## Canonical jig identity

Identify the jig from the MCU UID written in `META`, not from the operator's
log filename:

| Physical jig | MCU UID |
| --- | --- |
| JIG1 | `003C00273234470438353535` |
| JIG2 | `0025002C3234470438353535` |
| JIG3 | `004C003A3034510B31363339` |
| JIG4 | `0027002E3234470438353535` |

The firmware table in `Core/Src/nonlinear_test.c` must use this exact mapping.
An unknown UID must remain `UNKNOWN_JIG`; never infer a jig number from a file
name.

## Phase-1 configuration audit

`CONFIG` must carry `MCU_UID`, `JigID`, and `JigKnown` so a configuration
failure that occurs before `META` remains self-identifying.

| Jig | Audit state | ZERO | DIR | FILT | STATUS | PRT | RMAPID | Correction | CRC32 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JIG1 / `003C00273234470438353535` | Observed 2026-07-13 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG2 / `0025002C3234470438353535` | Observed 2026-07-13 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG3 / `004C003A3034510B31363339` | Observed 2026-07-13 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG4 / `0027002E3234470438353535` | Provisional observation 2026-07-24; locked smoke pending | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |

Both rows were supplied with explicit operator jig labels from the audit build
that preceded self-identifying CONFIG records. Their profiles match exactly.
`POLICY_A_LOCKED_V1` therefore locks these values by physical MCU UID and emits
`AuditFieldsLocked=1`. An unknown UID, missing expected profile, or mismatch in
ZERO/DIR/FILT/STATUS/PRT/RMAPID/correction CRC rejects motor enable with E510
and a field-specific `RejectReason`.

Phase 1 is closed for JIG1/JIG3 by passing locked, self-identified CONFIG
records. JIG2 requires the same locked smoke record before reuse in production
scope.

The dedicated 1807/7PP engineering profile supports two explicitly locked
sensor identities. JIG1..JIG3 retain register `0x1F = 0x3C`, observed
repeatedly on JIG3 on 2026-07-23; that is the original MA600 `PRODUCTID`
default (60 decimal). JIG4 reported `0x1F = 0x00` on 2026-07-24, matching the
MA600A `RMAPID/SUFFIXID` default. The firmware selects the exact expectation
by physical MCU UID; it does not accept either value generically and does not
weaken the remaining Policy-A checks.

The first JIG4 `BOOT_SMOKE` capture also returned a one-shot
`ZERO=0x00DB`, followed by repeated `ZERO=0x0000` records without any
configuration write. Configuration reads therefore require two consecutive
identical full snapshots, with a maximum of three attempts. A single startup
transient may be displaced by two stable reads; continuing or alternating
values produce `CONFIG_READ_FAILED` and keep the motor disabled.

The Phase-2B canonical-shadow run matrix is tracked separately in
`docs/phase2b-shadow-checklist.md`.

## Before testing

1. Build and flash the new Debug image.
2. Without pressing the test button, capture the `ConfigContext=BOOT_SMOKE`
   CONFIG line. Require the locked policy, known expected profile, both startup
   self-test fields equal to 1, and `RejectReason=NONE`.
3. Confirm boot completes without a controller self-test error.
4. Record the firmware BuildID and MCU/Jig identity.
5. Keep the motor mechanically safe to stop if direction or tracking is wrong.

## Healthy run

1. Run P03 on JIG1 three times using the same cooldown protocol as
   `p03-jig1.txt`.
2. Require `MeasurementValid=1`, `TrackingValid=1`, `AcquisitionResult=OK`, and
   `END ... Status=VALID` for every accepted sweep.
3. Require zero failed acquisition samples and investigate any transport error,
   retry, or jump-reject count.
4. Confirm the legacy nonlinear result stays within expected run-to-run variation
   of the historical 3.31 deg mean; do not treat that value as a quality limit.
5. Check the `RUNTIME` line. Confirm free heap is positive and the test-task stack
   high-water mark has practical margin after the full log is printed.
6. Confirm motor output is disabled after completion and `Motor OK` appears only
   after a valid END record.

## Failure behavior

1. Exercise the build-time MA600 fault-injection test on a controlled test build.
   Require an invalid sample, no unwrap-state advance, and no `Motor OK`.
2. If a safe mechanical method is available, prevent gross shaft tracking during
   a sweep. Require `TrackingValid=0`, `MeasurementValid=0`, an invalid END record,
   `E506`, no legacy `Nonlinear N Angle` numeric line, and no `Motor OK`.
3. During any failure, confirm PWM/relay actuation reaches the safe disabled state
   and an automatic batch does not proceed to another run.

## Endpoint and repeatability gate

1. Do not interpret `SettleValid=1` as closure pass. The current settle target
   tolerance is a gross motion envelope.
2. Compare point-256 `PositionErrorDeg` with canonical `ClosureErrorDeg`; retain
   both even when closure fails.
3. Require equivalent point-0/point-256 approach history in the selected
   protocol.
4. Require whole-window stationary P2P/drift evidence before selecting settle
   limits.
5. For `PERIODIC_MAP_V1`, require closure 3/3 in the diagnostic pilot, then
   10/10 in the fixed no-remount protocol. For
   `FIRST_PASS_TRAJECTORY_V1`, keep closure as an individual response metric
   with its own repeatability rule. Never convert closure failures into a pass
   by averaging.
6. Separate cold-start, preconditioned, remount, and different-day results.
7. A MA600A-feedback trim is a control diagnostic only; it is not an
   independent sensor-accuracy validation.

### Phase-3B0-A passive hold run checklist

- [x] Software/host contract and Debug/Release builds pass.
- [ ] Use the same final HEX checksum for all three no-remount sweeps.
- [ ] META contains `ClosureProbeEnabled=1`,
  `ClosureProbeProtocol=CLOSURE_HOLD_V1`, and `ClosureProbeOfficial=0`.
- [ ] Exactly four `CLOSURE_PROBE` stages exist: `INITIAL`, `HOLD_50`,
  `HOLD_100`, and `HOLD_200`.
- [ ] Every stage has `Point=256`, identical `CommandRaw` and `Power`,
  `AcquisitionResult=OK`, and `Valid=1`.
- [ ] Actual capture start/end times are monotonic; each hold starts no
  earlier than its nominal 50/100/200 ms time.
- [ ] INITIAL closure exactly matches the existing Point-256 canonical
  baseline and is not replaced by a held value.
- [ ] `CLOSURE_PROBE_RESULT` reports `Complete=1`, `ValidStages=4`,
  `PostTurnTimingComparable=0`, and `Status=VALID`.
- [ ] SPI failures, jump rejects, metadata invalid counts, skipped slots, and
  timing overruns are zero unless separately investigated.
- [ ] Save the analyzer CSV columns for all four closure values, 50/100/200
  deltas, and initial/200-ms window P2P/drift.
- [ ] Confirm no UART truncation, HardFault, stack overflow, unexpected next
  batch run, or delayed motor disable.
- [ ] Do not mark closure passed by averaging stages or runs; classify the
  observed time response before changing settle/control/approach behavior.

## Release gate

Do not enable DMA acquisition or introduce a nonlinear pass/fail threshold from
this migration. First archive the new logs, compare timing/measurements, and close
all healthy-run and failure-behavior checks above.
