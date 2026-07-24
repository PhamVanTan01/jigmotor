/* Shared motor geometry used by both the PWM commutator and measurement
 * diagnostics. MOTOR_NUM_POLSE keeps the spelling used by the existing PIXY
 * motor configuration. It is the physical pole count, not pole pairs:
 * 12 poles -> 6 pole pairs. Unlike an operator Motor ID, this value changes
 * the drive waveform and therefore must be correct before a test starts. */

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

#define MOTOR_MECHANICAL_COUNTS_PER_REV       65536U
/* Preserve the existing six-pole-pair mapping while making divisible pole
 * counts exact instead of unconditionally adding one count. A later,
 * separately validated change may replace this lookup-cycle representation
 * with direct Q16 electrical-phase multiplication. */
#define MOTOR_COUNT_PER_ELECTRICAL_CYCLE      \
    ((MOTOR_MECHANICAL_COUNTS_PER_REV + MOTOR_POLE_PAIRS - 1U) / MOTOR_POLE_PAIRS)

/* The dominant drive-related ripple observed with six pole pairs was order
 * 36: six ripple periods per electrical cycle. Keep that interpretation
 * explicit so a motor with another pole-pair count is analyzed at 6*p. */
#define MOTOR_ELECTRICAL_RIPPLE_MULTIPLE      6U
#define MOTOR_ELECTRICAL_RIPPLE_ORDER         \
    (MOTOR_POLE_PAIRS * MOTOR_ELECTRICAL_RIPPLE_MULTIPLE)

#if TEST_PROFILE_7PP_ENGINEERING
#if (MOTOR_NUM_POLSE != 14U) || (MOTOR_POLE_PAIRS != 7U)
#error "7PP engineering profile requires exactly 14 physical poles / 7 pole pairs"
#endif
#if MOTOR_COUNT_PER_ELECTRICAL_CYCLE != 9363U
#error "7PP electrical-cycle mapping must be ceil(65536/7) = 9363 counts"
#endif
#if MOTOR_ELECTRICAL_RIPPLE_ORDER != 42U
#error "7PP diagnostic ripple order must be 6 * 7 = 42"
#endif
#if (TEST_RUNS_PER_BUTTON != 1U) || ENABLE_AUTO_BATCH_TEST
#error "7PP movement smoke profile must run exactly once per button press"
#endif
#if ENABLE_CCW_ENGINEERING_TEST || (NL_MOTION_PROFILE != 2) || \
    (NL_APPROACH_MODE != 3) || !ENABLE_B0B_EQUAL_APPROACH
#error "7PP V3.2 profile requires CW S-curve V2 with shifted-reversal approach"
#endif
#if ENABLE_SWEEP_RAMP_SOFT_START || ENABLE_B0B_APPROACH_SOFT_START || \
    ENABLE_B0B_APPROACH_CREEP || ENABLE_B0B_APPROACH_FEEDFORWARD
#error "7PP V3.2 isolation profile must not enable bias, creep, or soft-start controls"
#endif
#if TEST_EXPECTED_MA600_REG_1F != 0x3CU
#error "7PP 1807 profile requires MA600 PRODUCTID 0x3C at register 0x1F"
#endif
#endif

#endif /* __MOTOR_CONFIG_H */
