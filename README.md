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

See `scripts\toolchain.ps1` for how the STM32CubeIDE/toolchain paths are
resolved, and `docs\end-of-shaft-mounting-test-plan.md` for how to verify the
MA600A end-of-shaft mounting meets the datasheet's accuracy spec before using
a jig for QC.
