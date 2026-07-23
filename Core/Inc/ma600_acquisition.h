/* Canonical checked acquisition layer for the MA600A.
 *
 * The low-level ma600 driver performs exactly one SPI transaction. This
 * layer owns retry policy, per-consumer unwrap state, and acquisition
 * diagnostics. Each independent consumer must use its own context.
 */

#ifndef __MA600_ACQUISITION_H
#define __MA600_ACQUISITION_H

#ifdef __cplusplus
extern "C" {
#endif

#include "ma600.h"
#include <stdint.h>

typedef enum
{
    MA600_SAMPLE_FLAG_NONE            = 0,
    MA600_SAMPLE_FLAG_RETRIED         = (1u << 0),
    MA600_SAMPLE_FLAG_TRANSPORT_ERROR = (1u << 1),
    MA600_SAMPLE_FLAG_JUMP_REJECTED   = (1u << 2),
    MA600_SAMPLE_FLAG_INVALID         = (1u << 3),
} MA600_SampleFlags_t;

typedef struct
{
    uint16_t          raw;
    int64_t           unwrappedRaw;
    MA600_ReadMeta_t  meta;
    MA600_Result_t    result;
    uint8_t           attempts;
    uint8_t           flags;
} MA600_Sample_t;

typedef struct
{
    MA600_UnwrapContext_t unwrap;
    uint32_t readAttempts;
    uint32_t acceptedSamples;
    uint32_t retryCount;
    uint32_t transportErrorCount;
    uint32_t jumpRejectCount;
    uint32_t failedSampleCount;
} MA600_AcquisitionContext_t;

void MA600_AcquisitionInit(MA600_AcquisitionContext_t *ctx);

/* Performs at most maxAttempts checked transactions. Transport failures and
 * rejected jumps are retried; unwrap state changes only after an accepted
 * sample. maxJumpRaw is consumer-specific because a static settle detector
 * and a moving controller have different physically plausible step sizes. */
MA600_Result_t MA600_AcquireSample(MA600_AcquisitionContext_t *ctx,
                                    int32_t maxJumpRaw,
                                    uint8_t maxAttempts,
                                    MA600_Sample_t *out);

float MA600_UnwrappedRawToDegrees(int64_t unwrappedRaw);

/* ---- Phase-2 canonical point sampler (CANONICAL_Q16_V1) ---- */

/* Upper bound on samples the optional MAD (median absolute deviation)
 * outlier filter can process for one point. The driver layer has no
 * dependency on nonlinear_test.c's NL_SAMPLES_PER_POINT; this constant is
 * the documented point of contact between the two -- a caller's
 * config->requiredAcceptedSamples must not exceed this when it also
 * supplies a madRelRawSampleLog buffer. */
#define MA600_MAD_MAX_SAMPLES 64U

typedef enum
{
    MA600_POINT_TIMING_BACK_TO_BACK = 0,
    MA600_POINT_TIMING_SCHEDULED_START_TO_START,
} MA600_PointTimingMode_t;

typedef struct
{
    MA600_PointTimingMode_t timingMode;
    uint32_t sampleIntervalCycles;
    uint32_t requiredAcceptedSamples;
    uint32_t maxTransactions;
    uint32_t maxConsecutiveFailures;
    uint32_t maxElapsedCycles;
    int32_t  maxJumpRaw;
} MA600_PointSamplerConfig_t;

typedef struct
{
    bool     valid;
    bool     scheduleInitialized;
    bool     madFilteringEnabled;
    MA600_Result_t result;
    MA600_Result_t lastFailureResult;
    int64_t  pointAnchorUnwrapped;
    int64_t  sumRelRaw;
    int64_t  minRelRaw;
    int64_t  maxRelRaw;
    int64_t  meanRelRawQ16;
    int64_t  pointMeanRawQ16;
    int64_t  madFilteredMeanRawQ16;  /* valid only when madFilteringEnabled */
    int64_t  firstAcceptedUnwrapped;
    int64_t  lastAcceptedUnwrapped;
    uint32_t requiredAcceptedSamples;
    uint32_t acceptedSampleCount;
    uint32_t transactionCount;
    uint32_t spiFailureCount;
    uint32_t jumpRejectedCount;
    uint32_t metadataInvalidCount;
    uint32_t maxConsecutiveFailures;
    uint32_t skippedSlotCount;
    uint32_t timingOverrunCount;
    uint32_t maxAbsTimingErrorCycles;
    uint32_t firstAttemptCycle;
    uint32_t lastAttemptCycle;
    uint32_t elapsedCycles;
    uint32_t madCandidateCount;
    uint32_t madRejectedCount;
    uint32_t robustSampleCount;
} MA600_PointSample_t;

typedef MA600_Result_t (*MA600_PointReadFn)(void *user, uint16_t *raw,
                                             MA600_ReadMeta_t *meta);
typedef uint32_t (*MA600_PointNowFn)(void *user);
typedef void (*MA600_PointWaitUntilFn)(void *user, uint32_t targetCycle);

typedef struct
{
    MA600_PointReadFn read;
    MA600_PointNowFn now;
    MA600_PointWaitUntilFn waitUntil;
    void *user;
} MA600_PointSamplerIo_t;

bool MA600_DivRoundNearestAwayFromZero(int64_t numerator, int64_t denominator,
                                        int64_t *out);
bool MA600_ComputeCanonicalPointMeanQ16(int64_t pointAnchorUnwrapped,
                                        int64_t sumRelRaw,
                                        uint32_t acceptedSampleCount,
                                        int64_t *outMeanRelRawQ16,
                                        int64_t *outPointMeanRawQ16);
bool MA600_ComputeCanonicalErrorQ16(int64_t pointMeanRawQ16,
                                    int64_t point0MeanRawQ16,
                                    int32_t directionSign,
                                    uint32_t pointIndex,
                                    uint32_t stepRaw,
                                    int64_t *outErrorRawQ16);
bool MA600_ComputeCanonicalErrorAtTargetQ16(int64_t pointMeanRawQ16,
                                            int64_t point0MeanRawQ16,
                                            int64_t signedTargetRaw,
                                            int64_t *outErrorRawQ16);

/* madRelRawSampleLog: optional (NULL = disabled, default -- existing
 * behavior/timing/output byte-for-byte unchanged). When non-NULL, every
 * accepted sample's relRaw is recorded into this caller-owned buffer
 * (capacity madRelRawSampleLogCapacity, which must be >=
 * config->requiredAcceptedSamples and <= MA600_MAD_MAX_SAMPLES) as it is
 * accepted; after the sampling loop succeeds, a median-absolute-deviation
 * outlier filter runs over the buffer and an additional, independent
 * robust mean is computed into out->madFilteredMeanRawQ16 -- out->
 * pointMeanRawQ16 (the plain mean) is always computed the same way
 * regardless of this parameter. madRejectFloorRelRaw is a caller-supplied
 * minimum rejection threshold (in raw counts) guarding the degenerate
 * MAD~=0 case (a very tight sample cluster) from rejecting ordinary
 * quantization noise; ignored when madRelRawSampleLog is NULL. */
MA600_Result_t MA600_ReadAveragedPointWithIo(
    MA600_UnwrapContext_t *sweepCtx,
    int64_t pointAnchorUnwrapped,
    const MA600_PointSamplerConfig_t *config,
    const MA600_PointSamplerIo_t *io,
    int64_t *madRelRawSampleLog,
    uint32_t madRelRawSampleLogCapacity,
    int64_t madRejectFloorRelRaw,
    MA600_PointSample_t *out);

MA600_Result_t MA600_ReadAveragedPoint(
    MA600_UnwrapContext_t *sweepCtx,
    int64_t pointAnchorUnwrapped,
    const MA600_PointSamplerConfig_t *config,
    int64_t *madRelRawSampleLog,
    uint32_t madRelRawSampleLogCapacity,
    int64_t madRejectFloorRelRaw,
    MA600_PointSample_t *out);

/* Pure deterministic C self-test for Q16 rounding/math, DWT wrap, immediate
 * sample zero, first-transaction failure, slot consumption, missed-slot
 * skipping/no-catch-up, and atomic jump rejection. */
bool MA600_PointSamplerSelfTest(void);

/* Deterministic test hook. When ENABLE_MA600_FAULT_INJECTION=1, forces the
 * only transaction to time out and verifies that the sample is invalid,
 * zero accepted samples are recorded, and unwrap state is untouched. Returns
 * false in normal production builds where fault injection is disabled. */
bool MA600_AcquisitionRunFaultInjectionSelfTest(void);

#ifdef __cplusplus
}
#endif

#endif /* __MA600_ACQUISITION_H */
