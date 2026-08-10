param(
    [switch]$FeatureBuild
)

$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'Core/Src/nonlinear_test.c'
$source = Get-Content -LiteralPath $sourcePath -Raw
$expectedFlag = if ($FeatureBuild) { '1' } else { '0' }

Assert-True ($source -match ('#define\s+ENABLE_SWEEP_POINT_CREEP_V57_HARDCAP_HOLD_DIAG\s+' + $expectedFlag) -and
        $source -match 'V5\.7 hard-cap hold diagnostic requires frozen V5\.5 motion' -and
        $source -match 'V5\.7 diagnoses V5\.5; V5\.6 three-stage motion must remain disabled' -and
        $source -match 'V5\.7 and V5\.4a are separate diagnostic identities') `
    'V5.7 feature default or dependency guards are invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_HOLD_SAMPLE_COUNT\s+6U' -and
        $source -match 'FIRST_HARD_CAP_PASSIVE_HOLD_0_10_25_50_100_200MS_V1' -and
        $source -match '0U, 10U, 25U, 50U, 100U, 200U' -and
        $source -match 'NL_SWEEP_CREEP_HOLD_MATERIAL_DELTA_RAW\s+NL_POINT_SETTLE_ERROR_RAW') `
    'V5.7 hold schedule or predeclared material threshold changed.'

$holdStart = $source.IndexOf('static void CaptureHardcapHoldProbe(')
$holdEnd = $source.IndexOf('static void ComputeShadowMetrics(', $holdStart)
$hold = if ($holdStart -ge 0 -and $holdEnd -gt $holdStart) {
    $source.Substring($holdStart, $holdEnd - $holdStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($hold) -and
        $hold -match 'MA600_AcquireSample' -and
        $hold -match 'RecordHardcapHoldSample' -and
        $source -match 'diag->targetUnwrappedRaw - sample->unwrappedRaw' -and
        $hold -notmatch 'Motor_SetElectricalPos\s*\(|CreepToUnwrappedTarget\s*\(|RampCommandToTarget\s*\(|LogLine(?:Large)?\s*\(') `
    'V5.7 hold must be passive acquisition-only and UART-silent.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
$dataFreeze = $capture.IndexOf('out->errorSamples[pointIndex] = error;')
$probeCall = $capture.IndexOf('CaptureHardcapHoldProbe(out, &sweepAcquisition, &sample);')
$advancePoint = $capture.IndexOf('pointIndex++;', $probeCall)
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        $capture -match 'pointCreepDiag\.result == NL_CREEP_BUDGET_EXCEEDED' -and
        $capture -match 'diag->storedCommandRaw = pos' -and
        $dataFreeze -ge 0 -and $probeCall -gt $dataFreeze -and $advancePoint -gt $probeCall -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.7 candidate latch/probe order is not DATA-first and UART-silent.'

Assert-True ($source -match 'hardcapHoldAcquisition\.readAttempts' -and
        $source -match 'hardcapHoldAcquisition\.retryCount' -and
        $source -match 'hardcapHoldAcquisition\.transportErrorCount' -and
        $source -match 'hardcapHoldAcquisition\.jumpRejectCount' -and
        $source -match 'hardcapHoldAcquisition\.failedSampleCount' -and
        $source -match '(?s)eligibleForStatistics\s*=.*?ENABLE_SWEEP_POINT_CREEP_V57_HARDCAP_HOLD_DIAG.*?&& false') `
    'V5.7 reads leak into official Acq* or diagnostic runs remain eligible.'

Assert-True ($source -match 'SWEEP_CREEP_HOLD_CONFIG,SchemaVersion=1' -and
        $source -match 'SWEEP_CREEP_HOLD_SAMPLE,SchemaVersion=1' -and
        $source -match 'SWEEP_CREEP_HOLD_RESULT,SchemaVersion=1' -and
        $source -match 'STATIC_WITHIN_SETTLE_BAND' -and
        $source -match 'RELAXES_TOWARD_TARGET' -and
        $source -match 'DRIFTS_AWAY_FROM_TARGET' -and
        $source -match 'ClassificationBasis=CREEP_FINAL_TO_HOLD_200MS' -and
        $source -match 'PreHoldGapReductionRaw=%s,GapReductionRaw=%s,TotalGapReductionRaw=%s' -and
        $source -match 'Using only the post-DATA hold window would silently miss' -and
        $source -match 'NoMotorCommandDuringHold=1,PointDataFrozenBeforeHold=1') `
    'V5.7 audit telemetry or mechanism classifications are incomplete.'

$parser = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/parse_sweep_creep_log.m') -Raw
$analyzer = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/analyze_sweep_creep_batch.m') -Raw
$matlabTest = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/tests/test_nl_stability_analysis.m') -Raw
Assert-True ($parser -match 'SWEEP_CREEP_HOLD_CONFIG' -and
        $parser -match 'SWEEP_CREEP_HOLD_SAMPLE' -and
        $parser -match 'SWEEP_CREEP_HOLD_RESULT' -and
        $analyzer -match 'HoldByLabel' -and
        $analyzer -match 'MeanTotalGapReductionRaw' -and
        $matlabTest -match 'PRE_HOLD_DATA_WINDOW' -and
        $matlabTest -match 'MeanTotalGapReductionRaw == 12') `
    'MATLAB V5.7 parser/analyzer/synthetic coverage is incomplete.'

Write-Host '[ OK ] Sweep-point creep V5.7 passive hard-cap hold contract tests passed.'
