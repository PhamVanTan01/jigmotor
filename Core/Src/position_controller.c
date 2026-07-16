#include "position_controller.h"
#include <math.h>
#include <stddef.h>

void PositionController_Init(PositionController_t *controller,
                             const PositionControllerConfig_t *config)
{
    if (controller == NULL || config == NULL)
    {
        return;
    }
    controller->config = *config;
    PositionController_Reset(controller);
}

void PositionController_Reset(PositionController_t *controller)
{
    if (controller == NULL)
    {
        return;
    }
    controller->integral = 0.0f;
    controller->lastError = 0.0f;
    controller->commandedPosition = 0.0f;
    controller->filteredDerivative = 0.0f;
    controller->lastOutput = 0.0f;
}

float PositionController_Update(PositionController_t *controller, float errorDeg)
{
    if (controller == NULL)
    {
        return 0.0f;
    }

    float p = controller->config.kp * errorDeg;
    controller->integral += controller->config.ki * errorDeg;
    if (controller->integral > controller->config.integralLimit)
        controller->integral = controller->config.integralLimit;
    if (controller->integral < -controller->config.integralLimit)
        controller->integral = -controller->config.integralLimit;

    float rawDerivative = controller->config.kd
        * (errorDeg - controller->lastError);
    float derivativeAlpha = controller->config.derivativeAlpha;
    if (derivativeAlpha < 0.0f) derivativeAlpha = 0.0f;
    if (derivativeAlpha > 1.0f) derivativeAlpha = 1.0f;
    controller->filteredDerivative += derivativeAlpha
        * (rawDerivative - controller->filteredDerivative);
    controller->lastError = errorDeg;

    float output = p + controller->integral + controller->filteredDerivative;
    if (output > controller->config.outputLimit) output = controller->config.outputLimit;
    if (output < -controller->config.outputLimit) output = -controller->config.outputLimit;

    float slewLimit = controller->config.outputSlewLimit;
    if (slewLimit > 0.0f)
    {
        float outputDelta = output - controller->lastOutput;
        if (outputDelta > slewLimit) output = controller->lastOutput + slewLimit;
        if (outputDelta < -slewLimit) output = controller->lastOutput - slewLimit;
    }
    controller->lastOutput = output;

    controller->commandedPosition -= output;
    return controller->commandedPosition;
}

float PositionController_GetCommandedPosition(const PositionController_t *controller)
{
    return (controller != NULL) ? controller->commandedPosition : 0.0f;
}

bool PositionController_RunSelfTest(void)
{
    const PositionControllerConfig_t proportionalOnly = {
        .kp = 1.0f,
        .ki = 0.0f,
        .kd = 0.0f,
        .integralLimit = 10.0f,
        .outputLimit = 10.0f,
        .derivativeAlpha = 1.0f,
        .outputSlewLimit = 10.0f,
    };
    PositionController_t controller;
    PositionController_Init(&controller, &proportionalOnly);

    float command1 = PositionController_Update(&controller, 2.0f);
    float command2 = PositionController_Update(&controller, -1.0f);
    PositionController_Reset(&controller);

    const PositionControllerConfig_t saturated = {
        .kp = 100.0f,
        .ki = 0.0f,
        .kd = 0.0f,
        .integralLimit = 10.0f,
        .outputLimit = 5.0f,
        .derivativeAlpha = 1.0f,
        .outputSlewLimit = 10.0f,
    };
    PositionController_Init(&controller, &saturated);
    float saturatedCommand = PositionController_Update(&controller, 1.0f);

    const PositionControllerConfig_t integralClamp = {
        .kp = 0.0f,
        .ki = 2.0f,
        .kd = 0.0f,
        .integralLimit = 3.0f,
        .outputLimit = 100.0f,
        .derivativeAlpha = 1.0f,
        .outputSlewLimit = 100.0f,
    };
    PositionController_Init(&controller, &integralClamp);
    float integralCommand1 = PositionController_Update(&controller, 2.0f);
    float integralCommand2 = PositionController_Update(&controller, 2.0f);
    float clampedIntegral = controller.integral;

    const PositionControllerConfig_t filteredDerivative = {
        .kp = 0.0f,
        .ki = 0.0f,
        .kd = 4.0f,
        .integralLimit = 10.0f,
        .outputLimit = 100.0f,
        .derivativeAlpha = 0.25f,
        .outputSlewLimit = 100.0f,
    };
    PositionController_Init(&controller, &filteredDerivative);
    float derivativeCommand1 = PositionController_Update(&controller, 4.0f);
    float derivativeCommand2 = PositionController_Update(&controller, 4.0f);

    const PositionControllerConfig_t slewLimited = {
        .kp = 10.0f,
        .ki = 0.0f,
        .kd = 0.0f,
        .integralLimit = 10.0f,
        .outputLimit = 100.0f,
        .derivativeAlpha = 1.0f,
        .outputSlewLimit = 3.0f,
    };
    PositionController_Init(&controller, &slewLimited);
    float slewCommand1 = PositionController_Update(&controller, 2.0f);
    float slewCommand2 = PositionController_Update(&controller, 2.0f);
    float slewOutput2 = controller.lastOutput;
    PositionController_Reset(&controller);
    bool resetStateValid = controller.integral == 0.0f
        && controller.lastError == 0.0f
        && controller.commandedPosition == 0.0f
        && controller.filteredDerivative == 0.0f
        && controller.lastOutput == 0.0f;

    return fabsf(command1 - (-2.0f)) < 0.0001f
        && fabsf(command2 - (-1.0f)) < 0.0001f
        && fabsf(saturatedCommand - (-5.0f)) < 0.0001f
        && fabsf(integralCommand1 - (-3.0f)) < 0.0001f
        && fabsf(integralCommand2 - (-6.0f)) < 0.0001f
        && fabsf(clampedIntegral - 3.0f) < 0.0001f
        && fabsf(derivativeCommand1 - (-4.0f)) < 0.0001f
        && fabsf(derivativeCommand2 - (-7.0f)) < 0.0001f
        && fabsf(slewCommand1 - (-3.0f)) < 0.0001f
        && fabsf(slewCommand2 - (-9.0f)) < 0.0001f
        && fabsf(slewOutput2 - 6.0f) < 0.0001f
        && resetStateValid;
}
