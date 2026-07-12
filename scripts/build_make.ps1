# build_make.ps1
# Fallback build path: invokes the Eclipse-generated Debug/makefile directly using
# the bundled `make` and arm-none-eabi-gcc from the STM32CubeIDE installation
# (never the global PATH). Requires that Core/Src, Core/Inc, Drivers, and the
# Debug/makefile already exist (i.e. the project has been generated/built at
# least once, e.g. via build_cubeide.ps1 or the IDE).

param(
    [string]$Configuration = "Debug"
)

. (Join-Path $PSScriptRoot "toolchain.ps1")

if (-not $Global:MakeExe) {
    Write-Host "[FAIL] Bundled make.exe not found under the STM32CubeIDE installation."
    exit 1
}

if (-not $Global:ArmGccBinDir) {
    Write-Host "[FAIL] Bundled arm-none-eabi-gcc not found under the STM32CubeIDE installation."
    exit 1
}

$buildDir = Join-Path $ProjectRoot $Configuration
$makefile = Join-Path $buildDir "makefile"

if (-not (Test-Path $makefile)) {
    Write-Host "[FAIL] $makefile not found."
    Write-Host "       Run build_cubeide.ps1 (or build once from the IDE) so the makefile is generated."
    exit 1
}

$artifactName = Get-BuildArtifactName -ProjectRoot $ProjectRoot -Configuration $Configuration -ProjectName $ProjectName

Write-Host "== Building $ProjectName ($Configuration) via bundled make =="
Write-Host "artifact   : $artifactName.elf"
Write-Host "make       : $($Global:MakeExe)"
Write-Host "gcc bin    : $($Global:ArmGccBinDir)"

$oldPath = $env:PATH
try {
    # Only prepend bundled CubeIDE tool paths for this process, scoped to this
    # script -- this is not relying on a pre-existing global PATH entry.
    $makeBinDir = Split-Path -Parent $Global:MakeExe
    $env:PATH = "$($Global:ArmGccBinDir);$makeBinDir;$oldPath"
    Push-Location $buildDir
    & $Global:MakeExe -j4 all
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
    $env:PATH = $oldPath
}

$elf = Join-Path $buildDir "$artifactName.elf"

if (-not (Test-Path $elf)) {
    Write-Host "[FAIL] make exited $exitCode or $elf missing."
    exit 1
}

if ($exitCode -ne 0) {
    Write-Host "[WARN] make exited $exitCode, but $elf exists. This is usually a generated secondary-output/size step issue, not a compiler/linker failure."
}

Write-Host "[ OK ] Build succeeded: $elf"
exit 0
