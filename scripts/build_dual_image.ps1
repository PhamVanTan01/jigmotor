# Builds independently compiled Control and Measurement firmware images from
# the CubeIDE-generated Release makefiles. Measurement keeps JIG_APP_MODE=2;
# Control is rebuilt in an isolated sibling directory with JIG_APP_MODE=1.

param(
    [ValidateSet('Control', 'Measurement', 'All')]
    [string]$Mode = 'All'
)

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

function Copy-ArtifactSet {
    param([string]$SourceDirectory, [string]$ModeName)
    $destination = Assert-ChildPath `
        (Join-Path $ProjectRoot "Build\$ModeName") $ProjectRoot
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    $stem = "jigmotor_$($ModeName.ToLowerInvariant())"
    foreach ($extension in @('elf', 'hex', 'map', 'list')) {
        $source = Join-Path $SourceDirectory "jigmotor.$extension"
        if (-not (Test-Path $source)) { throw "Missing artifact: $source" }
        Copy-Item -LiteralPath $source `
            -Destination (Join-Path $destination "$stem.$extension") -Force
    }
    $hashes = Get-FileHash `
        (Join-Path $destination "$stem.elf"), `
        (Join-Path $destination "$stem.hex") -Algorithm SHA256
    $hashLines = $hashes | ForEach-Object {
        "$($_.Hash)  $([System.IO.Path]::GetFileName($_.Path))"
    }
    Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') `
        -Value $hashLines -Encoding ascii
    return $destination
}

if (-not $Global:MakeExe -or -not $Global:ArmGccBinDir) {
    throw 'Bundled STM32CubeIDE make/GCC toolchain not found.'
}

$releaseDirectory = Join-Path $ProjectRoot 'Release'
if (-not (Test-Path (Join-Path $releaseDirectory 'makefile'))) {
    throw 'Release makefile missing. Run build_cubeide.ps1 -Configuration Release first.'
}

function Build-ModeImage {
    param([string]$ModeName, [int]$ModeValue)
    Write-Host "== Building independently compiled $ModeName image =="
    $modeDirectory = Assert-ChildPath (Join-Path $ProjectRoot $ModeName) $ProjectRoot
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
    $modeDefine = "-DJIG_APP_MODE=$ModeValue"
    $sourceDefine = "-DJIG_BUILD_SOURCE_ID=\`"$sourceId\`""

    $makeFragments = Get-ChildItem -LiteralPath $modeDirectory `
        -Recurse -Filter 'subdir.mk'
    foreach ($fragment in $makeFragments) {
        $content = Get-Content -LiteralPath $fragment.FullName -Raw
        if ($content.Contains('-DJIG_APP_MODE=2')) {
            $content = $content.Replace('-DJIG_APP_MODE=2',
                "$modeDefine $sourceDefine")
            Set-Content -LiteralPath $fragment.FullName -Value $content -NoNewline
        }
    }
    $modeMatches = Get-ChildItem -LiteralPath $modeDirectory -Recurse `
        -Filter 'subdir.mk' | Select-String -Pattern ([regex]::Escape($modeDefine))
    if (-not $modeMatches) {
        throw "$ModeName makefiles do not contain $modeDefine."
    }

    Invoke-BundledMake -BuildDirectory $modeDirectory -Clean
    $output = Copy-ArtifactSet -SourceDirectory $modeDirectory -ModeName $ModeName
    Write-Host "[ OK ] $ModeName artifacts: $output (SourceId=$sourceId)"
}

if ($Mode -eq 'Measurement' -or $Mode -eq 'All') {
    Build-ModeImage -ModeName 'Measurement' -ModeValue 2
}

if ($Mode -eq 'Control' -or $Mode -eq 'All') {
    Build-ModeImage -ModeName 'Control' -ModeValue 1
}

Write-Host '[ OK ] Dual-image build completed.'
