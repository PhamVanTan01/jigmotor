/* 3-phase sine-commutation motor driver (TIM1 CH1/2/3) for a PM1505 (12-pole)
 * test motor, plus a simple closed-loop position controller used only to
 * return to a reference angle before a sweep. */

#ifndef __MOTOR_H
#define __MOTOR_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include "ma600.h"

/* Snapshot of every persistent controller/acquisition/output-command element
 * that can make one closed-loop home sequence start differently from another.
 * The snapshot is diagnostic; physical tests use Motor_ResetControlSession(). */
typedef struct
{
    float    integralTerm;
    float    lastErrorDeg;
    float    commandedPositionRaw;
    float    filteredDerivativeTerm;
    float    lastOutputStepRaw;
    bool     feedbackTrackerInitialized;
    uint32_t feedbackAcceptedSamples;
    uint16_t outputElectricalPositionRaw;
    float    outputPower;
    bool     outputEnabled;
} Motor_ControllerState_t;

/* Same 0-65535 unit convention as the MA600A's raw angle: one full
 * mechanical revolution is 65536 counts. */
void  Motor_Init(void);
bool  Motor_RunControllerSelfTest(void);
void  Motor_Enable(void);
void  Motor_Disable(void);
void  Motor_SetElectricalPos(uint16_t pos, float power);

/* Closed-loop PID step toward targetDeg using checked, independently
 * unwrapped encoder feedback. The motor command is not changed when the
 * feedback sample is invalid. */
MA600_Result_t Motor_MoveToAngle(float targetDeg, float *outErrorDeg);

/* Control-image characterization variant. It uses the identical position
 * controller and checked feedback path, but bounds winding power explicitly.
 * The Measurement image continues to call Motor_MoveToAngle(), whose behavior
 * remains the original full-power home command. */
MA600_Result_t Motor_MoveToAngleWithPower(float targetDeg, float power,
                                          float *outErrorDeg);

/* Resets PID and feedback-tracker state. Call only while the test engine owns
 * the motor and before beginning a new closed-loop positioning sequence. */
void Motor_ResetPositionController(void);

/* Establishes a deterministic physical-test boundary while the output is
 * disabled: controller, feedback acquisition, and retained PWM command are
 * all reset together. */
void Motor_ResetControlSession(void);

/* Read-only controller/acquisition state for run-boundary audit logging. */
void Motor_GetControllerState(Motor_ControllerState_t *outState);

/* Diagnostic only (matches the "Motor offset" log field in
 * docs/end-of-shaft-mounting-test-plan.md's log format): reduces a raw
 * MA600A count to its offset within one electrical cycle. Not used by any
 * of the actual position/angle math above. */
uint16_t Motor_ElectricalOffset(uint16_t rawCount);

/* Build-time motor geometry used by commutation and harmonic diagnostics. */
uint16_t Motor_GetPoleCount(void);
uint16_t Motor_GetPolePairs(void);

/* Diagnostic only: the PID's internally accumulated commanded position (raw
 * 0-65535-scale units, unwrapped -- keeps growing/shrinking across many
 * electrical cycles, not clamped to one revolution). Useful to see whether
 * the PID is actually driving the commutation angle a meaningful amount, or
 * barely moving it, when the shaft itself isn't visibly rotating. */
int32_t Motor_GetCommandedPos(void);

/* Stable identifiers emitted by the nonlinear test so a hardware data set
 * cannot silently mix different home-control behavior. */
const char *Motor_GetHomeControllerProfileId(void);

#ifdef __cplusplus
}
#endif

#endif /* __MOTOR_H */
