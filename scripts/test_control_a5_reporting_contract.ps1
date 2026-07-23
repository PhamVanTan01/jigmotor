param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$EnginePath = Join-Path $Root 'Core/Src/control_engine.c'
$CapturePath = Join-Path $Root 'Core/Src/control_a5_capture.c'
$HeaderPath = Join-Path $Root 'Core/Inc/control_a5_capture.h'
$AnalyzerPath = Join-Path $PSScriptRoot 'analyze_control_a5.ps1'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$engine = Get-Content -LiteralPath $EnginePath -Raw
$capture = Get-Content -LiteralPath $CapturePath -Raw
$header = Get-Content -LiteralPath $HeaderPath -Raw
$analyzer = Get-Content -LiteralPath $AnalyzerPath -Raw

$reportStart = $engine.IndexOf('static void ControlReportA5(')
$reportEnd = $engine.IndexOf('static void ControlRunA4(', $reportStart)
Assert-True -Condition ($reportStart -ge 0 -and $reportEnd -gt $reportStart) -Message 'Cannot isolate ControlReportA5().'
$reportBody = $engine.Substring($reportStart, $reportEnd - $reportStart)

$runStart = $engine.IndexOf('static void ControlRunA5(')
$runEnd = $engine.IndexOf('static bool ControlA5AbortRequested(', $runStart)
Assert-True -Condition ($runStart -ge 0 -and $runEnd -gt $runStart) -Message 'Cannot isolate ControlRunA5().'
$runBody = $engine.Substring($runStart, $runEnd - $runStart)
$safeStopIndex = $runBody.IndexOf('safe_stop:')
Assert-True ($safeStopIndex -gt 0) 'A5 safe_stop label is missing.'
$beforeSafeStop = $runBody.Substring(0, $safeStopIndex)
$afterSafeStop = $runBody.Substring($safeStopIndex)

Assert-True -Condition (-not $beforeSafeStop.Contains('ControlLog(')) -Message 'A5 emits UART before the converged safe-stop path.'
$orderedTokens = @(
    'Motor_Disable();',
    'Motor_SetElectricalPos((uint16_t)CONTROL_A5_COMMAND_PHASE_RAW, 0.0f);',
    'ControlA5_RecordSafeStopState(&a5Report)',
    'ControlA5_FinalizeAfterSafeStop(&a5Report)',
    'ControlReportA5(&a5Report)'
)
$previous = -1
foreach ($token in $orderedTokens) {
    $index = $afterSafeStop.IndexOf($token)
    Assert-True ($index -gt $previous) "A5 deferred order is wrong at: $token"
    $previous = $index
}

$recordTypes = @('ARMED', 'IDENTITY', 'CLOCK', 'CONFIG', 'SUMMARY',
    'TIMING', 'HEALTH', 'STATE', 'RUNTIME', 'DATA')
foreach ($recordType in $recordTypes) {
    Assert-True -Condition ($reportBody.Contains("CONTROL_A5_$recordType,RecordVersion=1")) -Message "Missing versioned CONTROL_A5_$recordType record."
    Assert-True -Condition ($analyzer.Contains("'CONTROL_A5_$recordType'")) -Message "Analyzer does not consume CONTROL_A5_$recordType."
}
$dataLoop = 'for (uint32_t index = 0U; index < report->evidenceCount; index++)'
Assert-True -Condition ($reportBody.Contains($dataLoop)) -Message 'A5 DATA does not iterate the accepted evidence count exactly once.'
Assert-True -Condition ($reportBody.Contains('ControlA5_GetEvidenceBuffer()')) -Message 'A5 reporter is not reading the retained evidence buffer.'
Assert-True -Condition (-not ($capture -match 'ControlLog|HAL_UART|printf\s*\(')) -Message 'Timed A5 capture module acquired a UART/printf dependency.'
Assert-True -Condition ($header.Contains('#define CONTROL_A5_CAPTURE_INTEGRATION_ENABLED 1U')) -Message 'A5.4 must activate the capture integration default.'
Assert-True -Condition ($header.Contains('#define CONTROL_A5_PROFILE_ACTIVATION_ACK 1U')) -Message 'A5.4 must acknowledge the profile activation.'
Assert-True -Condition ($engine.Contains('char line[512];')) -Message 'Deferred logger line budget changed without review.'

Write-Host '[ OK ] A5.3 deferred reporting/safe-stop contract passed.'
