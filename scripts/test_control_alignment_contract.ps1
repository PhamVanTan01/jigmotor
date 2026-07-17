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

Assert-True ($mode -match 'CONTROL_A2C_FIXED_PHASE_ALIGN_P06_H500_V1') `
    'Control A2C profile identity is missing.'
Assert-True ($app -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $app -match 'ControlEngine_RequestStart') `
    'Control image does not select the dedicated engine at compile time.'

Assert-True ($control -match 'CONTROL_A2_TARGET_POWER_PPM\s+60000U' -and
    $control -match 'CONTROL_A2_RAMP_TICKS\s+500U' -and
    $control -match 'CONTROL_A2_HOLD_TICKS\s+500U' -and
    $control -match 'CONTROL_A2_PERIOD_MS\s+1U' -and
    $control -match 'CONTROL_A2_MAX_TRAVEL_RAW\s+910' -and
    $control -match 'CONTROL_A2_MAX_SAMPLE_STEP_RAW\s+45' -and
    $control -match 'CONTROL_A2_MAX_ACTIVE_MS\s+1200U' -and
    $control -match 'CONTROL_A2_MAX_CONSECUTIVE_MISSES\s+3U') `
    'A2C power/timing/safety envelope changed without a profile revision.'

$previous = -1
for ($sequence = 0; $sequence -le 1000; $sequence++) {
    $powerPpm = if ($sequence -ge 500) {
        60000
    } else {
        [math]::Floor($sequence * 60000 / 500)
    }
    Assert-True ($powerPpm -ge $previous -and $powerPpm -le 60000) `
        "A2C power ramp is not monotonic at sequence $sequence."
    $previous = $powerPpm
}
Assert-True ($previous -eq 60000) 'A2C ramp does not close at exactly 6 percent.'

Assert-True ($header -match '#if JIG_APP_MODE == JIG_APP_CONTROL[\s\S]*?Motor_PrimeControlSession') `
    'Control-only prime API declaration is missing.'
$prime = [regex]::Match($motor,
    '(?s)bool\s+Motor_PrimeControlSession\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($prime) -and
    $prime -match 'outputState\.enabled' -and
    $prime -match 'initialPower\s*!=\s*0\.0f' -and
    $prime -match 'Motor_Disable\(\)' -and
    $prime -match 'Motor_ResetPositionController\(\)' -and
    $prime -match 'positionController\.commandedPosition' -and
    $prime -match 'MotorPwm_SetElectricalPos\([^;]+,\s*0\.0f\)' -and
    $prime -notmatch 'Motor_Enable\(\)') `
    'Prime API is not fail-closed, zero-power, or controller/PWM coherent.'

Assert-True ($control -notmatch 'ControlHome|ControlObserveOneDegree|SmoothstepRaw|Motor_MoveToAngle') `
    'Alignment-only image still contains HOME/PID or the one-degree trajectory.'
$align = [regex]::Match($control,
    '(?s)static ControlA2Result_t ControlRunAlignment\(.*?\n\}').Value
$run = [regex]::Match($control,
    '(?s)static void ControlRunA2\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($align) -and
    -not [string]::IsNullOrWhiteSpace($run)) `
    'Could not locate the A2 alignment-only workflow.'
Assert-True ($align -match 'Motor_Enable\(\)' -and
    $align -match 'outputState\.outputPower\s*==\s*0\.0f' -and
    $align -match 'ControlA2PowerPpm' -and
    $align -match 'Motor_SetElectricalPos' -and
    $align -match 'osDelayUntil\(deadline\)' -and
    $align -match 'deadline\s*=\s*now' -and
    $align -match 'CONTROL_A2_SAMPLE_STEP_LIMIT' -and
    $align -match 'CONTROL_A2_TRAVEL_LIMIT' -and
    $align -match 'CONTROL_A2_DEADLINE_FAULT' -and
    $align -match 'CONTROL_A2_DURATION_LIMIT') `
    'A2C alignment is missing zero-power enable, ramp, acquisition, or fail-safe gates.'
Assert-True ($align -notmatch 'ControlLog|HAL_UART_Transmit') `
    'A2C emits UART while the motor can be enabled.'

$resetIndex = $run.IndexOf('Motor_ResetControlSession()')
$baselineIndex = $run.IndexOf('MA600_AcquireSample')
$primeIndex = $run.IndexOf('Motor_PrimeControlSession')
$armedIndex = $run.IndexOf('ControlLog(')
$activeIndex = $run.IndexOf('ControlRunAlignment')
$disableIndex = $run.LastIndexOf('Motor_Disable()')
$clearIndex = $run.LastIndexOf('Motor_SetElectricalPos')
$reportIndex = $run.LastIndexOf('ControlReport(&report)')
Assert-True ($resetIndex -ge 0 -and $resetIndex -lt $baselineIndex -and
    $baselineIndex -lt $primeIndex -and $primeIndex -lt $armedIndex -and
    $armedIndex -lt $activeIndex -and $activeIndex -lt $disableIndex -and
    $disableIndex -lt $clearIndex -and $clearIndex -lt $reportIndex) `
    'A2C call order is not reset -> baseline -> prime -> armed -> active -> disable -> clear -> report.'

Assert-True ($control -match 'section\("\.ccmram_bss"\)' -and
    $control -match 'memset\(controlEvidence,\s*0,\s*sizeof\(controlEvidence\)\)' -and
    $control -match 'CONTROL_A2_DATA' -and
    $control -match 'EncoderRaw' -and
    $control -match 'TravelMilliDeg' -and
    $control -match 'PowerPpm' -and
    $control -match 'VelocityRawPerSecond' -and
    $control -match 'AccelerationRawPerSecond2' -and
    $control -match 'SpiLatencyCycles' -and
    $control -match 'PwmCounterAtCs' -and
    $control -match 'CorrectionRaw=0') `
    'A2C deferred alignment evidence is incomplete.'
Assert-True ($control -notmatch '%lld' -and
    $control -match 'AccelerationRawPerSecond2=%ld' -and
    $control -match 'acceleration64\s*>\s*INT32_MAX' -and
    $control -match 'acceleration64\s*<\s*INT32_MIN' -and
    $control -match 'AccelerationSaturations=%lu') `
    'A2C UART telemetry must avoid unsupported newlib-nano long-long printf and report saturation.'
Assert-True ($control -match 'xPortGetMinimumEverFreeHeapSize' -and
    $control -match 'uxTaskGetStackHighWaterMark' -and
    $control -match 'controlAbortRequested\s*=\s*true') `
    'A2C resource telemetry or second-press abort is missing.'

Write-Host '[ OK ] Control A2C fixed-phase power-envelope contract passed.'
