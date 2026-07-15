$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

try {
    # --- Default-off, independent of B0-B and of the step-diag flag. ---
    Assert-True ($source -match '#ifndef\s+ENABLE_SWEEP_RAMP_SOFT_START\s*[\r\n]+#define\s+ENABLE_SWEEP_RAMP_SOFT_START\s+0') `
        'ENABLE_SWEEP_RAMP_SOFT_START must default to 0.'
    Assert-True ($source -match '#define\s+NL_SWEEP_RAMP_SOFT_START_DELAY_MS\s+8U') `
        'NL_SWEEP_RAMP_SOFT_START_DELAY_MS must be the documented initial experimental guess (8).'
    Assert-True ($source -match '#define\s+NL_SWEEP_RAMP_SOFT_START_PROTOCOL_ID\s+"SOFT_START_V1"' -and
            $source -match '#define\s+NL_SWEEP_RAMP_SOFT_START_PROTOCOL_ID\s+"NONE"') `
        'Both protocol IDs (SOFT_START_V1 when flagged / NONE default) must exist.'

    # --- RampCommandToTarget signature: stepDelayMs is now a real (7th)
    # parameter, and osDelay uses it instead of the old fixed constant. ---
    Assert-True ($source -match '(?s)static MA600_Result_t RampCommandToTarget\(\s*MA600_AcquisitionContext_t \*sweepAcquisition,\s*int32_t \*pos,\s*int32_t targetPos,\s*uint32_t \*stepsExecuted,\s*int64_t \*stepUnwrappedRawLog,\s*uint8_t stepLogCapacity,\s*uint32_t stepDelayMs\)') `
        'RampCommandToTarget must keep its 7-parameter signature ending in stepDelayMs.'
    $rampFn = [regex]::Match($source,
        '(?s)static MA600_Result_t RampCommandToTarget\(.*?\n\}').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($rampFn) -and $rampFn -match 'osDelay\(stepDelayMs\);') `
        'RampCommandToTarget must call osDelay(stepDelayMs), not a hard-coded constant.'
    Assert-True ($rampFn -notmatch 'osDelay\(NL_RAMP_STEP_DELAY_MS\)') `
        'RampCommandToTarget must no longer reference NL_RAMP_STEP_DELAY_MS internally -- callers pass it explicitly now.'

    # --- The 3 pre-existing call sites all pass NL_RAMP_STEP_DELAY_MS
    # explicitly -- their behavior must be byte-for-byte unchanged. ---
    Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*backoffCommand,\s*&backoffStepsExecuted,\s*out->approachBackoffStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*NL_RAMP_STEP_DELAY_MS\)') `
        'The B0-B backoff call must pass NL_RAMP_STEP_DELAY_MS explicitly (unchanged behavior).'
    Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*0,\s*&forwardStepsExecuted,\s*out->approachForwardStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*NL_RAMP_STEP_DELAY_MS\)') `
        'The B0-B forward call must pass NL_RAMP_STEP_DELAY_MS explicitly (unchanged behavior).'
    Assert-True ($source -match 'RampCommandToTarget\(&sweepAcquisition, &pos, targetPos, NULL, NULL, 0,\s*[\r\n\s]*rampStepDelayMs\)') `
        'The non-diag main-sweep call (#else branch) must pass rampStepDelayMs (which defaults to NL_RAMP_STEP_DELAY_MS), not a bare NL_RAMP_STEP_DELAY_MS or a different literal.'

    # --- Main-sweep call site: rampStepDelayMs defaults to
    # NL_RAMP_STEP_DELAY_MS and is ONLY overridden for pointIndex==1, ONLY
    # under the flag. ---
    $callSiteBlock = [regex]::Match($source,
        '(?s)SetEngineState\(NL_ENGINE_RAMP\);\s*NlAcquisitionCounters_t rampBefore = SnapshotAcquisitionCounters\(&sweepAcquisition\);.*?AccumulateCounterDelta\(&sweepAcquisition, &rampBefore, &out->rampAcquisition\);').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($callSiteBlock)) `
        'Could not locate the main-sweep ramp call site.'
    Assert-True ($callSiteBlock -match 'uint32_t rampStepDelayMs = NL_RAMP_STEP_DELAY_MS;') `
        'rampStepDelayMs must default to NL_RAMP_STEP_DELAY_MS unconditionally.'
    $ifIdx = $callSiteBlock.IndexOf('#if ENABLE_SWEEP_RAMP_SOFT_START')
    $defaultIdx = $callSiteBlock.IndexOf('uint32_t rampStepDelayMs = NL_RAMP_STEP_DELAY_MS;')
    $overrideIdx = $callSiteBlock.IndexOf('rampStepDelayMs = NL_SWEEP_RAMP_SOFT_START_DELAY_MS;')
    $pointCheckIdx = $callSiteBlock.IndexOf('if (pointIndex == 1)')
    Assert-True ($ifIdx -ge 0 -and $defaultIdx -ge 0 -and $overrideIdx -gt $ifIdx -and
            $pointCheckIdx -gt $ifIdx -and $pointCheckIdx -lt $overrideIdx -and $defaultIdx -lt $ifIdx) `
        'The override must be guarded by ENABLE_SWEEP_RAMP_SOFT_START, gated on pointIndex==1, and come after the unconditional default assignment.'
    Assert-True ($callSiteBlock -match 'rampDiagThisRamp \? &rampDiagSteps : NULL, rampDiagBuf, rampDiagCapacity,\s*[\r\n\s]*rampStepDelayMs\)') `
        'The diag-enabled RampCommandToTarget call must pass rampStepDelayMs as its final argument.'

    # --- META: always-print summary pair, same convention as ApproachProtocol. ---
    Assert-True ($source -match '"ApproachProtocol=%s,ApproachStructuralValid=%s,"\s*[\r\n]+\s*"RampSoftStartProtocol=%s,RampSoftStartDelayMs=%s,"') `
        'META must carry RampSoftStartProtocol/RampSoftStartDelayMs immediately after the Approach pair.'
    Assert-True ($source -match 'NL_B0B_APPROACH_PROTOCOL_ID, approachStructuralValidText,\s*[\r\n]+\s*NL_SWEEP_RAMP_SOFT_START_PROTOCOL_ID, rampSoftStartDelayText,') `
        'The META argument list must supply NL_SWEEP_RAMP_SOFT_START_PROTOCOL_ID/rampSoftStartDelayText right after the Approach pair.'
    Assert-True ($source -match '(?s)#if ENABLE_SWEEP_RAMP_SOFT_START\s*[\r\n]+\s*char rampSoftStartDelayText\[8\];\s*[\r\n]+\s*snprintf\(rampSoftStartDelayText, sizeof\(rampSoftStartDelayText\), "%u",\s*[\r\n]+\s*\(unsigned\)NL_SWEEP_RAMP_SOFT_START_DELAY_MS\);\s*[\r\n]+#else\s*[\r\n]+\s*const char \*rampSoftStartDelayText = "NA";\s*[\r\n]+#endif') `
        'rampSoftStartDelayText must print the numeric delay when flagged on, "NA" otherwise.'

    # --- META line budget: both new summary pairs (Approach + RampSoftStart)
    # together must still fit the 1900-byte LogLineLarge buffer, measured
    # against the longest real META line on disk, not assumed. ---
    Assert-True ($source -match 'char\s+buf\[1900\]') `
        'Could not confirm the LogLineLarge 1900-byte buffer (source layout changed?).'
    $logFiles = Get-ChildItem -Path $root -Filter '*.txt' -File |
        Where-Object { $_.Length -lt 20MB }
    $maxMetaLen = 0
    foreach ($lf in $logFiles) {
        foreach ($line in [System.IO.File]::ReadLines($lf.FullName)) {
            if ($line.StartsWith('META,') -and $line.Length -gt $maxMetaLen) {
                $maxMetaLen = $line.Length
            }
        }
    }
    Assert-True ($maxMetaLen -gt 0) 'No real META line found to measure the line budget against.'
    # NOTE: the longest observed real META line already includes the
    # ApproachProtocol/ApproachStructuralValid pair (deployed in an earlier
    # change) -- only the NEW RampSoftStart pair is additional budget here.
    $softStartPairCost = (',RampSoftStartProtocol=SOFT_START_V1,RampSoftStartDelayMs=NA').Length
    Assert-True (($maxMetaLen + $softStartPairCost) -lt 1900) `
        ("META line budget exceeded: longest observed " + $maxMetaLen +
         ' (already includes ApproachProtocol pair) + new RampSoftStart pair ' + $softStartPairCost + ' must stay < 1900.')

    # --- No leakage into the official contract. ---
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'The soft-start experiment must not touch the official measurement-valid gate.'
    Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
            $source -match 'OfficialResultSource=LEGACY') `
        'The soft-start experiment must not change the official schema-v5/legacy result contract.'
    Assert-True ($source -notmatch 'kp\s*=\s*2\.[1-9]' -and $source -notmatch 'ki\s*=\s*0\.00[4-9]') `
        'This change must not touch PID gains -- only ramp timing for one specific ramp.'

    Write-Host '[ OK ] Sweep-ramp soft-start experiment contract tests passed.'
}
finally {
}
