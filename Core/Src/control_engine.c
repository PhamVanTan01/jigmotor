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

#define CONTROL_ENGINE_COMMAND_START       1U

/* C0 is deliberately locked to the smallest plant-observation move. A later
 * profile/commit may promote 5 or 10 degrees only after the 1-degree hardware
 * log passes its safety gate. */
#define CONTROL_C0_TARGET_DEG              1U
#if CONTROL_C0_TARGET_DEG != 1U
#error "C0 hardware gate requires a 1-degree target"
#endif

#define CONTROL_C0_POWER                   0.35f
#define CONTROL_C0_POWER_MILLI             350U
#define CONTROL_C0_PERIOD_MS               1U
#define CONTROL_C0_COMMANDS_PER_DEG        40U
#define CONTROL_C0_TRAJECTORY_TICKS        \
    (CONTROL_C0_TARGET_DEG * CONTROL_C0_COMMANDS_PER_DEG)
#define CONTROL_C0_HOLD_TICKS              250U
#define CONTROL_C0_MAX_EVIDENCE            \
    (CONTROL_C0_TRAJECTORY_TICKS + CONTROL_C0_HOLD_TICKS + 1U)
#define CONTROL_C0_MAX_JUMP_RAW            1821
#define CONTROL_C0_READ_ATTEMPTS           3U
#define CONTROL_C0_MAX_TRAVEL_RAW          546        /* about 3 degrees */
#define CONTROL_C0_MAX_ACTIVE_MS           6000U
#define CONTROL_C0_MAX_CONSECUTIVE_MISSES  3U

#define CONTROL_C0_HOME_TIMEOUT_MS         5000U
#define CONTROL_C0_HOME_PERIOD_MS          2U
#define CONTROL_C0_HOME_SETTLE_ERROR_MDEG  150
#define CONTROL_C0_HOME_SETTLE_COUNT       100U
#define CONTROL_C0_HOME_WRONG_WAY_MDEG     10000

typedef enum
{
    CONTROL_C0_OK = 0,
    CONTROL_C0_STATUS_FAULT,
    CONTROL_C0_HOME_ACQUISITION_FAULT,
    CONTROL_C0_HOME_TIMEOUT,
    CONTROL_C0_HOME_WRONG_WAY,
    CONTROL_C0_ACQUISITION_FAULT,
    CONTROL_C0_TRAVEL_LIMIT,
    CONTROL_C0_DEADLINE_FAULT,
    CONTROL_C0_DURATION_LIMIT,
    CONTROL_C0_EVIDENCE_OVERFLOW,
    CONTROL_C0_OPERATOR_ABORT,
} ControlC0Result_t;

typedef enum
{
    CONTROL_PHASE_RAMP = 0,
    CONTROL_PHASE_HOLD,
} ControlEvidencePhase_t;

typedef struct
{
    uint32_t sequence;
    uint32_t scheduledTick;
    uint32_t sampleTick;
    uint32_t loopCycles;
    uint32_t spiLatencyCycles;
    uint32_t latenessTicks;
    int32_t referenceRaw;
    int32_t actualRaw;
    int32_t errorRaw;
    int32_t velocityRawPerSecond;
    int64_t accelerationRawPerSecond2;
    uint16_t commandElectricalRaw;
    uint16_t pwmCounterAtCs;
    uint8_t phase;
} ControlEvidence_t;

typedef struct
{
    ControlC0Result_t result;
    uint32_t activeDurationMs;
    uint32_t homeDurationMs;
    uint32_t homeUpdates;
    int32_t homeInitialErrorMilliDeg;
    int32_t homeFinalErrorMilliDeg;
    uint32_t evidenceCount;
    uint32_t deadlineMisses;
    uint32_t maxLatenessTicks;
    uint32_t maxLoopCycles;
    uint32_t backtrackCount;
    uint32_t maxBacktrackRaw;
    int32_t maxActualRaw;
    int32_t finalActualRaw;
    int32_t finalErrorRaw;
    MA600_AcquisitionContext_t acquisition;
} ControlC0Report_t;

static osMessageQueueId_t controlCommandQueue;
static osThreadId_t controlTaskHandle;
static volatile bool controlEngineInitialized;
static volatile bool controlEngineBusy;
static volatile bool controlAbortRequested;

/* CCM is CPU-only and therefore appropriate for deferred UART evidence, not
 * DMA buffers. NOLOAD data is explicitly cleared before every run. */
static ControlEvidence_t controlEvidence[CONTROL_C0_MAX_EVIDENCE]
    __attribute__((section(".ccmram_bss"), aligned(8)));

static int32_t AbsI32(int32_t value)
{
    return (value < 0) ? -value : value;
}

static float AbsFloat(float value)
{
    return (value < 0.0f) ? -value : value;
}

static int32_t DegreesToMilli(float degrees)
{
    float scaled = degrees * 1000.0f;
    return (int32_t)(scaled + ((scaled >= 0.0f) ? 0.5f : -0.5f));
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

static int32_t SmoothstepRaw(int32_t targetRaw, uint32_t index,
                             uint32_t count)
{
    if (count == 0U || index >= count)
    {
        return targetRaw;
    }
    float u = (float)index / (float)count;
    float u2 = u * u;
    float u3 = u2 * u;
    float blend = u3 * (10.0f + u * (-15.0f + 6.0f * u));
    float command = (float)targetRaw * blend;
    return (int32_t)(command + ((command >= 0.0f) ? 0.5f : -0.5f));
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

static const char *ControlResultName(ControlC0Result_t result)
{
    switch (result)
    {
        case CONTROL_C0_OK:                     return "OK";
        case CONTROL_C0_STATUS_FAULT:           return "STATUS_FAULT";
        case CONTROL_C0_HOME_ACQUISITION_FAULT: return "HOME_ACQUISITION_FAULT";
        case CONTROL_C0_HOME_TIMEOUT:           return "HOME_TIMEOUT";
        case CONTROL_C0_HOME_WRONG_WAY:         return "HOME_WRONG_WAY";
        case CONTROL_C0_ACQUISITION_FAULT:      return "ACQUISITION_FAULT";
        case CONTROL_C0_TRAVEL_LIMIT:           return "TRAVEL_LIMIT";
        case CONTROL_C0_DEADLINE_FAULT:         return "DEADLINE_FAULT";
        case CONTROL_C0_DURATION_LIMIT:         return "DURATION_LIMIT";
        case CONTROL_C0_EVIDENCE_OVERFLOW:      return "EVIDENCE_OVERFLOW";
        case CONTROL_C0_OPERATOR_ABORT:         return "OPERATOR_ABORT";
        default:                                return "UNKNOWN";
    }
}

static const char *ControlPhaseName(uint8_t phase)
{
    return (phase == (uint8_t)CONTROL_PHASE_RAMP) ? "RAMP" : "HOLD";
}

static ControlC0Result_t ControlHome(ControlC0Report_t *report,
                                     uint32_t activeStartTick)
{
    float errorDeg = 0.0f;
    MA600_Result_t acquire = Motor_MoveToAngleWithPower(0.0f,
        CONTROL_C0_POWER, &errorDeg);
    if (acquire != MA600_RESULT_OK)
    {
        return CONTROL_C0_HOME_ACQUISITION_FAULT;
    }

    report->homeInitialErrorMilliDeg = DegreesToMilli(errorDeg);
    report->homeFinalErrorMilliDeg = report->homeInitialErrorMilliDeg;
    uint32_t homeStartTick = HAL_GetTick();
    uint32_t settled = 0U;
    Motor_Enable();
    osDelay(CONTROL_C0_HOME_PERIOD_MS);

    for (;;)
    {
        if (controlAbortRequested)
        {
            return CONTROL_C0_OPERATOR_ABORT;
        }
        acquire = Motor_MoveToAngleWithPower(0.0f, CONTROL_C0_POWER,
            &errorDeg);
        report->homeUpdates++;
        report->homeFinalErrorMilliDeg = DegreesToMilli(errorDeg);
        if (acquire != MA600_RESULT_OK)
        {
            return CONTROL_C0_HOME_ACQUISITION_FAULT;
        }

        if ((uint32_t)AbsI32(report->homeFinalErrorMilliDeg)
                <= CONTROL_C0_HOME_SETTLE_ERROR_MDEG)
        {
            settled++;
        }
        else
        {
            settled = 0U;
        }
        if (settled >= CONTROL_C0_HOME_SETTLE_COUNT)
        {
            report->homeDurationMs = HAL_GetTick() - homeStartTick;
            return CONTROL_C0_OK;
        }
        if (AbsFloat(errorDeg) * 1000.0f
                > (float)(AbsI32(report->homeInitialErrorMilliDeg)
                    + CONTROL_C0_HOME_WRONG_WAY_MDEG))
        {
            report->homeDurationMs = HAL_GetTick() - homeStartTick;
            return CONTROL_C0_HOME_WRONG_WAY;
        }

        uint32_t now = HAL_GetTick();
        report->homeDurationMs = now - homeStartTick;
        if (report->homeDurationMs >= CONTROL_C0_HOME_TIMEOUT_MS)
        {
            return CONTROL_C0_HOME_TIMEOUT;
        }
        if (now - activeStartTick >= CONTROL_C0_MAX_ACTIVE_MS)
        {
            return CONTROL_C0_DURATION_LIMIT;
        }
        osDelay(CONTROL_C0_HOME_PERIOD_MS);
    }
}

static ControlC0Result_t ControlObserveOneDegree(ControlC0Report_t *report,
                                                  uint32_t activeStartTick)
{
    MA600_AcquisitionInit(&report->acquisition);
    MA600_Sample_t baseline;
    MA600_Result_t result = MA600_AcquireSample(&report->acquisition,
        CONTROL_C0_MAX_JUMP_RAW, CONTROL_C0_READ_ATTEMPTS, &baseline);
    if (result != MA600_RESULT_OK)
    {
        return CONTROL_C0_ACQUISITION_FAULT;
    }

    Motor_ControllerState_t motorState;
    Motor_GetControllerState(&motorState);
    int32_t startCommandRaw = (int32_t)motorState.outputElectricalPositionRaw;
    const int32_t targetRaw = (int32_t)(((uint32_t)CONTROL_C0_TARGET_DEG
        * MOTOR_MECHANICAL_COUNTS_PER_REV + 180U) / 360U);
    uint32_t deadline = osKernelGetTickCount();
    uint32_t consecutiveMisses = 0U;
    int32_t previousActualRaw = 0;
    int32_t previousVelocity = 0;

    for (uint32_t sequence = 0U;
            sequence < CONTROL_C0_MAX_EVIDENCE; sequence++)
    {
        if (controlAbortRequested)
        {
            return CONTROL_C0_OPERATOR_ABORT;
        }
        uint32_t lateness = 0U;
        uint32_t scheduledTick = deadline;
        if (sequence > 0U)
        {
            deadline += CONTROL_C0_PERIOD_MS;
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
                if (consecutiveMisses >= CONTROL_C0_MAX_CONSECUTIVE_MISSES)
                {
                    return CONTROL_C0_DEADLINE_FAULT;
                }
                /* Do not catch up with back-to-back motor commands after a
                 * late cycle. Preserve the missed target in evidence, then
                 * schedule the following cycle from the current time. */
                deadline = now;
            }
            else
            {
                consecutiveMisses = 0U;
            }
        }

        ControlEvidence_t *evidence = &controlEvidence[sequence];
        evidence->sequence = sequence;
        evidence->scheduledTick = scheduledTick;
        evidence->latenessTicks = lateness;
        if (sequence <= CONTROL_C0_TRAJECTORY_TICKS)
        {
            evidence->phase = (uint8_t)CONTROL_PHASE_RAMP;
            evidence->referenceRaw = SmoothstepRaw(targetRaw, sequence,
                CONTROL_C0_TRAJECTORY_TICKS);
        }
        else
        {
            evidence->phase = (uint8_t)CONTROL_PHASE_HOLD;
            evidence->referenceRaw = targetRaw;
        }
        evidence->commandElectricalRaw = (uint16_t)(startCommandRaw
            + evidence->referenceRaw);

        uint32_t loopStartCycle = DWT->CYCCNT;
        Motor_SetElectricalPos(evidence->commandElectricalRaw,
            CONTROL_C0_POWER);
        MA600_Sample_t sample;
        result = MA600_AcquireSample(&report->acquisition,
            CONTROL_C0_MAX_JUMP_RAW, CONTROL_C0_READ_ATTEMPTS, &sample);
        evidence->loopCycles = DWT->CYCCNT - loopStartCycle;
        evidence->sampleTick = osKernelGetTickCount();
        if (evidence->loopCycles > report->maxLoopCycles)
        {
            report->maxLoopCycles = evidence->loopCycles;
        }
        if (result != MA600_RESULT_OK)
        {
            return CONTROL_C0_ACQUISITION_FAULT;
        }
        if (sample.meta.metaValid)
        {
            evidence->spiLatencyCycles = sample.meta.transferCompleteCycle
                - sample.meta.csAssertCycle;
            evidence->pwmCounterAtCs = sample.meta.pwmCounterAtCs;
        }

        int64_t actual64 = sample.unwrappedRaw - baseline.unwrappedRaw;
        evidence->actualRaw = (int32_t)actual64;
        evidence->errorRaw = evidence->referenceRaw - evidence->actualRaw;
        int32_t deltaRaw = evidence->actualRaw - previousActualRaw;
        evidence->velocityRawPerSecond = deltaRaw * 1000;
        evidence->accelerationRawPerSecond2 =
            ((int64_t)evidence->velocityRawPerSecond
                - (int64_t)previousVelocity) * 1000LL;
        previousActualRaw = evidence->actualRaw;
        previousVelocity = evidence->velocityRawPerSecond;
        report->evidenceCount = sequence + 1U;
        report->finalActualRaw = evidence->actualRaw;
        report->finalErrorRaw = evidence->errorRaw;
        if (evidence->actualRaw > report->maxActualRaw)
        {
            report->maxActualRaw = evidence->actualRaw;
        }
        if (deltaRaw < -9)
        {
            uint32_t magnitude = (uint32_t)(-deltaRaw);
            report->backtrackCount++;
            if (magnitude > report->maxBacktrackRaw)
            {
                report->maxBacktrackRaw = magnitude;
            }
        }
        if (AbsI32(evidence->actualRaw) > CONTROL_C0_MAX_TRAVEL_RAW)
        {
            return CONTROL_C0_TRAVEL_LIMIT;
        }
        if (HAL_GetTick() - activeStartTick >= CONTROL_C0_MAX_ACTIVE_MS)
        {
            return CONTROL_C0_DURATION_LIMIT;
        }
    }

    if (report->evidenceCount != CONTROL_C0_MAX_EVIDENCE)
    {
        return CONTROL_C0_EVIDENCE_OVERFLOW;
    }
    return CONTROL_C0_OK;
}

static void ControlReport(const ControlC0Report_t *report)
{
    ControlLog(
        "CONTROL_C0_SUMMARY,Profile=CONTROL_C0_OPEN_LOOP_1DEG_V1,"
        "Result=%s,TargetMilliDeg=1000,PowerMilli=%u,CorrectionRaw=0,"
        "ActiveDurationMs=%lu,EvidenceCount=%lu,FinalActualMilliDeg=%ld,"
        "FinalErrorMilliDeg=%ld,MaxActualMilliDeg=%ld\r\n",
        ControlResultName(report->result), CONTROL_C0_POWER_MILLI,
        (unsigned long)report->activeDurationMs,
        (unsigned long)report->evidenceCount,
        (long)RawToMilliDeg(report->finalActualRaw),
        (long)RawToMilliDeg(report->finalErrorRaw),
        (long)RawToMilliDeg(report->maxActualRaw));
    ControlLog(
        "CONTROL_C0_HOME,InitialErrorMilliDeg=%ld,FinalErrorMilliDeg=%ld,"
        "DurationMs=%lu,Updates=%lu\r\n",
        (long)report->homeInitialErrorMilliDeg,
        (long)report->homeFinalErrorMilliDeg,
        (unsigned long)report->homeDurationMs,
        (unsigned long)report->homeUpdates);
    ControlLog(
        "CONTROL_C0_HEALTH,DeadlineMisses=%lu,MaxLatenessTicks=%lu,"
        "MaxLoopCycles=%lu,Backtracks=%lu,MaxBacktrackRaw=%lu,"
        "ReadAttempts=%lu,Accepted=%lu,Retries=%lu,TransportErrors=%lu,"
        "JumpRejects=%lu,FailedSamples=%lu\r\n",
        (unsigned long)report->deadlineMisses,
        (unsigned long)report->maxLatenessTicks,
        (unsigned long)report->maxLoopCycles,
        (unsigned long)report->backtrackCount,
        (unsigned long)report->maxBacktrackRaw,
        (unsigned long)report->acquisition.readAttempts,
        (unsigned long)report->acquisition.acceptedSamples,
        (unsigned long)report->acquisition.retryCount,
        (unsigned long)report->acquisition.transportErrorCount,
        (unsigned long)report->acquisition.jumpRejectCount,
        (unsigned long)report->acquisition.failedSampleCount);

    for (uint32_t i = 0U; i < report->evidenceCount; i++)
    {
        const ControlEvidence_t *e = &controlEvidence[i];
        ControlLog(
            "CONTROL_C0_DATA,Seq=%lu,Phase=%s,ReferenceMilliDeg=%ld,"
            "ActualMilliDeg=%ld,ErrorMilliDeg=%ld,CommandRaw=%u,"
            "VelocityRawPerSecond=%ld,AccelerationRawPerSecond2=%lld,"
            "ScheduledTick=%lu,SampleTick=%lu,LatenessTicks=%lu,"
            "LoopCycles=%lu,SpiLatencyCycles=%lu,PwmCounterAtCs=%u,"
            "CorrectionRaw=0\r\n",
            (unsigned long)e->sequence, ControlPhaseName(e->phase),
            (long)RawToMilliDeg(e->referenceRaw),
            (long)RawToMilliDeg(e->actualRaw),
            (long)RawToMilliDeg(e->errorRaw),
            (unsigned int)e->commandElectricalRaw,
            (long)e->velocityRawPerSecond,
            (long long)e->accelerationRawPerSecond2,
            (unsigned long)e->scheduledTick,
            (unsigned long)e->sampleTick,
            (unsigned long)e->latenessTicks,
            (unsigned long)e->loopCycles,
            (unsigned long)e->spiLatencyCycles,
            (unsigned int)e->pwmCounterAtCs);
    }

    UBaseType_t stackHighWaterWords = uxTaskGetStackHighWaterMark(NULL);
    ControlLog(
        "CONTROL_C0_RUNTIME,FreeHeap=%lu,MinEverFreeHeap=%lu,"
        "ControlStackHighWaterWords=%lu\r\n",
        (unsigned long)xPortGetFreeHeapSize(),
        (unsigned long)xPortGetMinimumEverFreeHeapSize(),
        (unsigned long)stackHighWaterWords);
}

static void ControlRunC0(void)
{
    ControlC0Report_t report;
    memset(&report, 0, sizeof(report));
    memset(controlEvidence, 0, sizeof(controlEvidence));
    report.result = CONTROL_C0_STATUS_FAULT;

    Motor_Disable();
    Motor_ResetControlSession();
    MA600_Status_t status;
    if (!MA600_PrecheckAndClearStatus(&status))
    {
        ControlReport(&report);
        return;
    }

    ControlLog(
        "CONTROL_C0_ARMED,Profile=CONTROL_C0_OPEN_LOOP_1DEG_V1,"
        "TargetMilliDeg=1000,PowerMilli=%u,PeriodMs=%u,"
        "MaxTravelMilliDeg=3000,CorrectionRaw=0\r\n",
        CONTROL_C0_POWER_MILLI, CONTROL_C0_PERIOD_MS);

    uint32_t activeStartTick = HAL_GetTick();
    report.result = ControlHome(&report, activeStartTick);
    if (report.result == CONTROL_C0_OK)
    {
        report.result = ControlObserveOneDegree(&report, activeStartTick);
    }

    /* This is the only active-run exit. No UART evidence is emitted until
     * torque is off, including fault and operator-abort paths. */
    Motor_Disable();
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
            ControlRunC0();
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
