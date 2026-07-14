/* End-of-shaft mounting nonlinear sweep test (docs/end-of-shaft-mounting-test-plan.md
 * Part B). Blocking; prints the result over USART3 in a format
 * scripts/analyze_nonlinear_logs.ps1 already knows how to parse.
 *
 * Schema v2 addition: alongside the original single-number "Nonlinear N Angle" metric
 * (kept byte-for-byte, see NlSweepStats_t/ComputeSweepStats), this now also computes and
 * logs a broader per-test feature set (mean-removed RMS, harmonic 1/2/3/6/12/18 amplitude+
 * phase, two residual-RMS variants, a dense-grid fitted peak-to-peak, crest factor, P99,
 * and a full raw per-point curve) in new META/DATA/RESULT/END lines, for building an
 * offline dataset (golden template, Mahalanobis/PCA, etc. -- explicitly NOT computed here).
 * All new logging is deferred until after Motor_Disable() so it can never perturb the
 * sweep's motion/settle timing -- see the note above CaptureSweep().
 *
 * Terminology note (per a MA600A Rev. 1.0 datasheet review): this jig has NO independent
 * reference encoder -- the only "ground truth" available is the commanded open-loop step
 * position. Every nonlinear/INL-style number this file produces (including
 * Motor_System_INL_Deg/Motor_Error_P2P_Deg below) therefore measures the WHOLE system --
 * motor + magnet + mounting + jig + MA600A combined -- not the MA600A sensor in isolation.
 * It must never be compared directly against the datasheet's own INL spec (<=0.6 deg
 * uncalibrated / <=0.1 deg after user calibration): that spec only applies to a proper
 * "jig qualification" setup with an independent precision reference encoder, which this
 * hardware does not have. */

#include "nonlinear_test.h"
#include "motor.h"
#include "motor_config.h"
#include "ma600.h"
#include "ma600_acquisition.h"
#include "main.h"
#include "cmsis_os.h"
#include "FreeRTOS.h"
#include "task.h"
#include <math.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdbool.h>
#include <string.h>

extern UART_HandleTypeDef huart3;

#define NL_ENGINE_COMMAND_START 1U

static osMessageQueueId_t nlEngineCommandQueue;
static osThreadId_t nlEngineTaskHandle;
static volatile bool nlEngineBusy;
static volatile NonlinearEngineState_t nlEngineState = NL_ENGINE_IDLE;

static void SetEngineState(NonlinearEngineState_t state)
{
    nlEngineState = state;
}

/* Was 2 runs (discarding run 1, keeping run 2) matching the reference
 * firmware's convention. Changed to a single run per the user's request --
 * two full 370 deg open-loop sweeps back to back was extending motor-on
 * time and visibly heating the motor for no benefit once the measurement
 * was already shown to be highly repeatable run-to-run (~3.6-3.8 deg
 * across several independent full tests). */
#define NL_TEST_COUNT               1
#define NL_SKIP_FIRST_COUNT         0
#define NL_USED_COUNT               (NL_TEST_COUNT - NL_SKIP_FIRST_COUNT)
#define NL_SWEEP_ANGLE_DEG          370.0f
/* Was dropped 256 -> 64 (4x finer grid) as a grid-quantization experiment:
 * real jig1/jig2 data on 2 products showed the finer grid did NOT shrink the
 * jig-to-jig gap in "NL raw peak-to-peak" -- if anything it got worse
 * (avg 0.06 -> 0.37 deg). That rules out grid quantization as the dominant
 * cause and points at genuine rotor-to-jig mounting phase difference
 * instead (confirmed independently by the harmonic1 phase differing ~19.5
 * deg between jigs while harmonic6/cogging phase agreed to ~1 deg). Reverted
 * to 256 since the finer grid bought nothing but 2x sweep time (more motor
 * heat, the original concern that motivated smoothing this sweep at all). */
#define NL_POS_INCREASE             256
/* Each sweep point used to be one big jump followed by a static hold --
 * visibly jerky/choppy rotation. Now ramped smoothly in NL_RAMP_STEP-sized
 * micro-steps (see the ramp loop below) instead of one hard jump, which is
 * both smoother motion and, by avoiding a sudden step-and-stop at every
 * point, likely gentler on motor heating too. */
#define NL_RAMP_STEP                8
#define NL_RAMP_STEP_DELAY_MS       1
/* Was 20 -- per a MA600A datasheet review, per-position averaging should be as large as
 * practical since it's effectively free here: CaptureSweep()'s sampling loop has no
 * inter-sample delay (already tested and confirmed not to matter, see the comment there), so
 * more samples just means more back-to-back SPI reads, not more wall-clock time. Kept
 * NL_POS_INCREASE (N=256) unchanged -- raising N reintroduces the RAM/motor-time risk this
 * project has hit before; a bigger K is the low-risk half of that N/K tradeoff. */
#define NL_SAMPLES_PER_POINT        64
/* Every Nth sweep point gets a "NL curve" log line -- back to 4 (~66 lines,
 * ~5.6 deg/logged point) now that NL_POS_INCREASE is back to 256 (~264
 * points total; was temporarily 16 during the NL_POS_INCREASE=64
 * experiment). This decimated line is for quick visual inspection only --
 * the full-resolution "DATA" lines (see PrintSweepLog) carry every point. */
#define NL_CURVE_LOG_DECIMATION     4
/* Replaces the old fixed NL_SETTLE_MS delay (tried 5ms, then 50ms as an
 * experiment -- neither changed the underlying result much, because a fixed
 * wait doesn't actually know whether the shaft has settled, it just hopes
 * the time was enough). This was flagged as a real methodology gap: sampling
 * on a timer instead of on the actual measured angle means two jigs with
 * different friction/stiffness/damping can genuinely be at different
 * positions when the timer fires, even after commanding the identical
 * target. Now each point waits for the encoder's own reading to stop
 * changing (see WaitForPointSettle) instead of a blind delay. */
#define NL_POINT_SETTLE_ERROR_RAW   9LL    /* 9 raw counts = 0.04944 deg. */
#define NL_POINT_SETTLE_CONSECUTIVE 8      /* consecutive settled polls required. */
#define NL_POINT_SETTLE_POLL_MS     1      /* polling period while waiting. */
#define NL_POINT_SETTLE_TIMEOUT_MS  100    /* give up and sample anyway past this -- see the
                                             * per-sweep "did not settle" count logged at the end. */
/* Pilot motion-integrity envelope, not a product-quality limit. Historical
 * healthy tracking maxima are about 1.5..3.4 deg; five degrees detects a
 * stable-but-clearly-wrong rotor without filtering the nonlinear curve we
 * are trying to measure. Point 0 defines the sweep reference and therefore
 * requires stability but has zero target error by definition. */
#define NL_SETTLE_TARGET_TOLERANCE_RAW  910LL /* 4.99878 deg. */
#define NL_SETTLE_CONTRACT_ID           "STABILITY_AND_TARGET_V1"
#define NL_CONTINUOUS_CONTEXT_ID        "SWEEP_CONTEXT_V1"
/* Was loosened to 0.15/10s at one point to work around a since-fixed PID
 * bug (pidCurrentPos truncating small outputs to 0 and stalling -- see
 * motor.c). With that fixed and Ki raised so the integral term breaks
 * through stiction faster (see motor.c's PidKi comment), tightened back to
 * 0.10 deg per the user's request; NL_MOVE_ZERO_TIMEOUT_MS below stays at
 * 20s as headroom in case a run still needs the extra margin. */
#define NL_MOVE_ZERO_ERROR_DEG      0.10f
#define NL_MOVE_ZERO_SETTLE_TICKS   500
#define NL_MOVE_ZERO_TIMEOUT_MS     20000
#define NL_MOVE_ZERO_DIAG_INTERVAL_MS 500
/* Caps the move-to-zero PID loop to ~500Hz -- see the comment at its
 * osDelay() call site for why this is required, not just a nice-to-have. */
#define NL_MOVE_ZERO_LOOP_DELAY_MS  2
#define NL_ACQ_MAX_ATTEMPTS         3U
#define NL_SETTLE_MAX_JUMP_RAW      1821
#define NL_SWEEP_MAX_JUMP_RAW       1821
/* Phase-2B shadow sampler. Legacy schema-v5 DATA/ACQ/RESULT remain official;
 * these limits apply only to the non-official CANONICAL_Q16_V1 capture made
 * at the same settled point. The point sampler aborts when consecutive
 * failures exceed maxConsecutiveFailures, so 2 means the third consecutive
 * failure aborts, matching the legacy three-attempt failure boundary. */
#define NL_SHADOW_POINT_MAX_TRANSACTIONS          96U
#define NL_SHADOW_POINT_MAX_CONSECUTIVE_FAILURES  2U
#define NL_SHADOW_POINT_MAX_ELAPSED_US             20000U
#define NL_SHADOW_CONTRACT_ID                      "CANONICAL_Q16_V1"
#define NL_SHADOW_SIGN_CONVENTION                  "MEASURED_MINUS_TARGET"
#define NL_SHADOW_REFERENCE_DEFINITION             "POINT0_CANONICAL_MEAN"
#define NL_SHADOW_CANONICAL_MEAN_SOURCE            "ALL_TIER1"
#define NL_SHADOW_CLOSURE_LIMIT_DEG                 0.20f
/* Phase-3B0-A passive closure hold probe. It never changes the command or
 * power at Point 256 and its numeric result is diagnostic-only. The extra
 * 200 ms dwell intentionally makes points after the first turn timing-
 * incomparable with older sweeps, so that fact is explicit in the log. */
#ifndef ENABLE_CLOSURE_HOLD_PROBE
#define ENABLE_CLOSURE_HOLD_PROBE                    1
#endif
#define NL_CLOSURE_PROBE_PROTOCOL_ID                 "CLOSURE_HOLD_V1"
#define NL_CLOSURE_PROBE_STAGE_COUNT                 4U
/* Phase-3B0-R isolated experiment: every physical test starts its closed-loop
 * home from the same zeroed controller and PID-acquisition state. Gains,
 * ramp, dither, open-loop sweep, settle, and encoder math remain unchanged so
 * reset-vs-persistent state is the only intentional experimental factor. */
#define NL_CONTROLLER_STATE_POLICY_ID                "RESET_BEFORE_EACH_HOME_V1"
#define NL_CLOSURE_POINT_INDEX                       \
    (MOTOR_MECHANICAL_COUNTS_PER_REV / NL_POS_INCREASE)
#if (MOTOR_MECHANICAL_COUNTS_PER_REV % NL_POS_INCREASE) != 0
#error "Closure probe requires an integer full-turn point index"
#endif
/* Gross motion-integrity guards, not product-quality thresholds. Normal JIG1/P03
 * baselines are about 1.1 deg RMS / 2.4 deg max, while the known stalled JIG2
 * regression is 102 deg RMS / 180 deg max. These deliberately wide limits only
 * prevent a lost/stalled rotor from being reported as a valid nonlinear sweep. */
#define NL_TRACKING_RMS_VALID_DEG   15.0f
#define NL_TRACKING_MAX_VALID_DEG   30.0f
#define NL_TRACKING_RMS_LIMIT_TEXT  "15.0"
#define NL_TRACKING_MAX_LIMIT_TEXT  "30.0"
#define NL_CHECK_DIR_ANGLE_DEG      90.0f
#define NL_DITHER_START_POS         20
#define NL_DITHER_SETTLE_MS         200
#define NL_FULL_TURN_RAW            65536.0f
/* A single-sample max/min ("peak-to-peak") is fragile: one noisy point
 * anywhere in the sweep sets the whole result, and jig-to-jig differences in
 * exactly which point that is (SPI/EMI noise, not a real mounting
 * difference) could look like a real jig-to-jig gap. Averaging the
 * top/bottom NL_ROBUST_EXTREME_COUNT points instead is far less sensitive
 * to any single outlier while still capturing genuine, repeated excursions
 * (the real cogging pattern already showed multiple points near -2 deg, not
 * just one, so this shouldn't mask a real effect) -- though real data since
 * showed raw peak-to-peak actually correlating better jig-to-jig than this
 * averaged version, so both are logged and compared rather than assuming
 * either is right. NL_MAX_SWEEP_POINTS is a generous upper bound on how many
 * points a run can have at the current NL_POS_INCREASE=256 (370/(360*256/65536)
 * ~= 264 points) -- was temporarily raised 300->1100 alongside a since-reverted
 * NL_POS_INCREASE=64 grid-resolution experiment, but that 1100 was never put back down
 * when NL_POS_INCREASE reverted to 256. Left oversized 4x, this only cost a harmless
 * ~4.4KB of static RAM for the single float errorSamples[] array that existed back then --
 * but schema v2's NlSweepCapture_t (see below) holds 3 such arrays per capture, and with
 * ENABLE_CCW_ENGINEERING_TEST doubling the capture count, the same 4x oversizing overflowed
 * this MCU's RAM at link time. Restored to 300 (comfortable margin over the ~264 actually
 * used today) now that NL_POS_INCREASE is back to 256 too. */
#define NL_ROBUST_EXTREME_COUNT     5
#define NL_MAX_SWEEP_POINTS         300

/* --- Schema v2 additions: all overridable via a build define without editing source. ---
 * v2->v3 (rejected, see below) attempted to redefine Residual_RMS_Full/Fitted_P2P/
 * FitExplainedRatio in place to mean "computed against the 12-harmonic set" while keeping the
 * v2 field names -- a real hardware run showed harmonic 36 (not 6) dominates this curve by
 * ~15x (see NL_HARMONIC_ORDERS), which motivated adding the wider harmonic set, but silently
 * changing what an existing field name means (distinguishable only by checking SchemaVersion)
 * is exactly the kind of silent-meaning-change this project has repeatedly rejected elsewhere
 * (e.g. "Nonlinear N Angle" never changed meaning either). v3->v4 fixes that: legacy fields
 * are restored to their v2 meaning (6-harmonic set {1,2,3,6,12,18}), and the 12-harmonic
 * results get their own distinctly-named `_Extended` fields (see ComputeModelMetricsByOrders/
 * NL_LEGACY_HARMONIC_ORDERS) -- no v3 log is known to exist outside this development session,
 * so v3 is simply retired rather than migrated. */
#ifndef NL_LOG_SCHEMA_VERSION
#define NL_LOG_SCHEMA_VERSION       5
#endif
#ifndef NL_FIT_EVAL_POINTS
/* Grid used only to reconstruct Fitted_P2P/Fitted_P2P_Extended (see
 * ComputeFittedMinMaxDenseByOrders) -- deliberately independent of, and much denser than, the
 * ~256-point measurement grid (1.40625 deg/step), so the fitted curve's true peak isn't
 * quantized away by the measurement step size. Convergence was checked directly (not guessed)
 * against real hardware data: reconstructing the same 12-harmonic coefficients at increasing
 * grid density and comparing to a 16384-point reference gave 1024 pts -> 0.0047 deg off (just
 * inside a <0.005 deg target, but with thin margin), 4096 pts -> 0.00008 deg off (essentially
 * converged). Chose 4096 for real margin; the extra trig evaluations are still cheap on a
 * 168MHz Cortex-M4 (FeatureComputeTimeMs logs the actual cost per run if this ever needs
 * revisiting). */
#define NL_FIT_EVAL_POINTS          4096
#endif
/* Jig identity is resolved automatically from MCU_UID (see ResolveJigId/NL_KNOWN_JIGS below),
 * not a compile-time JIG_ID define -- the same binary self-identifies on every known jig. For
 * a board not yet added to NL_KNOWN_JIGS, pass -DFORCE_JIG_ID=\"JIG3\" (etc.) at build time as
 * an explicit opt-in override; there is deliberately no silent default like the old "JIG1"
 * fallback used to be. */
#ifdef MOTOR_ID
#define NL_MOTOR_ID_SOURCE          "BUILD_DEFINE"
#else
/* No input mechanism exists on this board (one button, no keypad/display) to enter a real
 * Motor ID -- left as a placeholder; the operator identifies the motor via the saved log
 * file's name, same convention scripts/analyze_nonlinear_logs.ps1's Get-SourceMetadata
 * already uses for Jig/Product. A SET_MOTOR_ID UART command is a reasonable future addition,
 * out of scope here. */
#define MOTOR_ID                    "UNKNOWN"
#define NL_MOTOR_ID_SOURCE          "UNSET"
#endif
#ifndef FIRMWARE_VERSION
#define FIRMWARE_VERSION            "jigmotor-nl2"
#endif
#define FIRMWARE_BUILD_ID           (__DATE__ " " __TIME__)

/* This jig has no independent reference encoder. The measured curve is the
 * response of the complete motor/magnet/mounting/drive/sensor system, so the
 * MA600A datasheet's sensor-only INL limit is not a valid acceptance gate.
 * Keep this policy version in every META line so offline datasets cannot
 * silently mix results produced under different acceptance semantics. */
#define NL_MEASUREMENT_POLICY_ID    "WHOLE_SYSTEM_REPORT_ONLY_V1"
#define NL_MEASUREMENT_DEFINITION   "WHOLE_SYSTEM_COMMAND_TRACKING"
#define NL_ACCEPTANCE_MODE          "REPORT_ONLY"

/* STM32F405's 96-bit factory-programmed Unique Device ID. Combined with TestID/SweepID (both
 * reset to 0 on every reboot -- see nlTestIdCounter/nlSweepIdCounter) this is what actually
 * makes a (TestID, SweepID) pair unique across different power-up sessions/log files, not
 * TestID/SweepID alone. */
#define MCU_UID_WORD0                (*(volatile uint32_t *)0x1FFF7A10UL)
#define MCU_UID_WORD1                (*(volatile uint32_t *)0x1FFF7A14UL)
#define MCU_UID_WORD2                (*(volatile uint32_t *)0x1FFF7A18UL)

/* Lets the exact same compiled binary self-identify on whichever physical jig it's running on,
 * instead of needing a separate build per board with a hand-edited JIG_ID. Add a row here for
 * each new jig (grab its MCU_UID from any META line it has already logged). JIG1/JIG2 words
 * 1-2 are identical (same manufacturing lot -- the STM32F405's UID packs wafer X/Y position
 * in word0 and lot number in words 1-2, so boards from one batch commonly share words 1-2 and
 * differ only in word0); comparing all 3 words anyway costs nothing and stays correct for a
 * jig from a different lot such as JIG3. */
typedef struct
{
    uint32_t uid0, uid1, uid2;
    const char *jigId;
    MA600_ExpectedConfig_t expectedConfig;
} NlKnownJig_t;

static const NlKnownJig_t NL_KNOWN_JIGS[] = {
    {
        0x003C0027, 0x32344704, 0x38353535, "JIG1",
        { 0x0000, 0x00, 0x05, 0x00, 0x00, 0x00, 0x190A55AD }
    }, /* MCU_UID=003C00273234470438353535 */
    {
        0x0025002C, 0x32344704, 0x38353535, "JIG2",
        { 0x0000, 0x00, 0x05, 0x00, 0x00, 0x00, 0x190A55AD }
    }, /* MCU_UID=0025002C3234470438353535 */
    {
        0x004C003A, 0x3034510B, 0x31363339, "JIG3",
        { 0x0000, 0x00, 0x05, 0x00, 0x00, 0x00, 0x190A55AD }
    }, /* MCU_UID=004C003A3034510B31363339 */
};

static const NlKnownJig_t *FindKnownJigByUid(void)
{
    uint32_t uid0 = MCU_UID_WORD0;
    uint32_t uid1 = MCU_UID_WORD1;
    uint32_t uid2 = MCU_UID_WORD2;
    for (size_t i = 0; i < sizeof(NL_KNOWN_JIGS) / sizeof(NL_KNOWN_JIGS[0]); i++)
    {
        if (NL_KNOWN_JIGS[i].uid0 == uid0
            && NL_KNOWN_JIGS[i].uid1 == uid1
            && NL_KNOWN_JIGS[i].uid2 == uid2)
        {
            return &NL_KNOWN_JIGS[i];
        }
    }
    return NULL;
}

/* Deliberately does NOT fall back to "JIG1" (or any other guess) for an unrecognized UID --
 * silently mislabeling a new/unknown board as an existing one corrupts a dataset without any
 * visible error. Returns "UNKNOWN_JIG" plus *outKnown=false instead, so it's obviously wrong
 * in the log rather than plausibly wrong. FORCE_JIG_ID is an explicit escape hatch for a board
 * not yet added to the table above (e.g. bringing up a third jig) -- opt-in only, never the
 * default. */
static const char *ResolveJigId(bool *outKnown)
{
#ifdef FORCE_JIG_ID
    *outKnown = true;
    return FORCE_JIG_ID;
#else
    const NlKnownJig_t *knownJig = FindKnownJigByUid();
    if (knownJig != NULL)
    {
        *outKnown = true;
        return knownJig->jigId;
    }
    *outKnown = false;
    return "UNKNOWN_JIG";
#endif
}

#ifndef ENABLE_CCW_ENGINEERING_TEST
/* Architecture is ready (see NlSweepDirection_t/CaptureSweep) but CCW is NOT production-
 * verified: doubling sweep time doubles motor heat and introduces an unvalidated
 * error-sign/encoder-unwrap path (see the comment on NlSweepDirection_t). Keep at 0 unless
 * deliberately running a hardware validation session. */
#define ENABLE_CCW_ENGINEERING_TEST 0
#endif
#define NL_MAX_SWEEPS_PER_TEST      (NL_TEST_COUNT * (1 + ENABLE_CCW_ENGINEERING_TEST))

#ifndef ENABLE_NL_MATH_SELF_TEST
/* When 1, NonlinearTest_Run() skips the motor entirely and instead runs synthetic curves
 * with known closed-form answers through the real feature-computation functions (see
 * RunNlMathSelfTest) -- a one-time build-time check that ComputeHarmonicFull/
 * ComputeResidualRms/ComputeFittedMinMaxDense/FormatDegN are bug-free in C, not just correct
 * on paper (the formulas themselves were cross-checked separately in
 * scripts or scratch tooling outside this repo before being written here). Leave at 0. */
#define ENABLE_NL_MATH_SELF_TEST    0
#endif

/* Real hardware data (test jig 1.txt/test jig 2.txt) showed RMS_AC/A36 trending down across
 * consecutive TestIDs on both jigs -- a plausible sign of accumulated motor heat, with the
 * rest interval between runs so far only controlled by the operator's own timing (uneven,
 * unmeasured). This runs a fixed number of tests back-to-back from a single button press with
 * a firmware-timed rest between them, so jig-to-jig comparisons aren't confounded by however
 * long the operator happened to wait. This is COOLDOWN-TIME control, not temperature control
 * -- there is no thermal sensor on this hardware, so "the motor reached the same temperature"
 * is never actually verified, only "the same rest interval elapsed every time". This flag is
 * deliberately enabled for the current one-precondition plus ten-official-run hardware
 * experiment; disable it again when returning to single-press production behavior. */
#ifndef ENABLE_AUTO_BATCH_TEST
#define ENABLE_AUTO_BATCH_TEST      1
#endif

#if ENABLE_AUTO_BATCH_TEST
/* NL_TEST_REPEAT_1_RUN: batch completes after exactly one run, never entering
 * NL_BATCH_COOLDOWN -- for a remount study where the ~120s rest happens manually, between
 * button presses, while the operator physically removes/reinstalls the motor. Under this
 * mode BatchID (see nlBatchIdCounter below) already doubles as the mount-cycle ID: every
 * fresh button press is a new BatchID, and by protocol the operator only presses after a
 * completed remount, so no separate MountCycle field is needed. */
#ifndef NL_TEST_REPEAT_1_RUN
#define NL_TEST_REPEAT_1_RUN        0
#endif
#ifndef NL_TEST_REPEAT_3_RUNS
#define NL_TEST_REPEAT_3_RUNS       0
#endif
#ifndef NL_TEST_REPEAT_10_RUNS
#define NL_TEST_REPEAT_10_RUNS      1
#endif
#if ((NL_TEST_REPEAT_1_RUN + NL_TEST_REPEAT_3_RUNS + NL_TEST_REPEAT_10_RUNS) != 1)
#error "Enable exactly one test mode: NL_TEST_REPEAT_1_RUN, NL_TEST_REPEAT_3_RUNS, or NL_TEST_REPEAT_10_RUNS"
#endif
#if NL_TEST_REPEAT_1_RUN
#define NL_BATCH_RUN_COUNT          1U
#elif NL_TEST_REPEAT_3_RUNS
#define NL_BATCH_RUN_COUNT          3U
#else
#define NL_BATCH_RUN_COUNT          10U
#endif

/* Placeholder value -- not derived from any measurement yet. The right rest interval should
 * come from a T-sweep study (rerun the same motor/jig at several rest intervals -- 1, 3, 5, 8,
 * 12, 20 min -- and see where RMS_AC/A36 stop changing), which is an offline/operational task,
 * not something to guess into firmware. */
#ifndef NL_COOLDOWN_TIME_MS
#define NL_COOLDOWN_TIME_MS         (2UL * 60UL * 1000UL)
#endif
/* Bounded by the ~200ms StartDefaultTask poll period (see NonlinearBatch_Poll) plus whatever
 * that loop iteration's other work costs (heartbeat toggle, one SPI read, a couple of short
 * UART transmits) -- all sub-millisecond to a few ms, so overshoot should almost always land
 * well under 200ms; a cooldown reported invalid here is a real signal worth looking at, not
 * expected noise. */
#define NL_COOLDOWN_TOLERANCE_MS    300UL
#define NL_THERMAL_PROTOCOL_ID      "COOLDOWN_120S_V1"

/* Experimental repeatability protocol requested for the fixed-jig study:
 *   cycle 1  = one exact full sweep used only to precondition the motor/system;
 *   120 s motor-off cooldown;
 *   cycles 2..11 = ten official runs, also separated by the same 120 s cooldown.
 * The precondition sweep is deliberately captured and logged for audit, but its RunOrder is
 * zero, EligibleForStatistics is zero, and it cannot emit the legacy final average/Motor OK.
 * A failed precondition aborts the batch before official RunOrder 1. This is a controlled
 * time/energy history, not measured temperature control: no temperature sensor is fitted. */
#define NL_PRECONDITION_COUNT               1U
#define NL_OFFICIAL_RUN_COUNT               NL_BATCH_RUN_COUNT
#define NL_BATCH_TOTAL_CYCLE_COUNT          (NL_PRECONDITION_COUNT + NL_OFFICIAL_RUN_COUNT)
#define NL_PRECONDITION_PROTOCOL_ID         "ONE_FULL_SWEEP_120S_V1"
#if (NL_BATCH_RUN_COUNT != 10U)
#error "ONE_FULL_SWEEP_120S_V1 requires the 10-run batch mode"
#endif
#endif /* ENABLE_AUTO_BATCH_TEST */

static void LogLine(const char *fmt, ...)
    __attribute__((format(printf, 1, 2)));
static void LogLineLarge(const char *fmt, ...)
    __attribute__((format(printf, 1, 2)));

static void LogLine(const char *fmt, ...)
{
    char buf[128];
    va_list args;
    va_start(args, fmt);
    int len = vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    if (len > 0)
    {
        if ((size_t)len >= sizeof(buf))
        {
            len = (int)sizeof(buf) - 1;
        }
        HAL_UART_Transmit(&huart3, (uint8_t *)buf, (uint16_t)len, 100);
    }
}

/* Only for the composite META/RESULT/END lines, which carry far more fields than LogLine's
 * 128-byte buffer can hold -- RESULT alone is pushing 1300+ bytes now that it carries both the
 * legacy (6-harmonic) and extended (12-harmonic) model fields plus ModelId/Orders/Valid and
 * PhaseValidMask (was 768, sized for the original single 6-harmonic RESULT line). Used
 * exclusively from PrintSweepLog(), which only ever runs after the motor has stopped (see
 * CaptureSweep's header comment). PrintSweepLog and this helper do share a call chain, so
 * the dedicated test task is sized from compiler stack-usage reports with explicit margin. */
static void LogLineLarge(const char *fmt, ...)
{
    char buf[1900];
    va_list args;
    va_start(args, fmt);
    int len = vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    if (len > 0)
    {
        if ((size_t)len >= sizeof(buf))
        {
            len = (int)sizeof(buf) - 1;
        }
        HAL_UART_Transmit(&huart3, (uint8_t *)buf, (uint16_t)len, 200);
    }
}

/* Fixed-point "%.2f"-equivalent formatting: this project links
 * --specs=nano.specs (newlib-nano), which strips floating-point support out
 * of *printf by default, so building the string with a real "%f" would not
 * print correctly (same fix already applied in main.c). */
static void FormatDeg2(float value, char *out, size_t outSize)
{
    /* Fixed on real hardware data: the previous integer-division approach
     * (whole = hundredths/100) silently dropped the sign whenever the magnitude was under
     * 1.0 -- e.g. -0.01456 rounded to hundredths=-1, but -1/100 truncates to whole=0 in C,
     * and the remainder's sign was discarded next, printing "0.01" instead of "-0.01". Seen
     * directly on hardware: a DATA line reported error=-0.01456 for the same point schema
     * v2's "NL curve" line (this function) printed as error=0.01 deg. Handles sign explicitly
     * instead of relying on the sign surviving integer division. */
    bool negative = (value < 0.0f);
    float absValue = negative ? -value : value;
    int32_t hundredths = (int32_t)(absValue * 100.0f + 0.5f);
    int32_t whole = hundredths / 100;
    int32_t frac = hundredths % 100;

    if (negative && (whole != 0 || frac != 0))
    {
        snprintf(out, outSize, "-%ld.%02ld", (long)whole, (long)frac);
    }
    else
    {
        snprintf(out, outSize, "%ld.%02ld", (long)whole, (long)frac);
    }
}

/* Same fixed-point idea as FormatDeg2, generalized to a caller-chosen decimal count (schema
 * v2 fields use 4-5 digits -- repeatability observed so far is only ~0.02-0.05 deg, which
 * FormatDeg2's 2 digits would quantize away). Unlike FormatDeg2, this explicitly handles the
 * case where the value rounds to a magnitude under 1.0 but is still negative (e.g. -0.05):
 * FormatDeg2's integer-division approach silently loses the sign there (whole==0, and the
 * remainder's sign is discarded); worth doing correctly here since phase and per-point
 * NLValue fields are routinely small and negative. */
static void FormatDegN(float value, int decimals, char *out, size_t outSize)
{
    int32_t scale = 1;
    for (int i = 0; i < decimals; i++)
    {
        scale *= 10;
    }

    bool negative = (value < 0.0f);
    float absValue = negative ? -value : value;
    int32_t scaledInt = (int32_t)(absValue * (float)scale + 0.5f);
    int32_t whole = scaledInt / scale;
    int32_t frac = scaledInt % scale;

    if (negative && (whole != 0 || frac != 0))
    {
        snprintf(out, outSize, "-%ld.%0*ld", (long)whole, decimals, (long)frac);
    }
    else
    {
        snprintf(out, outSize, "%ld.%0*ld", (long)whole, decimals, (long)frac);
    }
}

/* newlib-nano does not reliably provide every long-long printf variant used
 * by full newlib. Keep exact signed Q16 values auditable without adding a
 * linker feature or converting them through float. */
static void FormatI64(int64_t value, char *out, size_t outSize)
{
    if (out == NULL || outSize == 0U)
    {
        return;
    }

    char reverse[24];
    size_t count = 0U;
    bool negative = value < 0;
    uint64_t magnitude = negative
        ? (uint64_t)(-(value + 1)) + 1U
        : (uint64_t)value;

    do
    {
        reverse[count++] = (char)('0' + (magnitude % 10U));
        magnitude /= 10U;
    } while (magnitude != 0U && count < sizeof(reverse) - 1U);

    if (negative && count < sizeof(reverse) - 1U)
    {
        reverse[count++] = '-';
    }

    size_t written = 0U;
    while (count > 0U && written + 1U < outSize)
    {
        out[written++] = reverse[--count];
    }
    out[written] = '\0';
}

static float ShadowRawQ16ToDegrees(int64_t rawQ16)
{
    return (float)((double)rawQ16 * 360.0 / (65536.0 * 65536.0));
}

static uint8_t SaturateU8(uint32_t value)
{
    return (uint8_t)((value > 255U) ? 255U : value);
}

static uint16_t SaturateU16(uint32_t value)
{
    return (uint16_t)((value > 65535U) ? 65535U : value);
}

static bool IsMotorIdConfigured(void)
{
    return MOTOR_ID[0] != '\0'
        && strcmp(MOTOR_ID, "UNKNOWN") != 0
        && strcmp(MOTOR_ID, "UNKNOWN_MOTOR") != 0;
}

static const char *MA600_ResultName(MA600_Result_t result)
{
    switch (result)
    {
        case MA600_RESULT_OK:           return "OK";
        case MA600_RESULT_INVALID_ARG:  return "INVALID_ARG";
        case MA600_RESULT_SPI_TIMEOUT:  return "SPI_TIMEOUT";
        case MA600_RESULT_SPI_ERROR:    return "SPI_ERROR";
        case MA600_RESULT_SAMPLE_JUMP:  return "SAMPLE_JUMP";
        case MA600_RESULT_CONFIG_ERROR: return "CONFIG_ERROR";
        case MA600_RESULT_TIMING_METADATA_INVALID: return "TIMING_METADATA_INVALID";
        case MA600_RESULT_ACQUISITION_BUDGET_EXCEEDED: return "ACQUISITION_BUDGET_EXCEEDED";
        case MA600_RESULT_ACQUISITION_TIMEOUT: return "ACQUISITION_TIMEOUT";
        case MA600_RESULT_MATH_OVERFLOW: return "MATH_OVERFLOW";
        default:                        return "UNKNOWN";
    }
}

/* One DFT bin: order `order`'s raw cosine/sine coefficients (a, b) plus the derived
 * amplitude/phase. Reconstruction convention used everywhere in this file:
 *   x(theta) = mean + sum_k [ a_k*cos(k*theta) + b_k*sin(k*theta) ]
 *            = mean + sum_k [ amplitude_k * cos(k*theta - phaseDeg_k) ]
 * Always reconstruct from (a, b), never from (amplitude, phaseDeg) -- the pair (a, b) is the
 * canonical form computed directly from data; amplitude/phase are derived for display only. */
typedef struct
{
    uint8_t order;
    float a;
    float b;
    float amplitude;
    float phaseDeg;   /* atan2f(b, a), degrees, range [-180, 180). */
    bool  phaseValid; /* false when amplitude is too small for phase to mean anything -- see
                        * NL_PHASE_MIN_AMPLITUDE_DEG. */
} NlHarmonicResult_t;

/* Below this amplitude, phase is numerically meaningless: atan2 of two near-zero, noise-
 * dominated coefficients can swing wildly for a negligible change in the input curve. A
 * starting/placeholder threshold -- the right value is a few times the sensor's real noise
 * floor in degrees, which is now directly measurable via the "MA600 noise" StdDev field (see
 * main.c); revisit this constant once that's been characterized on real hardware rather than
 * guessed. */
#define NL_PHASE_MIN_AMPLITUDE_DEG 0.05f

/* Originally just {1, 2, 3, 6, 12, 18}, on the assumption that this motor's cogging (12
 * poles / 6 pole-pairs -> 6 electrical cycles/revolution) would show up mainly at harmonic 6.
 * Real hardware data (schema v2's first live runs) disproved that: harmonic 36 dominates by
 * roughly 15x over harmonic 6 (independently confirmed by re-running this exact DFT against
 * the logged DATA rows), with harmonic 72 and 108 (2x, 3x of it) also standing out -- i.e. the
 * true dominant ripple repeats 36 times/mechanical-revolution, which for a 6-pole-pair motor
 * is 6 ripples per *electrical* cycle (36/6). That's a well-known pattern in sine-commutated
 * PMSM drives (6th-order torque/position ripple relative to the electrical fundamental, from
 * back-EMF space harmonics and/or commutation-lookup quantization in Motor_PhasePwm) -- not
 * necessarily classic slot/pole "cogging" in the traditional sense, so harmonic 6 alone was
 * never going to explain much of this curve (confirmed: the old 6-harmonic set's
 * FitExplainedRatio was only ~15%; this expanded set reaches ~97%). 1/2/3 kept for
 * mounting/concentricity-scale signatures; 9/18/27/45 for the same electrical-ripple family's
 * neighbors; 36/72/108 for the dominant ripple and its own harmonics. Only RMS_AC, harmonic
 * amplitudes, and Fitted_P2P are used for any experimental pass/fail judgment (still none in
 * this version) -- the rest remain dataset-only. Sweep has ~256 points/revolution (Nyquist
 * ~128), so harmonic 108 is still comfortably resolvable. */
#define NL_HARMONIC_COUNT 12
static const uint8_t NL_HARMONIC_ORDERS[NL_HARMONIC_COUNT] =
    {1, 2, 3, 6, 9, 12, 18, 27, 36, 45, 72, 108};

/* The original schema v2 harmonic set -- Residual_RMS_Full/Fitted_P2P/FitExplainedRatio are
 * defined against exactly this subset (see NlSweepCapture_t), independent of whatever
 * NL_HARMONIC_ORDERS above grows to. NOT a contiguous prefix of NL_HARMONIC_ORDERS (order 9
 * sits between 6 and 12 in the full array), so it's looked up by value via FindHarmonic
 * (ComputeModelMetricsByOrders), never by index. */
#define NL_LEGACY_HARMONIC_COUNT 6
static const uint8_t NL_LEGACY_HARMONIC_ORDERS[NL_LEGACY_HARMONIC_COUNT] = {1, 2, 3, 6, 12, 18};

/* Single-frequency DFT coefficient (a cheap alternative to a full FFT when only a handful of
 * specific harmonics matter): projects the mean-removed error curve onto cos(harmonic*angle)
 * and sin(harmonic*angle). `errors` must be in original angle order (index i was recorded at
 * commanded angle 360*i*NL_POS_INCREASE/65536) and `count` must already be limited to one full
 * mechanical revolution (the caller passes analysisCount, not capturedCount) -- Fourier
 * analysis assumes exactly one period, and the >360 deg measurement margin would double-count
 * part of the curve if included here. Mean is subtracted explicitly (not relied on
 * cancelling out via the cos/sin sums) to avoid floating-point rounding drift and to keep
 * RMS_AC/harmonics/residuals/FitExplainedRatio all defined against the same AC signal. */
static void ComputeHarmonicFull(const float *errors, int count, float mean, int harmonic,
    NlHarmonicResult_t *out)
{
    float sumCos = 0.0f;
    float sumSin = 0.0f;

    for (int i = 0; i < count; i++)
    {
        float angleDeg = 360.0f * (float)i * (float)NL_POS_INCREASE / NL_FULL_TURN_RAW;
        float angleRad = angleDeg * (float)M_PI / 180.0f;
        float harmonicRad = (float)harmonic * angleRad;
        float centered = errors[i] - mean;
        sumCos += centered * cosf(harmonicRad);
        sumSin += centered * sinf(harmonicRad);
    }

    out->order = (uint8_t)harmonic;
    if (count <= 0)
    {
        out->a = 0.0f;
        out->b = 0.0f;
        out->amplitude = 0.0f;
        out->phaseDeg = 0.0f;
        out->phaseValid = false;
        return;
    }

    out->a = (2.0f / (float)count) * sumCos;
    out->b = (2.0f / (float)count) * sumSin;
    out->amplitude = sqrtf(out->a * out->a + out->b * out->b);
    out->phaseDeg = atan2f(out->b, out->a) * 180.0f / (float)M_PI;
    out->phaseValid = (out->amplitude >= NL_PHASE_MIN_AMPLITUDE_DEG);
}

static const NlHarmonicResult_t *FindHarmonic(const NlHarmonicResult_t *harmonics, int count, int order)
{
    for (int i = 0; i < count; i++)
    {
        if (harmonics[i].order == (uint8_t)order)
        {
            return &harmonics[i];
        }
    }
    return NULL;
}

/* Residual after subtracting only the harmonics listed in `ordersToUse` (plus mean) from the
 * curve, evaluated at the actual ~256 measured points (NOT the dense NL_FIT_EVAL_POINTS grid
 * used for Fitted_P2P -- residual is meaningless anywhere except where a real sample exists).
 * Used twice: ordersToUse={6} for Residual_RMS_H6 ("how much is left once only cogging is
 * removed"), ordersToUse=NL_HARMONIC_ORDERS (all 6) for Residual_RMS_Full. */
static float ComputeResidualRms(const float *errors, int count, float mean,
    const NlHarmonicResult_t *harmonics, const uint8_t *ordersToUse, int numOrders)
{
    if (count <= 0)
    {
        return 0.0f;
    }

    float sumSq = 0.0f;
    for (int i = 0; i < count; i++)
    {
        float angleDeg = 360.0f * (float)i * (float)NL_POS_INCREASE / NL_FULL_TURN_RAW;
        float angleRad = angleDeg * (float)M_PI / 180.0f;
        float fitted = mean;

        for (int j = 0; j < numOrders; j++)
        {
            const NlHarmonicResult_t *h = FindHarmonic(harmonics, NL_HARMONIC_COUNT, ordersToUse[j]);
            if (h == NULL)
            {
                continue;
            }
            float harmonicRad = (float)h->order * angleRad;
            fitted += h->a * cosf(harmonicRad) + h->b * sinf(harmonicRad);
        }

        float residual = errors[i] - fitted;
        sumSq += residual * residual;
    }

    return sqrtf(sumSq / (float)count);
}

/* Fitted_P2P is deliberately NOT max(errors)-min(errors) at the ~256 measured points -- that
 * would quantize the true peak of the fitted curve to the 1.40625 deg measurement step. This
 * reconstructs mean + the selected harmonics on an independent, much denser NL_FIT_EVAL_POINTS
 * grid (~0.088 deg/step at 4096 points) and takes the min/max of *that*.
 * Takes `ordersToUse`/`numOrders` (like ComputeResidualRms) and looks each one up via
 * FindHarmonic, rather than assuming `allHarmonics[0..numOrders-1]` is already the right
 * subset in the right order -- the 6 legacy orders are NOT contiguous at the front of the
 * 12-element NL_HARMONIC_ORDERS array (order 9 sits between 6 and 12), so indexing directly
 * would silently reconstruct the wrong curve for the legacy model. */
static void ComputeFittedMinMaxDenseByOrders(const NlHarmonicResult_t *allHarmonics, int allHarmonicsCount,
    const uint8_t *ordersToUse, int numOrders, float mean, float *outMax, float *outMin)
{
    float maxV = -1.0e9f;
    float minV = 1.0e9f;

    for (int i = 0; i < NL_FIT_EVAL_POINTS; i++)
    {
        float angleRad = 2.0f * (float)M_PI * (float)i / (float)NL_FIT_EVAL_POINTS;
        float fitted = mean;
        for (int j = 0; j < numOrders; j++)
        {
            const NlHarmonicResult_t *h = FindHarmonic(allHarmonics, allHarmonicsCount, ordersToUse[j]);
            if (h == NULL)
            {
                continue;
            }
            float harmonicRad = (float)h->order * angleRad;
            fitted += h->a * cosf(harmonicRad) + h->b * sinf(harmonicRad);
        }
        if (fitted > maxV) maxV = fitted;
        if (fitted < minV) minV = fitted;
    }

    *outMax = maxV;
    *outMin = minV;
}

/* Every RMS_AC-normalized quantity a harmonic model produces (residual, fitted P2P, explained
 * ratio), computed consistently from the SAME `ordersToUse` list -- used for both the legacy
 * (6-harmonic) and extended (12-harmonic) models so they can never accidentally drift onto two
 * different reconstruction code paths. */
typedef struct
{
    float residualRms;
    float fittedP2P;
    float explainedRatio;     /* clamped to [0,1] -- only meaningful when ratioValid. */
    bool  ratioValid;         /* false when rmsAc ~0 (1 - 0/0 is undefined, not "0% explained"). */
    bool  valid;              /* false when an order is missing from allHarmonics, an order
                                * violates Nyquist for the current analysisCount, or the raw
                                * (pre-clamp) explained ratio falls outside a small tolerance of
                                * [0,1] -- the last case is a sign the reconstruction itself is
                                * wrong (e.g. mismatched coefficients), not just "a poor fit",
                                * and clamping it to 0 first would hide that instead of
                                * surfacing it. */
    const char *invalidReason; /* short literal, only meaningful when valid==false. */
} NlModelMetrics_t;

#define NL_RMS_EPSILON     1e-6f
#define NL_RATIO_TOLERANCE 0.001f

static NlModelMetrics_t ComputeModelMetricsByOrders(
    const float *errors, int analysisCount, float mean,
    const NlHarmonicResult_t *allHarmonics, int allHarmonicsCount,
    const uint8_t *ordersToUse, int numOrders, float rmsAc)
{
    NlModelMetrics_t m = {0};

    for (int j = 0; j < numOrders; j++)
    {
        if (FindHarmonic(allHarmonics, allHarmonicsCount, ordersToUse[j]) == NULL)
        {
            m.invalidReason = "ORDER_NOT_COMPUTED";
            return m;
        }
        /* 2*order < analysisCount is required for that DFT bin to be meaningfully resolved.
         * At today's NL_POS_INCREASE=256 (analysisCount=256, Nyquist=128) every order up to
         * 108 passes comfortably -- this only matters if NL_POS_INCREASE is changed for a
         * grid-resolution experiment later, so this guard is defensive, not a live concern. */
        if (2u * (uint32_t)ordersToUse[j] >= (uint32_t)analysisCount)
        {
            m.invalidReason = "ORDER_ABOVE_NYQUIST";
            return m;
        }
    }

    m.residualRms = ComputeResidualRms(errors, analysisCount, mean, allHarmonics, ordersToUse, numOrders);
    float fittedMax, fittedMin;
    ComputeFittedMinMaxDenseByOrders(allHarmonics, allHarmonicsCount, ordersToUse, numOrders, mean, &fittedMax, &fittedMin);
    m.fittedP2P = fittedMax - fittedMin;

    if (rmsAc > NL_RMS_EPSILON)
    {
        float ratio = m.residualRms / rmsAc;
        float rawRatio = 1.0f - ratio * ratio;
        if (!isfinite(rawRatio) || rawRatio < -NL_RATIO_TOLERANCE || rawRatio > 1.0f + NL_RATIO_TOLERANCE)
        {
            m.invalidReason = "RATIO_OUT_OF_RANGE";
            return m;
        }
        float clamped = rawRatio;
        if (clamped < 0.0f) clamped = 0.0f;
        if (clamped > 1.0f) clamped = 1.0f;
        m.explainedRatio = clamped;
        m.ratioValid = true;
    }
    else
    {
        m.explainedRatio = 0.0f;
        m.ratioValid = false;
    }

    m.valid = true;
    return m;
}

/* Plain insertion sort, ascending. O(count^2), but this only ever runs a few times per sweep
 * on <=~264 elements (a few ms on a 168MHz Cortex-M4) -- not a real-time constraint, so
 * simplicity wins over a faster algorithm. */
static void SortAscending(float *values, int count)
{
    for (int i = 1; i < count; i++)
    {
        float key = values[i];
        int j = i - 1;
        while (j >= 0 && values[j] > key)
        {
            values[j + 1] = values[j];
            j--;
        }
        values[j + 1] = key;
    }
}

typedef struct
{
    float robustPP;        /* avg(top K) - avg(bottom K): the current "Nonlinear Angle". */
    float rawPP;            /* single max - single min, for comparison. */
    float rms;              /* sqrt(mean(error^2)) -- an amplitude-style metric, not a
                              * peak/range one, so not directly comparable to the datasheet's
                              * 0.6 deg (peak) reference, but very insensitive to any single
                              * noisy point. NOT mean-removed (unlike schema v2's RMS_AC) --
                              * kept exactly as before, this is the same "NL TC rms" field. */
    float percentileLow;    /* 5th percentile value. */
    float percentileHigh;   /* 95th percentile value. */
    float percentilePP;     /* percentileHigh - percentileLow: a range-style metric like
                              * robustPP/rawPP, but defined by proportion of points excluded
                              * (5% each side) rather than a fixed count K. */
} NlSweepStats_t;

/* Computes several candidate "how nonlinear was this sweep" metrics from the same raw
 * per-point error data, so they can be compared side by side on the same run. Unlike the
 * original version of this function, `values` is never mutated/sorted in place -- callers
 * (harmonic analysis, residuals, DATA logging) all depend on errorSamples staying in angle
 * order for the lifetime of a capture, so this copies into caller-provided `scratch` and
 * sorts that instead. */
static NlSweepStats_t ComputeSweepStats(const float *values, float *scratch, int count, int extremeCount)
{
    NlSweepStats_t stats = {0};
    if (count <= 0)
    {
        return stats;
    }

    float sumSquares = 0.0f;
    for (int i = 0; i < count; i++)
    {
        sumSquares += values[i] * values[i];
    }
    stats.rms = sqrtf(sumSquares / (float)count);

    memcpy(scratch, values, (size_t)count * sizeof(float));
    SortAscending(scratch, count);

    int k = extremeCount;
    if (k > count) k = count;
    if (k < 1) k = 1;

    float bottomSum = 0.0f;
    float topSum = 0.0f;
    for (int i = 0; i < k; i++)
    {
        bottomSum += scratch[i];
        topSum += scratch[count - 1 - i];
    }
    float robustMin = bottomSum / (float)k;
    float robustMax = topSum / (float)k;
    stats.robustPP = robustMax - robustMin;
    stats.rawPP = scratch[count - 1] - scratch[0];

    int p5Idx = (int)(0.05f * (float)(count - 1) + 0.5f);
    int p95Idx = (int)(0.95f * (float)(count - 1) + 0.5f);
    if (p5Idx < 0) p5Idx = 0;
    if (p95Idx >= count) p95Idx = count - 1;
    stats.percentileLow = scratch[p5Idx];
    stats.percentileHigh = scratch[p95Idx];
    stats.percentilePP = stats.percentileHigh - stats.percentileLow;

    return stats;
}

typedef enum
{
    NL_ZERO_OK = 0,
    NL_ZERO_DIRECTION_ERROR,
    NL_ZERO_TIMEOUT,
    NL_ZERO_ACQUISITION_ERROR,
} NlZeroResult_t;

typedef struct
{
    NlZeroResult_t result;
    uint32_t durationMs;
    uint32_t updateCount;
    float initialErrorDeg;
    float finalErrorDeg;
    int32_t initialCommandedPositionRaw;
    int32_t finalCommandedPositionRaw;
} NlZeroObservation_t;

static NlZeroResult_t FinishMoveToZeroObservation(NlZeroObservation_t *out,
                                                   NlZeroResult_t result,
                                                   uint32_t startTick)
{
    if (out != NULL)
    {
        out->result = result;
        out->durationMs = HAL_GetTick() - startTick;
        out->finalCommandedPositionRaw = Motor_GetCommandedPos();
    }
    return result;
}

static const char *NlZeroResultName(NlZeroResult_t result)
{
    switch (result)
    {
        case NL_ZERO_OK:                return "OK";
        case NL_ZERO_DIRECTION_ERROR:   return "DIRECTION_ERROR";
        case NL_ZERO_TIMEOUT:           return "TIMEOUT";
        case NL_ZERO_ACQUISITION_ERROR: return "ACQUISITION_ERROR";
        default:                        return "UNKNOWN";
    }
}

/* Drives back to angle 0 with the position PID and waits for it to settle.
 * This loop originally had no time bound at all (matching the reference
 * firmware's busy-poll), which turned out to be a real bug on real
 * hardware: if the PID never converges to within NL_MOVE_ZERO_ERROR_DEG
 * (wrong gains for this motor, a wiring/feedback problem, mechanical
 * binding, etc.) it would spin here forever with no further log output,
 * looking indistinguishable from a hang. It now times out and prints
 * periodic diagnostics so a stuck run is visible and recoverable instead of
 * silent. */
static NlZeroResult_t MoveToZeroAndCheckDirection(NlZeroObservation_t *out)
{
    if (out == NULL)
    {
        return NL_ZERO_ACQUISITION_ERROR;
    }
    memset(out, 0, sizeof(*out));
    uint32_t startTick = HAL_GetTick();
    out->initialCommandedPositionRaw = Motor_GetCommandedPos();

    SetEngineState(NL_ENGINE_HOME);
    float errorBefore = 0.0f;
    if (Motor_MoveToAngle(0.0f, &errorBefore) != MA600_RESULT_OK)
    {
        return FinishMoveToZeroObservation(out, NL_ZERO_ACQUISITION_ERROR,
            startTick);
    }
    out->initialErrorDeg = errorBefore;
    out->finalErrorDeg = errorBefore;
    out->updateCount = 1U;
    int32_t settled = 0;
    uint32_t lastDiagTick = startTick;

    for (;;)
    {
        float error = 0.0f;
        if (Motor_MoveToAngle(0.0f, &error) != MA600_RESULT_OK)
        {
            return FinishMoveToZeroObservation(out, NL_ZERO_ACQUISITION_ERROR,
                startTick);
        }
        out->finalErrorDeg = error;
        out->updateCount++;

        if (fabsf(error) < NL_MOVE_ZERO_ERROR_DEG)
        {
            settled++;
        }
        else
        {
            settled = 0;
        }

        if (settled > NL_MOVE_ZERO_SETTLE_TICKS)
        {
            return FinishMoveToZeroObservation(out, NL_ZERO_OK, startTick);
        }

        if (fabsf(error) - fabsf(errorBefore) > NL_CHECK_DIR_ANGLE_DEG)
        {
            return FinishMoveToZeroObservation(out, NL_ZERO_DIRECTION_ERROR,
                startTick);
        }

        uint32_t now = HAL_GetTick();
        if (now - lastDiagTick >= NL_MOVE_ZERO_DIAG_INTERVAL_MS)
        {
            lastDiagTick = now;
            char errBuf[16];
            FormatDeg2(error, errBuf, sizeof(errBuf));
            LogLine("MA600 move-to-zero: error=%s deg settled=%ld/%ld cmdPos=%ld\r\n",
                errBuf, (long)settled, (long)NL_MOVE_ZERO_SETTLE_TICKS,
                (long)Motor_GetCommandedPos());
        }

        if (now - startTick >= NL_MOVE_ZERO_TIMEOUT_MS)
        {
            return FinishMoveToZeroObservation(out, NL_ZERO_TIMEOUT, startTick);
        }

        /* This is the actual bug behind the "vibrates but never rotates"
         * symptom seen on hardware: with no delay here, this loop runs at
         * whatever rate the SPI bus allows (tens of thousands of Hz on this
         * hardware) -- confirmed from a real log where the commanded
         * position (Motor_GetCommandedPos()) raced to -158,000,000+ counts
         * within 10 seconds (~230 commanded revolutions/sec) while the real
         * encoder angle barely moved. That's the electrical field being
         * commanded to spin far faster than the rotor's mechanical inertia
         * can ever follow, so the rotor just sees rapidly alternating
         * torque and buzzes in place instead of actually turning -- no
         * amount of gain tuning fixes that, the loop itself has to be rate
         * limited. The reference firmware avoided this by construction: its
         * encoder feedback was refreshed by a separate ~1kHz task, capping
         * how fast *effective* PID updates could happen regardless of how
         * often this loop polled it. jigmotor has no such task, so the cap
         * has to be explicit here. */
        osDelay(NL_MOVE_ZERO_LOOP_DELAY_MS);
    }
}

/* Open-loop dither with shrinking amplitude around electrical position 0 --
 * settles the rotor at whatever mechanical position is nearest that
 * electrical zero-crossing. Not an absolute reference; the encoder is
 * re-zeroed right after this, and every angle in the run is relative to
 * that. */
static void LockStartPosition(void)
{
    SetEngineState(NL_ENGINE_LOCK);
    for (int32_t d = NL_DITHER_START_POS; d > 0; d--)
    {
        Motor_SetElectricalPos((uint16_t)(0 - d), 1.0f);
        osDelay((uint32_t)d);
        Motor_SetElectricalPos((uint16_t)d, 1.0f);
        osDelay((uint32_t)d);
    }
    Motor_SetElectricalPos(0, 1.0f);
    osDelay(NL_DITHER_SETTLE_MS);
}

/* A point is valid only when both the raw movement delta and the distance to
 * the expected unwrapped target remain within their limits for the complete
 * consecutive window. A timeout is retained as diagnostic data; the caller
 * captures the point but rejects the sweep's measurement validity. */
typedef enum
{
    NL_SETTLE_OK = 0,
    NL_SETTLE_TIMEOUT,
    NL_SETTLE_WRONG_POSITION,
    NL_SETTLE_ACQUISITION_ERROR,
} NlSettleResult_t;

typedef struct
{
    NlSettleResult_t result;
    MA600_Result_t acquisitionResult;
    MA600_Sample_t finalSample;
    uint32_t pollCount;
    uint32_t maxStableConsecutive;
    uint32_t maxCombinedConsecutive;
    int64_t positionErrorRaw;
    bool stabilityValid;
    bool targetProximityValid;
    bool valid;
} NlSettleObservation_t;

typedef struct
{
    uint32_t readAttempts;
    uint32_t acceptedSamples;
    uint32_t retryCount;
    uint32_t transportErrorCount;
    uint32_t jumpRejectCount;
    uint32_t failedSampleCount;
} NlAcquisitionCounters_t;

static NlAcquisitionCounters_t SnapshotAcquisitionCounters(
    const MA600_AcquisitionContext_t *ctx)
{
    NlAcquisitionCounters_t snapshot = {0};
    if (ctx != NULL)
    {
        snapshot.readAttempts = ctx->readAttempts;
        snapshot.acceptedSamples = ctx->acceptedSamples;
        snapshot.retryCount = ctx->retryCount;
        snapshot.transportErrorCount = ctx->transportErrorCount;
        snapshot.jumpRejectCount = ctx->jumpRejectCount;
        snapshot.failedSampleCount = ctx->failedSampleCount;
    }
    return snapshot;
}

static void AccumulateCounterDelta(const MA600_AcquisitionContext_t *ctx,
                                   const NlAcquisitionCounters_t *before,
                                   NlAcquisitionCounters_t *total)
{
    if (ctx == NULL || before == NULL || total == NULL)
    {
        return;
    }
    total->readAttempts += ctx->readAttempts - before->readAttempts;
    total->acceptedSamples += ctx->acceptedSamples - before->acceptedSamples;
    total->retryCount += ctx->retryCount - before->retryCount;
    total->transportErrorCount += ctx->transportErrorCount - before->transportErrorCount;
    total->jumpRejectCount += ctx->jumpRejectCount - before->jumpRejectCount;
    total->failedSampleCount += ctx->failedSampleCount - before->failedSampleCount;
}

static uint64_t AbsI64ToU64(int64_t value)
{
    return (value < 0) ? (uint64_t)(-(value + 1)) + 1U : (uint64_t)value;
}

static const char *SettleResultName(NlSettleResult_t result)
{
    switch (result)
    {
        case NL_SETTLE_OK:                return "OK";
        case NL_SETTLE_TIMEOUT:           return "TIMEOUT";
        case NL_SETTLE_WRONG_POSITION:    return "WRONG_POSITION";
        case NL_SETTLE_ACQUISITION_ERROR: return "ACQUISITION_ERROR";
        default:                          return "UNKNOWN";
    }
}

/* Uses the caller-owned sweep context. Stability and target proximity must
 * hold together for one complete consecutive window. No context is created
 * or reacquired here, so wrap history remains continuous through ramp,
 * settle, and point capture. */
static NlSettleResult_t WaitForPointSettle(
    MA600_AcquisitionContext_t *sweepAcquisition,
    int64_t expectedTargetUnwrapped,
    bool targetRequired,
    NlSettleObservation_t *out)
{
    if (sweepAcquisition == NULL || out == NULL)
    {
        return NL_SETTLE_ACQUISITION_ERROR;
    }
    memset(out, 0, sizeof(*out));
    out->result = NL_SETTLE_ACQUISITION_ERROR;
    out->acquisitionResult = MA600_RESULT_OK;

    MA600_Sample_t sample;
    MA600_Result_t result = MA600_AcquireSample(sweepAcquisition,
        NL_SETTLE_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &sample);
    if (result != MA600_RESULT_OK)
    {
        out->acquisitionResult = result;
        return NL_SETTLE_ACQUISITION_ERROR;
    }
    out->finalSample = sample;
    out->pollCount = 1U;
    int64_t lastUnwrapped = sample.unwrappedRaw;
    uint32_t stableConsecutive = 0U;
    uint32_t combinedConsecutive = 0U;
    uint32_t startTick = HAL_GetTick();

    for (;;)
    {
        osDelay(NL_POINT_SETTLE_POLL_MS);
        result = MA600_AcquireSample(sweepAcquisition, NL_SETTLE_MAX_JUMP_RAW,
            NL_ACQ_MAX_ATTEMPTS, &sample);
        if (result != MA600_RESULT_OK)
        {
            out->acquisitionResult = result;
            out->result = NL_SETTLE_ACQUISITION_ERROR;
            return NL_SETTLE_ACQUISITION_ERROR;
        }
        out->finalSample = sample;
        out->pollCount++;
        uint64_t deltaRaw = AbsI64ToU64(sample.unwrappedRaw - lastUnwrapped);
        lastUnwrapped = sample.unwrappedRaw;
        out->positionErrorRaw = sample.unwrappedRaw - expectedTargetUnwrapped;
        bool stable = deltaRaw <= (uint64_t)NL_POINT_SETTLE_ERROR_RAW;
        bool targetNear = !targetRequired
            || AbsI64ToU64(out->positionErrorRaw)
                <= (uint64_t)NL_SETTLE_TARGET_TOLERANCE_RAW;

        if (stable)
        {
            stableConsecutive++;
        }
        else
        {
            stableConsecutive = 0U;
        }
        if (stable && targetNear)
        {
            combinedConsecutive++;
        }
        else
        {
            combinedConsecutive = 0U;
        }
        if (stableConsecutive > out->maxStableConsecutive)
            out->maxStableConsecutive = stableConsecutive;
        if (combinedConsecutive > out->maxCombinedConsecutive)
            out->maxCombinedConsecutive = combinedConsecutive;
        out->stabilityValid = out->maxStableConsecutive
            >= NL_POINT_SETTLE_CONSECUTIVE;
        out->targetProximityValid = targetNear;

        if (combinedConsecutive >= NL_POINT_SETTLE_CONSECUTIVE)
        {
            out->valid = true;
            out->result = NL_SETTLE_OK;
            return NL_SETTLE_OK;
        }

        if (HAL_GetTick() - startTick >= NL_POINT_SETTLE_TIMEOUT_MS)
        {
            out->valid = false;
            if (out->stabilityValid && !out->targetProximityValid)
            {
                out->result = NL_SETTLE_WRONG_POSITION;
                return NL_SETTLE_WRONG_POSITION;
            }
            out->result = NL_SETTLE_TIMEOUT;
            return NL_SETTLE_TIMEOUT;
        }
    }
}

static float WrapSignedDeg(float deg)
{
    while (deg > 180.0f) deg -= 360.0f;
    while (deg < -180.0f) deg += 360.0f;
    return deg;
}

/* CCW is architecture-only right now (see ENABLE_CCW_ENGINEERING_TEST): the phase fields
 * logged per harmonic (H{k}_PhaseSweepDeg) are relative to sweep *progress* (0->360 deg by
 * magnitude, same convention for either direction), not the MA600A's absolute physical angle
 * -- ghép trục CW/CCW về cùng 1 hệ quy chiếu tuyệt đối is offline/future work. The encoder's
 * per-capture unwrap is based on the delta between consecutive accepted reads and should be
 * direction-symmetric in principle, but has only ever
 * actually been exercised moving CW on real hardware -- treat the CCW path as compile-
 * verified only until a dedicated hardware validation run confirms it. */
typedef enum
{
    NL_SWEEP_CW = 0,
    NL_SWEEP_CCW = 1,
} NlSweepDirection_t;

/* Point-heavy Phase-2B storage lives in CPU-only CCM RAM. It is explicitly
 * cleared before each capture, so it does not depend on startup initialization
 * of the custom linker section. No DMA peripheral accesses these arrays. */
typedef struct
{
    int64_t  pointMeanRawQ16[NL_MAX_SWEEP_POINTS];
    int64_t  settlePositionErrorRaw[NL_MAX_SWEEP_POINTS];
    uint32_t firstAttemptCycle[NL_MAX_SWEEP_POINTS];
    uint32_t elapsedCycle[NL_MAX_SWEEP_POINTS];
    uint16_t settlePollCount[NL_MAX_SWEEP_POINTS];
    uint8_t  transactions[NL_MAX_SWEEP_POINTS];
    uint8_t  accepted[NL_MAX_SWEEP_POINTS];
    uint8_t  spiFailures[NL_MAX_SWEEP_POINTS];
    uint8_t  jumpRejects[NL_MAX_SWEEP_POINTS];
    uint8_t  metadataInvalid[NL_MAX_SWEEP_POINTS];
    uint8_t  results[NL_MAX_SWEEP_POINTS];
    uint8_t  settleResults[NL_MAX_SWEEP_POINTS];
    uint8_t  settleFlags[NL_MAX_SWEEP_POINTS];
    uint8_t  rampAcceptedSamples[NL_MAX_SWEEP_POINTS];
} NlShadowPointStorage_t;

typedef struct
{
    bool     attempted;
    bool     valid;
    MA600_Result_t result;
    uint32_t nominalHoldMs;
    uint32_t captureStartElapsedMs;
    uint32_t captureEndElapsedMs;
    int32_t  commandRaw;
    int64_t  positionErrorRawQ16;
    int64_t  windowP2PRaw;
    int64_t  windowDriftRaw;
    MA600_PointSample_t point;
} NlClosureProbeStage_t;

/* Full result of one sweep (one direction, one run). Capturing into this struct instead of
 * logging inline is what lets CaptureSweep() stay 100% silent on UART -- see its header
 * comment. Sized for NL_MAX_SWEEP_POINTS regardless of how many points a given sweep actually
 * used; at NL_TEST_COUNT=1 with CCW off there is exactly 1 of these (~12KB), comfortably
 * inside this MCU's 192KB RAM -- revisit if NL_TEST_COUNT or CCW usage grows a lot. */
typedef struct
{
    int      runIndex;         /* 0-based index within this test's NL_TEST_COUNT loop. */
    uint32_t testId;           /* shared by every sweep (CW, and CCW if enabled) of one button press. */
    uint32_t sweepId;          /* unique per CaptureSweep() call, monotonic for the whole boot session. */
    NlSweepDirection_t direction;

    /* Run-boundary controller-state contract. This is copied in after
     * CaptureSweep() clears/initializes the capture so every emitted sweep
     * records the exact home session that established its starting state. */
    bool controllerResetApplied;
    bool controllerResetStateValid;
    Motor_ControllerState_t controllerStateBeforeReset;
    Motor_ControllerState_t controllerStateAfterReset;
    NlZeroObservation_t homeObservation;

#if ENABLE_AUTO_BATCH_TEST
    uint32_t batchId;
    uint32_t cycleOrder;         /* 1..11 physical sweep order, including precondition. */
    uint32_t runOrder;           /* 0 for precondition; 1..10 for official runs. */
    uint32_t batchRunCount;      /* Official run count (10), excluding precondition. */
    bool     preconditionRun;
    bool     eligibleForStatistics;
    bool     preconditionValid;  /* true for official runs only after cycle 1 passed. */
    bool     firstRunInBatch;   /* true only for cycleOrder==1 -- no firmware-controlled cooldown
                                  * preceded this run, so the three cooldown fields below are
                                  * not meaningful and are logged as NA rather than a fabricated 0. */
    uint32_t cooldownTargetMs;
    uint32_t cooldownActualMs;
    bool     cooldownValid;
    uint32_t motorActiveDurationMs; /* Motor_Enable() to Motor_Disable() wall-clock span. */
    uint32_t timeSincePreviousRunMs; /* Wall-clock from the PREVIOUS run's motor-off tick to this
                                       * run's start -- meaningful only when hasPreviousRun is
                                       * true. Under NL_TEST_REPEAT_1_RUN this is the actual
                                       * elapsed rest time the operator took between remounts,
                                       * since that cooldown isn't firmware-timed in that mode. */
    bool     hasPreviousRun;
#endif

    int      capturedCount;    /* total points captured, including the >360 deg margin. */
    int      analysisCount;    /* points actually used for harmonic/RMS/residual (== 256 at NL_POS_INCREASE=256). */
    bool     measurementValid; /* protocol validity: acquisition succeeded, point count and
                                 * settling are complete, and gross tracking integrity passed.
                                 * Independent of nonlinear magnitude and model validity. */

    uint16_t rawAtOffset;
    uint16_t motorOffset;
    float    angleOffsetAtStart;
    int32_t  multiTurnRawAtStart;

    float    mean;
    float    rmsAc;
    NlHarmonicResult_t harmonics[NL_HARMONIC_COUNT];
    /* Datasheet-aligned diagnostic orders (MA600A Rev. 1.0 uses H1/H2/H4/H8 for its own
     * constant-speed calibration fit) -- computed standalone, deliberately NOT folded into
     * harmonics[]/NL_HARMONIC_ORDERS so ExtendedOrders/Residual_RMS_Extended/Fitted_P2P_Extended
     * keep meaning exactly what they already mean (order 1/2 for this purpose are already
     * available as harmonics[] entries -- same amplitude/phase, no need to duplicate). */
    NlHarmonicResult_t harmonicH4;
    NlHarmonicResult_t harmonicH8;
    NlHarmonicResult_t electricalRippleHarmonic;
    uint16_t motorPoleCount;
    uint16_t motorPolePairs;
    uint16_t electricalRippleOrder;
    bool     electricalRippleValid;
    uint8_t  dominantSelectedOrder;       /* order with the largest amplitude in harmonics[] --
                                            * describes the target-grid curve only, not proof of
                                            * a physical origin -- see NL_HARMONIC_ORDERS. */
    float    dominantSelectedAmplitude;
    float    dominantSelectedEnergyRatio; /* 0.5*amplitude^2 / rmsAc^2 -- what fraction of the
                                            * curve's total AC energy this one harmonic accounts
                                            * for (Parseval), a clearer statement than "largest
                                            * amplitude" alone. */
    float    residualRmsH6;             /* kept for historical comparison against the original
                                          * (disproven) H6-cogging assumption -- see the
                                          * NL_HARMONIC_ORDERS comment. */
    float    residualRmsH36;            /* same idea, against the harmonic actually found to dominate. */
    /* Legacy (6-harmonic, {1,2,3,6,12,18}) model -- schema v2's original meaning, restored
     * after v3 briefly (and wrongly) redefined these three under the same names. */
    float    residualRmsFull;
    float    fittedP2P;
    float    fitExplainedRatio;
    bool     legacyModelValid;
    /* Extended (12-harmonic, NL_HARMONIC_ORDERS) model -- new in v4, distinctly named so it's
     * never confused with the legacy fields above regardless of whether SchemaVersion is
     * checked. See the Context note in the plan (and NL_HARMONIC_ORDERS' comment) for why a
     * high FitExplainedRatioExtended does NOT by itself prove a physical cogging origin. */
    float    residualRmsExtended;
    float    fittedP2PExtended;
    float    fitExplainedRatioExtended;
    bool     extendedModelValid;
    float    crestFactor;
    float    p99AbsDeviation;
    float    trackingErrorRmsDeg;
    float    trackingErrorMaxAbsDeg;
    bool     trackingValid;
    uint32_t featureComputeTimeMs;

    MA600_Result_t acquisitionResult;
    uint32_t acquisitionReadAttempts;
    uint32_t acquisitionRetries;
    uint32_t acquisitionTransportErrors;
    uint32_t acquisitionJumpRejects;
    uint32_t acquisitionFailedSamples;

    /* Phase-3A motion acquisition uses one continuous unwrap context. The
     * phase counters below are subtracted from the context totals so frozen
     * schema-v5 Acq* fields retain their original point-capture meaning. */
    NlAcquisitionCounters_t contextAcquisition;
    NlAcquisitionCounters_t rampAcquisition;
    NlAcquisitionCounters_t settleAcquisition;
    uint32_t contextReacquireCount;
    int      settlePointCount;
    int      settleStabilityValidCount;
    int      settleTargetProximityValidCount;
    int      settleValidCount;
    int      settleTimeoutCount;
    int      settleWrongPositionCount;
    int64_t  maxAbsSettlePositionErrorRaw;

    /* Phase-2B diagnostic capture. None of these fields participate in
     * measurementValid, Motor OK, batch completion, or the legacy RESULT.
     * Keeping point counters separate prevents shadow/ramp reads from
     * silently changing the meaning of schema-v5 Acq* fields. */
    bool     shadowCanonicalEnabled;
    bool     shadowCanonicalStarted;
    bool     shadowCanonicalValid;
    bool     shadowClosureValid;
    MA600_Result_t shadowAcquisitionResult;
    int      shadowAttemptedPointCount;
    int      shadowCapturedCount;
    int      shadowAnalysisCount;
    uint32_t shadowTransactionCount;
    uint32_t shadowAcceptedSampleCount;
    uint32_t shadowSpiFailureCount;
    uint32_t shadowJumpRejectedCount;
    uint32_t shadowMetadataInvalidCount;
    uint32_t shadowFailedPointCount;
    uint32_t shadowSkippedSlotCount;
    uint32_t shadowTimingOverrunCount;
    uint32_t shadowMaxAbsTimingErrorCycles;
    uint32_t shadowMaxConsecutiveFailuresObserved;
    uint32_t shadowFeatureComputeTimeMs;
    int64_t  shadowPoint0MeanRawQ16;
    int64_t  shadowClosureErrorRawQ16;
    float    shadowMean;
    float    shadowRmsAc;
    float    shadowA36;
    float    shadowP2P;
    float    shadowClosureErrorDeg;
    float    shadowLegacyMinusCanonicalRms;
    float    shadowLegacyMinusCanonicalA36;
    NlShadowPointStorage_t *shadowPoints;

    /* Phase-3B0-A diagnostic only. A numeric closure value here never
     * participates in measurementValid/Motor OK/batch disposition. A read
     * failure is still a safety/acquisition failure and stops the sweep. */
    bool     closureProbeEnabled;
    bool     closureProbeStarted;
    bool     closureProbeComplete;
    bool     postTurnTimingComparable;
    MA600_Result_t closureProbeAcquisitionResult;
    uint32_t closureProbeAttemptedStageCount;
    uint32_t closureProbeValidStageCount;
    NlClosureProbeStage_t closureProbeStages[NL_CLOSURE_PROBE_STAGE_COUNT];

    int      notSettledCount;
    float    absoluteAngleAtMax;
    float    absoluteAngleAtMin;
    uint16_t rawAtMax;
    uint16_t rawAtMin;

    NlSweepStats_t legacyStats;

    float    errorSamples[NL_MAX_SWEEP_POINTS];
    uint16_t rawAngleSamples[NL_MAX_SWEEP_POINTS];
    int32_t  targetRawSamples[NL_MAX_SWEEP_POINTS];
    uint32_t csAssertCycleSamples[NL_MAX_SWEEP_POINTS];
    uint16_t pwmCounterSamples[NL_MAX_SWEEP_POINTS];
    uint8_t  acquisitionAttemptSamples[NL_MAX_SWEEP_POINTS];
    uint8_t  acquisitionFlagSamples[NL_MAX_SWEEP_POINTS];

} NlSweepCapture_t;

static NlSweepCapture_t nlCaptures[NL_MAX_SWEEPS_PER_TEST];
static NlShadowPointStorage_t nlShadowPointStorage[NL_MAX_SWEEPS_PER_TEST]
    __attribute__((section(".ccmram_bss")));
static float nlSortScratch[NL_MAX_SWEEP_POINTS];
static uint32_t nlTestIdCounter = 0;
static uint32_t nlSweepIdCounter = 0;

enum
{
    NL_SETTLE_FLAG_STABILITY_VALID = (1U << 0),
    NL_SETTLE_FLAG_TARGET_VALID    = (1U << 1),
    NL_SETTLE_FLAG_COMBINED_VALID  = (1U << 2),
};

static void RecordSettleObservation(NlSweepCapture_t *out, int pointIndex,
                                    const NlSettleObservation_t *observation,
                                    uint32_t rampAcceptedSamples)
{
    if (out == NULL || observation == NULL
            || pointIndex < 0 || pointIndex >= NL_MAX_SWEEP_POINTS)
    {
        return;
    }

    uint8_t flags = 0U;
    if (observation->stabilityValid)
    {
        flags |= NL_SETTLE_FLAG_STABILITY_VALID;
        out->settleStabilityValidCount++;
    }
    if (observation->targetProximityValid)
    {
        flags |= NL_SETTLE_FLAG_TARGET_VALID;
        out->settleTargetProximityValidCount++;
    }
    if (observation->valid)
    {
        flags |= NL_SETTLE_FLAG_COMBINED_VALID;
        out->settleValidCount++;
    }
    if (observation->result == NL_SETTLE_TIMEOUT)
    {
        out->settleTimeoutCount++;
    }
    else if (observation->result == NL_SETTLE_WRONG_POSITION)
    {
        out->settleWrongPositionCount++;
    }

    uint64_t absPositionErrorRaw = AbsI64ToU64(observation->positionErrorRaw);
    if (absPositionErrorRaw > (uint64_t)out->maxAbsSettlePositionErrorRaw)
    {
        out->maxAbsSettlePositionErrorRaw = (int64_t)absPositionErrorRaw;
    }

    out->settlePointCount++;
    if (out->shadowPoints != NULL)
    {
        out->shadowPoints->settlePositionErrorRaw[pointIndex] = observation->positionErrorRaw;
        out->shadowPoints->settlePollCount[pointIndex] = SaturateU16(observation->pollCount);
        out->shadowPoints->settleResults[pointIndex] = (uint8_t)observation->result;
        out->shadowPoints->settleFlags[pointIndex] = flags;
        out->shadowPoints->rampAcceptedSamples[pointIndex] = SaturateU8(rampAcceptedSamples);
    }
}

static void RecordShadowPoint(NlSweepCapture_t *out, int pointIndex,
                              const MA600_PointSample_t *point,
                              MA600_Result_t result)
{
    if (out == NULL || point == NULL || out->shadowPoints == NULL)
    {
        return;
    }

    out->shadowCanonicalStarted = true;
    out->shadowAttemptedPointCount++;
    out->shadowTransactionCount += point->transactionCount;
    out->shadowAcceptedSampleCount += point->acceptedSampleCount;
    out->shadowSpiFailureCount += point->spiFailureCount;
    out->shadowJumpRejectedCount += point->jumpRejectedCount;
    out->shadowMetadataInvalidCount += point->metadataInvalidCount;
    out->shadowSkippedSlotCount += point->skippedSlotCount;
    out->shadowTimingOverrunCount += point->timingOverrunCount;
    if (point->maxAbsTimingErrorCycles > out->shadowMaxAbsTimingErrorCycles)
    {
        out->shadowMaxAbsTimingErrorCycles = point->maxAbsTimingErrorCycles;
    }
    if (point->maxConsecutiveFailures > out->shadowMaxConsecutiveFailuresObserved)
    {
        out->shadowMaxConsecutiveFailuresObserved = point->maxConsecutiveFailures;
    }

    if (pointIndex >= 0 && pointIndex < NL_MAX_SWEEP_POINTS)
    {
        out->shadowPoints->firstAttemptCycle[pointIndex] = point->firstAttemptCycle;
        out->shadowPoints->elapsedCycle[pointIndex] = point->elapsedCycles;
        out->shadowPoints->transactions[pointIndex] = SaturateU8(point->transactionCount);
        out->shadowPoints->accepted[pointIndex] = SaturateU8(point->acceptedSampleCount);
        out->shadowPoints->spiFailures[pointIndex] = SaturateU8(point->spiFailureCount);
        out->shadowPoints->jumpRejects[pointIndex] = SaturateU8(point->jumpRejectedCount);
        out->shadowPoints->metadataInvalid[pointIndex] = SaturateU8(point->metadataInvalidCount);
        out->shadowPoints->results[pointIndex] = (uint8_t)result;
    }

    if (result == MA600_RESULT_OK && point->valid
            && pointIndex >= 0 && pointIndex < NL_MAX_SWEEP_POINTS)
    {
        out->shadowPoints->pointMeanRawQ16[pointIndex] = point->pointMeanRawQ16;
        if (pointIndex == 0)
        {
            out->shadowPoint0MeanRawQ16 = point->pointMeanRawQ16;
        }
        out->shadowCapturedCount++;
    }
    else
    {
        out->shadowFailedPointCount++;
        out->shadowAcquisitionResult = result;
    }
}

static const char *ClosureProbeStageName(uint32_t stageIndex)
{
    static const char *const names[NL_CLOSURE_PROBE_STAGE_COUNT] = {
        "INITIAL", "HOLD_50", "HOLD_100", "HOLD_200"
    };
    return (stageIndex < NL_CLOSURE_PROBE_STAGE_COUNT)
        ? names[stageIndex] : "UNKNOWN";
}

static void WaitForClosureProbeTime(uint32_t startTick, uint32_t targetElapsedMs)
{
    for (;;)
    {
        uint32_t elapsedMs = (uint32_t)(HAL_GetTick() - startTick);
        if (elapsedMs >= targetElapsedMs)
        {
            return;
        }
        osDelay(targetElapsedMs - elapsedMs);
    }
}

static MA600_Result_t RecordClosureProbeStage(NlSweepCapture_t *out,
                                               uint32_t stageIndex,
                                               const MA600_PointSample_t *point,
                                               MA600_Result_t result,
                                               uint32_t nominalHoldMs,
                                               uint32_t captureStartElapsedMs,
                                               uint32_t captureEndElapsedMs,
                                               int32_t commandRaw,
                                               int32_t directionSign)
{
    if (out == NULL || point == NULL || stageIndex >= NL_CLOSURE_PROBE_STAGE_COUNT)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    NlClosureProbeStage_t *stage = &out->closureProbeStages[stageIndex];
    memset(stage, 0, sizeof(*stage));
    stage->attempted = true;
    stage->result = result;
    stage->nominalHoldMs = nominalHoldMs;
    stage->captureStartElapsedMs = captureStartElapsedMs;
    stage->captureEndElapsedMs = captureEndElapsedMs;
    stage->commandRaw = commandRaw;
    stage->point = *point;
    out->closureProbeAttemptedStageCount++;

    if (result != MA600_RESULT_OK || !point->valid)
    {
        if (result == MA600_RESULT_OK)
        {
            stage->result = MA600_RESULT_INVALID_ARG;
        }
        return stage->result;
    }

    if (!MA600_ComputeCanonicalErrorQ16(point->pointMeanRawQ16,
            out->shadowPoint0MeanRawQ16, directionSign,
            NL_CLOSURE_POINT_INDEX, NL_POS_INCREASE,
            &stage->positionErrorRawQ16))
    {
        stage->result = MA600_RESULT_MATH_OVERFLOW;
        return stage->result;
    }

    stage->windowP2PRaw = point->maxRelRaw - point->minRelRaw;
    stage->windowDriftRaw = point->lastAcceptedUnwrapped
        - point->firstAcceptedUnwrapped;
    stage->valid = true;
    out->closureProbeValidStageCount++;
    return MA600_RESULT_OK;
}

static MA600_Result_t CaptureClosureHoldProbe(NlSweepCapture_t *out,
                                               MA600_UnwrapContext_t *shadowUnwrap,
                                               int64_t pointAnchorUnwrapped,
                                               const MA600_PointSamplerConfig_t *config,
                                               const MA600_PointSample_t *baselinePoint,
                                               int32_t commandRaw,
                                               NlSweepDirection_t direction)
{
    static const uint32_t nominalHoldMs[NL_CLOSURE_PROBE_STAGE_COUNT] = {
        0U, 50U, 100U, 200U
    };
    int32_t directionSign = (direction == NL_SWEEP_CW) ? 1 : -1;

    out->closureProbeStarted = true;
    out->postTurnTimingComparable = false;
    uint32_t probeStartTick = HAL_GetTick();

    MA600_Result_t result = RecordClosureProbeStage(out, 0U, baselinePoint,
        MA600_RESULT_OK, 0U, 0U, 0U, commandRaw, directionSign);
    if (result != MA600_RESULT_OK)
    {
        out->closureProbeAcquisitionResult = result;
        return result;
    }

    for (uint32_t stageIndex = 1U;
            stageIndex < NL_CLOSURE_PROBE_STAGE_COUNT; stageIndex++)
    {
        WaitForClosureProbeTime(probeStartTick, nominalHoldMs[stageIndex]);
        uint32_t captureStartElapsedMs = (uint32_t)(HAL_GetTick() - probeStartTick);
        MA600_PointSample_t point;
        result = MA600_ReadAveragedPoint(shadowUnwrap, pointAnchorUnwrapped,
            config, &point);
        uint32_t captureEndElapsedMs = (uint32_t)(HAL_GetTick() - probeStartTick);
        result = RecordClosureProbeStage(out, stageIndex, &point, result,
            nominalHoldMs[stageIndex], captureStartElapsedMs,
            captureEndElapsedMs, commandRaw, directionSign);
        if (result != MA600_RESULT_OK)
        {
            out->closureProbeAcquisitionResult = result;
            return result;
        }
    }

    out->closureProbeComplete = true;
    out->closureProbeAcquisitionResult = MA600_RESULT_OK;
    return MA600_RESULT_OK;
}

static void ComputeShadowMetrics(NlSweepCapture_t *out, NlSweepDirection_t direction)
{
    uint32_t startTick = HAL_GetTick();
    out->shadowCanonicalValid = false;
    out->shadowClosureValid = false;

    if (!out->shadowCanonicalEnabled || !out->shadowCanonicalStarted
            || out->shadowPoints == NULL
            || out->shadowAcquisitionResult != MA600_RESULT_OK
            || out->shadowCapturedCount != out->capturedCount
            || out->analysisCount <= 0
            || out->shadowCapturedCount <= 256)
    {
        out->shadowFeatureComputeTimeMs = HAL_GetTick() - startTick;
        return;
    }

    out->shadowPoint0MeanRawQ16 = out->shadowPoints->pointMeanRawQ16[0];
    int32_t directionSign = (direction == NL_SWEEP_CW) ? 1 : -1;
    float sum = 0.0f;
    float minError = 1.0e9f;
    float maxError = -1.0e9f;

    for (int i = 0; i < out->shadowCapturedCount; i++)
    {
        int64_t errorRawQ16 = 0;
        if (!MA600_ComputeCanonicalErrorQ16(out->shadowPoints->pointMeanRawQ16[i],
                out->shadowPoint0MeanRawQ16, directionSign, (uint32_t)i,
                NL_POS_INCREASE, &errorRawQ16))
        {
            out->shadowAcquisitionResult = MA600_RESULT_MATH_OVERFLOW;
            out->shadowFeatureComputeTimeMs = HAL_GetTick() - startTick;
            return;
        }

        float errorDeg = ShadowRawQ16ToDegrees(errorRawQ16);
        if (i < out->analysisCount)
        {
            nlSortScratch[i] = errorDeg;
            sum += errorDeg;
            if (errorDeg < minError) minError = errorDeg;
            if (errorDeg > maxError) maxError = errorDeg;
        }
        if (i == 256)
        {
            out->shadowClosureErrorRawQ16 = errorRawQ16;
            out->shadowClosureErrorDeg = errorDeg;
        }
    }

    out->shadowAnalysisCount = out->analysisCount;
    out->shadowMean = sum / (float)out->shadowAnalysisCount;
    float sumSqAc = 0.0f;
    for (int i = 0; i < out->shadowAnalysisCount; i++)
    {
        float dev = nlSortScratch[i] - out->shadowMean;
        sumSqAc += dev * dev;
    }
    out->shadowRmsAc = sqrtf(sumSqAc / (float)out->shadowAnalysisCount);

    NlHarmonicResult_t h36;
    ComputeHarmonicFull(nlSortScratch, out->shadowAnalysisCount,
        out->shadowMean, 36, &h36);
    out->shadowA36 = h36.amplitude;
    out->shadowP2P = maxError - minError;
    out->shadowLegacyMinusCanonicalRms = out->rmsAc - out->shadowRmsAc;
    out->shadowLegacyMinusCanonicalA36 = out->harmonics[8].amplitude - out->shadowA36;
    out->shadowClosureValid = fabsf(out->shadowClosureErrorDeg)
        <= NL_SHADOW_CLOSURE_LIMIT_DEG;
    out->shadowCanonicalValid = true;
    out->shadowFeatureComputeTimeMs = HAL_GetTick() - startTick;
}

#if ENABLE_AUTO_BATCH_TEST
typedef enum
{
    NL_BATCH_IDLE = 0,
    NL_BATCH_RUNNING,
    NL_BATCH_COOLDOWN,
    NL_BATCH_COMPLETE,
    NL_BATCH_ABORTED,   /* Defined but nothing sets it yet -- this hardware has no second input
                          * (e-stop, etc.) besides BTN_Pin, which is already spent starting the
                          * batch. Not inventing an abort trigger that doesn't exist; this is
                          * just a place for one to plug into later without another restructure. */
} NlBatchState_t;

static NlBatchState_t nlBatchState = NL_BATCH_IDLE;
/* CounterScope=BOOT like every other counter in this file -- resets on power cycle, not a new
 * limitation. Under NL_TEST_REPEAT_1_RUN, BatchID *is* the mount-cycle ID: each fresh button
 * press starts a new BatchID, and the operator only presses after finishing a remount, so this
 * doubles as MountCycle without a separate field. */
static uint32_t nlBatchIdCounter = 0;
static uint32_t nlBatchId;
static uint32_t nlCurrentCycle;
static uint32_t nlCooldownStartTick;
static uint32_t nlCooldownActualMs;
static bool     nlCooldownValid;
static bool     nlFirstRunInBatch;
static bool     nlPreconditionValid;
static uint32_t nlLastMotorOffTick; /* set by NonlinearTest_Run() right after Motor_Disable() --
                                      * the real "torque off" moment cooldown must be timed from,
                                      * not whenever logging/feature computation finishes after it. */
static bool     nlHasPreviousRun = false; /* Can't tell "no previous run" from nlLastMotorOffTick
                                            * == 0 -- 0 is a valid HAL_GetTick() value early in
                                            * boot -- so track it with an explicit flag instead. */

/* Wraparound-safe: HAL_GetTick() - startTick relies on unsigned subtraction wrapping modulo
 * 2^32, which gives the correct elapsed time even across a tick-counter rollover. */
static bool HasTimeElapsed(uint32_t startTick, uint32_t durationMs)
{
    return ((uint32_t)(HAL_GetTick() - startTick) >= durationMs);
}
#endif /* ENABLE_AUTO_BATCH_TEST */

static bool ControllerStateIsReset(const Motor_ControllerState_t *state)
{
    return state != NULL
        && state->integralTerm == 0.0f
        && state->lastErrorDeg == 0.0f
        && state->commandedPositionRaw == 0.0f
        && !state->feedbackTrackerInitialized
        && state->feedbackAcceptedSamples == 0U
        && state->outputElectricalPositionRaw == 0U
        && state->outputPower == 0.0f
        && !state->outputEnabled;
}

static void RecordControllerObservation(NlSweepCapture_t *capture,
    const Motor_ControllerState_t *beforeReset,
    const Motor_ControllerState_t *afterReset,
    const NlZeroObservation_t *home)
{
    if (capture == NULL || beforeReset == NULL || afterReset == NULL
            || home == NULL)
    {
        return;
    }

    capture->controllerResetApplied = true;
    capture->controllerResetStateValid = ControllerStateIsReset(afterReset);
    capture->controllerStateBeforeReset = *beforeReset;
    capture->controllerStateAfterReset = *afterReset;
    capture->homeObservation = *home;
}

/* One sweep: drives the shaft open-loop from 0 to NL_SWEEP_ANGLE_DEG in NL_POS_INCREASE
 * steps (CW: increasing; CCW: decreasing, see NlSweepDirection_t), comparing the commanded
 * position against the MA600A's reading at each step, and computes the full schema-v2
 * feature set plus the legacy stats (see ComputeSweepStats). Captures everything into `out`;
 * DOES NOT CALL LogLine (or anything that transmits over UART) ANYWHERE -- this was a
 * mandatory fix from review: printing per-point data while the motor is still moving/settling
 * changes the very dwell-time/timing conditions this whole file exists to hold constant, and
 * printing between sweeps (when multiple sweeps run per test, e.g. with CCW enabled) changes
 * inter-sweep rest time the same way. All UART output happens later, from PrintSweepLog(),
 * only after every sweep of the test has finished and Motor_Disable() has already run. */
static MA600_Result_t CaptureSweep(int runIndex, NlSweepDirection_t direction,
                                   uint32_t testId, NlSweepCapture_t *out)
{
    size_t captureSlot = (size_t)(out - nlCaptures);
    NlShadowPointStorage_t *shadowPoints = (captureSlot < NL_MAX_SWEEPS_PER_TEST)
        ? &nlShadowPointStorage[captureSlot]
        : NULL;
    memset(out, 0, sizeof(*out));
    if (shadowPoints != NULL)
    {
        memset(shadowPoints, 0, sizeof(*shadowPoints));
    }
    out->shadowPoints = shadowPoints;
    out->shadowCanonicalEnabled = shadowPoints != NULL;
    out->shadowAcquisitionResult = MA600_RESULT_OK;
    out->closureProbeEnabled = (ENABLE_CLOSURE_HOLD_PROBE != 0)
        && shadowPoints != NULL;
    out->closureProbeAcquisitionResult = MA600_RESULT_OK;
    out->postTurnTimingComparable = true;
    out->runIndex = runIndex;
    out->direction = direction;
    out->testId = testId;
    out->sweepId = ++nlSweepIdCounter;
    out->motorPoleCount = Motor_GetPoleCount();
    out->motorPolePairs = Motor_GetPolePairs();
    out->electricalRippleOrder = (uint16_t)(out->motorPolePairs
        * MOTOR_ELECTRICAL_RIPPLE_MULTIPLE);

    MA600_AcquisitionContext_t sweepAcquisition;
    MA600_AcquisitionInit(&sweepAcquisition);
    MA600_Sample_t sample;
    MA600_Result_t acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
        NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &sample);
    if (acquisitionResult != MA600_RESULT_OK)
    {
        out->acquisitionResult = acquisitionResult;
        out->acquisitionReadAttempts = sweepAcquisition.readAttempts;
        out->acquisitionRetries = sweepAcquisition.retryCount;
        out->acquisitionTransportErrors = sweepAcquisition.transportErrorCount;
        out->acquisitionJumpRejects = sweepAcquisition.jumpRejectCount;
        out->acquisitionFailedSamples = sweepAcquisition.failedSampleCount;
        return acquisitionResult;
    }

    /* Point 0 establishes the mechanical reference, but still has to prove
     * stability. Its target-proximity check is intentionally not required:
     * there is no earlier continuous-sweep origin to compare it against. */
    NlAcquisitionCounters_t settleBefore = SnapshotAcquisitionCounters(&sweepAcquisition);
    NlSettleObservation_t settleObservation;
    SetEngineState(NL_ENGINE_SETTLE);
    NlSettleResult_t settleResult = WaitForPointSettle(&sweepAcquisition,
        sample.unwrappedRaw, false, &settleObservation);
    AccumulateCounterDelta(&sweepAcquisition, &settleBefore, &out->settleAcquisition);
    if (settleResult == NL_SETTLE_ACQUISITION_ERROR)
    {
        out->acquisitionResult = settleObservation.acquisitionResult;
        out->contextAcquisition = SnapshotAcquisitionCounters(&sweepAcquisition);
        out->acquisitionReadAttempts = out->contextAcquisition.readAttempts
            - out->settleAcquisition.readAttempts;
        out->acquisitionRetries = out->contextAcquisition.retryCount
            - out->settleAcquisition.retryCount;
        out->acquisitionTransportErrors = out->contextAcquisition.transportErrorCount
            - out->settleAcquisition.transportErrorCount;
        out->acquisitionJumpRejects = out->contextAcquisition.jumpRejectCount
            - out->settleAcquisition.jumpRejectCount;
        out->acquisitionFailedSamples = out->contextAcquisition.failedSampleCount
            - out->settleAcquisition.failedSampleCount;
        return out->acquisitionResult;
    }

    settleObservation.positionErrorRaw = 0;
    settleObservation.targetProximityValid = true;
    settleObservation.valid = (settleResult == NL_SETTLE_OK)
        && settleObservation.stabilityValid;
    sample = settleObservation.finalSample;
    const int64_t sweepOriginUnwrapped = sample.unwrappedRaw;
    out->rawAtOffset = sample.raw;
    out->motorOffset = Motor_ElectricalOffset(out->rawAtOffset);
    out->angleOffsetAtStart = MA600_UnwrappedRawToDegrees(sweepOriginUnwrapped);
    out->multiTurnRawAtStart = (int32_t)sweepOriginUnwrapped;
    float angleOffset = out->angleOffsetAtStart;

    /* Shadow is an independent consumer: seed it from the accepted sweep
     * origin, then let it advance on its own. Its reads and rejects cannot
     * mutate legacy unwrap state or schema-v5 Acq* counters. */
    MA600_UnwrapContext_t shadowUnwrap = sweepAcquisition.unwrap;
    bool shadowActive = out->shadowCanonicalEnabled;
    const MA600_PointSamplerConfig_t shadowPointConfig = {
        .timingMode = MA600_POINT_TIMING_BACK_TO_BACK,
        .sampleIntervalCycles = 0U,
        .requiredAcceptedSamples = NL_SAMPLES_PER_POINT,
        .maxTransactions = NL_SHADOW_POINT_MAX_TRANSACTIONS,
        .maxConsecutiveFailures = NL_SHADOW_POINT_MAX_CONSECUTIVE_FAILURES,
        .maxElapsedCycles = MA600_DwtUsToCycles(NL_SHADOW_POINT_MAX_ELAPSED_US),
        .maxJumpRaw = NL_SWEEP_MAX_JUMP_RAW,
    };

    int32_t pos = 0;
    float sweptAngleDeg = 0.0f;
    int pointIndex = 0;
    uint32_t rampAcceptedForPoint = 0U;
    float errorMaxTrack = -1.0e9f;
    float errorMinTrack = 1.0e9f;
    float absoluteAngleAtMax = 0.0f;
    float absoluteAngleAtMin = 0.0f;
    uint16_t rawAtMax = 0;
    uint16_t rawAtMin = 0;

    while (pointIndex < NL_MAX_SWEEP_POINTS)
    {
        RecordSettleObservation(out, pointIndex, &settleObservation,
            rampAcceptedForPoint);
        const int64_t pointAnchorUnwrapped = settleObservation.finalSample.unwrappedRaw;

        /* Bring the independent shadow unwrap up to the same settled raw
         * observation. Its anchor is the immutable post-settle sample, not
         * whichever sample happened to be last after the legacy window. */
        if (shadowActive && pointIndex > 0)
        {
            int64_t shadowAnchorUnwrapped = 0;
            MA600_Result_t shadowSyncResult = MA600_UnwrapUpdate(&shadowUnwrap,
                settleObservation.finalSample.raw,
                settleObservation.finalSample.meta.csAssertCycle,
                NL_SWEEP_MAX_JUMP_RAW, &shadowAnchorUnwrapped);
            if (shadowSyncResult != MA600_RESULT_OK)
            {
                MA600_PointSample_t failedShadowPoint;
                memset(&failedShadowPoint, 0, sizeof(failedShadowPoint));
                failedShadowPoint.result = shadowSyncResult;
                RecordShadowPoint(out, pointIndex, &failedShadowPoint, shadowSyncResult);
                shadowActive = false;
            }
        }

        SetEngineState(NL_ENGINE_ACQUIRE);
        float angleSampleSum = 0.0f;
        for (int sampleCount = 0; sampleCount < NL_SAMPLES_PER_POINT; sampleCount++)
        {
            acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
                NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &sample);
            if (acquisitionResult != MA600_RESULT_OK)
            {
                goto capture_complete;
            }
            angleSampleSum += MA600_UnwrappedRawToDegrees(sample.unwrappedRaw);
            /* No inter-sample delay here (there used to be one, as a test
             * for whether residual mechanical ringing was corrupting the
             * average) -- a real "NL curve" log came back nearly identical
             * with and without it, which ruled that out: the point-to-point
             * shape is a repeatable, position-dependent signature, not
             * averaging noise, so there's nothing to gain by spreading
             * these out and it only costs time. */
        }

        float encAngle = angleSampleSum / (float)NL_SAMPLES_PER_POINT;

        sweptAngleDeg = 360.0f * fabsf((float)pos) / NL_FULL_TURN_RAW;
        float signedTargetDeg = (direction == NL_SWEEP_CW) ? sweptAngleDeg : -sweptAngleDeg;
        float error = signedTargetDeg - (encAngle - angleOffset);

        /* Absolute reference for this point, independent of this run's
         * LockStartPosition/per-capture unwrap origin: the MA600A's raw
         * reading itself, which this driver never re-zeros (MA600_Init()
         * writes no registers, ZERO0/ZERO1 are never touched), so it stays
         * tied to the sensor's own fixed factory-zero orientation across
         * every run and every jig. */
        acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
            NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &sample);
        if (acquisitionResult != MA600_RESULT_OK)
        {
            goto capture_complete;
        }
        uint16_t rawAtPoint = sample.raw;
        float absoluteAngleDeg = MA600_RawToDegrees(rawAtPoint);

        if (error > errorMaxTrack)
        {
            errorMaxTrack = error;
            absoluteAngleAtMax = absoluteAngleDeg;
            rawAtMax = rawAtPoint;
        }
        if (error < errorMinTrack)
        {
            errorMinTrack = error;
            absoluteAngleAtMin = absoluteAngleDeg;
            rawAtMin = rawAtPoint;
        }

        if (pointIndex < NL_MAX_SWEEP_POINTS)
        {
            out->errorSamples[pointIndex] = error;
            out->rawAngleSamples[pointIndex] = rawAtPoint;
            out->targetRawSamples[pointIndex] = pos;
            out->csAssertCycleSamples[pointIndex] = sample.meta.csAssertCycle;
            out->pwmCounterSamples[pointIndex] = sample.meta.pwmCounterAtCs;
            out->acquisitionAttemptSamples[pointIndex] = sample.attempts;
            out->acquisitionFlagSamples[pointIndex] = sample.flags;
        }

        /* Phase-2B only: take a second, canonical window after the official
         * legacy point is already frozen. A shadow failure is recorded and
         * disables later shadow points, but never aborts or invalidates the
         * legacy sweep. */
        if (shadowActive)
        {
            MA600_PointSample_t shadowPoint;
            MA600_Result_t shadowResult = MA600_ReadAveragedPoint(&shadowUnwrap,
                pointAnchorUnwrapped, &shadowPointConfig, &shadowPoint);
            RecordShadowPoint(out, pointIndex, &shadowPoint, shadowResult);
            if (shadowResult == MA600_RESULT_OK && out->closureProbeEnabled
                    && pointIndex == (int)NL_CLOSURE_POINT_INDEX)
            {
                /* INITIAL is the exact already-recorded Point-256 shadow
                 * window. It is copied, never re-read or overwritten. The
                 * same command/power and same shadow unwrap then continue
                 * through the three passive hold windows. */
                MA600_Result_t probeResult = CaptureClosureHoldProbe(out,
                    &shadowUnwrap, pointAnchorUnwrapped, &shadowPointConfig,
                    &shadowPoint, pos, direction);
                if (probeResult != MA600_RESULT_OK)
                {
                    acquisitionResult = probeResult;
                    shadowActive = false;
                    goto capture_complete;
                }
            }
            if (shadowResult != MA600_RESULT_OK)
            {
                shadowActive = false;
            }
        }
        pointIndex++;

        /* The current point already covers the requested >360-degree margin.
         * Stop here so the motor is not ramped to an unused extra point. */
        if (sweptAngleDeg >= NL_SWEEP_ANGLE_DEG)
        {
            break;
        }

        /* Ramp to the next point in small NL_RAMP_STEP increments instead
         * of one NL_POS_INCREASE (256-count) jump -- a single jump that
         * size is a large, abrupt commutation-angle step that made the
         * shaft visibly move in jerky bursts rather than smooth rotation.
         * Micro-stepping here produces continuous-looking motion, and by
         * removing the sudden step-and-stop at every point, is gentler on
         * motor heating too (confirmed as a real concern running back-to-back
         * sweeps on hardware). */
        int32_t targetPos = pos + ((direction == NL_SWEEP_CW) ? NL_POS_INCREASE : -NL_POS_INCREASE);
        SetEngineState(NL_ENGINE_RAMP);
        NlAcquisitionCounters_t rampBefore = SnapshotAcquisitionCounters(&sweepAcquisition);
        if (direction == NL_SWEEP_CW)
        {
            while (pos < targetPos)
            {
                pos += NL_RAMP_STEP;
                if (pos > targetPos)
                {
                    pos = targetPos;
                }
                Motor_SetElectricalPos((uint16_t)pos, 1.0f);
                osDelay(NL_RAMP_STEP_DELAY_MS);
                MA600_Sample_t rampSample;
                acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
                    NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &rampSample);
                if (acquisitionResult != MA600_RESULT_OK)
                {
                    AccumulateCounterDelta(&sweepAcquisition, &rampBefore,
                        &out->rampAcquisition);
                    goto capture_complete;
                }
            }
        }
        else
        {
            while (pos > targetPos)
            {
                pos -= NL_RAMP_STEP;
                if (pos < targetPos)
                {
                    pos = targetPos;
                }
                Motor_SetElectricalPos((uint16_t)pos, 1.0f);
                osDelay(NL_RAMP_STEP_DELAY_MS);
                MA600_Sample_t rampSample;
                acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
                    NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &rampSample);
                if (acquisitionResult != MA600_RESULT_OK)
                {
                    AccumulateCounterDelta(&sweepAcquisition, &rampBefore,
                        &out->rampAcquisition);
                    goto capture_complete;
                }
            }
        }
        AccumulateCounterDelta(&sweepAcquisition, &rampBefore, &out->rampAcquisition);
        rampAcceptedForPoint = sweepAcquisition.acceptedSamples - rampBefore.acceptedSamples;

        /* Stability alone is insufficient: a stalled rotor can be perfectly
         * stable at the wrong angle. Require stability and target proximity
         * together while preserving the same continuous unwrap context. */
        SetEngineState(NL_ENGINE_SETTLE);
        settleBefore = SnapshotAcquisitionCounters(&sweepAcquisition);
        int64_t expectedTargetUnwrapped = sweepOriginUnwrapped + (int64_t)pos;
        settleResult = WaitForPointSettle(&sweepAcquisition,
            expectedTargetUnwrapped, true, &settleObservation);
        AccumulateCounterDelta(&sweepAcquisition, &settleBefore,
            &out->settleAcquisition);
        if (settleResult == NL_SETTLE_ACQUISITION_ERROR)
        {
            acquisitionResult = settleObservation.acquisitionResult;
            goto capture_complete;
        }
    }

capture_complete:
    int capturedCount = (pointIndex < NL_MAX_SWEEP_POINTS) ? pointIndex : NL_MAX_SWEEP_POINTS;
    out->capturedCount = capturedCount;
    out->notSettledCount = out->settlePointCount - out->settleValidCount;
    out->absoluteAngleAtMax = absoluteAngleAtMax;
    out->absoluteAngleAtMin = absoluteAngleAtMin;
    out->rawAtMax = rawAtMax;
    out->rawAtMin = rawAtMin;
    out->acquisitionResult = acquisitionResult;
    out->contextAcquisition = SnapshotAcquisitionCounters(&sweepAcquisition);
    /* Frozen schema-v5 Acq* fields continue to mean the original origin +
     * 64 averaged reads + one raw read per point. Motion reads are exposed
     * separately in MOTION_RESULT and do not silently change that contract. */
    out->acquisitionReadAttempts = out->contextAcquisition.readAttempts
        - out->rampAcquisition.readAttempts - out->settleAcquisition.readAttempts;
    out->acquisitionRetries = out->contextAcquisition.retryCount
        - out->rampAcquisition.retryCount - out->settleAcquisition.retryCount;
    out->acquisitionTransportErrors = out->contextAcquisition.transportErrorCount
        - out->rampAcquisition.transportErrorCount
        - out->settleAcquisition.transportErrorCount;
    out->acquisitionJumpRejects = out->contextAcquisition.jumpRejectCount
        - out->rampAcquisition.jumpRejectCount - out->settleAcquisition.jumpRejectCount;
    out->acquisitionFailedSamples = out->contextAcquisition.failedSampleCount
        - out->rampAcquisition.failedSampleCount
        - out->settleAcquisition.failedSampleCount;

    if (acquisitionResult != MA600_RESULT_OK)
    {
        out->measurementValid = false;
        return acquisitionResult;
    }

    SetEngineState(NL_ENGINE_ANALYZE);
    uint32_t featureStartTick = HAL_GetTick();

    /* One full mechanical revolution is exactly NL_FULL_TURN_RAW/NL_POS_INCREASE points at
     * this grid (256 at the current constants) -- everything beyond that is the >360 deg
     * measurement margin, kept in DATA for offline periodicity checks but excluded here
     * since harmonic/DFT analysis assumes exactly one period. This is a compile-time-exact
     * relationship given the current constants (deterministic step accumulation, no drift),
     * checked at runtime only as a defensive guard against a future constant change that
     * breaks the 65536/NL_POS_INCREASE divisibility assumption. */
    uint32_t expectedAnalysisCount = (uint32_t)(NL_FULL_TURN_RAW / (float)NL_POS_INCREASE);
    bool divisible = (((uint32_t)NL_FULL_TURN_RAW) % NL_POS_INCREASE) == 0;
    int analysisCount = 0;
    for (int i = 0; i < capturedCount; i++)
    {
        float angleDeg = 360.0f * (float)i * (float)NL_POS_INCREASE / NL_FULL_TURN_RAW;
        if (angleDeg >= 360.0f)
        {
            break;
        }
        analysisCount++;
    }
    out->analysisCount = analysisCount;
    bool structuralValid = divisible
        && (analysisCount == (int)expectedAnalysisCount)
        && (capturedCount >= (int)expectedAnalysisCount)
        && (out->settlePointCount == capturedCount)
        && (out->settleValidCount == capturedCount);

    float sum = 0.0f;
    for (int i = 0; i < analysisCount; i++)
    {
        sum += out->errorSamples[i];
    }
    float meanVal = (analysisCount > 0) ? (sum / (float)analysisCount) : 0.0f;
    out->mean = meanVal;

    float sumSqAc = 0.0f;
    float maxAbsDev = 0.0f;
    for (int i = 0; i < analysisCount; i++)
    {
        float dev = out->errorSamples[i] - meanVal;
        sumSqAc += dev * dev;
        float absDev = fabsf(dev);
        if (absDev > maxAbsDev)
        {
            maxAbsDev = absDev;
        }
    }
    out->rmsAc = (analysisCount > 0) ? sqrtf(sumSqAc / (float)analysisCount) : 0.0f;
    out->crestFactor = (out->rmsAc > 1e-6f) ? (maxAbsDev / out->rmsAc) : 0.0f;

    for (int k = 0; k < NL_HARMONIC_COUNT; k++)
    {
        ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal, NL_HARMONIC_ORDERS[k], &out->harmonics[k]);
    }

    /* Datasheet-aligned H4/H8 -- see the NlSweepCapture_t field comment. Nyquist-safe by a wide
     * margin (order 4/8 vs. analysisCount ~256, limit ~128). */
    ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal, 4, &out->harmonicH4);
    ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal, 8, &out->harmonicH8);

    /* Six torque/ripple opportunities per electrical cycle map to order
     * 6*p over one mechanical revolution. With MOTOR_NUM_POLSE=12, p=6 and
     * this is A36. Keep fixed A36 above for historical comparison while
     * making the motor-geometry interpretation explicit and configurable. */
    out->electricalRippleValid = (out->electricalRippleOrder > 0U)
        && ((uint32_t)out->electricalRippleOrder * 2U < (uint32_t)analysisCount);
    if (out->electricalRippleValid)
    {
        ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal,
            (int)out->electricalRippleOrder, &out->electricalRippleHarmonic);
    }

    out->dominantSelectedOrder = out->harmonics[0].order;
    out->dominantSelectedAmplitude = out->harmonics[0].amplitude;
    for (int k = 1; k < NL_HARMONIC_COUNT; k++)
    {
        if (out->harmonics[k].amplitude > out->dominantSelectedAmplitude)
        {
            out->dominantSelectedAmplitude = out->harmonics[k].amplitude;
            out->dominantSelectedOrder = out->harmonics[k].order;
        }
    }
    out->dominantSelectedEnergyRatio = (out->rmsAc > NL_RMS_EPSILON)
        ? (0.5f * out->dominantSelectedAmplitude * out->dominantSelectedAmplitude) / (out->rmsAc * out->rmsAc)
        : 0.0f;

    uint8_t h6Only[1] = { 6 };
    out->residualRmsH6 = ComputeResidualRms(out->errorSamples, analysisCount, meanVal,
        out->harmonics, h6Only, 1);
    uint8_t h36Only[1] = { 36 };
    out->residualRmsH36 = ComputeResidualRms(out->errorSamples, analysisCount, meanVal,
        out->harmonics, h36Only, 1);

    /* Legacy (6-harmonic) and extended (12-harmonic) models -- see NL_LEGACY_HARMONIC_ORDERS/
     * NlSweepCapture_t's comments for why these must never share a field name. */
    NlModelMetrics_t legacy = ComputeModelMetricsByOrders(out->errorSamples, analysisCount, meanVal,
        out->harmonics, NL_HARMONIC_COUNT, NL_LEGACY_HARMONIC_ORDERS, NL_LEGACY_HARMONIC_COUNT, out->rmsAc);
    out->residualRmsFull = legacy.residualRms;
    out->fittedP2P = legacy.fittedP2P;
    out->fitExplainedRatio = legacy.explainedRatio;
    out->legacyModelValid = legacy.valid && legacy.ratioValid;

    NlModelMetrics_t extended = ComputeModelMetricsByOrders(out->errorSamples, analysisCount, meanVal,
        out->harmonics, NL_HARMONIC_COUNT, NL_HARMONIC_ORDERS, NL_HARMONIC_COUNT, out->rmsAc);
    out->residualRmsExtended = extended.residualRms;
    out->fittedP2PExtended = extended.fittedP2P;
    out->fitExplainedRatioExtended = extended.explainedRatio;
    out->extendedModelValid = extended.valid && extended.ratioValid;

    for (int i = 0; i < analysisCount; i++)
    {
        nlSortScratch[i] = fabsf(out->errorSamples[i] - meanVal);
    }
    SortAscending(nlSortScratch, analysisCount);
    int p99Idx = (int)ceilf(0.99f * (float)analysisCount) - 1;
    if (p99Idx >= analysisCount) p99Idx = analysisCount - 1;
    if (p99Idx < 0) p99Idx = 0;
    out->p99AbsDeviation = (analysisCount > 0) ? nlSortScratch[p99Idx] : 0.0f;

    out->legacyStats = ComputeSweepStats(out->errorSamples, nlSortScratch, analysisCount, NL_ROBUST_EXTREME_COUNT);

    /* Dataset-only diagnostic: how far the actually-measured angle sat from the commanded
     * target at each point, independent of the nonlinear-error math above. Lets an offline
     * consumer tell "motor has real nonlinearity" apart from "closed-loop hadn't actually
     * settled to target when this point was sampled".
     * targetRawSamples[i] (== pos) is a displacement *relative* to this sweep's own start
     * (LockStartPosition's zero-crossing), not an absolute MA600A raw angle -- rawAngleSamples[i]
     * IS absolute (the sensor is never re-zeroed). Comparing them directly without first
     * re-based pos onto the absolute frame (adding rawAtOffset, the absolute raw angle this
     * sweep started at) compares two different origins and produces a bogus ~constant offset
     * equal to rawAtOffset itself -- caught on real hardware: this showed up as a wrap-around
     * ~-25 deg "tracking error" on every single point, matching rawAtOffset's ~335 deg wrapped
     * into [-180,180), while the actual per-point nonlinear error data was ~1-2 deg. */
    float trackSumSq = 0.0f;
    float trackMaxAbs = 0.0f;
    for (int i = 0; i < capturedCount; i++)
    {
        float measuredDeg = MA600_RawToDegrees(out->rawAngleSamples[i]);
        uint16_t expectedTargetRaw = (uint16_t)((int32_t)out->rawAtOffset + out->targetRawSamples[i]);
        float targetDeg = MA600_RawToDegrees(expectedTargetRaw);
        float trackErr = WrapSignedDeg(measuredDeg - targetDeg);
        trackSumSq += trackErr * trackErr;
        float absTrackErr = fabsf(trackErr);
        if (absTrackErr > trackMaxAbs)
        {
            trackMaxAbs = absTrackErr;
        }
    }
    out->trackingErrorRmsDeg = (capturedCount > 0) ? sqrtf(trackSumSq / (float)capturedCount) : 0.0f;
    out->trackingErrorMaxAbsDeg = trackMaxAbs;
    out->trackingValid = (capturedCount > 0)
        && (out->trackingErrorRmsDeg <= NL_TRACKING_RMS_VALID_DEG)
        && (out->trackingErrorMaxAbsDeg <= NL_TRACKING_MAX_VALID_DEG);
    out->measurementValid = structuralValid && out->trackingValid;

    out->featureComputeTimeMs = HAL_GetTick() - featureStartTick;
    ComputeShadowMetrics(out, direction);
    return MA600_RESULT_OK;
}

/* Emits every UART line for one capture: META, then the full-resolution DATA curve, then
 * RESULT, then (CW only -- see below) the original legacy-named lines byte-for-byte
 * equivalent to the pre-schema-v2 output, then END. END is always the last line of this
 * capture's record, even after the legacy block -- a script can safely close the record on
 * END without risking a legacy line arriving "after" it.
 *
 * The legacy block (Motor offset / NL curve / NL harmonic1&6 / NL raw peak-to-peak /
 * NL TC percentile&rms / Nonlinear N Angle / MA600 Raw Nonlinear N Angle / MA600 Filter-Raw
 * Max Diff -- all unchanged in meaning and format from before schema v2) is only printed for
 * CW sweeps: it's what scripts/analyze_nonlinear_logs.ps1 parses into the production
 * "Nonlinear N Angle"/"Nonlinear Final Average" numbers, and those were never meant to
 * represent a CCW sweep. Printing them for CCW too (when the engineering flag is on) could
 * duplicate a run-numbered field the parser keys by number, silently shadowing the real CW
 * value -- so CCW captures only ever get the new schema-v2 (META/DATA/RESULT/END) lines. */
static void PrintClosureProbeLog(const NlSweepCapture_t *c, const char *jigId,
                                 const char *direction)
{
    for (uint32_t i = 0U; i < NL_CLOSURE_PROBE_STAGE_COUNT; i++)
    {
        const NlClosureProbeStage_t *stage = &c->closureProbeStages[i];
        if (!stage->attempted)
        {
            continue;
        }

        char pointMeanBuf[24], closureRawBuf[24], p2pRawBuf[24], driftRawBuf[24];
        char closureDegBuf[20], p2pDegBuf[20], driftDegBuf[20];
        if (stage->valid)
        {
            FormatI64(stage->point.pointMeanRawQ16,
                pointMeanBuf, sizeof(pointMeanBuf));
            FormatI64(stage->positionErrorRawQ16,
                closureRawBuf, sizeof(closureRawBuf));
            FormatI64(stage->windowP2PRaw, p2pRawBuf, sizeof(p2pRawBuf));
            FormatI64(stage->windowDriftRaw, driftRawBuf, sizeof(driftRawBuf));
            FormatDegN(ShadowRawQ16ToDegrees(stage->positionErrorRawQ16), 5,
                closureDegBuf, sizeof(closureDegBuf));
            FormatDegN(MA600_UnwrappedRawToDegrees(stage->windowP2PRaw), 5,
                p2pDegBuf, sizeof(p2pDegBuf));
            FormatDegN(MA600_UnwrappedRawToDegrees(stage->windowDriftRaw), 5,
                driftDegBuf, sizeof(driftDegBuf));
        }
        else
        {
            snprintf(pointMeanBuf, sizeof(pointMeanBuf), "NA");
            snprintf(closureRawBuf, sizeof(closureRawBuf), "NA");
            snprintf(p2pRawBuf, sizeof(p2pRawBuf), "NA");
            snprintf(driftRawBuf, sizeof(driftRawBuf), "NA");
            snprintf(closureDegBuf, sizeof(closureDegBuf), "NA");
            snprintf(p2pDegBuf, sizeof(p2pDegBuf), "NA");
            snprintf(driftDegBuf, sizeof(driftDegBuf), "NA");
        }

        LogLineLarge(
            "CLOSURE_PROBE,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
            "Direction=%s,Official=0,Protocol=%s,Stage=%s,Point=%u,CommandRaw=%ld,Power=1.00000,"
            "NominalHoldMs=%lu,CaptureStartElapsedMs=%lu,CaptureEndElapsedMs=%lu,"
            "PointMeanRawQ16=%s,ClosureErrorRawQ16=%s,ClosureErrorDeg=%s,"
            "WindowP2PRaw=%s,WindowP2PDeg=%s,WindowDriftRaw=%s,WindowDriftDeg=%s,"
            "Transactions=%lu,AcceptedSamples=%lu,SpiFailures=%lu,JumpRejects=%lu,"
            "MetadataInvalid=%lu,SkippedSlots=%lu,TimingOverruns=%lu,"
            "MaxConsecutiveFailuresObserved=%lu,AcquisitionResult=%s,Valid=%d\r\n",
            NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
            (unsigned long)c->sweepId, jigId, MOTOR_ID, direction,
            NL_CLOSURE_PROBE_PROTOCOL_ID, ClosureProbeStageName(i),
            (unsigned)NL_CLOSURE_POINT_INDEX, (long)stage->commandRaw,
            (unsigned long)stage->nominalHoldMs,
            (unsigned long)stage->captureStartElapsedMs,
            (unsigned long)stage->captureEndElapsedMs,
            pointMeanBuf, closureRawBuf, closureDegBuf,
            p2pRawBuf, p2pDegBuf, driftRawBuf, driftDegBuf,
            (unsigned long)stage->point.transactionCount,
            (unsigned long)stage->point.acceptedSampleCount,
            (unsigned long)stage->point.spiFailureCount,
            (unsigned long)stage->point.jumpRejectedCount,
            (unsigned long)stage->point.metadataInvalidCount,
            (unsigned long)stage->point.skippedSlotCount,
            (unsigned long)stage->point.timingOverrunCount,
            (unsigned long)stage->point.maxConsecutiveFailures,
            MA600_ResultName(stage->result), stage->valid ? 1 : 0);
    }

    const char *status = !c->closureProbeEnabled ? "DISABLED"
        : ((c->closureProbeComplete
                && c->closureProbeValidStageCount == NL_CLOSURE_PROBE_STAGE_COUNT
                && c->closureProbeAcquisitionResult == MA600_RESULT_OK)
            ? "VALID" : "INVALID");
    LogLineLarge(
        "CLOSURE_PROBE_RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Direction=%s,Official=0,Protocol=%s,Enabled=%d,Started=%d,Complete=%d,"
        "ExpectedStages=%u,AttemptedStages=%lu,ValidStages=%lu,"
        "PostTurnTimingComparable=%d,AcquisitionResult=%s,Status=%s\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
        (unsigned long)c->sweepId, jigId, MOTOR_ID, direction,
        NL_CLOSURE_PROBE_PROTOCOL_ID, c->closureProbeEnabled ? 1 : 0,
        c->closureProbeStarted ? 1 : 0, c->closureProbeComplete ? 1 : 0,
        (unsigned)NL_CLOSURE_PROBE_STAGE_COUNT,
        (unsigned long)c->closureProbeAttemptedStageCount,
        (unsigned long)c->closureProbeValidStageCount,
        c->postTurnTimingComparable ? 1 : 0,
        MA600_ResultName(c->closureProbeAcquisitionResult), status);
}

static void PrintSweepLog(const NlSweepCapture_t *c)
{
    const char *dirStr = (c->direction == NL_SWEEP_CW) ? "CW" : "CCW";
    bool jigKnown = false;
    const char *jigId = ResolveJigId(&jigKnown);

    char startAngleBuf[16];
    FormatDeg2(c->angleOffsetAtStart, startAngleBuf, sizeof(startAngleBuf));
    char controllerBeforeIntegralBuf[20], controllerBeforeLastErrorBuf[20];
    char controllerBeforeCommandBuf[24], controllerAfterIntegralBuf[20];
    char controllerAfterLastErrorBuf[20], controllerAfterCommandBuf[24];
    char controllerBeforeOutputPowerBuf[20], controllerAfterOutputPowerBuf[20];
    char homeInitialErrorBuf[20], homeFinalErrorBuf[20];
    FormatDegN(c->controllerStateBeforeReset.integralTerm, 5,
        controllerBeforeIntegralBuf, sizeof(controllerBeforeIntegralBuf));
    FormatDegN(c->controllerStateBeforeReset.lastErrorDeg, 5,
        controllerBeforeLastErrorBuf, sizeof(controllerBeforeLastErrorBuf));
    FormatDegN(c->controllerStateBeforeReset.commandedPositionRaw, 3,
        controllerBeforeCommandBuf, sizeof(controllerBeforeCommandBuf));
    FormatDegN(c->controllerStateAfterReset.integralTerm, 5,
        controllerAfterIntegralBuf, sizeof(controllerAfterIntegralBuf));
    FormatDegN(c->controllerStateAfterReset.lastErrorDeg, 5,
        controllerAfterLastErrorBuf, sizeof(controllerAfterLastErrorBuf));
    FormatDegN(c->controllerStateAfterReset.commandedPositionRaw, 3,
        controllerAfterCommandBuf, sizeof(controllerAfterCommandBuf));
    FormatDegN(c->controllerStateBeforeReset.outputPower, 3,
        controllerBeforeOutputPowerBuf, sizeof(controllerBeforeOutputPowerBuf));
    FormatDegN(c->controllerStateAfterReset.outputPower, 3,
        controllerAfterOutputPowerBuf, sizeof(controllerAfterOutputPowerBuf));
    FormatDegN(c->homeObservation.initialErrorDeg, 5,
        homeInitialErrorBuf, sizeof(homeInitialErrorBuf));
    FormatDegN(c->homeObservation.finalErrorDeg, 5,
        homeFinalErrorBuf, sizeof(homeFinalErrorBuf));
#if ENABLE_AUTO_BATCH_TEST
    /* Run 1 has no firmware-controlled cooldown before it -- log "NA", not a fabricated 0,
     * which would look like "0ms cooldown, perfectly on target" instead of "not applicable". */
    char cooldownTargetBuf[16], cooldownActualBuf[16], cooldownValidBuf[8];
    if (c->firstRunInBatch)
    {
        snprintf(cooldownTargetBuf, sizeof(cooldownTargetBuf), "NA");
        snprintf(cooldownActualBuf, sizeof(cooldownActualBuf), "NA");
        snprintf(cooldownValidBuf, sizeof(cooldownValidBuf), "NA");
    }
    else
    {
        snprintf(cooldownTargetBuf, sizeof(cooldownTargetBuf), "%lu", (unsigned long)c->cooldownTargetMs);
        snprintf(cooldownActualBuf, sizeof(cooldownActualBuf), "%lu", (unsigned long)c->cooldownActualMs);
        snprintf(cooldownValidBuf, sizeof(cooldownValidBuf), "%d", c->cooldownValid ? 1 : 0);
    }

    /* Distinct from firstRunInBatch: that's true on run 1 of EVERY batch, this is only false
     * once ever, on the very first run since boot -- e.g. under NL_TEST_REPEAT_1_RUN, every
     * run is firstRunInBatch=1 (batch size 1), but only the first one has no previous run. */
    char timeSincePreviousRunBuf[16];
    if (c->hasPreviousRun)
    {
        snprintf(timeSincePreviousRunBuf, sizeof(timeSincePreviousRunBuf), "%lu", (unsigned long)c->timeSincePreviousRunMs);
    }
    else
    {
        snprintf(timeSincePreviousRunBuf, sizeof(timeSincePreviousRunBuf), "NA");
    }
    const char *runRole = c->preconditionRun ? "PRECONDITION" : "OFFICIAL";
    const char *preconditionValid = c->preconditionRun ? "NA"
        : (c->preconditionValid ? "1" : "0");
#endif
    LogLineLarge(
        "META,SchemaVersion=%d,Firmware=%s,BuildID=%s,MCU_UID=%08lX%08lX%08lX,CounterScope=BOOT,"
        "JigID=%s,JigKnown=%d,MotorID=%s,MotorIDSource=%s,MotorIDValid=%d,"
        "MotorPoleCount=%u,MotorPolePairs=%u,ElectricalRippleMultiple=%u,ElectricalRippleOrder=%u,"
        "TestID=%lu,SweepID=%lu,Direction=%s,"
        "MeasurementPolicy=%s,MeasurementDefinition=%s,AcceptanceMode=%s,"
        "OfficialResultSource=LEGACY,ShadowCanonicalEnabled=%d,"
        "ShadowContractVersion=%s,ShadowOfficial=0,"
        "ClosureProbeEnabled=%d,ClosureProbeProtocol=%s,ClosureProbeOfficial=0,"
        "PhaseReference=SweepProgress,StepRaw=%d,ExpectedAnalysisPoints=%d,CapturedPoints=%d,"
        "AnalysisPoints=%d,MeasurementValid=%d,TrackingValid=%d,"
        "TrackingRmsLimitDeg=" NL_TRACKING_RMS_LIMIT_TEXT ","
        "TrackingMaxLimitDeg=" NL_TRACKING_MAX_LIMIT_TEXT ","
        "AcquisitionResult=%s,AcqReadAttempts=%lu,"
        "AcqRetries=%lu,AcqTransportErrors=%lu,AcqJumpRejects=%lu,AcqFailedSamples=%lu,"
        "ContinuousSweepContext=%s,ContextReacquireCount=%lu,RampFeedbackEnabled=1,"
        "SettleContract=%s,SettleStabilityLimitRaw=%ld,SettleTargetToleranceRaw=%ld,"
        "SettlePoints=%d,SettleStabilityValid=%d,SettleTargetProximityValid=%d,SettleValid=%d,"
        "StartRaw=%u,StartAngleDeg=%s,AnalysisStartRaw=%u,"
        "ControllerStatePolicy=%s,ControllerResetApplied=%d,ControllerResetStateValid=%d,"
        "HomeResult=%s,HomeDurationMs=%lu,HomeUpdateCount=%lu"
#if ENABLE_AUTO_BATCH_TEST
        ",BatchID=%lu,CycleOrder=%lu,RunOrder=%lu,BatchRunCount=%lu,"
        "PreconditionProtocol=%s,RunRole=%s,EligibleForStatistics=%d,PreconditionValid=%s,"
        "ThermalProtocol=%s,FirstRunInBatch=%d,"
        "MotorActiveDurationMs=%lu,CooldownTargetMs=%s,CooldownActualMs=%s,CooldownValid=%s,"
        "TimeSincePreviousRunMs=%s"
#endif
        "\r\n",
        NL_LOG_SCHEMA_VERSION, FIRMWARE_VERSION, FIRMWARE_BUILD_ID,
        (unsigned long)MCU_UID_WORD0, (unsigned long)MCU_UID_WORD1, (unsigned long)MCU_UID_WORD2,
        jigId, jigKnown ? 1 : 0, MOTOR_ID, NL_MOTOR_ID_SOURCE,
        IsMotorIdConfigured() ? 1 : 0,
        (unsigned)c->motorPoleCount, (unsigned)c->motorPolePairs,
        (unsigned)MOTOR_ELECTRICAL_RIPPLE_MULTIPLE,
        (unsigned)c->electricalRippleOrder,
        (unsigned long)c->testId, (unsigned long)c->sweepId, dirStr,
        NL_MEASUREMENT_POLICY_ID, NL_MEASUREMENT_DEFINITION, NL_ACCEPTANCE_MODE,
        c->shadowCanonicalEnabled ? 1 : 0, NL_SHADOW_CONTRACT_ID,
        c->closureProbeEnabled ? 1 : 0, NL_CLOSURE_PROBE_PROTOCOL_ID,
        NL_POS_INCREASE, (int)(NL_FULL_TURN_RAW / (float)NL_POS_INCREASE),
        c->capturedCount, c->analysisCount, c->measurementValid ? 1 : 0,
        c->trackingValid ? 1 : 0,
        MA600_ResultName(c->acquisitionResult),
        (unsigned long)c->acquisitionReadAttempts, (unsigned long)c->acquisitionRetries,
        (unsigned long)c->acquisitionTransportErrors, (unsigned long)c->acquisitionJumpRejects,
        (unsigned long)c->acquisitionFailedSamples,
        NL_CONTINUOUS_CONTEXT_ID, (unsigned long)c->contextReacquireCount,
        NL_SETTLE_CONTRACT_ID, (long)NL_POINT_SETTLE_ERROR_RAW,
        (long)NL_SETTLE_TARGET_TOLERANCE_RAW,
        c->settlePointCount,
        (c->capturedCount > 0 && c->settleStabilityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0 && c->settleTargetProximityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0 && c->settleValidCount == c->capturedCount) ? 1 : 0,
        (unsigned)c->rawAtOffset, startAngleBuf,
        (unsigned)(c->capturedCount > 0 ? c->rawAngleSamples[0] : c->rawAtOffset),
        NL_CONTROLLER_STATE_POLICY_ID, c->controllerResetApplied ? 1 : 0,
        c->controllerResetStateValid ? 1 : 0,
        NlZeroResultName(c->homeObservation.result),
        (unsigned long)c->homeObservation.durationMs,
        (unsigned long)c->homeObservation.updateCount
#if ENABLE_AUTO_BATCH_TEST
        , (unsigned long)c->batchId, (unsigned long)c->cycleOrder,
        (unsigned long)c->runOrder, (unsigned long)c->batchRunCount,
        NL_PRECONDITION_PROTOCOL_ID, runRole, c->eligibleForStatistics ? 1 : 0,
        preconditionValid, NL_THERMAL_PROTOCOL_ID, c->firstRunInBatch ? 1 : 0,
        (unsigned long)c->motorActiveDurationMs,
        cooldownTargetBuf, cooldownActualBuf, cooldownValidBuf, timeSincePreviousRunBuf
#endif
        );

    LogLineLarge(
        "CONTROL_STATE,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Direction=%s,Policy=%s,ResetApplied=%d,ResetStateValid=%d,"
        "BeforeIntegralTerm=%s,BeforeLastErrorDeg=%s,BeforeCommandRaw=%s,"
        "BeforeFeedbackInitialized=%d,BeforeFeedbackAccepted=%lu,"
        "BeforeOutputElectricalPositionRaw=%u,BeforeOutputPower=%s,BeforeOutputEnabled=%d,"
        "AfterIntegralTerm=%s,AfterLastErrorDeg=%s,AfterCommandRaw=%s,"
        "AfterFeedbackInitialized=%d,AfterFeedbackAccepted=%lu,"
        "AfterOutputElectricalPositionRaw=%u,AfterOutputPower=%s,AfterOutputEnabled=%d,"
        "HomeResult=%s,HomeDurationMs=%lu,HomeUpdateCount=%lu,"
        "HomeInitialErrorDeg=%s,HomeFinalErrorDeg=%s,"
        "HomeInitialCommandRaw=%ld,HomeFinalCommandRaw=%ld\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
        (unsigned long)c->sweepId, jigId, MOTOR_ID, dirStr,
        NL_CONTROLLER_STATE_POLICY_ID, c->controllerResetApplied ? 1 : 0,
        c->controllerResetStateValid ? 1 : 0,
        controllerBeforeIntegralBuf, controllerBeforeLastErrorBuf,
        controllerBeforeCommandBuf,
        c->controllerStateBeforeReset.feedbackTrackerInitialized ? 1 : 0,
        (unsigned long)c->controllerStateBeforeReset.feedbackAcceptedSamples,
        (unsigned)c->controllerStateBeforeReset.outputElectricalPositionRaw,
        controllerBeforeOutputPowerBuf,
        c->controllerStateBeforeReset.outputEnabled ? 1 : 0,
        controllerAfterIntegralBuf, controllerAfterLastErrorBuf,
        controllerAfterCommandBuf,
        c->controllerStateAfterReset.feedbackTrackerInitialized ? 1 : 0,
        (unsigned long)c->controllerStateAfterReset.feedbackAcceptedSamples,
        (unsigned)c->controllerStateAfterReset.outputElectricalPositionRaw,
        controllerAfterOutputPowerBuf,
        c->controllerStateAfterReset.outputEnabled ? 1 : 0,
        NlZeroResultName(c->homeObservation.result),
        (unsigned long)c->homeObservation.durationMs,
        (unsigned long)c->homeObservation.updateCount,
        homeInitialErrorBuf, homeFinalErrorBuf,
        (long)c->homeObservation.initialCommandedPositionRaw,
        (long)c->homeObservation.finalCommandedPositionRaw);

    LogLineLarge(
        "SHADOW_META,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Official=0,ContractVersion=%s,SignedConvention=%s,ReferenceDefinition=%s,"
        "CanonicalMeanSource=%s,MadFilteringEnabled=0,TimingMode=BACK_TO_BACK,"
        "RequiredAcceptedSamples=%u,MaxTransactions=%u,MaxConsecutiveFailures=%u,"
        "MaxElapsedUs=%lu,MaxJumpRaw=%ld\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
        jigId, MOTOR_ID, NL_SHADOW_CONTRACT_ID, NL_SHADOW_SIGN_CONVENTION,
        NL_SHADOW_REFERENCE_DEFINITION, NL_SHADOW_CANONICAL_MEAN_SOURCE,
        (unsigned)NL_SAMPLES_PER_POINT, (unsigned)NL_SHADOW_POINT_MAX_TRANSACTIONS,
        (unsigned)NL_SHADOW_POINT_MAX_CONSECUTIVE_FAILURES,
        (unsigned long)NL_SHADOW_POINT_MAX_ELAPSED_US, (long)NL_SWEEP_MAX_JUMP_RAW);

    for (int i = 0; i < c->capturedCount; i++)
    {
        char angleDegBuf[20], nlValBuf[20];
        float angleDeg = MA600_RawToDegrees(c->rawAngleSamples[i]);
        FormatDegN(angleDeg, 5, angleDegBuf, sizeof(angleDegBuf));
        FormatDegN(c->errorSamples[i], 5, nlValBuf, sizeof(nlValBuf));
        /* TargetRaw is logged in the SAME absolute MA600A frame as AngleRaw (rawAtOffset +
         * targetRawSamples[i], the sweep-start-relative commanded displacement) -- not the
         * bare relative pos -- so an offline consumer can directly diff AngleRaw-TargetRaw
         * without separately re-deriving rawAtOffset from META first. See the tracking-error
         * comment above for the bug this exact relative/absolute mismatch caused. */
        uint16_t targetRawAbs = (uint16_t)((int32_t)c->rawAtOffset + c->targetRawSamples[i]);
        LogLine("DATA,%d,%lu,%lu,%s,%s,%s,%d,%u,%u,%s,%s\r\n",
            NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
            jigId, MOTOR_ID, dirStr, i, (unsigned)targetRawAbs,
            (unsigned)c->rawAngleSamples[i], angleDegBuf, nlValBuf);
        LogLine("ACQ,%d,%lu,%lu,%s,%d,%lu,%u,%u,0x%02X\r\n",
            NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
            dirStr, i, (unsigned long)c->csAssertCycleSamples[i],
            (unsigned)c->pwmCounterSamples[i], (unsigned)c->acquisitionAttemptSamples[i],
            (unsigned)c->acquisitionFlagSamples[i]);

        if (c->shadowPoints != NULL && i < c->settlePointCount)
        {
            uint8_t settleFlags = c->shadowPoints->settleFlags[i];
            int64_t settleErrorRaw = c->shadowPoints->settlePositionErrorRaw[i];
            char settleErrorRawBuf[24], settleErrorDegBuf[20];
            FormatI64(settleErrorRaw, settleErrorRawBuf, sizeof(settleErrorRawBuf));
            FormatDegN(MA600_UnwrappedRawToDegrees(settleErrorRaw), 5,
                settleErrorDegBuf, sizeof(settleErrorDegBuf));
            LogLineLarge(
                "MOTION,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
                "Direction=%s,Point=%d,RampAcceptedSamples=%u,SettleResult=%s,"
                "StabilityValid=%d,TargetProximityValid=%d,SettleValid=%d,"
                "PositionErrorRaw=%s,PositionErrorDeg=%s,PollCount=%u\r\n",
                NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
                (unsigned long)c->sweepId, jigId, MOTOR_ID, dirStr, i,
                (unsigned)c->shadowPoints->rampAcceptedSamples[i],
                SettleResultName((NlSettleResult_t)c->shadowPoints->settleResults[i]),
                (settleFlags & NL_SETTLE_FLAG_STABILITY_VALID) != 0U ? 1 : 0,
                (settleFlags & NL_SETTLE_FLAG_TARGET_VALID) != 0U ? 1 : 0,
                (settleFlags & NL_SETTLE_FLAG_COMBINED_VALID) != 0U ? 1 : 0,
                settleErrorRawBuf, settleErrorDegBuf,
                (unsigned)c->shadowPoints->settlePollCount[i]);
        }

        if (c->shadowPoints != NULL && i < c->shadowCapturedCount)
        {
            int64_t shadowErrorRawQ16 = 0;
            int32_t directionSign = (c->direction == NL_SWEEP_CW) ? 1 : -1;
            if (MA600_ComputeCanonicalErrorQ16(c->shadowPoints->pointMeanRawQ16[i],
                    c->shadowPoints->pointMeanRawQ16[0], directionSign, (uint32_t)i,
                    NL_POS_INCREASE, &shadowErrorRawQ16))
            {
                char meanQ16Buf[24], errorQ16Buf[24], errorDegBuf[20];
                FormatI64(c->shadowPoints->pointMeanRawQ16[i], meanQ16Buf, sizeof(meanQ16Buf));
                FormatI64(shadowErrorRawQ16, errorQ16Buf, sizeof(errorQ16Buf));
                FormatDegN(ShadowRawQ16ToDegrees(shadowErrorRawQ16), 5,
                    errorDegBuf, sizeof(errorDegBuf));
                LogLine("SHADOW_DATA,%d,%lu,%lu,%s,%s,%s,%d,%s,%s,%s\r\n",
                    NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
                    (unsigned long)c->sweepId, jigId, MOTOR_ID, dirStr, i,
                    meanQ16Buf, errorQ16Buf, errorDegBuf);
            }
        }

        if (c->shadowPoints != NULL && i < c->shadowAttemptedPointCount)
        {
            LogLine("SHADOW_ACQ,%d,%lu,%lu,%s,%d,%lu,%lu,%u,%u,%u,%u,%u,%s\r\n",
                NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId,
                (unsigned long)c->sweepId, dirStr, i,
                (unsigned long)c->shadowPoints->firstAttemptCycle[i],
                (unsigned long)c->shadowPoints->elapsedCycle[i],
                (unsigned)c->shadowPoints->transactions[i],
                (unsigned)c->shadowPoints->accepted[i],
                (unsigned)c->shadowPoints->spiFailures[i],
                (unsigned)c->shadowPoints->jumpRejects[i],
                (unsigned)c->shadowPoints->metadataInvalid[i],
                MA600_ResultName((MA600_Result_t)c->shadowPoints->results[i]));
        }
    }

    char maxSettleErrorRawBuf[24], maxSettleErrorDegBuf[20];
    FormatI64(c->maxAbsSettlePositionErrorRaw,
        maxSettleErrorRawBuf, sizeof(maxSettleErrorRawBuf));
    FormatDegN(MA600_UnwrappedRawToDegrees(c->maxAbsSettlePositionErrorRaw), 5,
        maxSettleErrorDegBuf, sizeof(maxSettleErrorDegBuf));
    LogLineLarge(
        "MOTION_RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Direction=%s,ContractVersion=%s,ContinuousSweepContext=%s,ContextReacquireCount=%lu,"
        "ContextReadAttempts=%lu,ContextAcceptedSamples=%lu,ContextRetries=%lu,"
        "ContextTransportErrors=%lu,ContextJumpRejects=%lu,ContextFailedSamples=%lu,"
        "RampReadAttempts=%lu,RampAcceptedSamples=%lu,RampRetries=%lu,"
        "RampTransportErrors=%lu,RampJumpRejects=%lu,RampFailedSamples=%lu,"
        "SettleReadAttempts=%lu,SettleAcceptedSamples=%lu,SettleRetries=%lu,"
        "SettleTransportErrors=%lu,SettleJumpRejects=%lu,SettleFailedSamples=%lu,"
        "SettlePoints=%d,StabilityValidPoints=%d,TargetProximityValidPoints=%d,"
        "SettleValidPoints=%d,SettleTimeoutPoints=%d,SettleWrongPositionPoints=%d,"
        "SettleStabilityValid=%d,SettleTargetProximityValid=%d,SettleValid=%d,"
        "MaxAbsSettlePositionErrorRaw=%s,MaxAbsSettlePositionErrorDeg=%s\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
        jigId, MOTOR_ID, dirStr, NL_SETTLE_CONTRACT_ID, NL_CONTINUOUS_CONTEXT_ID,
        (unsigned long)c->contextReacquireCount,
        (unsigned long)c->contextAcquisition.readAttempts,
        (unsigned long)c->contextAcquisition.acceptedSamples,
        (unsigned long)c->contextAcquisition.retryCount,
        (unsigned long)c->contextAcquisition.transportErrorCount,
        (unsigned long)c->contextAcquisition.jumpRejectCount,
        (unsigned long)c->contextAcquisition.failedSampleCount,
        (unsigned long)c->rampAcquisition.readAttempts,
        (unsigned long)c->rampAcquisition.acceptedSamples,
        (unsigned long)c->rampAcquisition.retryCount,
        (unsigned long)c->rampAcquisition.transportErrorCount,
        (unsigned long)c->rampAcquisition.jumpRejectCount,
        (unsigned long)c->rampAcquisition.failedSampleCount,
        (unsigned long)c->settleAcquisition.readAttempts,
        (unsigned long)c->settleAcquisition.acceptedSamples,
        (unsigned long)c->settleAcquisition.retryCount,
        (unsigned long)c->settleAcquisition.transportErrorCount,
        (unsigned long)c->settleAcquisition.jumpRejectCount,
        (unsigned long)c->settleAcquisition.failedSampleCount,
        c->settlePointCount, c->settleStabilityValidCount,
        c->settleTargetProximityValidCount, c->settleValidCount,
        c->settleTimeoutCount, c->settleWrongPositionCount,
        (c->capturedCount > 0 && c->settleStabilityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0
            && c->settleTargetProximityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0 && c->settleValidCount == c->capturedCount) ? 1 : 0,
        maxSettleErrorRawBuf, maxSettleErrorDegBuf);

    char ampBuf[NL_HARMONIC_COUNT][16];
    char phaseBuf[NL_HARMONIC_COUNT][16];
    unsigned phaseValidMask = 0;
    for (int k = 0; k < NL_HARMONIC_COUNT; k++)
    {
        FormatDegN(c->harmonics[k].amplitude, 4, ampBuf[k], sizeof(ampBuf[k]));
        FormatDegN(c->harmonics[k].phaseDeg, 4, phaseBuf[k], sizeof(phaseBuf[k]));
        if (c->harmonics[k].phaseValid)
        {
            phaseValidMask |= (1u << k);
        }
    }

    /* Datasheet-aligned H4/H8 -- bits 12/13 are a pure append to PhaseValidMask, bits 0-11
     * keep their exact existing meaning (order 1..108, see the comment above). */
    char ampBufH4[16], phaseBufH4[16], ampBufH8[16], phaseBufH8[16];
    char electricalRippleAmpBuf[16], electricalRipplePhaseBuf[16];
    FormatDegN(c->harmonicH4.amplitude, 4, ampBufH4, sizeof(ampBufH4));
    FormatDegN(c->harmonicH4.phaseDeg, 4, phaseBufH4, sizeof(phaseBufH4));
    FormatDegN(c->harmonicH8.amplitude, 4, ampBufH8, sizeof(ampBufH8));
    FormatDegN(c->harmonicH8.phaseDeg, 4, phaseBufH8, sizeof(phaseBufH8));
    FormatDegN(c->electricalRippleHarmonic.amplitude, 4,
        electricalRippleAmpBuf, sizeof(electricalRippleAmpBuf));
    FormatDegN(c->electricalRippleHarmonic.phaseDeg, 4,
        electricalRipplePhaseBuf, sizeof(electricalRipplePhaseBuf));
    if (c->harmonicH4.phaseValid) phaseValidMask |= (1u << 12);
    if (c->harmonicH8.phaseValid) phaseValidMask |= (1u << 13);

    char meanBuf[16], rmsAcBuf[16], resH6Buf[16], resH36Buf[16];
    char resFullBuf[16], fittedBuf[16], ferBuf[16];
    char resExtBuf[16], fittedExtBuf[16], ferExtBuf[16];
    char crestBuf[16], p99Buf[16], trkRmsBuf[16], trkMaxBuf[16];
    char domAmpBuf[16], domEnergyBuf[16];
    char motorP2PBuf[16], motorInlBuf[16];
    FormatDegN(c->mean, 4, meanBuf, sizeof(meanBuf));
    FormatDegN(c->rmsAc, 4, rmsAcBuf, sizeof(rmsAcBuf));
    FormatDegN(c->residualRmsH6, 4, resH6Buf, sizeof(resH6Buf));
    FormatDegN(c->residualRmsH36, 4, resH36Buf, sizeof(resH36Buf));
    FormatDegN(c->residualRmsFull, 4, resFullBuf, sizeof(resFullBuf));
    FormatDegN(c->fittedP2P, 4, fittedBuf, sizeof(fittedBuf));
    FormatDegN(c->fitExplainedRatio, 4, ferBuf, sizeof(ferBuf));
    FormatDegN(c->residualRmsExtended, 4, resExtBuf, sizeof(resExtBuf));
    FormatDegN(c->fittedP2PExtended, 4, fittedExtBuf, sizeof(fittedExtBuf));
    FormatDegN(c->fitExplainedRatioExtended, 4, ferExtBuf, sizeof(ferExtBuf));
    FormatDegN(c->crestFactor, 4, crestBuf, sizeof(crestBuf));
    FormatDegN(c->p99AbsDeviation, 4, p99Buf, sizeof(p99Buf));
    FormatDegN(c->trackingErrorRmsDeg, 4, trkRmsBuf, sizeof(trkRmsBuf));
    FormatDegN(c->trackingErrorMaxAbsDeg, 4, trkMaxBuf, sizeof(trkMaxBuf));
    FormatDegN(c->dominantSelectedAmplitude, 4, domAmpBuf, sizeof(domAmpBuf));
    FormatDegN(c->dominantSelectedEnergyRatio, 4, domEnergyBuf, sizeof(domEnergyBuf));
    /* Raw measured-curve peak-to-peak (max-min of c->errorSamples, via legacyStats.rawPP --
     * already computed, not a new calculation) and the MA600A-datasheet INL formula
     * (P2P/2) applied to it. See the file-header comment: this is a SYSTEM value (motor +
     * magnet + mounting + jig + MA600A), never comparable to the datasheet's own sensor-only
     * INL spec without an independent reference encoder, which this jig does not have. */
    FormatDegN(c->legacyStats.rawPP, 4, motorP2PBuf, sizeof(motorP2PBuf));
    FormatDegN(c->legacyStats.rawPP / 2.0f, 4, motorInlBuf, sizeof(motorInlBuf));

    /* Field order matches NL_HARMONIC_ORDERS = {1,2,3,6,9,12,18,27,36,45,72,108} exactly --
     * ampBuf[k]/phaseBuf[k] is harmonic order NL_HARMONIC_ORDERS[k]. PhaseValidMask bit k
     * mirrors that same order (bit 0 = H1's phase valid, ... bit 11 = H108's). Bits 12/13 are
     * the standalone datasheet-aligned H4/H8 (bit 12 = H4, bit 13 = H8) -- appended, not part
     * of the order-1..108 sequence above. */
    LogLineLarge(
        "RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,Direction=%s,"
        "CapturedPoints=%d,AnalysisPoints=%d,MeanDC=%s,RMS_AC=%s,"
        "A1=%s,A2=%s,A3=%s,A6=%s,A9=%s,A12=%s,A18=%s,A27=%s,A36=%s,A45=%s,A72=%s,A108=%s,"
        "H1_PhaseSweepDeg=%s,H2_PhaseSweepDeg=%s,H3_PhaseSweepDeg=%s,H6_PhaseSweepDeg=%s,"
        "H9_PhaseSweepDeg=%s,H12_PhaseSweepDeg=%s,H18_PhaseSweepDeg=%s,H27_PhaseSweepDeg=%s,"
        "H36_PhaseSweepDeg=%s,H45_PhaseSweepDeg=%s,H72_PhaseSweepDeg=%s,H108_PhaseSweepDeg=%s,"
        "A4=%s,H4_PhaseSweepDeg=%s,A8=%s,H8_PhaseSweepDeg=%s,"
        "MotorPoleCount=%u,MotorPolePairs=%u,ElectricalRippleMultiple=%u,ElectricalRippleOrder=%u,"
        "AElectrical6=%s,Electrical6_PhaseSweepDeg=%s,ElectricalRippleValid=%d,"
        "PhaseValidMask=0x%04X,"
        "DominantSelectedOrder=%u,DominantSelectedAmplitude=%s,DominantSelectedEnergyRatio=%s,"
        "LegacyModelId=HSET6_V1,LegacyOrders=1|2|3|6|12|18,LegacyModelValid=%d,"
        "Residual_RMS_H6=%s,Residual_RMS_H36=%s,Residual_RMS_Full=%s,Fitted_P2P=%s,FitExplainedRatio=%s,"
        "ExtendedModelId=HSET12_V1,ExtendedOrders=1|2|3|6|9|12|18|27|36|45|72|108,ExtendedModelValid=%d,"
        "Residual_RMS_Extended=%s,Fitted_P2P_Extended=%s,FitExplainedRatio_Extended=%s,"
        "Motor_Error_P2P_Deg=%s,Motor_System_INL_Deg=%s,"
        "CrestFactor=%s,P99_AbsDeviation=%s,TrackingValid=%d,TrackingError_RMS_Deg=%s,"
        "TrackingError_MaxAbs_Deg=%s,FeatureComputeTimeMs=%lu\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
        jigId, MOTOR_ID, dirStr, c->capturedCount, c->analysisCount, meanBuf, rmsAcBuf,
        ampBuf[0], ampBuf[1], ampBuf[2], ampBuf[3], ampBuf[4], ampBuf[5],
        ampBuf[6], ampBuf[7], ampBuf[8], ampBuf[9], ampBuf[10], ampBuf[11],
        phaseBuf[0], phaseBuf[1], phaseBuf[2], phaseBuf[3], phaseBuf[4], phaseBuf[5],
        phaseBuf[6], phaseBuf[7], phaseBuf[8], phaseBuf[9], phaseBuf[10], phaseBuf[11],
        ampBufH4, phaseBufH4, ampBufH8, phaseBufH8,
        (unsigned)c->motorPoleCount, (unsigned)c->motorPolePairs,
        (unsigned)MOTOR_ELECTRICAL_RIPPLE_MULTIPLE,
        (unsigned)c->electricalRippleOrder, electricalRippleAmpBuf,
        electricalRipplePhaseBuf, c->electricalRippleValid ? 1 : 0,
        phaseValidMask,
        (unsigned)c->dominantSelectedOrder, domAmpBuf, domEnergyBuf,
        c->legacyModelValid ? 1 : 0,
        resH6Buf, resH36Buf, resFullBuf, fittedBuf, ferBuf,
        c->extendedModelValid ? 1 : 0,
        resExtBuf, fittedExtBuf, ferExtBuf,
        motorP2PBuf, motorInlBuf,
        crestBuf, p99Buf, c->trackingValid ? 1 : 0, trkRmsBuf, trkMaxBuf,
        (unsigned long)c->featureComputeTimeMs);

    char shadowMeanBuf[20], shadowRmsBuf[20], shadowA36Buf[20], shadowP2PBuf[20];
    char shadowClosureBuf[20], shadowRmsDeltaBuf[20], shadowA36DeltaBuf[20];
    char shadowPoint0Q16Buf[24], shadowClosureQ16Buf[24], shadowError0Q16Buf[24];
    FormatDegN(c->shadowMean, 5, shadowMeanBuf, sizeof(shadowMeanBuf));
    FormatDegN(c->shadowRmsAc, 5, shadowRmsBuf, sizeof(shadowRmsBuf));
    FormatDegN(c->shadowA36, 5, shadowA36Buf, sizeof(shadowA36Buf));
    FormatDegN(c->shadowP2P, 5, shadowP2PBuf, sizeof(shadowP2PBuf));
    FormatDegN(c->shadowClosureErrorDeg, 5, shadowClosureBuf, sizeof(shadowClosureBuf));
    FormatDegN(c->shadowLegacyMinusCanonicalRms, 5,
        shadowRmsDeltaBuf, sizeof(shadowRmsDeltaBuf));
    FormatDegN(c->shadowLegacyMinusCanonicalA36, 5,
        shadowA36DeltaBuf, sizeof(shadowA36DeltaBuf));
    if (c->shadowCapturedCount > 0)
    {
        FormatI64(c->shadowPoint0MeanRawQ16,
            shadowPoint0Q16Buf, sizeof(shadowPoint0Q16Buf));
        FormatI64(0, shadowError0Q16Buf, sizeof(shadowError0Q16Buf));
    }
    else
    {
        snprintf(shadowPoint0Q16Buf, sizeof(shadowPoint0Q16Buf), "NA");
        snprintf(shadowError0Q16Buf, sizeof(shadowError0Q16Buf), "NA");
    }
    if (c->shadowCanonicalValid)
    {
        FormatI64(c->shadowClosureErrorRawQ16,
            shadowClosureQ16Buf, sizeof(shadowClosureQ16Buf));
    }
    else
    {
        snprintf(shadowClosureQ16Buf, sizeof(shadowClosureQ16Buf), "NA");
    }

    LogLineLarge(
        "SHADOW_RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Official=0,ContractVersion=%s,Valid=%d,AnalysisPoints=%d,MeanDC=%s,RMS_AC=%s,"
        "A36=%s,P2P=%s,Point0MeanRawQ16=%s,Error0RawQ16=%s,"
        "ClosureErrorRawQ16=%s,ClosureErrorDeg=%s,ClosureLimitDeg=0.20000,ClosureValid=%d,"
        "LegacyMinusCanonicalRMS=%s,LegacyMinusCanonicalA36=%s,"
        "AttemptedPoints=%d,CapturedPoints=%d,Transactions=%lu,AcceptedSamples=%lu,"
        "SpiFailures=%lu,JumpRejects=%lu,MetadataInvalid=%lu,FailedPoints=%lu,"
        "SkippedSlots=%lu,TimingOverruns=%lu,MaxAbsTimingErrorCycles=%lu,"
        "MaxConsecutiveFailuresObserved=%lu,FeatureComputeTimeMs=%lu\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
        jigId, MOTOR_ID, NL_SHADOW_CONTRACT_ID, c->shadowCanonicalValid ? 1 : 0,
        c->shadowAnalysisCount, shadowMeanBuf, shadowRmsBuf, shadowA36Buf, shadowP2PBuf,
        shadowPoint0Q16Buf, shadowError0Q16Buf, shadowClosureQ16Buf, shadowClosureBuf,
        c->shadowClosureValid ? 1 : 0, shadowRmsDeltaBuf, shadowA36DeltaBuf,
        c->shadowAttemptedPointCount, c->shadowCapturedCount,
        (unsigned long)c->shadowTransactionCount,
        (unsigned long)c->shadowAcceptedSampleCount,
        (unsigned long)c->shadowSpiFailureCount,
        (unsigned long)c->shadowJumpRejectedCount,
        (unsigned long)c->shadowMetadataInvalidCount,
        (unsigned long)c->shadowFailedPointCount,
        (unsigned long)c->shadowSkippedSlotCount,
        (unsigned long)c->shadowTimingOverrunCount,
        (unsigned long)c->shadowMaxAbsTimingErrorCycles,
        (unsigned long)c->shadowMaxConsecutiveFailuresObserved,
        (unsigned long)c->shadowFeatureComputeTimeMs);

    PrintClosureProbeLog(c, jigId, dirStr);

    LogLineLarge(
        "SHADOW_END,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,"
        "Official=0,Started=%d,"
        "AttemptedPoints=%d,CapturedPoints=%d,AcquisitionResult=%s,Status=%s\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId,
        jigId, MOTOR_ID, c->shadowCanonicalStarted ? 1 : 0,
        c->shadowAttemptedPointCount,
        c->shadowCapturedCount, MA600_ResultName(c->shadowAcquisitionResult),
        c->shadowCanonicalValid ? "VALID" : "INVALID");

    bool emitLegacyResult = true;
#if ENABLE_AUTO_BATCH_TEST
    emitLegacyResult = c->eligibleForStatistics;
#endif
    if (c->direction == NL_SWEEP_CW && c->measurementValid && emitLegacyResult)
    {
        int runIndex = c->runIndex;

        LogLine("Motor offset: %u\r\n", (unsigned)c->motorOffset);
        char offsetBuf[16];
        FormatDeg2(c->angleOffsetAtStart, offsetBuf, sizeof(offsetBuf));
        LogLine("Motor angle offset: %s degree\r\n", offsetBuf);
        LogLine("MA600 start raw=%u count=%ld filtered=%s rawAngle=%s degree\r\n",
            (unsigned)c->rawAtOffset, (long)c->multiTurnRawAtStart, offsetBuf, offsetBuf);

        for (int i = 0; i < c->capturedCount; i++)
        {
            if (runIndex >= NL_SKIP_FIRST_COUNT && (i % NL_CURVE_LOG_DECIMATION) == 0)
            {
                float angleDeg = 360.0f * (float)i * (float)NL_POS_INCREASE / NL_FULL_TURN_RAW;
                char angleBuf[16], pointErrBuf[16];
                FormatDeg2(angleDeg, angleBuf, sizeof(angleBuf));
                FormatDeg2(c->errorSamples[i], pointErrBuf, sizeof(pointErrBuf));
                LogLine("NL curve %d: angle=%s error=%s deg\r\n", runIndex + 1, angleBuf, pointErrBuf);
            }
        }

        LogLine("NL points not settled within %ldms %d: %d/%d\r\n",
            (long)NL_POINT_SETTLE_TIMEOUT_MS, runIndex + 1, c->notSettledCount, c->capturedCount);

        char maxAbsBuf[16], minAbsBuf[16];
        FormatDeg2(c->absoluteAngleAtMax, maxAbsBuf, sizeof(maxAbsBuf));
        FormatDeg2(c->absoluteAngleAtMin, minAbsBuf, sizeof(minAbsBuf));
        LogLine("NL absolute extrema %d: max_raw=%u (%s deg) min_raw=%u (%s deg)\r\n",
            runIndex + 1, (unsigned)c->rawAtMax, maxAbsBuf, (unsigned)c->rawAtMin, minAbsBuf);

        const NlHarmonicResult_t *h1 = FindHarmonic(c->harmonics, NL_HARMONIC_COUNT, 1);
        const NlHarmonicResult_t *h6 = FindHarmonic(c->harmonics, NL_HARMONIC_COUNT, 6);

        char h1AmpBuf[16], h1PhaseBuf[16];
        FormatDeg2(h1 ? h1->amplitude : 0.0f, h1AmpBuf, sizeof(h1AmpBuf));
        FormatDeg2(h1 ? h1->phaseDeg : 0.0f, h1PhaseBuf, sizeof(h1PhaseBuf));
        LogLine("NL harmonic1 (mounting/concentricity signature) %d: amplitude=%s phase=%s deg\r\n",
            runIndex + 1, h1AmpBuf, h1PhaseBuf);

        /* Label corrected on real hardware data: the original "(motor cogging signature,
         * 12-pole)" claim assumed harmonic 6 would dominate, but it was found to be ~15x
         * smaller than harmonic 36 (see the NL_HARMONIC_ORDERS comment) -- kept only as a
         * historical reference point, not a cogging signature. */
        char h6AmpBuf[16], h6PhaseBuf[16];
        FormatDeg2(h6 ? h6->amplitude : 0.0f, h6AmpBuf, sizeof(h6AmpBuf));
        FormatDeg2(h6 ? h6->phaseDeg : 0.0f, h6PhaseBuf, sizeof(h6PhaseBuf));
        LogLine("NL harmonic6 (historical reference, see RESULT's DominantSelectedOrder) %d: amplitude=%s phase=%s deg\r\n",
            runIndex + 1, h6AmpBuf, h6PhaseBuf);

        char domAmpBuf2[16];
        FormatDeg2(c->dominantSelectedAmplitude, domAmpBuf2, sizeof(domAmpBuf2));
        LogLine("NL dominant harmonic %d: order=%u amplitude=%s deg\r\n",
            runIndex + 1, (unsigned)c->dominantSelectedOrder, domAmpBuf2);

        char rawBuf[16];
        FormatDeg2(c->legacyStats.rawPP, rawBuf, sizeof(rawBuf));
        LogLine("NL raw peak-to-peak %d (single max-min, for comparison): %s degree\r\n",
            runIndex + 1, rawBuf);

        char p5Buf[16], p95Buf[16], pctBuf[16];
        FormatDeg2(c->legacyStats.percentileLow, p5Buf, sizeof(p5Buf));
        FormatDeg2(c->legacyStats.percentileHigh, p95Buf, sizeof(p95Buf));
        FormatDeg2(c->legacyStats.percentilePP, pctBuf, sizeof(pctBuf));
        LogLine("NL TC percentile %d: P5=%s P95=%s range=%s degree\r\n",
            runIndex + 1, p5Buf, p95Buf, pctBuf);

        char rmsBuf[16];
        FormatDeg2(c->legacyStats.rms, rmsBuf, sizeof(rmsBuf));
        LogLine("NL TC rms %d: %s degree\r\n", runIndex + 1, rmsBuf);

        char errBuf[16];
        FormatDeg2(c->legacyStats.robustPP, errBuf, sizeof(errBuf));
        LogLine("Nonlinear %d Angle: %s degree\r\n", runIndex + 1, errBuf);
        /* Same value as above (see the original filterRawDiffMax note) -- kept so the
         * existing log parser's "raw" columns are populated too. */
        LogLine("MA600 Raw Nonlinear %d Angle: %s degree\r\n", runIndex + 1, errBuf);

        char diffBuf[16];
        FormatDeg2(0.0f, diffBuf, sizeof(diffBuf));
        LogLine("MA600 Filter-Raw Max Diff %d: %s degree\r\n", runIndex + 1, diffBuf);
    }
    else if (c->direction == NL_SWEEP_CW && !c->measurementValid)
    {
        LogLine("Nonlinear %d INVALID: tracking=%d acquisition=%s settled=%d/%d\r\n",
            c->runIndex + 1, c->trackingValid ? 1 : 0,
            MA600_ResultName(c->acquisitionResult),
            c->capturedCount - c->notSettledCount, c->capturedCount);
    }

    LogLineLarge(
        "END,SchemaVersion=%d,TestID=%lu,SweepID=%lu,Direction=%s,CapturedPoints=%d,"
        "AnalysisPoints=%d,TrackingValid=%d,SettleStabilityValid=%d,"
        "SettleTargetProximityValid=%d,SettleValid=%d,AcquisitionResult=%s,Status=%s\r\n",
        NL_LOG_SCHEMA_VERSION, (unsigned long)c->testId, (unsigned long)c->sweepId, dirStr,
        c->capturedCount, c->analysisCount, c->trackingValid ? 1 : 0,
        (c->capturedCount > 0 && c->settleStabilityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0
            && c->settleTargetProximityValidCount == c->capturedCount) ? 1 : 0,
        (c->capturedCount > 0 && c->settleValidCount == c->capturedCount) ? 1 : 0,
        MA600_ResultName(c->acquisitionResult),
        c->measurementValid ? "VALID" : "INVALID");
}

#if ENABLE_NL_MATH_SELF_TEST
/* Runs the real feature-computation pipeline (ComputeHarmonicFull / ComputeResidualRms /
 * ComputeFittedMinMaxDense) against synthetic curves with known closed-form answers,
 * independent of the motor/MA600A -- catches C-level bugs (wrong index, buffer-scratch
 * clobbered too early, wrong phase convention, FormatDegN losing a sign) that a purely
 * on-paper formula check cannot. The formulas themselves were cross-checked against an
 * independent reimplementation before this was written; expected values below match that
 * cross-check's output.
 * Case 1: x=1.5+2.0*cos(6*theta+30deg) -> expect mean~1.5000 rms_ac~1.4142 A6~2.0000
 *         others~0 residual_H6~0 residual_full~0 fitted_p2p~4.0000
 * Case 2: x=0.4+1.2*cos(6*theta)+0.3*cos(12*theta)-0.2*sin(3*theta) -> expect A3~0.2000
 *         A6~1.2000 A12~0.3000 others~0 residual_full~0 (residual_H6 nonzero -- A3/A12
 *         energy still present) */
static float NlSelfTestCase1(float thetaDeg)
{
    return 1.5f + 2.0f * cosf((6.0f * thetaDeg + 30.0f) * (float)M_PI / 180.0f);
}

static float NlSelfTestCase2(float thetaDeg)
{
    return 0.4f
        + 1.2f * cosf(6.0f * thetaDeg * (float)M_PI / 180.0f)
        + 0.3f * cosf(12.0f * thetaDeg * (float)M_PI / 180.0f)
        - 0.2f * sinf(3.0f * thetaDeg * (float)M_PI / 180.0f);
}

static void RunNlMathSelfTestCase(const char *name, float (*xFn)(float thetaDeg))
{
    static float synth[NL_MAX_SWEEP_POINTS];
    int count = (int)(NL_FULL_TURN_RAW / (float)NL_POS_INCREASE);

    for (int i = 0; i < count; i++)
    {
        float angleDeg = 360.0f * (float)i * (float)NL_POS_INCREASE / NL_FULL_TURN_RAW;
        synth[i] = xFn(angleDeg);
    }

    float sum = 0.0f;
    for (int i = 0; i < count; i++)
    {
        sum += synth[i];
    }
    float mean = sum / (float)count;

    float sumSqAc = 0.0f;
    for (int i = 0; i < count; i++)
    {
        float dev = synth[i] - mean;
        sumSqAc += dev * dev;
    }
    float rmsAc = sqrtf(sumSqAc / (float)count);

    NlHarmonicResult_t harmonics[NL_HARMONIC_COUNT];
    for (int k = 0; k < NL_HARMONIC_COUNT; k++)
    {
        ComputeHarmonicFull(synth, count, mean, NL_HARMONIC_ORDERS[k], &harmonics[k]);
    }

    uint8_t h6Only[1] = { 6 };
    float residualH6 = ComputeResidualRms(synth, count, mean, harmonics, h6Only, 1);
    /* residual_full stays ~0 even though NL_HARMONIC_ORDERS now includes orders (9, 18, 27,
     * 36, 45, 72, 108) absent from these synthetic signals -- a harmonic with ~0 true
     * amplitude just fits ~0 and contributes nothing, so adding it to the model doesn't
     * change the residual. */
    float residualFull = ComputeResidualRms(synth, count, mean, harmonics, NL_HARMONIC_ORDERS, NL_HARMONIC_COUNT);

    float fittedMax, fittedMin;
    ComputeFittedMinMaxDenseByOrders(harmonics, NL_HARMONIC_COUNT, NL_HARMONIC_ORDERS, NL_HARMONIC_COUNT,
        mean, &fittedMax, &fittedMin);
    float fittedP2P = fittedMax - fittedMin;

    char meanBuf[16], rmsBuf[16], resH6Buf[16], resFullBuf[16], p2pBuf[16];
    FormatDegN(mean, 4, meanBuf, sizeof(meanBuf));
    FormatDegN(rmsAc, 4, rmsBuf, sizeof(rmsBuf));
    FormatDegN(residualH6, 4, resH6Buf, sizeof(resH6Buf));
    FormatDegN(residualFull, 4, resFullBuf, sizeof(resFullBuf));
    FormatDegN(fittedP2P, 4, p2pBuf, sizeof(p2pBuf));
    LogLine("SELFTEST %s: mean=%s rms_ac=%s residual_H6=%s residual_full=%s fitted_p2p=%s\r\n",
        name, meanBuf, rmsBuf, resH6Buf, resFullBuf, p2pBuf);

    /* Internal formula-consistency check, not a business requirement: for a uniform target-
     * grid and integer DFT bins, RMS_AC^2 should equal residual_full^2 plus the sum of each
     * harmonic's energy (amplitude^2/2) -- Parseval's theorem. A large parseval_rel_error means
     * the 2/N scaling, mean removal, sample count, or reconstruction don't actually agree with
     * each other, independent of whether any individual number "looks reasonable" on its own. */
    float harmonicEnergy = 0.0f;
    for (int k = 0; k < NL_HARMONIC_COUNT; k++)
    {
        harmonicEnergy += 0.5f * harmonics[k].amplitude * harmonics[k].amplitude;
    }
    float parsevalExpected = residualFull * residualFull + harmonicEnergy;
    float parsevalRelError = fabsf(rmsAc * rmsAc - parsevalExpected) / fmaxf(rmsAc * rmsAc, 1e-9f);
    char parsevalBuf[16];
    FormatDegN(parsevalRelError, 6, parsevalBuf, sizeof(parsevalBuf));
    LogLine("SELFTEST %s: parseval_rel_error=%s (expect small, e.g. <0.001)\r\n", name, parsevalBuf);

    for (int k = 0; k < NL_HARMONIC_COUNT; k++)
    {
        char ampBuf[16], phaseBuf[16];
        FormatDegN(harmonics[k].amplitude, 4, ampBuf, sizeof(ampBuf));
        FormatDegN(harmonics[k].phaseDeg, 4, phaseBuf, sizeof(phaseBuf));
        LogLine("SELFTEST %s: A%u=%s phase%u=%s phaseValid%u=%d\r\n",
            name, (unsigned)harmonics[k].order, ampBuf, (unsigned)harmonics[k].order, phaseBuf,
            (unsigned)harmonics[k].order, harmonics[k].phaseValid ? 1 : 0);
    }
}

static void RunNlMathSelfTest(void)
{
    LogLine("SELFTEST begin (compare against the standalone formula cross-check)\r\n");
    RunNlMathSelfTestCase("Case1", NlSelfTestCase1);
    RunNlMathSelfTestCase("Case2", NlSelfTestCase2);
    LogLine("SELFTEST end\r\n");
}
#endif /* ENABLE_NL_MATH_SELF_TEST */

/* Phase-1 Policy-A locked gate. Both known jig UIDs independently reported
 * the same read-only profile on 2026-07-13. A physical UID must now select an
 * expected profile, and every audited field must match before motor enable. */
static bool ReadLogAndGateConfiguration(const char *configContext)
{
    if (configContext == NULL)
    {
        configContext = "UNKNOWN";
    }
    bool jigKnown = false;
    const char *jigId = ResolveJigId(&jigKnown);
    const NlKnownJig_t *knownJig = FindKnownJigByUid();
    const MA600_ExpectedConfig_t *expected = (knownJig != NULL)
        ? &knownJig->expectedConfig
        : NULL;
    MA600_Config_t config;
    MA600_Result_t readResult = MA600_ReadConfiguration(&config);
    bool readValid = (readResult == MA600_RESULT_OK) && config.valid;
    MA600_ConfigGateResult_t gateResult = readValid
        ? MA600_ValidateConfigurationLockedGate(&config, expected)
        : MA600_CONFIG_GATE_READ_INVALID;
    const char *rejectReason = MA600_ConfigGateResultName(gateResult);
    int errorCode = 0;
    if (gateResult == MA600_CONFIG_GATE_READ_INVALID)
    {
        errorCode = 507;
    }
    else if (gateResult == MA600_CONFIG_GATE_STATUS_NOT_CLEAN)
    {
        errorCode = 509;
    }
    else if (gateResult == MA600_CONFIG_GATE_CORRECTION_TABLE_NOT_ZERO)
    {
        errorCode = 508;
    }
    else if (gateResult != MA600_CONFIG_GATE_OK)
    {
        errorCode = 510;
    }

    bool policyGatePassed = (errorCode == 0);
    LogLineLarge(
        "CONFIG,RecordVersion=1,GatePolicy=POLICY_A_LOCKED_V1,"
        "ConfigContext=%s,Firmware=%s,BuildID=%s,"
        "MCU_UID=%08lX%08lX%08lX,JigID=%s,JigKnown=%d,"
        "ConfigGateSelfTest=1,PointSamplerSelfTest=1,"
        "ExpectedCalibrationState=ZERO_TABLE,ConfigReadValid=%d,ConfigValid=%d,PolicyAGatePassed=%d,"
        "AuditFieldsLocked=1,ExpectedProfileFound=%d,RejectReason=%s,"
        "ExpectedZero=0x%04X,ExpectedDir=0x%02X,ExpectedFilt=0x%02X,ExpectedStatus=0x%02X,"
        "ExpectedPrt=0x%02X,ExpectedRmapId=0x%02X,ExpectedCorrCRC32=0x%08lX,"
        "Zero=0x%04X,Dir=0x%02X,Filt=0x%02X,"
        "Status=0x%02X,Prt=0x%02X,RmapId=0x%02X,CorrNonZeroCount=%u,CorrCRC32=0x%08lX\r\n",
        configContext, FIRMWARE_VERSION, FIRMWARE_BUILD_ID,
        (unsigned long)MCU_UID_WORD0, (unsigned long)MCU_UID_WORD1, (unsigned long)MCU_UID_WORD2,
        jigId, jigKnown ? 1 : 0,
        readValid ? 1 : 0, policyGatePassed ? 1 : 0, policyGatePassed ? 1 : 0,
        expected != NULL ? 1 : 0, rejectReason,
        expected != NULL ? (unsigned)expected->zero : 0U,
        expected != NULL ? (unsigned)expected->dir : 0U,
        expected != NULL ? (unsigned)expected->filt : 0U,
        expected != NULL ? (unsigned)expected->status : 0U,
        expected != NULL ? (unsigned)expected->prt : 0U,
        expected != NULL ? (unsigned)expected->rmapId : 0U,
        expected != NULL ? (unsigned long)expected->corrCrc32 : 0UL,
        (unsigned)config.zero, (unsigned)config.dir, (unsigned)config.filt,
        (unsigned)config.status, (unsigned)config.prt, (unsigned)config.rmapId,
        (unsigned)config.corrNonZeroCount, (unsigned long)config.corrCrc32);

    if (!policyGatePassed)
    {
        LogLine("Motor ERROR: E%d (MA600 config gate rejected: %s)!\r\n",
            errorCode, rejectReason);
    }
    return policyGatePassed;
}

/* The atomic full-sweep unit. The batch state machine calls the same acquisition/motion path
 * once as PRECONDITION and then ten times as OFFICIAL; only result eligibility differs. With
 * ENABLE_AUTO_BATCH_TEST off, the signature and behavior remain the single-run passthrough. */
#if ENABLE_AUTO_BATCH_TEST
static bool NonlinearTest_Run(uint32_t batchId, uint32_t cycleOrder, uint32_t runOrder,
    uint32_t batchRunCount, bool preconditionRun, bool preconditionValid,
    bool firstRunInBatch, uint32_t cooldownTargetMs, uint32_t cooldownActualMs,
    bool cooldownValid)
#else
static bool NonlinearTest_Run(void)
#endif
{
    LogLine("Getting result!\r\n");

    if (!ReadLogAndGateConfiguration(
#if ENABLE_AUTO_BATCH_TEST
            preconditionRun ? "PRECONDITION_PRE_MOTOR" : "BATCH_PRE_MOTOR"
#else
            "BATCH_PRE_MOTOR"
#endif
            ))
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        return false;
    }

#if ENABLE_NL_MATH_SELF_TEST
    RunNlMathSelfTest();
    return true;
#endif

    uint32_t testId = ++nlTestIdCounter;

    /* The driver is still disabled here. Reset the software feedback/control
     * state and clear the retained PWM compare command before enabling it;
     * otherwise a later physical test can briefly replay the previous
     * sweep's endpoint even though its PID variables were reset. */
    Motor_Disable();
    Motor_ControllerState_t controllerStateBeforeReset;
    Motor_ControllerState_t controllerStateAfterReset;
    Motor_GetControllerState(&controllerStateBeforeReset);
    Motor_ResetControlSession();
    Motor_GetControllerState(&controllerStateAfterReset);
    if (!ControllerStateIsReset(&controllerStateAfterReset))
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E507 (control-session reset verification failed)!\r\n");
        return false;
    }

    Motor_Enable();
#if ENABLE_AUTO_BATCH_TEST
    uint32_t runStartTick = HAL_GetTick();
    /* Snapshot BEFORE nlLastMotorOffTick/nlHasPreviousRun get overwritten by this same run,
     * further down once Motor_Disable() runs. */
    bool     hasPreviousRun = nlHasPreviousRun;
    uint32_t timeSincePreviousRunMs = hasPreviousRun ? (runStartTick - nlLastMotorOffTick) : 0;
#endif

    float errorSum = 0.0f;
    NlZeroResult_t zeroResult = NL_ZERO_OK;
    MA600_Result_t captureResult = MA600_RESULT_OK;
    bool allMeasurementsValid = true;
    int captureCount = 0;

    for (int run = 0; run < NL_TEST_COUNT; run++)
    {
        NlZeroObservation_t homeObservation;
        zeroResult = MoveToZeroAndCheckDirection(&homeObservation);
        if (zeroResult != NL_ZERO_OK)
        {
            break;
        }

        LockStartPosition();

        captureResult = CaptureSweep(run, NL_SWEEP_CW, testId, &nlCaptures[captureCount]);
        RecordControllerObservation(&nlCaptures[captureCount],
            &controllerStateBeforeReset, &controllerStateAfterReset,
            &homeObservation);
        allMeasurementsValid = allMeasurementsValid && nlCaptures[captureCount].measurementValid;
        /* Run 1 ("Nonlinear 1") is intentionally discarded -- same
         * SKIP_FIRST_COUNT convention as the reference firmware, which
         * gives no inline rationale beyond the constant name; the working
         * theory is it lets the open-loop dither/lock settle out backlash
         * before the run that actually counts. */
        if (captureResult == MA600_RESULT_OK && nlCaptures[captureCount].measurementValid
                && run >= NL_SKIP_FIRST_COUNT)
        {
            errorSum += nlCaptures[captureCount].legacyStats.robustPP;
        }
        captureCount++;
        if (captureResult != MA600_RESULT_OK)
        {
            break;
        }

#if ENABLE_CCW_ENGINEERING_TEST
        LockStartPosition();
        captureResult = CaptureSweep(run, NL_SWEEP_CCW, testId, &nlCaptures[captureCount]);
        RecordControllerObservation(&nlCaptures[captureCount],
            &controllerStateBeforeReset, &controllerStateAfterReset,
            &homeObservation);
        allMeasurementsValid = allMeasurementsValid && nlCaptures[captureCount].measurementValid;
        /* CCW is engineering-only: not folded into errorSum/finalAverage, which stays
         * CW-based to match unchanged production semantics. */
        captureCount++;
        if (captureResult != MA600_RESULT_OK)
        {
            break;
        }
#endif
    }

    Motor_Disable();
    SetEngineState(NL_ENGINE_REPORT);
#if ENABLE_AUTO_BATCH_TEST
    /* The real "torque off" moment -- this is what a firmware-controlled cooldown must time
     * from, not whenever logging/feature computation (measured ~573ms, see FeatureComputeTimeMs)
     * happens to finish afterward. */
    uint32_t motorOffTick = HAL_GetTick();
    nlLastMotorOffTick = motorOffTick;
    nlHasPreviousRun = true;
    uint32_t motorActiveDurationMs = motorOffTick - runStartTick;
    for (int i = 0; i < captureCount; i++)
    {
        nlCaptures[i].batchId = batchId;
        nlCaptures[i].cycleOrder = cycleOrder;
        nlCaptures[i].runOrder = runOrder;
        nlCaptures[i].batchRunCount = batchRunCount;
        nlCaptures[i].preconditionRun = preconditionRun;
        nlCaptures[i].eligibleForStatistics = !preconditionRun;
        nlCaptures[i].preconditionValid = preconditionValid;
        nlCaptures[i].firstRunInBatch = firstRunInBatch;
        nlCaptures[i].cooldownTargetMs = cooldownTargetMs;
        nlCaptures[i].cooldownActualMs = cooldownActualMs;
        nlCaptures[i].cooldownValid = cooldownValid;
        nlCaptures[i].motorActiveDurationMs = motorActiveDurationMs;
        nlCaptures[i].timeSincePreviousRunMs = timeSincePreviousRunMs;
        nlCaptures[i].hasPreviousRun = hasPreviousRun;
    }
#endif

    /* Only now, with the motor fully stopped and every sweep of this test already captured,
     * does any UART logging for this test happen -- see CaptureSweep's header comment. */
    for (int i = 0; i < captureCount; i++)
    {
        PrintSweepLog(&nlCaptures[i]);
    }

    if (zeroResult == NL_ZERO_DIRECTION_ERROR)
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E502!\r\n");
        return false;
    }
    if (zeroResult == NL_ZERO_TIMEOUT)
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E503 (move-to-zero did not converge within %ld ms)!\r\n",
            (long)NL_MOVE_ZERO_TIMEOUT_MS);
        return false;
    }
    if (zeroResult == NL_ZERO_ACQUISITION_ERROR)
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E504 (move-to-zero encoder acquisition failed)!\r\n");
        return false;
    }
    if (captureResult != MA600_RESULT_OK)
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E505 (sweep acquisition failed: %s)!\r\n",
            MA600_ResultName(captureResult));
        return false;
    }
    if (!allMeasurementsValid)
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("Motor ERROR: E506 (sweep acquisition invalid; inspect META/END)!\r\n");
        return false;
    }

#if ENABLE_AUTO_BATCH_TEST
    if (preconditionRun)
    {
        LogLineLarge(
            "PRECONDITION_RESULT,SchemaVersion=%d,BatchID=%lu,CycleOrder=%lu,TestID=%lu,"
            "Protocol=%s,RunRole=PRECONDITION,EligibleForStatistics=0,Status=VALID\r\n",
            NL_LOG_SCHEMA_VERSION, (unsigned long)batchId, (unsigned long)cycleOrder,
            (unsigned long)testId, NL_PRECONDITION_PROTOCOL_ID);
        return true;
    }
#endif

    float finalAverage = errorSum / (float)NL_USED_COUNT;
    char finalBuf[16];
    FormatDeg2(finalAverage, finalBuf, sizeof(finalBuf));
    LogLine("Nonlinear Final Average: %s degree\r\n", finalBuf);
    LogLine("MA600 Raw Nonlinear Final Average: %s degree\r\n", finalBuf);

    /* WHOLE_SYSTEM_REPORT_ONLY_V1 applies no nonlinear threshold. "OK" means
     * the acquisition and protocol completed validly; it is not a sensor-INL
     * or product-quality acceptance decision. */
    LogLine("Motor OK!\r\n");
    return true;
}

#if ENABLE_AUTO_BATCH_TEST
/* Runs one physical cycle with the current batch/cooldown context, then either finishes or
 * arms the next cooldown. Cycle 1 is precondition; cycles 2..11 are official RunOrder 1..10.
 * Motor_Disable() (and therefore nlLastMotorOffTick) is already up to date when the call
 * returns. */
static void RunBatchSweep(void)
{
    bool preconditionRun = (nlCurrentCycle <= NL_PRECONDITION_COUNT);
    uint32_t officialRunOrder = preconditionRun ? 0U
        : (nlCurrentCycle - NL_PRECONDITION_COUNT);
    bool runValid = NonlinearTest_Run(nlBatchId, nlCurrentCycle, officialRunOrder,
        NL_OFFICIAL_RUN_COUNT, preconditionRun, nlPreconditionValid, nlFirstRunInBatch,
        NL_COOLDOWN_TIME_MS, nlCooldownActualMs, nlCooldownValid);
    nlFirstRunInBatch = false;

    if (!runValid)
    {
        nlBatchState = NL_BATCH_COMPLETE;
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("BATCH,BatchID=%lu,Status=FAILED,CycleOrder=%lu,RunOrder=%lu,RunRole=%s\r\n",
            (unsigned long)nlBatchId, (unsigned long)nlCurrentCycle,
            (unsigned long)officialRunOrder, preconditionRun ? "PRECONDITION" : "OFFICIAL");
        return;
    }

    if (preconditionRun)
    {
        nlPreconditionValid = true;
    }

    if (nlCurrentCycle >= NL_BATCH_TOTAL_CYCLE_COUNT)
    {
        nlBatchState = NL_BATCH_COMPLETE;
        LogLine(
            "BATCH,BatchID=%lu,Status=COMPLETE,PreconditionCount=%lu,"
            "RunCount=%lu,TotalCycleCount=%lu,PreconditionValid=1\r\n",
            (unsigned long)nlBatchId, (unsigned long)NL_PRECONDITION_COUNT,
            (unsigned long)NL_OFFICIAL_RUN_COUNT,
            (unsigned long)NL_BATCH_TOTAL_CYCLE_COUNT);
        return;
    }

    nlCooldownStartTick = nlLastMotorOffTick;
    nlCooldownActualMs = 0;
    nlCooldownValid = false;
    nlBatchState = NL_BATCH_COOLDOWN;
    SetEngineState(NL_ENGINE_COOLDOWN);
    LogLine(
        "BATCH,BatchID=%lu,Status=COOLDOWN_START,CycleOrder=%lu,RunOrder=%lu,RunRole=%s,"
        "TargetMs=%lu,Protocol=%s\r\n",
        (unsigned long)nlBatchId, (unsigned long)nlCurrentCycle,
        (unsigned long)officialRunOrder, preconditionRun ? "PRECONDITION" : "OFFICIAL",
        (unsigned long)NL_COOLDOWN_TIME_MS, NL_THERMAL_PROTOCOL_ID);
}
#endif /* ENABLE_AUTO_BATCH_TEST */

/* Call once on every detected button-press edge (see main.c's StartDefaultTask). With
 * ENABLE_AUTO_BATCH_TEST off, this is a direct passthrough to the original single-run
 * behavior -- nothing about a plain button press changes. With it on, a press starts a whole
 * one precondition cycle plus ten official runs with a firmware-timed cooldown between every
 * cycle (see NonlinearBatch_Poll). A press while running/cooling is ignored outright -- it
 * must not restart or extend the cooldown timer. */
static void NonlinearBatch_OnButtonPress(void)
{
    SetEngineState(NL_ENGINE_PRECHECK);
    /* Batch-start STATUS precheck (plan Part 1b): a stale ERRCRC/ERRMEM/
     * ERRPAR flag from before this button press must not silently ride
     * along into every run's StatusFlagsClear check. Runs once per batch
     * (not per run/per point) -- one attempt to clear, then refuse to
     * start if it's still dirty rather than "trying anyway". */
    MA600_Status_t nlPrecheckStatus;
    if (!MA600_PrecheckAndClearStatus(&nlPrecheckStatus))
    {
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine("MA600 STATUS precheck failed NVMB=%d CRC=%d MEM=%d PAR=%d; batch refused\r\n",
                nlPrecheckStatus.nvmBusy, nlPrecheckStatus.errCrc,
                nlPrecheckStatus.errMem, nlPrecheckStatus.errPar);
        return;
    }

#if ENABLE_NL_MATH_SELF_TEST
#if ENABLE_AUTO_BATCH_TEST
    /* Self-test bypasses the whole batch machine (and returns before touching any of these
     * arguments) -- values here are placeholders only, never read. */
    NonlinearTest_Run(0, 1, 1, 1, false, true, true, 0, 0, false);
#else
    NonlinearTest_Run();
#endif
    return;
#elif ENABLE_AUTO_BATCH_TEST
    if (nlBatchState == NL_BATCH_RUNNING || nlBatchState == NL_BATCH_COOLDOWN)
    {
        return;
    }
    nlBatchId = ++nlBatchIdCounter;
    nlCurrentCycle = 1;
    nlPreconditionValid = false;
    nlFirstRunInBatch = true;
    nlCooldownActualMs = 0;
    nlCooldownValid = false;
    nlBatchState = NL_BATCH_RUNNING;
    LogLine(
        "BATCH,BatchID=%lu,Status=START,PreconditionProtocol=%s,PreconditionCount=%lu,"
        "RunCount=%lu,TotalCycleCount=%lu,CooldownTargetMs=%lu\r\n",
        (unsigned long)nlBatchId, NL_PRECONDITION_PROTOCOL_ID,
        (unsigned long)NL_PRECONDITION_COUNT, (unsigned long)NL_OFFICIAL_RUN_COUNT,
        (unsigned long)NL_BATCH_TOTAL_CYCLE_COUNT, (unsigned long)NL_COOLDOWN_TIME_MS);
    RunBatchSweep();
#else
    NonlinearTest_Run();
#endif
}

/* Call once per StartDefaultTask loop iteration (~200ms cadence, unchanged) -- never blocks:
 * only compares tick counts, so the heartbeat LED / idle angle print / noise measurement all
 * keep running normally through a multi-minute cooldown. A no-op outside NL_BATCH_COOLDOWN or
 * when ENABLE_AUTO_BATCH_TEST is off. */
static void NonlinearBatch_Poll(void)
{
#if ENABLE_AUTO_BATCH_TEST
    if (nlBatchState != NL_BATCH_COOLDOWN)
    {
        return;
    }
    if (!HasTimeElapsed(nlCooldownStartTick, NL_COOLDOWN_TIME_MS))
    {
        return;
    }

    nlCooldownActualMs = HAL_GetTick() - nlCooldownStartTick;
    /* cooldownErrorMs is always >=0 here: HasTimeElapsed already confirmed actual>=target. */
    uint32_t cooldownErrorMs = nlCooldownActualMs - NL_COOLDOWN_TIME_MS;
    nlCooldownValid = (cooldownErrorMs <= NL_COOLDOWN_TOLERANCE_MS);

    if (!nlCooldownValid)
    {
        nlBatchState = NL_BATCH_COMPLETE;
        SetEngineState(NL_ENGINE_SAFE_STOP);
        LogLine(
            "BATCH,BatchID=%lu,Status=FAILED,Reason=COOLDOWN_INVALID,"
            "CompletedCycleOrder=%lu,NextCycleOrder=%lu,TargetMs=%lu,ActualMs=%lu,"
            "ToleranceMs=%lu\r\n",
            (unsigned long)nlBatchId, (unsigned long)nlCurrentCycle,
            (unsigned long)(nlCurrentCycle + 1U), (unsigned long)NL_COOLDOWN_TIME_MS,
            (unsigned long)nlCooldownActualMs, (unsigned long)NL_COOLDOWN_TOLERANCE_MS);
        return;
    }

    nlCurrentCycle++;
    nlBatchState = NL_BATCH_RUNNING;
    RunBatchSweep();
#endif
}

static void FinishEngineCommand(void)
{
    /* Defense in depth: NonlinearTest_Run() disables on every normal/error
     * path after Motor_Enable(); repeat it at the task boundary so future
     * sequencing edits cannot accidentally leave torque enabled. */
    Motor_Disable();

    UBaseType_t stackHighWaterWords = uxTaskGetStackHighWaterMark(NULL);
    LogLine("RUNTIME,FreeHeap=%lu,MinEverFreeHeap=%lu,TestStackHighWaterWords=%lu\r\n",
        (unsigned long)xPortGetFreeHeapSize(),
        (unsigned long)xPortGetMinimumEverFreeHeapSize(),
        (unsigned long)stackHighWaterWords);

    nlEngineBusy = false;
    SetEngineState(NL_ENGINE_IDLE);
}

static void NonlinearEngine_Task(void *argument)
{
    (void)argument;

    /* Read-only boot smoke: proves the locked UID profile and every pure
     * startup self-test before the operator presses the button. Busy remains
     * true during this SPI access so StartDefaultTask cannot interleave an
     * idle sensor transaction. No motor output is enabled here. */
    Motor_Disable();
    SetEngineState(NL_ENGINE_PRECHECK);
    (void)ReadLogAndGateConfiguration("BOOT_SMOKE");
    nlEngineBusy = false;
    SetEngineState(NL_ENGINE_IDLE);

    for (;;)
    {
        uint8_t command = 0;
        osStatus_t queueStatus = osMessageQueueGet(nlEngineCommandQueue,
            &command, NULL, 100U);

        if (queueStatus == osOK && command == NL_ENGINE_COMMAND_START)
        {
            NonlinearBatch_OnButtonPress();
        }

        NonlinearBatch_Poll();

#if ENABLE_AUTO_BATCH_TEST
        if (nlBatchState == NL_BATCH_COMPLETE
                || (queueStatus == osOK && nlBatchState == NL_BATCH_IDLE))
        {
            nlBatchState = NL_BATCH_IDLE;
            FinishEngineCommand();
        }
#else
        if (queueStatus == osOK)
        {
            FinishEngineCommand();
        }
#endif
    }
}

bool NonlinearEngine_Init(void)
{
    if (nlEngineCommandQueue != NULL || nlEngineTaskHandle != NULL)
    {
        return false;
    }

    nlEngineCommandQueue = osMessageQueueNew(1U, sizeof(uint8_t), NULL);
    if (nlEngineCommandQueue == NULL)
    {
        return false;
    }

    static const osThreadAttr_t testTaskAttributes = {
        .name = "TestTask",
        /* Worst static call chain is PrintSweepLog into LogLineLarge, plus
         * engine/run frames. Keep explicit margin above compiler-reported use. */
        .stack_size = 6656U,
        .priority = (osPriority_t)osPriorityAboveNormal,
    };
    nlEngineTaskHandle = osThreadNew(NonlinearEngine_Task, NULL, &testTaskAttributes);
    if (nlEngineTaskHandle == NULL)
    {
        osMessageQueueDelete(nlEngineCommandQueue);
        nlEngineCommandQueue = NULL;
        return false;
    }

    /* Keep idle diagnostics out of SPI1 until the test task has emitted its
     * read-only BOOT_SMOKE CONFIG record. */
    nlEngineBusy = true;
    SetEngineState(NL_ENGINE_IDLE);
    return true;
}

bool NonlinearEngine_RequestStart(void)
{
    if (nlEngineCommandQueue == NULL || nlEngineBusy)
    {
        return false;
    }

    nlEngineBusy = true;
    uint8_t command = NL_ENGINE_COMMAND_START;
    if (osMessageQueuePut(nlEngineCommandQueue, &command, 0U, 0U) != osOK)
    {
        nlEngineBusy = false;
        return false;
    }
    return true;
}

bool NonlinearEngine_IsBusy(void)
{
    return nlEngineBusy;
}

NonlinearEngineState_t NonlinearEngine_GetState(void)
{
    return nlEngineState;
}
