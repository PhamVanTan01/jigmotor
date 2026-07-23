/* Build identity for the dedicated 7-pole-pair B0-B engineering test.
 *
 * This branch intentionally produces a one-sweep-per-button build. It is not
 * a production/QC profile and must not be used to qualify MA600A accuracy.
 */

#ifndef __TEST_PROFILE_H
#define __TEST_PROFILE_H

#define TEST_PROFILE_7PP_ENGINEERING 1
#define TEST_PROFILE_ID            "7PP_ENGINEERING_B0B_REVERSAL_V2_1RUN_V1"
#define TEST_BUILD_LABEL           "motor-7pp-b0b-reversal-v2-1run-v1"
#define TEST_RESULT_CLASS          "ENGINEERING_ONLY"
#define TEST_APPROACH_PROTOCOL     "SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2"
#define TEST_MOTION_PROFILE        "SCURVE40_ABSOLUTE_TICK_V2"
#define TEST_SENSOR_IDENTITY       "MA600_PRODUCTID_0x3C"

/* Register 0x1F is PRODUCTID on the original MA600 and reads 60 decimal
 * (0x3C). On MA600A the same address is RMAPID/SUFFIXID and defaults to
 * 0x00. The 1807/7PP hardware log repeatedly reports 0x3C, so this
 * engineering profile requires that exact identity instead of disabling
 * the configuration gate. */
#define TEST_EXPECTED_MA600_REG_1F 0x3CU

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

/* Motion Control V2 + DMA baseline selected from
 * codex/motion-control-v2-dma. Values match the selectors local to
 * nonlinear_test.c: S-curve V2=2 and reversal approach V2=1. */
#ifndef NL_MOTION_PROFILE
#define NL_MOTION_PROFILE          2
#endif
#ifndef NL_APPROACH_MODE
#define NL_APPROACH_MODE           1
#endif
#ifndef ENABLE_B0B_EQUAL_APPROACH
#define ENABLE_B0B_EQUAL_APPROACH  1
#endif

/* Isolate the equal-approach B0-B protocol. Do not reuse the 6PP-specific
 * 79/126 feedforward bias or combine it with creep/soft-start controls. */
#ifndef ENABLE_SWEEP_RAMP_STEP_DIAG
#define ENABLE_SWEEP_RAMP_STEP_DIAG 1
#endif
#ifndef ENABLE_SWEEP_RAMP_SOFT_START
#define ENABLE_SWEEP_RAMP_SOFT_START 0
#endif
#ifndef ENABLE_B0B_APPROACH_SOFT_START
#define ENABLE_B0B_APPROACH_SOFT_START 0
#endif
#ifndef ENABLE_B0B_APPROACH_CREEP
#define ENABLE_B0B_APPROACH_CREEP  0
#endif
#ifndef ENABLE_B0B_APPROACH_FEEDFORWARD
#define ENABLE_B0B_APPROACH_FEEDFORWARD 0
#endif

#endif /* __TEST_PROFILE_H */
