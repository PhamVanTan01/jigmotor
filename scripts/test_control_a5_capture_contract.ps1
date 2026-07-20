$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-FunctionBlock {
    param([string]$Text, [string]$StartPattern, [string]$EndPattern,
        [string]$Name)
    $match = [regex]::Match($Text,
        "(?s)$StartPattern.*?(?=$EndPattern)")
    Assert-True $match.Success "Could not locate $Name."
    $match.Value
}

$root = Split-Path -Parent $PSScriptRoot
$captureHeader = Get-Content -Raw `
    (Join-Path $root 'Core\Inc\control_a5_capture.h')
$capture = Get-Content -Raw `
    (Join-Path $root 'Core\Src\control_a5_capture.c')
$mathHeader = Get-Content -Raw `
    (Join-Path $root 'Core\Inc\control_a5_math.h')
$engine = Get-Content -Raw `
    (Join-Path $root 'Core\Src\control_engine.c')
$mode = Get-Content -Raw (Join-Path $root 'Core\Inc\app_mode.h')

# A5.4 activates capture by default: the app profile identity now names A5,
# both compile-time locks are 1, and the ControlEngineTask branch selects
# ControlRunA5(). The frozen A4B fallback path must still compile and exist
# (a future profile could disable A5 again for a controlled rollback), but it
# is no longer what a default build runs.
Assert-True ($captureHeader -match
        '#define CONTROL_A5_CAPTURE_INTEGRATION_ENABLED\s+1U' -and
    $captureHeader -match
        '#define CONTROL_A5_PROFILE_ACTIVATION_ACK\s+1U' -and
    $captureHeader -match
        'A5 capture cannot be enabled before the app profile activation is acknowledged' -and
    $mode -match 'CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1' -and
    $mode -notmatch 'CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1') `
    'A5.4 must activate capture behind the now-satisfied integration lock.'
Assert-True ($engine -match
        'if \(CONTROL_A5_CAPTURE_INTEGRATION_ENABLED != 0U\)' -and
    $engine -match '(?s)else\s*\{\s*ControlRunA4\(\);\s*\}') `
    'Control task must still compile the A4B fallback path alongside active A5.'

# Retained heap resource: one exact 24 KiB allocation, no stack/CCM buffer,
# self-tests before allocation, and a hard 64 KiB post-allocation floor.
Assert-True ($mathHeader -match
        'sizeof\(ControlA5Sample_t\) \* CONTROL_A5_SAMPLE_COUNT == 24576U' -and
    $captureHeader -match
        'CONTROL_A5_MIN_FREE_HEAP_AFTER_BUFFER\s+\(64U \* 1024U\)' -and
    $capture -match '(?s)ControlA5_CaptureResourcesInit\(void\).*?ControlA5_MathSelfTest\(\).*?MA600_ConfigurationGateSelfTest\(\).*?sizeof\(ControlA5Sample_t\)\s*\* CONTROL_A5_SAMPLE_COUNT.*?pvPortMalloc' -and
    $capture -match '(?s)freeAfter < CONTROL_A5_MIN_FREE_HEAP_AFTER_BUFFER.*?vPortFree\(candidate\)' -and
    $capture -match 'static ControlA5Sample_t \*controlA5Evidence;' -and
    $capture -notmatch 'ControlA5Sample_t\s+controlA5Evidence\[') `
    'A5 retained evidence allocation/headroom contract is incomplete.'
Assert-True ($engine -match
        '(?s)ControlEngine_Init\(void\).*?ControlA5_CaptureResourcesInit\(\).*?osMessageQueueNew' -and
    $engine -match
        '(?s)controlCommandQueue == NULL.*?ControlA5_CaptureResourcesReleaseForInitFailure' -and
    $engine -match
        '(?s)controlTaskHandle == NULL.*?ControlA5_CaptureResourcesReleaseForInitFailure') `
    'A5 resources are not initialized once or rolled back on engine-init failure.'

# Locked, read-only MA600 configuration snapshot. No status clear, register
# write, NVM write, or UART is allowed in this module.
Assert-True ($capture -match '(?s)CONTROL_A5_EXPECTED_CONFIG.*?\.zero = 0x0000U.*?\.dir = 0x00U.*?\.filt = 0x05U.*?\.status = 0x00U.*?\.prt = 0x00U.*?\.rmapId = 0x00U.*?\.corrCrc32 = 0x190A55ADU' -and
    $capture -match '(?s)ControlA5_ReadAndGateConfiguration.*?MA600_ReadConfiguration.*?MA600_ValidateConfigurationLockedGate') `
    'A5 exact Policy-A read-only configuration gate is incomplete.'
Assert-True ($capture -notmatch
        'MA600_PrecheckAndClearStatus|MA600_ClearErrorFlags|MA600_Write|HAL_UART|ControlLog|printf') `
    'A5 capture module performs a forbidden config mutation or UART operation.'

$window = Get-FunctionBlock $capture `
    'ControlA5Result_t\s+ControlA5_CaptureStaticWindow\(' `
    'bool\s+ControlA5_RecordSafeStopState\(' 'A5 static capture window'

# Dedicated acquisition, exact 2048x1 kHz policy, metadata capture, absolute
# scheduling with no catch-up, and physical/static gates.
Assert-True ($window -match 'MA600_AcquisitionInit\(&report->acquisition\)' -and
    $window -match
        'index < CONTROL_A5_SAMPLE_COUNT' -and
    $window -match
        'deadline = osKernelGetTickCount\(\) \+ CONTROL_A5_PERIOD_MS' -and
    $window -match 'deadline \+= CONTROL_A5_PERIOD_MS' -and
    $window -match 'osDelayUntil\(deadline\)' -and
    $window -match 'report->skippedSlots \+= now - deadline' -and
    $window -match 'break;' -and
    $window -match '(?s)MA600_AcquireSample\(\s*&report->acquisition, CONTROL_A5_MAX_UNWRAP_JUMP_RAW,\s*CONTROL_A5_READ_ATTEMPTS' -and
    $window -match 'sample\.attempts != 1U' -and
    $window -match 'sample\.flags != MA600_SAMPLE_FLAG_NONE') `
    'A5 exact acquisition/scheduling/no-retry contract is incomplete.'
Assert-True ($window -match 'sample\.meta\.csAssertCycle' -and
    $window -match 'sample\.meta\.pwmCounterAtCs' -and
    $window -match 'sample\.meta\.transferCompleteCycle' -and
    $window -match 'record->spiLatencyCycles' -and
    $window -match 'ControlA5_ScheduleErrorCycles' -and
    $window -match 'ControlA5_PwmPhaseBin' -and
    $window -match 'CONTROL_A5_MAX_SAMPLE_STEP_RAW' -and
    $window -match 'CONTROL_A5_MAX_STATIC_TRAVEL_RAW' -and
    $window -match 'CONTROL_A5_MAX_CAPTURE_MS' -and
    $window -match 'abortRequested\(\)') `
    'A5 timing/state/static-window evidence is incomplete.'
Assert-True ($window -notmatch
        'Motor_Set|Motor_Enable|Motor_Disable|HAL_UART|ControlLog|printf') `
    'A5 timed capture mutates the motor or emits UART.'

# Pre/post snapshots validate phase=0/power=35%/enabled and compare all
# persistent controller/output fields to catch any command-state mutation.
Assert-True ($capture -match '(?s)ControlA5_IsExpectedHoldState.*?outputEnabled.*?CONTROL_A5_COMMAND_PHASE_RAW.*?CONTROL_A5_COMMAND_POWER_PPM' -and
    $capture -match '(?s)ControlA5_ControllerStatesEqual.*?integralTerm.*?feedbackAcceptedSamples.*?outputElectricalPositionRaw.*?outputPower.*?outputEnabled' -and
    $capture -match '(?s)ControlA5_RecordPreCaptureState.*?Motor_GetControllerState.*?ControlA5_IsExpectedHoldState' -and
    $capture -match '(?s)ControlA5_RecordPostCaptureState.*?Motor_GetControllerState.*?commandChanged') `
    'A5 constant HOLD state is not checked before and after capture.'

$runA4 = Get-FunctionBlock $engine `
    'static void\s+ControlRunA4\(void\)' `
    '/\* Dormant A5\.2 orchestration\.' 'frozen A4B workflow'
Assert-True ($runA4 -notmatch 'ControlA5_|CONTROL_A5_') `
    'A5.2 altered the frozen active A4B workflow.'

$runA5 = Get-FunctionBlock $engine `
    'static void\s+ControlRunA5\(void\)' `
    'static bool\s+ControlA5AbortRequested\(void\)' 'A5 orchestration'
$orderedTokens = @(
    'ControlA5_CaptureReportInit',
    'ControlA5_ReadAndGateConfiguration',
    'MA600_AcquireSample',
    'ControlRunAlignment',
    'ControlA5_RecordPreCaptureState',
    'ControlA5_CaptureStaticWindow',
    'ControlA5_RecordPostCaptureState',
    'safe_stop:',
    'Motor_Disable()',
    'Motor_SetElectricalPos',
    'ControlA5_RecordSafeStopState',
    'ControlA5_FinalizeAfterSafeStop',
    'ControlReport'
)
$previous = -1
foreach ($token in $orderedTokens) {
    $index = $runA5.IndexOf($token, $previous + 1,
        [System.StringComparison]::Ordinal)
    Assert-True ($index -gt $previous) `
        "A5 orchestration order is wrong or missing token: $token"
    $previous = $index
}
Assert-True ($runA5 -notmatch '\breturn\b') `
    'A5 orchestration has an exit that bypasses the single safe-stop label.'
Assert-True ($runA5 -notmatch 'MA600_PrecheckAndClearStatus') `
    'A5 must not issue the legacy clear-status command.'

# Final validity is a conjunction; summaries are finalized only after the
# caller records a verified zero-power safe stop.
Assert-True ($capture -match '(?s)ControlA5_RecordSafeStopState.*?!report->safeStopState\.outputEnabled.*?outputPower == 0\.0f.*?CONTROL_A5_COMMAND_PHASE_RAW' -and
    $capture -match '(?s)ControlA5_FinalizeAfterSafeStop.*?ControlA5_StatsFinalize.*?measurementValid\s*=.*?resourcesValid.*?configValid.*?parentAlignmentValid.*?preStateValid.*?postStateValid.*?!report->commandChanged.*?acquisitionValid.*?timingValid.*?staticWindowValid.*?recordIntegrityValid.*?safeStopValid') `
    'A5 fail-closed safe-stop/final validity model is incomplete.'

# Nominal hardware evidence from A4B was 91,688 free bytes. The locked A5
# buffer leaves 67,112 bytes, above the 64 KiB floor with 1,576-byte margin.
$nominalFreeAfter = 91688 - 24576
Assert-True ($nominalFreeAfter -eq 67112 -and
    $nominalFreeAfter -ge 64KB) 'A5 nominal heap budget arithmetic failed.'

Write-Host '[ OK ] A5.2 dormant capture/safety integration contract passed.'
