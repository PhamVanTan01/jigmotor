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

Assert-True ($source -match ('#define\s+ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE\s+' + $expectedFlag) -and
        $source -match '(?s)#if\s+ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE\s*\\\s*&&\s*!ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING\s*#error\s+"V5\.4a fine-failure trace requires V5\.4 universal fine landing"') `
    'V5.4a flag or dependency guard is invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_TRACE_POLICY_ID\s+"FIRST_FINE_BUDGET_OR_INTEGRITY_FAILURE_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_TRACE_POLICY_ID\s+"FIRST_INTEGRITY_FAILURE_V1"') `
    'V5.4a and frozen V5.4 trace policy identities must both remain buildable.'

$helper = [regex]::Match($source,
    '(?s)static bool NlCreepDiagnosticsShouldLockTrace\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($helper) -and
        $helper -match '#elif ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE' -and
        $helper -match 'diag->fineLandingAttempted\s*&&\s*diag->result\s*==\s*NL_CREEP_BUDGET_EXCEEDED' -and
        $helper -match 'return NlCreepResultIsIntegrityFailure\(diag->result\);' -and
        $helper -notmatch 'NL_CREEP_TIMEOUT' -and
        $helper -notmatch 'NL_CREEP_RECOVERY_BUDGET_EXCEEDED') `
    'V5.4a trace predicate must add only fine-attempted ordinary budget exhaustion.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        $capture -match 'creepV54TracePoint\s*<\s*0\s*&&\s*NlCreepDiagnosticsShouldLockTrace\(&pointCreepDiag\)' -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.4a trace lock is missing or CaptureSweep is no longer UART-silent.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_STEP_RAW\s+16' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_ENTRY_RAW\s+64U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_FINE_STEP_RAW\s+4U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_BASE_MAX_TOTAL_RAW\s+220LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW\s+320LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_BASE_MAX_ITERATIONS\s+56U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_EXTENDED_MAX_ITERATIONS\s+81U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_POWER\s+1\.0f' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V54_TRACE_CAPACITY\s+100U') `
    'V5.4a must not alter any locked V5.4 motion or trace-capacity constant.'

Assert-True ($source -match 'TracePolicy=%s,TraceCapacity=%u' -and
        $source -match 'TraceCaptured=%d,TraceCount=%u' -and
        $source -match 'SWEEP_CREEP_STEP,SchemaVersion=2' -and
        $source -match 'SweepPointCreepTracePoint=%ld' -and
        $source -match 'NlCreepStepTrace_t\s+creepV54Trace\[NL_SWEEP_CREEP_V54_TRACE_CAPACITY\]' -and
        $source -notmatch 'creepV54Trace\s*\[NL_MAX_SWEEP_POINTS\]') `
    'V5.4a must reuse the existing bounded schema-7/schema-2 telemetry.'

Assert-True (([regex]::Matches($source, '\(void\)CreepToUnwrappedTarget\(').Count -eq 2) -and
        $source -match '(?s)static MA600_Result_t CreepToUnwrappedTarget\(.*?return CreepToUnwrappedTargetProfiled\(.*?NULL\);') `
    'V5.4a must not change the two frozen B0-B compatibility-wrapper calls.'

Write-Host '[ OK ] Sweep-point creep V5.4a first fine-budget trace contract tests passed.'
