param(
    [string]$SummaryCsv = '.\analysis\output\a2-a2e\powershell-summary.csv',
    [string]$EvidenceDirectory = '.\analysis\output\a2-a2e\evidence',
    [string]$OutputDirectory = '.\analysis\output\a2-a2e\matlab',
    [string]$MatlabExecutable = 'E:\matlab\bin\matlab.exe',
    [switch]$RunTests
)

$ErrorActionPreference = 'Stop'

foreach ($path in @($MatlabExecutable, $SummaryCsv, $EvidenceDirectory)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required MATLAB analysis path not found: $path"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$sourceDirectory = Join-Path $root 'analysis\matlab'
$summaryPath = (Resolve-Path -LiteralPath $SummaryCsv).Path
$evidencePath = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$outputPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $OutputDirectory))

function Convert-ToMatlabLiteral {
    param([string]$Value)
    $Value.Replace("'", "''")
}

$sourceLiteral = Convert-ToMatlabLiteral $sourceDirectory
$summaryLiteral = Convert-ToMatlabLiteral $summaryPath
$evidenceLiteral = Convert-ToMatlabLiteral $evidencePath
$outputLiteral = Convert-ToMatlabLiteral $outputPath

$commands = @("addpath('$sourceLiteral')")
if ($RunTests) {
    $testDirectory = Convert-ToMatlabLiteral (Join-Path $sourceDirectory 'tests')
    $commands += "addpath('$testDirectory')"
    $commands += 'test_a2_analysis'
}
$commands += "run_a2_power_envelope('$summaryLiteral','$evidenceLiteral','$outputLiteral')"

& $MatlabExecutable -batch ($commands -join ';')
if ($LASTEXITCODE -ne 0) {
    throw "MATLAB A2 analysis failed with exit code $LASTEXITCODE."
}

Write-Host "[ OK ] MATLAB A2 analysis: $outputPath"
