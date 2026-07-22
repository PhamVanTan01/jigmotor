$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$nl = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$motor = Get-Content -Raw (Join-Path $root 'Core\Src\motor.c')
$motorHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\motor.h')
$controller = Get-Content -Raw (Join-Path $root 'Core\Src\position_controller.c')
$controllerHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\position_controller.h')

# Frozen measurement definition: the motion path may change, never the
# official grid, sample count, target rounding, or analysis window.
Assert-True ($nl -match '#define\s+NL_POINTS_PER_REV\s+360U' -and
        $nl -match '#define\s+NL_GRID_STEP_DEG\s+1\.0f' -and
        $nl -match '#define\s+NL_SAMPLES_PER_POINT\s+64' -and
        $nl -match 'ROUND_INDEX_TIMES_65536_DIV_360' -and
        $nl -match 'Points 0\.\.359 are the 360 uniformly spaced samples') `
    'Motion V2 changed the frozen one-degree/64-sample measurement contract.'
Assert-True ($nl -match 'out->measurementValid\s*=\s*structuralValid\s*&&\s*out->trackingValid') `
    'Motion diagnostics must not enter the official validity equation.'

# Selected trajectory and exact-target behavior.
Assert-True ($nl -match '#define\s+NL_MOTION_PROFILE\s+NL_MOTION_PROFILE_SCURVE_V2' -and
        $nl -match '#define\s+NL_SCURVE_SEGMENT_TICKS\s+40U' -and
        $nl -match 'SCURVE40_ABSOLUTE_TICK_V2') `
    'The default S-curve profile is incomplete.'
$rampFn = [regex]::Match($nl, '(?s)static MA600_Result_t RampCommandToTarget\(.*?\n\}').Value
Assert-True ($rampFn -match 'NlSmoothstepCommandRaw' -and
        $rampFn -match '\*pos\s*=\s*targetPos;\s*/\* exact measurement target' -and
        $rampFn -match 'osDelayUntil\(deadline\)' -and
        $rampFn -match 'timingOverrunCount\+\+' -and
        $rampFn -match 'observedBacktrackCount\+\+') `
    'RampCommandToTarget is missing exact-target, absolute-cadence, or motion diagnostics.'

# Host-side check of the chosen quintic profile for both 182/183 raw steps.
foreach ($delta in @(182, 183, -182, -183)) {
    $previous = 0
    for ($i = 1; $i -le 40; $i++) {
        $u = [double]$i / 40.0
        $blend = [math]::Pow($u, 3) * (10.0 + $u * (-15.0 + 6.0 * $u))
        $command = [int][math]::Round($delta * $blend, 0, [MidpointRounding]::AwayFromZero)
        if ($delta -gt 0) {
            Assert-True ($command -ge $previous -and $command -le $delta) `
                "Positive S-curve is non-monotonic/overshooting at delta=$delta i=$i."
        } else {
            Assert-True ($command -le $previous -and $command -ge $delta) `
                "Negative S-curve is non-monotonic/overshooting at delta=$delta i=$i."
        }
        $previous = $command
    }
    Assert-True ($previous -eq $delta) "S-curve did not close exactly at delta=$delta."
}

# Start alignment: one smooth phase alignment, then equal CW local approach.
# docs/b0b-v3-no-reversal-plan.md muc 6.2: ENABLE_B0B_EQUAL_APPROACH is now
# derived from NL_APPROACH_MODE (true for every mode except LOCK_ONLY=0),
# which itself defaults to NL_APPROACH_MODE_REVERSAL_V2=1 -- same compiled
# default behavior as the old literal "#define ENABLE_B0B_EQUAL_APPROACH 1".
Assert-True ($nl -match '#ifndef\s+NL_APPROACH_MODE\s*[\r\n]+#define\s+NL_APPROACH_MODE\s+NL_APPROACH_MODE_REVERSAL_V2' -and
        $nl -match '#define\s+ENABLE_B0B_EQUAL_APPROACH\s+\(NL_APPROACH_MODE\s*!=\s*NL_APPROACH_MODE_LOCK_ONLY\)' -and
        $nl -match 'SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2') `
    'Same-direction point-0 approach is not the Motion-V2 default.'
$lockFn = [regex]::Match($nl, '(?s)static void LockStartPosition\(void\).*?\n\}').Value
Assert-True ($lockFn -match '#if NL_MOTION_PROFILE == NL_MOTION_PROFILE_SCURVE_V2' -and
        $lockFn -match 'NlSmoothstepCommandRaw' -and
        $lockFn -match 'Motor_SetElectricalPos\(0U, 1\.0f\)' -and
        $lockFn -match '#else') `
    'LockStartPosition does not preserve the V2/legacy selectable paths.'

# Home controller: periodic angle, clamped integral, filtered derivative,
# output slew, and complete reset-state coverage.
Assert-True ($motor -match 'WRAPPED_PID_SLEW_V2' -and
        $motor -match 'while \(error > 180\.0f\) error -= 360\.0f' -and
        $motor -match 'while \(error < -180\.0f\) error \+= 360\.0f' -and
        $motor -match '\.derivativeAlpha\s*=\s*0\.25f' -and
        $motor -match '\.outputSlewLimit\s*=\s*8\.0f') `
    'Wrapped/slew-limited home profile is incomplete.'
Assert-True ($controller -match 'controller->integral\s*=\s*controller->config\.integralLimit' -and
        $controller -match 'controller->filteredDerivative\s*\+=' -and
        $controller -match 'outputDelta\s*=\s*output\s*-\s*controller->lastOutput') `
    'Controller anti-windup, derivative filter, or output slew is missing.'
Assert-True ($controller -match 'integralCommand1' -and
        $controller -match 'derivativeCommand1' -and
        $controller -match 'slewCommand1' -and
        $controller -match 'resetStateValid') `
    'Firmware self-test does not exercise all new persistent controller behaviors.'
Assert-True ($controllerHeader -match 'filteredDerivative' -and
        $controllerHeader -match 'lastOutput' -and
        $motorHeader -match 'filteredDerivativeTerm' -and
        $motorHeader -match 'lastOutputStepRaw' -and
        $nl -match 'state->filteredDerivativeTerm\s*==\s*0\.0f' -and
        $nl -match 'state->lastOutputStepRaw\s*==\s*0\.0f') `
    'New persistent controller state is not included in the run-boundary reset gate.'

# Audit records and the GRID truncation fix.
Assert-True ($nl -match 'MOTION_PROFILE,SchemaVersion=' -and
        $nl -match 'FinalTargetMode=OPEN_LOOP_UNCHANGED' -and
        $nl -match 'RampTimingOverruns=%lu' -and
        $nl -match 'ObservedBacktracks=%lu') `
    'Motion profile/health telemetry is incomplete.'
Assert-True ($nl -match '(?s)LogLineLarge\(\s*"GRID,SchemaVersion=') `
    'GRID still uses the 128-byte LogLine buffer and will be truncated.'

Write-Host '[ OK ] Motion Control V2 contract tests passed.'
