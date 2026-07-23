$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

if ($source -match '#define\s+NL_MOTION_PROFILE\s+NL_MOTION_PROFILE_SCURVE_V2') {
    Assert-True ($source -match '#ifndef\s+ENABLE_SWEEP_RAMP_STEP_DIAG\s*[\r\n]+#define\s+ENABLE_SWEEP_RAMP_STEP_DIAG\s+1') `
        'Motion V2 must enable the first-three-ramp observation by default.'
    Assert-True ($source -match '#define\s+NL_SWEEP_RAMP_DIAG_MAX_STEPS\s+NL_MOTION_COMMANDS_PER_DEG') `
        'Motion V2 ramp diagnostic capacity must follow the selected profile.'
    Assert-True ($source -match 'sweepRampStepUnwrapped\[NL_SWEEP_RAMP_DIAG_COUNT\]\[NL_SWEEP_RAMP_DIAG_MAX_STEPS\]') `
        'Motion V2 per-command encoder trace storage is missing.'
    Assert-True ($source -match 'SWEEP_RAMP_STEPS,SchemaVersion=' -and
            $source -match 'char\s+rampStepsBuf\[1024\]') `
        'Motion V2 ramp trace output or its bounded buffer is missing.'
    Write-Host '[ OK ] Sweep-ramp Motion-V2 diagnostic contract passed.'
    exit 0
}

try {
    # --- Default-off, independent of B0-B. ---
    Assert-True ($source -match '#ifndef\s+ENABLE_SWEEP_RAMP_STEP_DIAG\s*[\r\n]+#define\s+ENABLE_SWEEP_RAMP_STEP_DIAG\s+0') `
        'ENABLE_SWEEP_RAMP_STEP_DIAG must default to 0.'
    Assert-True ($source -match '(?s)#define\s+NL_SWEEP_RAMP_DIAG_MAX_STEPS\s+\\\s*\(\(NL_GRID_STEP_RAW_MAX\s*\+\s*NL_RAMP_STEP\s*-\s*1U\)\s*/\s*NL_RAMP_STEP\)') `
        'NL_SWEEP_RAMP_DIAG_MAX_STEPS must hold the ceil(183/8) one-degree ramp.'
    Assert-True ($source -match '#define\s+NL_SWEEP_RAMP_DIAG_COUNT\s+3U') `
        'NL_SWEEP_RAMP_DIAG_COUNT must be 3 (ramps toward point 1, 2, 3).'
    Assert-True ($source -notmatch 'NL_SWEEP_RAMP_DIAG_MAX_STEPS\s*=\s*NL_B0B_APPROACH_DIAG_STEPS' -and
            $source -notmatch 'sweepRampStepUnwrapped\[NL_B0B_APPROACH_DIAG_STEPS\]') `
        'The sweep-ramp diagnostic must use its own constant, not reach into B0-B''s NL_B0B_APPROACH_DIAG_STEPS (keeps the two features independent).'

    # --- FormatI64PipeList guard widened to serve both features, without
    # touching NlApproachResultName's B0-B-only guard. ---
    Assert-True ($source -match '(?s)static const char \*NlApproachResultName.*?\n\}\s*[\r\n]+#endif') `
        'NlApproachResultName must stay under its own #endif immediately after the function (B0-B-only, not widened).'
    Assert-True ($source -match '#if\s+ENABLE_B0B_EQUAL_APPROACH\s*\|\|\s*ENABLE_SWEEP_RAMP_STEP_DIAG\s*[\r\n]+static void FormatI64PipeList\(') `
        'FormatI64PipeList must be guarded by (ENABLE_B0B_EQUAL_APPROACH || ENABLE_SWEEP_RAMP_STEP_DIAG), not B0-B alone.'

    # --- Struct fields: real #if-guarded (not always-present) since the
    # array-size constants only exist when the flag is on. ---
    Assert-True ($source -match 'uint8_t\s+sweepRampStepCount\[NL_SWEEP_RAMP_DIAG_COUNT\];\s*[\r\n]+\s*int64_t\s+sweepRampStepUnwrapped\[NL_SWEEP_RAMP_DIAG_COUNT\]\[NL_SWEEP_RAMP_DIAG_MAX_STEPS\];') `
        'NlSweepCapture_t is missing the sweepRampStepCount/sweepRampStepUnwrapped fields (or their declared shape changed).'
    $fieldDeclIdx = $source.IndexOf('uint8_t  sweepRampStepCount[NL_SWEEP_RAMP_DIAG_COUNT];')
    $guardBeforeIdx = $source.LastIndexOf('#if ENABLE_SWEEP_RAMP_STEP_DIAG', $fieldDeclIdx)
    $endifAfterIdx = $source.IndexOf('#endif', $fieldDeclIdx)
    $nextIfAfterGuardIdx = $source.IndexOf('#if', $guardBeforeIdx + 1)
    Assert-True ($fieldDeclIdx -ge 0 -and $guardBeforeIdx -ge 0 -and $endifAfterIdx -gt $fieldDeclIdx -and
            ($nextIfAfterGuardIdx -lt 0 -or $nextIfAfterGuardIdx -gt $fieldDeclIdx -or $nextIfAfterGuardIdx -eq $guardBeforeIdx)) `
        'The step-log struct fields must sit directly inside their own #if ENABLE_SWEEP_RAMP_STEP_DIAG / #endif block.'

    # --- Call site: uses pointIndex (already incremented) directly, no
    # extra counter; instruments only ramps toward point 1..NL_SWEEP_RAMP_DIAG_COUNT;
    # the non-instrumented (#else) path is an exact no-op, unchanged from before. ---
    $callSiteBlock = [regex]::Match($source,
        '(?s)SetEngineState\(NL_ENGINE_RAMP\);\s*NlAcquisitionCounters_t rampBefore = SnapshotAcquisitionCounters\(&sweepAcquisition\);.*?AccumulateCounterDelta\(&sweepAcquisition, &rampBefore, &out->rampAcquisition\);').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($callSiteBlock)) `
        'Could not locate the main-sweep ramp call site with the sweep-ramp-diag wiring.'
    Assert-True ($callSiteBlock -match 'rampDiagThisRamp\s*=\s*\(\(uint32_t\)pointIndex\s*<=\s*NL_SWEEP_RAMP_DIAG_COUNT\)') `
        'The instrumented-ramp selector must use pointIndex (already incremented before the ramp runs) directly, not a separate counter.'
    Assert-True ($callSiteBlock -match 'out->sweepRampStepUnwrapped\[pointIndex\s*-\s*1\]') `
        'The per-ramp buffer must be indexed by pointIndex-1 (0-based slot for the ramp toward point pointIndex).'
    Assert-True ($callSiteBlock -match 'RampCommandToTarget\(&sweepAcquisition,\s*&pos,\s*targetPos,\s*rampDiagThisRamp\s*\?\s*&rampDiagSteps\s*:\s*NULL,\s*rampDiagBuf,\s*rampDiagCapacity,\s*[\r\n\s]*rampStepDelayMs\)') `
        'The instrumented call must pass the conditional stepsExecuted pointer, the per-ramp buffer/capacity, and rampStepDelayMs.'
    Assert-True ($callSiteBlock -match '#else\s*[\r\n]+\s*acquisitionResult = RampCommandToTarget\(&sweepAcquisition, &pos, targetPos, NULL, NULL, 0,\s*[\r\n\s]*rampStepDelayMs\);\s*[\r\n]+#endif') `
        'The #else (diag-off) branch must pass rampStepDelayMs too (which itself defaults to NL_RAMP_STEP_DELAY_MS unless the independent soft-start flag overrides it).'
    Assert-True ($callSiteBlock -match 'out->sweepRampStepCount\[pointIndex\s*-\s*1\]\s*=\s*\(uint8_t\)rampDiagSteps;') `
        'The observed step count must be captured into sweepRampStepCount right after the instrumented call.'

    # --- Print block: independent #if guard, only emits for ramps actually
    # reached (StepCount > 0), uses FormatI64PipeList, correct field order. ---
    Assert-True ($source -match '(?s)#if ENABLE_SWEEP_RAMP_STEP_DIAG\s*/\*.*?for \(uint32_t rampDiagIdx = 0U; rampDiagIdx < NL_SWEEP_RAMP_DIAG_COUNT; rampDiagIdx\+\+\)') `
        'The SWEEP_RAMP_STEPS print loop must be independently flag-guarded and iterate all instrumented slots.'
    $printBlock = [regex]::Match($source,
        '(?s)for \(uint32_t rampDiagIdx = 0U;.*?SWEEP_RAMP_STEPS.*?rampStepsBuf\);\s*\}\s*#endif').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($printBlock)) `
        'Could not locate the full SWEEP_RAMP_STEPS print block.'
    Assert-True ($printBlock -match 'if\s*\(c->sweepRampStepCount\[rampDiagIdx\]\s*==\s*0U\)\s*[\r\n]+\s*\{\s*continue;') `
        'A ramp never reached (StepCount==0) must be skipped, not printed with fabricated data.'
    Assert-True ($printBlock -match '"SWEEP_RAMP_STEPS,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"\s*[\r\n]+\s*"Official=0,ToPointIndex=%lu,StepCount=%u,UnwrappedRaw=%s\\r\\n"') `
        'SWEEP_RAMP_STEPS field order/format changed unexpectedly.'
    Assert-True ($printBlock -match 'FormatI64PipeList\(c->sweepRampStepUnwrapped\[rampDiagIdx\],\s*[\r\n\s]*c->sweepRampStepCount\[rampDiagIdx\],\s*rampStepsBuf,\s*sizeof\(rampStepsBuf\)\)') `
        'SWEEP_RAMP_STEPS must build its value list via FormatI64PipeList over the captured buffer.'
    Assert-True ($printBlock -match '\(unsigned long\)\(rampDiagIdx \+ 1U\)') `
        'ToPointIndex must be 1-based (rampDiagIdx+1), matching pointIndex at the time of capture.'
    $stepBufMatch = [regex]::Match($source, 'char\s+rampStepsBuf\[(\d+)\]')
    Assert-True ($stepBufMatch.Success -and [int]$stepBufMatch.Groups[1].Value -ge 672) `
        'rampStepsBuf must be >= 672 bytes to hold the worst-case 32-value pipe list.'

    # --- No leakage into the official contract. ---
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'The sweep-ramp diagnostic must not touch the official measurement-valid gate.'
    Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
            $source -match 'OfficialResultSource=LEGACY') `
        'The sweep-ramp diagnostic must not change the official schema-v5/legacy result contract.'

    Write-Host '[ OK ] Sweep-ramp per-microstep diagnostic contract tests passed.'
}
finally {
}
