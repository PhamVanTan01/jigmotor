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
powershell -ExecutionPolicy Bypass -File scripts\build_cubeide.ps1
```

The active motor-motion profile and its hardware qualification procedure are
documented in `docs/motion-control-v2-implementation-plan.md`. Run
`scripts/test_motion_control_v2_contract.ps1` whenever changing the home,
alignment, or point-to-point trajectory code.

For a new Codex session or a clone on another computer, read
`docs/CODEX_HANDOFF_MOTION_V2_DMA.md` first. It records the effective branch,
measurement invariants, implemented DMA/motion behavior, build commands,
rollback switches, and remaining hardware-validation work.

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
