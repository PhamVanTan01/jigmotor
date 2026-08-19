# Builds an isolated "quick mechanical screen" Measurement image: same
# GREMSY_COMPAT_OPEN_LOOP_NL_V1 official open-loop pipeline as the standard
# Release/Measurement build, but with NL_TEST_REPEAT_3_RUNS=1 instead of the
# default NL_TEST_REPEAT_10_RUNS=1 -- 1 precondition + 3 official sweeps per
# button press instead of 1 + 10, for fast A/B screening between mechanical
# passes (sensor gap, mount hardware, ...) where the effect being looked for
# is already expected to be large relative to the ~1-2% within-batch noise
# floor established today.
#
# This is the existing NL_TEST_REPEAT_3_RUNS mode already defined in
# nonlinear_test.c (protocol ID ONE_FULL_SWEEP_120S_V1_FAST3) -- this script
# does not add new firmware logic, it only builds a separate, clearly
# isolated image with that mode selected, so the standard 10-run Release
# build is never touched. Every log produced by this image carries
# PreconditionProtocol=ONE_FULL_SWEEP_120S_V1_FAST3, which is a distinct
# value from the standard build's ONE_FULL_SWEEP_120S_V1 -- so a downstream
# analyzer or a person reading the log can never mistake n=3 quick-screen
# data for a qualified n=10 result.
#
# Do not use this image's results to accept/reject a mechanical
# configuration on their own. Per the existing in-source guidance: confirm
# anything found under this mode by re-running under the standard
# NL_TEST_REPEAT_10_RUNS build before trusting it.

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'toolchain.ps1')

function Assert-ChildPath {
    param([string]$Candidate, [string]$Parent)
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    $candidateFull = [System.IO.Path]::GetFullPath($Candidate)
    if (-not $candidateFull.StartsWith($parentFull,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing generated-build operation outside project: $candidateFull"
    }
    return $candidateFull
}

function Invoke-BundledMake {
    param([string]$BuildDirectory, [switch]$Clean)
    $oldPath = $env:PATH
    try {
        $makeBin = Split-Path -Parent $Global:MakeExe
        $env:PATH = "$($Global:ArmGccBinDir);$makeBin;$oldPath"
        Push-Location $BuildDirectory
        if ($Clean) {
            & $Global:MakeExe clean
            if ($LASTEXITCODE -ne 0) { throw "make clean failed in $BuildDirectory" }
        }
        & $Global:MakeExe -j4 all
        if ($LASTEXITCODE -ne 0) { throw "make failed in $BuildDirectory" }
    } finally {
        Pop-Location
        $env:PATH = $oldPath
    }
}

if (-not $Global:MakeExe -or -not $Global:ArmGccBinDir) {
    throw 'Bundled STM32CubeIDE make/GCC toolchain not found.'
}

$releaseDirectory = Join-Path $ProjectRoot 'Release'
if (-not (Test-Path (Join-Path $releaseDirectory 'makefile'))) {
    throw 'Release makefile missing. Run build_cubeide.ps1 -Configuration Release first.'
}

$modeDirectory = Assert-ChildPath (Join-Path $ProjectRoot 'QuickScreen3Run') $ProjectRoot
if (Test-Path $modeDirectory) {
    $resolvedMode = (Resolve-Path -LiteralPath $modeDirectory).Path
    if ($resolvedMode -ne $modeDirectory) {
        throw "Unexpected mode path resolution: $resolvedMode"
    }
    Remove-Item -LiteralPath $modeDirectory -Recurse -Force
}
Copy-Item -LiteralPath $releaseDirectory -Destination $modeDirectory -Recurse

$sourceId = (& git -C $ProjectRoot rev-parse --short=12 HEAD).Trim()
if (-not $sourceId) { throw 'Unable to resolve git source identity.' }
if (& git -C $ProjectRoot status --porcelain) { $sourceId += '-dirty' }
$extraDefines = '-DNL_TEST_REPEAT_3_RUNS=1 -DNL_TEST_REPEAT_10_RUNS=0'
$sourceDefine = "-DJIG_BUILD_SOURCE_ID=\`"$sourceId\`""

$makeFragments = Get-ChildItem -LiteralPath $modeDirectory -Recurse -Filter 'subdir.mk'
$patched = 0
foreach ($fragment in $makeFragments) {
    $content = Get-Content -LiteralPath $fragment.FullName -Raw
    if ($content.Contains('-DJIG_APP_MODE=2')) {
        $content = $content.Replace('-DJIG_APP_MODE=2',
            "-DJIG_APP_MODE=2 $extraDefines $sourceDefine")
        Set-Content -LiteralPath $fragment.FullName -Value $content -NoNewline
        $patched++
    }
}
if ($patched -eq 0) {
    throw 'No subdir.mk fragments contained -DJIG_APP_MODE=2 -- Release directory is not a Measurement build.'
}

$verifyMatches = Get-ChildItem -LiteralPath $modeDirectory -Recurse -Filter 'subdir.mk' |
    Select-String -Pattern 'NL_TEST_REPEAT_3_RUNS=1'
if (-not $verifyMatches) {
    throw 'QuickScreen3Run makefiles do not contain NL_TEST_REPEAT_3_RUNS=1.'
}

Write-Host '== Building isolated QuickScreen3Run image (NL_TEST_REPEAT_3_RUNS=1) =='
Invoke-BundledMake -BuildDirectory $modeDirectory -Clean

$destination = Assert-ChildPath (Join-Path $ProjectRoot 'Build\QuickScreen3Run') $ProjectRoot
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$stem = 'jigmotor_quickscreen3run'
foreach ($extension in @('elf', 'hex', 'map', 'list')) {
    $source = Join-Path $modeDirectory "jigmotor.$extension"
    if (-not (Test-Path $source)) { throw "Missing artifact: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $destination "$stem.$extension") -Force
}
$hashes = Get-FileHash (Join-Path $destination "$stem.elf"), (Join-Path $destination "$stem.hex") -Algorithm SHA256
$hashLines = $hashes | ForEach-Object { "$($_.Hash)  $([System.IO.Path]::GetFileName($_.Path))" }
Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Value $hashLines -Encoding ascii

$buildInfo = @"
QuickScreen3Run -- mechanical-pass A/B screening image
Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
SourceId: $sourceId
Mode: JIG_APP_MEASUREMENT (JIG_APP_MODE=2)
Batch protocol: NL_TEST_REPEAT_3_RUNS=1 (1 precondition + 3 official sweeps per button press)
PreconditionProtocol logged as: ONE_FULL_SWEEP_120S_V1_FAST3 (distinct from standard build's ONE_FULL_SWEEP_120S_V1)

Purpose: fast A/B check of whether a mechanical change (sensor gap, mount
hardware, remount) moved NL at all. Same official open-loop measurement
formula and canonical 64-sample capture as the standard build -- only the
number of official sweeps per batch differs.

Do NOT treat a result from this image as a qualified measurement on its
own. If a quick screen shows a difference worth pursuing, confirm it on
the standard 10-run build before drawing any conclusion.
"@
Set-Content -LiteralPath (Join-Path $destination 'build_info.txt') -Value $buildInfo -Encoding ascii

Write-Host "[ OK ] QuickScreen3Run artifacts: $destination (SourceId=$sourceId)"
