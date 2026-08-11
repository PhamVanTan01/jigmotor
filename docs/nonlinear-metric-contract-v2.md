# Nonlinear Metric Definition Contract v2

Contract ID: `CANONICAL_Q16_1DEG360_V2`

This contract defines the canonical capture used by the current
`UNIFORM_1_DEG_ROUNDED_RAW_V1` sweep. It supersedes
`CANONICAL_Q16_V1` only for new 360-point/one-degree captures. Historical
256-point records retain their original V1 identity.

Changing the formula, index set, target grid, sign, rounding, normalization,
or fitted grid requires another contract ID.

## Compatibility and the historical V1 mislabel

Firmware produced before this contract was introduced emitted some 360-point
captures with:

```text
ContractVersion=CANONICAL_Q16_V1
AnalysisPoints=360
```

That combination is a historical versioning defect: V1 is defined as a
256-point grid with closure at point 256. Host tools may read the combination
for backward analysis, but must expose it as a legacy alias and must not
silently treat it as a conforming V1 record.

New captures are conforming only when:

```text
ContractVersion=CANONICAL_Q16_1DEG360_V2
AnalysisPoints=360
GRID.Protocol=UNIFORM_1_DEG_ROUNDED_RAW_V1
GRID.PointsPerRev=360
```

## Integer and rounding rules

- Raw angle is a signed unwrapped MA600A count; one turn is 65,536 counts.
- Canonical point means and errors use signed int64 Q16 raw-count units.
- Signed division rounds to nearest, with an exact half away from zero.
- Q16 scaling uses multiplication by `65536LL`; a negative signed integer is
  never left-shifted.

The canonical point mean is unchanged from V1:

```text
rel_j = acceptedUnwrapped_j - pointAnchorUnwrapped

meanRelRawQ16 =
    DivRoundNearestAwayFromZero(sumRelRaw * 65536, acceptedSampleCount)

pointMeanRawQ16 =
    pointAnchorUnwrapped * 65536 + meanRelRawQ16
```

Production-candidate sampling fields remain:

```text
CanonicalMeanSource=ALL_TIER1
MadFilteringEnabled=0
```

## One-degree target grid

For point index `i`, the unsigned target magnitude is:

```text
targetMagnitudeRaw[i] =
    round_nearest(i * 65536 / 360)
```

The implementation uses integer rounding:

```c
(i * 65536 + 180) / 360
```

For direction sign `d` (`+1` CW, `-1` CCW):

```text
targetRelativeRawQ16[i] =
    d * targetMagnitudeRaw[i] * 65536
```

Consequences:

- Consecutive command increments are 182 or 183 raw counts.
- Point 180 is exactly 32,768 raw counts.
- Point 360 is exactly 65,536 raw counts.
- There is no cumulative one-turn rounding drift.
- `StepRaw=0` means the target is not represented by one fixed raw increment;
  consumers must use the declared rounded grid.

## Canonical relative error

For captured point `i`:

```text
measuredRelativeRawQ16[i] =
    pointMeanRawQ16[i] - pointMeanRawQ16[0]

errorRawQ16[i] =
    measuredRelativeRawQ16[i] - targetRelativeRawQ16[i]

errorDeg[i] =
    errorRawQ16[i] * 360 / (65536 * 65536)
```

`errorRawQ16[0]` is exactly zero by definition. Canonical shadow error uses
the `MEASURED_MINUS_TARGET` sign convention. Legacy `DATA.Error` may use the
opposite sign; an analyzer must identify which record family it consumes and
must not combine phases without normalizing the sign.

## Analysis and closure index sets

| Quantity | Required input |
| --- | --- |
| MeanDC | points 0..359 |
| RMS_AC | mean-removed error, points 0..359 |
| Raw P2P | max-min, points 0..359 |
| Robust NL | average(top 5)-average(bottom 5), points 0..359 |
| DFT/harmonics | mean-removed error, points 0..359 |
| Residual RMS | selected-order fit residual, points 0..359 |
| Closure | point 360 relative to point 0 and one exact turn |
| Post-turn diagnostics | points 361..370 |

Points 360..370 are excluded from NL, RMS, P2P, DFT, fit, and residual.

The exact closure formula is:

```text
closureErrorRawQ16 =
    pointMeanRawQ16[360]
    - pointMeanRawQ16[0]
    - d * 65536 * 65536
```

The current `0.20 deg` closure limit is a pilot measurement-integrity limit,
not a motor-quality, sensor-INL, or product-acceptance limit.

## Selected-order DFT

For `N=360`, mean-removed `x[n]`, and selected harmonic order `k`:

```text
theta_n = 2*pi*n/360
Re_k    = sum(x[n] * cos(k*theta_n))
Im_k    = -sum(x[n] * sin(k*theta_n))
A_k     = (2/360) * sqrt(Re_k^2 + Im_k^2)
phase   = atan2(-Im_k, Re_k)
```

Required selected orders are:

```text
1|2|3|6|9|12|18|27|36|45|72|108
```

The phase reference is sweep progress, not a traceable common mechanical
datum shared by different MA600 sensors or different jig remounts.

## Statistical eligibility

For records that declare the batch-role fields, a sweep is eligible for
official statistics only if all are true:

```text
META.MeasurementValid=1
END.Status=VALID
META.RunRole=OFFICIAL
META.EligibleForStatistics=1
all analysis points 0..359 are present
```

A valid `PRECONDITION` sweep remains excluded even when its acquisition and
END records are valid. For legacy records without `RunRole` and
`EligibleForStatistics`, tools must explicitly label the eligibility source
as legacy; they must not guess a precondition solely from file position.

## Measurand boundary

This contract fixes arithmetic and record semantics. It does not establish
sensor-only trueness. Without an independent angle reference, the reported
curve is the response of the complete motor, magnet, mounting, drive, jig,
and MA600 system:

```text
MeasurementDefinition=WHOLE_SYSTEM_COMMAND_TRACKING
AcceptanceMode=REPORT_ONLY
```

Therefore robust NL from this contract is a repeatable system
command-tracking signature under controlled conditions. It must not be
compared directly with the MA600 sensor-only datasheet INL limit.
