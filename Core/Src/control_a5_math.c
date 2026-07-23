#include "control_a5_math.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>

#define CONTROL_A5_CRC32_INITIAL       0xFFFFFFFFUL
#define CONTROL_A5_CRC32_XOR_OUT       0xFFFFFFFFUL
#define CONTROL_A5_CRC32_POLYNOMIAL    0xEDB88320UL
#define CONTROL_A5_SQRT_INT64_MAX      3037000499LL

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

static bool SafeSquareI64(int64_t value, int64_t *out)
{
    if (out == NULL || value > CONTROL_A5_SQRT_INT64_MAX
            || value < -CONTROL_A5_SQRT_INT64_MAX)
    {
        return false;
    }
    *out = value * value;
    return true;
}

static uint32_t AbsI32ToU32(int32_t value)
{
    return (value < 0) ? (uint32_t)(-(int64_t)value) : (uint32_t)value;
}

static uint32_t Crc32UpdateByte(uint32_t crc, uint8_t value)
{
    crc ^= (uint32_t)value;
    for (uint32_t bit = 0U; bit < 8U; bit++)
    {
        crc = ((crc & 1U) != 0U)
            ? ((crc >> 1U) ^ CONTROL_A5_CRC32_POLYNOMIAL)
            : (crc >> 1U);
    }
    return crc;
}

static uint32_t Crc32UpdateRawWord(uint32_t crc, uint16_t raw)
{
    /* Explicit little-endian wire contract for host reproducibility. */
    crc = Crc32UpdateByte(crc, (uint8_t)(raw & 0xFFU));
    return Crc32UpdateByte(crc, (uint8_t)(raw >> 8U));
}

int32_t ControlA5_WrapDeltaRaw(uint16_t previousRaw, uint16_t currentRaw)
{
    int32_t delta = (int32_t)currentRaw - (int32_t)previousRaw;
    if (delta > 32767)
    {
        delta -= 65536;
    }
    else if (delta < -32768)
    {
        delta += 65536;
    }
    return delta;
}

bool ControlA5_MeanRelRawQ16(int64_t sumRelRaw, uint32_t sampleCount,
                            int64_t *outMeanRelRawQ16)
{
    if (sampleCount == 0U || outMeanRelRawQ16 == NULL
            || sumRelRaw > INT64_MAX / 65536LL
            || sumRelRaw < INT64_MIN / 65536LL)
    {
        return false;
    }

    int64_t scaled = sumRelRaw * 65536LL;
    int64_t divisor = (int64_t)sampleCount;
    int64_t half = divisor / 2LL;
    if (scaled >= 0)
    {
        if (scaled > INT64_MAX - half)
        {
            return false;
        }
        *outMeanRelRawQ16 = (scaled + half) / divisor;
    }
    else
    {
        if (scaled == INT64_MIN)
        {
            return false;
        }
        int64_t magnitude = -scaled;
        if (magnitude > INT64_MAX - half)
        {
            return false;
        }
        *outMeanRelRawQ16 = -((magnitude + half) / divisor);
    }
    return true;
}

bool ControlA5_RawWordsCrc32(const uint16_t *rawWords, uint32_t count,
                            uint32_t *outCrc32)
{
    if (rawWords == NULL || count == 0U || outCrc32 == NULL)
    {
        return false;
    }

    uint32_t crc = CONTROL_A5_CRC32_INITIAL;
    for (uint32_t i = 0U; i < count; i++)
    {
        crc = Crc32UpdateRawWord(crc, rawWords[i]);
    }
    *outCrc32 = crc ^ CONTROL_A5_CRC32_XOR_OUT;
    return true;
}

uint32_t ControlA5_CycleDelta(uint32_t newerCycle, uint32_t olderCycle)
{
    return newerCycle - olderCycle;
}

bool ControlA5_ScheduleErrorCycles(uint32_t firstCycle, uint32_t actualCycle,
                                  uint32_t sampleIndex,
                                  uint32_t periodCycles,
                                  int32_t *outErrorCycles)
{
    uint64_t expectedOffset = (uint64_t)sampleIndex * (uint64_t)periodCycles;
    if (periodCycles == 0U || outErrorCycles == NULL
            || expectedOffset > UINT32_MAX)
    {
        return false;
    }

    uint32_t actualOffset = ControlA5_CycleDelta(actualCycle, firstCycle);
    int64_t error = (int64_t)actualOffset - (int64_t)expectedOffset;
    if (error < INT32_MIN || error > INT32_MAX)
    {
        return false;
    }
    *outErrorCycles = (int32_t)error;
    return true;
}

void ControlA5_StatsInit(ControlA5Stats_t *stats)
{
    if (stats != NULL)
    {
        memset(stats, 0, sizeof(*stats));
        stats->rawCrcState = CONTROL_A5_CRC32_INITIAL;
    }
}

bool ControlA5_StatsPush(ControlA5Stats_t *stats, uint16_t raw)
{
    if (stats == NULL || stats->count == UINT32_MAX)
    {
        return false;
    }

    if (!stats->initialized)
    {
        stats->initialized = true;
        stats->count = 1U;
        stats->firstRaw = raw;
        stats->lastRaw = raw;
        stats->firstUnwrapped = (int64_t)raw;
        stats->lastUnwrapped = (int64_t)raw;
        stats->minRelRaw = 0;
        stats->maxRelRaw = 0;
        stats->sumRelRaw = 0;
        stats->sumSquaresRelRaw = 0;
        stats->maxAbsStepRaw = 0U;
        stats->rawCrcState = Crc32UpdateRawWord(stats->rawCrcState, raw);
        return true;
    }

    int32_t delta = ControlA5_WrapDeltaRaw(stats->lastRaw, raw);
    int64_t nextUnwrapped = 0;
    int64_t relRaw = 0;
    int64_t nextSum = 0;
    int64_t square = 0;
    int64_t nextSumSquares = 0;
    if (!SafeAddI64(stats->lastUnwrapped, (int64_t)delta, &nextUnwrapped)
            || !SafeSubI64(nextUnwrapped, stats->firstUnwrapped, &relRaw)
            || !SafeAddI64(stats->sumRelRaw, relRaw, &nextSum)
            || !SafeSquareI64(relRaw, &square)
            || !SafeAddI64(stats->sumSquaresRelRaw, square, &nextSumSquares))
    {
        return false;
    }

    uint32_t absStep = AbsI32ToU32(delta);
    stats->count++;
    stats->lastRaw = raw;
    stats->lastUnwrapped = nextUnwrapped;
    if (relRaw < stats->minRelRaw)
    {
        stats->minRelRaw = relRaw;
    }
    if (relRaw > stats->maxRelRaw)
    {
        stats->maxRelRaw = relRaw;
    }
    stats->sumRelRaw = nextSum;
    stats->sumSquaresRelRaw = nextSumSquares;
    if (absStep > stats->maxAbsStepRaw)
    {
        stats->maxAbsStepRaw = absStep;
    }
    stats->rawCrcState = Crc32UpdateRawWord(stats->rawCrcState, raw);
    return true;
}

bool ControlA5_StatsFinalize(const ControlA5Stats_t *stats,
                            ControlA5Summary_t *out)
{
    if (stats == NULL || out == NULL || !stats->initialized
            || stats->count == 0U)
    {
        return false;
    }

    ControlA5Summary_t result;
    memset(&result, 0, sizeof(result));
    if (!SafeSubI64(stats->maxRelRaw, stats->minRelRaw,
            &result.peakToPeakRaw)
            || !SafeSubI64(stats->lastUnwrapped, stats->firstUnwrapped,
                &result.driftRaw)
            || !ControlA5_MeanRelRawQ16(stats->sumRelRaw, stats->count,
                &result.meanRelRawQ16))
    {
        return false;
    }

    result.acceptedSamples = stats->count;
    result.firstRaw = stats->firstRaw;
    result.lastRaw = stats->lastRaw;
    result.minRelRaw = stats->minRelRaw;
    result.maxRelRaw = stats->maxRelRaw;
    result.sumRelRaw = stats->sumRelRaw;
    result.sumSquaresRelRaw = stats->sumSquaresRelRaw;
    result.maxAbsStepRaw = stats->maxAbsStepRaw;
    result.rawCrc32 = stats->rawCrcState ^ CONTROL_A5_CRC32_XOR_OUT;
    *out = result;
    return true;
}

typedef struct
{
    const uint16_t *raw;
    uint32_t count;
    int64_t minRelRaw;
    int64_t maxRelRaw;
    int64_t peakToPeakRaw;
    int64_t driftRaw;
    int64_t meanRelRawQ16;
    uint32_t maxAbsStepRaw;
    uint32_t crc32;
} ControlA5GoldenVector_t;

static bool GoldenVectorPasses(const ControlA5GoldenVector_t *golden)
{
    if (golden == NULL || golden->raw == NULL || golden->count == 0U)
    {
        return false;
    }

    ControlA5Stats_t stats;
    ControlA5Summary_t summary;
    ControlA5_StatsInit(&stats);
    for (uint32_t i = 0U; i < golden->count; i++)
    {
        if (!ControlA5_StatsPush(&stats, golden->raw[i]))
        {
            return false;
        }
    }
    uint32_t independentCrc = 0U;
    return ControlA5_StatsFinalize(&stats, &summary)
        && ControlA5_RawWordsCrc32(golden->raw, golden->count,
            &independentCrc)
        && summary.acceptedSamples == golden->count
        && summary.minRelRaw == golden->minRelRaw
        && summary.maxRelRaw == golden->maxRelRaw
        && summary.peakToPeakRaw == golden->peakToPeakRaw
        && summary.driftRaw == golden->driftRaw
        && summary.meanRelRawQ16 == golden->meanRelRawQ16
        && summary.maxAbsStepRaw == golden->maxAbsStepRaw
        && summary.rawCrc32 == golden->crc32
        && independentCrc == golden->crc32;
}

bool ControlA5_MathSelfTest(void)
{
    static const uint16_t constant[] = {1000U, 1000U, 1000U, 1000U};
    static const uint16_t wrap[] = {65534U, 65535U, 0U, 1U};
    static const uint16_t noise[] = {1000U, 1001U, 999U, 1000U};
    static const uint16_t drift[] = {100U, 101U, 102U, 103U,
                                     104U, 105U, 106U, 107U};
    static const uint16_t impulse[] = {1000U, 1000U, 1016U, 1000U};
    static const ControlA5GoldenVector_t vectors[] = {
        {constant, 4U, 0, 0, 0, 0, 0, 0U, 0xA76BE7CFUL},
        {wrap, 4U, 0, 3, 3, 3, 98304, 1U, 0x2A4ECE20UL},
        {noise, 4U, -1, 1, 2, 0, 0, 2U, 0x3454243CUL},
        {drift, 8U, 0, 7, 7, 7, 229376, 1U, 0x0386FD67UL},
        {impulse, 4U, 0, 16, 16, 0, 262144, 16U, 0xF772B050UL},
    };

    for (uint32_t i = 0U; i < sizeof(vectors) / sizeof(vectors[0]); i++)
    {
        if (!GoldenVectorPasses(&vectors[i]))
        {
            return false;
        }
    }

    int64_t mean = 0;
    int32_t scheduleError = 0;
    uint32_t firstCycle = 0xFFFFFF00UL;
    uint32_t wrappedOnTime = firstCycle + 168000U;
    uint32_t wrappedLate = wrappedOnTime + 25U;
    if (ControlA5_MeanRelRawQ16(INT64_MAX / 65536LL + 1LL, 1U, &mean)
            || !ControlA5_ScheduleErrorCycles(firstCycle, wrappedOnTime,
                1U, 168000U, &scheduleError)
            || scheduleError != 0
            || !ControlA5_ScheduleErrorCycles(firstCycle, wrappedLate,
                1U, 168000U, &scheduleError)
            || scheduleError != 25
            || ControlA5_ScheduleErrorCycles(0U, 0U, UINT32_MAX,
                UINT32_MAX, &scheduleError))
    {
        return false;
    }

    /* Force a state that cannot occur in the bounded A5 window to prove an
     * overflow is rejected atomically instead of wrapping the accumulator. */
    ControlA5Stats_t overflow;
    ControlA5_StatsInit(&overflow);
    overflow.initialized = true;
    overflow.count = 1U;
    overflow.firstRaw = 0U;
    overflow.lastRaw = 0U;
    overflow.firstUnwrapped = 0;
    overflow.lastUnwrapped = INT64_MAX;
    overflow.rawCrcState = CONTROL_A5_CRC32_INITIAL;
    ControlA5Stats_t before = overflow;
    return !ControlA5_StatsPush(&overflow, 1U)
        && memcmp(&overflow, &before, sizeof(overflow)) == 0;
}
