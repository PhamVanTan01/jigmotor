#include "ma600_acquisition.h"
#include "main.h"
#include <limits.h>
#include <string.h>

#ifndef ENABLE_MA600_FAULT_INJECTION
#define ENABLE_MA600_FAULT_INJECTION 0
#endif

void MA600_AcquisitionInit(MA600_AcquisitionContext_t *ctx)
{
    if (ctx == NULL)
    {
        return;
    }

    memset(ctx, 0, sizeof(*ctx));
    MA600_UnwrapContextInit(&ctx->unwrap);
}

MA600_Result_t MA600_AcquireSample(MA600_AcquisitionContext_t *ctx,
                                    int32_t maxJumpRaw,
                                    uint8_t maxAttempts,
                                    MA600_Sample_t *out)
{
    if (ctx == NULL || out == NULL || maxAttempts == 0 || maxJumpRaw < 0)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    memset(out, 0, sizeof(*out));
    out->result = MA600_RESULT_INVALID_ARG;

    for (uint8_t attempt = 1; attempt <= maxAttempts; attempt++)
    {
        uint16_t raw = 0;
        MA600_ReadMeta_t meta = {0};

        ctx->readAttempts++;
        out->attempts = attempt;
        if (attempt > 1)
        {
            ctx->retryCount++;
            out->flags |= MA600_SAMPLE_FLAG_RETRIED;
        }

        MA600_Result_t result = MA600_ReadRawChecked(&raw, &meta);
        out->meta = meta;
        if (result != MA600_RESULT_OK)
        {
            ctx->transportErrorCount++;
            out->flags |= MA600_SAMPLE_FLAG_TRANSPORT_ERROR;
            out->result = result;
            continue;
        }

        int64_t unwrappedRaw = 0;
        result = MA600_UnwrapUpdate(&ctx->unwrap, raw, meta.csAssertCycle,
            maxJumpRaw, &unwrappedRaw);
        if (result != MA600_RESULT_OK)
        {
            ctx->jumpRejectCount++;
            out->flags |= MA600_SAMPLE_FLAG_JUMP_REJECTED;
            out->result = result;
            continue;
        }

        out->raw = raw;
        out->unwrappedRaw = unwrappedRaw;
        out->result = MA600_RESULT_OK;
        ctx->acceptedSamples++;
        return MA600_RESULT_OK;
    }

    out->flags |= MA600_SAMPLE_FLAG_INVALID;
    ctx->failedSampleCount++;
    return out->result;
}

float MA600_UnwrappedRawToDegrees(int64_t unwrappedRaw)
{
    return (float)unwrappedRaw * 360.0f / 65536.0f;
}

static bool SafeAddI64(int64_t a, int64_t b, int64_t *out)
{
    if (out == NULL
            || (b > 0 && a > INT64_MAX - b)
            || (b < 0 && a < INT64_MIN - b))
    {
        return false;
    }
    *out = a + b;
    return true;
}

static bool SafeSubI64(int64_t a, int64_t b, int64_t *out)
{
    if (out == NULL
            || (b < 0 && a > INT64_MAX + b)
            || (b > 0 && a < INT64_MIN + b))
    {
        return false;
    }
    *out = a - b;
    return true;
}

static bool ScaleByQ16(int64_t value, int64_t *out)
{
    if (out == NULL
            || value > INT64_MAX / 65536LL
            || value < INT64_MIN / 65536LL)
    {
        return false;
    }
    *out = value * 65536LL;
    return true;
}

bool MA600_DivRoundNearestAwayFromZero(int64_t numerator, int64_t denominator,
                                        int64_t *out)
{
    if (out == NULL || denominator <= 0 || numerator == INT64_MIN)
    {
        return false;
    }

    int64_t half = denominator / 2;
    if (numerator >= 0)
    {
        if (numerator > INT64_MAX - half)
        {
            return false;
        }
        *out = (numerator + half) / denominator;
    }
    else
    {
        int64_t magnitude = -numerator;
        if (magnitude > INT64_MAX - half)
        {
            return false;
        }
        *out = -((magnitude + half) / denominator);
    }
    return true;
}

bool MA600_ComputeCanonicalPointMeanQ16(int64_t pointAnchorUnwrapped,
                                        int64_t sumRelRaw,
                                        uint32_t acceptedSampleCount,
                                        int64_t *outMeanRelRawQ16,
                                        int64_t *outPointMeanRawQ16)
{
    if (acceptedSampleCount == 0U || outMeanRelRawQ16 == NULL
            || outPointMeanRawQ16 == NULL)
    {
        return false;
    }

    int64_t scaledSum = 0;
    int64_t scaledAnchor = 0;
    int64_t meanRelRawQ16 = 0;
    int64_t pointMeanRawQ16 = 0;
    if (!ScaleByQ16(sumRelRaw, &scaledSum)
            || !ScaleByQ16(pointAnchorUnwrapped, &scaledAnchor)
            || !MA600_DivRoundNearestAwayFromZero(scaledSum,
                (int64_t)acceptedSampleCount, &meanRelRawQ16)
            || !SafeAddI64(scaledAnchor, meanRelRawQ16, &pointMeanRawQ16))
    {
        return false;
    }

    *outMeanRelRawQ16 = meanRelRawQ16;
    *outPointMeanRawQ16 = pointMeanRawQ16;
    return true;
}

bool MA600_ComputeCanonicalErrorQ16(int64_t pointMeanRawQ16,
                                    int64_t point0MeanRawQ16,
                                    int32_t directionSign,
                                    uint32_t pointIndex,
                                    uint32_t stepRaw,
                                    int64_t *outErrorRawQ16)
{
    if (outErrorRawQ16 == NULL || (directionSign != 1 && directionSign != -1)
            || stepRaw == 0U)
    {
        return false;
    }
    if ((uint64_t)pointIndex > (uint64_t)INT64_MAX / (uint64_t)stepRaw)
    {
        return false;
    }

    int64_t targetRaw = (int64_t)((uint64_t)pointIndex * (uint64_t)stepRaw);
    if (directionSign < 0)
    {
        targetRaw = -targetRaw;
    }

    int64_t targetRawQ16 = 0;
    int64_t measuredRelativeRawQ16 = 0;
    if (!ScaleByQ16(targetRaw, &targetRawQ16)
            || !SafeSubI64(pointMeanRawQ16, point0MeanRawQ16,
                &measuredRelativeRawQ16)
            || !SafeSubI64(measuredRelativeRawQ16, targetRawQ16,
                outErrorRawQ16))
    {
        return false;
    }
    return true;
}

static bool CycleReached(uint32_t now, uint32_t target)
{
    return (int32_t)(now - target) >= 0;
}

static uint32_t DefaultPointNow(void *user)
{
    (void)user;
    return DWT->CYCCNT;
}

static void DefaultPointWaitUntil(void *user, uint32_t targetCycle)
{
    (void)user;
    while (!CycleReached(DWT->CYCCNT, targetCycle))
    {
        __NOP();
    }
}

static MA600_Result_t DefaultPointRead(void *user, uint16_t *raw,
                                       MA600_ReadMeta_t *meta)
{
    (void)user;
    return MA600_ReadRawChecked(raw, meta);
}

static MA600_Result_t FinishPointFailure(MA600_PointSample_t *out,
                                          MA600_Result_t result)
{
    out->valid = false;
    out->result = result;
    return result;
}

MA600_Result_t MA600_ReadAveragedPointWithIo(
    MA600_UnwrapContext_t *sweepCtx,
    int64_t pointAnchorUnwrapped,
    const MA600_PointSamplerConfig_t *config,
    const MA600_PointSamplerIo_t *io,
    MA600_PointSample_t *out)
{
    if (out != NULL)
    {
        memset(out, 0, sizeof(*out));
        out->result = MA600_RESULT_INVALID_ARG;
        out->lastFailureResult = MA600_RESULT_OK;
    }
    if (sweepCtx == NULL || config == NULL || io == NULL || out == NULL
            || io->read == NULL || io->now == NULL
            || config->requiredAcceptedSamples == 0U
            || config->maxTransactions < config->requiredAcceptedSamples
            || config->maxElapsedCycles == 0U
            || config->maxElapsedCycles > INT32_MAX
            || config->maxJumpRaw < 0
            || (config->timingMode != MA600_POINT_TIMING_BACK_TO_BACK
                && config->timingMode != MA600_POINT_TIMING_SCHEDULED_START_TO_START)
            || (config->timingMode == MA600_POINT_TIMING_SCHEDULED_START_TO_START
                && (config->sampleIntervalCycles == 0U
                    || config->sampleIntervalCycles > INT32_MAX
                    || io->waitUntil == NULL)))
    {
        return MA600_RESULT_INVALID_ARG;
    }

    out->pointAnchorUnwrapped = pointAnchorUnwrapped;
    out->requiredAcceptedSamples = config->requiredAcceptedSamples;
    out->madFilteringEnabled = false;
    out->minRelRaw = INT64_MAX;
    out->maxRelRaw = INT64_MIN;

    uint32_t nextSampleCycle = 0U;
    uint32_t consecutiveFailures = 0U;

    while (out->acceptedSampleCount < config->requiredAcceptedSamples)
    {
        if (out->transactionCount >= config->maxTransactions)
        {
            return FinishPointFailure(out, MA600_RESULT_ACQUISITION_BUDGET_EXCEEDED);
        }

        bool hadScheduledSlot = false;
        uint32_t scheduledCycle = 0U;
        if (config->timingMode == MA600_POINT_TIMING_SCHEDULED_START_TO_START
                && out->scheduleInitialized)
        {
            scheduledCycle = nextSampleCycle;
            if ((uint32_t)(scheduledCycle - out->firstAttemptCycle)
                    > config->maxElapsedCycles)
            {
                return FinishPointFailure(out, MA600_RESULT_ACQUISITION_TIMEOUT);
            }
            io->waitUntil(io->user, scheduledCycle);
            hadScheduledSlot = true;
        }

        uint16_t raw = 0U;
        MA600_ReadMeta_t meta = {0};
        MA600_Result_t readResult = io->read(io->user, &raw, &meta);
        out->transactionCount++;

        if (!meta.metaValid)
        {
            out->metadataInvalidCount++;
            return FinishPointFailure(out, MA600_RESULT_TIMING_METADATA_INVALID);
        }

        out->lastAttemptCycle = meta.csAssertCycle;
        if (out->transactionCount == 1U)
        {
            out->firstAttemptCycle = meta.csAssertCycle;
            if (config->timingMode == MA600_POINT_TIMING_SCHEDULED_START_TO_START)
            {
                out->scheduleInitialized = true;
                nextSampleCycle = meta.csAssertCycle + config->sampleIntervalCycles;
            }
        }
        else if (hadScheduledSlot)
        {
            int32_t timingError = (int32_t)(meta.csAssertCycle - scheduledCycle);
            uint32_t absoluteTimingError = (timingError < 0)
                ? (uint32_t)(-(int64_t)timingError)
                : (uint32_t)timingError;
            if (timingError > 0)
            {
                out->timingOverrunCount++;
            }
            if (absoluteTimingError > out->maxAbsTimingErrorCycles)
            {
                out->maxAbsTimingErrorCycles = absoluteTimingError;
            }
            nextSampleCycle = scheduledCycle + config->sampleIntervalCycles;
        }

        uint32_t nowAfterAttempt = io->now(io->user);
        out->elapsedCycles = nowAfterAttempt - out->firstAttemptCycle;
        if (out->elapsedCycles > config->maxElapsedCycles)
        {
            return FinishPointFailure(out, MA600_RESULT_ACQUISITION_TIMEOUT);
        }

        MA600_Result_t sampleResult = readResult;
        int64_t acceptedUnwrapped = 0;
        if (readResult != MA600_RESULT_OK)
        {
            if (readResult == MA600_RESULT_SPI_TIMEOUT
                    || readResult == MA600_RESULT_SPI_ERROR)
            {
                out->spiFailureCount++;
            }
        }
        else
        {
            sampleResult = MA600_UnwrapUpdate(sweepCtx, raw, meta.csAssertCycle,
                config->maxJumpRaw, &acceptedUnwrapped);
            if (sampleResult == MA600_RESULT_SAMPLE_JUMP)
            {
                out->jumpRejectedCount++;
            }
        }

        if (sampleResult != MA600_RESULT_OK)
        {
            out->lastFailureResult = sampleResult;
            consecutiveFailures++;
            if (consecutiveFailures > out->maxConsecutiveFailures)
            {
                out->maxConsecutiveFailures = consecutiveFailures;
            }
            if (consecutiveFailures > config->maxConsecutiveFailures)
            {
                return FinishPointFailure(out, MA600_RESULT_ACQUISITION_BUDGET_EXCEEDED);
            }
        }
        else
        {
            consecutiveFailures = 0U;
            int64_t relRaw = 0;
            int64_t newSum = 0;
            if (!SafeSubI64(acceptedUnwrapped, pointAnchorUnwrapped, &relRaw)
                    || !SafeAddI64(out->sumRelRaw, relRaw, &newSum))
            {
                return FinishPointFailure(out, MA600_RESULT_MATH_OVERFLOW);
            }
            out->sumRelRaw = newSum;
            if (relRaw < out->minRelRaw) out->minRelRaw = relRaw;
            if (relRaw > out->maxRelRaw) out->maxRelRaw = relRaw;
            if (out->acceptedSampleCount == 0U)
            {
                out->firstAcceptedUnwrapped = acceptedUnwrapped;
            }
            out->lastAcceptedUnwrapped = acceptedUnwrapped;
            out->acceptedSampleCount++;
        }

        if (out->acceptedSampleCount >= config->requiredAcceptedSamples)
        {
            break;
        }

        if (config->timingMode == MA600_POINT_TIMING_SCHEDULED_START_TO_START)
        {
            if (CycleReached(nowAfterAttempt, nextSampleCycle))
            {
                uint32_t lateCycles = nowAfterAttempt - nextSampleCycle;
                uint32_t missedSlots = lateCycles / config->sampleIntervalCycles + 1U;
                if (UINT32_MAX - out->skippedSlotCount < missedSlots)
                {
                    return FinishPointFailure(out, MA600_RESULT_ACQUISITION_BUDGET_EXCEEDED);
                }
                out->skippedSlotCount += missedSlots;
                nextSampleCycle += missedSlots * config->sampleIntervalCycles;
            }
        }
    }

    if (!MA600_ComputeCanonicalPointMeanQ16(pointAnchorUnwrapped,
            out->sumRelRaw, out->acceptedSampleCount,
            &out->meanRelRawQ16, &out->pointMeanRawQ16))
    {
        return FinishPointFailure(out, MA600_RESULT_MATH_OVERFLOW);
    }

    out->valid = true;
    out->result = MA600_RESULT_OK;
    return MA600_RESULT_OK;
}

MA600_Result_t MA600_ReadAveragedPoint(
    MA600_UnwrapContext_t *sweepCtx,
    int64_t pointAnchorUnwrapped,
    const MA600_PointSamplerConfig_t *config,
    MA600_PointSample_t *out)
{
    const MA600_PointSamplerIo_t io = {
        .read = DefaultPointRead,
        .now = DefaultPointNow,
        .waitUntil = DefaultPointWaitUntil,
        .user = NULL,
    };
    return MA600_ReadAveragedPointWithIo(sweepCtx, pointAnchorUnwrapped,
        config, &io, out);
}

#define POINT_SELFTEST_MAX_INPUTS 8U
typedef struct
{
    uint16_t raw[POINT_SELFTEST_MAX_INPUTS];
    MA600_Result_t result[POINT_SELFTEST_MAX_INPUTS];
    uint32_t csCycle[POINT_SELFTEST_MAX_INPUTS];
    uint32_t afterCycle[POINT_SELFTEST_MAX_INPUTS];
    bool metaValid[POINT_SELFTEST_MAX_INPUTS];
    uint32_t count;
    uint32_t index;
    uint32_t now;
    uint32_t waits[POINT_SELFTEST_MAX_INPUTS];
    uint32_t waitCount;
} PointSelfTestIo_t;

static MA600_Result_t PointSelfTestRead(void *user, uint16_t *raw,
                                        MA600_ReadMeta_t *meta)
{
    PointSelfTestIo_t *state = (PointSelfTestIo_t *)user;
    if (state == NULL || raw == NULL || meta == NULL || state->index >= state->count)
    {
        return MA600_RESULT_INVALID_ARG;
    }
    uint32_t i = state->index++;
    memset(meta, 0, sizeof(*meta));
    meta->csAssertCycle = state->csCycle[i];
    meta->metaValid = state->metaValid[i];
    *raw = state->raw[i];
    state->now = state->afterCycle[i];
    return state->result[i];
}

static uint32_t PointSelfTestNow(void *user)
{
    return ((PointSelfTestIo_t *)user)->now;
}

static void PointSelfTestWaitUntil(void *user, uint32_t targetCycle)
{
    PointSelfTestIo_t *state = (PointSelfTestIo_t *)user;
    if (state->waitCount < POINT_SELFTEST_MAX_INPUTS)
    {
        state->waits[state->waitCount++] = targetCycle;
    }
    if (!CycleReached(state->now, targetCycle))
    {
        state->now = targetCycle;
    }
}

static MA600_PointSamplerConfig_t PointSelfTestConfig(uint32_t required,
                                                       uint32_t interval,
                                                       uint32_t maxTransactions)
{
    MA600_PointSamplerConfig_t config = {
        .timingMode = MA600_POINT_TIMING_SCHEDULED_START_TO_START,
        .sampleIntervalCycles = interval,
        .requiredAcceptedSamples = required,
        .maxTransactions = maxTransactions,
        .maxConsecutiveFailures = maxTransactions,
        .maxElapsedCycles = 100000U,
        .maxJumpRaw = 20,
    };
    return config;
}

static void PointSelfTestInitIo(PointSelfTestIo_t *state, uint32_t count)
{
    memset(state, 0, sizeof(*state));
    state->count = count;
    for (uint32_t i = 0; i < count; i++)
    {
        state->result[i] = MA600_RESULT_OK;
        state->metaValid[i] = true;
    }
}

bool MA600_PointSamplerSelfTest(void)
{
    int64_t rounded = 0;
    bool roundingOk = MA600_DivRoundNearestAwayFromZero(1, 2, &rounded) && rounded == 1
        && MA600_DivRoundNearestAwayFromZero(-1, 2, &rounded) && rounded == -1
        && MA600_DivRoundNearestAwayFromZero(3, 2, &rounded) && rounded == 2
        && MA600_DivRoundNearestAwayFromZero(-3, 2, &rounded) && rounded == -2;

    int64_t meanRel = 0;
    int64_t pointMean = 0;
    bool meanOk = MA600_ComputeCanonicalPointMeanQ16(100, 1, 2,
        &meanRel, &pointMean)
        && meanRel == 32768LL
        && pointMean == 100LL * 65536LL + 32768LL;
    bool negativeMeanOk = MA600_ComputeCanonicalPointMeanQ16(-100, -1, 2,
        &meanRel, &pointMean)
        && meanRel == -32768LL
        && pointMean == -100LL * 65536LL - 32768LL;

    int64_t point0 = 100LL * 65536LL;
    int64_t fullTurn = point0 + 65536LL * 65536LL;
    int64_t error = 1;
    bool errorOk = MA600_ComputeCanonicalErrorQ16(point0, point0, 1, 0, 256, &error)
        && error == 0
        && MA600_ComputeCanonicalErrorQ16(fullTurn, point0, 1, 256, 256, &error)
        && error == 0;

    MA600_PointSamplerIo_t io = {
        .read = PointSelfTestRead,
        .now = PointSelfTestNow,
        .waitUntil = PointSelfTestWaitUntil,
        .user = NULL,
    };
    MA600_UnwrapContext_t ctx;
    MA600_PointSample_t point;
    PointSelfTestIo_t state;

    PointSelfTestInitIo(&state, 2U);
    state.raw[0] = 100U; state.raw[1] = 101U;
    state.csCycle[0] = 1000U; state.csCycle[1] = 1040U;
    state.afterCycle[0] = 1005U; state.afterCycle[1] = 1045U;
    state.now = 995U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    MA600_PointSamplerConfig_t config = PointSelfTestConfig(2U, 40U, 2U);
    bool immediateOk = MA600_ReadAveragedPointWithIo(&ctx, 100, &config, &io, &point)
        == MA600_RESULT_OK
        && point.valid && point.transactionCount == 2U
        && point.acceptedSampleCount == 2U && point.skippedSlotCount == 0U
        && point.firstAcceptedUnwrapped == 100LL
        && point.lastAcceptedUnwrapped == 101LL
        && point.minRelRaw == 0LL && point.maxRelRaw == 1LL
        && point.pointMeanRawQ16 == 100LL * 65536LL + 32768LL
        && state.waitCount == 1U && state.waits[0] == 1040U;

    PointSelfTestInitIo(&state, 4U);
    state.raw[0] = 100U; state.raw[1] = 104U;
    state.raw[2] = 96U; state.raw[3] = 100U;
    state.csCycle[0] = 1000U; state.csCycle[1] = 1040U;
    state.csCycle[2] = 1080U; state.csCycle[3] = 1120U;
    state.afterCycle[0] = 1005U; state.afterCycle[1] = 1045U;
    state.afterCycle[2] = 1085U; state.afterCycle[3] = 1125U;
    state.now = 995U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    config = PointSelfTestConfig(4U, 40U, 4U);
    bool alternatingWindowOk = MA600_ReadAveragedPointWithIo(&ctx, 100,
        &config, &io, &point) == MA600_RESULT_OK
        && point.minRelRaw == -4LL && point.maxRelRaw == 4LL
        && point.maxRelRaw - point.minRelRaw == 8LL
        && point.lastAcceptedUnwrapped - point.firstAcceptedUnwrapped == 0LL;

    PointSelfTestInitIo(&state, 4U);
    state.raw[0] = 100U; state.raw[1] = 101U;
    state.raw[2] = 102U; state.raw[3] = 103U;
    state.csCycle[0] = 1000U; state.csCycle[1] = 1040U;
    state.csCycle[2] = 1080U; state.csCycle[3] = 1120U;
    state.afterCycle[0] = 1005U; state.afterCycle[1] = 1045U;
    state.afterCycle[2] = 1085U; state.afterCycle[3] = 1125U;
    state.now = 995U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    config = PointSelfTestConfig(4U, 40U, 4U);
    bool monotonicWindowOk = MA600_ReadAveragedPointWithIo(&ctx, 100,
        &config, &io, &point) == MA600_RESULT_OK
        && point.minRelRaw == 0LL && point.maxRelRaw == 3LL
        && point.maxRelRaw - point.minRelRaw == 3LL
        && point.lastAcceptedUnwrapped - point.firstAcceptedUnwrapped == 3LL;

    PointSelfTestInitIo(&state, 3U);
    state.result[0] = MA600_RESULT_SPI_TIMEOUT;
    state.raw[1] = 100U; state.raw[2] = 102U;
    state.csCycle[0] = 1000U; state.csCycle[1] = 1040U;
    state.csCycle[2] = 1080U;
    state.afterCycle[0] = 1005U; state.afterCycle[1] = 1045U;
    state.afterCycle[2] = 1085U;
    state.now = 995U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    config = PointSelfTestConfig(2U, 40U, 3U);
    bool firstFailureOk = MA600_ReadAveragedPointWithIo(&ctx, 100, &config, &io, &point)
        == MA600_RESULT_OK
        && point.scheduleInitialized && point.transactionCount == 3U
        && point.acceptedSampleCount == 2U && point.spiFailureCount == 1U
        && point.lastFailureResult == MA600_RESULT_SPI_TIMEOUT
        && state.waitCount == 2U
        && state.waits[0] == 1040U && state.waits[1] == 1080U;

    PointSelfTestInitIo(&state, 3U);
    state.raw[0] = 100U; state.raw[1] = 101U; state.raw[2] = 102U;
    state.csCycle[0] = 1000U; state.csCycle[1] = 1125U; state.csCycle[2] = 1160U;
    state.afterCycle[0] = 1005U; state.afterCycle[1] = 1130U;
    state.afterCycle[2] = 1165U;
    state.now = 995U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    config = PointSelfTestConfig(3U, 40U, 3U);
    bool skippedOk = MA600_ReadAveragedPointWithIo(&ctx, 100, &config, &io, &point)
        == MA600_RESULT_OK
        && point.skippedSlotCount == 2U && point.timingOverrunCount == 1U
        && point.maxAbsTimingErrorCycles == 85U
        && state.waitCount == 2U
        && state.waits[0] == 1040U && state.waits[1] == 1160U;

    PointSelfTestInitIo(&state, 2U);
    state.raw[0] = 65534U; state.raw[1] = 1U;
    state.csCycle[0] = 0xFFFFFFF0U; state.csCycle[1] = 0x00000010U;
    state.afterCycle[0] = 0xFFFFFFF5U; state.afterCycle[1] = 0x00000015U;
    state.now = 0xFFFFFFE0U;
    io.user = &state;
    MA600_UnwrapContextInit(&ctx);
    config = PointSelfTestConfig(2U, 32U, 2U);
    bool wrapOk = MA600_ReadAveragedPointWithIo(&ctx, 65534, &config, &io, &point)
        == MA600_RESULT_OK
        && point.elapsedCycles == 37U && point.skippedSlotCount == 0U
        && point.firstAcceptedUnwrapped == 65534LL
        && point.lastAcceptedUnwrapped == 65537LL;

    MA600_UnwrapContextInit(&ctx);
    int64_t unwrapped = 0;
    bool anchorAccepted = MA600_UnwrapUpdate(&ctx, 100U, 10U, 10, &unwrapped)
        == MA600_RESULT_OK;
    uint16_t acceptedLastRaw = ctx.lastRaw;
    int64_t acceptedPosition = ctx.unwrappedRaw;
    uint32_t acceptedCycle = ctx.lastAcceptedCycle;
    uint32_t acceptedCount = ctx.acceptedCount;
    bool jumpRejected = MA600_UnwrapUpdate(&ctx, 200U, 20U, 10, &unwrapped)
        == MA600_RESULT_SAMPLE_JUMP
        && ctx.lastRaw == acceptedLastRaw
        && ctx.unwrappedRaw == acceptedPosition
        && ctx.lastAcceptedCycle == acceptedCycle
        && ctx.acceptedCount == acceptedCount
        && ctx.rejectedCount == 1U;

    return roundingOk && meanOk && negativeMeanOk && errorOk
        && immediateOk && alternatingWindowOk && monotonicWindowOk
        && firstFailureOk && skippedOk && wrapOk
        && anchorAccepted && jumpRejected;
}

bool MA600_AcquisitionRunFaultInjectionSelfTest(void)
{
#if ENABLE_MA600_FAULT_INJECTION
    MA600_AcquisitionContext_t ctx;
    MA600_AcquisitionInit(&ctx);

    MA600_Sample_t sample;
    MA600_FaultInjection_ArmNextTransaction(1, MA600_RESULT_SPI_TIMEOUT);
    MA600_Result_t result = MA600_AcquireSample(&ctx, 1821, 1U, &sample);
    MA600_FaultInjection_Reset();

    return result == MA600_RESULT_SPI_TIMEOUT
        && sample.result == MA600_RESULT_SPI_TIMEOUT
        && sample.meta.metaValid
        && (sample.flags & MA600_SAMPLE_FLAG_INVALID) != 0
        && sample.attempts == 1U
        && ctx.acceptedSamples == 0U
        && ctx.failedSampleCount == 1U
        && !ctx.unwrap.initialized;
#else
    return false;
#endif
}
