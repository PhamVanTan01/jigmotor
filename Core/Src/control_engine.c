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

/* A4 closes the one design hole A3 exposed (docs/control-a3-result.md): A3's
 * POWER_RAMP held the phase fixed at 0 while ramping to 35 percent, which
 * snapped the rotor for genuinely random starts (2/2 hand-rotated runs hit
 * SAMPLE_STEP_LIMIT at 16-18 percent power, exactly at P*sin(dist)=mu_s).
 * A4 seeds the starting phase from the encoder using the electrical offset
 * measured by A3 (6742 +/- 81 raw over 8 completed runs), so the power ramp
 * happens at ~zero torque regardless of where the rotor starts (worst-case
 * seed error ~108 raw ~ 3.6 elec deg -> ~2.2 percent residual torque, far
 * below the 9-10 percent static friction). The drag then runs only in the
 * positive direction A3 validated, over a span that ends at the phase-0
 * equivalent. Single variable vs A3: the phase start is seeded, not fixed.
 * Design record: docs/control-a3-result.md section 6. */
#define CONTROL_A4_PROFILE_ID                 "CONTROL_A4_ENCODER_SEEDED_DRAG_P35_V1"

/* Encoder<->electrical calibration constant for THIS motor+mount, measured
 * by A3 (mean of 8 completed runs). Remounting the motor invalidates it:
 * re-measure with one A3-style run from equilibrium before trusting A4. */
#define CONTROL_A4_ELECTRICAL_OFFSET_RAW      6742U

/* Power: 35 percent, unchanged from A3. */
#define CONTROL_A4_TARGET_POWER_PPM           350000U
#define CONTROL_A4_TARGET_POWER_MILLI         350U

/* Timing, 1 ms tick. FULL_SWEEP_TICKS is the full-cycle reference cadence
 * (Motion V2's proven 40 ms per mech degree); the actual sweep tick count
 * scales with the runtime span so the average drag speed stays the same. */
#define CONTROL_A4_PERIOD_MS                  1U
#define CONTROL_A4_POWER_RAMP_TICKS           300U
#define CONTROL_A4_FULL_SWEEP_TICKS           2400U
#define CONTROL_A4_HOLD_TICKS                 500U
#define CONTROL_A4_MAX_TOTAL_TICKS            \
    (CONTROL_A4_POWER_RAMP_TICKS + CONTROL_A4_FULL_SWEEP_TICKS + CONTROL_A4_HOLD_TICKS)
#define CONTROL_A4_MAX_ACTIVE_MS              4000U

/* Small spans still sweep slowly instead of stepping: floor of 2.4x the
 * capture window keeps the dynamics gentle and the detector windows
 * evaluable whenever a sweep runs at all. */
#define CONTROL_A4_MIN_SWEEP_TICKS            240U

/* Span at or below the A3-measured parking scatter (range 210 raw) means
 * the rotor already rests at the phase-0 equilibrium within measurement
 * repeatability: report AlreadyAligned=1 and do not require capture. */
#define CONTROL_A4_ALREADY_ALIGNED_SPAN_RAW   210U

/* Below this span the field never travels far enough past the static
 * friction band (~500 raw at 35 percent) for the window detector to prove
 * following; capture stays informational there instead of mandatory. */
#define CONTROL_A4_CAPTURE_REQUIRED_MIN_SPAN_RAW  1000U

/* Evidence decimation identical to A3; the worst-case run length is the
 * same 3200 ticks (span <= one cycle -> sweep ticks <= 2400). */
#define CONTROL_A4_EVIDENCE_DECIMATION        3U
#define CONTROL_A4_MAX_EVIDENCE               \
    ((CONTROL_A4_MAX_TOTAL_TICKS / CONTROL_A4_EVIDENCE_DECIMATION) + 2U)

/* Acquisition, unchanged. */
#define CONTROL_A4_MAX_JUMP_RAW               1821
#define CONTROL_A4_READ_ATTEMPTS              3U

/* Guards carried over from A3 unchanged -- that framework was validated in
 * both directions (drag peaks 92-106 raw/ms passed; ramp snaps tripped at
 * 152-154 raw/ms and stopped safely). */
#define CONTROL_A4_MAX_TRAVEL_RAW             12000
#define CONTROL_A4_MAX_SAMPLE_STEP_RAW        150
#define CONTROL_A4_MAX_CONSECUTIVE_MISSES     3U

/* Capture criterion, unchanged from A3. */
#define CONTROL_A4_CAPTURE_WINDOW_TICKS       100U
#define CONTROL_A4_CAPTURE_VELOCITY_NUM       1
#define CONTROL_A4_CAPTURE_VELOCITY_DEN       2
#define CONTROL_A4_CAPTURE_MIN_FIELD_RAW      60

/* Pull-out guard, armed only after capture latches (unchanged). */
#define CONTROL_A4_DRAG_LOSS_LAG_RAW          2731

#if CONTROL_A4_TARGET_POWER_PPM != 350000U
#error "A4 pilot must remain locked to 35 percent power"
#endif
#if CONTROL_A4_POWER_RAMP_TICKS != 300U || CONTROL_A4_FULL_SWEEP_TICKS != 2400U \
    || CONTROL_A4_HOLD_TICKS != 500U
#error "A4 pilot timing changed without a new profile identity"
#endif
#if CONTROL_A4_ELECTRICAL_OFFSET_RAW != 6742U
#error "A4 electrical offset changed: re-measure per mount and revise the profile identity"
#endif
#if CONTROL_A4_ELECTRICAL_OFFSET_RAW >= MOTOR_COUNT_PER_ELECTRICAL_CYCLE
#error "A4 electrical offset must lie inside one electrical cycle"
#endif

typedef enum
{
    CONTROL_A4_OK = 0,
    CONTROL_A4_STATUS_FAULT,
    CONTROL_A4_BASELINE_ACQUISITION_FAULT,
    CONTROL_A4_PRIME_FAULT,
    CONTROL_A4_ENABLE_STATE_FAULT,
    CONTROL_A4_ACQUISITION_FAULT,
    CONTROL_A4_TRAVEL_LIMIT,
    CONTROL_A4_SAMPLE_STEP_LIMIT,
    CONTROL_A4_DEADLINE_FAULT,
    CONTROL_A4_DURATION_LIMIT,
    CONTROL_A4_EVIDENCE_OVERFLOW,
    CONTROL_A4_OPERATOR_ABORT,
    CONTROL_A4_CAPTURE_FAULT,
    CONTROL_A4_DRAG_SLIP,
} ControlA4Result_t;

typedef enum
{
    CONTROL_A4_PHASE_POWER_RAMP = 0,  /* phase fixed at the encoder seed     */
    CONTROL_A4_PHASE_SWEEP,           /* quintic trajectory over the span    */
    CONTROL_A4_PHASE_HOLD,            /* parked at the phase-0 equivalent    */
} ControlA4Phase_t;

/* 56 bytes/record, layout unchanged from A3 (same CCM budget). */
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
    uint8_t  phase;                   /* ControlA4Phase_t                     */
    uint8_t  captureLatched;          /* 1 from the capture tick onward       */
} ControlA4Evidence_t;

typedef struct
{
    ControlA4Result_t result;
    uint32_t activeDurationMs;
    uint32_t evidenceCount;           /* decimated records actually written   */
    uint32_t deadlineMisses;
    uint32_t maxLatenessTicks;
    uint32_t maxLoopCycles;
    uint32_t maxAbsTravelRaw;
    uint32_t maxSampleStepRaw;
    uint32_t maxAbsVelocityRawPerSecond;
    uint32_t enablePowerPpm;

    /* Seeded-trajectory geometry, fixed after the baseline read. */
    uint32_t seedPhaseRaw;            /* F0 = (baseline - offset) mod cycle   */
    uint32_t sweepSpanRaw;            /* (cycle - F0) mod cycle, forward only */
    uint32_t sweepTicksUsed;
    bool     alreadyAligned;
    bool     captureRequired;

    bool     captureDetected;
    uint32_t captureSeq;              /* tick where the criterion first held;
                                       * UINT32_MAX when never                */
    uint32_t capturePhaseProgressRaw;
    int32_t  dragLagMeanRaw;          /* mean over post-capture SWEEP ticks   */
    int32_t  dragLagMaxRaw;
    int32_t  rampCreepRaw;            /* rotor travel during POWER_RAMP       */

    uint16_t baselineRaw;
    uint16_t finalRaw;
    uint16_t electricalOffsetRaw;     /* finalRaw mod cycle at end of HOLD    */

    bool     primeStateValid;
    bool     enableStateValid;
    MA600_AcquisitionContext_t acquisition;
} ControlA4Report_t;

static osMessageQueueId_t controlCommandQueue;
static osThreadId_t controlTaskHandle;
static volatile bool controlEngineInitialized;
static volatile bool controlEngineBusy;
static volatile bool controlAbortRequested;

/* CCM is CPU-only and appropriate for deferred UART evidence, not DMA
 * buffers. NOLOAD data is explicitly cleared before every run. */
static ControlA4Evidence_t controlEvidence[CONTROL_A4_MAX_EVIDENCE]
    __attribute__((section(".ccmram_bss"), aligned(8)));

_Static_assert(sizeof(ControlA4Evidence_t) == 56U,
    "A4 evidence record layout changed -- re-audit the CCM budget");
_Static_assert(sizeof(ControlA4Evidence_t) * CONTROL_A4_MAX_EVIDENCE
    <= 60U * 1024U, "A4 evidence exceeds the CCM budget");

/* Capture-criterion history rings live in regular RAM (not CCM evidence) so
 * detection runs at the full 1 ms rate regardless of evidence decimation. */
static int32_t  controlCaptureTravelRing[CONTROL_A4_CAPTURE_WINDOW_TICKS];
static uint32_t controlCaptureFieldRing[CONTROL_A4_CAPTURE_WINDOW_TICKS];

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

static uint32_t ControlA4PowerPpm(uint32_t sequence)
{
    if (sequence >= CONTROL_A4_POWER_RAMP_TICKS)
    {
        return CONTROL_A4_TARGET_POWER_PPM;
    }
    return (sequence * CONTROL_A4_TARGET_POWER_PPM)
        / CONTROL_A4_POWER_RAMP_TICKS;
}

/* Quintic smoothstep progress over the runtime span. Same float blend as
 * NlSmoothstepCommandRaw (nonlinear_test.c) with clamped endpoints, now
 * parameterized by the run's own sweepTicks/span instead of fixed values. */
static uint32_t ControlA4PhaseProgressRaw(uint32_t sweepTick,
    uint32_t sweepTicks, uint32_t spanRaw)
{
    if (sweepTicks == 0U || sweepTick >= sweepTicks)
    {
        return spanRaw;
    }
    if (sweepTick == 0U)
    {
        return 0U;
    }
    float u = (float)sweepTick / (float)sweepTicks;
    float blend = u * u * u * (10.0f + u * (-15.0f + 6.0f * u));
    long progress = lroundf((float)spanRaw * blend);
    if (progress < 0L)
    {
        progress = 0L;
    }
    if (progress > (long)spanRaw)
    {
        progress = (long)spanRaw;
    }
    return (uint32_t)progress;
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

static const char *ControlResultName(ControlA4Result_t result)
{
    switch (result)
    {
        case CONTROL_A4_OK:                         return "OK";
        case CONTROL_A4_STATUS_FAULT:               return "STATUS_FAULT";
        case CONTROL_A4_BASELINE_ACQUISITION_FAULT: return "BASELINE_ACQUISITION_FAULT";
        case CONTROL_A4_PRIME_FAULT:                return "PRIME_FAULT";
        case CONTROL_A4_ENABLE_STATE_FAULT:         return "ENABLE_STATE_FAULT";
        case CONTROL_A4_ACQUISITION_FAULT:          return "ACQUISITION_FAULT";
        case CONTROL_A4_TRAVEL_LIMIT:               return "TRAVEL_LIMIT";
        case CONTROL_A4_SAMPLE_STEP_LIMIT:          return "SAMPLE_STEP_LIMIT";
        case CONTROL_A4_DEADLINE_FAULT:             return "DEADLINE_FAULT";
        case CONTROL_A4_DURATION_LIMIT:             return "DURATION_LIMIT";
        case CONTROL_A4_EVIDENCE_OVERFLOW:          return "EVIDENCE_OVERFLOW";
        case CONTROL_A4_OPERATOR_ABORT:             return "OPERATOR_ABORT";
        case CONTROL_A4_CAPTURE_FAULT:              return "CAPTURE_FAULT";
        case CONTROL_A4_DRAG_SLIP:                  return "DRAG_SLIP";
        default:                                    return "UNKNOWN";
    }
}

static const char *ControlPhaseName(uint8_t phase)
{
    switch (phase)
    {
        case (uint8_t)CONTROL_A4_PHASE_POWER_RAMP: return "POWER_RAMP";
        case (uint8_t)CONTROL_A4_PHASE_SWEEP:      return "PHASE_SWEEP";
        default:                                   return "ALIGN_HOLD";
    }
}

static ControlA4Result_t ControlRunAlignment(ControlA4Report_t *report,
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
            == (uint16_t)report->seedPhaseRaw
        && outputState.outputPower == 0.0f;
    if (!report->enableStateValid)
    {
        return CONTROL_A4_ENABLE_STATE_FAULT;
    }

    uint32_t sweepTicks = report->sweepTicksUsed;
    uint32_t totalTicks = CONTROL_A4_POWER_RAMP_TICKS + sweepTicks
        + CONTROL_A4_HOLD_TICKS;
    uint32_t deadline = osKernelGetTickCount();
    uint32_t consecutiveMisses = 0U;
    int32_t previousTravelRaw = 0;
    bool captured = false;
    int64_t dragLagSum = 0;
    uint32_t dragLagCount = 0U;

    for (uint32_t sequence = 0U; sequence <= totalTicks; sequence++)
    {
        if (controlAbortRequested)
        {
            return CONTROL_A4_OPERATOR_ABORT;
        }

        uint32_t lateness = 0U;
        uint32_t scheduledTick = deadline;
        if (sequence > 0U)
        {
            deadline += CONTROL_A4_PERIOD_MS;
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
                if (consecutiveMisses >= CONTROL_A4_MAX_CONSECUTIVE_MISSES)
                {
                    return CONTROL_A4_DEADLINE_FAULT;
                }
                /* Never issue catch-up commands back-to-back after a miss. */
                deadline = now;
            }
            else
            {
                consecutiveMisses = 0U;
            }
        }

        ControlA4Phase_t phase;
        if (sequence < CONTROL_A4_POWER_RAMP_TICKS)
        {
            phase = CONTROL_A4_PHASE_POWER_RAMP;
        }
        else if (sequence <= CONTROL_A4_POWER_RAMP_TICKS + sweepTicks)
        {
            phase = CONTROL_A4_PHASE_SWEEP;
        }
        else
        {
            phase = CONTROL_A4_PHASE_HOLD;
        }
        uint32_t phaseProgress = 0U;
        if (phase != CONTROL_A4_PHASE_POWER_RAMP)
        {
            phaseProgress = ControlA4PhaseProgressRaw(
                sequence - CONTROL_A4_POWER_RAMP_TICKS, sweepTicks,
                report->sweepSpanRaw);
        }
        uint16_t commandElectrical = (uint16_t)(
            (report->seedPhaseRaw + phaseProgress)
                % MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
        uint32_t commandPowerPpm = ControlA4PowerPpm(sequence);
        float commandPower = (float)commandPowerPpm / 1000000.0f;

        uint32_t loopStartCycle = DWT->CYCCNT;
        Motor_SetElectricalPos(commandElectrical, commandPower);
        MA600_Sample_t sample;
        MA600_Result_t result = MA600_AcquireSample(&report->acquisition,
            CONTROL_A4_MAX_JUMP_RAW, CONTROL_A4_READ_ATTEMPTS, &sample);
        uint32_t loopCycles = DWT->CYCCNT - loopStartCycle;
        uint32_t sampleTick = osKernelGetTickCount();
        if (loopCycles > report->maxLoopCycles)
        {
            report->maxLoopCycles = loopCycles;
        }
        if (result != MA600_RESULT_OK)
        {
            return CONTROL_A4_ACQUISITION_FAULT;
        }

        int64_t travel64 = sample.unwrappedRaw - baseline->unwrappedRaw;
        int32_t travelRaw = (int32_t)travel64;
        int32_t deltaRaw = travelRaw - previousTravelRaw;
        int32_t velocityRawPerSecond = deltaRaw * 1000;
        previousTravelRaw = travelRaw;

        /* The rotor position where the sweep begins anchors the drag lag:
         * whatever crept during POWER_RAMP is history, not lag. */
        if (sequence == CONTROL_A4_POWER_RAMP_TICKS)
        {
            report->rampCreepRaw = travelRaw;
        }
        int32_t dragLagRaw = 0;
        if (phase != CONTROL_A4_PHASE_POWER_RAMP)
        {
            dragLagRaw = (int32_t)phaseProgress
                - (travelRaw - report->rampCreepRaw);
        }

        if (phase == CONTROL_A4_PHASE_SWEEP && sweepTicks > 0U)
        {
            uint32_t sweepTick = sequence - CONTROL_A4_POWER_RAMP_TICKS;
            uint32_t ringIndex = sweepTick % CONTROL_A4_CAPTURE_WINDOW_TICKS;
            if (!captured && sweepTick >= CONTROL_A4_CAPTURE_WINDOW_TICKS)
            {
                int64_t fieldDisp = (int64_t)phaseProgress
                    - (int64_t)controlCaptureFieldRing[ringIndex];
                int64_t rotorDisp = (int64_t)travelRaw
                    - (int64_t)controlCaptureTravelRing[ringIndex];
                if (fieldDisp >= CONTROL_A4_CAPTURE_MIN_FIELD_RAW
                        && rotorDisp * CONTROL_A4_CAPTURE_VELOCITY_DEN
                            >= fieldDisp * CONTROL_A4_CAPTURE_VELOCITY_NUM)
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
        if (captured && dragLagRaw > CONTROL_A4_DRAG_LOSS_LAG_RAW)
        {
            return CONTROL_A4_DRAG_SLIP;
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

        if ((sequence % CONTROL_A4_EVIDENCE_DECIMATION) == 0U
                || sequence == totalTicks)
        {
            if (report->evidenceCount >= CONTROL_A4_MAX_EVIDENCE)
            {
                return CONTROL_A4_EVIDENCE_OVERFLOW;
            }
            ControlA4Evidence_t *evidence =
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

        if (absStep > CONTROL_A4_MAX_SAMPLE_STEP_RAW)
        {
            return CONTROL_A4_SAMPLE_STEP_LIMIT;
        }
        if (absTravel > CONTROL_A4_MAX_TRAVEL_RAW)
        {
            return CONTROL_A4_TRAVEL_LIMIT;
        }
        if (HAL_GetTick() - activeStartTick >= CONTROL_A4_MAX_ACTIVE_MS)
        {
            return CONTROL_A4_DURATION_LIMIT;
        }
    }

    if (dragLagCount > 0U)
    {
        report->dragLagMeanRaw = (int32_t)(dragLagSum / (int64_t)dragLagCount);
    }
    if (report->captureRequired && !captured)
    {
        return CONTROL_A4_CAPTURE_FAULT;
    }
    return CONTROL_A4_OK;
}

static void ControlReport(const ControlA4Report_t *report)
{
    ControlLog(
        "CONTROL_A4_SUMMARY,Profile=%s,Result=%s,SeedPhaseRaw=%lu,"
        "SeedOffsetRaw=%u,SweepSpanRaw=%lu,SweepTicks=%lu,AlreadyAligned=%u,"
        "CaptureRequired=%u,TargetPowerMilli=%u,PowerRampMs=%u,HoldMs=%u,"
        "ActiveDurationMs=%lu,EvidenceCount=%lu,"
        "CaptureDetected=%u,CaptureSeq=%lu,CapturePhaseProgressRaw=%lu,"
        "DragLagMeanRaw=%ld,DragLagMaxRaw=%ld,RampCreepRaw=%ld,"
        "BaselineRaw=%u,FinalRaw=%u,ElectricalOffsetRaw=%u,"
        "MaxTravelMilliDeg=%ld,MaxStepMilliDeg=%ld\r\n",
        CONTROL_A4_PROFILE_ID, ControlResultName(report->result),
        (unsigned long)report->seedPhaseRaw,
        (unsigned int)CONTROL_A4_ELECTRICAL_OFFSET_RAW,
        (unsigned long)report->sweepSpanRaw,
        (unsigned long)report->sweepTicksUsed,
        report->alreadyAligned ? 1U : 0U,
        report->captureRequired ? 1U : 0U,
        (unsigned int)CONTROL_A4_TARGET_POWER_MILLI,
        (unsigned int)CONTROL_A4_POWER_RAMP_TICKS,
        (unsigned int)CONTROL_A4_HOLD_TICKS,
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
        "CONTROL_A4_SEQUENCE,PrimeStateValid=%u,EnableStateValid=%u,"
        "EnablePowerPpm=%lu\r\n",
        report->primeStateValid ? 1U : 0U,
        report->enableStateValid ? 1U : 0U,
        (unsigned long)report->enablePowerPpm);
    ControlLog(
        "CONTROL_A4_HEALTH,DeadlineMisses=%lu,MaxLatenessTicks=%lu,"
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
        const ControlA4Evidence_t *e = &controlEvidence[i];
        ControlLog(
            "CONTROL_A4_DATA,Seq=%lu,Phase=%s,EncoderRaw=%u,"
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
        "CONTROL_A4_RUNTIME,FreeHeap=%lu,MinEverFreeHeap=%lu,"
        "ControlStackHighWaterWords=%lu\r\n",
        (unsigned long)xPortGetFreeHeapSize(),
        (unsigned long)xPortGetMinimumEverFreeHeapSize(),
        (unsigned long)stackHighWaterWords);
}

static void ControlRunA4(void)
{
    ControlA4Report_t report;
    memset(&report, 0, sizeof(report));
    memset(controlEvidence, 0, sizeof(controlEvidence));
    memset(controlCaptureTravelRing, 0, sizeof(controlCaptureTravelRing));
    memset(controlCaptureFieldRing, 0, sizeof(controlCaptureFieldRing));
    report.result = CONTROL_A4_STATUS_FAULT;
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
    if (MA600_AcquireSample(&report.acquisition, CONTROL_A4_MAX_JUMP_RAW,
            CONTROL_A4_READ_ATTEMPTS, &baseline) != MA600_RESULT_OK)
    {
        report.result = CONTROL_A4_BASELINE_ACQUISITION_FAULT;
        ControlReport(&report);
        return;
    }
    report.baselineRaw = baseline.raw;
    report.finalRaw = baseline.raw;

    /* Seeded-trajectory geometry: the field starts at the rotor's own
     * electrical angle (zero torque), then drags forward -- the only
     * direction A3 validated -- to the phase-0 equivalent. */
    uint32_t baselineMod = (uint32_t)baseline.raw
        % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    report.seedPhaseRaw = (baselineMod + MOTOR_COUNT_PER_ELECTRICAL_CYCLE
        - CONTROL_A4_ELECTRICAL_OFFSET_RAW) % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    report.sweepSpanRaw = (MOTOR_COUNT_PER_ELECTRICAL_CYCLE
        - report.seedPhaseRaw) % MOTOR_COUNT_PER_ELECTRICAL_CYCLE;
    report.alreadyAligned =
        (report.sweepSpanRaw <= CONTROL_A4_ALREADY_ALIGNED_SPAN_RAW);
    report.captureRequired =
        (report.sweepSpanRaw >= CONTROL_A4_CAPTURE_REQUIRED_MIN_SPAN_RAW);
    if (report.sweepSpanRaw == 0U)
    {
        report.sweepTicksUsed = 0U;
    }
    else
    {
        uint32_t proportional = (uint32_t)(((uint64_t)CONTROL_A4_FULL_SWEEP_TICKS
            * report.sweepSpanRaw + (MOTOR_COUNT_PER_ELECTRICAL_CYCLE / 2U))
            / MOTOR_COUNT_PER_ELECTRICAL_CYCLE);
        report.sweepTicksUsed = (proportional < CONTROL_A4_MIN_SWEEP_TICKS)
            ? CONTROL_A4_MIN_SWEEP_TICKS : proportional;
    }

    if (!Motor_PrimeControlSession((int32_t)report.seedPhaseRaw, 0.0f))
    {
        report.result = CONTROL_A4_PRIME_FAULT;
        ControlReport(&report);
        return;
    }
    Motor_ControllerState_t primeState;
    Motor_GetControllerState(&primeState);
    report.primeStateValid = !primeState.outputEnabled
        && primeState.outputPower == 0.0f
        && primeState.outputElectricalPositionRaw
            == (uint16_t)report.seedPhaseRaw
        && primeState.commandedPositionRaw
            == (float)report.seedPhaseRaw;
    if (!report.primeStateValid)
    {
        report.result = CONTROL_A4_PRIME_FAULT;
        ControlReport(&report);
        return;
    }

    ControlLog(
        "CONTROL_A4_ARMED,Profile=%s,SeedPhaseRaw=%lu,SeedOffsetRaw=%u,"
        "SweepSpanRaw=%lu,SweepTicks=%lu,AlreadyAligned=%u,CaptureRequired=%u,"
        "TargetPowerMilli=%u,PowerRampMs=%u,HoldMs=%u,PeriodMs=%u,"
        "MaxTravelMilliDeg=%ld,MaxStepMilliDeg=%ld,CorrectionRaw=0\r\n",
        CONTROL_A4_PROFILE_ID,
        (unsigned long)report.seedPhaseRaw,
        (unsigned int)CONTROL_A4_ELECTRICAL_OFFSET_RAW,
        (unsigned long)report.sweepSpanRaw,
        (unsigned long)report.sweepTicksUsed,
        report.alreadyAligned ? 1U : 0U,
        report.captureRequired ? 1U : 0U,
        (unsigned int)CONTROL_A4_TARGET_POWER_MILLI,
        (unsigned int)CONTROL_A4_POWER_RAMP_TICKS,
        (unsigned int)CONTROL_A4_HOLD_TICKS,
        (unsigned int)CONTROL_A4_PERIOD_MS,
        (long)RawToMilliDeg(CONTROL_A4_MAX_TRAVEL_RAW),
        (long)RawToMilliDeg(CONTROL_A4_MAX_SAMPLE_STEP_RAW));

    uint32_t activeStartTick = HAL_GetTick();
    report.result = ControlRunAlignment(&report, &baseline, activeStartTick);

    /* The only active-run exit. Clear torque and compare registers before any
     * UART output, including faults and operator aborts. */
    Motor_Disable();
    Motor_SetElectricalPos((uint16_t)report.seedPhaseRaw, 0.0f);
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
            ControlRunA4();
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
