#include "control_engine.h"
#include "app_mode.h"

#if JIG_APP_MODE == JIG_APP_CONTROL

#include "motor.h"
#include "motor_config.h"
#include "ma600.h"
#include "ma600_acquisition.h"
#include "main.h"
#include "cmsis_os.h"
#include "FreeRTOS.h"
#include "task.h"
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern UART_HandleTypeDef huart3;

#define CONTROL_ENGINE_COMMAND_START          1U

/* A3 is the first phase-trajectory profile after the fixed-phase closeout
 * (docs/control-a2f-p09-result.md): A2..A2F proved no static power level both
 * safe and converging (static friction ~9-10 percent of max torque, kinetic
 * ~4 percent, observed motion direction uncorrelated with the commanded
 * field). Here the commanded phase sweeps exactly one electrical cycle with a
 * quintic S-curve, so the field is guaranteed to pass the rotor's equilibrium
 * wherever it starts and drag it to the phase-0 equivalent. There is still no
 * HOME/PID and no feedback into the trajectory; the encoder is evidence plus
 * safety only. Single variable vs A2F: the phase moves. Design record:
 * docs/control-a3-phase-trajectory-plan.md, docs/control-a3-struct-proposal.md. */
#define CONTROL_A3_PROFILE_ID                 "CONTROL_A3_ROTATING_CAPTURE_P35_V1"

/* Trajectory geometry. Raw scale: 65536/mech rev; one electrical cycle =
 * MOTOR_COUNT_PER_ELECTRICAL_CYCLE = 10923 raw = 60 mech deg. */
#define CONTROL_A3_PHASE_START_RAW            0U
#define CONTROL_A3_PHASE_SWEEP_SPAN_RAW       MOTOR_COUNT_PER_ELECTRICAL_CYCLE

/* Power: 35 percent, the C0 home precedent -- NOT the 6-9 percent band proven
 * ineffective by A2C..A2F. Capture jolt shrinks as power rises (predicted
 * ~305 raw at 35 percent, see the plan doc). */
#define CONTROL_A3_TARGET_POWER_PPM           350000U
#define CONTROL_A3_TARGET_POWER_MILLI         350U

/* Timing, 1 ms tick like A2F. Sweep cadence matches Motion V2's proven
 * 40 ms per mech degree: 60 deg -> 2400 ticks. */
#define CONTROL_A3_PERIOD_MS                  1U
#define CONTROL_A3_POWER_RAMP_TICKS           300U
#define CONTROL_A3_SWEEP_TICKS                2400U
#define CONTROL_A3_HOLD_TICKS                 500U
#define CONTROL_A3_TOTAL_TICKS                \
    (CONTROL_A3_POWER_RAMP_TICKS + CONTROL_A3_SWEEP_TICKS + CONTROL_A3_HOLD_TICKS)
#define CONTROL_A3_MAX_ACTIVE_MS              4000U

/* Evidence decimation: the run is ~3.2x longer than A2F but CCM stays 64 KB.
 * Every 3rd tick plus the final tick is recorded; guards still run at the
 * full 1 ms rate on every tick. */
#define CONTROL_A3_EVIDENCE_DECIMATION        3U
#define CONTROL_A3_MAX_EVIDENCE               \
    ((CONTROL_A3_TOTAL_TICKS / CONTROL_A3_EVIDENCE_DECIMATION) + 2U)

/* Acquisition, unchanged from A2F. */
#define CONTROL_A3_MAX_JUMP_RAW               1821
#define CONTROL_A3_READ_ATTEMPTS              3U

/* Guards -- widened from A2F with reasoning, never silently:
 * - travel: the drag can legitimately cover one full cycle (10923 raw =
 *   60 mech deg) plus ramp creep and settle overshoot;
 * - step: capture releases about asin(mu_s/P)-asin(mu_k/P) ~ 305 raw over
 *   ~10-30 ms -> expected peak 30-100 raw/ms; 150 is a reasoned ceiling;
 * - active: 300 + 2400 + 500 ticks plus margin. */
#define CONTROL_A3_MAX_TRAVEL_RAW             12000
#define CONTROL_A3_MAX_SAMPLE_STEP_RAW        150
#define CONTROL_A3_MAX_CONSECUTIVE_MISSES     3U

/* Capture criterion, evaluated every SWEEP tick over a trailing window
 * (per-tick rotor deltas are +/-1 raw quantized, so a single-tick comparison
 * is meaningless): captured when the rotor covered at least half of the
 * field displacement over the window. The field-displacement floor keeps the
 * +/-14 raw encoder noise band from faking a capture near the quintic's slow
 * endpoints, where the field barely moves per window. */
#define CONTROL_A3_CAPTURE_WINDOW_TICKS       100U
#define CONTROL_A3_CAPTURE_VELOCITY_NUM       1
#define CONTROL_A3_CAPTURE_VELOCITY_DEN       2
#define CONTROL_A3_CAPTURE_MIN_FIELD_RAW      60

/* Drag-slip guard, armed ONLY after capture latches: if the field runs more
 * than 90 elec deg (the pull-out angle) ahead of the rotor, the torque slope
 * has reversed and the rotor is lost -> safe stop. Before capture the same
 * distance is geometry (the field legitimately travels toward a stationary
 * rotor), so the guard must stay disarmed until then. */
#define CONTROL_A3_DRAG_LOSS_LAG_RAW          2731

#if CONTROL_A3_TARGET_POWER_PPM != 350000U
#error "A3 pilot must remain locked to 35 percent power"
#endif
#if CONTROL_A3_POWER_RAMP_TICKS != 300U || CONTROL_A3_SWEEP_TICKS != 2400U \
    || CONTROL_A3_HOLD_TICKS != 500U
#error "A3 pilot timing changed without a new profile identity"
#endif
#if CONTROL_A3_PHASE_SWEEP_SPAN_RAW != MOTOR_COUNT_PER_ELECTRICAL_CYCLE
#error "A3 sweep span must remain exactly one electrical cycle"
#endif

typedef enum
{
    CONTROL_A3_OK = 0,
    CONTROL_A3_STATUS_FAULT,
    CONTROL_A3_BASELINE_ACQUISITION_FAULT,
    CONTROL_A3_PRIME_FAULT,
    CONTROL_A3_ENABLE_STATE_FAULT,
    CONTROL_A3_ACQUISITION_FAULT,
    CONTROL_A3_TRAVEL_LIMIT,
    CONTROL_A3_SAMPLE_STEP_LIMIT,
    CONTROL_A3_DEADLINE_FAULT,
    CONTROL_A3_DURATION_LIMIT,
    CONTROL_A3_EVIDENCE_OVERFLOW,
    CONTROL_A3_OPERATOR_ABORT,
    CONTROL_A3_CAPTURE_FAULT,
    CONTROL_A3_DRAG_SLIP,
} ControlA3Result_t;

typedef enum
{
    CONTROL_A3_PHASE_POWER_RAMP = 0,  /* phase fixed at START_RAW, power 0->35% */
    CONTROL_A3_PHASE_SWEEP,           /* quintic phase trajectory, one cycle    */
    CONTROL_A3_PHASE_HOLD,            /* phase parked at START + span (phase 0) */
} ControlA3Phase_t;

/* 56 bytes/record. vs A2F: +commandPhaseProgressRaw, +dragLagRaw,
 * +captureLatched; -accelerationRawPerSecond2 (double-differenced noise gave
 * no decision value in A2; dragLagRaw is the quantity A3 actually acts on). */
typedef struct
{
    uint32_t sequence;                /* tick index, NOT decimated index      */
    uint32_t scheduledTick;
    uint32_t sampleTick;
    uint32_t loopCycles;
    uint32_t spiLatencyCycles;
    uint32_t latenessTicks;
    uint32_t commandPowerPpm;
    uint32_t commandPhaseProgressRaw; /* field displacement since sweep start */
    int32_t  travelRaw;               /* rotor displacement vs baseline       */
    int32_t  deltaRaw;
    int32_t  velocityRawPerSecond;
    int32_t  dragLagRaw;              /* fieldProgress - rotorProgressSinceSweepStart */
    uint16_t encoderRaw;
    uint16_t commandElectricalRaw;    /* absolute commanded phase, mod cycle  */
    uint16_t pwmCounterAtCs;
    uint8_t  phase;                   /* ControlA3Phase_t                     */
    uint8_t  captureLatched;          /* 1 from the capture tick onward       */
} ControlA3Evidence_t;

typedef struct
{
    ControlA3Result_t result;
    uint32_t activeDurationMs;
    uint32_t evidenceCount;           /* decimated records actually written   */
    uint32_t deadlineMisses;
    uint32_t maxLatenessTicks;
    uint32_t maxLoopCycles;
    uint32_t maxAbsTravelRaw;
    uint32_t maxSampleStepRaw;
    uint32_t maxAbsVelocityRawPerSecond;
    uint32_t enablePowerPpm;

    bool     captureDetected;
    uint32_t captureSeq;              /* tick where the criterion first held;
                                       * UINT32_MAX when never                */
    uint32_t capturePhaseProgressRaw;
    int32_t  dragLagMeanRaw;          /* mean over post-capture SWEEP ticks   */
    int32_t  dragLagMaxRaw;
    int32_t  rampCreepRaw;            /* rotor travel accumulated during
                                       * POWER_RAMP (the known ~0.8 deg A2
                                       * creep, now measured per run)         */

    uint16_t baselineRaw;
    uint16_t finalRaw;
    uint16_t electricalOffsetRaw;     /* finalRaw mod cycle at end of HOLD:
                                       * the encoder<->electrical offset of
                                       * this motor+mount                     */

    bool     primeStateValid;
    bool     enableStateValid;
    MA600_AcquisitionContext_t acquisition;
} ControlA3Report_t;

static osMessageQueueId_t controlCommandQueue;
static osThreadId_t controlTaskHandle;
static volatile bool controlEngineInitialized;
static volatile bool controlEngineBusy;
static volatile bool controlAbortRequested;

/* CCM is CPU-only and appropriate for deferred UART evidence, not DMA
 * buffers. NOLOAD data is explicitly cleared before every run. */
static ControlA3Evidence_t controlEvidence[CONTROL_A3_MAX_EVIDENCE]
    __attribute__((section(".ccmram_bss"), aligned(8)));

_Static_assert(sizeof(ControlA3Evidence_t) == 56U,
    "A3 evidence record layout changed -- re-audit the CCM budget");
_Static_assert(sizeof(ControlA3Evidence_t) * CONTROL_A3_MAX_EVIDENCE
    <= 60U * 1024U, "A3 evidence exceeds the CCM budget");

/* Capture-criterion history rings live in regular RAM (not CCM evidence) so
 * detection runs at the full 1 ms rate regardless of evidence decimation. */
static int32_t  controlCaptureTravelRing[CONTROL_A3_CAPTURE_WINDOW_TICKS];
static uint32_t controlCaptureFieldRing[CONTROL_A3_CAPTURE_WINDOW_TICKS];

static uint32_t AbsI32ToU32(int32_t value)
{
    return (value < 0) ? (uint32_t)(-(int64_t)value) : (uint32_t)value;
}

static int32_t RawToMilliDeg(int64_t raw)
{
    int64_t scaled = raw * 360000LL;
    if (scaled >= 0)
    {
        scaled += (int64_t)MOTOR_MECHANICAL_COUNTS_PER_REV / 2LL;
    }
    else
    {
        scaled -= (int64_t)MOTOR_MECHANICAL_COUNTS_PER_REV / 2LL;
    }
    return (int32_t)(scaled / (int64_t)MOTOR_MECHANICAL_COUNTS_PER_REV);
}

static uint32_t ControlA3PowerPpm(uint32_t sequence)
{
    if (sequence >= CONTROL_A3_POWER_RAMP_TICKS)
    {
        return CONTROL_A3_TARGET_POWER_PPM;
    }
    return (sequence * CONTROL_A3_TARGET_POWER_PPM)
        / CONTROL_A3_POWER_RAMP_TICKS;
}

/* Quintic smoothstep progress over the one-cycle sweep. Local copy of the
 * NlSmoothstepCommandRaw math (nonlinear_test.c) -- same float blend, fixed
 * endpoints -- because the Control image deliberately does not link the
 * nonlinear engine. Endpoints are clamped exact so HOLD parks at precisely
 * one electrical cycle (== phase 0 again). */
static uint32_t ControlA3PhaseProgressRaw(uint32_t sweepTick)
{
    if (sweepTick == 0U)
    {
        return 0U;
    }
    if (sweepTick >= CONTROL_A3_SWEEP_TICKS)
    {
        return CONTROL_A3_PHASE_SWEEP_SPAN_RAW;
    }
    float u = (float)sweepTick / (float)CONTROL_A3_SWEEP_TICKS;
    float blend = u * u * u * (10.0f + u * (-15.0f + 6.0f * u));
    long progress = lroundf((float)CONTROL_A3_PHASE_SWEEP_SPAN_RAW * blend);
    if (progress < 0L)
    {
        progress = 0L;
    }
    if (progress > (long)CONTROL_A3_PHASE_SWEEP_SPAN_RAW)
    {
        progress = (long)CONTROL_A3_PHASE_SWEEP_SPAN_RAW;
    }
    return (uint32_t)progress;
}

static ControlA3Phase_t ControlA3PhaseForSequence(uint32_t sequence)
{
    if (sequence < CONTROL_A3_POWER_RAMP_TICKS)
    {
        return CONTROL_A3_PHASE_POWER_RAMP;
    }
    if (sequence <= CONTROL_A3_POWER_RAMP_TICKS + CONTROL_A3_SWEEP_TICKS)
    {
        return CONTROL_A3_PHASE_SWEEP;
    }
    return CONTROL_A3_PHASE_HOLD;
}

static void ControlLog(const char *format, ...)
{
    char line[512];
    va_list args;
    va_start(args, format);
    int length = vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    if (length < 0)
    {
        return;
    }
    if (length >= (int)sizeof(line))
    {
        length = (int)sizeof(line) - 1;
    }
    HAL_UART_Transmit(&huart3, (uint8_t *)line, (uint16_t)length, 100U);
}

static const char *ControlResultName(ControlA3Result_t result)
{
    switch (result)
    {
        case CONTROL_A3_OK:                         return "OK";
        case CONTROL_A3_STATUS_FAULT:               return "STATUS_FAULT";
        case CONTROL_A3_BASELINE_ACQUISITION_FAULT: return "BASELINE_ACQUISITION_FAULT";
        case CONTROL_A3_PRIME_FAULT:                return "PRIME_FAULT";
        case CONTROL_A3_ENABLE_STATE_FAULT:         return "ENABLE_STATE_FAULT";
        case CONTROL_A3_ACQUISITION_FAULT:          return "ACQUISITION_FAULT";
        case CONTROL_A3_TRAVEL_LIMIT:               return "TRAVEL_LIMIT";
        case CONTROL_A3_SAMPLE_STEP_LIMIT:          return "SAMPLE_STEP_LIMIT";
        case CONTROL_A3_DEADLINE_FAULT:             return "DEADLINE_FAULT";
        case CONTROL_A3_DURATION_LIMIT:             return "DURATION_LIMIT";
        case CONTROL_A3_EVIDENCE_OVERFLOW:          return "EVIDENCE_OVERFLOW";
        case CONTROL_A3_OPERATOR_ABORT:             return "OPERATOR_ABORT";
        case CONTROL_A3_CAPTURE_FAULT:              return "CAPTURE_FAULT";
        case CONTROL_A3_DRAG_SLIP:                  return "DRAG_SLIP";
        default:                                    return "UNKNOWN";
    }
}

static const char *ControlPhaseName(uint8_t phase)
{
    switch (phase)
    {
        case (uint8_t)CONTROL_A3_PHASE_POWER_RAMP: return "POWER_RAMP";
        case (uint8_t)CONTROL_A3_PHASE_SWEEP:      return "PHASE_SWEEP";
        default:                                   return "ALIGN_HOLD";
    }
}

static ControlA3Result_t ControlRunAlignment(ControlA3Report_t *report,
                                              const MA600_Sample_t *baseline,
                                              uint32_t activeStartTick)
{
    Motor_Enable();
    Motor_ControllerState_t outputState;
    Motor_GetControllerState(&outputState);
    report->enablePowerPpm = (uint32_t)(outputState.outputPower * 1000000.0f
        + 0.5f);
    report->enableStateValid = outputState.outputEnabled
        && outputState.outputElectricalPositionRaw
            == CONTROL_A3_PHASE_START_RAW
        && outputState.outputPower == 0.0f;
    if (!report->enableStateValid)
    {
        return CONTROL_A3_ENABLE_STATE_FAULT;
    }

    uint32_t deadline = osKernelGetTickCount();
    uint32_t consecutiveMisses = 0U;
    int32_t previousTravelRaw = 0;
    bool captured = false;
    int64_t dragLagSum = 0;
    uint32_t dragLagCount = 0U;

    for (uint32_t sequence = 0U;
            sequence <= CONTROL_A3_TOTAL_TICKS; sequence++)
    {
        if (controlAbortRequested)
        {
            return CONTROL_A3_OPERATOR_ABORT;
        }

        uint32_t lateness = 0U;
        uint32_t scheduledTick = deadline;
        if (sequence > 0U)
        {
            deadline += CONTROL_A3_PERIOD_MS;
            scheduledTick = deadline;
            uint32_t now = osKernelGetTickCount();
            if ((int32_t)(deadline - now) > 0)
            {
                (void)osDelayUntil(deadline);
                consecutiveMisses = 0U;
            }
            else if ((int32_t)(now - deadline) > 0)
            {
                lateness = now - deadline;
                report->deadlineMisses++;
                consecutiveMisses++;
                if (lateness > report->maxLatenessTicks)
                {
                    report->maxLatenessTicks = lateness;
                }
                if (consecutiveMisses >= CONTROL_A3_MAX_CONSECUTIVE_MISSES)
                {
                    return CONTROL_A3_DEADLINE_FAULT;
                }
                /* Never issue catch-up commands back-to-back after a miss. */
                deadline = now;
            }
            else
            {
                consecutiveMisses = 0U;
            }
        }

        ControlA3Phase_t phase = ControlA3PhaseForSequence(sequence);
        uint32_t phaseProgress = 0U;
        if (phase != CONTROL_A3_PHASE_POWER_RAMP)
        {
            phaseProgress = ControlA3PhaseProgressRaw(
                sequence - CONTROL_A3_POWER_RAMP_TICKS);
        }
        uint16_t commandElectrical = (uint16_t)(
            (CONTROL_A3_PHASE_START_RAW + phaseProgress)
                % MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
        uint32_t commandPowerPpm = ControlA3PowerPpm(sequence);
        float commandPower = (float)commandPowerPpm / 1000000.0f;

        uint32_t loopStartCycle = DWT->CYCCNT;
        Motor_SetElectricalPos(commandElectrical, commandPower);
        MA600_Sample_t sample;
        MA600_Result_t result = MA600_AcquireSample(&report->acquisition,
            CONTROL_A3_MAX_JUMP_RAW, CONTROL_A3_READ_ATTEMPTS, &sample);
        uint32_t loopCycles = DWT->CYCCNT - loopStartCycle;
        uint32_t sampleTick = osKernelGetTickCount();
        if (loopCycles > report->maxLoopCycles)
        {
            report->maxLoopCycles = loopCycles;
        }
        if (result != MA600_RESULT_OK)
        {
            return CONTROL_A3_ACQUISITION_FAULT;
        }

        int64_t travel64 = sample.unwrappedRaw - baseline->unwrappedRaw;
        int32_t travelRaw = (int32_t)travel64;
        int32_t deltaRaw = travelRaw - previousTravelRaw;
        int32_t velocityRawPerSecond = deltaRaw * 1000;
        previousTravelRaw = travelRaw;

        /* The rotor position where the sweep begins anchors the drag lag:
         * whatever crept during POWER_RAMP is history, not lag. */
        if (sequence == CONTROL_A3_POWER_RAMP_TICKS)
        {
            report->rampCreepRaw = travelRaw;
        }
        int32_t dragLagRaw = 0;
        if (phase != CONTROL_A3_PHASE_POWER_RAMP)
        {
            dragLagRaw = (int32_t)phaseProgress
                - (travelRaw - report->rampCreepRaw);
        }

        if (phase == CONTROL_A3_PHASE_SWEEP)
        {
            uint32_t sweepTick = sequence - CONTROL_A3_POWER_RAMP_TICKS;
            uint32_t ringIndex = sweepTick % CONTROL_A3_CAPTURE_WINDOW_TICKS;
            if (!captured && sweepTick >= CONTROL_A3_CAPTURE_WINDOW_TICKS)
            {
                int64_t fieldDisp = (int64_t)phaseProgress
                    - (int64_t)controlCaptureFieldRing[ringIndex];
                int64_t rotorDisp = (int64_t)travelRaw
                    - (int64_t)controlCaptureTravelRing[ringIndex];
                if (fieldDisp >= CONTROL_A3_CAPTURE_MIN_FIELD_RAW
                        && rotorDisp * CONTROL_A3_CAPTURE_VELOCITY_DEN
                            >= fieldDisp * CONTROL_A3_CAPTURE_VELOCITY_NUM)
                {
                    captured = true;
                    report->captureDetected = true;
                    report->captureSeq = sequence;
                    report->capturePhaseProgressRaw = phaseProgress;
                }
            }
            controlCaptureFieldRing[ringIndex] = phaseProgress;
            controlCaptureTravelRing[ringIndex] = travelRaw;

            if (captured)
            {
                dragLagSum += dragLagRaw;
                dragLagCount++;
                if (dragLagRaw > report->dragLagMaxRaw)
                {
                    report->dragLagMaxRaw = dragLagRaw;
                }
            }
        }

        /* Pull-out check armed only once the rotor was provably following;
         * before capture the field legitimately runs ahead (geometry). */
        if (captured && dragLagRaw > CONTROL_A3_DRAG_LOSS_LAG_RAW)
        {
            return CONTROL_A3_DRAG_SLIP;
        }

        report->finalRaw = sample.raw;
        uint32_t absTravel = AbsI32ToU32(travelRaw);
        uint32_t absStep = AbsI32ToU32(deltaRaw);
        uint32_t absVelocity = AbsI32ToU32(velocityRawPerSecond);
        if (absTravel > report->maxAbsTravelRaw)
        {
            report->maxAbsTravelRaw = absTravel;
        }
        if (absStep > report->maxSampleStepRaw)
        {
            report->maxSampleStepRaw = absStep;
        }
        if (absVelocity > report->maxAbsVelocityRawPerSecond)
        {
            report->maxAbsVelocityRawPerSecond = absVelocity;
        }

        if ((sequence % CONTROL_A3_EVIDENCE_DECIMATION) == 0U
                || sequence == CONTROL_A3_TOTAL_TICKS)
        {
            if (report->evidenceCount >= CONTROL_A3_MAX_EVIDENCE)
            {
                return CONTROL_A3_EVIDENCE_OVERFLOW;
            }
            ControlA3Evidence_t *evidence =
                &controlEvidence[report->evidenceCount];
            evidence->sequence = sequence;
            evidence->scheduledTick = scheduledTick;
            evidence->sampleTick = sampleTick;
            evidence->loopCycles = loopCycles;
            evidence->latenessTicks = lateness;
            evidence->commandPowerPpm = commandPowerPpm;
            evidence->commandPhaseProgressRaw = phaseProgress;
            evidence->travelRaw = travelRaw;
            evidence->deltaRaw = deltaRaw;
            evidence->velocityRawPerSecond = velocityRawPerSecond;
            evidence->dragLagRaw = dragLagRaw;
            evidence->encoderRaw = sample.raw;
            evidence->commandElectricalRaw = commandElectrical;
            evidence->phase = (uint8_t)phase;
            evidence->captureLatched = captured ? 1U : 0U;
            evidence->spiLatencyCycles = 0U;
            evidence->pwmCounterAtCs = 0U;
            if (sample.meta.metaValid)
            {
                evidence->spiLatencyCycles = sample.meta.transferCompleteCycle
                    - sample.meta.csAssertCycle;
                evidence->pwmCounterAtCs = sample.meta.pwmCounterAtCs;
            }
            report->evidenceCount++;
        }

        if (absStep > CONTROL_A3_MAX_SAMPLE_STEP_RAW)
        {
            return CONTROL_A3_SAMPLE_STEP_LIMIT;
        }
        if (absTravel > CONTROL_A3_MAX_TRAVEL_RAW)
        {
            return CONTROL_A3_TRAVEL_LIMIT;
        }
        if (HAL_GetTick() - activeStartTick >= CONTROL_A3_MAX_ACTIVE_MS)
        {
            return CONTROL_A3_DURATION_LIMIT;
        }
    }

    if (dragLagCount > 0U)
    {
        report->dragLagMeanRaw = (int32_t)(dragLagSum / (int64_t)dragLagCount);
    }
    if (!captured)
    {
        return CONTROL_A3_CAPTURE_FAULT;
    }
    return CONTROL_A3_OK;
}

static void ControlReport(const ControlA3Report_t *report)
{
    ControlLog(
        "CONTROL_A3_SUMMARY,Profile=%s,Result=%s,PhaseStartRaw=%u,"
        "SweepSpanRaw=%lu,TargetPowerMilli=%u,PowerRampMs=%u,SweepMs=%u,"
        "HoldMs=%u,ActiveDurationMs=%lu,EvidenceCount=%lu,"
        "CaptureDetected=%u,CaptureSeq=%lu,CapturePhaseProgressRaw=%lu,"
        "DragLagMeanRaw=%ld,DragLagMaxRaw=%ld,RampCreepRaw=%ld,"
        "BaselineRaw=%u,FinalRaw=%u,ElectricalOffsetRaw=%u,"
        "MaxTravelMilliDeg=%ld,MaxStepMilliDeg=%ld\r\n",
        CONTROL_A3_PROFILE_ID, ControlResultName(report->result),
        (unsigned int)CONTROL_A3_PHASE_START_RAW,
        (unsigned long)CONTROL_A3_PHASE_SWEEP_SPAN_RAW,
        (unsigned int)CONTROL_A3_TARGET_POWER_MILLI,
        (unsigned int)CONTROL_A3_POWER_RAMP_TICKS,
        (unsigned int)CONTROL_A3_SWEEP_TICKS,
        (unsigned int)CONTROL_A3_HOLD_TICKS,
        (unsigned long)report->activeDurationMs,
        (unsigned long)report->evidenceCount,
        report->captureDetected ? 1U : 0U,
        (unsigned long)report->captureSeq,
        (unsigned long)report->capturePhaseProgressRaw,
        (long)report->dragLagMeanRaw,
        (long)report->dragLagMaxRaw,
        (long)report->rampCreepRaw,
        (unsigned int)report->baselineRaw,
        (unsigned int)report->finalRaw,
        (unsigned int)report->electricalOffsetRaw,
        (long)RawToMilliDeg(report->maxAbsTravelRaw),
        (long)RawToMilliDeg(report->maxSampleStepRaw));
    ControlLog(
        "CONTROL_A3_SEQUENCE,PrimeStateValid=%u,EnableStateValid=%u,"
        "EnablePowerPpm=%lu\r\n",
        report->primeStateValid ? 1U : 0U,
        report->enableStateValid ? 1U : 0U,
        (unsigned long)report->enablePowerPpm);
    ControlLog(
        "CONTROL_A3_HEALTH,DeadlineMisses=%lu,MaxLatenessTicks=%lu,"
        "MaxLoopCycles=%lu,MaxAbsVelocityRawPerSecond=%lu,"
        "ReadAttempts=%lu,Accepted=%lu,Retries=%lu,TransportErrors=%lu,"
        "JumpRejects=%lu,FailedSamples=%lu\r\n",
        (unsigned long)report->deadlineMisses,
        (unsigned long)report->maxLatenessTicks,
        (unsigned long)report->maxLoopCycles,
        (unsigned long)report->maxAbsVelocityRawPerSecond,
        (unsigned long)report->acquisition.readAttempts,
        (unsigned long)report->acquisition.acceptedSamples,
        (unsigned long)report->acquisition.retryCount,
        (unsigned long)report->acquisition.transportErrorCount,
        (unsigned long)report->acquisition.jumpRejectCount,
        (unsigned long)report->acquisition.failedSampleCount);

    for (uint32_t i = 0U; i < report->evidenceCount; i++)
    {
        const ControlA3Evidence_t *e = &controlEvidence[i];
        ControlLog(
            "CONTROL_A3_DATA,Seq=%lu,Phase=%s,EncoderRaw=%u,"
            "TravelMilliDeg=%ld,DeltaRaw=%ld,VelocityRawPerSecond=%ld,"
            "DragLagRaw=%ld,CommandPhaseRaw=%u,PhaseProgressRaw=%lu,"
            "PowerPpm=%lu,CaptureLatched=%u,ScheduledTick=%lu,SampleTick=%lu,"
            "LatenessTicks=%lu,LoopCycles=%lu,SpiLatencyCycles=%lu,"
            "PwmCounterAtCs=%u,CorrectionRaw=0\r\n",
            (unsigned long)e->sequence, ControlPhaseName(e->phase),
            (unsigned int)e->encoderRaw,
            (long)RawToMilliDeg(e->travelRaw),
            (long)e->deltaRaw,
            (long)e->velocityRawPerSecond,
            (long)e->dragLagRaw,
            (unsigned int)e->commandElectricalRaw,
            (unsigned long)e->commandPhaseProgressRaw,
            (unsigned long)e->commandPowerPpm,
            (unsigned int)e->captureLatched,
            (unsigned long)e->scheduledTick,
            (unsigned long)e->sampleTick,
            (unsigned long)e->latenessTicks,
            (unsigned long)e->loopCycles,
            (unsigned long)e->spiLatencyCycles,
            (unsigned int)e->pwmCounterAtCs);
    }

    UBaseType_t stackHighWaterWords = uxTaskGetStackHighWaterMark(NULL);
    ControlLog(
        "CONTROL_A3_RUNTIME,FreeHeap=%lu,MinEverFreeHeap=%lu,"
        "ControlStackHighWaterWords=%lu\r\n",
        (unsigned long)xPortGetFreeHeapSize(),
        (unsigned long)xPortGetMinimumEverFreeHeapSize(),
        (unsigned long)stackHighWaterWords);
}

static void ControlRunA3(void)
{
    ControlA3Report_t report;
    memset(&report, 0, sizeof(report));
    memset(controlEvidence, 0, sizeof(controlEvidence));
    memset(controlCaptureTravelRing, 0, sizeof(controlCaptureTravelRing));
    memset(controlCaptureFieldRing, 0, sizeof(controlCaptureFieldRing));
    report.result = CONTROL_A3_STATUS_FAULT;
    report.captureSeq = UINT32_MAX;

    Motor_Disable();
    Motor_ResetControlSession();
    MA600_Status_t status;
    if (!MA600_PrecheckAndClearStatus(&status))
    {
        ControlReport(&report);
        return;
    }

    MA600_AcquisitionInit(&report.acquisition);
    MA600_Sample_t baseline;
    if (MA600_AcquireSample(&report.acquisition, CONTROL_A3_MAX_JUMP_RAW,
            CONTROL_A3_READ_ATTEMPTS, &baseline) != MA600_RESULT_OK)
    {
        report.result = CONTROL_A3_BASELINE_ACQUISITION_FAULT;
        ControlReport(&report);
        return;
    }
    report.baselineRaw = baseline.raw;
    report.finalRaw = baseline.raw;

    if (!Motor_PrimeControlSession(CONTROL_A3_PHASE_START_RAW, 0.0f))
    {
        report.result = CONTROL_A3_PRIME_FAULT;
        ControlReport(&report);
        return;
    }
    Motor_ControllerState_t primeState;
    Motor_GetControllerState(&primeState);
    report.primeStateValid = !primeState.outputEnabled
        && primeState.outputPower == 0.0f
        && primeState.outputElectricalPositionRaw
            == CONTROL_A3_PHASE_START_RAW
        && primeState.commandedPositionRaw
            == (float)CONTROL_A3_PHASE_START_RAW;
    if (!report.primeStateValid)
    {
        report.result = CONTROL_A3_PRIME_FAULT;
        ControlReport(&report);
        return;
    }

    ControlLog(
        "CONTROL_A3_ARMED,Profile=%s,PhaseStartRaw=%u,SweepSpanRaw=%lu,"
        "TargetPowerMilli=%u,PowerRampMs=%u,SweepMs=%u,HoldMs=%u,PeriodMs=%u,"
        "MaxTravelMilliDeg=%ld,MaxStepMilliDeg=%ld,CorrectionRaw=0\r\n",
        CONTROL_A3_PROFILE_ID,
        (unsigned int)CONTROL_A3_PHASE_START_RAW,
        (unsigned long)CONTROL_A3_PHASE_SWEEP_SPAN_RAW,
        (unsigned int)CONTROL_A3_TARGET_POWER_MILLI,
        (unsigned int)CONTROL_A3_POWER_RAMP_TICKS,
        (unsigned int)CONTROL_A3_SWEEP_TICKS,
        (unsigned int)CONTROL_A3_HOLD_TICKS,
        (unsigned int)CONTROL_A3_PERIOD_MS,
        (long)RawToMilliDeg(CONTROL_A3_MAX_TRAVEL_RAW),
        (long)RawToMilliDeg(CONTROL_A3_MAX_SAMPLE_STEP_RAW));

    uint32_t activeStartTick = HAL_GetTick();
    report.result = ControlRunAlignment(&report, &baseline, activeStartTick);

    /* The only active-run exit. Clear torque and compare registers before any
     * UART output, including faults and operator aborts. */
    Motor_Disable();
    Motor_SetElectricalPos((uint16_t)CONTROL_A3_PHASE_START_RAW, 0.0f);
    report.activeDurationMs = HAL_GetTick() - activeStartTick;
    report.electricalOffsetRaw = (uint16_t)(report.finalRaw
        % MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
    ControlReport(&report);
}

static void ControlEngineTask(void *argument)
{
    (void)argument;
    uint8_t command;
    for (;;)
    {
        if (osMessageQueueGet(controlCommandQueue, &command, NULL,
                osWaitForever) != osOK)
        {
            Motor_Disable();
            controlEngineBusy = false;
            controlAbortRequested = false;
            continue;
        }
        if (command == CONTROL_ENGINE_COMMAND_START)
        {
            ControlRunA3();
        }
        Motor_Disable();
        controlEngineBusy = false;
        controlAbortRequested = false;
    }
}

bool ControlEngine_Init(void)
{
    Motor_Disable();
    if (controlEngineInitialized || controlCommandQueue != NULL
            || controlTaskHandle != NULL)
    {
        return false;
    }
    controlCommandQueue = osMessageQueueNew(1U, sizeof(uint8_t), NULL);
    if (controlCommandQueue == NULL)
    {
        return false;
    }
    static const osThreadAttr_t attributes = {
        .name = "ControlTask",
        .stack_size = 6144U,
        .priority = (osPriority_t)osPriorityAboveNormal,
    };
    controlTaskHandle = osThreadNew(ControlEngineTask, NULL, &attributes);
    if (controlTaskHandle == NULL)
    {
        osMessageQueueDelete(controlCommandQueue);
        controlCommandQueue = NULL;
        return false;
    }
    controlEngineBusy = false;
    controlAbortRequested = false;
    controlEngineInitialized = true;
    return true;
}

bool ControlEngine_RequestStart(void)
{
    if (!controlEngineInitialized)
    {
        Motor_Disable();
        return false;
    }
    if (controlEngineBusy)
    {
        controlAbortRequested = true;
        return true;
    }

    controlEngineBusy = true;
    controlAbortRequested = false;
    uint8_t command = CONTROL_ENGINE_COMMAND_START;
    if (osMessageQueuePut(controlCommandQueue, &command, 0U, 0U) != osOK)
    {
        controlEngineBusy = false;
        Motor_Disable();
        return false;
    }
    return true;
}

bool ControlEngine_IsBusy(void)
{
    return controlEngineBusy;
}

#endif /* JIG_APP_MODE == JIG_APP_CONTROL */
