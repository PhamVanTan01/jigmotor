/* Build identity for the dedicated 7-pole-pair engineering smoke test.
 *
 * This branch intentionally produces a one-sweep-per-button build. It is not
 * a production/QC profile and must not be used to qualify MA600A accuracy.
 */

#ifndef __TEST_PROFILE_H
#define __TEST_PROFILE_H

#define TEST_PROFILE_ID            "7PP_ENGINEERING_LOCK_ONLY_1RUN_V1"
#define TEST_BUILD_LABEL           "motor-7pp-lock-only-1run-v1"
#define TEST_RESULT_CLASS          "ENGINEERING_ONLY"
#define TEST_APPROACH_PROTOCOL     "LOCK_ONLY_DITHER_V1"
#define TEST_MOTION_PROFILE        "LEGACY_RAMP8_1MS_BRINGUP"

/* MOTOR_NUM_POLSE is the physical pole count, not the pole-pair count. */
#ifndef MOTOR_NUM_POLSE
#define MOTOR_NUM_POLSE            14U
#endif

/* A button edge must execute exactly one sweep. A possible second run is a
 * separate manual button press after the operator-enforced motor-off rest. */
#ifndef TEST_RUNS_PER_BUTTON
#define TEST_RUNS_PER_BUTTON       1U
#endif
#ifndef ENABLE_AUTO_BATCH_TEST
#define ENABLE_AUTO_BATCH_TEST     0
#endif
#ifndef ENABLE_CCW_ENGINEERING_TEST
#define ENABLE_CCW_ENGINEERING_TEST 0
#endif

#endif /* __TEST_PROFILE_H */
