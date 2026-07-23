/* Motor facade: combines checked encoder feedback, the pure position
 * controller, and the low-level PWM/relay driver without merging their state.
 */

#include "motor.h"
#include "app_mode.h"
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
    .derivativeAlpha = 0.25f,
    .outputSlewLimit = 8.0f,
};

#define MOTOR_HOME_CONTROLLER_PROFILE_ID "WRAPPED_PID_SLEW_V2"

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
    bool resetValid = state.integralTerm == 0.0f
        && state.lastErrorDeg == 0.0f
        && state.commandedPositionRaw == 0.0f
        && state.filteredDerivativeTerm == 0.0f
        && state.lastOutputStepRaw == 0.0f
        && !state.feedbackTrackerInitialized
        && state.feedbackAcceptedSamples == 0U
        && state.outputElectricalPositionRaw == 0U
        && state.outputPower == 0.0f
        && !state.outputEnabled;

#if JIG_APP_MODE == JIG_APP_CONTROL
    bool primeValid = Motor_PrimeControlSession(321, 0.0f);
    Motor_GetControllerState(&state);
    primeValid = primeValid
        && state.integralTerm == 0.0f
        && state.lastErrorDeg == 0.0f
        && state.commandedPositionRaw == 321.0f
        && state.filteredDerivativeTerm == 0.0f
        && state.lastOutputStepRaw == 0.0f
        && !state.feedbackTrackerInitialized
        && state.feedbackAcceptedSamples == 0U
        && state.outputElectricalPositionRaw == 321U
        && state.outputPower == 0.0f
        && !state.outputEnabled;
    Motor_ResetControlSession();
    return resetValid && primeValid;
#else
    return resetValid;
#endif
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
    outState->filteredDerivativeTerm = positionController.filteredDerivative;
    outState->lastOutputStepRaw = positionController.lastOutput;
    outState->feedbackTrackerInitialized = pidAcquisition.unwrap.initialized;
    outState->feedbackAcceptedSamples = pidAcquisition.acceptedSamples;

    MotorPwm_CommandState_t outputState;
    MotorPwm_GetCommandState(&outputState);
    outState->outputElectricalPositionRaw = outputState.electricalPositionRaw;
    outState->outputPower = outputState.power;
    outState->outputEnabled = outputState.enabled;
}

#if JIG_APP_MODE == JIG_APP_CONTROL
MA600_Result_t Motor_MoveToAngleWithPower(float targetDeg, float power,
                                          float *outErrorDeg)
{
    if (outErrorDeg == NULL || !(power >= 0.0f && power <= 1.0f))
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
    /* The encoder is periodic. Without wrapping, 352 deg to target 0 was
     * treated as a 352-degree move instead of the equivalent -8-degree
     * error, adding a full unnecessary revolution before every sweep. */
    while (error > 180.0f) error -= 360.0f;
    while (error < -180.0f) error += 360.0f;
    *outErrorDeg = error;
    float commandedPosition = PositionController_Update(&positionController, error);

    /* Converting a negative float directly to uint16_t is undefined. The
     * signed intermediate makes the final integer wrap well-defined. */
    MotorPwm_SetElectricalPos((uint16_t)(int32_t)commandedPosition, power);
    return MA600_RESULT_OK;
}

#if JIG_APP_MODE == JIG_APP_CONTROL
bool Motor_PrimeControlSession(int32_t commandedPositionRaw,
                               float initialPower)
{
    MotorPwm_CommandState_t outputState;
    MotorPwm_GetCommandState(&outputState);
    if (outputState.enabled || initialPower != 0.0f)
    {
        Motor_Disable();
        return false;
    }

    Motor_ResetPositionController();
    positionController.commandedPosition = (float)commandedPositionRaw;
    MotorPwm_SetElectricalPos((uint16_t)commandedPositionRaw, 0.0f);
    return true;
}
#endif

MA600_Result_t Motor_MoveToAngle(float targetDeg, float *outErrorDeg)
{
    return Motor_MoveToAngleWithPower(targetDeg, 1.0f, outErrorDeg);
}
#else
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
    /* Preserve the qualified Measurement home operations and full-power
     * command: the encoder is periodic, so use the shortest wrapped error. */
    while (error > 180.0f) error -= 360.0f;
    while (error < -180.0f) error += 360.0f;
    *outErrorDeg = error;
    float commandedPosition = PositionController_Update(&positionController, error);

    MotorPwm_SetElectricalPos((uint16_t)(int32_t)commandedPosition, 1.0f);
    return MA600_RESULT_OK;
}
#endif /* JIG_APP_MODE == JIG_APP_CONTROL */

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

const char *Motor_GetHomeControllerProfileId(void)
{
    return MOTOR_HOME_CONTROLLER_PROFILE_ID;
}
