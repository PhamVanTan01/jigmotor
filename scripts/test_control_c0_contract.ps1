$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$mode = Get-Content -Raw (Join-Path $root 'Core\Inc\app_mode.h')
$header = Get-Content -Raw (Join-Path $root 'Core\Inc\motor.h')
$motor = Get-Content -Raw (Join-Path $root 'Core\Src\motor.c')
$control = Get-Content -Raw (Join-Path $root 'Core\Src\control_engine.c')
$app = Get-Content -Raw (Join-Path $root 'Core\Src\app_engine.c')

Assert-True ($mode -match 'CONTROL_C0_OPEN_LOOP_1DEG_V1') `
    'Control C0 profile identity is missing.'
Assert-True ($app -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $app -match 'ControlEngine_RequestStart') `
    'Control image does not select the dedicated engine at compile time.'

# The first hardware image is intentionally unable to command more than one
# degree. Promotion to 5/10 degrees requires a new profile and contract edit.
Assert-True ($control -match '#define\s+CONTROL_C0_TARGET_DEG\s+1U' -and
    $control -match '#if CONTROL_C0_TARGET_DEG != 1U' -and
    $control -match 'CONTROL_C0_COMMANDS_PER_DEG\s+40U' -and
    $control -match 'CONTROL_C0_HOLD_TICKS\s+250U') `
    'C0 one-degree/40-command/hold profile is not compile-time locked.'

# Host-side proof that the exact C0 quintic profile is monotonic and closes on
# the rounded one-degree target (182 raw) at command 40.
$previous = 0
for ($i = 0; $i -le 40; $i++) {
    if ($i -ge 40) {
        $command = 182
    } else {
        $u = [double]$i / 40.0
        $blend = [math]::Pow($u, 3) * (10.0 + $u * (-15.0 + 6.0 * $u))
        $command = [int][math]::Round(182.0 * $blend, 0,
            [MidpointRounding]::AwayFromZero)
    }
    Assert-True ($command -ge $previous -and $command -le 182) `
        "C0 S-curve is non-monotonic or overshoots at command $i."
    $previous = $command
}
Assert-True ($previous -eq 182) 'C0 S-curve does not close at exactly 182 raw.'
Assert-True ($control -match '#define\s+CONTROL_C0_POWER\s+0\.35f' -and
    $control -match '#define\s+CONTROL_C0_MAX_TRAVEL_RAW\s+546' -and
    $control -match '#define\s+CONTROL_C0_MAX_ACTIVE_MS\s+6000U' -and
    $control -match 'CONTROL_C0_MAX_CONSECUTIVE_MISSES\s+3U') `
    'C0 power/travel/duration/deadline safety limits changed.'

Assert-True ($header -match 'Motor_MoveToAngleWithPower' -and
    $motor -match 'Motor_MoveToAngleWithPower\(targetDeg, 1\.0f, outErrorDeg\)' -and
    $motor -match 'MotorPwm_SetElectricalPos\([^;]+, power\)' -and
    $motor -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $motor -match '#else[\s\S]*?MotorPwm_SetElectricalPos\([^;]+, 1\.0f\)') `
    'Bounded-power home API is missing or legacy Measurement home changed.'
Assert-True ($control -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $control -match '#endif /\* JIG_APP_MODE == JIG_APP_CONTROL \*/') `
    'Control engine is still compiled into the Measurement policy.'

$homeFn = [regex]::Match($control,
    '(?s)static ControlC0Result_t ControlHome\(.*?\n\}').Value
$observe = [regex]::Match($control,
    '(?s)static ControlC0Result_t ControlObserveOneDegree\(.*?\n\}').Value
$run = [regex]::Match($control,
    '(?s)static void ControlRunC0\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($homeFn) -and
    -not [string]::IsNullOrWhiteSpace($observe) -and
    -not [string]::IsNullOrWhiteSpace($run)) `
    'Could not locate the bounded C0 workflow.'
Assert-True ($homeFn -match 'Motor_MoveToAngleWithPower' -and
    $homeFn -match 'Motor_Enable\(\)' -and
    $homeFn -match 'CONTROL_C0_HOME_TIMEOUT_MS' -and
    $homeFn -match 'controlAbortRequested') `
    'Home stage is missing bounded power, timeout, or operator abort.'
Assert-True ($observe -match 'SmoothstepRaw' -and
    $observe -match 'osDelayUntil\(deadline\)' -and
    $observe -match 'MA600_AcquireSample' -and
    $observe -match 'CONTROL_C0_TRAVEL_LIMIT' -and
    $observe -match 'CONTROL_C0_DEADLINE_FAULT' -and
    $observe -match 'CONTROL_C0_DURATION_LIMIT' -and
    $observe -match 'deadline\s*=\s*now') `
    'Open-loop observation is missing trajectory, feedback, or fail-safe gates.'

# UART is forbidden between Motor_Enable and the common Motor_Disable exit.
Assert-True ($homeFn -notmatch 'ControlLog|HAL_UART_Transmit' -and
    $observe -notmatch 'ControlLog|HAL_UART_Transmit') `
    'C0 emits UART while the motor can be enabled.'
$disableIndex = $run.LastIndexOf('Motor_Disable()')
$reportIndex = $run.LastIndexOf('ControlReport(&report)')
Assert-True ($disableIndex -ge 0 -and $reportIndex -gt $disableIndex) `
    'C0 does not disable torque before dumping evidence.'

Assert-True ($control -match 'section\("\.ccmram_bss"\)' -and
    $control -match 'memset\(controlEvidence, 0, sizeof\(controlEvidence\)\)' -and
    $control -match 'CONTROL_C0_DATA' -and
    $control -match 'CorrectionRaw=0' -and
    $control -match 'VelocityRawPerSecond' -and
    $control -match 'AccelerationRawPerSecond2' -and
    $control -match 'SpiLatencyCycles' -and
    $control -match 'PwmCounterAtCs') `
    'C0 deferred plant evidence is incomplete.'
Assert-True ($control -match 'xPortGetMinimumEverFreeHeapSize' -and
    $control -match 'uxTaskGetStackHighWaterMark' -and
    $control -match 'controlAbortRequested\s*=\s*true') `
    'C0 resource telemetry or second-press abort is missing.'

Write-Host '[ OK ] Control C0 one-degree plant-observation contract passed.'
