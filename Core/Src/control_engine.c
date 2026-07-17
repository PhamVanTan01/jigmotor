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
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern UART_HandleTypeDef huart3;

#define CONTROL_ENGINE_COMMAND_START          1U

/* A2 isolates driver enable and fixed-phase alignment. There is deliberately
 * no HOME/PID update and no position trajectory in this image. */
#define CONTROL_A2_PROFILE_ID                 "CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1"
#define CONTROL_A2_COMMAND_PHASE_RAW          0U
#define CONTROL_A2_TARGET_POWER_PPM           100000U
#define CONTROL_A2_TARGET_POWER_MILLI         100U
#define CONTROL_A2_PERIOD_MS                  1U
#define CONTROL_A2_RAMP_TICKS                 500U
#define CONTROL_A2_HOLD_TICKS                 100U
#define CONTROL_A2_MAX_EVIDENCE               \
    (CONTROL_A2_RAMP_TICKS + CONTROL_A2_HOLD_TICKS + 1U)
#define CONTROL_A2_MAX_JUMP_RAW               1821
#define CONTROL_A2_READ_ATTEMPTS              3U
#define CONTROL_A2_MAX_TRAVEL_RAW             910
#define CONTROL_A2_MAX_SAMPLE_STEP_RAW        45
#define CONTROL_A2_MAX_ACTIVE_MS              750U
#define CONTROL_A2_MAX_CONSECUTIVE_MISSES     3U

#if CONTROL_A2_TARGET_POWER_PPM != 100000U
#error "A2 pilot must remain locked to 10 percent power"
#endif
#if CONTROL_A2_RAMP_TICKS != 500U || CONTROL_A2_HOLD_TICKS != 100U
#error "A2 pilot timing changed without a new profile identity"
#endif

typedef enum
{
    CONTROL_A2_OK = 0,
    CONTROL_A2_STATUS_FAULT,
    CONTROL_A2_BASELINE_ACQUISITION_FAULT,
    CONTROL_A2_PRIME_FAULT,
    CONTROL_A2_ENABLE_STATE_FAULT,
    CONTROL_A2_ACQUISITION_FAULT,
    CONTROL_A2_TRAVEL_LIMIT,
    CONTROL_A2_SAMPLE_STEP_LIMIT,
    CONTROL_A2_DEADLINE_FAULT,
    CONTROL_A2_DURATION_LIMIT,
    CONTROL_A2_EVIDENCE_OVERFLOW,
    CONTROL_A2_OPERATOR_ABORT,
} ControlA2Result_t;

typedef enum
{
    CONTROL_A2_PHASE_RAMP = 0,
    CONTROL_A2_PHASE_HOLD,
} ControlA2Phase_t;

typedef struct
{
    uint32_t sequence;
    uint32_t scheduledTick;
    uint32_t sampleTick;
    uint32_t loopCycles;
    uint32_t spiLatencyCycles;
    uint32_t latenessTicks;
    uint32_t commandPowerPpm;
    int32_t travelRaw;
    int32_t deltaRaw;
    int32_t velocityRawPerSecond;
    int64_t accelerationRawPerSecond2;
    uint16_t encoderRaw;
    uint16_t commandElectricalRaw;
    uint16_t pwmCounterAtCs;
    uint8_t phase;
} ControlA2Evidence_t;

typedef struct
{
    ControlA2Result_t result;
    uint32_t activeDurationMs;
    uint32_t evidenceCount;
    uint32_t deadlineMisses;
    uint32_t maxLatenessTicks;
    uint32_t maxLoopCycles;
    uint32_t maxAbsTravelRaw;
    uint32_t maxSampleStepRaw;
    uint32_t maxAbsVelocityRawPerSecond;
    uint32_t enablePowerPpm;
    uint16_t baselineRaw;
    uint16_t finalRaw;
    bool primeStateValid;
    bool enableStateValid;
    MA600_AcquisitionContext_t acquisition;
} ControlA2Report_t;

static osMessageQueueId_t controlCommandQueue;
static osThreadId_t controlTaskHandle;
static volatile bool controlEngineInitialized;
static volatile bool controlEngineBusy;
static volatile bool controlAbortRequested;

/* CCM is CPU-only and appropriate for deferred UART evidence, not DMA
 * buffers. NOLOAD data is explicitly cleared before every run. */
static ControlA2Evidence_t controlEvidence[CONTROL_A2_MAX_EVIDENCE]
    __attribute__((section(".ccmram_bss"), aligned(8)));

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

static uint32_t ControlA2PowerPpm(uint32_t sequence)
{
    if (sequence >= CONTROL_A2_RAMP_TICKS)
    {
        return CONTROL_A2_TARGET_POWER_PPM;
    }
    return (sequence * CONTROL_A2_TARGET_POWER_PPM)
        / CONTROL_A2_RAMP_TICKS;
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

static const char *ControlResultName(ControlA2Result_t result)
{
    switch (result)
    {
        case CONTROL_A2_OK:                         return "OK";
        case CONTROL_A2_STATUS_FAULT:               return "STATUS_FAULT";
        case CONTROL_A2_BASELINE_ACQUISITION_FAULT: return "BASELINE_ACQUISITION_FAULT";
        case CONTROL_A2_PRIME_FAULT:                return "PRIME_FAULT";
        case CONTROL_A2_ENABLE_STATE_FAULT:         return "ENABLE_STATE_FAULT";
        case CONTROL_A2_ACQUISITION_FAULT:          return "ACQUISITION_FAULT";
        case CONTROL_A2_TRAVEL_LIMIT:               return "TRAVEL_LIMIT";
        case CONTROL_A2_SAMPLE_STEP_LIMIT:          return "SAMPLE_STEP_LIMIT";
        case CONTROL_A2_DEADLINE_FAULT:             return "DEADLINE_FAULT";
        case CONTROL_A2_DURATION_LIMIT:             return "DURATION_LIMIT";
        case CONTROL_A2_EVIDENCE_OVERFLOW:          return "EVIDENCE_OVERFLOW";
        case CONTROL_A2_OPERATOR_ABORT:             return "OPERATOR_ABORT";
        default:                                    return "UNKNOWN";
    }
}

static const char *ControlPhaseName(uint8_t phase)
{
    return (phase == (uint8_t)CONTROL_A2_PHASE_RAMP) ? "ALIGN_RAMP"
                                                      : "ALIGN_HOLD";
}

static ControlA2Result_t ControlRunAlignment(ControlA2Report_t *report,
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
            == CONTROL_A2_COMMAND_PHASE_RAW
        && outputState.outputPower == 0.0f;
    if (!report->enableStateValid)
    {
        return CONTROL_A2_ENABLE_STATE_FAULT;
    }

    uint32_t deadline = osKernelGetTickCount();
    uint32_t consecutiveMisses = 0U;
    int32_t previousTravelRaw = 0;
    int32_t previousVelocity = 0;

    for (uint32_t sequence = 0U;
            sequence < CONTROL_A2_MAX_EVIDENCE; sequence++)
    {
        if (controlAbortRequested)
        {
            return CONTROL_A2_OPERATOR_ABORT;
        }

        uint32_t lateness = 0U;
        uint32_t scheduledTick = deadline;
        if (sequence > 0U)
        {
            deadline += CONTROL_A2_PERIOD_MS;
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
                if (consecutiveMisses >= CONTROL_A2_MAX_CONSECUTIVE_MISSES)
                {
                    return CONTROL_A2_DEADLINE_FAULT;
                }
                /* Never issue catch-up commands back-to-back after a miss. */
                deadline = now;
            }
            else
            {
                consecutiveMisses = 0U;
            }
        }

        ControlA2Evidence_t *evidence = &controlEvidence[sequence];
        evidence->sequence = sequence;
        evidence->scheduledTick = scheduledTick;
        evidence->latenessTicks = lateness;
        evidence->phase = (sequence <= CONTROL_A2_RAMP_TICKS)
            ? (uint8_t)CONTROL_A2_PHASE_RAMP
            : (uint8_t)CONTROL_A2_PHASE_HOLD;
        evidence->commandElectricalRaw = CONTROL_A2_COMMAND_PHASE_RAW;
        evidence->commandPowerPpm = ControlA2PowerPpm(sequence);
        float commandPower = (float)evidence->commandPowerPpm / 1000000.0f;

        uint32_t loopStartCycle = DWT->CYCCNT;
        Motor_SetElectricalPos(evidence->commandElectricalRaw, commandPower);
        MA600_Sample_t sample;
        MA600_Result_t result = MA600_AcquireSample(&report->acquisition,
            CONTROL_A2_MAX_JUMP_RAW, CONTROL_A2_READ_ATTEMPTS, &sample);
        evidence->loopCycles = DWT->CYCCNT - loopStartCycle;
        evidence->sampleTick = osKernelGetTickCount();
        if (evidence->loopCycles > report->maxLoopCycles)
        {
            report->maxLoopCycles = evidence->loopCycles;
        }
        if (result != MA600_RESULT_OK)
        {
            return CONTROL_A2_ACQUISITION_FAULT;
        }

        evidence->encoderRaw = sample.raw;
        if (sample.meta.metaValid)
        {
            evidence->spiLatencyCycles = sample.meta.transferCompleteCycle
                - sample.meta.csAssertCycle;
            evidence->pwmCounterAtCs = sample.meta.pwmCounterAtCs;
        }
        int64_t travel64 = sample.unwrappedRaw - baseline->unwrappedRaw;
        evidence->travelRaw = (int32_t)travel64;
        evidence->deltaRaw = evidence->travelRaw - previousTravelRaw;
        evidence->velocityRawPerSecond = evidence->deltaRaw * 1000;
        evidence->accelerationRawPerSecond2 =
            ((int64_t)evidence->velocityRawPerSecond
                - (int64_t)previousVelocity) * 1000LL;
        previousTravelRaw = evidence->travelRaw;
        previousVelocity = evidence->velocityRawPerSecond;

        report->evidenceCount = sequence + 1U;
        report->finalRaw = sample.raw;
        uint32_t absTravel = AbsI32ToU32(evidence->travelRaw);
        uint32_t absStep = AbsI32ToU32(evidence->deltaRaw);
        uint32_t absVelocity = AbsI32ToU32(evidence->velocityRawPerSecond);
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

        if (absStep > CONTROL_A2_MAX_SAMPLE_STEP_RAW)
        {
            return CONTROL_A2_SAMPLE_STEP_LIMIT;
        }
        if (absTravel > CONTROL_A2_MAX_TRAVEL_RAW)
        {
            return CONTROL_A2_TRAVEL_LIMIT;
        }
        if (HAL_GetTick() - activeStartTick >= CONTROL_A2_MAX_ACTIVE_MS)
        {
            return CONTROL_A2_DURATION_LIMIT;
        }
    }

    return (report->evidenceCount == CONTROL_A2_MAX_EVIDENCE)
        ? CONTROL_A2_OK : CONTROL_A2_EVIDENCE_OVERFLOW;
}

static void ControlReport(const ControlA2Report_t *report)
{
    ControlLog(
        "CONTROL_A2_SUMMARY,Profile=%s,Result=%s,CommandPhaseRaw=%u,"
        "TargetPowerMilli=%u,RampMs=%u,HoldMs=%u,ActiveDurationMs=%lu,"
        "EvidenceCount=%lu,BaselineRaw=%u,FinalRaw=%u,MaxTravelMilliDeg=%ld,"
        "MaxStepMilliDeg=%ld\r\n",
        CONTROL_A2_PROFILE_ID, ControlResultName(report->result),
        CONTROL_A2_COMMAND_PHASE_RAW, CONTROL_A2_TARGET_POWER_MILLI,
        CONTROL_A2_RAMP_TICKS, CONTROL_A2_HOLD_TICKS,
        (unsigned long)report->activeDurationMs,
        (unsigned long)report->evidenceCount,
        (unsigned int)report->baselineRaw,
        (unsigned int)report->finalRaw,
        (long)RawToMilliDeg(report->maxAbsTravelRaw),
        (long)RawToMilliDeg(report->maxSampleStepRaw));
    ControlLog(
        "CONTROL_A2_SEQUENCE,PrimeStateValid=%u,EnableStateValid=%u,"
        "EnablePowerPpm=%lu\r\n",
        report->primeStateValid ? 1U : 0U,
        report->enableStateValid ? 1U : 0U,
        (unsigned long)report->enablePowerPpm);
    ControlLog(
        "CONTROL_A2_HEALTH,DeadlineMisses=%lu,MaxLatenessTicks=%lu,"
        "MaxLoopCycles=%lu,MaxAbsVelocityRawPerSecond=%lu,ReadAttempts=%lu,"
        "Accepted=%lu,Retries=%lu,TransportErrors=%lu,JumpRejects=%lu,"
        "FailedSamples=%lu\r\n",
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
        const ControlA2Evidence_t *e = &controlEvidence[i];
        ControlLog(
            "CONTROL_A2_DATA,Seq=%lu,Phase=%s,EncoderRaw=%u,TravelMilliDeg=%ld,"
            "DeltaRaw=%ld,VelocityRawPerSecond=%ld,"
            "AccelerationRawPerSecond2=%lld,CommandPhaseRaw=%u,PowerPpm=%lu,"
            "ScheduledTick=%lu,SampleTick=%lu,LatenessTicks=%lu,LoopCycles=%lu,"
            "SpiLatencyCycles=%lu,PwmCounterAtCs=%u,CorrectionRaw=0\r\n",
            (unsigned long)e->sequence, ControlPhaseName(e->phase),
            (unsigned int)e->encoderRaw,
            (long)RawToMilliDeg(e->travelRaw),
            (long)e->deltaRaw,
            (long)e->velocityRawPerSecond,
            (long long)e->accelerationRawPerSecond2,
            (unsigned int)e->commandElectricalRaw,
            (unsigned long)e->commandPowerPpm,
            (unsigned long)e->scheduledTick,
            (unsigned long)e->sampleTick,
            (unsigned long)e->latenessTicks,
            (unsigned long)e->loopCycles,
            (unsigned long)e->spiLatencyCycles,
            (unsigned int)e->pwmCounterAtCs);
    }

    UBaseType_t stackHighWaterWords = uxTaskGetStackHighWaterMark(NULL);
    ControlLog(
        "CONTROL_A2_RUNTIME,FreeHeap=%lu,MinEverFreeHeap=%lu,"
        "ControlStackHighWaterWords=%lu\r\n",
        (unsigned long)xPortGetFreeHeapSize(),
        (unsigned long)xPortGetMinimumEverFreeHeapSize(),
        (unsigned long)stackHighWaterWords);
}

static void ControlRunA2(void)
{
    ControlA2Report_t report;
    memset(&report, 0, sizeof(report));
    memset(controlEvidence, 0, sizeof(controlEvidence));
    report.result = CONTROL_A2_STATUS_FAULT;

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
    if (MA600_AcquireSample(&report.acquisition, CONTROL_A2_MAX_JUMP_RAW,
            CONTROL_A2_READ_ATTEMPTS, &baseline) != MA600_RESULT_OK)
    {
        report.result = CONTROL_A2_BASELINE_ACQUISITION_FAULT;
        ControlReport(&report);
        return;
    }
    report.baselineRaw = baseline.raw;
    report.finalRaw = baseline.raw;

    if (!Motor_PrimeControlSession(CONTROL_A2_COMMAND_PHASE_RAW, 0.0f))
    {
        report.result = CONTROL_A2_PRIME_FAULT;
        ControlReport(&report);
        return;
    }
    Motor_ControllerState_t primeState;
    Motor_GetControllerState(&primeState);
    report.primeStateValid = !primeState.outputEnabled
        && primeState.outputPower == 0.0f
        && primeState.outputElectricalPositionRaw
            == CONTROL_A2_COMMAND_PHASE_RAW
        && primeState.commandedPositionRaw
            == (float)CONTROL_A2_COMMAND_PHASE_RAW;
    if (!report.primeStateValid)
    {
        report.result = CONTROL_A2_PRIME_FAULT;
        ControlReport(&report);
        return;
    }

    ControlLog(
        "CONTROL_A2_ARMED,Profile=%s,CommandPhaseRaw=%u,TargetPowerMilli=%u,"
        "RampMs=%u,HoldMs=%u,PeriodMs=%u,MaxTravelMilliDeg=5000,"
        "MaxStepMilliDeg=250,CorrectionRaw=0\r\n",
        CONTROL_A2_PROFILE_ID, CONTROL_A2_COMMAND_PHASE_RAW,
        CONTROL_A2_TARGET_POWER_MILLI, CONTROL_A2_RAMP_TICKS,
        CONTROL_A2_HOLD_TICKS, CONTROL_A2_PERIOD_MS);

    uint32_t activeStartTick = HAL_GetTick();
    report.result = ControlRunAlignment(&report, &baseline, activeStartTick);

    /* The only active-run exit. Clear torque and compare registers before any
     * UART output, including faults and operator aborts. */
    Motor_Disable();
    Motor_SetElectricalPos(CONTROL_A2_COMMAND_PHASE_RAW, 0.0f);
    report.activeDurationMs = HAL_GetTick() - activeStartTick;
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
            ControlRunA2();
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
