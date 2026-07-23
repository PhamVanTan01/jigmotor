# save_build.ps1
# Builds the project (via build_cubeide.ps1) and archives the resulting .hex
# into builds\<Label>\ along with a build_info.txt sidecar, so a past
# firmware image can be re-flashed later without rebuilding from source.

param(
    [Parameter(Mandatory=$true)][string]$Label,
    [string]$Configuration = "Debug"
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build_cubeide.ps1'

Write-Host "== Saving build '$Label' ($Configuration) =="

& $buildScript -Configuration $Configuration
$buildExitCode = $LASTEXITCODE

$hexSource = Join-Path $ProjectRoot "$Configuration\jigmotor.hex"
if (-not (Test-Path $hexSource)) {
    Write-Host "[FAIL] Build did not produce $hexSource (build_cubeide.ps1 exit code $buildExitCode). Nothing saved."
    exit 1
}
if ($buildExitCode -ne 0) {
    Write-Host "[FAIL] build_cubeide.ps1 reported failure (exit code $buildExitCode) even though $hexSource exists. Not trusting this artifact -- nothing saved."
    exit 1
}

$outDir = Join-Path $ProjectRoot "builds\$Label"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

Copy-Item -LiteralPath $hexSource -Destination (Join-Path $outDir 'jigmotor.hex') -Force

Push-Location $ProjectRoot
try {
    $gitCommit = (git rev-parse HEAD 2>$null)
    $gitStatus = (git status --short 2>$null)
} finally {
    Pop-Location
}
$gitDirty = if ($gitStatus) { 'yes' } else { 'no' }

$sourceFile = Join-Path $ProjectRoot 'Core\Src\nonlinear_test.c'
$approachFlagLine = Select-String -Path $sourceFile -Pattern '#define\s+ENABLE_B0B_EQUAL_APPROACH\s+(\d+)' | Select-Object -First 1
$approachFlagValue = if ($approachFlagLine) { $approachFlagLine.Matches[0].Groups[1].Value } else { 'UNKNOWN' }

$infoLines = @(
    "SavedAtUtc=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "Configuration=$Configuration",
    "GitCommit=$gitCommit",
    "GitDirty=$gitDirty",
    "ApproachFlag(ENABLE_B0B_EQUAL_APPROACH)=$approachFlagValue"
)
Set-Content -Path (Join-Path $outDir 'build_info.txt') -Value $infoLines -Encoding utf8

Write-Host "[ OK ] Saved: $outDir\jigmotor.hex"
Write-Host "[ OK ] Info : $outDir\build_info.txt"
foreach ($line in $infoLines) { Write-Host "         $line" }
