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

Assert-True ($source -match ('#define\s+ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION\s+' + $expectedFlag) -and
        $source -match '(?s)#if\s+ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION\s*\\\s*&&\s*!ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING\s*#error\s+"V5\.5 dynamic BASE escalation requires V5\.4 universal fine landing"' -and
        $source -match '(?s)#if\s+ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION\s*\\\s*&&\s*ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE\s*#error\s+"V5\.4a diagnostic trace and V5\.5 motion experiment are mutually exclusive"') `
    'V5.5 flag, V5.4 dependency or V5.4a exclusion guard is invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_BASE_TO_EXTENDED_ESCALATION_UNIVERSAL_FINE_LANDING_V2"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_BUDGET_ESCALATION_ID\s+"BASE_EXHAUSTION_TO_EXTENDED_CAP_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_TRACE_POLICY_ID\s+"FIRST_HARD_CAP_BUDGET_OR_INTEGRITY_FAILURE_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_FINE_LANDING_PROTOCOL_ID\s+"UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1"') `
    'V5.5 protocol identities are missing or ambiguous.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_BASE_MAX_TOTAL_RAW\s+220LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW\s+320LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V55_BASE_HARD_MAX_TOTAL_RAW\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V55_BASE_MAX_ITERATIONS\s+NL_SWEEP_CREEP_V54_EXTENDED_MAX_ITERATIONS' -and
        $source -match '#define\s+NL_SWEEP_CREEP_STEP_RAW\s+16' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_ENTRY_RAW\s+64U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_STEP_RAW\s+4U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_JUMP_THRESHOLD_RAW\s+96U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_RECOVERY_MAX_TOTAL_RAW\s+64LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_RECOVERY_MAX_ITERATIONS\s+17U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_POWER\s+1\.0f') `
    'V5.5 must reuse the frozen V5.4 step/power/safety constants and 320-raw cap.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
$v55Selection = [regex]::Match($capture,
    '(?s)#if ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION.*?bool v54TraceAvailable').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        -not [string]::IsNullOrWhiteSpace($v55Selection) -and
        $v55Selection -match '(?s)creepBudgetClass\s*==\s*NL_SWEEP_CREEP_BUDGET_BASE.*?creepMaxTotalRaw\s*=\s*NL_SWEEP_CREEP_V55_BASE_HARD_MAX_TOTAL_RAW.*?creepMaxIterations\s*=\s*NL_SWEEP_CREEP_V55_BASE_MAX_ITERATIONS' -and
        $capture -match 'pointCreepDiag\.totalCorrectionRaw\s*>\s*NL_SWEEP_CREEP_BASE_MAX_TOTAL_RAW' -and
        $v55Selection -notmatch 'pointIndex\s*==' -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.5 BASE escalation must be live budget-driven, point-independent and UART-silent.'

$traceHelper = [regex]::Match($source,
    '(?s)static bool NlCreepDiagnosticsShouldLockTrace\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($traceHelper) -and
        $traceHelper -match '#if ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION' -and
        $traceHelper -match 'diag->result\s*==\s*NL_CREEP_BUDGET_EXCEEDED' -and
        $traceHelper -match 'return NlCreepResultIsIntegrityFailure\(diag->result\);') `
    'V5.5 must trace the first remaining hard-cap or integrity failure.'

Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=8' -and
        $source -match 'BudgetEscalationProtocol=%s,BaseBudgetRaw=%ld,BasePrimaryBudgetRaw=%ld' -and
        $source -match 'BaseHardBudgetRaw=%ld,BaseMaxIterations=%lu,BaseEscalatedMaxIterations=%lu' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=8' -and
        $source -match 'PrimaryBudgetRaw=%s,HardBudgetRaw=%s' -and
        $source -match 'BudgetEscalated=%d,EscalationCorrectionRaw=%s' -and
        $source -match 'SweepPointCreepBaseEscalationAttempted=%lu' -and
        $source -match 'SweepPointCreepBaseEscalationSucceeded=%lu' -and
        $source -match 'SweepPointCreepBaseEscalationFailed=%lu' -and
        $source -match 'SweepPointCreepBaseEscalationCorrectionRaw=%s') `
    'V5.5 schema-8 point/config or END rollup telemetry is incomplete.'

$parser = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/parse_sweep_creep_log.m') -Raw
$matlabTest = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/tests/test_nl_stability_analysis.m') -Raw
Assert-True ($parser -match 'BudgetEscalationProtocol' -and
        $parser -match 'BasePrimaryBudgetRaw' -and
        $parser -match 'BaseHardBudgetRaw' -and
        $parser -match 'BudgetEscalated' -and
        $parser -match 'EscalationCorrectionRaw' -and
        $parser -match 'SweepPointCreepBaseEscalationSucceeded' -and
        $matlabTest -match 'SWEEP_CREEP_CONFIG,SchemaVersion=8' -and
        $matlabTest -match 'BASE_EXHAUSTION_TO_EXTENDED_CAP_V1') `
    'MATLAB parser/synthetic regression does not cover V5.5 schema 8.'

Assert-True (([regex]::Matches($source, '\(void\)CreepToUnwrappedTarget\(').Count -eq 2) -and
        $source -match '(?s)static MA600_Result_t CreepToUnwrappedTarget\(.*?return CreepToUnwrappedTargetProfiled\(.*?NULL\);' -and
        $source -match 'NlCreepStepTrace_t\s+creepV54Trace\[NL_SWEEP_CREEP_V54_TRACE_CAPACITY\]' -and
        $source -notmatch 'creepV54Trace\s*\[NL_MAX_SWEEP_POINTS\]') `
    'V5.5 changed frozen B0-B wrapper isolation or bounded trace storage.'

Write-Host '[ OK ] Sweep-point creep V5.5 dynamic BASE escalation contract tests passed.'
