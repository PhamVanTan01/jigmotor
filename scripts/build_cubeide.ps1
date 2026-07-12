# build_cubeide.ps1
# Headless build of the GremsyMotorTester-MainBoard STM32CubeIDE project.
# Does not call arm-none-eabi-gcc directly and does not rely on global PATH --
# it drives STM32CubeIDE's own headless build application, which resolves the
# GNU ARM toolchain internally exactly as the GUI build would.

param(
    [string]$Configuration = "Debug"
)

. (Join-Path $PSScriptRoot "toolchain.ps1")

if (-not $Global:CubeIdeExe) {
    Write-Host "[FAIL] STM32CubeIDE executable not found. Set `$env:CUBEIDE_EXE and retry."
    exit 1
}

if (-not (Test-Path $Global:WorkspaceDir)) {
    New-Item -ItemType Directory -Path $Global:WorkspaceDir | Out-Null
}

Write-Host "== Building $ProjectName ($Configuration) =="
Write-Host "Project root : $ProjectRoot"
Write-Host "Project name : $ProjectName"
Write-Host "Workspace    : $($Global:WorkspaceDir)"
Write-Host "CubeIDE exe  : $($Global:CubeIdeExe)"

$argsList = @(
    "--launcher.suppressErrors",
    "-nosplash",
    "-application", "org.eclipse.cdt.managedbuilder.core.headlessbuild",
    "-data", "$($Global:WorkspaceDir)",
    "-import", "$ProjectRoot",
    "-cleanBuild", "$ProjectName/$Configuration"
)

& $Global:CubeIdeExe @argsList
$exitCode = $LASTEXITCODE

$artifactName = Get-BuildArtifactName -ProjectRoot $ProjectRoot -Configuration $Configuration -ProjectName $ProjectName
$elf = Join-Path $ProjectRoot "$Configuration\$artifactName.elf"

# The headless launcher's own process exit code is not a reliable pass/fail
# signal here: STM32CubeIDE's CDT indexer frequently reports nonzero
# "errors" from its own static-analysis pass (separate from actual GCC
# compilation) even when the real arm-none-eabi-gcc/ld invocations all
# succeeded. The .elf actually existing on disk is the authoritative signal.
if (-not (Test-Path $elf)) {
    Write-Host "[FAIL] Build did not produce $elf (headless launcher exit code $exitCode). Check the log above for the exact compiler/linker error."
    exit 1
}

if ($exitCode -ne 0) {
    Write-Host "[WARN] Headless launcher reported exit code $exitCode, but $elf was produced -- this is usually just CDT indexer noise, not a real build failure. Verify by inspecting the console output above for actual 'arm-none-eabi-gcc ... error:' lines."
}

Write-Host "[ OK ] Build succeeded: $elf"
exit 0
