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
Assert-True ($source -match (('#define\s+ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING\s+' + $expectedFlag)) -and
        $source -match '#if\s+ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING\s+&&\s+!ENABLE_SWEEP_POINT_CREEP' -and
        $source -match '#error\s+"V5\.4 universal fine landing requires ENABLE_SWEEP_POINT_CREEP"' -and
        $source -match '(?s)ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING.*?&& ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING.*?#error\s+"V5\.3 and V5\.4 fine-landing experiments are mutually exclusive"') `
    'V5.4 build flag, dependency guard, or V5.3/V5.4 exclusion guard is invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_GAP_BUDGET_UNIVERSAL_FINE_LANDING_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_FINE_LANDING_PROTOCOL_ID\s+"UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_PROTOCOL_ID\s+"UNIVERSAL_FINE_SINGLE_REVERSAL_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_FINE_SELECTION_RULE_ID\s+"ALL_POINTS_LIVE_GAP_LE_ENTRY"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_TRACE_POLICY_ID\s+"FIRST_INTEGRITY_FAILURE_V1"') `
    'V5.4 protocol or selection/trace identity changed.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_BASE_MAX_TOTAL_RAW\s+220LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW\s+320LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_STEP_RAW\s+16' -and
        $source -match '#define\s+NL_SWEEP_CREEP_DEADBAND_RAW\s+NL_B0B_TARGET_DEADBAND_RAW' -and
        $source -match '#define\s+NL_B0B_TARGET_DEADBAND_RAW\s+16LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_ENTRY_RAW\s+64U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_STEP_RAW\s+4U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_JUMP_THRESHOLD_RAW\s+96U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_BASE_MAX_ITERATIONS\s+56U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_EXTENDED_MAX_ITERATIONS\s+81U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_RECOVERY_MAX_TOTAL_RAW\s+64LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_RECOVERY_MAX_ITERATIONS\s+17U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_TRACE_CAPACITY\s+100U') `
    'V5.4 locked budget/fine/jump/recovery constants changed.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($capture)) 'Could not locate CaptureSweep.'

$callBlock = [regex]::Match($capture,
    '(?s)#if ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING\s*/\* Every point uses.*?#elif ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($callBlock) -and
        $callBlock -notmatch 'pointIndex' -and
        $callBlock -match 'CreepToUnwrappedTargetProfiled\(' -and
        $callBlock -match 'NL_SWEEP_CREEP_V54_BASE_MAX_ITERATIONS' -and
        $callBlock -match 'NL_SWEEP_CREEP_V54_EXTENDED_MAX_ITERATIONS' -and
        $callBlock -match 'creepV54TracePoint\s*<\s*0' -and
        $callBlock -match 'NL_SWEEP_CREEP_V54_RECOVERY_MAX_ITERATIONS,\s*&fineLandingConfig\);') `
    'V5.4 must profile every main-sweep point from live gap, with no point-index policy.'

Assert-True ($capture -match 'creepV54TracePoint\s*=\s*-1;' -and
        $capture -match 'NlCreepDiagnosticsShouldLockTrace\(&pointCreepDiag\)' -and
        $capture -match 'creepV54TracePoint\s*=\s*\(int16_t\)pointIndex;' -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.4 first-failure trace lock is incomplete or CaptureSweep is no longer UART-silent.'

Assert-True ($source -match '(?s)static bool NlCreepResultIsIntegrityFailure.*?NL_CREEP_TARGET_CROSSED.*?NL_CREEP_RECOVERY_TIMEOUT.*?NL_CREEP_RECOVERY_BUDGET_EXCEEDED.*?NL_CREEP_RECOVERY_RECROSSED.*?NL_CREEP_STICK_SLIP_JUMP.*?NL_CREEP_ACQUISITION_ERROR' -and
        $source -match '(?s)static bool NlCreepDiagnosticsShouldLockTrace.*?return NlCreepResultIsIntegrityFailure\(diag->result\);' -and
        $source -match 'NlCreepStepTrace_t\s+creepV54Trace\[NL_SWEEP_CREEP_V54_TRACE_CAPACITY\]' -and
        $source -notmatch 'creepV54Trace\s*\[NL_MAX_SWEEP_POINTS\]') `
    'V5.4 integrity-failure classification or bounded O(1) trace storage changed.'

Assert-True (([regex]::Matches($source, '\(void\)CreepToUnwrappedTarget\(').Count -eq 2) -and
        $source -match '(?s)static MA600_Result_t CreepToUnwrappedTarget\(.*?return CreepToUnwrappedTargetProfiled\(.*?NULL\);') `
    'Both and only the two frozen B0-B legs must retain the NULL-profile wrapper.'

Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=7' -and
        $source -match 'FineSelectionRule=%s,FineTargetPoint=-1' -and
        $source -match 'TracePolicy=%s,TraceCapacity=%u' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=7' -and
        $source -match 'TraceCaptured=%d,TraceCount=%u' -and
        $source -match 'SWEEP_CREEP_STEP,SchemaVersion=2' -and
        $source -match 'Point=%d,Official=0,StepOrder=%lu' -and
        $source -match 'SweepPointCreepFineBaseAttempted=%lu' -and
        $source -match 'SweepPointCreepFineExtendedAttempted=%lu' -and
        $source -match 'SweepPointCreepTracePoint=%ld') `
    'V5.4 config, point, step, or END telemetry contract is incomplete.'

Assert-True ($source -match 'sweepPointCreepRecoveryFailedCount == 0U\s*&& c->sweepPointCreepStickSlipJumpCount == 0U' -and
        $source -match '(?s)eligibleForStatistics = !preconditionRun\s*&& preconditionValid.*?sweepPointCreepStickSlipJumpCount == 0U' -and
        $source -match '\.stack_size\s*=\s*12288U') `
    'V5.4 must retain recovery/jump validity gating and the validated test-task stack.'

$parserPath = Join-Path $root 'analysis/matlab/nl/parse_sweep_creep_log.m'
$parser = Get-Content -LiteralPath $parserPath -Raw
$matlabTestPath = Join-Path $root 'analysis/matlab/tests/test_nl_stability_analysis.m'
$matlabTest = Get-Content -LiteralPath $matlabTestPath -Raw
Assert-True ($parser -match '"FineSelectionRule"' -and
        $parser -match '"TracePolicy"' -and
        $parser -match '"TraceCaptured"' -and
        $parser -match '"SweepPointCreepFineBaseAttempted"' -and
        $parser -match '"SweepPointCreepFineExtendedAttempted"' -and
        $parser -match '"SweepPointCreepTracePoint"' -and
        $matlabTest -match 'SWEEP_CREEP_CONFIG,SchemaVersion=7' -and
        $matlabTest -match 'SWEEP_CREEP_POINT,SchemaVersion=7' -and
        $matlabTest -match 'SWEEP_CREEP_STEP,SchemaVersion=2') `
    'MATLAB parser or synthetic schema-7/schema-2 regression coverage is incomplete.'

Write-Host '[ OK ] Sweep-point creep V5.4 universal live-gap fine-landing contract tests passed.'
