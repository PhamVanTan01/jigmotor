$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$analyzer = Join-Path $PSScriptRoot 'analyze_7pp_stutter_trace.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\7pp-stutter-trace.log'
$summaryCsv = Join-Path ([System.IO.Path]::GetTempPath()) `
    "jigmotor-7pp-stutter-summary-$PID.csv"
$pointCsv = Join-Path ([System.IO.Path]::GetTempPath()) `
    "jigmotor-7pp-stutter-points-$PID.csv"

try {
    $summary = @(& $analyzer -Path $fixture -OutSummaryCsv $summaryCsv `
        -OutPointCsv $pointCsv)
    $points = @(Import-Csv -LiteralPath $pointCsv)

    if ($summary.Count -ne 1 -or $points.Count -ne 1) {
        throw 'Analyzer did not produce exactly one sweep and one point.'
    }
    if ($summary[0].Profile -ne '7PP_STUTTER_DIAG_P135_160_1RUN_V1' -or
            $summary[0].TraceStatus -ne 'VALID') {
        throw 'Trace profile/status was not preserved.'
    }
    if ([int]$points[0].LongestNearZeroTicks -ne 4 -or
            [int]$points[0].BacktrackCount -ne 1 -or
            [int]$points[0].MaxBacktrackRaw -ne 20) {
        throw 'Ramp plateau/backtrack metrics are incorrect.'
    }
    if ($points[0].Classification -ne 'MIXED' -or
            [int]$points[0].SettleElapsedMs -ne 100 -or
            [int]$points[0].FinalTargetErrorRaw -ne -1070) {
        throw 'Settle/classification metrics are incorrect.'
    }
    Write-Host '[ OK ] 7PP stutter trace analyzer contract passed.'
}
finally {
    Remove-Item -LiteralPath $summaryCsv, $pointCsv -Force `
        -ErrorAction SilentlyContinue
}
