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
    /* 0..1 one-pole smoothing applied to the derivative contribution.
     * 1 keeps the legacy unfiltered derivative. */
    float derivativeAlpha;
    /* Maximum change of the incremental position command per controller
     * update. This is an acceleration/slew guard, not an output clamp. */
    float outputSlewLimit;
} PositionControllerConfig_t;

typedef struct
{
    PositionControllerConfig_t config;
    float integral;
    float lastError;
    float commandedPosition;
    float filteredDerivative;
    float lastOutput;
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
