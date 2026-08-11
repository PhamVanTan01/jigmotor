$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

# --- Default-off, independent of the (already-rejected) soft-start flag. ---
Assert-True ($source -match '#ifndef\s+ENABLE_B0B_APPROACH_CREEP\s*[\r\n]+#define\s+ENABLE_B0B_APPROACH_CREEP\s+0') `
    'ENABLE_B0B_APPROACH_CREEP must default to 0.'
Assert-True ($source -match '#define\s+NL_B0B_CREEP_STEP_RAW\s+8' -and
        $source -match '#define\s+NL_B0B_CREEP_MAX_TOTAL_RAW\s+150LL' -and
        $source -match '#define\s+NL_B0B_CREEP_MAX_ITERATIONS\s+30U') `
    'Creep safety constants (step/budget/iteration cap) must match the documented first estimates.'
# Deadband is shared with the feed-forward experiment (Part 3) via
# NL_B0B_TARGET_DEADBAND_RAW, defined unconditionally so a
# feedforward=1/creep=0 build still compiles -- NL_B0B_CREEP_DEADBAND_RAW
# now aliases it instead of redefining its own literal. The EFFECTIVE
# value (16 raw) must still match the documented first estimate.
Assert-True ($source -match '(?m)^#define\s+NL_B0B_TARGET_DEADBAND_RAW\s+16LL' -and
        $source -match '#define\s+NL_B0B_CREEP_DEADBAND_RAW\s+NL_B0B_TARGET_DEADBAND_RAW') `
    'NL_B0B_CREEP_DEADBAND_RAW must alias the shared, unconditionally-defined NL_B0B_TARGET_DEADBAND_RAW (16 raw).'
Assert-True ($source -match '#define\s+NL_B0B_CREEP_PROTOCOL_ID\s+"ENCODER_CREEP_V1"' -and
        $source -match '#define\s+NL_B0B_CREEP_PROTOCOL_ID\s+"NONE"') `
    'Both protocol IDs (ENCODER_CREEP_V1 when flagged / NONE default) must exist.'

# --- Diagnostics types always declared (both branches compile). ---
$creepEnum = [regex]::Match($source, '(?s)typedef enum\s*\{.*?\}\s*NlCreepResult_t;').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($creepEnum) -and
        $creepEnum -match 'NL_CREEP_NOT_RUN\s*=\s*0,' -and
        $creepEnum -match 'NL_CREEP_OK,' -and
        $creepEnum -match 'NL_CREEP_TIMEOUT,' -and
        $creepEnum -match 'NL_CREEP_BUDGET_EXCEEDED,' -and
        $creepEnum -match 'NL_CREEP_TARGET_CROSSED,' -and
        $creepEnum -match 'NL_CREEP_ACQUISITION_ERROR,') `
    'NlCreepResult_t enum is missing or its shape changed.'
$creepDiagStruct = [regex]::Match($source, '(?s)typedef struct\s*\{[^{}]*?\}\s*NlCreepDiagnostics_t;').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($creepDiagStruct) -and
        $creepDiagStruct -match 'NlCreepResult_t result;' -and
        $creepDiagStruct -match 'uint32_t iterations;' -and
        $creepDiagStruct -match 'int64_t totalCorrectionRaw;' -and
        $creepDiagStruct -match 'int64_t finalGapRaw;') `
    'NlCreepDiagnostics_t struct is missing or its shape changed.'
Assert-True ($source -match 'NlCreepDiagnostics_t\s+backoffCreepDiag;\s*[\r\n]+\s*NlCreepDiagnostics_t\s+forwardCreepDiag;') `
    'NlSweepCapture_t is missing the per-leg creep diagnostic fields.'

# --- CreepToUnwrappedTarget: only compiled/called under the flag; permits one
# explicitly bounded recovery reversal; only touches the motor via Motor_SetElectricalPos
# (same power=1.0 convention as the rest of B0-B); reuses WaitForPointSettle
# rather than re-implementing settle logic.
# 2026-08-04: also reused (unchanged) by ENABLE_SWEEP_POINT_CREEP's own
# main-sweep-loop call site (see that flag's comment) -- the guard is now an
# OR of both flags so the function still compiles out entirely when BOTH are
# off, which is what this test actually cares about. ---
$creepFn = [regex]::Match($source,
    '(?s)#if ENABLE_B0B_APPROACH_CREEP \|\| ENABLE_SWEEP_POINT_CREEP\s*/\* Runs only AFTER.*?static MA600_Result_t CreepToUnwrappedTarget\(.*?\n\}\s*#endif').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($creepFn)) `
    'Could not locate a flag-gated CreepToUnwrappedTarget definition.'
Assert-True ($creepFn -match 'int direction = \(gap > 0\) \? 1 : -1;' -and
        ([regex]::Matches($creepFn, 'direction\s*=\s*-direction')).Count -eq 1 -and
        $creepFn -match 'diag->result = NL_CREEP_RECOVERY_RECROSSED;\s*break;') `
    'CreepToUnwrappedTarget must permit exactly one reversal and stop on a recovery re-cross.'
# 2026-08-04 v3: power/step/deadband/budget/iterations are now caller-
# supplied parameters (not hardcoded to the B0-B literals/macros), so
# ENABLE_SWEEP_POINT_CREEP's own call site can use its own tuning without
# touching B0-B's behavior. The function body must use its own parameters;
# B0-B's *call sites* (checked further below) must still pass the exact
# original literals/macros, which is what actually pins B0-B's behavior.
Assert-True ($creepFn -match 'int32_t \*commandPos, int64_t targetUnwrapped,\s*[\r\n\s]*MA600_Sample_t \*anchorSample, NlCreepDiagnostics_t \*diag,\s*[\r\n\s]*uint32_t stepRaw, uint32_t deadbandRaw, int64_t maxTotalRaw,\s*[\r\n\s]*uint32_t maxIterations, float power, bool stopOnTargetCrossing,\s*[\r\n\s]*int64_t recoveryMaxTotalRaw, uint32_t recoveryMaxIterations\)') `
    'CreepToUnwrappedTarget must take ordinary and recovery limits as caller parameters.'
Assert-True ($creepFn -match 'Motor_SetElectricalPos\(\(uint16_t\)\*commandPos,\s*power\)') `
    'CreepToUnwrappedTarget must command through Motor_SetElectricalPos using its own power parameter.'
Assert-True ($creepFn -match 'WaitForPointSettle\(sweepAcquisition,\s*[\r\n\s]*anchor \+ step,\s*false,\s*&microSettle\)') `
    'CreepToUnwrappedTarget must reuse WaitForPointSettle (targetRequired=false) for each micro-step, not new settle logic.'
Assert-True ($creepFn -match 'diag->iterations >= maxIterations' -and
        $creepFn -match 'diag->totalCorrectionRaw >= maxTotalRaw' -and
        $creepFn -match 'diag->recoveryIterations >= recoveryMaxIterations' -and
        $creepFn -match 'diag->recoveryCorrectionRaw >= recoveryMaxTotalRaw' -and
        $creepFn -match 'AbsI64ToU64\(gap\) <= \(uint64_t\)deadbandRaw') `
    'CreepToUnwrappedTarget must check ordinary/recovery caps and deadband every loop pass.'
Assert-True ($creepFn -match 'NL_SETTLE_ACQUISITION_ERROR' -and
        $creepFn -match 'NL_CREEP_ACQUISITION_ERROR') `
    'CreepToUnwrappedTarget must propagate a real sensor acquisition error distinctly from timeout/budget.'

# --- RampCommandToTarget/the 40-tick quintic are untouched: creep is a
# separate, later stage, not a change to the existing ramp. ---
Assert-True ($source -match '(?s)static MA600_Result_t RampCommandToTarget\(\s*MA600_AcquisitionContext_t \*sweepAcquisition,\s*int32_t \*pos,\s*int32_t targetPos,\s*uint32_t \*stepsExecuted,\s*int64_t \*stepUnwrappedRawLog,\s*uint8_t stepLogCapacity,\s*uint32_t stepDelayMs,\s*NlMotionDiagnostics_t \*motionDiag\)') `
    'RampCommandToTarget signature must be unchanged by this experiment.'

# --- Insertion points: creep runs AFTER each settle succeeds (out->result
# already confirmed NL_SETTLE_OK on the code path above each call site),
# updates the settle's own finalSample in place, and precedes every
# downstream use of the corrected anchor. ---
Assert-True ($source -match '(?s)#if ENABLE_B0B_APPROACH_CREEP\s*/\* 3b\..*?CreepToUnwrappedTarget\(&sweepAcquisition, &commandPos,\s*[\r\n\s]*expectedBackoffUnwrapped, &backoffSettle\.finalSample,\s*[\r\n\s]*&out->backoffCreepDiag, NL_B0B_CREEP_STEP_RAW, NL_B0B_CREEP_DEADBAND_RAW,\s*[\r\n\s]*NL_B0B_CREEP_MAX_TOTAL_RAW, NL_B0B_CREEP_MAX_ITERATIONS, 1\.0f, false,\s*[\r\n\s]*0LL, 0U\);\s*#endif\s*int64_t backoffAnchorUnwrapped = backoffSettle\.finalSample\.unwrappedRaw;') `
    'Backoff creep must run against expectedBackoffUnwrapped, pass B0-B''s own unchanged constants + 1.0f power, and update backoffSettle.finalSample BEFORE backoffAnchorUnwrapped is read from it (insertion point or B0-B tuning changed incorrectly).'
Assert-True ($source -match '(?s)CreepToUnwrappedTarget\(&sweepAcquisition, &commandPos,\s*[\r\n\s]*expectedPoint0Unwrapped, &point0Settle\.finalSample,\s*[\r\n\s]*&out->forwardCreepDiag, NL_B0B_CREEP_STEP_RAW, NL_B0B_CREEP_DEADBAND_RAW,\s*[\r\n\s]*NL_B0B_CREEP_MAX_TOTAL_RAW, NL_B0B_CREEP_MAX_ITERATIONS, 1\.0f, false,\s*[\r\n\s]*0LL, 0U\);\s*#endif\s*sweepOriginUnwrapped = point0Settle\.finalSample\.unwrappedRaw;') `
    'Point-0 creep must run against expectedPoint0Unwrapped, pass B0-B''s own unchanged constants + 1.0f power, and update point0Settle.finalSample before sweepOriginUnwrapped/sample/settleObservation are assigned.'
Assert-True ($source -match '(?s)sweepOriginUnwrapped = point0Settle\.finalSample\.unwrappedRaw;.*?sample = point0Settle\.finalSample;\s*settleObservation = point0Settle;') `
    'sample/settleObservation must still be assigned from point0Settle AFTER the creep update, so the official per-sweep anchor (pointAnchorUnwrapped) reflects the corrected position.'

# --- APPROACH_RESULT: new fields present, right after B0BSoftStartProtocol. ---
Assert-True ($source -match '"B0BSoftStartProtocol=%s,"\s*[\r\n]+\s*"B0BCreepProtocol=%s,BackoffCreepResult=%s,BackoffCreepIterations=%lu,"\s*[\r\n]+\s*"BackoffCreepTotalRaw=%s,ForwardCreepResult=%s,ForwardCreepIterations=%lu,"\s*[\r\n]+\s*"ForwardCreepTotalRaw=%s,"') `
    'APPROACH_RESULT must carry the 7 new creep fields immediately after B0BSoftStartProtocol.'
Assert-True ($source -match '(?s)NL_B0B_CREEP_PROTOCOL_ID,\s*[\r\n\s]*NlCreepResultName\(c->backoffCreepDiag\.result\),\s*[\r\n\s]*\(unsigned long\)c->backoffCreepDiag\.iterations,\s*[\r\n\s]*backoffCreepTotalBuf,\s*[\r\n\s]*NlCreepResultName\(c->forwardCreepDiag\.result\),\s*[\r\n\s]*\(unsigned long\)c->forwardCreepDiag\.iterations,\s*[\r\n\s]*forwardCreepTotalBuf,') `
    'The APPROACH_RESULT argument list must supply the creep protocol ID and both legs diagnostics in that order.'
Assert-True ($source -match 'FormatI64\(c->backoffCreepDiag\.totalCorrectionRaw, backoffCreepTotalBuf,' -and
        $source -match 'FormatI64\(c->forwardCreepDiag\.totalCorrectionRaw, forwardCreepTotalBuf,') `
    'The int64 total-correction fields must go through FormatI64, never %ld.'

# --- No new META field (same buffer-headroom lesson as the soft-start
# experiment): stay entirely inside APPROACH_RESULT. ---
Assert-True ($source -notmatch 'B0BCreep\w*.*META,SchemaVersion' -and
        $source -notmatch 'META,SchemaVersion.*?B0BCreep') `
    'B0-B creep must not add a new META field (insufficient buffer headroom); use APPROACH_RESULT instead.'

# --- APPROACH_RESULT line budget: longest real line (already reflecting the
# soft-start field, since a hardware log with it exists on disk) plus the
# NEW creep fields' worst case must stay under the 1900-byte buffer. ---
Assert-True ($source -match 'char\s+buf\[1900\]') `
    'Could not confirm the LogLineLarge 1900-byte buffer (source layout changed?).'
$logFiles = Get-ChildItem -Path $root -Filter '*.txt' -File |
    Where-Object { $_.Length -lt 20MB }
$maxApproachResultLen = 0
foreach ($lf in $logFiles) {
    foreach ($line in [System.IO.File]::ReadLines($lf.FullName)) {
        if ($line.StartsWith('APPROACH_RESULT,') -and $line.Length -gt $maxApproachResultLen) {
            $maxApproachResultLen = $line.Length
        }
    }
}
Assert-True ($maxApproachResultLen -gt 0) `
    'No real APPROACH_RESULT line found to measure the line budget against.'
# Worst case per new field: ACQUISITION_ERROR (longest result name) and a
# full-width negative int64 ("-9223372036854775808" = 20 chars).
$newFieldsCost = (
    ',B0BCreepProtocol=ENCODER_CREEP_V1,BackoffCreepResult=ACQUISITION_ERROR,' +
    'BackoffCreepIterations=4294967295,BackoffCreepTotalRaw=-9223372036854775808,' +
    'ForwardCreepResult=ACQUISITION_ERROR,ForwardCreepIterations=4294967295,' +
    'ForwardCreepTotalRaw=-9223372036854775808'
).Length
Assert-True (($maxApproachResultLen + $newFieldsCost) -lt 1900) `
    ("APPROACH_RESULT line budget exceeded: longest observed " + $maxApproachResultLen +
     ' + new creep fields worst case ' + $newFieldsCost + ' must stay < 1900.')

# --- ENABLE_SWEEP_POINT_CREEP V5 adaptive targeted-budget.  BASE preserves
# V4; EXTENDED is selected only from the live post-settle gap, never from a
# fixed point/angle list. Power/step/deadband and the official gate stay
# unchanged. ---
Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_GAP_BUDGET_SINGLE_RECOVERY_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_TARGET_CROSSING_GUARD_ID\s+"STOP_BEFORE_NEXT_COMMAND_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_PROTOCOL_ID\s+"SINGLE_REVERSAL_SAME_STEP_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_STOP_ON_TARGET_CROSSING\s+true' -and
        $source -match '#define\s+NL_SWEEP_CREEP_STEP_RAW\s+16' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_TRIGGER_RAW\s+200LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_BASE_MAX_TOTAL_RAW\s+220LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_BASE_MAX_ITERATIONS\s+15U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW\s+320LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_EXTENDED_MAX_ITERATIONS\s+21U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_MAX_TOTAL_RAW\s+320LL' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_MAX_ITERATIONS\s+21U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_POWER\s+1\.0f') `
    'NL_SWEEP_CREEP_* V5 adaptive constants missing or changed unexpectedly.'

$adaptiveBlock = [regex]::Match($source,
    '(?s)int64_t initialGapRaw = expectedTargetUnwrapped.*?MA600_Result_t creepAcqResult = CreepToUnwrappedTarget\(.*?NL_SWEEP_CREEP_POWER,\s*NL_SWEEP_CREEP_STOP_ON_TARGET_CROSSING,\s*NL_SWEEP_CREEP_RECOVERY_MAX_TOTAL_RAW,\s*NL_SWEEP_CREEP_RECOVERY_MAX_ITERATIONS\);').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($adaptiveBlock)) `
    'Could not locate the V5 adaptive sweep-creep selection/call block.'
Assert-True ($adaptiveBlock -match 'expectedTargetUnwrapped\s*-\s*settleObservation\.finalSample\.unwrappedRaw' -and
        $adaptiveBlock -match 'AbsI64ToU64\(initialGapRaw\)\s*>\s*\(uint64_t\)NL_SWEEP_CREEP_EXTENDED_TRIGGER_RAW' -and
        $adaptiveBlock -match 'creepMaxTotalRaw, creepMaxIterations, NL_SWEEP_CREEP_POWER,\s*[\r\n\s]*NL_SWEEP_CREEP_STOP_ON_TARGET_CROSSING') `
    'V5 must select and pass the adaptive budget from the live post-settle initial gap.'
$budgetSelectionBlock = [regex]::Match($source,
    '(?s)int64_t initialGapRaw = expectedTargetUnwrapped.*?uint32_t creepMaxIterations =.*?NL_SWEEP_CREEP_BASE_MAX_ITERATIONS;').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($budgetSelectionBlock) -and
        $budgetSelectionBlock -notmatch 'pointIndex\s*(==|>=|<=|>|<)' -and
        $budgetSelectionBlock -notmatch 'DIFFICULT.*POINT|POINT.*WHITELIST') `
    'V5 budget selection must not contain a fixed point/angle whitelist.'

Assert-True ($source -match 'creepInitialGapRaw\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepFinalGapRaw\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepTotalCorrectionRaw\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepIterations\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepResults\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepBudgetClasses\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepPreCrossGapRaw\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepCrossingGapRaw\[NL_MAX_SWEEP_POINTS\]' -and
        $source -match 'creepRecoveryIterations\[NL_MAX_SWEEP_POINTS\]') `
    'V5 per-point creep telemetry must be retained in the CCM shadow storage.'
Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=5' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=5' -and
        $source -match 'Official=0,Enabled=1,Protocol=%s' -and
        $source -match 'TargetCrossingGuard=%s' -and
        $source -match 'RecoveryProtocol=%s' -and
        $source -match 'RecoveryAttempted=%d,RecoverySucceeded=%d' -and
        $source -match 'InitialGapRaw=%s,InitialAbsGapRaw=%s,BudgetClass=%s') `
    'V5 diagnostic-only config/per-point records are missing.'
Assert-True ($source -match '(?s)for \(int i = 0; i < NL_MAX_SWEEP_POINTS; i\+\+\).*?creepResults\[i\].*?SWEEP_CREEP_POINT' -and
        $source -match 'diag->finalGapRaw = targetUnwrapped\s*-\s*microSettle\.finalSample\.unwrappedRaw;') `
    'V5 must retain/report a next-target acquisition failure with its actual final encoder gap.'
Assert-True ($source -match 'SweepPointCreepBaseBudgetExceeded=%lu' -and
        $source -match 'SweepPointCreepExtendedPoints=%lu' -and
        $source -match 'SweepPointCreepExtendedOk=%lu' -and
        $source -match 'SweepPointCreepExtendedTotalIterations=%lu' -and
        $source -match 'SweepPointCreepExtendedTotalCorrectionRaw=%s' -and
        $source -match 'SweepPointCreepExtendedTimeouts=%lu' -and
        $source -match 'SweepPointCreepExtendedBudgetExceeded=%lu' -and
        $source -match 'SweepPointCreepTargetCrossed=%lu' -and
        $source -match 'SweepPointCreepBaseTargetCrossed=%lu' -and
        $source -match 'SweepPointCreepExtendedTargetCrossed=%lu' -and
        $source -match 'SweepPointCreepRecoveryAttempted=%lu' -and
        $source -match 'SweepPointCreepRecoverySucceeded=%lu' -and
        $source -match 'SweepPointCreepRecoveryFailed=%lu' -and
        $source -match 'SweepPointCreepRecoveryRecrossed=%lu' -and
        $source -match 'SweepPointCreepIntegrityValid=%d') `
    'END must include the V5.2 BASE/EXTENDED crossing and recovery-integrity fields.'

# V5.2 target-crossing recovery: evaluate only after a fresh micro-settle,
# reverse once, and stop before another command if the recovery re-crosses.
$crossingGuard = [regex]::Match($creepFn,
    '(?s)anchor = microSettle\.finalSample\.unwrappedRaw;\s*gap = targetUnwrapped - anchor;.*?diag->result = NL_CREEP_RECOVERY_RECROSSED;\s*break;.*?diag->finalGapRaw = gap;').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($crossingGuard) -and
        $crossingGuard -match 'AbsI64ToU64\(gap\) > \(uint64_t\)deadbandRaw' -and
        $crossingGuard -match 'direction > 0 && gap < 0' -and
        $crossingGuard -match 'direction < 0 && gap > 0' -and
        $crossingGuard -match 'recoveryPhase = true;' -and
        $crossingGuard -match 'direction = -direction;') `
    'V5.2 must start one bounded recovery only after a live target sign crossing.'

Assert-True ($source -match 'eligibleForStatistics = !preconditionRun\s*&& preconditionValid\s*&& \(nlCaptures\[i\]\.sweepPointCreepRecoveryFailedCount == 0U\)\s*&& \(nlCaptures\[i\]\.sweepPointCreepStickSlipJumpCount == 0U\)' -and
        $source -match 'CreepIntegrityValid=%d,Status=%s' -and
        $source -match 'Motor RESULT INVALID: %s \(SweepPointCreepRecoveryFailed=%lu,StickSlipJump=%lu\)' -and
        $source -match 'nlPreconditionValid =\s*\(nlCaptures\[0\]\.sweepPointCreepRecoveryFailedCount == 0U\)\s*&& \(nlCaptures\[0\]\.sweepPointCreepStickSlipJumpCount == 0U\)') `
    'V5.2/V5.3 must accept recovered crossings but suppress recovery/jump integrity failures.'

# Both V5 records must live in PrintSweepLog, not CaptureSweep: UART in
# the capture loop would perturb the very motion timing being measured.
$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$captureSweep = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($captureSweep) -and
        $captureSweep -notmatch 'SWEEP_CREEP_CONFIG' -and
        $captureSweep -notmatch 'SWEEP_CREEP_POINT' -and
        $captureSweep -notmatch '"SWEEP_CREEP_STEP,SchemaVersion') `
    'V5 must not emit SWEEP_CREEP_* UART records inside CaptureSweep.'

# --- No leakage into the official contract. ---
Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
    'The creep experiment must not touch the official measurement-valid gate.'
Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
        $source -match 'OfficialResultSource=LEGACY') `
    'The creep experiment must not change the official schema-v5/legacy result contract.'
Assert-True ($source -notmatch 'MotorPwm_SetElectricalPos\([^;]*power\s*[<>!=]') `
    'This change must not touch B0-B power (must remain full power, unchanged).'

Write-Host '[ OK ] B0-B approach endpoint-creep experiment contract tests passed.'
