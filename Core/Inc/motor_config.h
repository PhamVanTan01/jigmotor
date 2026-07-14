/* Shared motor geometry used by both the PWM commutator and measurement
 * diagnostics. MOTOR_NUM_POLSE keeps the spelling used by the existing PIXY
 * motor configuration. It is the physical pole count, not pole pairs:
 * 12 poles -> 6 pole pairs. Unlike an operator Motor ID, this value changes
 * the drive waveform and therefore must be correct before a test starts. */

#ifndef __MOTOR_CONFIG_H
#define __MOTOR_CONFIG_H

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

#endif /* __MOTOR_CONFIG_H */
