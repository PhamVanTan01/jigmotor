/* 3-phase sine-commutation motor driver (TIM1 CH1/2/3), plus a simple
 * closed-loop position controller used only to return to a reference angle
 * before a sweep. Motor geometry comes from motor_config.h. */

#include "motor.h"
#include "motor_config.h"
#include "ma600.h"
#include "main.h"
#include <math.h>

extern TIM_HandleTypeDef htim1;

/* One mechanical revolution contains MOTOR_POLE_PAIRS electrical cycles.
 * The bring-up build deliberately preserves the existing integer-cycle
 * modulo mapping; direct-Q16 electrical phase is a separate later trial. */
#define MOTOR_PHASE_B_OFFSET    (MOTOR_COUNT_PER_ELECTRICAL_CYCLE / 3U)
#define MOTOR_PHASE_C_OFFSET    (MOTOR_COUNT_PER_ELECTRICAL_CYCLE * 2U / 3U)

/* Matches jigmotor.ioc's TIM1 Period (SPI1/TIM1 config generated from the
 * .ioc, not something this file owns) -- PWM full-scale compare value. */
#define MOTOR_PWM_PERIOD        2154

/* Starting point was the reference firmware's PM3505 gains (kP=0.5,
 * kI=0.0005, kD=2.0, output clamp=100), which produced real hardware
 * symptoms here: the shaft visibly vibrated but never built up enough net
 * torque to actually rotate toward the target. That combination (weak P,
 * big D on a noisy/oscillating signal, small per-iteration step) is
 * consistent with too little push to overcome static friction/cogging on
 * this specific (lighter, fewer-pole, PM1505) motor -- PM3505's gains were
 * tuned for a mechanically different motor, not a universal constant.
 * First retuning attempt: more P authority, much less D (D was reacting to
 * sample-to-sample oscillation, not damping it), and a bigger max step so
 * each PID iteration commits a large-enough electrical lead angle to
 * actually generate net torque instead of just nudging back and forth. */
/* Second retuning: after fixing the int32_t-truncation bug (see
 * pidCurrentPos below), logs showed genuine convergence but a slow tail --
 * error would plateau for a few seconds around a few tenths of a degree
 * before creeping down. That plateau-then-creep shape is the signature of
 * static friction/cogging: P alone gives a vanishingly small push near zero
 * error, so it's Ki's job to slowly wind up enough command to break through
 * stiction, and 0.0005 was too small to do that quickly. Raised Ki ~6x to
 * cut that wind-up time, and Kp somewhat for a stronger overall pull. */
static float PidKp = 2.0f;
static float PidKi = 0.003f;
static float PidKd = 0.3f;
static const float PidIntegralLimit = 5.0f;
static const float PidOutputMax = 400.0f;

static float pidIntegral = 0.0f;
static float pidLastError = 0.0f;
/* Float, not int32_t: with kP=1.5, any |output| below ~0.667 deg-equivalent
 * truncates to exactly 0 when cast straight to an integer, which silently
 * drops the command whenever the error gets small -- confirmed on real
 * hardware as the PID getting permanently stuck a fraction of a degree
 * short of converging (commanded position frozen bit-for-bit across many
 * seconds while error sat at ~0.4-0.6 deg). Keeping the accumulator in
 * float lets those small outputs actually accumulate across iterations
 * instead of being discarded every time; only Motor_SetElectricalPos()'s
 * uint16_t argument truncates, and only once, at the point it's actually
 * needed for a register write. */
static float pidCurrentPos = 0.0f;

/* Biased sine (0..1 range, not -1..1) scaled by `power`, matching a plain
 * sinusoidal open-loop 3-phase drive: each phase's PWM duty follows a sine
 * wave offset 120 electrical degrees from the others. */
static uint16_t Motor_PhasePwm(uint32_t stepInCycle, float power)
{
    float angleRad = 2.0f * (float)M_PI * (float)stepInCycle /
        (float)MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    float duty = (sinf(angleRad) * 0.5f + 0.5f) * power;

    if (duty < 0.0f) duty = 0.0f;
    if (duty > 1.0f) duty = 1.0f;

    return (uint16_t)(duty * (float)MOTOR_PWM_PERIOD);
}

void Motor_Init(void)
{
    /* This board routes the 3 motor phase wires through relays
     * (RL_MODE_PHASE / RL_ENA_RES_AB / RL_ENA_RES_AC) that the sibling
     * project switches between "PWM drive" and 3 different "measure
     * winding resistance" positions (gremsyRelay.c's relayMode_t). All 3
     * pins default to the RESET state at boot (MX_GPIO_Init()), which
     * matches the *resistance-measurement* wiring, not PWM -- without this,
     * TIM1's PWM output is not actually connected to the motor windings at
     * all, so the shaft never moves no matter what's commanded (this was
     * the root cause of a real hang seen on hardware: PID correctly kept
     * commanding position changes but never saw the angle move, because
     * the motor had no drive path). jigmotor doesn't do a resistance test,
     * so it only ever needs the PWM-drive relay state, set once here. */
    HAL_GPIO_WritePin(RL_MODE_PHASE_GPIO_Port, RL_MODE_PHASE_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(RL_ENA_RES_AB_GPIO_Port, RL_ENA_RES_AB_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RL_ENA_RES_AC_GPIO_Port, RL_ENA_RES_AC_Pin, GPIO_PIN_RESET);

    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_1);
    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_2);
    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_3);
}

void Motor_Enable(void)
{
    HAL_GPIO_WritePin(MOTOR_ENA_GPIO_Port, MOTOR_ENA_Pin, GPIO_PIN_SET);
}

void Motor_Disable(void)
{
    HAL_GPIO_WritePin(MOTOR_ENA_GPIO_Port, MOTOR_ENA_Pin, GPIO_PIN_RESET);
}

void Motor_SetElectricalPos(uint16_t pos, float power)
{
    uint32_t stepA = (uint32_t)pos % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    uint32_t stepB = ((uint32_t)pos + MOTOR_PHASE_B_OFFSET) % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    uint32_t stepC = ((uint32_t)pos + MOTOR_PHASE_C_OFFSET) % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;

    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_1, Motor_PhasePwm(stepA, power));
    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_2, Motor_PhasePwm(stepB, power));
    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_3, Motor_PhasePwm(stepC, power));
}

float Motor_MoveToAngle(float targetDeg)
{
    /* This project has no separate always-on encoder task (unlike the
     * reference firmware, where a dedicated ~1kHz task keeps the multi-turn
     * accumulator fresh in the background) -- jigmotor is single-task, so
     * the PID must pull a fresh SPI reading itself on every call, or it
     * would converge against stale feedback and never actually settle. */
    MA600_UpdateMultiTurn();
    float error = MA600_ReadMultiTurnDegrees() - targetDeg;

    float p = PidKp * error;
    pidIntegral += PidKi * error;
    if (fabsf(pidIntegral) > PidIntegralLimit)
    {
        pidIntegral = 0.0f;
    }
    float d = PidKd * (error - pidLastError);
    pidLastError = error;

    float output = p + pidIntegral + d;
    if (output > PidOutputMax) output = PidOutputMax;
    if (output < -PidOutputMax) output = -PidOutputMax;

    pidCurrentPos -= output;

    /* Two-step cast, not a direct (uint16_t)pidCurrentPos: converting a
     * negative float straight to an unsigned type is undefined behavior in
     * C, unlike int-to-unsigned conversions which wrap predictably. Going
     * through int32_t first (well-defined float truncation, and comfortably
     * in range for the magnitudes this accumulates to) makes the final
     * uint16_t truncation the well-defined modulo-wraparound this code
     * actually relies on. */
    Motor_SetElectricalPos((uint16_t)(int32_t)pidCurrentPos, 1.0f);

    return error;
}

uint16_t Motor_ElectricalOffset(uint16_t rawCount)
{
    return (uint16_t)((uint32_t)rawCount % MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
}

int32_t Motor_GetCommandedPos(void)
{
    return pidCurrentPos;
}

uint16_t Motor_GetPoleCount(void)
{
    return (uint16_t)MOTOR_NUM_POLSE;
}

uint16_t Motor_GetPolePairs(void)
{
    return (uint16_t)MOTOR_POLE_PAIRS;
}

uint16_t Motor_GetElectricalCycleRaw(void)
{
    return (uint16_t)MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
}

uint16_t Motor_GetElectricalRippleOrder(void)
{
    return (uint16_t)MOTOR_ELECTRICAL_RIPPLE_ORDER;
}
