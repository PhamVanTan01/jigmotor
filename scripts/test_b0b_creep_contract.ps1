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

# --- CreepToUnwrappedTarget: only compiled/called under the flag; never
# reverses direction; only touches the motor via Motor_SetElectricalPos
# (same power=1.0 convention as the rest of B0-B); reuses WaitForPointSettle
# rather than re-implementing settle logic. ---
$creepFn = [regex]::Match($source,
    '(?s)#if ENABLE_B0B_APPROACH_CREEP\s*/\* Runs only AFTER.*?static MA600_Result_t CreepToUnwrappedTarget\(.*?\n\}\s*#endif').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($creepFn)) `
    'Could not locate a flag-gated CreepToUnwrappedTarget definition.'
Assert-True ($creepFn -match 'int direction = \(gap > 0\) \? 1 : -1;' -and
        $creepFn -notmatch 'direction\s*=\s*-direction' -and
        $creepFn -notmatch 'direction\s*\*=\s*-1') `
    'CreepToUnwrappedTarget must fix direction once at entry and never reverse it.'
Assert-True ($creepFn -match 'Motor_SetElectricalPos\(\(uint16_t\)\*commandPos,\s*1\.0f\)') `
    'CreepToUnwrappedTarget must command through Motor_SetElectricalPos at full power, matching B0-B.'
Assert-True ($creepFn -match 'WaitForPointSettle\(sweepAcquisition,\s*[\r\n\s]*anchor \+ step,\s*false,\s*&microSettle\)') `
    'CreepToUnwrappedTarget must reuse WaitForPointSettle (targetRequired=false) for each micro-step, not new settle logic.'
Assert-True ($creepFn -match 'diag->iterations >= NL_B0B_CREEP_MAX_ITERATIONS' -and
        $creepFn -match 'diag->totalCorrectionRaw >= NL_B0B_CREEP_MAX_TOTAL_RAW' -and
        $creepFn -match 'AbsI64ToU64\(gap\) <= \(uint64_t\)NL_B0B_CREEP_DEADBAND_RAW') `
    'CreepToUnwrappedTarget must check deadband, iteration cap and budget cap every loop pass.'
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
Assert-True ($source -match '(?s)#if ENABLE_B0B_APPROACH_CREEP\s*/\* 3b\..*?CreepToUnwrappedTarget\(&sweepAcquisition, &commandPos,\s*[\r\n\s]*expectedBackoffUnwrapped, &backoffSettle\.finalSample,\s*[\r\n\s]*&out->backoffCreepDiag\);\s*#endif\s*int64_t backoffAnchorUnwrapped = backoffSettle\.finalSample\.unwrappedRaw;') `
    'Backoff creep must run against expectedBackoffUnwrapped and update backoffSettle.finalSample BEFORE backoffAnchorUnwrapped is read from it (insertion point moved incorrectly).'
Assert-True ($source -match '(?s)CreepToUnwrappedTarget\(&sweepAcquisition, &commandPos,\s*[\r\n\s]*expectedPoint0Unwrapped, &point0Settle\.finalSample,\s*[\r\n\s]*&out->forwardCreepDiag\);\s*#endif\s*sweepOriginUnwrapped = point0Settle\.finalSample\.unwrappedRaw;') `
    'Point-0 creep must run against expectedPoint0Unwrapped and update point0Settle.finalSample before sweepOriginUnwrapped/sample/settleObservation are assigned.'
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

# --- No leakage into the official contract. ---
Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
    'The creep experiment must not touch the official measurement-valid gate.'
Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
        $source -match 'OfficialResultSource=LEGACY') `
    'The creep experiment must not change the official schema-v5/legacy result contract.'
Assert-True ($source -notmatch 'MotorPwm_SetElectricalPos\([^;]*power\s*[<>!=]') `
    'This change must not touch B0-B power (must remain full power, unchanged).'

Write-Host '[ OK ] B0-B approach endpoint-creep experiment contract tests passed.'
