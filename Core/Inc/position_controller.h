#ifndef __POSITION_CONTROLLER_H
#define __POSITION_CONTROLLER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef struct
{
    float kp;
    float ki;
    float kd;
    float integralLimit;
    float outputLimit;
} PositionControllerConfig_t;

typedef struct
{
    PositionControllerConfig_t config;
    float integral;
    float lastError;
    float commandedPosition;
} PositionController_t;

void PositionController_Init(PositionController_t *controller,
                             const PositionControllerConfig_t *config);
void PositionController_Reset(PositionController_t *controller);
float PositionController_Update(PositionController_t *controller, float errorDeg);
float PositionController_GetCommandedPosition(const PositionController_t *controller);
bool PositionController_RunSelfTest(void);

#ifdef __cplusplus
}
#endif

#endif /* __POSITION_CONTROLLER_H */
