/* Shared motor geometry for PWM commutation and measurement diagnostics. */

#ifndef __MOTOR_CONFIG_H
#define __MOTOR_CONFIG_H

#include "test_profile.h"

#ifndef MOTOR_NUM_POLSE
#define MOTOR_NUM_POLSE 12U
#endif

#if (MOTOR_NUM_POLSE < 2U) || (MOTOR_NUM_POLSE > 128U)
#error "MOTOR_NUM_POLSE must be in the range 2..128"
#endif

#if ((MOTOR_NUM_POLSE % 2U) != 0U)
#error "MOTOR_NUM_POLSE must be even so it forms whole pole pairs"
#endif

#define MOTOR_POLE_PAIRS                       (MOTOR_NUM_POLSE / 2U)
#define MOTOR_MECHANICAL_COUNTS_PER_REV        65536U
#define MOTOR_COUNT_PER_ELECTRICAL_CYCLE       \
    ((MOTOR_MECHANICAL_COUNTS_PER_REV + MOTOR_POLE_PAIRS - 1U) / MOTOR_POLE_PAIRS)
#define MOTOR_ELECTRICAL_RIPPLE_MULTIPLE       6U
#define MOTOR_ELECTRICAL_RIPPLE_ORDER          \
    (MOTOR_POLE_PAIRS * MOTOR_ELECTRICAL_RIPPLE_MULTIPLE)

/* Compile-time contract for this branch's dedicated 7PP profile. */
#if (MOTOR_NUM_POLSE != 14U)
#error "7PP engineering profile requires 14 physical poles"
#endif

#if (MOTOR_POLE_PAIRS != 7U)
#error "7PP engineering profile requires 7 pole pairs"
#endif

#if (MOTOR_COUNT_PER_ELECTRICAL_CYCLE != 9363U)
#error "7PP integer electrical cycle must be 9363 raw counts"
#endif

#if (MOTOR_ELECTRICAL_RIPPLE_ORDER != 42U)
#error "7PP electrical ripple order must be 42"
#endif

#endif /* __MOTOR_CONFIG_H */
