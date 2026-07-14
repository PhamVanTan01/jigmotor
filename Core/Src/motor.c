/* Motor facade: combines checked encoder feedback, the pure position
 * controller, and the low-level PWM/relay driver without merging their state.
 */

#include "motor.h"
#include "ma600_acquisition.h"
#include "motor_pwm.h"
#include "position_controller.h"
#include "motor_config.h"
#include <stddef.h>

#define MOTOR_PID_MAX_JUMP_RAW      8192
#define MOTOR_PID_READ_ATTEMPTS     3U

static const PositionControllerConfig_t POSITION_CONFIG = {
    .kp = 2.0f,
    .ki = 0.003f,
    .kd = 0.3f,
    .integralLimit = 5.0f,
    .outputLimit = 400.0f,
};

static PositionController_t positionController;
static MA600_AcquisitionContext_t pidAcquisition;

void Motor_Init(void)
{
    MotorPwm_Init();
    PositionController_Init(&positionController, &POSITION_CONFIG);
    MA600_AcquisitionInit(&pidAcquisition);
}

bool Motor_RunControllerSelfTest(void)
{
    if (!PositionController_RunSelfTest())
    {
        return false;
    }

    /* Exercise the real facade state, not just a local pure-controller
     * instance. This runs at boot before the output driver is enabled, so
     * changing compare registers cannot energize the motor. Leave the
     * production state reset on exit. */
    (void)PositionController_Update(&positionController, 2.0f);
    pidAcquisition.unwrap.initialized = true;
    pidAcquisition.acceptedSamples = 1U;
    MotorPwm_SetElectricalPos(123U, 0.5f);
    Motor_ResetControlSession();

    Motor_ControllerState_t state;
    Motor_GetControllerState(&state);
    return state.integralTerm == 0.0f
        && state.lastErrorDeg == 0.0f
        && state.commandedPositionRaw == 0.0f
        && !state.feedbackTrackerInitialized
        && state.feedbackAcceptedSamples == 0U
        && state.outputElectricalPositionRaw == 0U
        && state.outputPower == 0.0f
        && !state.outputEnabled;
}

void Motor_Enable(void)
{
    MotorPwm_Enable();
}

void Motor_Disable(void)
{
    MotorPwm_Disable();
}

void Motor_SetElectricalPos(uint16_t pos, float power)
{
    MotorPwm_SetElectricalPos(pos, power);
}

void Motor_ResetPositionController(void)
{
    PositionController_Reset(&positionController);
    MA600_AcquisitionInit(&pidAcquisition);
}

void Motor_ResetControlSession(void)
{
    Motor_ResetPositionController();
    MotorPwm_ResetCommand();
}

void Motor_GetControllerState(Motor_ControllerState_t *outState)
{
    if (outState == NULL)
    {
        return;
    }

    outState->integralTerm = positionController.integral;
    outState->lastErrorDeg = positionController.lastError;
    outState->commandedPositionRaw = positionController.commandedPosition;
    outState->feedbackTrackerInitialized = pidAcquisition.unwrap.initialized;
    outState->feedbackAcceptedSamples = pidAcquisition.acceptedSamples;

    MotorPwm_CommandState_t outputState;
    MotorPwm_GetCommandState(&outputState);
    outState->outputElectricalPositionRaw = outputState.electricalPositionRaw;
    outState->outputPower = outputState.power;
    outState->outputEnabled = outputState.enabled;
}

MA600_Result_t Motor_MoveToAngle(float targetDeg, float *outErrorDeg)
{
    if (outErrorDeg == NULL)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    MA600_Sample_t sample;
    MA600_Result_t result = MA600_AcquireSample(&pidAcquisition,
        MOTOR_PID_MAX_JUMP_RAW, MOTOR_PID_READ_ATTEMPTS, &sample);
    if (result != MA600_RESULT_OK)
    {
        return result;
    }

    float error = MA600_UnwrappedRawToDegrees(sample.unwrappedRaw) - targetDeg;
    *outErrorDeg = error;
    float commandedPosition = PositionController_Update(&positionController, error);

    /* Converting a negative float directly to uint16_t is undefined. The
     * signed intermediate makes the final integer wrap well-defined. */
    MotorPwm_SetElectricalPos((uint16_t)(int32_t)commandedPosition, 1.0f);
    return MA600_RESULT_OK;
}

uint16_t Motor_ElectricalOffset(uint16_t rawCount)
{
    return (uint16_t)((uint32_t)rawCount % MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
}

uint16_t Motor_GetPolePairs(void)
{
    return (uint16_t)MOTOR_POLE_PAIRS;
}

uint16_t Motor_GetPoleCount(void)
{
    return (uint16_t)MOTOR_NUM_POLSE;
}

int32_t Motor_GetCommandedPos(void)
{
    return (int32_t)PositionController_GetCommandedPosition(&positionController);
}
