/* 3-phase sine-commutation motor driver (TIM1 CH1/2/3), plus a simple
 * closed-loop position controller used only to return to a reference angle
 * before a sweep. */

#ifndef __MOTOR_H
#define __MOTOR_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* Same 0-65535 unit convention as the MA600A's raw angle: one full
 * mechanical revolution is 65536 counts. */
void  Motor_Init(void);
void  Motor_Enable(void);
void  Motor_Disable(void);
void  Motor_SetElectricalPos(uint16_t pos, float power);

/* Closed-loop PID step toward targetDeg (multi-turn, unwrapped degrees --
 * see MA600_ReadMultiTurnDegrees()). Call repeatedly; returns the current
 * error so the caller can detect convergence. */
float Motor_MoveToAngle(float targetDeg);

/* Diagnostic only (matches the "Motor offset" log field in
 * docs/end-of-shaft-mounting-test-plan.md's log format): reduces a raw
 * MA600A count to its offset within one electrical cycle. Not used by any
 * of the actual position/angle math above. */
uint16_t Motor_ElectricalOffset(uint16_t rawCount);

/* Diagnostic only: the PID's internally accumulated commanded position (raw
 * 0-65535-scale units, unwrapped -- keeps growing/shrinking across many
 * electrical cycles, not clamped to one revolution). Useful to see whether
 * the PID is actually driving the commutation angle a meaningful amount, or
 * barely moving it, when the shaft itself isn't visibly rotating. */
int32_t Motor_GetCommandedPos(void);

/* Build-geometry audit values used by boot/run manifests. */
uint16_t Motor_GetPoleCount(void);
uint16_t Motor_GetPolePairs(void);
uint16_t Motor_GetElectricalCycleRaw(void);
uint16_t Motor_GetElectricalRippleOrder(void);

#ifdef __cplusplus
}
#endif

#endif /* __MOTOR_H */
