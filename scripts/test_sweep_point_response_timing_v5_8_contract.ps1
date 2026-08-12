param(
    [string]$SourcePath = "Core/Src/nonlinear_test.c"
)

$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath $SourcePath -Raw
$pythonTool = Get-Content -LiteralPath 'tools/auto_log_analysis.py' -Raw
$matlabParser = Get-Content -LiteralPath 'analysis/matlab/nl/parse_sweep_creep_log.m' -Raw
$matlabAnalyzer = Get-Content -LiteralPath 'analysis/matlab/nl/analyze_sweep_creep_batch.m' -Raw

$checks = [ordered]@{
    'V5.8 default-off flag exists' =
        $source -match '#define ENABLE_SWEEP_POINT_RESPONSE_TIMING_DIAG 0'
    'V5.8 requires frozen V5.5' =
        $source -match 'V5\.8 response timing requires frozen V5\.5 motion'
    'V5.8 excludes V5.6 and V5.7' =
        ($source -match 'V5\.8 diagnoses V5\.5; V5\.6 three-stage motion must remain disabled') -and
        ($source -match 'V5\.8 timing and V5\.7 passive hold are separate diagnostic identities')
    'Timing storage includes exact phase and wall boundaries' =
        ($source -match 'timingRampCycles\[NL_MAX_SWEEP_POINTS\]') -and
        ($source -match 'timingInitialSettleCycles\[NL_MAX_SWEEP_POINTS\]') -and
        ($source -match 'timingCreepCycles\[NL_MAX_SWEEP_POINTS\]') -and
        ($source -match 'timingCommandToStopCycles\[NL_MAX_SWEEP_POINTS\]') -and
        ($source -match 'timingCommandToDataFrozenCycles\[NL_MAX_SWEEP_POINTS\]')
    'Motor-on path only reads DWT and defers UART' =
        ($source -match 'pendingPointCommandStartCycle = DWT->CYCCNT') -and
        ($source -match 'legacyCaptureStartCycle = DWT->CYCCNT') -and
        ($source -match 'shadowCaptureStartCycle = DWT->CYCCNT')
    'Per-point timing schema reports command response' =
        ($source -match 'SWEEP_POINT_TIMING,SchemaVersion=1') -and
        ($source -match 'NominalStepCommandRaw=%s') -and
        ($source -match 'CreepCorrectionCommandRaw=%u') -and
        ($source -match 'TimeToDeadbandCycles=%s') -and
        ($source -match 'CreepResult=%s')
    'Failed target uses explicit NA formatting' =
        ($source -match 'hasCommand && reachedDeadband, deadbandBuf')
    'Completeness record exists' =
        ($source -match 'SWEEP_POINT_TIMING_END,SchemaVersion=1') -and
        ($source -match 'ExpectedPoints=%d') -and
        ($source -match 'EmittedPoints=%lu')
    'V5.8 runs are statistically ineligible' =
        # 2026-08-12: eligibility is now profile-gated (open-loop-nl-direction-
        # correction-handoff-2026-08-12.md section 18.2) instead of an explicit
        # per-flag "&& false" exclusion. V5.8 nests under
        # ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION (checked above in
        # "V5.8 requires frozen V5.5"), which itself nests under
        # ENABLE_SWEEP_POINT_CREEP -- the open-loop profile's #error guard forces
        # that off, so V5.8 cannot compile in at all under NL_PROFILE_GREMSY_OPEN_LOOP,
        # making eligibility architecturally impossible rather than counter-excluded.
        ($source -match '(?s)nlCaptures\[i\]\.eligibleForStatistics =\s*\(NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\)') -and
        ($source -match '(?s)#if NL_MEASUREMENT_PROFILE == NL_PROFILE_GREMSY_OPEN_LOOP\s*#if ENABLE_SWEEP_POINT_CREEP\b')
    'Automatic UART analyzer exports response CSV' =
        ($pythonTool -match 'def analyze_motor_response_timing') -and
        ($pythonTool -match '\.response\.csv') -and
        ($pythonTool -match 'StoppedOutsideDeadband')
    'MATLAB parser and batch analyzer include V5.8' =
        ($matlabParser -match 'case "SWEEP_POINT_TIMING"') -and
        ($matlabParser -match 'TimingEnd = rows_to_table') -and
        ($matlabAnalyzer -match 'TimingByLabel') -and
        ($matlabAnalyzer -match 'MeanFailedStopLatencyMs')
}

$failed = @($checks.GetEnumerator() | Where-Object { -not $_.Value })
foreach ($check in $checks.GetEnumerator()) {
    $status = if ($check.Value) { 'PASS' } else { 'FAIL' }
    Write-Host "[$status] $($check.Key)"
}

if ($failed.Count -gt 0) {
    throw "V5.8 timing contract failed: $($failed.Count) check(s)."
}

Write-Host '[PASS] V5.8 command-response timing contract is internally consistent.'
