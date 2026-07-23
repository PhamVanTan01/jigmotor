/* A5.2 platform integration for a static MA600 RawAngle capture.
 *
 * The complete deferred record schema is present as of A5.3. The active A4B
 * image keeps this integration disabled until A5.4 changes the app identity.
 * When enabled, this module owns only read-only configuration/state checks,
 * the dedicated acquisition context, timing evidence, and the 24 KiB sample
 * buffer. It never changes the motor command and never writes UART.
 */

#ifndef __CONTROL_A5_CAPTURE_H
#define __CONTROL_A5_CAPTURE_H

#ifdef __cplusplus
extern "C" {
#endif

#include "app_mode.h"

#if JIG_APP_MODE == JIG_APP_CONTROL

#include "control_a5_math.h"
#include "ma600.h"
#include "ma600_acquisition.h"
#include "motor.h"

#include <stdbool.h>
#include <stdint.h>

/* A5.4: the app profile identity now names A5, so the acknowledgement gate
 * below is satisfied and capture activates by default. Flipping either
 * define back to 0 independently is a compile error (see the check below),
 * matching the discipline used for every other profile lock in this file. */
#ifndef CONTROL_A5_CAPTURE_INTEGRATION_ENABLED
#define CONTROL_A5_CAPTURE_INTEGRATION_ENABLED 1U
#endif
#ifndef CONTROL_A5_PROFILE_ACTIVATION_ACK
#define CONTROL_A5_PROFILE_ACTIVATION_ACK 1U
#endif

#if CONTROL_A5_CAPTURE_INTEGRATION_ENABLED > 1U
#error "CONTROL_A5_CAPTURE_INTEGRATION_ENABLED must be 0 or 1"
#endif
#if CONTROL_A5_PROFILE_ACTIVATION_ACK > 1U \
        || CONTROL_A5_CAPTURE_INTEGRATION_ENABLED \
            != CONTROL_A5_PROFILE_ACTIVATION_ACK
#error "A5 capture cannot be enabled before the app profile activation is acknowledged"
#endif

#define CONTROL_A5_MIN_FREE_HEAP_AFTER_BUFFER  (64U * 1024U)
#define CONTROL_A5_PWM_PHASE_BIN_COUNT          32U

#if CONTROL_A5_PWM_PHASE_BIN_COUNT != 32U
#error "A5 phase-bin mask contract requires exactly 32 bins"
#endif

typedef bool (*ControlA5AbortRequestedFn_t)(void);

typedef struct
{
    ControlA5Report_t measurement;
    ControlA5Stats_t stats;

    MA600_Config_t config;
    MA600_ConfigGateResult_t configGateResult;
    MA600_AcquisitionContext_t acquisition;

    Motor_ControllerState_t preState;
    Motor_ControllerState_t postState;
    Motor_ControllerState_t safeStopState;

    uint32_t freeHeapBeforeAllocation;
    uint32_t freeHeapAfterAllocation;
    uint32_t minEverFreeHeapAfterAllocation;
    uint32_t evidenceCount;
    uint32_t slotsReached;
    uint32_t skippedSlots;
    uint32_t timingOverruns;
    uint32_t captureDurationMs;
    uint32_t systemClockHz;
    uint32_t periodCycles;
    uint32_t pwmPeriodCounts;
    uint32_t intervalMinCycles;
    uint32_t intervalMaxCycles;
    uint32_t maxAbsScheduleErrorCycles;
    uint32_t spiLatencyMinCycles;
    uint32_t spiLatencyMaxCycles;
    uint32_t spiLatencySumCycles;
    uint32_t spiLatencyMeanCycles;
    uint32_t pwmPhaseBinMask;

    bool resourcesValid;
    bool configReadValid;
    bool configValid;
    bool parentAlignmentValid;
    bool preStateValid;
    bool postStateValid;
    bool commandChanged;
    bool acquisitionValid;
    bool timingValid;
    bool staticWindowValid;
    bool recordIntegrityValid;
    bool safeStopValid;
} ControlA5CaptureReport_t;

/* Called once from ControlEngine_Init() when the integration flag is enabled.
 * The successful allocation is retained and reused for the image lifetime. */
bool ControlA5_CaptureResourcesInit(void);
bool ControlA5_CaptureResourcesReady(void);

/* Used only to roll back a partially failed ControlEngine_Init(). */
void ControlA5_CaptureResourcesReleaseForInitFailure(void);

/* Call while the motor output is disabled. This clears the retained evidence
 * buffer before alignment, never inside the timed A5 capture. */
void ControlA5_CaptureReportInit(ControlA5CaptureReport_t *report);

/* Exact locked Policy-A gate. This reads MA600 configuration only and never
 * clears status, changes registers, or writes NVM. */
bool ControlA5_ReadAndGateConfiguration(ControlA5CaptureReport_t *report);

void ControlA5_SetParentAlignmentValid(ControlA5CaptureReport_t *report,
                                       bool valid);
bool ControlA5_RecordPreCaptureState(ControlA5CaptureReport_t *report);
bool ControlA5_RecordPostCaptureState(ControlA5CaptureReport_t *report);

/* Captures into the retained buffer. It contains no motor-command or UART
 * operation. The caller must always perform the single safe-stop path after
 * this function returns, regardless of its result. */
ControlA5Result_t ControlA5_CaptureStaticWindow(
    ControlA5CaptureReport_t *report,
    ControlA5AbortRequestedFn_t abortRequested);

/* Call only after Motor_Disable() and a zero-power command have completed. */
bool ControlA5_RecordSafeStopState(ControlA5CaptureReport_t *report);
bool ControlA5_FinalizeAfterSafeStop(ControlA5CaptureReport_t *report);

const ControlA5Sample_t *ControlA5_GetEvidenceBuffer(void);

#endif /* JIG_APP_MODE == JIG_APP_CONTROL */

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_A5_CAPTURE_H */
