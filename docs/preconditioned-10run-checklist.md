# Preconditioned 10-run repeatability experiment

Status: **software implemented; hardware run pending**

Updated: 2026-07-14

## Fixed protocol

This is an exploratory one-jig repeatability experiment, not temperature
control and not a product/datasheet/ISO acceptance test. The fixture has no
motor temperature sensor, so the controlled quantities are one identical
preconditioning sweep and the motor-off time only.

One button press executes:

1. Cycle 1: one complete normal sweep with `RunRole=PRECONDITION`,
   `RunOrder=0`, and `EligibleForStatistics=0`.
2. Motor off for 120,000 ms. More than 300 ms scheduling overshoot aborts the
   batch before the next motor enable.
3. Cycles 2 through 11: official `RunOrder=1..10`, each separated by the same
   validated 120-second motor-off interval.
4. No cooldown follows official run 10.

The expected duration is about 22 to 23 minutes: ten cooldown intervals plus
eleven full sweeps. Do not remount, move, reflash, reset, or press the button
again during the batch.

## Software checklist

- [x] Ten-run mode is selected (`NL_TEST_REPEAT_10_RUNS=1`).
- [x] Total physical sequence is one precondition plus ten official cycles.
- [x] Precondition uses the same CONFIG gate, zeroing, motion, settle,
  acquisition, feature, shadow, and closure-probe path as an official sweep.
- [x] Precondition is retained as a structured audit record.
- [x] Precondition cannot emit the legacy final average or `Motor OK`.
- [x] Precondition failure aborts before official run 1.
- [x] Cooldown outside 120,000..120,300 ms aborts before another motor enable.
- [x] META carries `CycleOrder`, `RunOrder`, `RunRole`,
  `EligibleForStatistics`, `PreconditionValid`, and both protocol IDs.
- [x] Analyzer rejects inconsistent role/order/eligibility/cooldown records.
- [x] Analyzer excludes `EligibleForStatistics=0` from `-Summary` statistics.
- [x] Positive precondition/official fixture passes.
- [x] Negative eligibility, missing-audit-result, and invalid-cooldown fixtures
  are rejected.
- [x] Debug firmware build passes without compiler warnings.
- [x] Release firmware build passes and final HEX SHA-256 is recorded below.
- [x] All seven host regression scripts pass after the final build.

## Hardware run checklist

- [ ] Use JIG1 and P03 without remounting for the first experiment.
- [ ] Flash one final HEX and record its SHA-256.
- [ ] Start logging before pressing the button and save the complete UART log.
- [ ] Confirm `BATCH ... Status=START`, `PreconditionCount=1`, `RunCount=10`,
  and `TotalCycleCount=11`.
- [ ] Confirm cycle 1 is `PRECONDITION`, `RunOrder=0`, and
  `EligibleForStatistics=0`.
- [ ] Confirm exactly one valid `PRECONDITION_RESULT` and no `Motor OK` for
  cycle 1.
- [ ] Confirm official cycles are exactly `CycleOrder=2..11` and
  `RunOrder=1..10`.
- [ ] Confirm each official META reports `PreconditionValid=1`,
  `CooldownTargetMs=120000`, `CooldownActualMs=120000..120300`, and
  `CooldownValid=1`.
- [ ] Confirm exactly 11 valid structured sweep records, but only 10
  `Motor OK` lines and 10 statistic-eligible records.
- [ ] Confirm final BATCH record reports `Status=COMPLETE`, `RunCount=10`,
  `TotalCycleCount=11`, and `PreconditionValid=1`.
- [ ] Confirm no `COOLDOWN_INVALID`, acquisition/tracking error, UART
  truncation, HardFault, stack overflow, or unexpected motor enable.
- [ ] Preserve the final `RUNTIME` line and verify task-stack margin.

## Analysis gate

- [ ] Run `scripts/analyze_nonlinear_logs.ps1` with `-OutCsv` and `-Summary`.
- [ ] Verify the CSV retains the precondition row for audit but the summary
  count is 10, not 11.
- [ ] Report all ten individual values before calculating mean, standard
  deviation, range, and coefficient of variation.
- [ ] Trend official run order versus RMS/A36/closure/position error to detect
  remaining warm-up drift.
- [ ] Treat every acquisition/tracking/settle failure individually; never turn
  an invalid run into a pass by averaging.
- [ ] Compare closure results separately from repeatability metrics. This
  experiment does not promote the 0.20-degree pilot closure rule to an
  acceptance limit.
- [ ] If official run 1 still differs systematically from runs 2..10, reject
  this preconditioning duration as insufficient; do not discard another run
  after seeing the data.

## Final artifact

- Release HEX SHA-256:
  `4CF8D5DDAADDE753E1850BE389BB4A3447F91E7D8C9289FD1AC9BBD1C58FBB85`
