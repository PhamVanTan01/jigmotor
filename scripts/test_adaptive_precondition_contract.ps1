$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

# --- Default-off, independent of the fixed precondition constants. ---
Assert-True ($source -match '#ifndef\s+ENABLE_ADAPTIVE_PRECONDITION\s*[\r\n]+#define\s+ENABLE_ADAPTIVE_PRECONDITION\s+0') `
    'ENABLE_ADAPTIVE_PRECONDITION must default to 0.'
Assert-True ($source -match '#define\s+NL_PRECONDITION_STABILITY_THRESHOLD_DEG\s+0\.03f') `
    'NL_PRECONDITION_STABILITY_THRESHOLD_DEG must be the pilot first estimate (0.03 deg).'
Assert-True ($source -match '#define\s+NL_PRECONDITION_MAX_COUNT\s+5U') `
    'NL_PRECONDITION_MAX_COUNT safety cap must be 5.'
Assert-True ($source -match '#define\s+NL_PRECONDITION_PROTOCOL_ID_ADAPTIVE\s+"ADAPTIVE_2CONSECUTIVE_STABLE_V1"') `
    'NL_PRECONDITION_PROTOCOL_ID_ADAPTIVE must be declared.'

# --- The fixed single-precondition protocol constants (from the earlier
# ten-official-run contract) must remain byte-identical -- this feature is
# strictly additive on top of them. ---
Assert-True ($source -match '#define\s+NL_PRECONDITION_COUNT\s+1U' -and
        $source -match 'NL_BATCH_TOTAL_CYCLE_COUNT\s+\(NL_PRECONDITION_COUNT\s*\+\s*NL_OFFICIAL_RUN_COUNT\)' -and
        $source -match '#define\s+NL_PRECONDITION_PROTOCOL_ID\s+"ONE_FULL_SWEEP_120S_V1"') `
    'The fixed one-precondition protocol constants must not be altered by this feature.'

# --- Protocol ID resolves through one macro (same pattern as
# NL_B0B_APPROACH_ACTIVE_DELAY_MS): adaptive string when flagged, the
# original fixed-protocol string otherwise -- byte-identical output when
# the flag is off. ---
Assert-True ($source -match '#define\s+NL_PRECONDITION_PROTOCOL_ID_ACTIVE\s+NL_PRECONDITION_PROTOCOL_ID_ADAPTIVE' -and
        $source -match '#define\s+NL_PRECONDITION_PROTOCOL_ID_ACTIVE\s+NL_PRECONDITION_PROTOCOL_ID(?!_ADAPTIVE)') `
    'NL_PRECONDITION_PROTOCOL_ID_ACTIVE must resolve to the adaptive protocol ID when flagged, the original one otherwise.'
Assert-True ($source -match 'PreconditionProtocol=%s,PreconditionCount=%lu,[\s\S]{0,200}NL_PRECONDITION_PROTOCOL_ID_ACTIVE,') `
    'The BATCH START log line must print the resolved (not the bare fixed) protocol ID.'

# --- preconditionRun / officialRunOrder: the fixed-mode expressions from
# the ten-official-run contract must remain textually present (that older
# test asserts them independently and this flag must not disturb them),
# with a parallel adaptive expression selected by the same flag. ---
Assert-True ($source -match '(?s)bool\s+preconditionRun\s*=\s*!nlPreconditionStabilityAchieved;[\s\S]*?#else[\s\S]*?bool\s+preconditionRun\s*=\s*\(nlCurrentCycle\s*<=\s*NL_PRECONDITION_COUNT\);') `
    'preconditionRun must resolve to the adaptive stability flag when on, the fixed cycle-count comparison otherwise.'
Assert-True ($source -match 'officialRunOrder\s*=\s*preconditionRun\s*\?\s*0U[\s\S]*?nlCurrentCycle\s*-\s*NL_PRECONDITION_COUNT') `
    'The fixed-mode officialRunOrder expression (required by the ten-official-run contract) must remain present.'
Assert-True ($source -match 'officialRunOrder\s*=\s*preconditionRun\s*\?\s*0U[\s\S]*?nlCurrentCycle\s*-\s*nlPreconditionRunsSoFar') `
    'The adaptive-mode officialRunOrder expression must use the runtime precondition-run counter, not a fixed constant.'

# --- nlPreconditionRunsSoFar increments unconditionally (both modes),
# ahead of any flag-gated branch -- so BATCH logs stay accurate/meaningful
# even with the flag off (always ends at exactly 1). ---
Assert-True ($source -match '(?s)if\s*\(preconditionRun\)\s*\{\s*nlPreconditionRunsSoFar\+\+;') `
    'nlPreconditionRunsSoFar must increment unconditionally as the first statement once a precondition run completes.'

# --- Stability comparison must use shadowCanonicalValid (metric-computed
# gate) rather than shadowClosureValid (0.20 deg pass/fail threshold,
# a different and irrelevant check here), and must require at least one
# prior precondition closure value before calling anything "stable" --
# i.e. real two-consecutive-sweep agreement, not a single-sample fluke. ---
Assert-True ($source -match 'bool\s+thisClosureUsable\s*=\s*nlCaptures\[0\]\.shadowCanonicalValid;') `
    'The adaptive stability check must gate on shadowCanonicalValid (metric computed), not shadowClosureValid (0.20 deg threshold).'
Assert-True ($source -match '(?s)if\s*\(thisClosureUsable\s*&&\s*nlHasLastPreconditionClosure\)\s*\{[\s\S]*?stableNow\s*=\s*\(fabsf\(nlPreconditionDeltaDeg\)\s*[\r\n\s]*<=\s*NL_PRECONDITION_STABILITY_THRESHOLD_DEG\);') `
    'Stability must require both a usable closure value AND a prior precondition closure to compare against (true two-consecutive-run agreement).'

# --- Safety cap: an unstable precondition must abort the batch loudly
# (PRECONDITION_UNSTABLE + safe-stop), never spin forever, and never
# silently fall through into official runs on an unproven precondition. ---
Assert-True ($source -match 'else\s+if\s*\(nlPreconditionRunsSoFar\s*>=\s*NL_PRECONDITION_MAX_COUNT\)') `
    'An unstable precondition must be checked against the NL_PRECONDITION_MAX_COUNT safety cap.'
Assert-True ($source -match '(?s)nlPreconditionRunsSoFar\s*>=\s*NL_PRECONDITION_MAX_COUNT\)\s*\{[\s\S]*?Status=PRECONDITION_UNSTABLE[\s\S]*?SetEngineState\(NL_ENGINE_SAFE_STOP\)[\s\S]{0,400}return;') `
    'Exceeding the safety cap without stability must log Status=PRECONDITION_UNSTABLE, force a safe-stop, and abort the batch (return).'
Assert-True ($source -match 'if\s*\(stableNow\)\s*\{\s*nlPreconditionStabilityAchieved\s*=\s*true;\s*nlPreconditionValid\s*=\s*true;\s*\}') `
    'Reaching stability must set both nlPreconditionStabilityAchieved and nlPreconditionValid.'

# --- Batch-complete condition: fixed-mode expression must remain
# byte-identical (still the sole condition when the flag is off); the
# adaptive expression must generalize it using the runtime precondition
# count rather than assuming a fixed total. ---
Assert-True ($source -match '(?s)bool\s+batchOfficialRunsComplete\s*=\s*\(nlCurrentCycle\s*>=\s*NL_BATCH_TOTAL_CYCLE_COUNT\);') `
    'The fixed-mode batch-complete condition must remain nlCurrentCycle >= NL_BATCH_TOTAL_CYCLE_COUNT, unchanged.'
Assert-True ($source -match '(?s)bool\s+batchOfficialRunsComplete\s*=\s*\(!preconditionRun\)[\s\S]*?nlCurrentCycle\s*-\s*nlPreconditionRunsSoFar\)\s*>=\s*NL_OFFICIAL_RUN_COUNT\);') `
    'The adaptive-mode batch-complete condition must compare official runs completed (via the runtime precondition count) against NL_OFFICIAL_RUN_COUNT.'

# --- COMPLETE log line: existing fields/values must stay exactly as
# before (byte-identical when the flag is off); two new fields append at
# the end using runtime state, never replacing the old ones. ---
Assert-True ($source -match '(?s)"BATCH,BatchID=%lu,Status=COMPLETE,PreconditionCount=%lu,"\s*[\r\n]+\s*"RunCount=%lu,TotalCycleCount=%lu,PreconditionValid=1,"\s*[\r\n]+\s*"PreconditionRunsUsed=%lu,PreconditionStabilityDeltaDeg=%s\\r\\n",\s*[\r\n\s]*\(unsigned long\)nlBatchId,\s*\(unsigned long\)NL_PRECONDITION_COUNT,\s*[\r\n\s]*\(unsigned long\)NL_OFFICIAL_RUN_COUNT,\s*[\r\n\s]*\(unsigned long\)NL_BATCH_TOTAL_CYCLE_COUNT,') `
    'The BATCH COMPLETE line must keep its original fields/args unchanged and append PreconditionRunsUsed/PreconditionStabilityDeltaDeg using runtime values.'

# --- OnButtonPress must reset the new state at every batch start so a
# second batch never inherits stability/delta state from a previous one. ---
Assert-True ($source -match '(?s)nlBatchId\s*=\s*\+\+nlBatchIdCounter;[\s\S]*?nlPreconditionRunsSoFar\s*=\s*0;[\s\S]*?nlHasPreconditionDeltaDeg\s*=\s*false;') `
    'A new batch must reset nlPreconditionRunsSoFar and nlHasPreconditionDeltaDeg.'
Assert-True ($source -match '(?s)nlPreconditionRunsSoFar\s*=\s*0;[\s\S]*?#if\s+ENABLE_ADAPTIVE_PRECONDITION[\s\S]*?nlPreconditionStabilityAchieved\s*=\s*false;[\s\S]*?nlHasLastPreconditionClosure\s*=\s*false;[\s\S]*?#endif') `
    'A new batch must reset nlPreconditionStabilityAchieved and nlHasLastPreconditionClosure under the adaptive flag.'

# --- State declarations: unconditional counters (so log lines never need
# to branch), adaptive-only comparison state gated behind the flag. ---
Assert-True ($source -match 'static\s+uint32_t\s+nlPreconditionRunsSoFar;' -and
        $source -match 'static\s+bool\s+nlHasPreconditionDeltaDeg;' -and
        $source -match 'static\s+float\s+nlPreconditionDeltaDeg;') `
    'nlPreconditionRunsSoFar/nlHasPreconditionDeltaDeg/nlPreconditionDeltaDeg must be declared unconditionally.'
Assert-True ($source -match '(?s)#if\s+ENABLE_ADAPTIVE_PRECONDITION\s*[\r\n]+static\s+bool\s+nlPreconditionStabilityAchieved;\s*[\r\n]+static\s+bool\s+nlHasLastPreconditionClosure;\s*[\r\n]+static\s+float\s+nlLastPreconditionClosureDeg;\s*[\r\n]+#endif') `
    'nlPreconditionStabilityAchieved/nlHasLastPreconditionClosure/nlLastPreconditionClosureDeg must be declared only under the adaptive flag.'

# --- No leakage into the official contract / no change to the schema. ---
Assert-True ($source -match 'eligibleForStatistics\s*=\s*!preconditionRun') `
    'Precondition eligibility semantics must be unchanged.'
Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5') `
    'This feature must not change the official schema-v5 contract.'

# --- BATCH,... lines (where the new fields live) are console-only
# diagnostics, never parsed by the analyzer -- confirms the new fields
# carry zero risk to the analyzer/CSV pipeline. If this ever stops being
# true, the assumption behind keeping these fields BATCH-line-only (rather
# than fighting for scarce META/APPROACH_RESULT buffer headroom) must be
# re-checked. ---
$analyzerSource = Get-Content -Raw (Join-Path $root 'scripts\analyze_nonlinear_logs.ps1')
Assert-True ($analyzerSource -notmatch "'BATCH,") `
    'analyze_nonlinear_logs.ps1 must not parse BATCH lines -- if it now does, the new PreconditionRunsUsed/PreconditionStabilityDeltaDeg fields need a schema review.'

Write-Host '[ OK ] Adaptive precondition (Part 1) contract tests passed.'
