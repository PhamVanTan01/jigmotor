# V5.4a-DIAG — first fine-budget failure trace

Date: 2026-08-06

Status: IMPLEMENTED / SOFTWARE VERIFIED — HARDWARE DIAG PENDING

## 1. Decision

V5.4 has passed the hard motion-integrity gates on two P03/JIG7 remounts, including point 26 and
point 66 at 8/8 cycles each. It must not be promoted yet because the effectiveness gate remains
systematically false:

- remount01: 157 fine-landing failures in three official sweeps;
- remount02: 148 fine-landing failures in three official sweeps;
- 48 failed points are shared between the two remounts;
- 21 points fail in all 6/6 official sweeps;
- failures are concentrated at `Point mod 10 = 6..9`.

The current V5.4 trace policy locks the single step buffer only for an integrity failure. Ordinary
`BUDGET_EXCEEDED` remains valid diagnostic data, so the real logs above contain
`SweepPointCreepTracePoint=-1` even when `FineLandingFailed>0`.

V5.4a-DIAG changes only which completed point is retained in the existing bounded trace buffer. It
does not change motor motion or the NL measurand.

## 2. Diagnostic question

Capture the first point in each sweep satisfying:

```text
FineLandingAttempted == 1 && Result == BUDGET_EXCEEDED
```

The resulting `SWEEP_CREEP_STEP` sequence must distinguish:

1. **budget consumed before fine entry** — no or very few fine commands remain;
2. **fine step has insufficient response** — repeated 4-raw commands produce little/no settled
   encoder movement;
3. **fine response is effective but budget is marginal** — consistent progress stops just outside
   the deadband;
4. **unexpected integrity event** — if no earlier fine-budget failure exists, retain the existing
   first-integrity-failure fallback.

## 3. Locked invariants

The following V5.4 values and behaviors are frozen:

| Item | Locked value |
|---|---:|
| Coarse step | 16 raw |
| Fine entry | 64 raw |
| Fine step | 4 raw |
| Deadband | 16 raw |
| BASE budget / iteration guard | 220 raw / 56 |
| EXTENDED budget / iteration guard | 320 raw / 81 |
| Power | 1.0 |
| Jump threshold | 96 raw |
| Recovery budget / iteration guard | 64 raw / 17 |
| Reversal limit | one |
| Trace storage | one 100-entry buffer per sweep |

Also frozen:

- `CreepToUnwrappedTargetProfiled()` command, settle, jump and recovery order;
- `WaitForPointSettle()`, MA600 acquisition and continuous unwrap context;
- ramp → settle → creep → official capture cadence;
- B0-B behavior and its `NULL` fine-profile compatibility wrapper;
- DATA/Error/NL/harmonic calculations and eligibility semantics;
- no UART formatting or transmission inside `CaptureSweep()`.

## 4. Firmware contract

Add a nested, default-off flag:

```c
#define ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE 0
```

Rules:

1. V5.4a requires both `ENABLE_SWEEP_POINT_CREEP=1` and
   `ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING=1`.
2. Base V5.4 remains independently buildable with the original trace policy.
3. V5.4a reports:

```text
TracePolicy=FIRST_FINE_BUDGET_OR_INTEGRITY_FAILURE_V1
```

4. The motion protocol IDs remain unchanged because motion is unchanged:

```text
SweepPointCreepProtocol=ADAPTIVE_GAP_BUDGET_UNIVERSAL_FINE_LANDING_V1
FineLandingProtocol=UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1
RecoveryProtocol=UNIVERSAL_FINE_SINGLE_REVERSAL_V1
```

5. The first trace candidate locks the buffer. Under V5.4a a candidate is:

```text
(FineLandingAttempted && Result == BUDGET_EXCEEDED)
OR existing V5.4 integrity failure
```

6. If no candidate occurs, `TracePoint=-1` and no step rows are emitted.
7. Existing CONFIG/POINT schema 7 and STEP schema 2 remain sufficient because `TracePolicy`
   explicitly versions the changed selection semantics.

## 5. Software verification

Create a dedicated contract test and verify:

- flag dependency guards;
- base V5.4 and V5.4a trace IDs remain distinct;
- the fine-budget predicate requires both `FineLandingAttempted` and exactly
  `NL_CREEP_BUDGET_EXCEEDED`;
- timeout and ordinary no-fine budget failures do not become V5.4a trace candidates;
- all legacy integrity candidates remain covered;
- storage remains O(1), never `360 x trace capacity`;
- `CaptureSweep()` remains UART-silent;
- all locked motion constants and call arguments are unchanged;
- default, V5.3, V5.4 and V5.4a feature configurations compile;
- full PowerShell regression passes except an explicitly expected FAST3/default-mode assertion.

## 6. Hardware validation

Build one FAST3 batch for P03/JIG7:

- 1 precondition;
- 3 official;
- no remount during the batch.

One batch is sufficient for this diagnostic because V5.4 already showed the same failure family on
two independent remounts. This phase is not a repeatability qualification.

Required result:

- batch completes and 3/3 official remain valid;
- recovery failure, recross and stick-slip jump remain zero;
- `TracePoint >= 0` in every sweep that has `FineLandingFailed>0`;
- traced point has `FineLandingAttempted=1` and `Result=BUDGET_EXCEEDED`;
- `TraceCount` equals the number of emitted `SWEEP_CREEP_STEP` rows for that point;
- step rows reconstruct `TotalCorrectionRaw`, `FineIterations`, `FineCorrectionRaw` and final gap.

## 7. Decision after the log

- **Budget mostly consumed before fine entry:** V5.5 must reserve a bounded landing allowance or
  change the coarse-to-fine schedule; do not simply raise the global budget.
- **4-raw commands repeatedly produce near-zero motion:** choose a response-aware landing profile,
  initially evaluating `16 → 8 → 4`; do not keep a universal fixed 4-raw step.
- **4-raw response is healthy and final gap is only marginally outside ±16:** a narrowly bounded
  landing reserve may be justified, followed by a fresh repeatability test.
- **Integrity regresses:** stop the effectiveness branch and fix safety before any V5.5 tuning.

No V5.5 motion change is authorized by this plan; V5.4a-DIAG exists only to obtain the missing
step-level evidence.

## 8. Definition of Done

- [x] plan recorded before implementation;
- [x] nested diagnostic flag and dependency guard implemented;
- [x] trace selection changed only under V5.4a;
- [x] V5.4 base trace behavior preserved;
- [x] dedicated contract test passes;
- [x] complete regression suite passes;
- [x] Release FAST3 artifact packaged with ELF/HEX/MAP, manifest and SHA256;
- [x] source restored to default-off and 10-official mode after packaging;
- [ ] one P03/JIG7 hardware batch captured and analyzed.
