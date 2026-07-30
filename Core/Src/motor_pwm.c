#include "motor_pwm.h"
#include "motor_config.h"
#include "main.h"
#include <math.h>
#include <stddef.h>

extern TIM_HandleTypeDef htim1;

#define MOTOR_PHASE_B_OFFSET    (MOTOR_COUNT_PER_ELECTRICAL_CYCLE / 3U)
#define MOTOR_PHASE_C_OFFSET    (MOTOR_COUNT_PER_ELECTRICAL_CYCLE * 2U / 3U)
#define MOTOR_PWM_PERIOD        2154

#ifndef ENABLE_DEADTIME_COMPENSATION_FEEDFORWARD
/* Experimental, default OFF -- "Huong A" open-loop dead-time compensation.
 * Adds a small duty-cycle offset based on the SIGN of the commanded sine
 * value for this phase (a proxy for current direction inferred from the
 * command itself, not a real current measurement) to counteract the
 * systematic distortion dead-time causes near current zero-crossings --
 * see the JIG1-vs-JIG4 no-relay H2 comparison (H2 ratio 128%-398% across
 * P02/P03/P05/P06, far too product-dependent to be a fixed calibration
 * offset -- consistent with a dead-time x per-product-eccentricity
 * interaction). DEADTIME_COMPENSATION_FRACTION is an empirically-swept
 * dimensionless fraction of full duty range, not derived from an absolute
 * timing measurement here -- start small and adjust based on measured H2
 * before/after. Sign convention is UNVERIFIED until tested on real
 * hardware: if H2 gets WORSE instead of closer to the other jig, flip the
 * sign of DEADTIME_COMPENSATION_FRACTION and retest. This does nothing to
 * current sensing or measurement -- it only changes what PWM duty is
 * commanded, exactly like production code, just with this added term. */
#define ENABLE_DEADTIME_COMPENSATION_FEEDFORWARD    0
#endif

#ifndef DEADTIME_COMPENSATION_FRACTION
#define DEADTIME_COMPENSATION_FRACTION    0.01f
#endif

static MotorPwm_CommandState_t lastCommand;

static uint16_t MotorPwm_PhaseValue(uint32_t stepInCycle, float power)
{
    float angleRad = 2.0f * (float)M_PI * (float)stepInCycle
        / (float)MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    float sinValue = sinf(angleRad);
    float duty = (sinValue * 0.5f + 0.5f) * power;

#if ENABLE_DEADTIME_COMPENSATION_FEEDFORWARD
    if (sinValue > 0.0f)
    {
        duty += DEADTIME_COMPENSATION_FRACTION * power;
    }
    else if (sinValue < 0.0f)
    {
        duty -= DEADTIME_COMPENSATION_FRACTION * power;
    }
#endif

    if (duty < 0.0f) duty = 0.0f;
    if (duty > 1.0f) duty = 1.0f;
    return (uint16_t)(duty * (float)MOTOR_PWM_PERIOD);
}

void MotorPwm_Init(void)
{
    MotorPwm_Disable();

    /* Route the winding relays to the PWM-drive path. The GPIO reset state is
     * the resistance-measurement path and cannot drive the motor. */
    HAL_GPIO_WritePin(RL_MODE_PHASE_GPIO_Port, RL_MODE_PHASE_Pin, GPIO_PIN_SET);
    HAL_GPIO_WritePin(RL_ENA_RES_AB_GPIO_Port, RL_ENA_RES_AB_Pin, GPIO_PIN_RESET);
    HAL_GPIO_WritePin(RL_ENA_RES_AC_GPIO_Port, RL_ENA_RES_AC_Pin, GPIO_PIN_RESET);

    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_1);
    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_2);
    HAL_TIM_PWM_Start(&htim1, TIM_CHANNEL_3);
    MotorPwm_ResetCommand();
}

void MotorPwm_Enable(void)
{
    HAL_GPIO_WritePin(MOTOR_ENA_GPIO_Port, MOTOR_ENA_Pin, GPIO_PIN_SET);
    lastCommand.enabled = true;
}

void MotorPwm_Disable(void)
{
    HAL_GPIO_WritePin(MOTOR_ENA_GPIO_Port, MOTOR_ENA_Pin, GPIO_PIN_RESET);
    lastCommand.enabled = false;
}

void MotorPwm_SetElectricalPos(uint16_t pos, float power)
{
    uint32_t stepA = (uint32_t)pos % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    uint32_t stepB = ((uint32_t)pos + MOTOR_PHASE_B_OFFSET)
        % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    uint32_t stepC = ((uint32_t)pos + MOTOR_PHASE_C_OFFSET)
        % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;

    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_1, MotorPwm_PhaseValue(stepA, power));
    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_2, MotorPwm_PhaseValue(stepB, power));
    __HAL_TIM_SetCompare(&htim1, TIM_CHANNEL_3, MotorPwm_PhaseValue(stepC, power));

    lastCommand.electricalPositionRaw = pos;
    lastCommand.power = power;
}

void MotorPwm_ResetCommand(void)
{
    /* The output driver is disabled at every physical-test boundary before
     * this is called. Clearing all compares prevents the next enable from
     * briefly replaying the previous sweep's final phase/power command. */
    MotorPwm_SetElectricalPos(0U, 0.0f);
}

void MotorPwm_GetCommandState(MotorPwm_CommandState_t *outState)
{
    if (outState != NULL)
    {
        *outState = lastCommand;
    }
}
