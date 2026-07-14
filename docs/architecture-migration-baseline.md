# Architecture Migration Baseline

Baseline captured on 2026-07-13 before the acquisition/task architecture
migration. Existing uncommitted work in `ma600.h`, `ma600.c`, and
`nonlinear_test.c` is part of this baseline and must not be discarded.

## Chosen Architecture

Use an incremental layered modular monolith inside the existing STM32/FreeRTOS
firmware:

- `ma600.c`: one checked low-level SPI transaction and read-only device/status
  operations.
- `ma600_acquisition.c`: canonical retry, per-consumer unwrap, jump validation,
  timing metadata, counters, and test fault injection.
- `motor_pwm.c`: relay/PWM actuation only.
- `position_controller.c`: deterministic controller state and math only.
- `motor.c`: small facade combining checked feedback, controller, and actuation.
- `nonlinear_test.c`: test-engine state/sequencing, capture, analysis, and reporting,
  owned by a dedicated task.

This keeps failure policy and hardware ownership explicit without introducing a
framework or a second scheduler. A large mechanical split of nonlinear analysis
and reporting is intentionally gated until the new image passes hardware
equivalence; moving that code now would add a wide diff with no behavioral gain.

## Deferred Decisions

- SPI DMA remains disabled. The current blocking transaction now records a DWT
  timestamp and TIM1 phase adjacent to chip-select, providing evidence for a
  later timing decision. DMA is justified only if hardware logs show timing
  variance that affects results.
- A hardware watchdog remains deferred until the board's reset/safe-output
  behavior is validated. Stack-overflow and allocation-failure hooks already
  force the motor-enable pin low before entering the fatal handler.

## Build

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build_make.ps1
```

Debug build result:

| Region | Bytes |
| --- | ---: |
| Text | 75,656 |
| Data | 108 |
| BSS | 118,648 |

`configTOTAL_HEAP_SIZE` accounts for 102,400 bytes of BSS. Runtime heap and
task stack high-water measurements are still required on hardware before
adding application tasks.

## Hardware Log

`p03-jig1.txt` is the read-only representative baseline. It contains three
schema-v4 JIG1/P03 sweeps from firmware build `Jul 13 2026 10:31:10`.

| Metric | Baseline |
| --- | ---: |
| Valid runs | 3 |
| NL average mean | 3.31 deg |
| NL average range | 0.09 deg |
| NL average standard deviation | 0.046 deg |
| Representative motor-active duration | about 17.1 s |

The migration must preserve parsing of historical schema-v4 logs and numerical
results within explicit floating-point tolerances. New firmware emits schema v5
because measurement validity now includes a gross motion-integrity check.
Hardware values are expected to have normal run-to-run variation; they are
comparison evidence, not exact golden constants.

### Negative regression fixture

`p03-jig2.txt` is a read-only failure fixture from the same old firmware. Its
first sweep lost motor tracking but was incorrectly marked `MeasurementValid=1`
and printed `Motor OK`:

| Metric | Failed old-firmware run |
| --- | ---: |
| Tracking RMS error | 102.0610 deg |
| Tracking maximum absolute error | 179.5331 deg |
| Reported nonlinear angle | 317.03 deg |
| Later failure | E503 move-to-zero timeout |

Schema v5 must reject this shape as a protocol/motion failure. The guard is
deliberately loose (15 deg RMS and 30 deg maximum) compared with the healthy
JIG1 baseline (about 1.1 deg RMS and 2.4 deg maximum). These are not nonlinear
product-quality limits; they only prevent a stalled or disconnected drive from
being presented as a valid measurement.

## Measurement Policy

Policy ID: `WHOLE_SYSTEM_REPORT_ONLY_V1`.

The sweep compares commanded commutation position with the MA600A mounted on
the same motor. It has no independent precision reference encoder. Therefore
the result describes the combined motor, magnet, mounting, jig mechanics,
drive, and MA600A response. It is not a sensor-only INL measurement and must
not be judged against the MA600A datasheet's sensor-only 0.6 degree INL limit.

Production firmware reports the measurements and protocol validity but does
not apply a nonlinear pass/fail threshold. Protocol validity includes checked
sensor acquisition, complete settling/point count, and the gross tracking guard
above. A nonlinear quality threshold may be introduced only as a new versioned
policy after a representative population study or after adding an independent
reference encoder.
