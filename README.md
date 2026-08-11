# jigmotor

Firmware project for a Gremsy motor QC jig using the MPS MA600A magnetic
angle sensor as an absolute encoder, mounted end-of-shaft on the motor under
test. STM32F405RGTx target.

## STM32CubeIDE

This repository holds the `jigmotor.ioc` for the STM32F405RGTx target. The
`Core/Src`, `Core/Inc`, `Drivers`, `.project`, and `.cproject` are generated
from it and are not checked in yet.

1. Open STM32CubeIDE.
2. `File > Open File...` and select `jigmotor.ioc`.
3. Click **GENERATE CODE** (toolchain: STM32CubeIDE).
4. Build either the `Debug` or `Release` configuration.

## Building from the command line

Once the project has been generated once (via CubeIDE, see above):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\preflight.ps1
powershell -ExecutionPolicy Bypass -File scripts\build_cubeide.ps1 -Configuration Release
powershell -ExecutionPolicy Bypass -File scripts\build_dual_image.ps1 -Mode All
```

The dual-image command writes independently compiled artifacts to
`Build/Measurement` and `Build/Control`, including SHA-256 manifests. At P1,
`jigmotor_measurement.hex` preserves the active Motion V2 + SPI DMA behavior.
`jigmotor_control.hex` now contains the bounded C0 plant-observation profile
`CONTROL_C0_OPEN_LOOP_1DEG_V1`: it homes at 35% power, commands only one degree,
records feedback at 1 kHz, then disables torque before UART output. Follow
`docs/control-c0-hardware-test.md`; this is not yet a closed-loop tracking PID.

The active motor-motion profile and its hardware qualification procedure are
documented in `docs/motion-control-v2-implementation-plan.md`. Run
`scripts/test_motion_control_v2_contract.ps1` whenever changing the home,
alignment, or point-to-point trajectory code.

For a complete 360-point nonlinear-error assessment, including raw/centered
curves, pointwise repeatability, A1-B-A2 differential, robust-NL tail
locations, and the harmonic spectrum, use `tools/analyze_nl_curve.py`.
Its measurement contract and output files are documented in
`docs/nl-pointwise-curve-analysis.md`.

For a new Codex session or a clone on another computer, read
`docs/CODEX_HANDOFF_MOTION_V2_DMA.md` first. It records the effective branch,
measurement invariants, implemented DMA/motion behavior, build commands,
rollback switches, and remaining hardware-validation work.

The P1 architecture now separates motor control and official measurement into
two independently linked firmware images. The remaining resource and control
phases are tracked in:

- `docs/stm32f405-dual-mode-system-design.md`
- `docs/stm32f405-dual-mode-implementation-plan.md`

See `scripts\toolchain.ps1` for how the STM32CubeIDE/toolchain paths are
resolved, and `docs\end-of-shaft-mounting-test-plan.md` for how to verify the
MA600A end-of-shaft mounting meets the datasheet's accuracy spec before using
a jig for QC.

## Architecture

- Current measurement data flow: `docs/system_measurement_architecture.md`
- Target algorithm-preserving system design:
  `docs/system-design-v2-algorithm-preserving.md`
- SPI acquisition restructuring and controlled optimization plan:
  `docs/spi-acquisition-optimization-plan.md`
