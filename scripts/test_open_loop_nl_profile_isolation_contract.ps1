$ErrorActionPreference = 'Stop'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $root 'Core/Src/nonlinear_test.c'
$source = Get-Content -LiteralPath $sourcePath -Raw

Assert-True ($source -match '#define\s+NL_PROFILE_GREMSY_OPEN_LOOP\s+1' -and
        $source -match '#define\s+NL_PROFILE_POSITION_DIAGNOSTIC\s+2' -and
        $source -match '(?s)#ifndef NL_MEASUREMENT_PROFILE\s*#define NL_MEASUREMENT_PROFILE NL_PROFILE_GREMSY_OPEN_LOOP\s*#endif') `
    'Measurement-profile identity macros are missing or the default is not the open-loop profile (AGENTS.md RULE 0: primary and authoritative objective).'

Assert-True ($source -match '(?s)#if \(NL_MEASUREMENT_PROFILE != NL_PROFILE_GREMSY_OPEN_LOOP\)\s*\\\s*&& \(NL_MEASUREMENT_PROFILE != NL_PROFILE_POSITION_DIAGNOSTIC\)\s*#error') `
    'NL_MEASUREMENT_PROFILE must reject any value other than the two locked profile identities.'

$guard = [regex]::Match($source,
    '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#if ENABLE_SWEEP_POINT_CREEP.*?#error "Feedback actuation \(or encoder-derived feedforward\) is forbidden in NL_PROFILE_GREMSY_OPEN_LOOP.*?#endif\s*#endif').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($guard) -and
        $guard -match 'ENABLE_SWEEP_POINT_CREEP\b' -and
        $guard -match 'ENABLE_B0B_APPROACH_CREEP' -and
        $guard -match 'ENABLE_B0B_APPROACH_FEEDFORWARD' -and
        $guard -match 'ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION') `
    'The open-loop profile must #error when any feedback-actuation or encoder-derived-feedforward flag (sweep-point creep, B0-B approach creep, B0-B feedforward -- CREEP_DERIVED_BIAS_V2 -- or V5.9 terminal correction explicitly, in case the V5.9-under-SWEEP_POINT_CREEP nesting is ever refactored) is enabled.'

Assert-True ($source -match '(?s)#ifndef ENABLE_B0B_APPROACH_FEEDFORWARD\s*#define ENABLE_B0B_APPROACH_FEEDFORWARD   0\s*#endif.*?#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP') `
    'The profile-isolation guard must be placed AFTER ENABLE_B0B_APPROACH_FEEDFORWARD is defined, not before -- an undefined macro in #if is silently treated as 0, so placing the guard earlier would not error today but would stop protecting if the flag definitions are ever reordered.'

Assert-True ($source -notmatch '(?s)#if ENABLE_SWEEP_POINT_CREEP_V57_HARDCAP_HOLD_DIAG\s*\\\s*\|\|\s*ENABLE_SWEEP_POINT_RESPONSE_TIMING_DIAG\s*/\*.*?&& false') `
    'eligibleForStatistics must not go back to a flag-by-flag exclusion list (V5.7/V5.8-only) -- that exact pattern is how the V5.9 eligibility leak happened (handoff 2026-08-12 section 18.2). It must be profile-gated instead.'

Assert-True ($source -match '(?s)nlCaptures\[i\]\.eligibleForStatistics =\s*\(NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\)\s*&& !preconditionRun\s*&& preconditionValid\s*&& nlCaptures\[i\]\.measurementValid;') `
    'eligibleForStatistics must be gated on NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP first, and must also require measurementValid (a structurally-invalid run must never be statistics-eligible).'

Assert-True ($source -match 'MeasurementPolicy=%s,MeasurementProfile=%s,MeasurementDefinition=%s,' -and
        $source -match 'MeasurementContractVersion=%s,OfficialOpenLoopNL=1,FeedbackActuationEnabled=%d,' -and
        $source -match 'ApproachProtocol=%s,MotionProfile=%s,GridProtocol=%s,' -and
        $source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP.*?OfficialResultSource=CANONICAL_Q16.*?#else.*?OfficialResultSource=LEGACY') `
    'Profile-specific META must emit the measurement contract, open-loop/feedback identity, and canonical-vs-legacy result source without a hand-maintained runtime alias.'

Assert-True ($source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#define NL_MEASUREMENT_PROFILE_ID\s+"GREMSY_COMPAT_OPEN_LOOP_NL_V1"\s*#define NL_MEASUREMENT_DEFINITION\s+"WHOLE_SYSTEM_OPEN_LOOP_TRACKING_V1"\s*#else\s*#define NL_MEASUREMENT_PROFILE_ID\s+"POSITION_RESPONSE_DIAGNOSTIC_V5X"\s*#define NL_MEASUREMENT_DEFINITION\s+"ENCODER_CORRECTED_POSITION_RESPONSE"\s*#endif') `
    'NL_MEASUREMENT_PROFILE_ID/NL_MEASUREMENT_DEFINITION must be profile-conditional with the exact locked names from docs/nonlinear-log-schema-v6.md.'

Assert-True ($source -notmatch '#define\s+NL_MEASUREMENT_DEFINITION\s+"WHOLE_SYSTEM_COMMAND_TRACKING"') `
    'The retired unqualified WHOLE_SYSTEM_COMMAND_TRACKING definition must not come back -- it was ambiguous about encoder-based command correction.'

Assert-True ($source -match 'RampEncoderObservationEnabled=1,RampFeedbackActuationEnabled=0,' -and
        $source -notmatch 'RampFeedbackEnabled=1') `
    'The misleading RampFeedbackEnabled=1 field must stay retired in favor of RampEncoderObservationEnabled/RampFeedbackActuationEnabled (handoff 2026-08-12 section 4).'

$s2Marker = $source.IndexOf('/* S2/S3 cutover: this is the one and only official 64-sample window.')
$captureStart = if ($s2Marker -ge 0) {
    $source.LastIndexOf('#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP',
        $s2Marker)
} else { -1 }
$captureElse = $source.IndexOf('#else', $captureStart)
$officialCapture = if ($captureStart -ge 0 -and $captureElse -gt $captureStart) {
    $source.Substring($captureStart, $captureElse - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($officialCapture) -and
        $officialCapture -match 'CaptureCanonicalPointFromSweepContext\(' -and
        $officialCapture -match 'RecordShadowPoint\(' -and
        $officialCapture -match 'out->shadowPoint0MeanRawQ16 = canonicalPoint\.pointMeanRawQ16;' -and
        $officialCapture -match 'NlComputeProfileErrorRawQ16\(' -and
        $officialCapture -match 'MA600_DivRoundNearestAwayFromZero\(canonicalPoint\.pointMeanRawQ16,' -and
        $officialCapture -notmatch 'float angleSampleSum' -and
        $officialCapture -notmatch 'MA600_ReadAveragedPoint\(') `
    'S2/ALG-001: the official profile must use one canonical Q16 window for Error/DATA/extrema and must not run the legacy or independent-shadow capture.'

Assert-True ($source -notmatch '(?s)uint16_t rawAtPoint = sample\.raw;\s*float absoluteAngleDeg = MA600_RawToDegrees\(rawAtPoint\);\s*#if ENABLE_SWEEP_POINT_RESPONSE_TIMING_DIAG\s*uint32_t legacyCaptureEndCycle') `
    'ALG-001: the old dual-read pattern (fresh MA600_AcquireSample after the 64-sample loop, used only for rawAtPoint) must not come back.'

Assert-True ($source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#define NL_SETTLE_CONTRACT_ID\s+"STABILITY_ONLY_CAPTURE_V1"\s*#define NL_POINT_SETTLE_TARGET_REQUIRED 0' -and
        $source -match 'WaitForPointSettle\(&sweepAcquisition,\s*expectedTargetUnwrapped,\s*NL_POINT_SETTLE_TARGET_REQUIRED != 0,') `
    'S3: official point capture must be readiness-gated by stability only; target proximity stays observation/validity telemetry and cannot drive correction.'

Assert-True ($source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*if \(c->officialMeasurementValid\).*?"RESULT,SchemaVersion=.*?OpenLoopNL_Deg=%s,RobustP2P_Deg=%s.*?else.*?"DIAGNOSTIC_RESULT,SchemaVersion=.*?Diagnostic_OpenLoopNL_Deg=%s' -and
        $source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*errorSum \+= nlCaptures\[captureCount\]\.legacyStats\.rawPP;\s*#else\s*errorSum \+= nlCaptures\[captureCount\]\.legacyStats\.robustPP;') `
    'S3: valid schema-v6 output and final average must use RawP2P/OpenLoopNL; invalid output must use Diagnostic_* names, while robust P2P remains supporting.'

Assert-True ($source -match 'CommandRawQ16=%s,MeanUnwrappedRawQ16=%s,ErrorRawQ16=%s' -and
        $source -match 'ErrorSignConvention=%s' -and
        $source -match '#define NL_MEASUREMENT_CONTRACT_ID\s+"GREMSY_OPEN_LOOP_NL_1DEG360_V1"') `
    'S0/S2: schema-v6 DATA must expose command/mean/error Q16 from the versioned 360-point open-loop contract.'

$profileStart = $source.IndexOf('static MA600_Result_t RampCommandToTarget(')
$profileEnd = $source.IndexOf('static uint64_t AbsI64ToU64(', $profileStart)
$ramp = if ($profileStart -ge 0 -and $profileEnd -gt $profileStart) {
    $source.Substring($profileStart, $profileEnd - $profileStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($ramp) -and
        $ramp -match 'MA600_AcquireSample\(' -and
        $ramp -notmatch '\*pos\s*=\s*rampSample' -and
        $ramp -notmatch '\*pos\s*\+?=\s*.*rampSample') `
    'RampCommandToTarget must keep reading MA600 for observability but must never let the sample feed back into *pos (open-loop actuation invariant).'

Assert-True ($source -match '(?s)static void LogLineLarge.*?char buf\[2600\].*?LARGE_LINE_TRUNCATED.*?nlUartTransmitFailureCount\+\+;.*?return;') `
    'Schema-v6 META exceeds the old 1900-byte buffer: LogLineLarge must use the validated 2600-byte buffer and fail closed rather than transmit a truncated role/eligibility contract.'

Write-Host '[ OK ] Open-loop NL profile-isolation contract tests passed.'
