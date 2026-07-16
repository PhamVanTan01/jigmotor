$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$root = Split-Path -Parent $PSScriptRoot
$motorHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\motor.h')
$motorSource = Get-Content -Raw (Join-Path $root 'Core\Src\motor.c')
$controllerSource = Get-Content -Raw (Join-Path $root 'Core\Src\position_controller.c')
$pwmHeader = Get-Content -Raw (Join-Path $root 'Core\Inc\motor_pwm.h')
$pwmSource = Get-Content -Raw (Join-Path $root 'Core\Src\motor_pwm.c')
$nonlinearSource = Get-Content -Raw (Join-Path $root 'Core\Src\nonlinear_test.c')
$mainSource = Get-Content -Raw (Join-Path $root 'Core\Src\main.c')

Assert-True ($nonlinearSource -match
    'NL_CONTROLLER_STATE_POLICY_ID\s+"RESET_BEFORE_EACH_HOME_V1"') `
    'The controller-state experiment policy ID changed unexpectedly.'

Assert-True ($motorHeader -match 'typedef\s+struct[\s\S]*?integralTerm[\s\S]*?lastErrorDeg[\s\S]*?commandedPositionRaw[\s\S]*?feedbackTrackerInitialized[\s\S]*?feedbackAcceptedSamples[\s\S]*?Motor_ControllerState_t') `
    'The controller/acquisition audit snapshot is incomplete.'
Assert-True ($motorHeader -match
    'void\s+Motor_GetControllerState\s*\(Motor_ControllerState_t\s*\*outState\)') `
    'The read-only controller-state snapshot API is missing.'

$resetFunction = [regex]::Match($motorSource,
    'void\s+Motor_ResetPositionController\s*\([^)]*\)\s*\{[\s\S]*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($resetFunction)) `
    'Could not locate Motor_ResetPositionController().'
Assert-True ($resetFunction -match 'PositionController_Reset\s*\(&positionController\)' -and
        $resetFunction -match 'MA600_AcquisitionInit\s*\(&pidAcquisition\)') `
    'Run-boundary reset must clear both the controller and PID feedback acquisition state.'

$sessionResetFunction = [regex]::Match($motorSource,
    'void\s+Motor_ResetControlSession\s*\([^)]*\)\s*\{[\s\S]*?\n\}').Value
Assert-True ($sessionResetFunction -match 'Motor_ResetPositionController\s*\(\)' -and
        $sessionResetFunction -match 'MotorPwm_ResetCommand\s*\(\)') `
    'The physical-test boundary must reset software state and the retained PWM command together.'
Assert-True ($pwmHeader -match 'MotorPwm_GetCommandState' -and
        $pwmSource -match 'MotorPwm_SetElectricalPos\s*\(0U,\s*0\.0f\)' -and
        $pwmSource -match 'lastCommand\.electricalPositionRaw\s*=\s*pos' -and
        $pwmSource -match 'lastCommand\.power\s*=\s*power' -and
        $pwmSource -match 'lastCommand\.enabled\s*=\s*true' -and
        $pwmSource -match 'lastCommand\.enabled\s*=\s*false') `
    'PWM command reset/readback contract is incomplete.'

$snapshotFunction = [regex]::Match($motorSource,
    'void\s+Motor_GetControllerState\s*\([^)]*\)\s*\{[\s\S]*?\n\}').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($snapshotFunction)) `
    'Could not locate Motor_GetControllerState().'
Assert-True ($snapshotFunction -match 'positionController\.integral' -and
        $snapshotFunction -match 'positionController\.lastError' -and
        $snapshotFunction -match 'positionController\.commandedPosition' -and
        $snapshotFunction -match 'pidAcquisition\.unwrap\.initialized' -and
        $snapshotFunction -match 'pidAcquisition\.acceptedSamples' -and
        $snapshotFunction -match 'MotorPwm_GetCommandState') `
    'The state snapshot no longer covers every persistent value used by the home controller.'

$runBoundary = [regex]::Match($nonlinearSource,
    'uint32_t\s+testId\s*=\s*\+\+nlTestIdCounter;[\s\S]*?LockStartPosition\s*\(\s*\)\s*;').Value
Assert-True (-not [string]::IsNullOrWhiteSpace($runBoundary)) `
    'Could not locate the physical-test run boundary.'
$beforeIndex = $runBoundary.IndexOf('Motor_GetControllerState(&controllerStateBeforeReset)')
$disableIndex = $runBoundary.IndexOf('Motor_Disable()')
$resetIndex = $runBoundary.IndexOf('Motor_ResetControlSession()')
$afterIndex = $runBoundary.IndexOf('Motor_GetControllerState(&controllerStateAfterReset)')
$validateIndex = $runBoundary.IndexOf('ControllerStateIsReset(&controllerStateAfterReset)')
$homeIndex = $runBoundary.IndexOf('MoveToZeroAndCheckDirection(&homeObservation)')
$lockIndex = $runBoundary.IndexOf('LockStartPosition()')
$enableIndex = $runBoundary.IndexOf('Motor_Enable()')
Assert-True ($disableIndex -ge 0 -and $disableIndex -lt $beforeIndex -and
        $beforeIndex -lt $resetIndex -and
        $resetIndex -lt $afterIndex -and $afterIndex -lt $validateIndex -and
        $validateIndex -lt $enableIndex -and $enableIndex -lt $homeIndex -and
        $homeIndex -lt $lockIndex) `
    'Required order is disable -> snapshot-before -> full reset -> validate -> enable -> home -> dither lock.'

$resetCheck = [regex]::Match($nonlinearSource,
    'static\s+bool\s+ControllerStateIsReset[\s\S]*?\n\}').Value
Assert-True ($resetCheck -match 'integralTerm\s*==\s*0\.0f' -and
        $resetCheck -match 'lastErrorDeg\s*==\s*0\.0f' -and
        $resetCheck -match 'commandedPositionRaw\s*==\s*0\.0f' -and
        $resetCheck -match '!state->feedbackTrackerInitialized' -and
        $resetCheck -match 'feedbackAcceptedSamples\s*==\s*0U' -and
        $resetCheck -match 'outputElectricalPositionRaw\s*==\s*0U' -and
        $resetCheck -match 'outputPower\s*==\s*0\.0f' -and
        $resetCheck -match '!state->outputEnabled') `
    'The run-boundary reset validity gate is incomplete.'

Assert-True ($nonlinearSource -match
    'MoveToZeroAndCheckDirection\s*\(NlZeroObservation_t\s*\*out\)' -and
        $nonlinearSource -match 'HomeDurationMs=%lu,HomeUpdateCount=%lu' -and
        $nonlinearSource -match 'HomeInitialErrorDeg=%s,HomeFinalErrorDeg=%s' -and
        $nonlinearSource -match 'HomeInitialCommandRaw=%ld,HomeFinalCommandRaw=%ld') `
    'Home convergence diagnostics are incomplete.'
Assert-True ($nonlinearSource -match 'ControllerStatePolicy=%s,ControllerResetApplied=%d,ControllerResetStateValid=%d' -and
        $nonlinearSource -match 'CONTROL_STATE,SchemaVersion=%d' -and
        $nonlinearSource -match 'BeforeIntegralTerm=%s' -and
        $nonlinearSource -match 'AfterFeedbackAccepted=%lu' -and
        $nonlinearSource -match 'BeforeOutputElectricalPositionRaw=%u' -and
        $nonlinearSource -match 'AfterOutputPower=%s' -and
        $nonlinearSource -match 'AfterOutputEnabled=%d') `
    'META/CONTROL_STATE records do not expose the complete reset audit contract.'

$selfTest = [regex]::Match($motorSource,
    'bool\s+Motor_RunControllerSelfTest\s*\([^)]*\)\s*\{[\s\S]*?\n\}').Value
Assert-True ($selfTest -match 'PositionController_Update\s*\(&positionController' -and
        $selfTest -match 'pidAcquisition\.unwrap\.initialized\s*=\s*true' -and
        $selfTest -match 'MotorPwm_SetElectricalPos\s*\(123U,\s*0\.5f\)' -and
        $selfTest -match 'Motor_ResetControlSession\s*\(\)' -and
        $selfTest -match 'state\.feedbackAcceptedSamples\s*==\s*0U' -and
        $selfTest -match 'state\.outputPower\s*==\s*0\.0f' -and
        $selfTest -match '!state\.outputEnabled') `
    'Boot self-test no longer proves that the real facade state is reset.'
Assert-True ($mainSource -match 'Motor_Init\s*\(\)[\s\S]*?Motor_RunControllerSelfTest\s*\(\)[\s\S]*?Error_Handler\s*\(\)') `
    'Controller reset self-test is not fail-closed at boot.'

# Freeze every other experimental factor. Controller tuning or motion changes
# must be made under a new policy ID and a separate hardware data set.
Assert-True ($motorSource -match '\.kp\s*=\s*2\.0f' -and
        $motorSource -match '\.ki\s*=\s*0\.003f' -and
        $motorSource -match '\.kd\s*=\s*0\.3f' -and
        $motorSource -match '\.integralLimit\s*=\s*5\.0f' -and
        $motorSource -match '\.outputLimit\s*=\s*400\.0f') `
    'PID tuning changed inside the isolated reset-state experiment.'
Assert-True ($controllerSource -match 'controller->integral\s*\+=\s*controller->config\.ki\s*\*\s*errorDeg' -and
        $controllerSource -match 'controller->integral\s*=\s*0\.0f' -and
        $controllerSource -match 'controller->commandedPosition\s*-=\s*output') `
    'Controller update math changed inside the isolated reset-state experiment.'
Assert-True ($nonlinearSource -match '#define\s+NL_POINTS_PER_REV\s+360U' -and
        $nonlinearSource -match '#define\s+NL_GRID_STEP_DEG\s+1\.0f' -and
        $nonlinearSource -match 'NlTargetRawMagnitudeForPoint' -and
        $nonlinearSource -match '#define\s+NL_TEST_COUNT\s+1' -and
        $nonlinearSource -match '#define\s+NL_RAMP_STEP\s+8' -and
        $nonlinearSource -match '#define\s+NL_RAMP_STEP_DELAY_MS\s+1' -and
        $nonlinearSource -match '#define\s+NL_MOVE_ZERO_LOOP_DELAY_MS\s+2' -and
        $nonlinearSource -match '#define\s+NL_DITHER_START_POS\s+20' -and
        $nonlinearSource -match '#define\s+NL_DITHER_SETTLE_MS\s+200') `
    'Approved one-degree sweep, ramp, home-loop, or dither contract changed unexpectedly.'

Write-Host '[ OK ] Phase-3B0-R controller-state synchronization contract tests passed.'
