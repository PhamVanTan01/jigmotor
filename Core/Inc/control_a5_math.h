/* Pure data model and integer math for the A5 MA600 static RawAngle phase.
 *
 * This module deliberately has no HAL, RTOS, motor, SPI, or UART dependency.
 * A5.1 defines and tests the data contract only; the active A4B execution
 * path does not include or call it until the separately reviewed A5.2 phase.
 */

#ifndef __CONTROL_A5_MATH_H
#define __CONTROL_A5_MATH_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stdint.h>

#define CONTROL_A5_PROFILE_ID \
    "CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1"
#define CONTROL_A5_PARENT_PROFILE_ID \
    "CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1"

#define CONTROL_A5_SAMPLE_COUNT              2048U
#define CONTROL_A5_SAMPLE_RATE_HZ             1000U
#define CONTROL_A5_PERIOD_MS                 1U
#define CONTROL_A5_CAPTURE_MS                2048U
#define CONTROL_A5_READ_ATTEMPTS             1U
#define CONTROL_A5_ELECTRICAL_OFFSET_RAW     7971U
#define CONTROL_A5_COMMAND_PHASE_RAW         0U
#define CONTROL_A5_COMMAND_POWER_PPM         350000U
#define CONTROL_A5_MAX_UNWRAP_JUMP_RAW       1821
#define CONTROL_A5_MAX_SAMPLE_STEP_RAW       150
#define CONTROL_A5_MAX_STATIC_TRAVEL_RAW     210
#define CONTROL_A5_MAX_CAPTURE_MS            2300U

#if CONTROL_A5_SAMPLE_COUNT != 2048U \
        || CONTROL_A5_SAMPLE_RATE_HZ != 1000U \
        || CONTROL_A5_PERIOD_MS != 1U \
        || CONTROL_A5_CAPTURE_MS != 2048U
#error "A5 sample-count/cadence contract changed without a profile revision"
#endif
#if CONTROL_A5_ELECTRICAL_OFFSET_RAW != 7971U \
        || CONTROL_A5_COMMAND_PHASE_RAW != 0U \
        || CONTROL_A5_COMMAND_POWER_PPM != 350000U
#error "A5 frozen A4B hold state changed without a profile revision"
#endif
#if CONTROL_A5_READ_ATTEMPTS != 1U
#error "A5 raw evidence must not hide timing changes behind retries"
#endif

typedef enum
{
    CONTROL_A5_NOT_RUN = 0,
    CONTROL_A5_OK,
    CONTROL_A5_INVALID_ARGUMENT,
    CONTROL_A5_MATH_OVERFLOW,
    CONTROL_A5_BUFFER_FAULT,
    CONTROL_A5_CONFIG_FAULT,
    CONTROL_A5_PARENT_ALIGNMENT_FAULT,
    CONTROL_A5_HOLD_STATE_FAULT,
    CONTROL_A5_ACQUISITION_FAULT,
    CONTROL_A5_TIMING_FAULT,
    CONTROL_A5_SAMPLE_STEP_LIMIT,
    CONTROL_A5_STATIC_TRAVEL_LIMIT,
    CONTROL_A5_RECORD_OVERFLOW,
    CONTROL_A5_OPERATOR_ABORT,
    CONTROL_A5_SAFE_STOP_FAULT,
} ControlA5Result_t;

typedef enum
{
    CONTROL_A5_INVALID_NONE             = 0U,
    CONTROL_A5_INVALID_PROFILE          = (1UL << 0),
    CONTROL_A5_INVALID_CONFIG           = (1UL << 1),
    CONTROL_A5_INVALID_PARENT_ALIGNMENT = (1UL << 2),
    CONTROL_A5_INVALID_HOLD_STATE       = (1UL << 3),
    CONTROL_A5_INVALID_ACQUISITION      = (1UL << 4),
    CONTROL_A5_INVALID_TIMING           = (1UL << 5),
    CONTROL_A5_INVALID_STATIC_WINDOW    = (1UL << 6),
    CONTROL_A5_INVALID_RECORD           = (1UL << 7),
    CONTROL_A5_INVALID_SAFE_STOP        = (1UL << 8),
} ControlA5InvalidReason_t;

/* Index is implicit in the array position. The transport copies metadata
 * here after each checked read; DMA never targets this buffer directly. */
typedef struct
{
    uint32_t csAssertCycle;
    uint16_t angleRaw;
    uint16_t pwmCounterAtCs;
    uint16_t spiLatencyCycles;
    uint8_t  attempts;
    uint8_t  flags;
} ControlA5Sample_t;

_Static_assert(sizeof(ControlA5Sample_t) == 12U,
    "A5 sample record size changed -- re-audit the SRAM budget");
_Static_assert(sizeof(ControlA5Sample_t) * CONTROL_A5_SAMPLE_COUNT == 24576U,
    "A5 evidence buffer is no longer the approved 24 KiB allocation");

/* Online state. All position fields after firstUnwrapped are relative to the
 * first accepted sample, so raw wrap at 65535/0 is harmless. A failed push
 * leaves the state unchanged. */
typedef struct
{
    bool     initialized;
    uint32_t count;
    uint16_t firstRaw;
    uint16_t lastRaw;
    int64_t  firstUnwrapped;
    int64_t  lastUnwrapped;
    int64_t  minRelRaw;
    int64_t  maxRelRaw;
    int64_t  sumRelRaw;
    int64_t  sumSquaresRelRaw;
    uint32_t maxAbsStepRaw;
    uint32_t rawCrcState;
} ControlA5Stats_t;

typedef struct
{
    uint32_t acceptedSamples;
    uint16_t firstRaw;
    uint16_t lastRaw;
    int64_t  minRelRaw;
    int64_t  maxRelRaw;
    int64_t  peakToPeakRaw;
    int64_t  driftRaw;
    int64_t  meanRelRawQ16;
    int64_t  sumRelRaw;
    int64_t  sumSquaresRelRaw;
    uint32_t maxAbsStepRaw;
    uint32_t rawCrc32;
} ControlA5Summary_t;

typedef struct
{
    ControlA5Result_t result;
    uint32_t invalidReasonMask;
    bool measurementValid;
    ControlA5Summary_t rawAngle;
} ControlA5Report_t;

void ControlA5_StatsInit(ControlA5Stats_t *stats);
bool ControlA5_StatsPush(ControlA5Stats_t *stats, uint16_t raw);
bool ControlA5_StatsFinalize(const ControlA5Stats_t *stats,
                            ControlA5Summary_t *out);

/* Public pure helpers are intentionally small so host and firmware contract
 * tests can exercise the exact wrap, rounding, CRC, and DWT arithmetic. */
int32_t ControlA5_WrapDeltaRaw(uint16_t previousRaw, uint16_t currentRaw);
bool ControlA5_MeanRelRawQ16(int64_t sumRelRaw, uint32_t sampleCount,
                            int64_t *outMeanRelRawQ16);
bool ControlA5_RawWordsCrc32(const uint16_t *rawWords, uint32_t count,
                            uint32_t *outCrc32);
uint32_t ControlA5_CycleDelta(uint32_t newerCycle, uint32_t olderCycle);
bool ControlA5_ScheduleErrorCycles(uint32_t firstCycle, uint32_t actualCycle,
                                  uint32_t sampleIndex,
                                  uint32_t periodCycles,
                                  int32_t *outErrorCycles);

/* Deterministic, hardware-independent golden-vector test. A5.2 will wire this
 * into fail-closed initialization; A5.1 only compiles and host-contracts it. */
bool ControlA5_MathSelfTest(void);

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_A5_MATH_H */
