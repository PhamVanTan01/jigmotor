# Motion Control V2 — implementation and hardware qualification

Status: software implemented; all 12 host contracts and both Debug/Release
builds pass with zero compiler warnings. Hardware qualification is still
required before this profile can replace the July 15 baseline for production
data.

## Objective

Make home, start alignment, and one-degree point-to-point motion smoother and
more repeatable without changing the measurement definition. The official
curve remains 360 points (`0..359`), each point remains the mean of 64 accepted
MA600 samples, and each final command remains the rounded
`round(i * 65536 / 360)` target.

The official sample is deliberately not closed-loop corrected. Closing the
position loop at capture time could suppress the motor/system nonlinearity the
jig is intended to measure.

## Implemented profiles

### Sweep trajectory

Default: `SCURVE40_ABSOLUTE_TICK_V2`.

- 40 command slots per one-degree segment.
- 1 ms absolute RTOS deadline cadence (`osDelayUntil`), so SPI transaction
  time does not accumulate into the next segment deadline.
- Quintic blend `10u^3 - 15u^4 + 6u^5` gives zero velocity and acceleration at
  both endpoints.
- The last command is explicitly clamped to the exact 182/183-raw target.
- Power remains 1.0 to avoid changing two physical factors in one revision.
- Legacy `STAIRCASE8_RELATIVE_TICK_V1` remains selectable at compile time for
  A/B/A rollback.

### Point-zero alignment

Default: `SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`.

- The old 40-direction-change dither is bypassed under Motion V2.
- The retained electrical phase is aligned to the nearest equivalent phase
  zero using one S-curve.
- The existing one-degree backoff is followed by a CW S-curve to point 0,
  matching the final approach direction/profile used by point 360.

### Home controller

Default: `WRAPPED_PID_SLEW_V2`.

- Periodic error is wrapped to `[-180, 180]`, preventing a reading near 360
  degrees from causing an unnecessary almost-full-revolution home move.
- Existing gains and the fixed 2 ms loop period are retained for the first
  hardware experiment.
- Integral windup is clamped instead of discontinuously reset to zero.
- Derivative contribution uses a one-pole filter (`alpha=0.25`).
- Incremental output changes are limited to 8 raw counts per update.
- Filter/output state is included in the mandatory run-boundary reset audit.

## Telemetry

Every sweep emits a motor-off `MOTION_PROFILE` record containing:

- selected sweep and home profile IDs;
- tick period and command count per degree;
- lock duration/command count/overruns;
- ramp segment and command counts;
- timing overruns and maximum lateness;
- observed encoder backtrack count and maximum magnitude.

The first three normal ramps and both equal-approach legs emit their accepted
per-command encoder traces after motor-off. `GRID` now uses the large logging
buffer, fixing the previous `GRID...CONTROL_STATE` concatenation.

## Qualification sequence

Do not tune multiple factors in one firmware image.

1. Flash Motion V2 and capture startup text, including the DMA transport ID.
2. The current image deliberately retains the official fixed batch of one
   precondition plus ten runs. Treat the precondition and first official run as
   the motion-safety screen; stop the test if motion is visibly unsafe instead
   of changing the measurement contract to a three-run batch.
3. Check visible movement, `MOTION_PROFILE`, all `MOTION` records, and the
   first-three-ramp traces.
4. If movement is worse or any acquisition/settle gate fails, compile the
   legacy staircase profile and run A/B/A before changing any parameter.
5. If the initial screen passes, allow the complete one-precondition plus ten
   official-run batch to finish with the existing 120-second cooldown protocol.

## Acceptance gates

- `MeasurementValid=1` and `TrackingValid=1` for every official run.
- `SpiFailures=0`, `AcqRetries=0`, `JumpRejects=0`, `FailedPoints=0`, and
  `TimingOverruns=0`.
- `RampTimingOverruns=0` and no observed CW backtrack larger than the 9-raw
  settle-noise threshold.
- Exactly 371 captured points and 23,744 canonical accepted samples per run.
- RMS_AC coefficient of variation no worse than the July 15 baseline 0.236%.
- Mean pointwise repeatability standard deviation no worse than 0.0225 deg.
- Tracking maximum no worse than the baseline neighborhood of 2.16 deg.
- Closure target remains 0.2 deg. Smoothness may be accepted independently
  for diagnosis, but a closure result near the old 0.69 deg is not declared
  fixed.
- Motor-active duration and the RMS_AC/A36 thermal trend must be reported;
  the 40 ms segment is expected to increase sweep time versus the 23-command
  staircase.

## Rollback and tuning order

Compile-time selection keeps the legacy trajectory available. If V2 is too
slow or heats the motor, screen segment durations in this order while keeping
all other factors fixed: 40 ms, 32 ms, then an intermediate value chosen from
the measured velocity/backtrack trace. Power must remain 1.0 during this
screening. Power profiling is a separate future experiment.

Do not convert the official sweep to closed-loop position control without a
new measurement contract and a new baseline dataset.
