# Nonlinear Metric Definition Contract v1

Contract ID: `CANONICAL_Q16_V1`

This document fixes the mathematical meaning of schema-v6 canonical capture
and analysis. Changing any formula, index set, normalization, sign, rounding,
or fitted grid requires a new contract ID.

## Integer and rounding rules

- Raw angle: signed unwrapped MA600A counts; 65,536 counts per revolution.
- Canonical mean/error: signed int64 Q16 raw-count units.
- Signed rounding: nearest, with exact half rounded away from zero.
- Multiplication by Q16 scale uses `* 65536LL`. Never left-shift a negative
  signed integer.
- Every multiplication must be proven to fit int64 for the configured sample
  and jump budgets.

For a signed numerator and positive denominator:

```c
int64_t DivRoundNearestAwayFromZero(int64_t numerator, int64_t denominator)
{
    if (numerator >= 0)
    {
        return (numerator + denominator / 2) / denominator;
    }
    return -(((-numerator) + denominator / 2) / denominator);
}
```

The implementation must reject denominator zero and must not call this helper
with `INT64_MIN`.

## Canonical point mean

For point `i`, the caller snapshots `pointAnchorUnwrapped` immediately after
settle succeeds. For every tier-1 accepted sample `j`:

```text
rel_j = acceptedUnwrapped_j - pointAnchorUnwrapped
K     = acceptedSampleCount
```

Then:

```c
meanRelRawQ16 = DivRoundNearestAwayFromZero(
    sumRelRaw * 65536LL,
    acceptedSampleCount);

pointMeanRawQ16 =
    pointAnchorUnwrapped * 65536LL + meanRelRawQ16;
```

Initial production candidate:

```text
CanonicalMeanSource=ALL_TIER1
MadFilteringEnabled=0
```

MAD/robust results remain engineering diagnostics until Phase B chooses a
production policy.

## Canonical relative error

For `STEP_RAW=256`, point indices `i=0..264`, and direction sign `d` (`+1` CW,
`-1` CCW):

```c
measuredRelativeRawQ16[i] =
    pointMeanRawQ16[i] - pointMeanRawQ16[0];

targetRelativeRawQ16[i] =
    ((int64_t)d * (int64_t)i * STEP_RAW) * 65536LL;

errorRawQ16[i] =
    measuredRelativeRawQ16[i] - targetRelativeRawQ16[i];
```

Therefore `errorRawQ16[0]` is exactly zero by definition. Float degree values
are derived only after capture:

```text
errorDeg = errorRawQ16 * 360 / (65536 * 65536)
```

## Closure

Point 256 is the exact full-turn closure point:

```c
closureErrorRawQ16 = errorRawQ16[256];
```

Equivalent CW expression:

```c
closureErrorRawQ16 =
    pointMeanRawQ16[256]
    - pointMeanRawQ16[0]
    - 65536LL * 65536LL;
```

The pilot measurement-integrity limit is `0.20 deg`, corresponding to
2,386,093 Q16 raw-count units using the contract rounding rule. It is not a
product-quality limit and must remain identified as pilot until population
data selects the final integrity limit.

The formula above is mathematically exact, but its physical interpretation has
preconditions. Point 0 and point 256 must use equivalent command phase/power,
approach direction/history, settle definition, and mechanical/thermal state,
apart from the intended one-revolution displacement. If those preconditions
are not controlled, `closureErrorRawQ16` contains motor return-to-target,
friction/cogging/hysteresis, and thermal effects in addition to acquisition
integrity. It is not sensor-only trueness.

The 2026-07-14 Phase-3B0 review found that the current point-0 dither approach
and point-256 CW approach are not equivalent. It also found a `0.99633`
correlation between point-256 position error and closure across nine hardware
sweeps. Therefore the formula remains valid, but `ClosureValid` cannot yet be
promoted to an official measurement-validity gate. The missing physical-state
protocol is specified in `phase3b0-closure-measurement-review.md`.

Using the MA600A itself to closed-loop trim point 256 may diagnose actuator
control capability, but it cannot establish MA600A accuracy because the device
under test would also be the reference.

The official-validity formula later in this contract assumes a periodic-map
measurement where closure is an integrity condition. If the selected measurand
is instead the first trajectory after dither/start, closure is a physical
response metric and requires a different versioned measurement/validity
policy; that policy must not silently reuse `ClosureValid` from this contract.

## Settle contract

Settle requires two independent conditions:

```text
SettleValid = SettleStabilityValid && SettleTargetProximityValid
```

Stability uses a fixed sample window and explicitly versioned limits for P2P,
drift/slope, and consecutive samples. Target proximity compares the accepted
unwrapped position with the target in the same unwrapped coordinate frame.

Pairwise consecutive deltas alone do not satisfy this future canonical settle
contract: a slow monotonic drift can keep every pair below its limit while the
complete window spans a much larger range. Whole-window P2P and first-to-last
drift must be computed; any slope rule and every numeric limit must be
versioned and selected from stationary-noise/hold evidence before schema-v6
promotion.

The gross target-proximity envelope and closure limit have different meanings.
Passing a wide motion-integrity envelope (currently about 5 degrees in the
schema-v5 Phase-3A implementation) does not imply passing the pilot
0.20-degree closure limit and must not be logged or interpreted as endpoint
equivalence.

A stable shaft outside the target tolerance is
`SETTLED_WRONG_POSITION`, makes the point invalid, and sets the settle-invalid
bit. It must never qualify merely because it stopped moving.

## Official validity

```text
OfficialMeasurementValid =
    ConfigValid
    && AcquisitionComplete
    && AllRequiredPointsValid
    && SettleValid
    && TrackingValid
    && ClosureValid
    && ContextReacquireCount == 0
    && MotorFaultCount == 0
```

`OfficialInvalidReasonMask` bits:

```c
#define NL_INVALID_CONFIG          (1U << 0)
#define NL_INVALID_ACQUISITION     (1U << 1)
#define NL_INVALID_SETTLE          (1U << 2)
#define NL_INVALID_TRACKING        (1U << 3)
#define NL_INVALID_CLOSURE         (1U << 4)
#define NL_INVALID_REACQUISITION   (1U << 5)
#define NL_INVALID_MOTOR_FAULT     (1U << 6)
```

## Analysis index sets

| Metric | Required input |
| --- | --- |
| MeanDC | canonical error points 0..255 |
| RMS_AC | `error-MeanDC`, points 0..255 |
| Raw P2P | max-min of error points 0..255 |
| Closure | point 256 relative to point 0/exact full-turn target |
| DFT | mean-removed error points 0..255 |
| P99 absolute deviation | nearest-rank `ceil(0.99*N)-1` of `abs(error-mean)`, points 0..255 |
| Residual RMS | RMS of `errorAC-fitted`, points 0..255 |
| Fitted P2P | max-min of the fitted curve on `UNIFORM_4096_V1` |

Points 256..264 are excluded from MeanDC, RMS, P2P, DFT, fit, and residual.
Point 256 is closure; points 257..264 are post-turn diagnostics only.

## Selected-order DFT

For `N=256`, mean-removed `x[n]`, and selected order `k`:

```text
Re_k = sum(x[n] * cos(2*pi*k*n/N))
Im_k = -sum(x[n] * sin(2*pi*k*n/N))
A_k  = (2/N) * sqrt(Re_k^2 + Im_k^2)
PhaseSweepDeg = atan2(-Im_k, Re_k) * 180/pi
```

This phase definition preserves the existing positive-sine coefficient
convention. The associated identifiers are
`DFTPhaseReference=SWEEP_PROGRESS`,
`DFTSignConvention=IM_NEGATIVE_SIN`, and `DFTPhaseUnit=DEG`.
Required selected orders are
`1|2|3|6|9|12|18|27|36|45|72|108`; standalone H4/H8 remain diagnostic.

For reconstruction, `a_k=(2/N)*Re_k`, `b_k=(-2/N)*Im_k`, and:

```text
fitted(theta) = MeanDC + sum(a_k*cos(k*theta) + b_k*sin(k*theta))
```

`LEGACY_6_V1` uses `1|2|3|6|12|18`; `EXTENDED_12_V1` uses the full selected
order list. Residual RMS and fitted P2P must name their model. Residual RMS is
evaluated only at captured points 0..255. Fitted P2P uses exactly 4096 samples
`theta_q=2*pi*q/4096`, `q=0..4095`; this grid is `UNIFORM_4096_V1`.

Direct selected-order DFT is preferred over FFT. A 256-entry sine/cosine LUT
may replace per-sample trigonometric calls after capture; it must not run in
the acquisition loop and must pass the synthetic metric tests.

## Acquisition-loop boundary

The timing-sensitive loop is integer/fixed-point only:

```text
SPI read -> timestamp -> unwrap -> jump validation -> accumulation -> counters
```

It performs no printf/CSV formatting, float conversion, sorting, DFT,
trigonometry, or configuration CRC scan. Interval cycles, jump limits, and
time budgets are precomputed. Large arrays use a static sweep workspace; no
per-sweep heap allocation or large task-stack array is allowed.
