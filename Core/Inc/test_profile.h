/* Build identity for the dedicated 7-pole-pair V3.2 engineering test.
 *
 * This branch intentionally produces a one-sweep-per-button build. It is not
 * a production/QC profile and must not be used to qualify MA600A accuracy.
 */

#ifndef __TEST_PROFILE_H
#define __TEST_PROFILE_H

#define TEST_PROFILE_7PP_ENGINEERING 1
#define TEST_PROFILE_ID            "7PP_STUTTER_DIAG_P135_160_1RUN_V1"
#define TEST_BUILD_LABEL           "motor-7pp-stutter-diag-p135-160-1run-v1"
#define TEST_RESULT_CLASS          "ENGINEERING_ONLY"
#define TEST_APPROACH_PROTOCOL     "SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2"
#define TEST_MOTION_PROFILE        "SCURVE40_ABSOLUTE_TICK_V2"
#define TEST_SENSOR_IDENTITY       "UID_LOCKED_MA600_VARIANT_V1"
#define TEST_SENSOR_REG_1F_POLICY  "PER_JIG_PROFILE"

/* Register 0x1F is PRODUCTID on the original MA600 and reads 60 decimal
 * (0x3C). On MA600A the same address is RMAPID/SUFFIXID and defaults to
 * 0x00. JIG1/JIG2 retain the original-MA600 expectation. JIG3 sensor
 * revision 2 (replaced 2026-07-24) and JIG4 are explicitly locked to the
 * MA600A value observed on their own UIDs. This supports both sensor variants
 * without weakening the per-jig configuration gate. */
#define TEST_EXPECTED_MA600_REG_1F_MA600  0x3CU
#define TEST_EXPECTED_MA600_REG_1F_MA600A 0x00U

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

/* Motion Control V2 + DMA with V3.2 shifted reversal generalized to the
 * 7PP raw electrical cycle: S-curve V2=2, shifted-reversal mode=3. */
#ifndef NL_MOTION_PROFILE
#define NL_MOTION_PROFILE          2
#endif
#ifndef NL_APPROACH_MODE
#define NL_APPROACH_MODE           3
#endif
#ifndef ENABLE_B0B_EQUAL_APPROACH
#define ENABLE_B0B_EQUAL_APPROACH  1
#endif

/* Isolate V3.2 geometry. Do not reuse the 6PP-specific 79/126 feedforward
 * bias or combine it with creep/soft-start controls. */
#ifndef ENABLE_SWEEP_RAMP_STEP_DIAG
#define ENABLE_SWEEP_RAMP_STEP_DIAG 1
#endif
/* P7-AB1 is observation-only. It records every S-curve tick and settle poll
 * for points 135..160 into bounded CCM RAM, then prints the records only
 * after Motor_Disable(). It must not alter any motion or settle constant. */
#ifndef ENABLE_7PP_STUTTER_TRACE
#define ENABLE_7PP_STUTTER_TRACE   1
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
