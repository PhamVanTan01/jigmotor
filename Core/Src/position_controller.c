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
}

float PositionController_Update(PositionController_t *controller, float errorDeg)
{
    if (controller == NULL)
    {
        return 0.0f;
    }

    float p = controller->config.kp * errorDeg;
    controller->integral += controller->config.ki * errorDeg;
    if (fabsf(controller->integral) > controller->config.integralLimit)
    {
        /* Preserve the existing controller behavior. This can later be
         * replaced by clamping/back-calculation as a separately validated
         * tuning change. */
        controller->integral = 0.0f;
    }
    float d = controller->config.kd * (errorDeg - controller->lastError);
    controller->lastError = errorDeg;

    float output = p + controller->integral + d;
    if (output > controller->config.outputLimit) output = controller->config.outputLimit;
    if (output < -controller->config.outputLimit) output = -controller->config.outputLimit;

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
    };
    PositionController_Init(&controller, &saturated);
    float saturatedCommand = PositionController_Update(&controller, 1.0f);

    return fabsf(command1 - (-2.0f)) < 0.0001f
        && fabsf(command2 - (-1.0f)) < 0.0001f
        && fabsf(saturatedCommand - (-5.0f)) < 0.0001f;
}
