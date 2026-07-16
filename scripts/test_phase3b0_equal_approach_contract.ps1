$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$analyzer = Join-Path $PSScriptRoot 'analyze_nonlinear_logs.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-phase3b0-equal-approach-p05-jig3.txt'
$baselineFixture = Join-Path $PSScriptRoot 'fixtures\schema-v5-phase3b0-closure-probe-p05-jig3.txt'
$csv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3b0-equal-approach.csv'
$baselineCsv = Join-Path ([System.IO.Path]::GetTempPath()) 'jigmotor-phase3b0-equal-approach-baseline.csv'

# Motion Control V2 promotes the formerly optional experiment to the compiled
# default and replaces the 23-command staircase with a 40-command S-curve.
# Keep the legacy fixture checks below for legacy-profile branches, while the
# active V2 branch has its own source contract here.
if ($source -match '#define\s+NL_MOTION_PROFILE\s+NL_MOTION_PROFILE_SCURVE_V2') {
    Assert-True ($source -match '#ifndef\s+ENABLE_B0B_EQUAL_APPROACH\s*[\r\n]+#define\s+ENABLE_B0B_EQUAL_APPROACH\s+1') `
        'Motion V2 must compile equal-approach as the default.'
    Assert-True ($source -match 'SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2') `
        'Motion V2 equal-approach protocol ID is missing.'
    Assert-True ($source -match '#define\s+NL_B0B_APPROACH_DIAG_STEPS\s+NL_MOTION_COMMANDS_PER_DEG') `
        'Motion V2 approach diagnostic capacity must follow the selected profile.'
    Assert-True ($source -match 'forwardStepsExecuted\s*==\s*NL_B0B_APPROACH_DIAG_STEPS' -and
            $source -match 'backoffStepsExecuted\s*==\s*NL_B0B_APPROACH_DIAG_STEPS') `
        'Motion V2 must structurally validate both equal-approach legs.'
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'Equal-approach leaked into the frozen official validity gate.'
    Write-Host '[ OK ] Phase-3B0 equal-approach promoted Motion-V2 contract passed.'
    exit 0
}

try {
    # --- Default-off contract: protocol A must be the compiled default. ---
    Assert-True ($source -match '#ifndef\s+ENABLE_B0B_EQUAL_APPROACH\s*[\r\n]+#define\s+ENABLE_B0B_EQUAL_APPROACH\s+0') `
        'ENABLE_B0B_EQUAL_APPROACH must default to 0 (protocol A).'
    Assert-True ($source -match '#define\s+NL_B0B_APPROACH_PROTOCOL_ID\s+"DITHER_PLUS_CW_LOCAL_APPROACH_V1"' -and
            $source -match '#define\s+NL_B0B_APPROACH_PROTOCOL_ID\s+"DITHER_V1"') `
        'Both protocol IDs (DITHER_V1 default / DITHER_PLUS_CW_LOCAL_APPROACH_V1 flagged) must exist.'
    Assert-True ($source -match '#define\s+NL_B0B_APPROACH_BACKOFF_RAW\s+NL_GRID_STEP_RAW_MIN') `
        'Backoff distance must match the 182-raw point359-to-point360 closure step.'
    Assert-True ($source -match '\*pos\s*=\s*targetPos;\s*/\*\s*không overshoot') `
        'Ramp helper must clamp the final partial 6/7-raw micro-step to the exact target.'
    Assert-True ($source -match '(?s)#if\s+ENABLE_CCW_ENGINEERING_TEST\s*[\r\n]+#error "B0-B equal-approach') `
        'The CCW/B0-B mutual-exclusion #error guard is missing.'

    # The guard block must appear AFTER the ENABLE_CCW_ENGINEERING_TEST default --
    # placed earlier, the #if would read an undefined macro as 0 and never fire.
    $ccwDefaultIdx = $source.IndexOf('#define ENABLE_CCW_ENGINEERING_TEST 0')
    $b0bBlockIdx = $source.IndexOf('#ifndef ENABLE_B0B_EQUAL_APPROACH')
    Assert-True ($ccwDefaultIdx -ge 0 -and $b0bBlockIdx -gt $ccwDefaultIdx) `
        'B0-B flag block must come after the ENABLE_CCW_ENGINEERING_TEST default.'

    # --- Frozen official contract untouched. ---
    Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
            $source -match 'OfficialResultSource=LEGACY') `
        'B0-B changed the official schema-v5/legacy result contract.'
    Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
        'B0-B leaked into the official measurement-valid gate.'
    Assert-True ($source -match 'NL_SHADOW_CLOSURE_LIMIT_DEG\s+0\.20f') `
        'The pilot closure limit changed -- forbidden in this change.'

    # --- Ramp refactor: single direction-deriving helper, old dual loops gone. ---
    Assert-True ($source -match 'static MA600_Result_t RampCommandToTarget\(') `
        'RampCommandToTarget helper is missing.'
    Assert-True ($source -match '(?s)static MA600_Result_t RampCommandToTarget\(\s*MA600_AcquisitionContext_t \*sweepAcquisition,\s*int32_t \*pos,\s*int32_t targetPos,\s*uint32_t \*stepsExecuted,\s*int64_t \*stepUnwrappedRawLog,\s*uint8_t stepLogCapacity,\s*uint32_t stepDelayMs\)') `
        'RampCommandToTarget must keep its parameter list (stepsExecuted + the SF-pre-step log buffer/capacity pair + stepDelayMs).'
    Assert-True ($source -match 'RampCommandToTarget\(&sweepAcquisition,\s*&pos,\s*targetPos,\s*NULL,\s*NULL,\s*0,\s*[\r\n\s]*rampStepDelayMs\)') `
        'The main sweep ramp no longer routes through RampCommandToTarget as a no-op (NULL stepsExecuted, NULL/0 step log, explicit delay).'
    Assert-True (([regex]::Matches($source, 'while\s*\(pos\s*[<>]\s*targetPos\)')).Count -eq 0) `
        'The old inline CW/CCW ramp loops must be gone (helper is the single ramp path).'

    # --- SF-pre-step diagnostic: per-microstep log fills only on an accepted
    # sample, and only after the error-return path (never logs a failed step). ---
    Assert-True ($source -match '(?s)#define\s+NL_B0B_APPROACH_DIAG_STEPS\s+\\\s*\(\(NL_GRID_STEP_RAW_MAX\s*\+\s*NL_RAMP_STEP\s*-\s*1U\)\s*/\s*NL_RAMP_STEP\)') `
        'NL_B0B_APPROACH_DIAG_STEPS must hold ceil(183/8)=23 commands.'
    $rampFn = [regex]::Match($source,
        '(?s)static MA600_Result_t RampCommandToTarget\(.*?\n\}').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($rampFn)) `
        'Could not locate the full RampCommandToTarget body for step-log ordering checks.'
    $errorReturnIdx = $rampFn.IndexOf('return r;')
    $stepLogFillIdx = $rampFn.IndexOf('stepUnwrappedRawLog[steps - 1] = rampSample.unwrappedRaw;')
    Assert-True ($errorReturnIdx -ge 0 -and $stepLogFillIdx -gt $errorReturnIdx) `
        'The step log must only be filled AFTER the error-return check, so a failed/unaccepted sample is never logged.'

    # --- Approach block structure inside CaptureSweep. ---
    $approachBlock = [regex]::Match($source,
        '(?s)#if ENABLE_B0B_EQUAL_APPROACH\s*/\* ===== Protocol B.*?#else\s*/\* ===== Protocol A').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($approachBlock)) `
        'Could not locate the protocol-B approach block inside CaptureSweep.'

    # Command/encoder domain separation: commands start at 0, ramp to -256 and
    # back to 0 through the helper only; no unwrapped encoder value may ever be
    # cast into a motor command.
    Assert-True ($approachBlock -match 'int32_t\s+commandPos\s*=\s*0') `
        'commandPos must start at 0 in the motor-command domain.'
    Assert-True ($approachBlock -match 'backoffCommand\s*=\s*0\s*-\s*NL_B0B_APPROACH_BACKOFF_RAW') `
        'Backoff command must be -NL_B0B_APPROACH_BACKOFF_RAW in the command domain.'
    Assert-True ($approachBlock -match 'RampCommandToTarget\(&sweepAcquisition,\s*[\r\n\s]*&commandPos,\s*backoffCommand' -and
            $approachBlock -match 'RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*0,') `
        'The 0 -> -256 -> 0 command sequence through RampCommandToTarget is incomplete.'
    $approachBlockNoComments = [regex]::Replace($approachBlock, '(?s)/\*.*?\*/', '')
    Assert-True ($approachBlockNoComments -notmatch 'Motor_SetElectricalPos') `
        'The approach block must not command the motor directly -- only via RampCommandToTarget.'
    Assert-True ($source -notmatch 'Motor_SetElectricalPos\(\(uint16_t\)\s*\w*[Uu]nwrapped') `
        'An encoder-domain unwrapped value is being cast into a motor command (P0 domain-mixing bug).'

    # Settle targets stay in the encoder domain.
    Assert-True ($approachBlock -match 'expectedBackoffUnwrapped\s*=\s*initialAnchorUnwrapped\s*-\s*NL_B0B_APPROACH_BACKOFF_RAW' -and
            $approachBlock -match 'expectedPoint0Unwrapped\s*=\s*backoffAnchorUnwrapped\s*\+\s*NL_B0B_APPROACH_BACKOFF_RAW') `
        'Backoff/point-0 settle targets are not derived in the encoder (unwrapped) domain.'

    # All three settles are mandatory (== NL_SETTLE_OK) with the two-way error
    # split: real sensor errors propagate, soft failures return MA600_RESULT_OK.
    Assert-True (([regex]::Matches($approachBlock, 'FinalizeApproachEarlyExit\(out,\s*&sweepAcquisition\)')).Count -eq 6) `
        'All 6 approach failure sites (acquire, 3 settles, 2 ramps) must call FinalizeApproachEarlyExit.'
    Assert-True (([regex]::Matches($approachBlock, 'return MA600_RESULT_OK;')).Count -eq 3) `
        'Exactly the 3 settle soft-failure paths may return MA600_RESULT_OK early.'
    Assert-True (([regex]::Matches($approachBlock, '==\s*NL_SETTLE_ACQUISITION_ERROR')).Count -eq 3) `
        'Each of the 3 settles must split ACQUISITION_ERROR from soft failures.'
    Assert-True ($approachBlock -match 'WaitForPointSettle\(&sweepAcquisition,[\r\n\s]*sample\.unwrappedRaw,\s*false' -and
            $approachBlock -match 'WaitForPointSettle\(&sweepAcquisition,[\r\n\s]*expectedBackoffUnwrapped,\s*true' -and
            $approachBlock -match 'WaitForPointSettle\(&sweepAcquisition,[\r\n\s]*expectedPoint0Unwrapped,\s*true') `
        'Settle target requirements are wrong (initial: none; backoff/point-0: explicit target).'

    # Early exits must zero the capture and invalidate the measurement.
    $finalizeFn = [regex]::Match($source,
        '(?s)static void FinalizeApproachEarlyExit.*?\n\}').Value
    Assert-True ($finalizeFn -match 'out->measurementValid\s*=\s*false' -and
            $finalizeFn -match 'out->capturedCount\s*=\s*0') `
        'FinalizeApproachEarlyExit must invalidate the measurement and zero capturedCount.'

    # Counter allocation: initial+backoff settles into approachSettleAcquisition;
    # the point-0 settle into the MAIN settleAcquisition (protocol parity) plus a
    # diagnostic-only copy that never enters the Acq* subtraction.
    Assert-True (([regex]::Matches($approachBlock, '&out->approachSettleAcquisition\)')).Count -eq 2) `
        'Exactly the initial and backoff settles may charge approachSettleAcquisition.'
    Assert-True ($approachBlock -match '(?s)AccumulateCounterDelta\(&sweepAcquisition,\s*&settleBefore,\s*&out->settleAcquisition\);\s*AccumulateCounterDelta\(&sweepAcquisition,\s*&settleBefore,[\r\n\s]*&out->approachPoint0SettleAcquisitionDiag\)') `
        'The point-0 settle must charge the MAIN settleAcquisition plus the diagnostic copy.'
    $acqFormula = [regex]::Match($source,
        '(?s)/\* Frozen schema-v5 Acq\* fields.*?out->acquisitionFailedSamples[^;]+;').Value
    $acqFormulaNoComments = [regex]::Replace($acqFormula, '(?s)/\*.*?\*/', '')
    Assert-True ($acqFormulaNoComments -match 'approachSettleAcquisition\.readAttempts' -and
            $acqFormulaNoComments -match 'approachBackoffRampAcquisition\.readAttempts' -and
            $acqFormulaNoComments -match 'approachForwardRampAcquisition\.readAttempts') `
        'The frozen Acq* formula must subtract the three approach counter sets.'
    Assert-True ($acqFormulaNoComments -notmatch 'approachPoint0SettleAcquisitionDiag') `
        'The diagnostic point-0 settle copy must NEVER be subtracted (double-count bug).'

    # ApproachAcquisitionClean must cover all four approach counter sets.
    foreach ($counterSet in @('approachSettleAcquisition', 'approachBackoffRampAcquisition',
            'approachForwardRampAcquisition', 'approachPoint0SettleAcquisitionDiag')) {
        foreach ($f in @('retryCount', 'transportErrorCount', 'jumpRejectCount', 'failedSampleCount')) {
            Assert-True ($approachBlock -match ('out->' + $counterSet + '\.' + $f + '\s*==\s*0')) `
                ("ApproachAcquisitionClean is missing " + $counterSet + '.' + $f)
        }
    }

    # Structural gate composition.
    Assert-True ($approachBlock -match '(?s)out->approachStructuralValid\s*=\s*out->approachDirectionValid\s*&&\s*out->approachStepCountValid\s*&&\s*out->backoffDirectionValid\s*&&\s*out->approachAcquisitionClean') `
        'ApproachStructuralValid must gate direction + step count + backoff direction + acquisition-clean.'
    Assert-True ($approachBlock -match 'forwardStepsExecuted\s*==\s*NL_B0B_APPROACH_DIAG_STEPS' -and
            $approachBlock -match 'backoffStepsExecuted\s*==\s*NL_B0B_APPROACH_DIAG_STEPS') `
        'Step-count validity must check both legs against the expected 23 commands.'
    Assert-True ($approachBlock -match 'approachReturnErrorRaw\s*=\s*sweepOriginUnwrapped\s*-\s*initialAnchorUnwrapped') `
        'The closed-loop 0 -> -256 -> 0 return-error diagnostic is missing.'

    # SF-pre-step: each leg's RampCommandToTarget call must pass its own
    # struct-embedded buffer + NL_B0B_APPROACH_DIAG_STEPS capacity, and the
    # returned step count must be captured right next to *StepsExecuted.
    Assert-True ($approachBlock -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*backoffCommand,\s*&backoffStepsExecuted,\s*out->approachBackoffStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_RAMP_STEP_DELAY_MS\)') `
        'The backoff leg must log its per-step raw positions into approachBackoffStepUnwrapped, with the delay passed explicitly.'
    Assert-True ($approachBlock -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*0,\s*&forwardStepsExecuted,\s*out->approachForwardStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_RAMP_STEP_DELAY_MS\)') `
        'The forward leg must log its per-step raw positions into approachForwardStepUnwrapped, with the delay passed explicitly.'
    Assert-True ($approachBlock -match '(?s)out->approachBackoffStepsExecuted\s*=\s*backoffStepsExecuted;\s*out->approachBackoffStepCount\s*=\s*\(uint8_t\)backoffStepsExecuted;') `
        'approachBackoffStepCount must be captured right alongside approachBackoffStepsExecuted.'
    Assert-True ($approachBlock -match '(?s)out->approachForwardStepsExecuted\s*=\s*forwardStepsExecuted;\s*out->approachForwardStepCount\s*=\s*\(uint8_t\)forwardStepsExecuted;') `
        'approachForwardStepCount must be captured right alongside approachForwardStepsExecuted.'

    # Success path must hand its settle result to the shared post-#endif code.
    Assert-True ($approachBlock -match '(?s)sample\s*=\s*point0Settle\.finalSample;\s*settleObservation\s*=\s*point0Settle;\s*settleResult\s*=\s*out->approachPoint0SettleResult;') `
        'Protocol B does not hand sample/settleObservation/settleResult to the shared origin code.'

    # NA-when-not-attempted: three Attempted flags feed the record printing.
    foreach ($flag in @('approachInitialAttempted', 'approachBackoffAttempted', 'approachPoint0Attempted')) {
        Assert-True ($source -match ('c->' + $flag + '\s*[\r\n\s]*\?\s*SettleResultName')) `
            ("APPROACH_RESULT must print NA unless " + $flag + ' is set (zero-init NL_SETTLE_OK==0 must not read as OK).')
    }
    Assert-True ($source -match 'NL_APPROACH_NOT_APPLICABLE\s*=\s*0') `
        'NL_APPROACH_NOT_APPLICABLE must be the zero-init default, distinct from OK.'

    # Summary pair always in META and SHADOW_RESULT; detailed record separate.
    Assert-True ($source -match '(?s)META,SchemaVersion.*?ApproachProtocol=%s,ApproachStructuralValid=%s') `
        'META must always carry the ApproachProtocol/ApproachStructuralValid summary pair.'
    Assert-True ($source -match '(?s)SHADOW_RESULT,SchemaVersion.*?ApproachProtocol=%s,ApproachStructuralValid=%s') `
        'SHADOW_RESULT must always carry the ApproachProtocol/ApproachStructuralValid summary pair.'
    Assert-True ($source -match '(?s)#if ENABLE_B0B_EQUAL_APPROACH.*?APPROACH_RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,.*?Direction=%s,Official=0,Protocol=%s,Started=1,Complete=%d,Status=%s') `
        'APPROACH_RESULT identity header must follow the CLOSURE_PROBE_RESULT pattern and be flag-gated.'
    Assert-True ($source -match 'ApproachMotionQualification=UNCALIBRATED') `
        'The uncalibrated motion-threshold marker is missing from APPROACH_RESULT.'
    $approachPrint = [regex]::Match($source,
        '(?s)APPROACH_RESULT,SchemaVersion.*?returnErrBuf\);').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($approachPrint) -and
            $approachPrint -notmatch '%ld,?"?\s*[\r\n\s]*.*BackoffObservedDeltaRaw') `
        'int64 approach diagnostics must go through FormatI64 buffers, never %ld.'
    foreach ($i64Buf in @('backoffDeltaBuf', 'backoffTargetErrBuf', 'approachDeltaBuf',
            'approachTargetErrBuf', 'returnErrBuf')) {
        Assert-True ($source -match ('FormatI64\(c->\w+,\s*' + $i64Buf)) `
            ("int64 diagnostic " + $i64Buf + ' must be formatted with FormatI64.')
    }

    # --- SF-pre-step: struct fields, unconditional so protocol A compiles too. ---
    Assert-True ($source -match 'uint8_t\s+approachBackoffStepCount;\s*[\r\n]+\s*int64_t\s+approachBackoffStepUnwrapped\[NL_B0B_APPROACH_DIAG_STEPS\];\s*[\r\n]+\s*uint8_t\s+approachForwardStepCount;\s*[\r\n]+\s*int64_t\s+approachForwardStepUnwrapped\[NL_B0B_APPROACH_DIAG_STEPS\];') `
        'NlSweepCapture_t is missing the per-microstep step-log fields (or their declared order/type changed).'

    # --- APPROACH_STEPS record: 2 lines (BACKOFF/FORWARD), pipe-delimited via
    # the bounded FormatI64PipeList helper, flag-gated, never %ld for int64. ---
    Assert-True ($source -match '(?s)#if ENABLE_B0B_EQUAL_APPROACH.*?static void FormatI64PipeList\(') `
        'FormatI64PipeList helper must exist and be flag-gated under ENABLE_B0B_EQUAL_APPROACH.'
    $pipeListFn = [regex]::Match($source,
        '(?s)static void FormatI64PipeList\(.*?\n\}').Value
    Assert-True (-not [string]::IsNullOrWhiteSpace($pipeListFn) -and
            $pipeListFn -match 'FormatI64\(values\[i\]' -and
            $pipeListFn -match 'pos\s*\+\s*need\s*>=\s*outSize') `
        'FormatI64PipeList must format each value with FormatI64 and bounds-check before appending (no overflow).'
    Assert-True ($source -match '"APPROACH_STEPS,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"\s*[\r\n]+\s*"Official=0,Leg=BACKOFF,StepCount=%u,UnwrappedRaw=%s\\r\\n"') `
        'APPROACH_STEPS BACKOFF line is missing or its field order changed.'
    Assert-True ($source -match '"APPROACH_STEPS,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"\s*[\r\n]+\s*"Official=0,Leg=FORWARD,StepCount=%u,UnwrappedRaw=%s\\r\\n"') `
        'APPROACH_STEPS FORWARD line is missing or its field order changed.'
    Assert-True ($source -match 'FormatI64PipeList\(c->approachBackoffStepUnwrapped,\s*c->approachBackoffStepCount,\s*[\r\n\s]*backoffStepsBuf,\s*sizeof\(backoffStepsBuf\)\)' -and
            $source -match 'FormatI64PipeList\(c->approachForwardStepUnwrapped,\s*c->approachForwardStepCount,\s*[\r\n\s]*forwardStepsBuf,\s*sizeof\(forwardStepsBuf\)\)') `
        'APPROACH_STEPS lines must be built from FormatI64PipeList over the captured per-leg buffers.'
    # Worst case: 32 steps x a full-width int64 ("-9223372036854775808" = 20
    # chars) + 31 '|' separators = 671 chars -- the declared stack buffers
    # must not be smaller than that (regressing NL_RAMP_STEP/NL_POS_INCREASE
    # without resizing these would silently truncate the diagnostic).
    $stepBufMatches = [regex]::Matches($source, 'char\s+(?:backoffStepsBuf|forwardStepsBuf)\[(\d+)\]')
    Assert-True ($stepBufMatches.Count -eq 2) 'Expected exactly 2 sized step-log stack buffers (backoff/forward).'
    foreach ($m in $stepBufMatches) {
        Assert-True ([int]$m.Groups[1].Value -ge 672) `
            'backoffStepsBuf/forwardStepsBuf must be >= 672 bytes to hold the worst-case 32-value pipe list.'
    }

    # META line budget: longest real META observed plus the protocol-B summary
    # pair must stay under the LogLineLarge 1900-byte buffer. Measured at test
    # time, not hard-coded from any single historical log.
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
    $summaryPairCost = (',ApproachProtocol=DITHER_PLUS_CW_LOCAL_APPROACH_V1,ApproachStructuralValid=NA').Length
    Assert-True ($maxMetaLen -gt 0) 'No real META line found to measure the line budget against.'
    Assert-True (($maxMetaLen + $summaryPairCost) -lt 1900) `
        ("META line budget exceeded: longest observed " + $maxMetaLen + ' + summary pair ' + $summaryPairCost + ' must stay < 1900.')

    # --- Analyzer round-trip: protocol-B fixture parses and exports. ---
    & $analyzer -Path $fixture -OutCsv $csv | Out-Null
    $rows = @(Import-Csv $csv)
    Assert-True ($rows.Count -eq 1) 'Equal-approach fixture did not produce exactly one record.'
    $row = $rows[0]
    Assert-True ($row.ApproachProtocol -eq 'DITHER_PLUS_CW_LOCAL_APPROACH_V1' -and
            $row.ApproachStructuralValid -eq '1' -and
            $row.ApproachStatus -eq 'OK' -and
            $row.ApproachComplete -eq '1' -and
            $row.ApproachAcquisitionClean -eq '1' -and
            $row.ApproachMotionQualification -eq 'UNCALIBRATED') `
        'Parsed equal-approach contract fields are incomplete.'
    Assert-True ($row.ApproachObservedDeltaRaw -eq '254' -and
            $row.ApproachTargetErrorRaw -eq '-2' -and
            $row.ApproachReturnErrorRaw -eq '-1' -and
            $row.BackoffObservedDeltaRaw -eq '-255') `
        'Approach motion diagnostics were not exported correctly.'
    Assert-True ($row.OfficialResultSource -eq 'LEGACY') `
        'The equal-approach fixture must keep OfficialResultSource=LEGACY.'

    # --- Backward compatibility: a protocol-A log (no Approach fields) still
    # parses clean, with the new export columns simply empty. ---
    & $analyzer -Path $baselineFixture -OutCsv $baselineCsv | Out-Null
    $baselineRows = @(Import-Csv $baselineCsv)
    Assert-True ($baselineRows.Count -eq 1) 'Baseline fixture no longer parses to one record.'
    Assert-True ([string]::IsNullOrEmpty($baselineRows[0].ApproachProtocol) -and
            [string]::IsNullOrEmpty($baselineRows[0].ApproachStatus)) `
        'A protocol-A log without Approach fields must export empty Approach columns, not fabricated values.'

    Write-Host '[ OK ] Phase-3B0-B equal-approach contract tests passed.'
}
finally {
    Remove-Item -LiteralPath $csv -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $baselineCsv -Force -ErrorAction SilentlyContinue
}
