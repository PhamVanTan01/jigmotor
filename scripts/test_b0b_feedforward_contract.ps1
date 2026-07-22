$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

# --- Default-off. ---
Assert-True ($source -match '#ifndef\s+ENABLE_B0B_APPROACH_FEEDFORWARD\s*[\r\n]+#define\s+ENABLE_B0B_APPROACH_FEEDFORWARD\s+0') `
    'ENABLE_B0B_APPROACH_FEEDFORWARD must default to 0.'
Assert-True ($source -match '#define\s+NL_B0B_FEEDFORWARD_BACKOFF_BIAS_RAW\s+100' -and
        $source -match '#define\s+NL_B0B_FEEDFORWARD_FORWARD_BIAS_RAW\s+136') `
    'Feedforward bias constants must match the creep-derived first estimates (100/136 raw).'
Assert-True ($source -match '#define\s+NL_B0B_FEEDFORWARD_PROTOCOL_ID\s+"CREEP_DERIVED_BIAS_V1"' -and
        $source -match '#define\s+NL_B0B_FEEDFORWARD_PROTOCOL_ID\s+"NONE"') `
    'Both protocol IDs (CREEP_DERIVED_BIAS_V1 when flagged / NONE default) must exist.'
Assert-True ($source -notmatch 'friction.feed.forward' -and $source -notmatch 'FRICTION_FEEDFORWARD') `
    'The bias must not be framed/named as a friction coefficient -- it is a lumped, creep-derived, hardware-specific empirical correction.'

# --- Deadband shared with creep, NOT gated behind ENABLE_B0B_APPROACH_CREEP
# -- a build with feedforward=1/creep=0 must still compile. ---
Assert-True ($source -match '(?m)^#define\s+NL_B0B_TARGET_DEADBAND_RAW\s+16LL') `
    'NL_B0B_TARGET_DEADBAND_RAW must be defined unconditionally (not inside #if ENABLE_B0B_APPROACH_CREEP).'
Assert-True ($source -match '(?s)#define\s+NL_B0B_TARGET_DEADBAND_RAW\s+16LL.*?#if\s+ENABLE_B0B_APPROACH_CREEP.*?#define\s+NL_B0B_CREEP_DEADBAND_RAW\s+NL_B0B_TARGET_DEADBAND_RAW') `
    'NL_B0B_CREEP_DEADBAND_RAW must alias the shared NL_B0B_TARGET_DEADBAND_RAW, not redefine its own literal.'

# --- Compile-time guards: non-negative bias, and a cap on the TOTAL
# commandPos excursion per leg (not just each bias in isolation). ---
Assert-True ($source -match '(?s)#if\s*\(NL_B0B_FEEDFORWARD_BACKOFF_BIAS_ACTIVE\s*<\s*0\)[\s\\]*\|\|\s*\(NL_B0B_FEEDFORWARD_FORWARD_BIAS_ACTIVE\s*<\s*0\)[\s\\]*#error') `
    'A compile-time guard must reject negative feedforward bias values.'
Assert-True ($source -match '#define\s+NL_B0B_MAX_COMMAND_EXCURSION_RAW\s+500') `
    'NL_B0B_MAX_COMMAND_EXCURSION_RAW must be a named constant (not a bare literal).'
Assert-True ($source -match '(?s)\(NL_B0B_APPROACH_BACKOFF_RAW \+ NL_B0B_FEEDFORWARD_BACKOFF_BIAS_ACTIVE\)[\s\S]{0,40}>\s*NL_B0B_MAX_COMMAND_EXCURSION_RAW[\s\S]{0,80}\|\|[\s\S]{0,120}NL_B0B_APPROACH_BACKOFF_RAW \+ NL_B0B_FEEDFORWARD_BACKOFF_BIAS_ACTIVE[\s\S]{0,40}\+ NL_B0B_FEEDFORWARD_FORWARD_BIAS_ACTIVE\)\s*>\s*NL_B0B_MAX_COMMAND_EXCURSION_RAW[\s\S]{0,20}#error') `
    'The excursion guard must check the FORWARD leg''s cumulative span (182+backoffBias+forwardBias), not just the forward bias in isolation.'

# --- ExtendCommandBlind: signature mirrors RampCommandToTarget (stepsExecuted
# out-param, shared NlMotionDiagnostics_t), never reads/settles the encoder
# (it is blind, not creep), and is flag-gated (both branches still compile). ---
$extendFn = [regex]::Match($source,
    '(?s)#if ENABLE_B0B_APPROACH_FEEDFORWARD\s*/\* Open-loop, unmeasured.*?static void ExtendCommandBlind\(.*?\n\}\s*#endif /\* ENABLE_B0B_APPROACH_FEEDFORWARD \*/').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($extendFn)) `
    'Could not locate a flag-gated ExtendCommandBlind definition.'
Assert-True ($extendFn -match 'static void ExtendCommandBlind\(int32_t \*commandPos, int32_t totalExtensionRaw,\s*[\r\n\s]*uint32_t stepDelayMs, uint32_t \*stepsExecuted, NlMotionDiagnostics_t \*motionDiag\)') `
    'ExtendCommandBlind must take (commandPos, totalExtensionRaw, stepDelayMs, stepsExecuted, motionDiag) -- no acquisition-context parameter (it never reads the encoder).'
Assert-True ($extendFn -notmatch 'MA600_AcquireSample\(' -and
        $extendFn -notmatch 'WaitForPointSettle\(' -and
        $extendFn -notmatch 'CreepToUnwrappedTarget\(') `
    'ExtendCommandBlind must never read the encoder or settle -- it is a blind, predictive command sequence, not feedback (that is what distinguishes it from creep).'
Assert-True ($extendFn -match 'Motor_SetElectricalPos\(\(uint16_t\)\*commandPos,\s*1\.0f\)') `
    'ExtendCommandBlind must command through Motor_SetElectricalPos at full power, matching the rest of B0-B.'
Assert-True ($extendFn -match '\*stepsExecuted = steps;') `
    'ExtendCommandBlind must report the actual runtime step count, not rely on a compile-time-derived value.'
Assert-True ($extendFn -match 'motionDiag->timingOverrunCount\+\+' -and
        $extendFn -match 'motionDiag->maxLatenessTicks') `
    'ExtendCommandBlind must track timing overruns through the shared NlMotionDiagnostics_t, not silently drop them.'

# --- RampCommandToTarget and the 40-tick quintic must be completely
# untouched -- the whole point is isolating the change to a new, separate,
# B0-B-only stage rather than the function shared by the official sweep. ---
Assert-True ($source -match '(?s)static MA600_Result_t RampCommandToTarget\(\s*MA600_AcquisitionContext_t \*sweepAcquisition,\s*int32_t \*pos,\s*int32_t targetPos,\s*uint32_t \*stepsExecuted,\s*int64_t \*stepUnwrappedRawLog,\s*uint8_t stepLogCapacity,\s*uint32_t stepDelayMs,\s*NlMotionDiagnostics_t \*motionDiag\)') `
    'RampCommandToTarget signature must be unchanged by this experiment.'

# --- Insertion points: ExtendCommandBlind runs AFTER each RampCommandToTarget
# succeeds and BEFORE the corresponding settle call -- the ramp's own target
# (backoffCommand / literal 0) must stay untouched by the bias. ---
Assert-True ($source -match '(?s)int32_t backoffCommand = 0 - NL_B0B_APPROACH_BACKOFF_RAW;(?!\s*-\s*NL_B0B_FEEDFORWARD)') `
    'backoffCommand (the RampCommandToTarget target) must stay exactly "0 - NL_B0B_APPROACH_BACKOFF_RAW" -- the bias must NOT be baked into the 40-tick ramp target itself.'
Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos, backoffCommand,[\s\S]{0,1300}?ExtendCommandBlind\(&commandPos, -NL_B0B_FEEDFORWARD_BACKOFF_BIAS_ACTIVE,[\s\S]{0,700}?expectedBackoffUnwrapped = initialAnchorUnwrapped - NL_B0B_APPROACH_BACKOFF_RAW;') `
    'ExtendCommandBlind (backoff) must run after RampCommandToTarget and before the backoff settle target is computed/used, and expectedBackoffUnwrapped must stay unbiased.'
Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition, &commandPos, 0,[\s\S]{0,1300}?ExtendCommandBlind\(&commandPos, NL_B0B_FEEDFORWARD_FORWARD_BIAS_ACTIVE,[\s\S]{0,950}?expectedPoint0Unwrapped = backoffAnchorUnwrapped \+ NL_B0B_APPROACH_BACKOFF_RAW;') `
    'ExtendCommandBlind (forward) must run after the forward RampCommandToTarget (target still literal 0) and before expectedPoint0Unwrapped is computed, which must stay unbiased.'

# --- Pre-creep snapshot: the tracking-valid gate must be captured BEFORE
# the corresponding #if ENABLE_B0B_APPROACH_CREEP block, so creep (if also
# enabled) cannot take credit for feed-forward's own result. ---
Assert-True ($source -match '(?s)out->backoffFeedforwardTargetErrorRaw =\s*[\r\n\s]*backoffSettle\.finalSample\.unwrappedRaw - expectedBackoffUnwrapped;[\s\S]{0,300}?#endif\s*#if ENABLE_B0B_APPROACH_CREEP') `
    'The backoff feedforward-tracking snapshot must be computed BEFORE the #if ENABLE_B0B_APPROACH_CREEP block that follows it.'
Assert-True ($source -match '(?s)out->forwardFeedforwardTargetErrorRaw =\s*[\r\n\s]*point0Settle\.finalSample\.unwrappedRaw - expectedPoint0Unwrapped;[\s\S]{0,300}?#endif\s*#if ENABLE_B0B_APPROACH_CREEP') `
    'The forward feedforward-tracking snapshot must be computed BEFORE the #if ENABLE_B0B_APPROACH_CREEP block that follows it.'
Assert-True ($source -match 'backoffFeedforwardTrackingValid =\s*[\r\n\s]*AbsI64ToU64\(out->backoffFeedforwardTargetErrorRaw\) <= \(uint64_t\)NL_B0B_TARGET_DEADBAND_RAW;' -and
        $source -match 'forwardFeedforwardTrackingValid =\s*[\r\n\s]*AbsI64ToU64\(out->forwardFeedforwardTargetErrorRaw\) <= \(uint64_t\)NL_B0B_TARGET_DEADBAND_RAW;') `
    'Both tracking-valid flags must use NL_B0B_TARGET_DEADBAND_RAW, not the loose settle target tolerance.'

# --- Struct fields declared unconditionally (both branches compile). ---
Assert-True ($source -match 'uint32_t backoffExtensionSteps;\s*[\r\n]+\s*uint32_t forwardExtensionSteps;' -and
        $source -match 'int64_t\s+backoffFeedforwardTargetErrorRaw;\s*[\r\n]+\s*int64_t\s+forwardFeedforwardTargetErrorRaw;' -and
        $source -match 'bool\s+backoffFeedforwardTrackingValid;\s*[\r\n]+\s*bool\s+forwardFeedforwardTrackingValid;') `
    'NlSweepCapture_t is missing the feedforward diagnostic fields.'

# --- APPROACH_RESULT: new fields present, right after the existing creep fields. ---
Assert-True ($source -match '"ForwardCreepTotalRaw=%s,"\s*[\r\n]+\s*"B0BFeedforwardProtocol=%s,FeedforwardBackoffBiasRaw=%d,"\s*[\r\n]+\s*"FeedforwardForwardBiasRaw=%d,BackoffExtensionStepsExecuted=%lu,"\s*[\r\n]+\s*"ForwardExtensionStepsExecuted=%lu,BackoffFeedforwardTargetErrorRaw=%s,"\s*[\r\n]+\s*"ForwardFeedforwardTargetErrorRaw=%s,BackoffFeedforwardTrackingValid=%d,"\s*[\r\n]+\s*"ForwardFeedforwardTrackingValid=%d,"') `
    'APPROACH_RESULT must carry the new feedforward fields immediately after the existing creep fields.'
Assert-True ($source -match '(?s)NL_B0B_FEEDFORWARD_PROTOCOL_ID,\s*[\r\n\s]*\(int\)NL_B0B_FEEDFORWARD_BACKOFF_BIAS_ACTIVE,\s*[\r\n\s]*\(int\)NL_B0B_FEEDFORWARD_FORWARD_BIAS_ACTIVE,\s*[\r\n\s]*\(unsigned long\)c->backoffExtensionSteps,\s*[\r\n\s]*\(unsigned long\)c->forwardExtensionSteps,\s*[\r\n\s]*backoffFeedforwardErrBuf,\s*[\r\n\s]*forwardFeedforwardErrBuf,\s*[\r\n\s]*c->backoffFeedforwardTrackingValid \? 1 : 0,\s*[\r\n\s]*c->forwardFeedforwardTrackingValid \? 1 : 0,') `
    'The APPROACH_RESULT argument list must supply the feedforward fields in the declared order.'
Assert-True ($source -match 'FormatI64\(c->backoffFeedforwardTargetErrorRaw, backoffFeedforwardErrBuf,' -and
        $source -match 'FormatI64\(c->forwardFeedforwardTargetErrorRaw, forwardFeedforwardErrBuf,') `
    'The int64 feedforward target-error fields must go through FormatI64, never %ld.'

# --- No new META field -- stay entirely inside APPROACH_RESULT. ---
Assert-True ($source -notmatch 'B0BFeedforward\w*.*META,SchemaVersion' -and
        $source -notmatch 'META,SchemaVersion.*?B0BFeedforward') `
    'B0-B feedforward must not add a new META field (insufficient buffer headroom); use APPROACH_RESULT instead.'

# --- APPROACH_RESULT line budget: longest real line (already reflecting
# soft-start + creep fields) plus the NEW feedforward fields' worst case
# must stay under the 1900-byte buffer. ---
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
# Worst case per new field: CREEP_DERIVED_BIAS_V1 (longest protocol string),
# a full-width negative int (-2147483648) for the bias fields, a full-width
# uint32 for the step counters, and a full-width negative int64 for the
# target-error fields.
$newFieldsCost = (
    ',B0BFeedforwardProtocol=CREEP_DERIVED_BIAS_V1,FeedforwardBackoffBiasRaw=-2147483648,' +
    'FeedforwardForwardBiasRaw=-2147483648,BackoffExtensionStepsExecuted=4294967295,' +
    'ForwardExtensionStepsExecuted=4294967295,BackoffFeedforwardTargetErrorRaw=-9223372036854775808,' +
    'ForwardFeedforwardTargetErrorRaw=-9223372036854775808,BackoffFeedforwardTrackingValid=0,' +
    'ForwardFeedforwardTrackingValid=0'
).Length
Assert-True (($maxApproachResultLen + $newFieldsCost) -lt 1900) `
    ("APPROACH_RESULT line budget exceeded: longest observed " + $maxApproachResultLen +
     ' + new feedforward fields worst case ' + $newFieldsCost + ' must stay < 1900.')

# --- No leakage into the official contract. ---
Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
    'The feedforward experiment must not touch the official measurement-valid gate.'
Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
        $source -match 'OfficialResultSource=LEGACY') `
    'The feedforward experiment must not change the official schema-v5/legacy result contract.'
Assert-True ($source -notmatch 'MotorPwm_SetElectricalPos\([^;]*power\s*[<>!=]') `
    'This change must not touch B0-B power (must remain full power, unchanged).'

Write-Host '[ OK ] B0-B creep-derived endpoint bias (feedforward) experiment contract tests passed.'
