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

Assert-True ($mode -match 'CONTROL_A3_ROTATING_CAPTURE_P35_V1') `
    'Control A3 profile identity is missing.'
Assert-True ($app -match '#if JIG_APP_MODE == JIG_APP_CONTROL' -and
    $app -match 'ControlEngine_RequestStart') `
    'Control image does not select the dedicated engine at compile time.'

# --- Locked profile envelope: any change requires a new profile identity. ---
Assert-True ($control -match 'CONTROL_A3_TARGET_POWER_PPM\s+350000U' -and
    $control -match 'CONTROL_A3_POWER_RAMP_TICKS\s+300U' -and
    $control -match 'CONTROL_A3_SWEEP_TICKS\s+2400U' -and
    $control -match 'CONTROL_A3_HOLD_TICKS\s+500U' -and
    $control -match 'CONTROL_A3_PERIOD_MS\s+1U' -and
    $control -match 'CONTROL_A3_PHASE_SWEEP_SPAN_RAW\s+MOTOR_COUNT_PER_ELECTRICAL_CYCLE' -and
    $control -match 'CONTROL_A3_MAX_TRAVEL_RAW\s+12000' -and
    $control -match 'CONTROL_A3_MAX_SAMPLE_STEP_RAW\s+150' -and
    $control -match 'CONTROL_A3_MAX_ACTIVE_MS\s+4000U' -and
    $control -match 'CONTROL_A3_MAX_CONSECUTIVE_MISSES\s+3U' -and
    $control -match 'CONTROL_A3_EVIDENCE_DECIMATION\s+3U' -and
    $control -match 'CONTROL_A3_CAPTURE_WINDOW_TICKS\s+100U' -and
    $control -match 'CONTROL_A3_CAPTURE_MIN_FIELD_RAW\s+60' -and
    $control -match 'CONTROL_A3_DRAG_LOSS_LAG_RAW\s+2731') `
    'A3 power/timing/safety envelope changed without a profile revision.'
Assert-True ($control -match '#error "A3 pilot must remain locked to 35 percent power"' -and
    $control -match '#error "A3 pilot timing changed without a new profile identity"' -and
    $control -match '#error "A3 sweep span must remain exactly one electrical cycle"') `
    'A3 compile-time identity locks are missing.'

# --- Power ramp: monotonic, closes at exactly 35 percent. ---
$previous = -1
for ($sequence = 0; $sequence -le 3200; $sequence++) {
    $powerPpm = if ($sequence -ge 300) {
        350000
    } else {
        [math]::Floor($sequence * 350000 / 300)
    }
    Assert-True ($powerPpm -ge $previous -and $powerPpm -le 350000) `
        "A3 power ramp is not monotonic at sequence $sequence."
    $previous = $powerPpm
}
Assert-True ($previous -eq 350000) 'A3 ramp does not close at exactly 35 percent.'

# --- Phase trajectory: host-side re-derivation of the quintic sweep.
# Non-decreasing, starts at 0, ends at exactly one electrical cycle. ---
$span = 10923
$previousProgress = -1
for ($tick = 0; $tick -le 2400; $tick++) {
    if ($tick -eq 0) {
        $progress = 0
    } elseif ($tick -ge 2400) {
        $progress = $span
    } else {
        $u = $tick / 2400.0
        $blend = $u * $u * $u * (10.0 + $u * (-15.0 + 6.0 * $u))
        $progress = [math]::Round($span * $blend)
    }
    Assert-True ($progress -ge $previousProgress) `
        "A3 quintic phase trajectory is not monotonic at tick $tick."
    Assert-True ($progress -ge 0 -and $progress -le $span) `
        "A3 quintic phase trajectory leaves [0, span] at tick $tick."
    $previousProgress = $progress
}
Assert-True ($previousProgress -eq $span) `
    'A3 sweep does not close at exactly one electrical cycle.'
Assert-True ($control -match '(?s)ControlA3PhaseProgressRaw\(uint32_t sweepTick\).*?sweepTick >= CONTROL_A3_SWEEP_TICKS.*?return CONTROL_A3_PHASE_SWEEP_SPAN_RAW;' -and
    $control -match '10\.0f \+ u \* \(-15\.0f \+ 6\.0f \* u\)') `
    'A3 firmware quintic does not clamp endpoints or changed its blend math.'

# --- Prime API stays fail-closed and zero-power (unchanged from A2F). ---
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

# --- Still trajectory-open-loop: no HOME/PID may touch this image. ---
Assert-True ($control -notmatch 'ControlHome|Motor_MoveToAngle') `
    'Alignment image must not contain HOME/PID.'

$align = [regex]::Match($control,
    '(?s)static ControlA3Result_t ControlRunAlignment\(.*?\n\}').Value
$run = [regex]::Match($control,
    '(?s)static void ControlRunA3\(.*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($align) -and
    -not [string]::IsNullOrWhiteSpace($run)) `
    'Could not locate the A3 alignment workflow.'
Assert-True ($align -match 'Motor_Enable\(\)' -and
    $align -match 'outputState\.outputPower\s*==\s*0\.0f' -and
    $align -match 'ControlA3PowerPpm' -and
    $align -match 'ControlA3PhaseProgressRaw' -and
    $align -match 'Motor_SetElectricalPos' -and
    $align -match 'osDelayUntil\(deadline\)' -and
    $align -match 'deadline\s*=\s*now' -and
    $align -match 'CONTROL_A3_SAMPLE_STEP_LIMIT' -and
    $align -match 'CONTROL_A3_TRAVEL_LIMIT' -and
    $align -match 'CONTROL_A3_DEADLINE_FAULT' -and
    $align -match 'CONTROL_A3_DURATION_LIMIT' -and
    $align -match 'CONTROL_A3_CAPTURE_FAULT' -and
    $align -match 'CONTROL_A3_DRAG_SLIP') `
    'A3 alignment is missing zero-power enable, trajectory, or fail-safe gates.'
Assert-True ($align -match 'captured\s*&&\s*dragLagRaw\s*>\s*CONTROL_A3_DRAG_LOSS_LAG_RAW') `
    'A3 pull-out guard must be armed only after capture latches.'
Assert-True ($align -match 'fieldDisp\s*>=\s*CONTROL_A3_CAPTURE_MIN_FIELD_RAW') `
    'A3 capture criterion is missing the field-displacement noise floor.'
Assert-True ($align -notmatch 'ControlLog|HAL_UART_Transmit') `
    'A3 emits UART while the motor can be enabled.'

# --- Run order: reset -> baseline -> prime -> armed -> active -> disable ->
# clear -> report. ---
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
    'A3 call order is not reset -> baseline -> prime -> armed -> active -> disable -> clear -> report.'

# --- Evidence: CCM budget locked, decimated writes, A3 record set. ---
Assert-True ($control -match 'section\("\.ccmram_bss"\)' -and
    $control -match 'memset\(controlEvidence,\s*0,\s*sizeof\(controlEvidence\)\)' -and
    $control -match '_Static_assert\(sizeof\(ControlA3Evidence_t\) == 56U' -and
    $control -match '(?s)_Static_assert\(sizeof\(ControlA3Evidence_t\) \* CONTROL_A3_MAX_EVIDENCE\s*[\r\n\s]*<= 60U \* 1024U') `
    'A3 CCM evidence budget locks are missing.'
Assert-True ($control -match 'sequence % CONTROL_A3_EVIDENCE_DECIMATION\) == 0U' -and
    $control -match 'sequence == CONTROL_A3_TOTAL_TICKS') `
    'A3 evidence decimation must keep every Nth tick plus the final tick.'
Assert-True ($control -match 'CONTROL_A3_DATA' -and
    $control -match 'EncoderRaw' -and
    $control -match 'TravelMilliDeg' -and
    $control -match 'DragLagRaw' -and
    $control -match 'PhaseProgressRaw' -and
    $control -match 'CaptureLatched' -and
    $control -match 'PowerPpm' -and
    $control -match 'VelocityRawPerSecond' -and
    $control -match 'SpiLatencyCycles' -and
    $control -match 'PwmCounterAtCs' -and
    $control -match 'ElectricalOffsetRaw' -and
    $control -match 'CorrectionRaw=0') `
    'A3 deferred evidence/summary record set is incomplete.'
Assert-True ($control -notmatch '%lld' -and
    $control -notmatch 'AccelerationRawPerSecond2=') `
    'A3 telemetry must avoid long-long printf and the retired acceleration log field.'
Assert-True ($control -match 'xPortGetMinimumEverFreeHeapSize' -and
    $control -match 'uxTaskGetStackHighWaterMark' -and
    $control -match 'controlAbortRequested\s*=\s*true') `
    'A3 resource telemetry or second-press abort is missing.'

Write-Host '[ OK ] Control A3 rotating-capture phase-trajectory contract passed.'
