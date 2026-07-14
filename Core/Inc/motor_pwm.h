#ifndef __MOTOR_PWM_H
#define __MOTOR_PWM_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef struct
{
    uint16_t electricalPositionRaw;
    float power;
    bool enabled;
} MotorPwm_CommandState_t;

void MotorPwm_Init(void);
void MotorPwm_Enable(void);
void MotorPwm_Disable(void);
void MotorPwm_SetElectricalPos(uint16_t pos, float power);
void MotorPwm_ResetCommand(void);
void MotorPwm_GetCommandState(MotorPwm_CommandState_t *outState);

#ifdef __cplusplus
}
#endif

#endif /* __MOTOR_PWM_H */
