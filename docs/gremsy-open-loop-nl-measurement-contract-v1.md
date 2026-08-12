# Gremsy-compatible Open-loop NL Measurement Contract v1

Contract ID: `GREMSY_OPEN_LOOP_NL_1DEG360_V1`

Status: S0-S3 software implementation complete; S4/S5 verification and
hardware pilot remain required before production qualification.

## Measurand

This contract measures the whole-system open-loop command-to-rotor response:

```text
Error[i] = CommandAngle[i]
           - (EncoderMeanAngle[i] - EncoderMeanAngle[0])

OpenLoopNL = max(Error[0..359]) - min(Error[0..359])
```

It includes motor, magnet, commutation, PWM/driver, friction, mounting, jig,
and MA600 response. Without an independent reference encoder it is not a
sensor-only or motor-only absolute INL claim.

## Fixed actuation boundary

- Measurement profile: `GREMSY_COMPAT_OPEN_LOOP_NL_V1`.
- Approach protocol: `SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1`.
- Motion profile: `SCURVE40_ABSOLUTE_TICK_V2`.
- Grid protocol: `UNIFORM_1_DEG_ROUNDED_RAW_V1`.
- The one-degree command grid and S-curve ramp are fixed before the response
  is observed.
- Encoder samples may be read during ramps, settle, and capture for
  observation and validity only.
- No point-level creep, recovery, adaptive endpoint command, encoder-derived
  feedforward, terminal correction, PID, or FOC may alter the command after a
  point ramp begins and before that point's DATA is frozen.
- The Gremsy-compatible setup homing stage ends before the open-loop dither
  establishes the measurement reference. After that reference is
  established, the official sweep is actuation-open-loop.
- A failed point/sweep is invalidated; it is never rescued and reported as
  official NL.

## Grid and point set

- Grid: `UNIFORM_1_DEG_ROUNDED_RAW_V1`.
- Analysis: points 0..359.
- Closure: point 360.
- Optional post-turn diagnostics: points 361..370.
- Command raw magnitude at index `i` is
  `round_nearest(i * 65536 / 360)`, producing 182/183-raw increments and an
  exact 65536-raw full turn at point 360.

## One canonical capture per point

Each point contains exactly one official 64-accepted-sample window. The same
window supplies:

- `MeanUnwrappedRawQ16`;
- rounded `DATA.AngleRaw` and extrema association;
- `ErrorRawQ16` and `ErrorDeg`;
- Raw P2P, robust P2P, RMS, harmonics, residual/model metrics, and closure.

Arithmetic uses `MathContractVersion=CANONICAL_Q16_V1` only as the version of
the Q16 mean/error arithmetic and signed rounding. It does not identify the
grid/measurand; this measurement contract does. The historical reuse of the
math ID as a 256/360-point measurand ID is therefore retired.

For point `i`:

```text
CommandRawQ16[i] = signedTargetRaw[i] * 65536

MeasuredRelativeRawQ16[i] =
    MeanUnwrappedRawQ16[i] - MeanUnwrappedRawQ16[0]

ErrorRawQ16[i] =
    CommandRawQ16[i] - MeasuredRelativeRawQ16[i]
```

The sign convention is `COMMAND_MINUS_MEASURED`. Point 0 error is exactly
zero by definition.

## Capture readiness and validity

Official capture readiness is stability-only:

```text
SettleContract=STABILITY_ONLY_CAPTURE_V1
SettleTargetRequired=0
```

Target proximity is still measured and logged, but it does not delay capture
and never changes the command. A separate versioned gross tracking guard may
invalidate a sweep. Acquisition failure, incomplete canonical points,
stability failure, gross tracking failure, closure failure, or context
reacquisition makes `OfficialMeasurementValid=0` and produces only a
`DIAGNOSTIC_RESULT` with `Diagnostic_*` metric names.

## Primary and supporting metrics

- Primary: `RESULT.OpenLoopNL_Deg = max(Error)-min(Error)` on points 0..359.
- Supporting: `RobustP2P_Deg`, `RMS_AC`, full curve, harmonics, residuals,
  fitted P2P, extrema locations, and closure.
- Supporting metrics may diagnose repeatability and mechanism, but may not
  silently redefine or replace `OpenLoopNL_Deg`.

## Profile isolation

Feedback-assisted V5.x builds use
`MeasurementProfile=POSITION_RESPONSE_DIAGNOSTIC_V5X`, schema v5,
`OfficialOpenLoopNL=0`, and `EligibleForStatistics=0`. Their corrected curves
must not be pooled with this contract's official open-loop data.
