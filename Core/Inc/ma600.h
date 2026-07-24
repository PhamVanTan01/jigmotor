/* MA600A magnetic angle sensor driver (SPI1, mode 3). */

#ifndef __MA600_H
#define __MA600_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>

typedef struct
{
    bool nvmBusy;
    bool errCrc;
    bool errMem;
    bool errPar;
} MA600_Status_t;

void            MA600_Init(void);
const char     *MA600_AngleTransportName(void);
float           MA600_RawToDegrees(uint16_t raw);
bool            MA600_ReadStatus(MA600_Status_t *status);

/* Checked low-level I/O. Retry, unwrap, and jump policy live in
 * ma600_acquisition; no unchecked angle-read API is exposed. */
typedef enum
{
    MA600_RESULT_OK = 0,
    MA600_RESULT_INVALID_ARG,
    MA600_RESULT_SPI_TIMEOUT,
    MA600_RESULT_SPI_ERROR,
    MA600_RESULT_SAMPLE_JUMP,
    MA600_RESULT_CONFIG_ERROR,
    MA600_RESULT_TIMING_METADATA_INVALID,
    MA600_RESULT_ACQUISITION_BUDGET_EXCEEDED,
    MA600_RESULT_ACQUISITION_TIMEOUT,
    MA600_RESULT_MATH_OVERFLOW,
} MA600_Result_t;

/* Snapshot taken as close as possible to the /CS falling edge (inside
 * MA600_ReadRawChecked(), before HAL_SPI_TransmitReceive()) so that
 * pwmCounterAtCs reflects the actual TIM1 phase the sensor's output was
 * frozen at -- a few microseconds of layered call overhead is already a
 * large fraction of one PWM period (~12.8us at the current TIM1 config),
 * so this must not be captured by an outer caller after HAL overhead. */
typedef struct
{
    uint32_t csAssertCycle;
    uint32_t transferCompleteCycle;
    uint16_t pwmCounterAtCs;
    bool     metaValid;       /* true once the pre-/CS snapshot is captured, even if the
                                * following SPI transaction times out or is fault-injected. */
    bool     dmaUsed;
} MA600_ReadMeta_t;

/* Pure read: no retry, no state, no unwrap policy. Never returns 0 to mean
 * "error" -- callers must check the MA600_Result_t. meta may be NULL if
 * the caller doesn't need the CS-adjacent timing snapshot (e.g. PID
 * feedback). Retry policy belongs to the caller (canonical point sampler),
 * not here. */
MA600_Result_t  MA600_ReadRawChecked(uint16_t *raw, MA600_ReadMeta_t *meta);
MA600_Result_t  MA600_ReadRegChecked(uint8_t addr, uint8_t *value);

/* Sends the "Clear Error Flags" SPI command (single 16-bit frame, not an
 * NVM operation -- does not write NVM/config). */
bool             MA600_ClearErrorFlags(void);

/* Batch-start precheck: reads STATUS; if any error flag is set, sends
 * Clear Error Flags and re-reads. Returns true only if STATUS is clean
 * after this (possibly no-op) clear -- caller must refuse to start a batch
 * on false and require a power-cycle, per the acquisition-architecture
 * plan's STATUS policy (Part 1b). outStatus, if non-NULL, receives the
 * final (post-clear) status. */
bool             MA600_PrecheckAndClearStatus(MA600_Status_t *outStatus);

/* One context per independent tracker (PID feedback, settle detector,
 * sweep sampler must each use their own -- sharing one lets one consumer's
 * read cadence corrupt another's tracked position). maxJumpRaw is supplied
 * by the caller according to its own motion mode (static vs moving) --
 * there is deliberately no single system-wide jump threshold here. */
typedef struct
{
    bool     initialized;
    uint16_t lastRaw;
    int64_t  unwrappedRaw;

    uint32_t lastAcceptedCycle;  /* DWT cycle of the last accepted sample --
                                   * used by callers to compute a moving-mode
                                   * maxJumpRaw from elapsed time since last
                                   * accepted, not since the last attempt. */
    uint32_t acceptedCount;
    uint32_t rejectedCount;
} MA600_UnwrapContext_t;

void             MA600_UnwrapContextInit(MA600_UnwrapContext_t *ctx);

/* Updates the accepted tracking fields and *outUnwrapped only if the read is
 * accepted (the wrap-corrected step from ctx->lastRaw is within maxJumpRaw).
 * A rejected sample increments rejectedCount only; it never changes lastRaw,
 * unwrappedRaw, lastAcceptedCycle, or acceptedCount, so one bad reading cannot
 * poison the accumulator or drag later samples off course. */
MA600_Result_t   MA600_UnwrapUpdate(MA600_UnwrapContext_t *ctx, uint16_t raw,
                                     uint32_t acceptedCycle, int32_t maxJumpRaw,
                                     int64_t *outUnwrapped);

/* ---- Config snapshot (read-only; never writes NVM/registers) ---- */
typedef enum
{
    MA600_CAL_UNKNOWN = 0,
    MA600_CAL_ZERO_TABLE,
    MA600_CAL_ACTIVE_TABLE,
} MA600_CalState_t;

typedef struct
{
    bool             valid;         /* false if a read failed or snapshots did not stabilize */
    uint16_t         zero;          /* ZERO0(0x00) | ZERO1(0x01)<<8 */
    uint8_t          dir;           /* DIR (0x09) */
    uint8_t          filt;          /* FILT (0x0D) -- FW bits */
    uint8_t          status;        /* STATUS (0x1A) at snapshot time */
    uint8_t          prt;           /* PRT (0x1C) -- MTSP/PRT/PRTS/APRT/FTA/FTM */
    uint8_t          rmapId;        /* Register 0x1F: MA600 PRODUCTID or MA600A RMAPID */
    uint8_t          corr[32];      /* CORR0..CORR31, 0x20-0x3F */
    uint16_t         corrNonZeroCount;
    uint32_t         corrCrc32;     /* CRC-32/ISO-HDLC over corr[0..31], CORR0 first */
    MA600_CalState_t calState;
} MA600_Config_t;

/* Reads bounded repeated snapshots and accepts only two consecutive identical
 * snapshots. This rejects unstable SPI/config data while tolerating one
 * transient first response after sensor power-up. */
MA600_Result_t   MA600_ReadConfiguration(MA600_Config_t *out);

typedef struct
{
    uint16_t zero;
    uint8_t  dir;
    uint8_t  filt;
    uint8_t  status;
    uint8_t  prt;
    uint8_t  rmapId;
    uint32_t corrCrc32;
} MA600_ExpectedConfig_t;

/* Phase-1 Policy-A result. The safety gate checks transport/status/zero-table
 * invariants. The locked gate additionally requires a known UID-selected
 * expected profile and exact values for every audited field. */
typedef enum
{
    MA600_CONFIG_GATE_OK = 0,
    MA600_CONFIG_GATE_READ_INVALID,
    MA600_CONFIG_GATE_STATUS_NOT_CLEAN,
    MA600_CONFIG_GATE_CORRECTION_TABLE_NOT_ZERO,
    MA600_CONFIG_GATE_EXPECTED_PROFILE_MISSING,
    MA600_CONFIG_GATE_ZERO_MISMATCH,
    MA600_CONFIG_GATE_DIR_MISMATCH,
    MA600_CONFIG_GATE_FILT_MISMATCH,
    MA600_CONFIG_GATE_STATUS_MISMATCH,
    MA600_CONFIG_GATE_PRT_MISMATCH,
    MA600_CONFIG_GATE_RMAPID_MISMATCH,
    MA600_CONFIG_GATE_CORRECTION_CRC_MISMATCH,
} MA600_ConfigGateResult_t;

MA600_ConfigGateResult_t MA600_ValidateConfigurationSafetyGate(const MA600_Config_t *config);
MA600_ConfigGateResult_t MA600_ValidateConfigurationLockedGate(
    const MA600_Config_t *config, const MA600_ExpectedConfig_t *expected);
const char              *MA600_ConfigGateResultName(MA600_ConfigGateResult_t result);
bool                     MA600_ConfigurationGateSelfTest(void);

/* Software fault injection (test builds only, ENABLE_MA600_FAULT_INJECTION=1
 * defined as a preprocessor macro): forces the Nth MA600_ReadRawChecked()
 * transaction (counting from 1, reset by ArmNextTransaction) to return
 * forcedResult instead of doing the real SPI transaction, so the
 * checked-read/retry/status code path can be exercised without depending
 * on real bus electrical conditions (a floating/disconnected CIPO does not
 * reliably produce HAL_TIMEOUT -- clock still runs on the master side). A
 * no-op when the build flag is 0 (the default). */
void             MA600_FaultInjection_ArmNextTransaction(uint32_t atTransactionNumber,
                                                          MA600_Result_t forcedResult);
void             MA600_FaultInjection_Reset(void);

/* DWT cycle-counter utilities (enabled once; used for sub-microsecond
 * scheduling/timestamping instead of HAL_GetTick(), whose 1ms resolution
 * is too coarse for ~40us sample spacing). */
void             MA600_DwtInit(void);
uint32_t         MA600_DwtCyclesToUs(uint32_t cycles);
uint32_t         MA600_DwtUsToCycles(uint32_t us);

#ifdef __cplusplus
}
#endif

#endif /* __MA600_H */
