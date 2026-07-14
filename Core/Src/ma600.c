/* MA600A magnetic angle sensor driver (SPI1, mode 3). */

#include "ma600.h"
#include "main.h"
#include <string.h>

extern SPI_HandleTypeDef hspi1;
extern TIM_HandleTypeDef htim1;

#ifndef ENABLE_MA600_FAULT_INJECTION
#define ENABLE_MA600_FAULT_INJECTION 0
#endif

#define MA600_REG_ZERO0        0x00
#define MA600_REG_ZERO1        0x01
#define MA600_REG_DIR          0x09
#define MA600_REG_FILT         0x0D
#define MA600_REG_STATUS       0x1A
#define MA600_REG_PRT          0x1C
#define MA600_REG_RMAPID       0x1F
#define MA600_CORR_BASE        0x20
#define MA600_CORR_COUNT       32
#define MA600_CMD_READ_REG     0xD2
#define MA600_CMD_CLEAR_ERROR_HI 0xD7
#define MA600_CMD_CLEAR_ERROR_LO 0x00

/* SPI mode 3 requires /CS idle High between transactions. MX_GPIO_Init()
 * leaves SPI1_CS_Pin driven low (asserted) at boot because the .ioc has no
 * explicit idle level for it, so MA600_Init() must deselect explicitly
 * rather than assume the post-init pin state is already correct. */
static void MA600_Select(void)
{
    HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_RESET);
}

static void MA600_Deselect(void)
{
    HAL_GPIO_WritePin(SPI1_CS_GPIO_Port, SPI1_CS_Pin, GPIO_PIN_SET);
}

void MA600_Init(void)
{
    MA600_Deselect();
    MA600_DwtInit();
}

float MA600_RawToDegrees(uint16_t raw)
{
    return (float)raw * 360.0f / 65536.0f;
}

bool MA600_ReadStatus(MA600_Status_t *status)
{
    if (status == NULL)
    {
        return false;
    }

    uint8_t reg;
    if (MA600_ReadRegChecked(MA600_REG_STATUS, &reg) != MA600_RESULT_OK)
    {
        return false;
    }

    status->nvmBusy = (reg & 0x80) != 0;
    status->errCrc  = (reg & 0x04) != 0;
    status->errMem  = (reg & 0x02) != 0;
    status->errPar  = (reg & 0x01) != 0;

    return true;
}

/* ==================== Checked I/O ==================== */

#if ENABLE_MA600_FAULT_INJECTION
static uint32_t        faultInjectionCounter = 0;
static uint32_t        faultInjectionAtTransaction = 0;  /* 0 = disarmed */
static MA600_Result_t  faultInjectionResult = MA600_RESULT_SPI_TIMEOUT;
#endif

void MA600_FaultInjection_ArmNextTransaction(uint32_t atTransactionNumber, MA600_Result_t forcedResult)
{
#if ENABLE_MA600_FAULT_INJECTION
    faultInjectionCounter = 0;
    faultInjectionAtTransaction = atTransactionNumber;
    faultInjectionResult = forcedResult;
#else
    (void)atTransactionNumber;
    (void)forcedResult;
#endif
}

void MA600_FaultInjection_Reset(void)
{
#if ENABLE_MA600_FAULT_INJECTION
    faultInjectionCounter = 0;
    faultInjectionAtTransaction = 0;
#endif
}

MA600_Result_t MA600_ReadRawChecked(uint16_t *raw, MA600_ReadMeta_t *meta)
{
    if (meta != NULL)
    {
        memset(meta, 0, sizeof(*meta));
    }
    if (raw == NULL)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    uint8_t tx[2] = {0x00, 0x00};
    uint8_t rx[2] = {0x00, 0x00};

    /* Snapshot taken immediately before /CS falls -- no printf, RTOS call,
     * or other logic between these two lines and MA600_Select(), so the
     * PWM phase recorded actually reflects when the sensor's output was
     * frozen (see MA600_ReadMeta_t's header comment). */
    uint32_t csAssertCycle = DWT->CYCCNT;
    uint16_t pwmCounterAtCs = (uint16_t)__HAL_TIM_GET_COUNTER(&htim1);
    if (meta != NULL)
    {
        meta->csAssertCycle = csAssertCycle;
        meta->pwmCounterAtCs = pwmCounterAtCs;
        meta->metaValid = true;
    }

#if ENABLE_MA600_FAULT_INJECTION
    faultInjectionCounter++;
    if (faultInjectionAtTransaction != 0 && faultInjectionCounter == faultInjectionAtTransaction)
    {
        return faultInjectionResult;
    }
#endif

    MA600_Select();
    HAL_StatusTypeDef st = HAL_SPI_TransmitReceive(&hspi1, tx, rx, sizeof(tx), 10);
    MA600_Deselect();

    if (st == HAL_TIMEOUT)
    {
        return MA600_RESULT_SPI_TIMEOUT;
    }
    if (st != HAL_OK)
    {
        return MA600_RESULT_SPI_ERROR;
    }

    *raw = ((uint16_t)rx[0] << 8) | (uint16_t)rx[1];
    return MA600_RESULT_OK;
}

MA600_Result_t MA600_ReadRegChecked(uint8_t addr, uint8_t *value)
{
    if (value == NULL)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    uint8_t tx[2];
    uint8_t rx[2] = {0x00, 0x00};

    MA600_Select();
    tx[0] = MA600_CMD_READ_REG;
    tx[1] = addr;
    HAL_StatusTypeDef st1 = HAL_SPI_Transmit(&hspi1, tx, sizeof(tx), 10);
    MA600_Deselect();
    if (st1 != HAL_OK)
    {
        return (st1 == HAL_TIMEOUT) ? MA600_RESULT_SPI_TIMEOUT : MA600_RESULT_SPI_ERROR;
    }

    MA600_Select();
    HAL_StatusTypeDef st2 = HAL_SPI_Receive(&hspi1, rx, sizeof(rx), 10);
    MA600_Deselect();
    if (st2 != HAL_OK)
    {
        return (st2 == HAL_TIMEOUT) ? MA600_RESULT_SPI_TIMEOUT : MA600_RESULT_SPI_ERROR;
    }

    *value = rx[1];
    return MA600_RESULT_OK;
}

bool MA600_ClearErrorFlags(void)
{
    uint8_t tx[2] = { MA600_CMD_CLEAR_ERROR_HI, MA600_CMD_CLEAR_ERROR_LO };
    uint8_t rx[2] = { 0x00, 0x00 };

    /* Single 16-bit command frame (datasheet: "A clear error flags
     * operation consists of one 16-bit frame") -- not an NVM operation, so
     * sending this during a test batch does not violate the "no NVM writes
     * during test" constraint. */
    MA600_Select();
    HAL_StatusTypeDef st = HAL_SPI_TransmitReceive(&hspi1, tx, rx, sizeof(tx), 10);
    MA600_Deselect();

    return st == HAL_OK;
}

bool MA600_PrecheckAndClearStatus(MA600_Status_t *outStatus)
{
    MA600_Status_t status = {0};

    if (!MA600_ReadStatus(&status))
    {
        if (outStatus != NULL) { *outStatus = status; }
        return false;
    }

    if (status.errCrc || status.errMem || status.errPar)
    {
        MA600_ClearErrorFlags();
        if (!MA600_ReadStatus(&status))
        {
            if (outStatus != NULL) { *outStatus = status; }
            return false;
        }
    }

    if (outStatus != NULL) { *outStatus = status; }
    return !(status.nvmBusy || status.errCrc || status.errMem || status.errPar);
}

void MA600_UnwrapContextInit(MA600_UnwrapContext_t *ctx)
{
    if (ctx == NULL)
    {
        return;
    }
    ctx->initialized = false;
    ctx->lastRaw = 0;
    ctx->unwrappedRaw = 0;
    ctx->lastAcceptedCycle = 0;
    ctx->acceptedCount = 0;
    ctx->rejectedCount = 0;
}

MA600_Result_t MA600_UnwrapUpdate(MA600_UnwrapContext_t *ctx, uint16_t raw,
                                   uint32_t acceptedCycle, int32_t maxJumpRaw,
                                   int64_t *outUnwrapped)
{
    if (ctx == NULL || outUnwrapped == NULL || maxJumpRaw < 0)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    if (!ctx->initialized)
    {
        /* First sample of this context defines the anchor -- nothing to
         * validate a jump against yet. */
        ctx->initialized = true;
        ctx->lastRaw = raw;
        ctx->unwrappedRaw = (int64_t)raw;
        ctx->lastAcceptedCycle = acceptedCycle;
        ctx->acceptedCount++;
        *outUnwrapped = ctx->unwrappedRaw;
        return MA600_RESULT_OK;
    }

    int32_t delta = (int32_t)raw - (int32_t)ctx->lastRaw;
    if (delta > 32768)
    {
        delta -= 65536;
    }
    else if (delta < -32768)
    {
        delta += 65536;
    }

    int32_t absoluteDelta = (delta < 0) ? -delta : delta;
    if (absoluteDelta > maxJumpRaw)
    {
        /* Reject: only diagnostic reject accounting changes. The accepted
         * tracking state and timestamp remain atomic and untouched. */
        ctx->rejectedCount++;
        return MA600_RESULT_SAMPLE_JUMP;
    }

    int64_t candidateUnwrapped = ctx->unwrappedRaw + (int64_t)delta;

    /* Commit every accepted-state field together, using this transaction's
     * CS-adjacent timestamp. There are no fallible operations after this
     * point and before the complete commit. */
    ctx->lastRaw = raw;
    ctx->unwrappedRaw = candidateUnwrapped;
    ctx->lastAcceptedCycle = acceptedCycle;
    ctx->acceptedCount++;
    *outUnwrapped = candidateUnwrapped;
    return MA600_RESULT_OK;
}

/* CRC-32/ISO-HDLC: poly 0x04C11DB7 (reflected 0xEDB88320), init 0xFFFFFFFF,
 * refin/refout=true, xorout 0xFFFFFFFF -- the common "CRC-32" used by
 * zip/Ethernet. Fixed here so CorrCRC32 is comparable across runs/builds. */
static uint32_t Crc32IsoHdlc(const uint8_t *data, uint32_t len)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (uint32_t i = 0; i < len; i++)
    {
        crc ^= data[i];
        for (int b = 0; b < 8; b++)
        {
            crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
        }
    }
    return crc ^ 0xFFFFFFFFu;
}

MA600_Result_t MA600_ReadConfiguration(MA600_Config_t *out)
{
    if (out == NULL)
    {
        return MA600_RESULT_INVALID_ARG;
    }

    memset(out, 0, sizeof(*out));

    uint8_t zero0 = 0, zero1 = 0, status = 0;
    bool ok = true;

    ok = ok && (MA600_ReadRegChecked(MA600_REG_ZERO0, &zero0) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_ZERO1, &zero1) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_DIR, &out->dir) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_FILT, &out->filt) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_STATUS, &status) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_PRT, &out->prt) == MA600_RESULT_OK);
    ok = ok && (MA600_ReadRegChecked(MA600_REG_RMAPID, &out->rmapId) == MA600_RESULT_OK);

    out->zero = (uint16_t)zero0 | ((uint16_t)zero1 << 8);
    out->status = status;

    out->corrNonZeroCount = 0;
    for (int i = 0; i < MA600_CORR_COUNT; i++)
    {
        uint8_t v = 0;
        if (MA600_ReadRegChecked((uint8_t)(MA600_CORR_BASE + i), &v) != MA600_RESULT_OK)
        {
            ok = false;
            v = 0;
        }
        out->corr[i] = v;
        if (v != 0)
        {
            out->corrNonZeroCount++;
        }
    }
    out->corrCrc32 = Crc32IsoHdlc(out->corr, MA600_CORR_COUNT);

    out->valid = ok;
    if (!ok)
    {
        out->calState = MA600_CAL_UNKNOWN;
        return MA600_RESULT_CONFIG_ERROR;
    }

    /* Policy A (this project): the on-chip 32-point LUT is not relied on --
     * see docs/end-of-shaft-mounting-test-plan.md / the sibling project's
     * MA600_LUT_ENABLED=0 -- so the expected state is always ZERO_TABLE. */
    out->calState = (out->corrNonZeroCount == 0) ? MA600_CAL_ZERO_TABLE : MA600_CAL_ACTIVE_TABLE;
    return MA600_RESULT_OK;
}

MA600_ConfigGateResult_t MA600_ValidateConfigurationSafetyGate(const MA600_Config_t *config)
{
    if (config == NULL || !config->valid || config->calState == MA600_CAL_UNKNOWN)
    {
        return MA600_CONFIG_GATE_READ_INVALID;
    }
    if ((config->status & (uint8_t)(0x80U | 0x04U | 0x02U | 0x01U)) != 0U)
    {
        return MA600_CONFIG_GATE_STATUS_NOT_CLEAN;
    }
    if (config->calState != MA600_CAL_ZERO_TABLE || config->corrNonZeroCount != 0U)
    {
        return MA600_CONFIG_GATE_CORRECTION_TABLE_NOT_ZERO;
    }
    return MA600_CONFIG_GATE_OK;
}

MA600_ConfigGateResult_t MA600_ValidateConfigurationLockedGate(
    const MA600_Config_t *config, const MA600_ExpectedConfig_t *expected)
{
    MA600_ConfigGateResult_t safetyResult = MA600_ValidateConfigurationSafetyGate(config);
    if (safetyResult != MA600_CONFIG_GATE_OK)
    {
        return safetyResult;
    }
    if (expected == NULL)
    {
        return MA600_CONFIG_GATE_EXPECTED_PROFILE_MISSING;
    }
    if (config->zero != expected->zero)
    {
        return MA600_CONFIG_GATE_ZERO_MISMATCH;
    }
    if (config->dir != expected->dir)
    {
        return MA600_CONFIG_GATE_DIR_MISMATCH;
    }
    if (config->filt != expected->filt)
    {
        return MA600_CONFIG_GATE_FILT_MISMATCH;
    }
    if (config->status != expected->status)
    {
        return MA600_CONFIG_GATE_STATUS_MISMATCH;
    }
    if (config->prt != expected->prt)
    {
        return MA600_CONFIG_GATE_PRT_MISMATCH;
    }
    if (config->rmapId != expected->rmapId)
    {
        return MA600_CONFIG_GATE_RMAPID_MISMATCH;
    }
    if (config->corrCrc32 != expected->corrCrc32)
    {
        return MA600_CONFIG_GATE_CORRECTION_CRC_MISMATCH;
    }
    return MA600_CONFIG_GATE_OK;
}

const char *MA600_ConfigGateResultName(MA600_ConfigGateResult_t result)
{
    switch (result)
    {
        case MA600_CONFIG_GATE_OK: return "NONE";
        case MA600_CONFIG_GATE_READ_INVALID: return "CONFIG_READ_FAILED";
        case MA600_CONFIG_GATE_STATUS_NOT_CLEAN: return "STATUS_NOT_CLEAN";
        case MA600_CONFIG_GATE_CORRECTION_TABLE_NOT_ZERO:
            return "UNEXPECTED_NONZERO_CORRECTION_TABLE";
        case MA600_CONFIG_GATE_EXPECTED_PROFILE_MISSING:
            return "EXPECTED_CONFIG_PROFILE_MISSING";
        case MA600_CONFIG_GATE_ZERO_MISMATCH: return "ZERO_MISMATCH";
        case MA600_CONFIG_GATE_DIR_MISMATCH: return "DIR_MISMATCH";
        case MA600_CONFIG_GATE_FILT_MISMATCH: return "FILT_MISMATCH";
        case MA600_CONFIG_GATE_STATUS_MISMATCH: return "STATUS_MISMATCH";
        case MA600_CONFIG_GATE_PRT_MISMATCH: return "PRT_MISMATCH";
        case MA600_CONFIG_GATE_RMAPID_MISMATCH: return "RMAPID_MISMATCH";
        case MA600_CONFIG_GATE_CORRECTION_CRC_MISMATCH:
            return "CORRECTION_CRC_MISMATCH";
        default: return "UNKNOWN_CONFIG_GATE_RESULT";
    }
}

bool MA600_ConfigurationGateSelfTest(void)
{
    static const uint32_t zeroTableCrc32 = 0x190A55ADU;
    MA600_Config_t config;
    memset(&config, 0, sizeof(config));
    config.valid = true;
    config.calState = MA600_CAL_ZERO_TABLE;
    config.filt = 0x05U;
    config.corrCrc32 = zeroTableCrc32;
    bool cleanAccepted = (MA600_ValidateConfigurationSafetyGate(&config) == MA600_CONFIG_GATE_OK);

    config.status = 0x80U;
    bool statusRejected = (MA600_ValidateConfigurationSafetyGate(&config)
        == MA600_CONFIG_GATE_STATUS_NOT_CLEAN);

    config.status = 0U;
    config.corrNonZeroCount = 1U;
    config.calState = MA600_CAL_ACTIVE_TABLE;
    bool correctionRejected = (MA600_ValidateConfigurationSafetyGate(&config)
        == MA600_CONFIG_GATE_CORRECTION_TABLE_NOT_ZERO);

    config.corrNonZeroCount = 0U;
    config.calState = MA600_CAL_ZERO_TABLE;
    config.valid = false;
    bool invalidRejected = (MA600_ValidateConfigurationSafetyGate(&config)
        == MA600_CONFIG_GATE_READ_INVALID);

    config.valid = true;
    MA600_ExpectedConfig_t expected = {
        .zero = 0x0000U,
        .dir = 0x00U,
        .filt = 0x05U,
        .status = 0x00U,
        .prt = 0x00U,
        .rmapId = 0x00U,
        .corrCrc32 = zeroTableCrc32,
    };

    bool lockedAccepted = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_OK);
    bool missingProfileRejected = (MA600_ValidateConfigurationLockedGate(&config, NULL)
        == MA600_CONFIG_GATE_EXPECTED_PROFILE_MISSING);

    config.zero = 1U;
    bool zeroRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_ZERO_MISMATCH);
    config.zero = expected.zero;
    config.dir = 1U;
    bool dirRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_DIR_MISMATCH);
    config.dir = expected.dir;
    config.filt = 4U;
    bool filtRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_FILT_MISMATCH);
    config.filt = expected.filt;
    config.status = 0x08U;
    bool statusExactRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_STATUS_MISMATCH);
    config.status = expected.status;
    config.prt = 1U;
    bool prtRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_PRT_MISMATCH);
    config.prt = expected.prt;
    config.rmapId = 1U;
    bool rmapIdRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_RMAPID_MISMATCH);
    config.rmapId = expected.rmapId;
    config.corrCrc32 ^= 1U;
    bool crcRejected = (MA600_ValidateConfigurationLockedGate(&config, &expected)
        == MA600_CONFIG_GATE_CORRECTION_CRC_MISMATCH);

    return cleanAccepted && statusRejected && correctionRejected && invalidRejected
        && lockedAccepted && missingProfileRejected && zeroRejected && dirRejected
        && filtRejected && statusExactRejected && prtRejected && rmapIdRejected
        && crcRejected;
}

void MA600_DwtInit(void)
{
    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CYCCNT = 0;
    DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

uint32_t MA600_DwtCyclesToUs(uint32_t cycles)
{
    return cycles / (SystemCoreClock / 1000000UL);
}

uint32_t MA600_DwtUsToCycles(uint32_t us)
{
    return us * (SystemCoreClock / 1000000UL);
}
