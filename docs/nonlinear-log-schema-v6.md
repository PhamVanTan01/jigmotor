# Nonlinear Log Schema v6 Contract

Status: design contract; firmware must not emit `SchemaVersion=6` until the
canonical sampler and validity rules below are implemented and verified.

Schema v4 and v5 meanings are frozen. A parser must never infer v6 semantics
from a v5 record.

## Identity precedence

1. `META.MCU_UID` and `META.JigID` are authoritative.
2. A known UID/JigID mismatch is a parser error.
3. Filename-derived identity is allowed only for legacy records without META.

Canonical mapping:

| JigID | MCU UID |
| --- | --- |
| JIG1 | `003C00273234470438353535` |
| JIG2 | `0025002C3234470438353535` |

The pre-motor `CONFIG` record includes `MCU_UID`, `JigID`, and `JigKnown`.
This is mandatory because a configuration-gate rejection can stop the batch
before any later `META` record exists.

## Record sequence

### Session and batch framing

- `SESSION_START` identifies one firmware boot/logging session with SessionID,
  BuildID, MCU UID, JigID, and JigKnown.
- `BATCH_START` carries SessionID, BatchID, expected run count, and thermal
  protocol before any run precheck or motor command.
- `BATCH_ABORT` closes an interrupted/failed batch with the last TestID/SweepID
  when available and an explicit reason.
- `BATCH_COMPLETE` closes a successful batch with the completed run count.

Every META/DATA/ACQ/RESULT/END record carries the identifiers needed to group
it under `(SessionID, BatchID, TestID, SweepID)`. Parsers ignore structured
fragments without a valid META and never merge text across a session or batch
boundary. A filename is never an identity or grouping field.

One run emits records in this order:

1. `CONFIG` — read-only configuration and gate result, before motor enable.
2. `META` — capture identity, policy, mode, counts, and validity.
3. `DATA` — one canonical point record per captured target.
4. `ACQ` — point-level acquisition quality/counters/timing.
5. Exactly one of:
   - `RESULT` for an official-valid measurement;
   - `DIAGNOSTIC_RESULT` for an invalid measurement.
6. `END` — final status and reason; always the last record for the sweep.

UART transmission remains deferred until after motor disable. `CONFIG` is the
only pre-motor record and is emitted while the output is already disabled.

## Required META fields

- `SchemaVersion=6`
- firmware BuildID, MCU UID, JigID/JigKnown, MotorID, TestID, SweepID
- `MeasurementPolicy=WHOLE_SYSTEM_REPORT_ONLY_V1`
- `MeasurementDefinition=WHOLE_SYSTEM_COMMAND_TRACKING`
- `AcceptanceMode=REPORT_ONLY`
- `MathContractVersion=CANONICAL_Q16_V1`
- `SignedRoundingMode=NEAREST_AWAY_FROM_ZERO`
- `ReferenceDefinition=POINT0_CANONICAL_MEAN`
- `MeanDCComparableToLegacy=0`
- `CanonicalMeanSource=ALL_TIER1`
- `MadFilteringEnabled=0`
- `OfficialResultSource=CANONICAL_Q16` for an official schema-v6 result.
  Phase-2B shadow builds retain `OfficialResultSource=LEGACY` and expose the
  new calculations only as `ShadowCanonical*` diagnostics.
- sweep direction, step/grid, expected/captured/analysis counts
- `SampleTimingMode`, `SampleIntervalCycles`, `ScheduleInitialized`
- `RequiredAcceptedSamples`, point/sweep transaction and accepted counts
- `Quality=VALID|DEGRADED|INVALID`
- `OfficialMeasurementValid=0|1`
- `OfficialInvalidReasonMask`
- tracking, config, settle, acquisition, and context-reacquisition validity
- batch/cooldown and motor-active timing fields

## Canonical DATA contract

- Point 0 canonical accepted mean defines the sweep reference.
- `Point0MeanRawQ16` records that exact canonical reference.
- Mean values and relative error use signed int64 Q16 raw-count units.
- `Error_0=0` by definition.
- CW target at 360 degrees is exactly `65536LL * 65536LL`; CCW is exactly its
  negative. Signed negative values are never left-shifted.
- A diagnostic single raw read must not be substituted for the canonical mean.
- Float degree fields are derived presentation values, not calculation state.
- Closure fields are `ClosureErrorRawQ16`, `ClosureErrorDeg`,
  `ClosureLimitDeg`, and `ClosureValid`. The initial limit is the pilot
  measurement-integrity value 0.20 degrees from `CANONICAL_Q16_V1`, not a
  product-quality threshold.

## Validity contract

`OfficialMeasurementValid=1` requires all of:

- configuration gate passed;
- expected point count and complete canonical means;
- no invalid settle point;
- settle stability and target-proximity checks both passed;
- acquisition budgets not exceeded;
- zero context reacquisitions;
- gross tracking-integrity guard passed;
- full-turn closure passed the versioned measurement-integrity limit;
- no motor fault was recorded;
- model-independent capture validity.

`OfficialInvalidReasonMask` uses the `CANONICAL_Q16_V1` bit assignments for
configuration, acquisition, settle, tracking, closure, reacquisition, and
motor-fault failures. More than one bit may be set. `SettleStabilityValid`,
`SettleTargetProximityValid`, and `SettleValid` must be logged separately; a
stable off-target point is `SETTLED_WRONG_POSITION`.

Model-fit validity is logged separately and does not redefine raw capture
validity. `DEGRADED` handling remains diagnostic until Phase B selects a policy.

An invalid sweep must not emit official `RMS_AC`, harmonic, INL, fitted P2P,
legacy `Nonlinear N Angle`, final average, or `Motor OK` fields. Equivalent
numbers may appear only under names prefixed with `Diagnostic_`.

## Acquisition observability

Point and sweep records include:

- `TransactionCount` and `AcceptedSampleCount`;
- `SpiFailureCount` and maximum consecutive failures;
- `JumpRejectedCount` and maximum consecutive rejects;
- `SkippedSlotCount` and elapsed acquisition time;
- `TimingOverrunCount`, `MaxAbsTimingErrorCycles`, and
  `ScheduleInitialized`;
- `MadFilteringEnabled`, `MadCandidateCount`, `MadRejectedCount`, and
  `RobustSampleCount` (all official Phase-2 filtering fields remain disabled
  or diagnostic because `ALL_TIER1` is canonical);
- context reacquire count;
- CS snapshot cycle validity, `PWMPhaseBinCount[16]`, `PWMPhaseCoverage`,
  `NearEdgeCount`, `MeanEdgeDistance`, and `MinEdgeDistance` for active
  switching edges only.

For a scheduled sampler, metadata is captured before the HAL transaction and
remains valid on SPI failure. The first attempted transaction initializes the
schedule, a failed attempt consumes its slot, and missed slots advance to the
next future slot. Catch-up bursts are forbidden.

Large RESULT/ACQ records must either fit their configured static output buffer
or fail explicitly; silent truncation is a schema error.

Every retry, recovery, degradation, invalidation, and abort must change an
explicit counter or reason field; none may be silent.

## Compatibility tests

The repository parser must contain fixtures for:

- legacy records without META;
- schema v4;
- schema v5 with misleading filename identity;
- valid schema v6;
- invalid schema v6 without official result fields;
- UID/JigID mismatch rejection.
