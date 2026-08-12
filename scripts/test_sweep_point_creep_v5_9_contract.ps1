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

Assert-True ($source -match ('#define\s+ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION\s+' + $expectedFlag) -and
        $source -match 'V5\.9 terminal correction requires frozen V5\.5 motion' -and
        $source -match 'V5\.9 terminal correction requires V5\.4 universal fine landing' -and
        $source -match 'V5\.9 extends V5\.5 motion; V5\.6 three-stage MID landing must remain disabled' -and
        $source -match 'V5\.9 changes motion; V5\.7 passive-hold diagnostic assumes frozen V5\.5 motion' -and
        $source -match 'V5\.9 and V5\.4a are separate diagnostic/motion identities' -and
        $source -match 'V5\.8 DWT timing is explicitly allowed ON at the same time as V5\.9') `
    'V5.9 feature default or dependency/exclusion guards are invalid.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_PROTOCOL_ID\s+"ADAPTIVE_BASE_TO_EXTENDED_ESCALATION_WITH_EXTENDED_TERMINAL_CAP_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_TERMINAL_PROTOCOL_ID\s+"EXTENDED_PRIMARY320_TO_HARDCAP400_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_LANDING_PROTOCOL_ID\s+"UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1"' -and
        $source -match '#define\s+NL_SWEEP_CREEP_RECOVERY_PROTOCOL_ID\s+"UNIVERSAL_FINE_SINGLE_REVERSAL_V1"') `
    'V5.9 protocol identity is missing or reuses another version''s semantics.'

Assert-True ($source -match '#define\s+NL_SWEEP_CREEP_V59_EXTENDED_TERMINAL_ALLOWANCE_RAW\s+80LL' -and
        $source -match '(?s)#define\s+NL_SWEEP_CREEP_V59_EXTENDED_HARD_CAP_RAW\s+\\\s*\(NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW\s+\\\s*\+\s*NL_SWEEP_CREEP_V59_EXTENDED_TERMINAL_ALLOWANCE_RAW\)' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V59_EXTENDED_MAX_ITERATIONS\s+101U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V59_MAX_TERMINAL_POINTS_PER_SWEEP\s+10U' -and
        $source -match '#define\s+NL_SWEEP_CREEP_V59_MAX_TERMINAL_TOTAL_RAW_PER_SWEEP\s+800LL' -and
        $source -match '#if NL_SWEEP_CREEP_V59_EXTENDED_HARD_CAP_RAW != 400LL' -and
        $source -match 'V5\.9 plan locks the EXTENDED hard cap at exactly 400 raw' -and
        $source -match 'V5\.9 EXTENDED iterations must exceed ceil\(400-raw hard cap/fine step\)' -and
        $source -match 'V5\.9 trace capacity must cover ordinary plus recovery iteration guards') `
    'V5.9 terminal constants (80/400/101/10/800 raw) or their compile-time asserts changed.'

Assert-True ($source -match '(?s)#if ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION\s*#define\s+NL_SWEEP_CREEP_V54_TRACE_CAPACITY\s+120U\s*#else\s*#define\s+NL_SWEEP_CREEP_V54_TRACE_CAPACITY\s+100U') `
    'V5.9 must widen the shared V5.4 trace buffer to 120 without changing the 100-entry baseline for other versions.'

Assert-True ($source -match '(?s)#if ENABLE_SWEEP_POINT_CREEP_V56_THREE_STAGE_LANDING\s*\\\s*\|\|\s*ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION\s*static int16_t SaturateI16') `
    'SaturateI16 must stay compiled in for V5.9-only builds (it is called from the terminal-entry-gap print path).'

Assert-True ($source -match '(?s)typedef struct\s*\{\s*int64_t primaryCapRaw;\s*\}\s*NlCreepTerminalConfig_t;' -and
        $source -match 'const NlCreepTerminalConfig_t \*terminal\)' -and
        $source -match 'bool terminalEligible;' -and
        $source -match 'bool terminalAttempted;' -and
        $source -match 'int64_t terminalEntryGapRaw;' -and
        $source -match 'uint32_t terminalEntryIteration;' -and
        $source -match 'uint32_t terminalIterations;' -and
        $source -match 'int64_t terminalCorrectionRaw;' -and
        $source -match 'bool terminalSucceeded;' -and
        $source -match 'bool terminalSuppressedBySweepGuard;') `
    'NlCreepTerminalConfig_t/NlCreepDiagnostics_t terminal fields are incomplete (must stay unconditionally declared).'

$profileStart = $source.IndexOf('static MA600_Result_t CreepToUnwrappedTargetProfiled(')
$profileEnd = $source.IndexOf('static MA600_Result_t CreepToUnwrappedTarget(', $profileStart)
$profile = if ($profileStart -ge 0 -and $profileEnd -gt $profileStart) {
    $source.Substring($profileStart, $profileEnd - $profileStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($profile) -and
        $profile -match 'diag->terminalEligible = \(terminal != NULL\)' -and
        $profile -match 'terminal != NULL && !recoveryPhase && !diag->terminalAttempted\s*\r?\n\s*&& diag->totalCorrectionRaw >= terminal->primaryCapRaw' -and
        $profile -match 'diag->terminalAttempted = true;' -and
        $profile -match 'diag->terminalEntryGapRaw = gap;' -and
        $profile -match 'diag->terminalEntryIteration = diag->iterations;' -and
        $profile -match 'diag->terminalAttempted && !recoveryPhase\)\s*\r?\n\s*\{\s*\r?\n\s*diag->terminalIterations\+\+;' -and
        $profile -match 'diag->terminalCorrectionRaw \+= stepMagnitude;' -and
        $profile -match 'diag->terminalSucceeded = diag->terminalAttempted\s*\r?\n\s*&& diag->result == NL_CREEP_OK;') `
    'V5.9 terminal latch/accumulation/success logic in CreepToUnwrappedTargetProfiled is incomplete or changed.'
Assert-True ($profile -notmatch 'diag->terminalSucceeded = diag->terminalAttempted\s*&&\s*\(diag->result == NL_CREEP_OK \|\| diag->result == NL_CREEP_OK_RECOVERED\)') `
    'V5.9 terminalSucceeded must require strictly NL_CREEP_OK, not OK_RECOVERED (a crossing/recovery during terminal is a failure per the locked plan).'

$captureStart = $source.IndexOf('static MA600_Result_t CaptureSweep(')
$captureEnd = $source.IndexOf('static void PrintShadowMadLog', $captureStart)
$capture = if ($captureStart -ge 0 -and $captureEnd -gt $captureStart) {
    $source.Substring($captureStart, $captureEnd - $captureStart)
} else { '' }
Assert-True (-not [string]::IsNullOrWhiteSpace($capture) -and
        $capture -match 'NlCreepTerminalConfig_t terminalConfig = \{' -and
        $capture -match '\.primaryCapRaw = NL_SWEEP_CREEP_EXTENDED_MAX_TOTAL_RAW,' -and
        $capture -match 'if \(creepBudgetClass == NL_SWEEP_CREEP_BUDGET_EXTENDED\)' -and
        $capture -match 'out->sweepPointCreepTerminalAttemptedCount\s*\r?\n\s*< NL_SWEEP_CREEP_V59_MAX_TERMINAL_POINTS_PER_SWEEP' -and
        $capture -match 'out->sweepPointCreepTerminalTotalCorrectionRaw\s*\r?\n\s*< NL_SWEEP_CREEP_V59_MAX_TERMINAL_TOTAL_RAW_PER_SWEEP' -and
        $capture -match 'creepMaxTotalRaw = NL_SWEEP_CREEP_V59_EXTENDED_HARD_CAP_RAW;' -and
        $capture -match 'creepMaxIterations = NL_SWEEP_CREEP_V59_EXTENDED_MAX_ITERATIONS;' -and
        $capture -match 'terminalSuppressedByGuard = true;' -and
        $capture -match 'pointCreepDiag\.terminalSuppressedBySweepGuard = terminalSuppressedByGuard;' -and
        $capture -notmatch '\bLogLine(?:Large)?\s*\(') `
    'V5.9 per-sweep terminal guard (10 points/800 raw, EXTENDED-only, prior-points-only) is missing or UART-unsilent during motion.'

Assert-True ($source -match 'uint32_t sweepPointCreepTerminalEligibleCount;' -and
        $source -match 'uint32_t sweepPointCreepTerminalAttemptedCount;' -and
        $source -match 'uint32_t sweepPointCreepTerminalSucceededCount;' -and
        $source -match 'uint32_t sweepPointCreepTerminalFailedCount;' -and
        $source -match 'uint32_t sweepPointCreepTerminalSuppressedCount;' -and
        $source -match 'uint32_t sweepPointCreepTerminalTotalIterations;' -and
        $source -match 'int64_t\s+sweepPointCreepTerminalTotalCorrectionRaw;' -and
        $source -match 'bool\s+sweepPointCreepTerminalSweepGuardExceeded;' -and
        $source -match 'int16_t\s+creepTerminalEntryGapRaw\[NL_MAX_SWEEP_POINTS\];' -and
        $source -match 'uint16_t\s+creepTerminalCorrectionRaw\[NL_MAX_SWEEP_POINTS\];' -and
        $source -match 'uint8_t\s+creepTerminalEntryIteration\[NL_MAX_SWEEP_POINTS\];' -and
        $source -match 'uint8_t\s+creepTerminalIterations\[NL_MAX_SWEEP_POINTS\];' -and
        $source -match 'uint8_t\s+creepTerminalFlags\[NL_MAX_SWEEP_POINTS\];' -and
        $capture -match 'out->sweepPointCreepTerminalSuppressedCount\+\+;' -and
        $capture -match 'out->sweepPointCreepTerminalSweepGuardExceeded = true;' -and
        $capture -match 'out->sweepPointCreepTerminalEligibleCount\+\+;' -and
        $capture -match 'out->sweepPointCreepTerminalAttemptedCount\+\+;' -and
        $capture -match 'out->sweepPointCreepTerminalSucceededCount\+\+;' -and
        $capture -match 'out->sweepPointCreepTerminalFailedCount\+\+;') `
    'V5.9 sweep-level aggregate/shadow-storage fields or their bookkeeping are incomplete.'

Assert-True ($source -match 'SWEEP_CREEP_CONFIG,SchemaVersion=10' -and
        $source -match 'ExtendedPrimaryBudgetRaw=%ld,ExtendedHardBudgetRaw=%ld' -and
        $source -match 'ExtendedTerminalAllowanceRaw=%ld,ExtendedMaxIterations=%lu' -and
        $source -match 'TerminalCorrectionProtocol=%s,TerminalMaxPointsPerSweep=%u' -and
        $source -match 'TerminalMaxTotalRawPerSweep=%ld' -and
        $source -match 'SWEEP_CREEP_POINT,SchemaVersion=10' -and
        $source -match 'TerminalEligible=%d,TerminalAttempted=%d,TerminalEntryGapRaw=%s' -and
        $source -match 'TerminalCorrectionRaw=%s,TerminalObservedTowardTargetRaw=%s' -and
        $source -match 'TerminalResponseEfficiencyPermille=%s,TerminalSucceeded=%d' -and
        $source -match 'TerminalSuppressedBySweepGuard=%d' -and
        $source -match 'SweepPointTerminalEligible=%lu,SweepPointTerminalAttempted=%lu' -and
        $source -match 'SweepPointTerminalSucceeded=%lu,SweepPointTerminalFailed=%lu' -and
        $source -match 'SweepPointTerminalSuppressed=%lu,SweepPointTerminalTotalIterations=%lu' -and
        $source -match 'SweepPointTerminalSweepGuardExceeded=%d') `
    'V5.9 schema-10 CONFIG/POINT telemetry or END aggregate telemetry is incomplete.'

Assert-True ($source -match '(?s)int64_t terminalObservedTowardTargetRaw =\s*\(int64_t\)AbsI64ToU64\(terminalEntryGapRaw\)\s*- \(int64_t\)AbsI64ToU64\(c->shadowPoints->creepFinalGapRaw\[i\]\);' -and
        $source -notmatch 'AbsI64ToU64\(terminalEntryGapRaw\)\s*-\s*AbsI64ToU64\(c->shadowPoints->creepFinalGapRaw\[i\]\)\)') `
    'TerminalObservedTowardTargetRaw must be a SIGNED subtraction (cast each operand to int64_t before subtracting) so a point that regresses under terminal correction shows negative, not an unsigned wraparound.'

Assert-True ($source -match 'char terminalEfficiencyBuf\[16\] = "NA";' -and
        $source -match 'if \(terminalAttempted && terminalCorrectionRaw > 0\)') `
    'TerminalResponseEfficiencyPermille must default to "NA" (not 0) and only compute when terminal was actually attempted with positive correction raw.'

$parser = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/parse_sweep_creep_log.m') -Raw
$analyzer = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/nl/analyze_sweep_creep_batch.m') -Raw
$matlabTest = Get-Content -LiteralPath (Join-Path $root 'analysis/matlab/tests/test_nl_stability_analysis.m') -Raw
Assert-True ($parser -match 'ExtendedPrimaryBudgetRaw' -and
        $parser -match 'TerminalCorrectionProtocol' -and
        $parser -match 'TerminalEntryGapRaw' -and
        $parser -match 'TerminalObservedTowardTargetRaw' -and
        $parser -match 'TerminalResponseEfficiencyPermille' -and
        $parser -match 'TerminalSuppressedBySweepGuard' -and
        $parser -match 'SweepPointTerminalEligible' -and
        $parser -match 'SweepPointTerminalSweepGuardExceeded' -and
        $analyzer -match 'function byLabel = build_terminal_by_label' -and
        $analyzer -match 'TerminalByLabel' -and
        $analyzer -match 'Primary320OnlySuccessRatePct' -and
        $analyzer -match 'Terminal400SuccessRatePct' -and
        $matlabTest -match 'test_sweep_point_creep_v5_9_terminal' -and
        $matlabTest -match 'SWEEP_CREEP_CONFIG,SchemaVersion=10' -and
        $matlabTest -match 'TerminalResponseEfficiencyPermille == -187' -and
        $matlabTest -match 'worsened\.TerminalObservedTowardTargetRaw == -15') `
    'MATLAB V5.9 parser/analyzer/synthetic coverage is incomplete.'

Write-Host '[ OK ] Sweep-point creep V5.9 EXTENDED terminal correction contract tests passed.'
