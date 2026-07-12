# preflight.ps1
# Verifies the toolchain and project files are present before attempting a build.
# Run this before build_cubeide.ps1. Exits non-zero on any missing prerequisite.

. (Join-Path $PSScriptRoot "toolchain.ps1")

$ok = $true

Write-Host "== $ProjectName preflight =="

if (-not $Global:CubeIdeExe) {
    Write-Host "[FAIL] STM32CubeIDE executable not found."
    Write-Host "       Set it explicitly, e.g.:"
    Write-Host "       `$env:CUBEIDE_EXE='C:\Path\To\STM32CubeIDE\stm32cubeidec.exe'"
    $ok = $false
} else {
    Write-Host "[ OK ] CUBEIDE_EXE = $($Global:CubeIdeExe)"
}

if (-not $Global:CubeMxJar) {
    Write-Host "[WARN] STM32CubeMX.jar not found next to STM32CubeIDE (only needed for .ioc regeneration, not for building)."
} else {
    Write-Host "[ OK ] STM32CubeMX.jar   = $($Global:CubeMxJar)"
}

if (-not $Global:BundledJavaExe) {
    Write-Host "[WARN] Bundled JRE not found (only needed for .ioc regeneration, not for building)."
} else {
    Write-Host "[ OK ] Bundled java.exe  = $($Global:BundledJavaExe)"
}

$projectFile = Join-Path $ProjectRoot ".project"
$cprojectFile = Join-Path $ProjectRoot ".cproject"

if (-not (Test-Path $projectFile) -or -not (Test-Path $cprojectFile)) {
    Write-Host "[FAIL] .project / .cproject not found in $ProjectRoot"
    Write-Host "       The CubeIDE project has not been generated yet from GremsyMotorTester-MainBoard.ioc."
    $ok = $false
} else {
    Write-Host "[ OK ] CubeIDE project files present"
}

$mainC = Join-Path $ProjectRoot "Core\Src\main.c"
if (-not (Test-Path $mainC)) {
    Write-Host "[FAIL] Core\Src\main.c not found"
    $ok = $false
} else {
    Write-Host "[ OK ] Core\Src\main.c present"
}

if (-not $ok) {
    Write-Host ""
    Write-Host "Preflight FAILED."
    exit 1
}

Write-Host ""
Write-Host "Preflight PASSED."
exit 0
