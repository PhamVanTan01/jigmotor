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

Assert-True ($source -match ('#define\s+ENABLE_SWEEP_POINT_CREEP_V56_THREE_STAGE_LANDING\s+' + $expectedFlag) -and
        $source -match 'V5\.6 three-stage landing requires V5\.5 dynamic BASE escalation' -and
        $source -match 'V5\.6 three-stage landing requires V5\.4 universal fine landing' -and
        $source -match 'V5\.6 motion experiment and V5\.4a diagnostic identity are mutually exclusive') `
    'V5.6 feature default/dependencies are invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_BASE_TO_EXTENDED_THREE_STAGE_LANDING_V3"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_LANDING_PROTOCOL_ID\s+"LIVE_GAP_MONOTONIC_16_8_4_DIAG_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_STEP_SELECTION_RULE_ID\s+"COARSE_GT96_MID_GT64_FINE_LE64"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RESPONSE_POLICY_ID\s+"MEASURE_ONLY_NO_RUNTIME_ADAPTATION_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_PROTOCOL_ID\s+"MONOTONIC_PHASE_SINGLE_REVERSAL_V2"') `
    'V5.6 protocol identity is missing or reuses V5.5 semantics.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_V56_MID_ENTRY_GAP_RAW\s+96U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V56_MID_STEP_RAW\s+8U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V56_STICK_SLIP_JUMP_DELTA_RAW\s+96U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_ENTRY_RAW\s+64U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_STEP_RAW\s+4U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V55_BASE_HARD_MAX_TOTAL_RAW\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V55_BASE_MAX_ITERATIONS\s+NL_SWEEP_CREEP_V54_EXTENDED_MAX_ITERATIONS') `
    'V5.6 16/8/4 thresholds or frozen V5.5 caps changed.'

$profileStart = $source.IndexOf('static MA600_Result_t CreepToUnwrappedTargetProfiled(')
$profileEnd = $source.IndexOf('static MA600_Result_t CreepToUnwrappedTarget(', $profileStart)
$profile = if ($profileStart -ge 0 -and $profileEnd -gt $profileStart) {
    $source.Substring($profileStart, $profileEnd - $profileStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($profile) -and
        $profile -match 'NL_CREEP_LANDING_PHASE_COARSE' -and
        $profile -match 'NL_CREEP_LANDING_PHASE_MID' -and
        $profile -match 'NL_CREEP_LANDING_PHASE_FINE' -and
        $profile -match 'fineLanding->midEntryRaw' -and
        $profile -match 'fineLanding->midStepRaw' -and
        $profile -match 'landingPhase\s*!=\s*NL_CREEP_LANDING_PHASE_COARSE' -and
        $profile.IndexOf('diag->stickSlipJumpDetected = true') -lt $profile.IndexOf('if (stopOnTargetCrossing') -and
        $profile -notmatch 'pointIndex|JIG[0-9]|MotorID') `
    'V5.6 state selection is not live-gap-only, monotonic, or jump-before-crossing.'

Assert-True ($source -match 'NL_CREEP_STEP_PHASE_MID' -and
        $source -match 'NL_CREEP_STEP_PHASE_RECOVERY_MID' -and
        $source -match 'return "MID"' -and
        $source -match 'return "RECOVERY_MID"') `
    'Schema-3 MID phase names are incomplete.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        $capture -match 'creepMidCorrectionRaw' -and
        $capture -match 'creepCoarseTailDirectedRaw' -and
        $capture -match 'NlCreepMergePhaseResponse' -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.6 capture telemetry is incomplete or writes UART during motion.'

Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=9' -and
        $source -match 'LandingProtocol=%s,StepSelectionRule=%s,ResponsePolicy=%s' -and
        $source -match 'MidEntryBasis=ABS_LIVE_TARGET_GAP_BEFORE_COMMAND' -and
        $source -match 'JumpThresholdBasis=ABS_SETTLED_OBSERVED_DELTA_PER_COMMAND' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=9' -and
        $source -match 'MidLandingAttempted=%d,MidIterations=%u,MidCorrectionRaw=%u' -and
        $source -match 'CoarseTailDirectedRaw=%ld,CoarseTailCommandRaw=%lu' -and
        $source -match 'SWEEP_CREEP_STEP,SchemaVersion=3' -and
        $source -match 'SWEEP_CREEP_RESPONSE,SchemaVersion=1' -and
        $source -match 'MidDirectedResponseRaw=%ld' -and
        $source -match 'SweepPointCreepExpectedPointTelemetry=%lu' -and
        $source -match 'SweepPointCreepEmittedStepTelemetry=%lu') `
    'V5.6 schema 9/3 or completeness telemetry is incomplete.'

$emissionGuard = [regex]::Match($source,
    '(?s)#if ENABLE_SWEEP_POINT_CREEP_V56_THREE_STAGE_LANDING\s*if \(creepResult == NL_CREEP_NOT_RUN\)\s*#else.*?#endif').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($emissionGuard) -and
        $emissionGuard -match '(?s)#if ENABLE_SWEEP_POINT_CREEP_V56_THREE_STAGE_LANDING\s*if \(creepResult == NL_CREEP_NOT_RUN\)\s*#else') `
    'V5.6 still filters BASE-OK point telemetry.'

Assert-True (([regex]::Matches($source, '\(void\)CreepToUnwrappedTarget\(').Count -eq 2) -and
        $source -match '(?s)static MA600_Result_t CreepToUnwrappedTarget\(.*?return CreepToUnwrappedTargetProfiled\(.*?NULL\);' -and
        $source -match 'NlCreepStepTrace_t\s+creepV54Trace\[NL_SWEEP_CREEP_V54_TRACE_CAPACITY\]' -and
        $source -notmatch 'creepV54Trace\s*\[NL_MAX_SWEEP_POINTS\]') `
    'V5.6 changed B0-B wrapper isolation or O(1) trace storage.'

$parser = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/parse_sweep_creep_log.m') -Raw
$analyzer = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/analyze_sweep_creep_batch.m') -Raw
$matlabTest = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/tests/test_nl_stability_analysis.m') -Raw
Assert-True ($parser -match 'MidLandingAttempted' -and
        $parser -match 'SweepPointCreepMidDirectedResponseRaw' -and
        $parser -match 'SweepPointCreepExpectedPointTelemetry' -and
        $parser -match 'SWEEP_CREEP_RESPONSE' -and
        $analyzer -match 'PhaseResponseByLabel' -and
        $analyzer -match 'TelemetryCompleteness' -and
        $analyzer -match '1000\.0 \* directedRaw / commandRaw' -and
        $matlabTest -match 'SWEEP_CREEP_CONFIG,SchemaVersion=9' -and
        $matlabTest -match 'EfficiencyPermille - 750\.0') `
    'MATLAB parser/analyzer/synthetic V5.6 coverage is incomplete.'

Write-Host '[ OK ] Sweep-point creep V5.6 three-stage response contract tests passed.'
