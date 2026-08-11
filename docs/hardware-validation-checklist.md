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
| JIG4 (1807 7PP jig) | `0027002E3234470438353535` |
| JIG4 | `0049003A3034510B31363339` |
| JIG5 | `001D00283234470438353535` |
| JIG6 | `005100323235511835383831` |
| JIG7 | `004600323235511835383831` |

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
| JIG4 (1807 7PP jig) / `0027002E3234470438353535` | Provisional observation 2026-07-24; locked smoke pending | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG4 / `0049003A3034510B31363339` | Corrected 2026-07-27 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG5 / `001D00283234470438353535` | Observed 2026-07-27 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG6 / `005100323235511835383831` | Confirmed 2026-07-28 | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |
| JIG7 / `004600323235511835383831` | **Single read, 2026-07-28** | `0x0000` | `0x00` | `0x05` | `0x00` | `0x00` | `0x00` | 0 non-zero | `0x190A55AD` |

JIG1/JIG2/JIG3 were supplied with explicit operator jig labels from the audit
build that preceded self-identifying CONFIG records. Their profiles match.
JIG4 is a new PCB with the MA600A sensor (same protocol/registers as
JIG1-3, different physical board) -- its first boot-smoke read
(`ZERO=0x00D5,FILT=0x0C,PRT=0x80`) was pre-calibration/transient, not this
board's real profile. A physical MA600 swap on the same board/MCU on
2026-07-24 then led to locking `ZERO=0x00E7`, which was itself another
premature lock: it was corrected on 2026-07-27 to `ZERO=0x0000` after 33
consecutive gated reads (`PRECONDITION_PRE_MOTOR` + `BATCH_PRE_MOTOR`, zero
exceptions) across three independent test-31 sessions on this exact
board/sensor (P03, P02, P06 -- all captured under `PolicyABypassOverride=1`
while the stale `0x00E7` lock was gate-rejecting every run). `ZERO=0x0000`
matches JIG1/JIG2/JIG3/JIG5 exactly. `FILT`/`PRT`/`STATUS`/`RMAPID` were
already identical to JIG1-3 throughout and are unchanged. `ZERO` is the
per-unit absolute-position calibration constant baked into each sensor IC,
not a shared sensor-configuration setting, so re-locking it on a sensor
swap (or correcting a bad lock) is intentional (`POLICY_A_LOCKED_V1` must
not silently accept a later configuration change); it does not weaken
Policy A for JIG1-3/JIG5. No separate sensor-configuration stratum concern
remains; JIG1/JIG3/JIG4/JIG5 numeric comparisons are not blocked by this.

JIG5 is a second new control board (different MCU/PCB) carrying, at
bring-up time, the same physical MA600A sensor JIG4 had -- registered as
its own entry rather than replacing JIG4 (operator's choice; JIG4's board
and locked profile are untouched). This swap was the diagnostic that
resolved JIG4's earlier instability: `BOOT_SMOKE` (the very first read
immediately after power-up, read-only, never gates anything) varied across
two full power cycles on this same new board (`0x007D` then `0x0080`), but
`PRECONDITION_PRE_MOTOR` (read later in boot, after the home routine) came
back `ZERO=0x0000` with zero exceptions across 3 reads then 6 reads on the
second power cycle. Since a different board reproduced the same
"boot-smoke unreliable, later read stable" pattern with the same sensor,
the earlier instability traces to sensor power-on settling time, not a
board-specific connection fault -- do not lock a profile from a
`BOOT_SMOKE` read alone; always confirm against the later gated read
across a real power cycle first.
JIG6 is a new control board registered 2026-07-28 from a bare `MCU_UID` read
(the STM32 UID is factory-lasered, independent of any sensor wiring) taken
*before* the mechanical assembly/MA600 sensor was attached -- the first
CONFIG line read all-`0xFF` across ZERO/DIR/FILT/STATUS/PRT/RMAPID
(`CorrNonZeroCount=32/32`), the standard signature of an unconnected SPI bus,
not a locked profile. The placeholder profile (predicted from JIG1-5, all
identical) was confirmed the same day once the sensor was physically
attached: `p03-jig6-test-32.txt` shows `ZERO=0x0000` with zero exceptions
across 7 gated reads (`PRECONDITION_PRE_MOTOR` + 6x `BATCH_PRE_MOTOR`,
`ConfigValid=1`/`RejectReason=NONE` throughout) -- the placeholder needed no
correction.

JIG7 is a new control board registered 2026-07-28 from the same die
batch/wafer lot as JIG6 (`MCU_UID_WORD1`/`WORD2` identical: `0x32355118`,
`0x35383831` -- only `WORD0` differs, `0x00460032` vs JIG6's `0x00510032`,
expected for STM32 UIDs from the same lot, not a misread). Unlike JIG6's
first read, this board's sensor was already attached: the first CONFIG
line read a clean, plausible profile (`ZERO=0x0000`, matching every other
known jig), rejected only with `EXPECTED_CONFIG_PROFILE_MISSING`
(unregistered UID) rather than a garbage/SPI-fault reason. Still only one
read -- registered directly from it (not a blind placeholder like JIG6's
pre-assembly entry), but per the same discipline that caught JIG4's three
premature locks, this needs re-verification against several more gated
reads across a real power cycle before being fully trusted.

`POLICY_A_LOCKED_V1` therefore locks these values by physical MCU UID and emits
`AuditFieldsLocked=1`. An unknown UID, missing expected profile, or mismatch in
ZERO/DIR/FILT/STATUS/PRT/RMAPID/correction CRC rejects motor enable with E510
and a field-specific `RejectReason`.

Phase 1 is closed for JIG1/JIG3 by passing locked, self-identified CONFIG
records. JIG2 requires the same locked smoke record before reuse in production
scope.

The dedicated 1807/7PP engineering profile supports two explicitly locked
sensor identities. JIG1/JIG2 retain register `0x1F = 0x3C`, the original
MA600 `PRODUCTID` default (60 decimal). JIG3 also reported `0x3C` during the
2026-07-23 7PP runs, but its sensor was physically replaced on 2026-07-24.
The replacement JIG3 sensor and JIG4 both report `0x1F = 0x00`, matching the
MA600A `RMAPID/SUFFIXID` default. Firmware built after that replacement locks
JIG3 and JIG4 to `0x00` by physical MCU UID; it does not accept either value
generically and does not weaken the remaining Policy-A checks.

Treat JIG3 data from before and after the sensor replacement as separate
fixture revisions. The replacement revision must pass a new locked
`BOOT_SMOKE`, repeatability run, and cross-jig correlation before its results
are combined with the historical JIG3 baseline.

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
