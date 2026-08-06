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
Assert-True ($source -match (('#define\s+ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING\s+' + $expectedFlag)) -and
        $source -match '#if\s+ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING\s+&&\s+!ENABLE_SWEEP_POINT_CREEP' -and
        $source -match '#error\s+"V5\.3 point-66 fine landing requires ENABLE_SWEEP_POINT_CREEP"') `
    'V5.3 build-mode flag is unexpected or not nested under main-sweep creep.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_GAP_BUDGET_POINT66_FINE_LANDING_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_FINE_LANDING_PROTOCOL_ID\s+"POINT66_FINE_STEP4_JUMP_GUARD_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_PROTOCOL_ID\s+"POINT66_FINE_SINGLE_REVERSAL_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_TARGET_POINT\s+66U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_FINE_ENTRY_RAW\s+64U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_FINE_STEP_RAW\s+4U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_JUMP_THRESHOLD_RAW\s+96U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_MAX_ITERATIONS\s+81U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_RECOVERY_MAX_TOTAL_RAW\s+64LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_RECOVERY_MAX_ITERATIONS\s+17U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V53_TRACE_CAPACITY\s+100U') `
    'V5.3 locked point/fine/jump/recovery constants or protocol IDs changed.'

$profiled = [regex]::Match($source,
    '(?s)static MA600_Result_t CreepToUnwrappedTargetProfiled\(.*?\n\}\s*\n\s*/\* Compatibility wrapper').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($profiled)) `
    'Could not locate the V5.3 profiled creep engine.'
Assert-True ($profiled -match 'finePhase = true;\s*diag->fineLandingAttempted = true;' -and
        $profiled -match 'uint32_t activeStepRaw = finePhase \? fineLanding->fineStepRaw : stepRaw;' -and
        $profiled -match 'observedDeltaRaw = anchor - anchorBeforeStep;' -and
        $profiled -match 'diag->result = NL_CREEP_STICK_SLIP_JUMP;\s*break;') `
    'V5.3 fine latch, live observed-delta calculation, or jump stop is missing.'

$jumpIndex = $profiled.IndexOf('diag->result = NL_CREEP_STICK_SLIP_JUMP;')
$crossingIndex = $profiled.IndexOf('if (stopOnTargetCrossing')
Assert-True ($jumpIndex -ge 0 -and $crossingIndex -gt $jumpIndex) `
    'Stick-slip jump classification must happen before crossing recovery.'

$wrapper = [regex]::Match($source,
    '(?s)static MA600_Result_t CreepToUnwrappedTarget\(.*?return CreepToUnwrappedTargetProfiled\(.*?NULL\);\s*\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($wrapper)) `
    'The frozen B0-B compatibility wrapper must call the profiled engine with NULL.'
Assert-True (([regex]::Matches($source, '\(void\)CreepToUnwrappedTarget\(').Count -eq 2)) `
    'Both and only the two B0-B approach legs must retain the compatibility wrapper.'

$callBlock = [regex]::Match($source,
    '(?s)#elif ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING\s*bool useV53FineLanding.*?#else\s*MA600_Result_t creepAcqResult = CreepToUnwrappedTarget').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($callBlock) -and
        $callBlock -match '\(uint32_t\)pointIndex\s*==\s*NL_SWEEP_CREEP_V53_TARGET_POINT' -and
        $callBlock -match 'creepMaxIterations = NL_SWEEP_CREEP_V53_MAX_ITERATIONS;' -and
        $callBlock -match 'NL_SWEEP_CREEP_V53_RECOVERY_MAX_ITERATIONS,\s*&fineLandingConfig\);' -and
        $callBlock -match 'else\s*\{\s*creepAcqResult = CreepToUnwrappedTarget\(') `
    'Only the explicit point-66 call site may opt into the V5.3 profile.'

Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=6' -and
        $source -match 'FineLandingProtocol=%s,FineTargetPoint=%u,FineEntryRaw=%u,FineStepRaw=%u' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=6' -and
        $source -match 'StickSlipJumpDetected=%d,MaxObservedStepDeltaRaw=%s,TraceCount=%u' -and
        $source -match 'SWEEP_CREEP_STEP,SchemaVersion=1' -and
        $source -match 'ObservedDeltaRaw=%s,GapAfterRaw=%s,StickSlipJumpDetected=%d') `
    'V5.3 config, point, or per-step deferred telemetry is incomplete.'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(' -and
        $capture -notmatch '"SWEEP_CREEP_STEP,SchemaVersion') `
    'CaptureSweep must remain UART-silent; V5.3 trace is RAM-only during motion.'

Assert-True ($source -match 'SweepPointCreepStickSlipJump=%lu' -and
        $source -match 'SweepPointCreepFineLandingAttempted=%lu' -and
        $source -match 'sweepPointCreepRecoveryFailedCount == 0U\s*&& c->sweepPointCreepStickSlipJumpCount == 0U' -and
        $source -match '(?s)eligibleForStatistics = !preconditionRun\s*&& preconditionValid.*?sweepPointCreepStickSlipJumpCount == 0U') `
    'V5.3 jump must be visible in END and suppress integrity/official eligibility.'

Assert-True ($source -match '\.stack_size\s*=\s*12288U' -and
        $source -match 'RUNTIME_CHECKPOINT,Stage=COOLDOWN_START,TestStackHighWaterWords=%lu,FreeHeap=%lu' -and
        $source -match 'COOLDOWN_PROGRESS,BatchID=%lu,CycleOrder=%lu,ElapsedMs=%lu,TargetMs=%lu') `
    'V5.3 stack-overflow fix or cooldown liveness telemetry is missing.'

Write-Host '[ OK ] Sweep-point creep V5.3 point-66 fine-landing contract tests passed.'
