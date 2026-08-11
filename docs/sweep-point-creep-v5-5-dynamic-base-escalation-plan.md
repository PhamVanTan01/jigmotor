# V5.5 — dynamic BASE-to-EXTENDED budget escalation

Date: 2026-08-06

Status: IMPLEMENTED / SOFTWARE VERIFIED — HARDWARE PILOT PENDING

## 1. Decision

V5.4a has answered the missing mechanism question. The next controlled change is **not** a larger
budget for all 360 points and is **not** a new motor step profile. V5.5 keeps the V5.4 motion law,
but lets a point initially classified as `BASE` continue to the already validated `EXTENDED` hard
cap only when that same point actually consumes the 220-raw BASE allowance and is still outside the
deadband.

```text
initial |gap| <= 200 raw -> BASE primary budget 220 raw
    success before/equal primary budget -> stop; no escalation
    still outside deadband at primary exhaustion -> escalate to hard cap 320 raw

initial |gap| > 200 raw -> EXTENDED hard cap 320 raw (unchanged)
```

This is targeted by live response/budget exhaustion. It does not use angle, point index, motor ID or
a historical whitelist.

## 2. Evidence from V5.4a

Usable official traces from the two P03/JIG7 remounts show:

| Trace family | Evidence | Interpretation |
|---|---|---|
| BASE budget exhausted immediately after fine latch | point 8: 224 raw coarse command, 0 fine commands, final gap -57 raw | initial-gap classification underestimates the command required |
| BASE budget exhausted after some fine work | point 9: 60–92 raw of fine commands, final gap -17 to -31 raw | fine response is positive and the endpoint is marginal |
| 4-raw fine response | net response 33.3–53.9%; 76 commands, mean directed response 1.93 raw/command | response is lossy/noisy but not globally zero |
| Safety | no jump, recross or recovery failure in the evaluated V5.4a sweeps | safe to test accounting/cap escalation without changing step or power |

The remount02 file has a host/log-stream hole in official run 3 (`DATA` 219–294 and part of point
telemetry are missing). That run is excluded from NL/repeatability statistics. Its intact `END` and
point-9 summary support only the bounded mechanism diagnosis; no motion constant is calibrated from
the missing interval.

## 3. Why this phase precedes 16→8→4 tuning

The trace does not show a universal near-zero response to every 4-raw command. Four complete point-9
traces make net progress and stop only 1–15 raw outside the ±16-raw deadband. The single zero-fine
trace never received a fine command because the common total budget had already been consumed.

Therefore the smallest causal experiment is to separate **initial budget class** from **final hard
cap** for BASE points. A staged 16→8→4 response-aware profile remains the next branch only if points
still fail after reaching the 320-raw cap.

## 4. Locked invariants

V5.5 must not change:

| Item | Locked value |
|---|---:|
| Coarse step | 16 raw |
| Fine entry / fine step | 64 raw / 4 raw |
| Deadband | 16 raw |
| BASE primary budget | 220 raw |
| EXTENDED / V5.5 hard cap | 320 raw |
| Power | 1.0 |
| Jump threshold | 96 raw |
| Recovery budget / guard | 64 raw / 17 iterations |
| Reversal limit | one |
| Trace storage | one 100-entry buffer per sweep |

Also frozen:

- quintic ramp, settle cadence, MA600 acquisition and continuous unwrap context;
- fine latch, command clamp-to-gap, jump-before-crossing classification and recovery ordering;
- B0-B compatibility wrapper and both B0-B approach legs;
- DATA/Error/NL/harmonic formulas, point grid and eligibility rules;
- no UART formatting or transmit operation inside `CaptureSweep()`.

## 5. Firmware contract

Add a default-off nested feature:

```c
#define ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION 0
```

Rules:

1. V5.5 requires `ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING=1`.
2. V5.5 and telemetry-only V5.4a are mutually exclusive experimental identities.
3. V5.4 and V5.4a remain independently buildable and byte-for-byte motion-compatible with their
   frozen artifacts.
4. V5.5 uses:

```text
SweepPointCreepProtocol=ADAPTIVE_BASE_TO_EXTENDED_ESCALATION_UNIVERSAL_FINE_LANDING_V2
BudgetEscalationProtocol=BASE_EXHAUSTION_TO_EXTENDED_CAP_V1
FineLandingProtocol=UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1
TracePolicy=FIRST_HARD_CAP_BUDGET_OR_INTEGRITY_FAILURE_V1
```

5. A BASE point receives a primary budget of 220 raw and an effective hard cap of 320 raw. It is
   counted as escalated only if its issued correction exceeds 220 raw.
6. EXTENDED points keep 320 raw and are never counted as BASE escalation.
7. BASE uses the existing 81-iteration guard while V5.5 is enabled, sufficient for the 320-raw hard
   cap with a 4-raw latched fine step. No extra recovery iteration is granted.
8. The bounded trace locks on the first ordinary hard-cap `BUDGET_EXCEEDED` or the existing first
   integrity failure. This covers both fine and no-fine residual failures.

## 6. Telemetry

V5.5 advances `SWEEP_CREEP_CONFIG` and `SWEEP_CREEP_POINT` to schema 8. Older schemas remain
parseable.

CONFIG adds:

- `BudgetEscalationProtocol`;
- `BasePrimaryBudgetRaw`;
- `BaseHardBudgetRaw`;
- `BaseEscalatedMaxIterations`.

POINT adds:

- `PrimaryBudgetRaw`;
- `HardBudgetRaw`;
- `BudgetEscalated`;
- `EscalationCorrectionRaw = max(TotalCorrectionRaw - PrimaryBudgetRaw, 0)` for BASE, otherwise 0.

END adds:

- `SweepPointCreepBaseEscalationAttempted`;
- `SweepPointCreepBaseEscalationSucceeded`;
- `SweepPointCreepBaseEscalationFailed`;
- `SweepPointCreepBaseEscalationCorrectionRaw`.

## 7. Software verification

Create `scripts/test_sweep_point_creep_v5_5_contract.ps1` and verify:

- nested feature guards and V5.4a/V5.5 exclusion;
- distinct protocol, escalation and trace-policy IDs;
- BASE primary 220 and hard cap 320; EXTENDED remains 320;
- V5.5 BASE and EXTENDED both use the existing 81-iteration V5.4 guard;
- no point-index/angle/motor lookup enters motion selection;
- coarse/fine step, deadband, power, jump and recovery constants are unchanged;
- remaining hard-cap failures retain a bounded first-failure trace;
- schema-8 telemetry and backward-compatible MATLAB parsing;
- `CaptureSweep()` remains UART-silent and B0-B keeps exactly two NULL-profile wrapper calls;
- default, V5.3, V5.4, V5.4a and V5.5 feature configurations compile;
- full PowerShell regression and Release build pass.

## 8. Hardware pilot

Device: P03/JIG7, no remount during the batch.

Run one FAST3 batch:

- 1 precondition;
- 3 official;
- logger must retain all 360 DATA points for every official run. Any missing/concatenated interval is
  a capture-pipeline failure and invalidates the batch for NL comparison.

Hard gates:

- precondition valid and `OfficialValid=3/3`;
- acquisition/transport clean;
- recovery failure, recross and stick-slip jump all zero;
- stack high-water at least 768 words;
- `SweepPointCreepIntegrityValid=1` for all four cycles.

Mechanism gates against the matched V5.4a baseline:

- BASE hard-cap `BudgetExceeded` reduced by at least 80%; reference mean is 55–63 per official
  sweep across the two V5.4a remounts;
- at least 90% of attempted BASE escalations succeed;
- point 8/9 family either reaches ±16 raw or, if it still fails, provides the first hard-cap trace;
- EXTENDED hard-cap behavior is reported separately and must not be disguised as BASE success;
- total correction and motor-active duration increase no more than 15% versus the matched V5.4a
  batch unless all extra use is explained by successful escalations.

Measurement gates:

- compute Robust NL, RMS_AC, A36 and full 360-point curve from 3/3 complete official runs;
- within-batch Robust-NL CV ≤ 5.7%; target is not a particular scalar NL mean;
- compare centered full-curve correlation/RMSE and top-5/bottom-5 locations against V5.4a;
- motion and NL remain separate verdicts.

## 9. Decision after V5.5

- **Escalation succeeds and integrity/NL remain stable:** promote the motion candidate to a second
  remount, then one second product.
- **BASE still reaches the 320 hard cap with low 4-raw response:** create V5.6 response-aware
  16→8→4 landing; do not raise the cap again.
- **Only initial EXTENDED points remain:** diagnose their first hard-cap trace separately; do not
  increase all budgets.
- **Time/heat exceeds the gate:** stop and optimize command efficiency before any wider test.
- **Any jump/recross/acquisition regression:** reject V5.5 and return to the frozen V5.4 artifact.

## 10. Definition of Done

- [x] causal branch selected from real V5.4a step trace;
- [x] plan written before the V5.5 motion change;
- [x] source/telemetry implemented behind a default-off flag;
- [x] dedicated contract and full regression pass;
- [x] FAST3 Release artifact packaged and source defaults restored;
- [ ] one complete P03/JIG7 hardware batch analyzed.
