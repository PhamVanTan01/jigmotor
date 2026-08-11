# V5.7-DIAG — Passive hold after the first V5.5 hard-cap failure

Status: **IMPLEMENTED / READY FOR HARDWARE TEST** (2026-08-10).

Build artifact:
`builds/sweep-point-creep-v5-7-hardcap-hold-diag-fast3-20260810/jigmotor.hex`.

## 1. Why this diagnostic exists

V5.6 proved that inserting an 8-raw MID stage does not improve the difficult
point: on P08/JIG8, MID response efficiency was about 200 permille worse than
the preceding COARSE-16 tail, while point 308 still failed in 8/8 cycles.
Therefore, the next useful question is no longer “which smaller step should be
tried?” but:

1. does the rotor continue to move toward the target after V5.5 stops issuing
   commands; or
2. has the rotor reached a static command/torque/friction equilibrium that
   additional wait time will not correct?

This build answers that question without changing the V5.5 motion algorithm.

## 2. Locked invariants

- V5.5 dynamic BASE escalation remains the motion under test.
- V5.4 universal fine landing and all V5.5 budgets, steps, power, settle rules,
  crossing/recovery guards, and target definitions remain unchanged.
- V5.6 three-stage landing is disabled.
- Only the first `NL_CREEP_BUDGET_EXCEEDED` point in the 0..359 analysis grid
  is selected per sweep; memory usage remains O(1).
- The actual stored motor command reached by V5.5 is held exactly as-is.
- The hold routine does not call `Motor_SetElectricalPos`, ramp, creep, PID,
  PWM, or UART output.
- Official `DATA` and shadow data for the selected point are frozen before the
  passive hold begins.
- Diagnostic acquisition counters are isolated from the frozen schema-v5
  acquisition counters.

## 3. Measurement protocol

Protocol ID:
`FIRST_HARD_CAP_PASSIVE_HOLD_0_10_25_50_100_200MS_V1`.

After the first hard-cap candidate is captured, MA600 is sampled at nominal:

| Sample | Hold time |
|---:|---:|
| 0 | 0 ms |
| 1 | 10 ms |
| 2 | 25 ms |
| 3 | 50 ms |
| 4 | 100 ms |
| 5 | 200 ms |

The predeclared material-change threshold is 9 raw, equal to
`NL_POINT_SETTLE_ERROR_RAW`. The firmware preserves two intervals separately:

- `PreHoldGapReductionRaw`: last settled sample returned by V5.5 creep to the
  post-DATA 0 ms hold sample. This catches fast relaxation while the official
  and shadow point windows are being acquired;
- `GapReductionRaw`: post-DATA hold sample 0 ms to 200 ms;
- `TotalGapReductionRaw`: V5.5 creep-final sample to hold 200 ms.

The mechanism classification uses `TotalGapReductionRaw`, not only the late
hold window. This prevents a fast relaxation during DATA acquisition from
being mislabeled static. `DominantInterval` reports whether the material
change occurred in `PRE_HOLD_DATA_WINDOW`, `PASSIVE_HOLD_WINDOW`, both, or was
distributed across two individually sub-threshold intervals:

- `RELAXES_TOWARD_TARGET`: total absolute gap decreases by at least 9 raw;
- `DRIFTS_AWAY_FROM_TARGET`: total absolute gap increases by at least 9 raw;
- `STATIC_WITHIN_SETTLE_BAND`: change is smaller than 9 raw;
- `ACQUISITION_INCOMPLETE`: fewer than 6 valid samples;
- `NO_HARD_CAP_CANDIDATE`: V5.5 did not hit a hard-cap failure in that sweep;
- `CANDIDATE_NOT_REACHED`: defensive state if a candidate was latched but its
  frozen point was not reached.

## 4. Telemetry contract

Each sweep emits, after motor motion is stopped:

- one `SWEEP_CREEP_HOLD_CONFIG` record;
- up to six `SWEEP_CREEP_HOLD_SAMPLE` records;
- one `SWEEP_CREEP_HOLD_RESULT` record.

The MATLAB parser and batch analyzer expose these as `HoldConfig`,
`HoldSamples`, `HoldResult`, and `HoldByLabel`. The analyzer reports candidate
count, completeness, classification counts, mean pre-hold/hold/total gap
reduction, mean observed hold drift, and complete rate.

## 5. Statistical status

This build is **diagnostic only**. Every run is forced to
`EligibleForStatistics=0`, including the three cycles labelled OFFICIAL.
Reason: the 200 ms hold at one point changes the cadence of all later points.
Consequently:

- do not approve or reject product NL using this build;
- do not compare its scalar NL directly with the V5.5 production baseline;
- use only the hold records to classify the hard-cap mechanism.

## 6. Hardware test procedure

First batch:

1. Flash the V5.7-DIAG artifact on JIG8.
2. Use P08 and keep the current mounting unchanged for the whole batch.
3. Run the complete FAST3 protocol: 1 PRECONDITION + 3 OFFICIAL-labelled
   diagnostic cycles.
4. Capture the complete UART stream with STM32 UART Flasher v1.10 or newer.
5. Send the raw `.txt` file; do not remove the PRECONDITION cycle.

The first batch is sufficient for a mechanism verdict when at least 3 of 4
cycles latch a candidate, all selected holds have 6/6 valid samples, and at
least 3 classifications agree. If candidate frequency is lower, repeat once
without remounting before changing any firmware parameter.

## 7. Decision after the log

| Dominant result | Interpretation | Next implementation |
|---|---|---|
| `RELAXES_TOWARD_TARGET` | V5.5 stops before passive mechanics settle | Test a bounded dwell/settle confirmation; keep V5.5 commands unchanged |
| `STATIC_WITHIN_SETTLE_BAND` | Stored command maps to a static off-target equilibrium | Do not add wait; investigate command-to-torque phase/bias or a closed-loop terminal correction |
| `DRIFTS_AWAY_FROM_TARGET` | Load-angle/backlash/relaxation moves away after stopping | Investigate approach direction and mechanical state; do not reduce step again |
| Mostly `NO_HARD_CAP_CANDIDATE` | V5.5 happened to pass this batch | No mechanism evidence; repeat the same binary/mount before modifying code |
| Incomplete or mixed | Acquisition or mechanism evidence is insufficient | Fix capture/acquisition or increase independent repetitions, not motion constants |

## 8. Verification completed

- Feature Release build: PASS (`text=93444`, `data=96`, `bss=165624`).
- V5.4 inherited motion contract: PASS.
- V5.5 inherited motion contract: PASS.
- V5.7 passive-hold contract: PASS.
- Host auto-log Python tests, including a stream larger than 1 MB: 6/6 PASS.
- Existing PowerShell contract suites: all pass after updating the closure-probe
  test boundary for the new adjacent passive-hold function.
- MATLAB schema fixture added; runtime MATLAB is not installed on this build PC,
  so the MATLAB test must be rerun on the MATLAB workstation.
- Source feature switches were restored to safe defaults after packaging.
