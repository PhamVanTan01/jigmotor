# End-of-Shaft Mounting Verification Test Plan (MA600A)

## Goal

Confirm that a jig with the MA600A mounted **end-of-shaft** (on-axis, per the
datasheet's Figure 6) is mechanically sound and produces a stable,
repeatable whole-system angle-error signature before it is trusted for motor
QC. The firmware sweep has no independent precision reference encoder, so it
cannot establish the MA600A's sensor-only INL. It measures the combined motor,
magnet, mounting, jig mechanics, drive, and MA600A response.

This plan uses measurement policy `WHOLE_SYSTEM_REPORT_ONLY_V1`: acquisition
validity is checked, but no nonlinear pass/fail threshold is applied. The
test is meant to run once per jig (or after rework that disturbs the mounting),
not as a per-unit production acceptance test.

Protocol note (2026-07-14): the earlier three-run/average convention below is
historical and must not be used for the new repeatability qualification.
Phase-3A hardware logs show an unresolved full-turn endpoint error. Complete
`phase3b0-closure-measurement-review.md` first. The qualified protocol must
retain every individual result, separate first-run/cold-start effects, and
pass closure without averaging.

This is separate from `docs/nonlinear-test-plan.md`-style tests in the sibling
`GremsyMotorTester-MainBoard` project (jig-to-jig correlation, LUT A/B). Those
assume the mounting is already good; this plan is what establishes that in the
first place.

## Required Setup

### Mechanical (from the MA600A datasheet, "Sensor (Magnet Mounting)" /
"End-of-Shaft Mounting" sections)

- **Magnet on the rotation axis**: a diametrically magnetized cylinder magnet
  mounted on-axis at the end of the motor shaft, with the MA600A package
  facing it along that same axis. This is what "end-of-shaft" means, as
  opposed to side-shaft (off-axis) mounting.
- **Reference magnet**: datasheet's worked example is a Neodymium N35 cylinder,
  Ø5mm x 2.5mm.
- **Air gap**: 2mm between the magnet face and the sensor package surface
  (the datasheet's example value -- treat as the starting point, not a fixed
  requirement; the real constraint is the field strength at the die, see
  below).
- **Concentricity**: the offset between the sensor's sensitive center and the
  magnet's rotation axis must be **less than 5% of the magnet's outer
  diameter** for optimal linearity. For the Ø5mm reference magnet, that is
  **< 0.25mm**.
- **Orientation**: the dot marked on the package top indicates alignment with
  the sensor's X/Y axes (datasheet Figure 32) -- confirm it is oriented
  consistently with however the firmware's zero-angle/rotation-direction
  config expects it.

### Magnetic field strength

- Recommended operating range: **20-80mT**.
- Functional (wider, still specified) range: **10-150mT**.
- Absolute maximum: **200mT**.
- **The MA600A has no field-strength diagnostic register** -- `STATUS` (0x1A)
  only exposes `NVMB`/`ERRCRC`/`ERRMEM`/`ERRPAR`, nothing about the magnetic
  field being too weak or too strong. There is no way to read "field OK" over
  SPI. Field strength at the sensor must be confirmed with an external
  gaussmeter at assembly time, or inferred indirectly from the measured error
  curve in the firmware sweep below (a field near the edges of the functional
  range, or the air gap being wrong, tends to show up as excess nonlinearity).

### Datasheet context (not firmware acceptance limits)

- Typical sensor-only INL at 25 degC, 45mT (uncalibrated): **0.2 deg**, max
  **0.6 deg**. The firmware sweep must not use these values as pass/fail limits
  because commanded motor position is not an independent precision reference.
- INL after the MA600A's on-chip 32-point user calibration: **0.06-0.1 deg**.
  **Do not rely on this for jigmotor.** The sibling project's
  `docs/ma600-calibration-procedure.md` found the on-chip LUT correction does
  not generalize well on real hardware and now ships disabled
  (`MA600_LUT_ENABLED = 0`). This plan records the **raw, uncalibrated**
  whole-system response. Do not use the LUT to hide a mechanical or acquisition
  problem.
- Functional test mode (FTM) accuracy: **2 deg**. This is a sanity self-test
  (verifies signal-path integrity, not real angle accuracy) -- use it only to
  rule out a dead/miswired sensor before doing the real sweep below.
- Operating temperature: -40 degC to +125 degC. Out of scope for this bench
  procedure (room-temperature only); note as a possible future extension if a
  thermal chamber becomes available.

## Test Procedure

### Part A -- Mechanical checklist (do this before powering on)

1. Confirm magnet part/dimensions match the reference (or record the actual
   part used if different) and that it is diametrically magnetized.
2. Measure and record the air gap between the magnet face and the sensor
   package surface.
3. Measure and record the concentricity offset between the sensor's sensitive
   center and the magnet's rotation axis. Confirm it is under 5% of the
   magnet's outer diameter.
4. Confirm the orientation dot alignment against the firmware's expected zero
   angle / rotation direction.
5. If a gaussmeter is available, measure the field at the sensor position and
   confirm it falls in 20-80mT (or at least within the 10-150mT functional
   range).

Do not proceed to Part B until all of the above are recorded -- a firmware
sweep run against a mounting that hasn't been checked isn't diagnostic of
anything.

### Part B -- Firmware angle sweep

This reuses the same measurement flow and log format already produced by the
sibling project's nonlinear test firmware, so `scripts/analyze_nonlinear_logs.ps1`
(already present in this repo) can parse it without modification once
`jigmotor`'s firmware implements the equivalent logging. Expected fields:

- `Motor offset:` / `Motor angle offset:` (start alignment)
- `Nonlinear N Angle:` / `MA600 Raw Nonlinear N Angle:` for N = 1..3 (three
  sweep runs; ignore run 1, average runs 2 and 3 -- same convention as
  `docs/nonlinear-test-plan.md`)
- `Nonlinear Final Average:` / `MA600 Raw Nonlinear Final Average:`
- `Motor  OK` / `Motor  ERROR: ...` result line

Procedure:

1. Power on the jig with the mounted assembly, wait for idle/ready state.
2. Start console log capture (USART3, 921600 8N1, same as the existing jigs).
3. Run the sweep: rotate one full mechanical revolution, sampling the MA600's
   raw angle at fixed anchor points against the commanded motor position, 3
   times (ignore run 1, use runs 2 and 3 as in the existing convention).
4. Record the printed `Nonlinear Final Average` and
   `MA600 Raw Nonlinear Final Average`.
5. Repeat with a second, different motor/magnet unit to check the result
   isn't specific to one part.

## Record Sheet

| Item | Value |
| --- | --- |
| Magnet part / dimensions | |
| Air gap (mm) | |
| Concentricity offset (mm) | |
| Orientation confirmed (Y/N) | |
| Field strength at sensor (mT), if measured | |

| Run | Motor offset | Angle offset | NL 2 | NL 3 | NL AVG (raw) | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | | | | | | |
| 2 | | | | | | |

## Review Rules

- Check the mechanical checklist first. If air gap, concentricity, or field
  strength are out of range, fix the assembly before drawing any conclusion
  from the firmware sweep numbers.
- Require protocol validity first: clean sensor status, successful checked SPI
  reads, acceptable sample jumps, the expected analysis-point count, successful
  settling at every point, and gross tracking integrity. Schema v5 uses wide
  15 deg RMS / 30 deg maximum tracking-error guards to catch a stalled or lost
  drive; these guards are not nonlinear product-quality acceptance limits.
- Compare repeatability across runs, jigs, and remounts. Investigate a change
  against the established jig/product population rather than against the
  MA600A's sensor-only 0.6 degree INL limit.
- If the whole-system curve degrades while acquisition remains valid, inspect
  air gap, concentricity, magnet strength, mechanical seating, drive behavior,
  and temperature before suspecting the sensor alone.
- Introducing a production nonlinear threshold requires a new versioned policy
  backed by a representative population study or an independent reference
  encoder.

## Parse Raw Logs

Save each sweep's console log as a text file, then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\analyze_nonlinear_logs.ps1 logs\*.txt -OutCsv logs\end-of-shaft-results.csv -Summary
```

The important columns are `NLAvg` (raw nonlinear final average) and
`MotorOffsetUsedMean` / `AngleOffsetUsedMean` (to confirm the assembly didn't
shift between runs).
