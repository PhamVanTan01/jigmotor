$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'fixtures\control-c0-sample.log'
$csv = Join-Path $env:TEMP 'jigmotor-control-c0-sample.csv'
$analysis = & (Join-Path $PSScriptRoot 'analyze_control_c0.ps1') `
    -LogPath $fixture -CsvPath $csv

Assert-True ($analysis.Result -eq 'OK') 'C0 analyzer lost summary result.'
Assert-True ($analysis.EvidenceCount -eq 4 -and $analysis.HoldCount -eq 2) `
    'C0 analyzer evidence/hold count is incorrect.'
Assert-True ($analysis.FinalActualMilliDeg -eq 1005 -and
    $analysis.FinalErrorMilliDeg -eq -5) 'C0 analyzer final values are incorrect.'
Assert-True ([math]::Abs($analysis.HoldRmsErrorMilliDeg - 35.532) -lt 0.001) `
    'C0 analyzer hold RMS is incorrect.'
Assert-True ($analysis.HoldMaxAbsErrorMilliDeg -eq 50 -and
    $analysis.OvershootMilliDeg -eq 5) 'C0 analyzer peak metrics are incorrect.'
Assert-True ($analysis.Rise90Sequence -eq 2 -and
    $analysis.Settle100mdegSequence -eq 2) 'C0 analyzer timing metrics are incorrect.'
Assert-True ([math]::Abs($analysis.MaxLoopUsAt168MHz - 100.0) -lt 0.001 -and
    [math]::Abs($analysis.MaxSpiLatencyUsAt168MHz - 10.0) -lt 0.001) `
    'C0 analyzer cycle-to-time conversion is incorrect.'
Assert-True ((Test-Path -LiteralPath $csv) -and
    (Import-Csv -LiteralPath $csv).Count -eq 4) 'C0 CSV export failed.'

Write-Host '[ OK ] Control C0 analyzer regression tests passed.'
