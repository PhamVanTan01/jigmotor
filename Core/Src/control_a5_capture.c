#include "control_a5_capture.h"

#if JIG_APP_MODE == JIG_APP_CONTROL

#include "FreeRTOS.h"
#include "cmsis_os.h"
#include "main.h"
#include "task.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

extern TIM_HandleTypeDef htim1;

static ControlA5Sample_t *controlA5Evidence;
static uint32_t controlA5FreeHeapBeforeAllocation;
static uint32_t controlA5FreeHeapAfterAllocation;
static uint32_t controlA5MinEverFreeHeapAfterAllocation;

static const MA600_ExpectedConfig_t CONTROL_A5_EXPECTED_CONFIG = {
    .zero = 0x0000U,
    .dir = 0x00U,
    .filt = 0x05U,
    .status = 0x00U,
    .prt = 0x00U,
    .rmapId = 0x00U,
    .corrCrc32 = 0x190A55ADU,
};

static void ControlA5_SetFault(ControlA5CaptureReport_t *report,
                               ControlA5Result_t result,
                               uint32_t invalidReason)
{
    if (report == NULL)
    {
        return;
    }
    if (report->measurement.result == CONTROL_A5_NOT_RUN
            || report->measurement.result == CONTROL_A5_OK)
    {
        report->measurement.result = result;
    }
    report->measurement.invalidReasonMask |= invalidReason;
    report->measurement.measurementValid = false;
}

static uint32_t ControlA5_AbsI32(int32_t value)
{
    return (value < 0) ? (uint32_t)(-(int64_t)value) : (uint32_t)value;
}

static uint32_t ControlA5_PowerToPpm(float power)
{
    if (power <= 0.0f)
    {
        return 0U;
    }
    if (power >= 1.0f)
    {
        return 1000000U;
    }
    return (uint32_t)(power * 1000000.0f + 0.5f);
}

static bool ControlA5_IsExpectedHoldState(
    const Motor_ControllerState_t *state)
{
    return state != NULL
        && state->outputEnabled
        && state->outputElectricalPositionRaw
            == (uint16_t)CONTROL_A5_COMMAND_PHASE_RAW
        && ControlA5_PowerToPpm(state->outputPower)
            == CONTROL_A5_COMMAND_POWER_PPM;
}

static bool ControlA5_ControllerStatesEqual(
    const Motor_ControllerState_t *a,
    const Motor_ControllerState_t *b)
{
    return a != NULL && b != NULL
        && a->integralTerm == b->integralTerm
        && a->lastErrorDeg == b->lastErrorDeg
        && a->commandedPositionRaw == b->commandedPositionRaw
        && a->filteredDerivativeTerm == b->filteredDerivativeTerm
        && a->lastOutputStepRaw == b->lastOutputStepRaw
        && a->feedbackTrackerInitialized == b->feedbackTrackerInitialized
        && a->feedbackAcceptedSamples == b->feedbackAcceptedSamples
        && a->outputElectricalPositionRaw == b->outputElectricalPositionRaw
        && a->outputPower == b->outputPower
        && a->outputEnabled == b->outputEnabled;
}

static uint32_t ControlA5_PwmPhaseBin(uint16_t pwmCounter)
{
    uint32_t periodCounts = __HAL_TIM_GET_AUTORELOAD(&htim1) + 1U;
    if (periodCounts == 0U)
    {
        return 0U;
    }
    uint32_t bin = (uint32_t)(((uint64_t)pwmCounter
        * CONTROL_A5_PWM_PHASE_BIN_COUNT) / periodCounts);
    return (bin < CONTROL_A5_PWM_PHASE_BIN_COUNT)
        ? bin : (CONTROL_A5_PWM_PHASE_BIN_COUNT - 1U);
}

bool ControlA5_CaptureResourcesInit(void)
{
    if (controlA5Evidence != NULL)
    {
        return true;
    }
    if (!ControlA5_MathSelfTest() || !MA600_ConfigurationGateSelfTest())
    {
        return false;
    }

    size_t allocationBytes = sizeof(ControlA5Sample_t)
        * CONTROL_A5_SAMPLE_COUNT;
    size_t freeBefore = xPortGetFreeHeapSize();
    if (freeBefore < allocationBytes
            || freeBefore - allocationBytes
                < CONTROL_A5_MIN_FREE_HEAP_AFTER_BUFFER)
    {
        return false;
    }

    ControlA5Sample_t *candidate = (ControlA5Sample_t *)pvPortMalloc(
        allocationBytes);
    if (candidate == NULL)
    {
        return false;
    }
    size_t freeAfter = xPortGetFreeHeapSize();
    if (freeAfter < CONTROL_A5_MIN_FREE_HEAP_AFTER_BUFFER)
    {
        vPortFree(candidate);
        return false;
    }

    memset(candidate, 0, allocationBytes);
    controlA5Evidence = candidate;
    controlA5FreeHeapBeforeAllocation = (uint32_t)freeBefore;
    controlA5FreeHeapAfterAllocation = (uint32_t)freeAfter;
    controlA5MinEverFreeHeapAfterAllocation =
        (uint32_t)xPortGetMinimumEverFreeHeapSize();
    return true;
}

bool ControlA5_CaptureResourcesReady(void)
{
    return controlA5Evidence != NULL;
}

void ControlA5_CaptureResourcesReleaseForInitFailure(void)
{
    if (controlA5Evidence != NULL)
    {
        vPortFree(controlA5Evidence);
        controlA5Evidence = NULL;
    }
    controlA5FreeHeapBeforeAllocation = 0U;
    controlA5FreeHeapAfterAllocation = 0U;
    controlA5MinEverFreeHeapAfterAllocation = 0U;
}

void ControlA5_CaptureReportInit(ControlA5CaptureReport_t *report)
{
    if (report == NULL)
    {
        return;
    }
    memset(report, 0, sizeof(*report));
    report->measurement.result = CONTROL_A5_NOT_RUN;
    report->configGateResult = MA600_CONFIG_GATE_READ_INVALID;
    report->intervalMinCycles = UINT32_MAX;
    report->spiLatencyMinCycles = UINT32_MAX;
    report->resourcesValid = ControlA5_CaptureResourcesReady();
    report->freeHeapBeforeAllocation = controlA5FreeHeapBeforeAllocation;
    report->freeHeapAfterAllocation = controlA5FreeHeapAfterAllocation;
    report->minEverFreeHeapAfterAllocation =
        controlA5MinEverFreeHeapAfterAllocation;
    ControlA5_StatsInit(&report->stats);

    if (!report->resourcesValid)
    {
        ControlA5_SetFault(report, CONTROL_A5_BUFFER_FAULT,
            CONTROL_A5_INVALID_RECORD);
        return;
    }

    /* This is deliberately outside the active motor/timed window. */
    memset(controlA5Evidence, 0,
        sizeof(ControlA5Sample_t) * CONTROL_A5_SAMPLE_COUNT);
}

bool ControlA5_ReadAndGateConfiguration(ControlA5CaptureReport_t *report)
{
    if (report == NULL || !report->resourcesValid)
    {
        return false;
    }

    MA600_Result_t readResult = MA600_ReadConfiguration(&report->config);
    report->configReadValid = readResult == MA600_RESULT_OK
        && report->config.valid;
    report->configGateResult = report->configReadValid
        ? MA600_ValidateConfigurationLockedGate(&report->config,
            &CONTROL_A5_EXPECTED_CONFIG)
        : MA600_CONFIG_GATE_READ_INVALID;
    report->configValid = report->configGateResult == MA600_CONFIG_GATE_OK;
    if (!report->configValid)
    {
        ControlA5_SetFault(report, CONTROL_A5_CONFIG_FAULT,
            CONTROL_A5_INVALID_CONFIG);
    }
    return report->configValid;
}

void ControlA5_SetParentAlignmentValid(ControlA5CaptureReport_t *report,
                                       bool valid)
{
    if (report == NULL)
    {
        return;
    }
    report->parentAlignmentValid = valid;
    if (!valid)
    {
        ControlA5_SetFault(report, CONTROL_A5_PARENT_ALIGNMENT_FAULT,
            CONTROL_A5_INVALID_PARENT_ALIGNMENT);
    }
}

bool ControlA5_RecordPreCaptureState(ControlA5CaptureReport_t *report)
{
    if (report == NULL)
    {
        return false;
    }
    Motor_GetControllerState(&report->preState);
    report->preStateValid = ControlA5_IsExpectedHoldState(&report->preState);
    if (!report->preStateValid)
    {
        ControlA5_SetFault(report, CONTROL_A5_HOLD_STATE_FAULT,
            CONTROL_A5_INVALID_HOLD_STATE);
    }
    return report->preStateValid;
}

bool ControlA5_RecordPostCaptureState(ControlA5CaptureReport_t *report)
{
    if (report == NULL)
    {
        return false;
    }
    Motor_GetControllerState(&report->postState);
    report->postStateValid = ControlA5_IsExpectedHoldState(&report->postState);
    report->commandChanged = !ControlA5_ControllerStatesEqual(
        &report->preState, &report->postState);
    if (!report->postStateValid || report->commandChanged)
    {
        ControlA5_SetFault(report, CONTROL_A5_HOLD_STATE_FAULT,
            CONTROL_A5_INVALID_HOLD_STATE);
    }
    return report->postStateValid && !report->commandChanged;
}

ControlA5Result_t ControlA5_CaptureStaticWindow(
    ControlA5CaptureReport_t *report,
    ControlA5AbortRequestedFn_t abortRequested)
{
    if (report == NULL || abortRequested == NULL || controlA5Evidence == NULL)
    {
        if (report != NULL)
        {
            ControlA5_SetFault(report, CONTROL_A5_INVALID_ARGUMENT,
                CONTROL_A5_INVALID_RECORD);
        }
        return CONTROL_A5_INVALID_ARGUMENT;
    }
    if (!report->configValid || !report->parentAlignmentValid
            || !report->preStateValid)
    {
        ControlA5_SetFault(report, CONTROL_A5_INVALID_ARGUMENT,
            CONTROL_A5_INVALID_RECORD);
        return report->measurement.result;
    }
    if (SystemCoreClock == 0U
            || (SystemCoreClock % CONTROL_A5_SAMPLE_RATE_HZ) != 0U)
    {
        ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
            CONTROL_A5_INVALID_TIMING);
        return report->measurement.result;
    }

    report->measurement.result = CONTROL_A5_OK;
    MA600_AcquisitionInit(&report->acquisition);
    ControlA5_StatsInit(&report->stats);
    uint32_t periodCycles = SystemCoreClock / CONTROL_A5_SAMPLE_RATE_HZ;
    report->systemClockHz = SystemCoreClock;
    report->periodCycles = periodCycles;
    report->pwmPeriodCounts = __HAL_TIM_GET_AUTORELOAD(&htim1) + 1U;
    if (report->pwmPeriodCounts == 0U)
    {
        ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
            CONTROL_A5_INVALID_TIMING);
        return report->measurement.result;
    }
    /* Start on the next RTOS tick. Anchoring sample 0 to an absolute slot
     * avoids a boundary race where sample 0 lands just before a tick and
     * sample 1 would otherwise be issued almost immediately after it. */
    uint32_t deadline = osKernelGetTickCount() + CONTROL_A5_PERIOD_MS;
    uint32_t captureStartTick = HAL_GetTick();
    uint32_t firstCsCycle = 0U;
    uint32_t previousCsCycle = 0U;

    for (uint32_t index = 0U; index < CONTROL_A5_SAMPLE_COUNT; index++)
    {
        if (abortRequested())
        {
            ControlA5_SetFault(report, CONTROL_A5_OPERATOR_ABORT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }

        if (index > 0U)
        {
            deadline += CONTROL_A5_PERIOD_MS;
        }

        uint32_t now = osKernelGetTickCount();
        if ((int32_t)(deadline - now) > 0)
        {
            (void)osDelayUntil(deadline);
            now = osKernelGetTickCount();
        }
        if ((int32_t)(now - deadline) > 0)
        {
            report->skippedSlots += now - deadline;
            report->timingOverruns++;
            ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }
        if ((int32_t)(deadline - now) > 0)
        {
            /* A scheduler returning before the absolute deadline is also
             * invalid; do not busy-wait or issue an early/catch-up read. */
            report->timingOverruns++;
            ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }

        report->slotsReached++;
        if ((uint32_t)(HAL_GetTick() - captureStartTick)
                >= CONTROL_A5_MAX_CAPTURE_MS)
        {
            report->timingOverruns++;
            ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }

        MA600_Sample_t sample;
        MA600_Result_t readResult = MA600_AcquireSample(
            &report->acquisition, CONTROL_A5_MAX_UNWRAP_JUMP_RAW,
            CONTROL_A5_READ_ATTEMPTS, &sample);
        if (readResult != MA600_RESULT_OK)
        {
            ControlA5_SetFault(report, CONTROL_A5_ACQUISITION_FAULT,
                CONTROL_A5_INVALID_ACQUISITION);
            break;
        }
        if (!sample.meta.metaValid || sample.attempts != 1U
                || sample.flags != MA600_SAMPLE_FLAG_NONE)
        {
            ControlA5_SetFault(report, CONTROL_A5_RECORD_OVERFLOW,
                CONTROL_A5_INVALID_RECORD);
            break;
        }

        uint32_t spiLatency = ControlA5_CycleDelta(
            sample.meta.transferCompleteCycle, sample.meta.csAssertCycle);
        if (spiLatency > UINT16_MAX
                || report->spiLatencySumCycles > UINT32_MAX - spiLatency)
        {
            ControlA5_SetFault(report, CONTROL_A5_RECORD_OVERFLOW,
                CONTROL_A5_INVALID_RECORD);
            break;
        }

        int32_t scheduleError = 0;
        if (index == 0U)
        {
            firstCsCycle = sample.meta.csAssertCycle;
        }
        else
        {
            uint32_t interval = ControlA5_CycleDelta(
                sample.meta.csAssertCycle, previousCsCycle);
            if (interval < report->intervalMinCycles)
            {
                report->intervalMinCycles = interval;
            }
            if (interval > report->intervalMaxCycles)
            {
                report->intervalMaxCycles = interval;
            }
        }
        previousCsCycle = sample.meta.csAssertCycle;
        if (!ControlA5_ScheduleErrorCycles(firstCsCycle,
                sample.meta.csAssertCycle, index, periodCycles,
                &scheduleError))
        {
            ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }
        uint32_t absScheduleError = ControlA5_AbsI32(scheduleError);
        if (absScheduleError > report->maxAbsScheduleErrorCycles)
        {
            report->maxAbsScheduleErrorCycles = absScheduleError;
        }
        if (absScheduleError >= periodCycles)
        {
            report->timingOverruns++;
            ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
                CONTROL_A5_INVALID_TIMING);
            break;
        }

        if (!ControlA5_StatsPush(&report->stats, sample.raw))
        {
            ControlA5_SetFault(report, CONTROL_A5_MATH_OVERFLOW,
                CONTROL_A5_INVALID_RECORD);
            break;
        }

        ControlA5Sample_t *record = &controlA5Evidence[index];
        record->csAssertCycle = sample.meta.csAssertCycle;
        record->angleRaw = sample.raw;
        record->pwmCounterAtCs = sample.meta.pwmCounterAtCs;
        record->spiLatencyCycles = (uint16_t)spiLatency;
        record->attempts = sample.attempts;
        record->flags = sample.flags;
        report->evidenceCount = index + 1U;

        if (spiLatency < report->spiLatencyMinCycles)
        {
            report->spiLatencyMinCycles = spiLatency;
        }
        if (spiLatency > report->spiLatencyMaxCycles)
        {
            report->spiLatencyMaxCycles = spiLatency;
        }
        report->spiLatencySumCycles += spiLatency;
        report->pwmPhaseBinMask |= 1UL
            << ControlA5_PwmPhaseBin(sample.meta.pwmCounterAtCs);

        if (report->stats.maxAbsStepRaw > CONTROL_A5_MAX_SAMPLE_STEP_RAW)
        {
            ControlA5_SetFault(report, CONTROL_A5_SAMPLE_STEP_LIMIT,
                CONTROL_A5_INVALID_STATIC_WINDOW);
            break;
        }
        uint64_t negativeTravel = report->stats.minRelRaw < 0
            ? (uint64_t)(-(report->stats.minRelRaw + 1)) + 1U : 0U;
        uint64_t positiveTravel = report->stats.maxRelRaw > 0
            ? (uint64_t)report->stats.maxRelRaw : 0U;
        if (negativeTravel > CONTROL_A5_MAX_STATIC_TRAVEL_RAW
                || positiveTravel > CONTROL_A5_MAX_STATIC_TRAVEL_RAW)
        {
            ControlA5_SetFault(report, CONTROL_A5_STATIC_TRAVEL_LIMIT,
                CONTROL_A5_INVALID_STATIC_WINDOW);
            break;
        }
    }

    report->captureDurationMs = HAL_GetTick() - captureStartTick;
    if (report->captureDurationMs > CONTROL_A5_MAX_CAPTURE_MS)
    {
        report->timingOverruns++;
        ControlA5_SetFault(report, CONTROL_A5_TIMING_FAULT,
            CONTROL_A5_INVALID_TIMING);
    }

    report->acquisitionValid = report->evidenceCount
            == CONTROL_A5_SAMPLE_COUNT
        && report->acquisition.readAttempts == CONTROL_A5_SAMPLE_COUNT
        && report->acquisition.acceptedSamples == CONTROL_A5_SAMPLE_COUNT
        && report->acquisition.retryCount == 0U
        && report->acquisition.transportErrorCount == 0U
        && report->acquisition.jumpRejectCount == 0U
        && report->acquisition.failedSampleCount == 0U;
    report->timingValid = report->evidenceCount == CONTROL_A5_SAMPLE_COUNT
        && report->slotsReached == CONTROL_A5_SAMPLE_COUNT
        && report->skippedSlots == 0U
        && report->timingOverruns == 0U;
    report->staticWindowValid = report->evidenceCount
            == CONTROL_A5_SAMPLE_COUNT
        && report->stats.maxAbsStepRaw <= CONTROL_A5_MAX_SAMPLE_STEP_RAW
        && report->stats.minRelRaw >= -CONTROL_A5_MAX_STATIC_TRAVEL_RAW
        && report->stats.maxRelRaw <= CONTROL_A5_MAX_STATIC_TRAVEL_RAW;
    report->recordIntegrityValid = report->evidenceCount
            == CONTROL_A5_SAMPLE_COUNT
        && report->stats.count == CONTROL_A5_SAMPLE_COUNT;

    if (!report->acquisitionValid)
    {
        report->measurement.invalidReasonMask |=
            CONTROL_A5_INVALID_ACQUISITION;
    }
    if (!report->timingValid)
    {
        report->measurement.invalidReasonMask |= CONTROL_A5_INVALID_TIMING;
    }
    if (!report->staticWindowValid)
    {
        report->measurement.invalidReasonMask |=
            CONTROL_A5_INVALID_STATIC_WINDOW;
    }
    if (!report->recordIntegrityValid)
    {
        report->measurement.invalidReasonMask |= CONTROL_A5_INVALID_RECORD;
    }
    return report->measurement.result;
}

bool ControlA5_RecordSafeStopState(ControlA5CaptureReport_t *report)
{
    if (report == NULL)
    {
        return false;
    }
    Motor_GetControllerState(&report->safeStopState);
    report->safeStopValid = !report->safeStopState.outputEnabled
        && report->safeStopState.outputPower == 0.0f
        && report->safeStopState.outputElectricalPositionRaw
            == (uint16_t)CONTROL_A5_COMMAND_PHASE_RAW;
    if (!report->safeStopValid)
    {
        ControlA5_SetFault(report, CONTROL_A5_SAFE_STOP_FAULT,
            CONTROL_A5_INVALID_SAFE_STOP);
    }
    return report->safeStopValid;
}

bool ControlA5_FinalizeAfterSafeStop(ControlA5CaptureReport_t *report)
{
    if (report == NULL)
    {
        return false;
    }
    /* Preserve the accepted evidence summary even if safe-stop verification
     * itself failed. Such a run remains invalid, but losing its already
     * captured diagnostics would make the safety fault harder to explain. */
    if (report->stats.initialized
            && !ControlA5_StatsFinalize(&report->stats,
                &report->measurement.rawAngle))
    {
        ControlA5_SetFault(report, CONTROL_A5_MATH_OVERFLOW,
            CONTROL_A5_INVALID_RECORD);
    }

    if (report->intervalMinCycles == UINT32_MAX)
    {
        report->intervalMinCycles = 0U;
    }
    if (report->spiLatencyMinCycles == UINT32_MAX)
    {
        report->spiLatencyMinCycles = 0U;
    }
    report->spiLatencyMeanCycles = report->evidenceCount > 0U
        ? (report->spiLatencySumCycles + report->evidenceCount / 2U)
            / report->evidenceCount
        : 0U;
    report->minEverFreeHeapAfterAllocation =
        (uint32_t)xPortGetMinimumEverFreeHeapSize();

    report->measurement.measurementValid =
        report->measurement.result == CONTROL_A5_OK
        && report->resourcesValid
        && report->configValid
        && report->parentAlignmentValid
        && report->preStateValid
        && report->postStateValid
        && !report->commandChanged
        && report->acquisitionValid
        && report->timingValid
        && report->staticWindowValid
        && report->recordIntegrityValid
        && report->safeStopValid;
    return report->measurement.measurementValid;
}

const ControlA5Sample_t *ControlA5_GetEvidenceBuffer(void)
{
    return controlA5Evidence;
}

#endif /* JIG_APP_MODE == JIG_APP_CONTROL */
