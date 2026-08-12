$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$source = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')

# --- Default-off, independent of B0-B's own on/off flag. ---
Assert-True ($source -match '#ifndef\s+ENABLE_B0B_APPROACH_SOFT_START\s*[\r\n]+#define\s+ENABLE_B0B_APPROACH_SOFT_START\s+0') `
    'ENABLE_B0B_APPROACH_SOFT_START must default to 0.'
Assert-True ($source -match '#define\s+NL_B0B_APPROACH_SOFT_START_DELAY_MS\s+4U') `
    'NL_B0B_APPROACH_SOFT_START_DELAY_MS must be the Phase-A-derived first estimate (4).'
Assert-True ($source -match '#define\s+NL_B0B_APPROACH_SOFT_START_PROTOCOL_ID\s+"SOFT_START_V1"' -and
        $source -match '#define\s+NL_B0B_APPROACH_SOFT_START_PROTOCOL_ID\s+"NONE"') `
    'Both protocol IDs (SOFT_START_V1 when flagged / NONE default) must exist.'
Assert-True ($source -match '#define\s+NL_B0B_APPROACH_ACTIVE_DELAY_MS\s+NL_B0B_APPROACH_SOFT_START_DELAY_MS' -and
        $source -match '#define\s+NL_B0B_APPROACH_ACTIVE_DELAY_MS\s+NL_RAMP_STEP_DELAY_MS') `
    'NL_B0B_APPROACH_ACTIVE_DELAY_MS must resolve to the soft-start delay when flagged, NL_RAMP_STEP_DELAY_MS otherwise.'

# --- Both approach legs must use the resolved constant, not a bare literal
# -- one flag flips both legs identically (single variable). ---
Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*backoffCommand,\s*&backoffStepsExecuted,\s*out->approachBackoffStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_B0B_APPROACH_ACTIVE_DELAY_MS,\s*&out->motionDiagnostics\)') `
    'The backoff leg must pass NL_B0B_APPROACH_ACTIVE_DELAY_MS, not a bare NL_RAMP_STEP_DELAY_MS literal.'
Assert-True ($source -match '(?s)RampCommandToTarget\(&sweepAcquisition,\s*&commandPos,\s*0,\s*&forwardStepsExecuted,\s*out->approachForwardStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_B0B_APPROACH_ACTIVE_DELAY_MS,\s*&out->motionDiagnostics\)') `
    'The forward leg must pass NL_B0B_APPROACH_ACTIVE_DELAY_MS, not a bare NL_RAMP_STEP_DELAY_MS literal.'
Assert-True ($source -notmatch 'out->approachBackoffStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_RAMP_STEP_DELAY_MS' -and
        $source -notmatch 'out->approachForwardStepUnwrapped,\s*NL_B0B_APPROACH_DIAG_STEPS,\s*[\r\n\s]*NL_RAMP_STEP_DELAY_MS') `
    'Neither approach leg may still hard-code NL_RAMP_STEP_DELAY_MS directly.'

# --- APPROACH_RESULT: new field present, delay arg resolved through the
# same constant, no separate per-leg value (one shared variable this round). ---
Assert-True ($source -match '"ApproachBackoffRaw=%ld,ApproachRampStepRaw=%d,ApproachRampDelayMs=%d,"\s*[\r\n]+\s*"B0BSoftStartProtocol=%s,"') `
    'APPROACH_RESULT must carry B0BSoftStartProtocol immediately after ApproachRampDelayMs.'
Assert-True ($source -match '(?s)\(long\)NL_B0B_APPROACH_BACKOFF_RAW,\s*\(int\)NL_RAMP_STEP,\s*[\r\n\s]*\(int\)NL_B0B_APPROACH_ACTIVE_DELAY_MS,\s*[\r\n\s]*NL_B0B_APPROACH_SOFT_START_PROTOCOL_ID,') `
    'The APPROACH_RESULT argument list must supply the resolved delay and the soft-start protocol ID in that order.'

# --- No new META field: META had only ~39 bytes of headroom left (measured
# against a real log at design time) against LogLineLarge's 2600-byte
# buffer -- this experiment must stay entirely inside APPROACH_RESULT,
# which had over 1100 bytes free. ---
Assert-True ($source -notmatch 'B0BSoftStart\w*.*META,SchemaVersion' -and
        $source -notmatch 'META,SchemaVersion.*?B0BSoftStart') `
    'B0-B soft-start must not add a new META field (insufficient buffer headroom); use APPROACH_RESULT instead.'

# --- APPROACH_RESULT line budget: longest real APPROACH_RESULT line plus
# the new field must stay comfortably under the 2600-byte LogLineLarge
# buffer. Measured against real logs, not assumed. ---
Assert-True ($source -match 'char\s+buf\[2600\]') `
    'Could not confirm the LogLineLarge 2600-byte buffer (source layout changed?).'
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
$newFieldCost = (',B0BSoftStartProtocol=SOFT_START_V1').Length
Assert-True (($maxApproachResultLen + $newFieldCost) -lt 2600) `
    ("APPROACH_RESULT line budget exceeded: longest observed " + $maxApproachResultLen +
     ' + new field ' + $newFieldCost + ' must stay < 2600.')

# --- No leakage into the official contract. ---
Assert-True ($source -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
    'The soft-start experiment must not touch the official measurement-valid gate.'
Assert-True ($source -match '#define\s+NL_LOG_SCHEMA_VERSION\s+5' -and
        $source -match 'OfficialResultSource=LEGACY') `
    'The soft-start experiment must not change the official schema-v5/legacy result contract.'
Assert-True ($source -notmatch 'NL_B0B_APPROACH_BACKOFF_RAW\s+\d' -or
        $source -match '#define\s+NL_B0B_APPROACH_BACKOFF_RAW\s+NL_GRID_STEP_RAW_MIN') `
    'This change must not alter the 182-raw backoff/forward distance -- only cadence.'
Assert-True ($source -notmatch 'MotorPwm_SetElectricalPos\([^;]*power\s*[<>!=]') `
    'This change must not touch B0-B power (must remain full power, unchanged).'

Write-Host '[ OK ] B0-B approach soft-start experiment contract tests passed.'
