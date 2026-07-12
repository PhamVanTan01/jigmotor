/* MA600A magnetic angle sensor driver (SPI1, mode 3). */

#include "ma600.h"
#include "main.h"

extern SPI_HandleTypeDef hspi1;

#define MA600_REG_STATUS       0x1A
#define MA600_CMD_READ_REG     0xD2

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
}

uint16_t MA600_ReadRawAngle(void)
{
    uint8_t tx[2] = {0x00, 0x00};
    uint8_t rx[2] = {0x00, 0x00};

    MA600_Select();
    HAL_SPI_TransmitReceive(&hspi1, tx, rx, sizeof(tx), 10);
    MA600_Deselect();

    return ((uint16_t)rx[0] << 8) | (uint16_t)rx[1];
}

float MA600_RawToDegrees(uint16_t raw)
{
    return (float)raw * 360.0f / 65536.0f;
}

float MA600_ReadAngleDegrees(void)
{
    return MA600_RawToDegrees(MA600_ReadRawAngle());
}

uint8_t MA600_ReadReg(uint8_t addr)
{
    uint8_t tx[2];
    uint8_t rx[2] = {0x00, 0x00};

    /* Read Register is a 2-frame operation: frame 1 sends the command +
     * address, frame 2 clocks out the reply (the MA600A returns the
     * previous frame's result, one frame late). */
    MA600_Select();
    tx[0] = MA600_CMD_READ_REG;
    tx[1] = addr;
    HAL_SPI_Transmit(&hspi1, tx, sizeof(tx), 10);
    MA600_Deselect();

    MA600_Select();
    HAL_SPI_Receive(&hspi1, rx, sizeof(rx), 10);
    MA600_Deselect();

    return rx[1];
}

bool MA600_ReadStatus(MA600_Status_t *status)
{
    if (status == NULL)
    {
        return false;
    }

    uint8_t reg = MA600_ReadReg(MA600_REG_STATUS);

    status->nvmBusy = (reg & 0x80) != 0;
    status->errCrc  = (reg & 0x04) != 0;
    status->errMem  = (reg & 0x02) != 0;
    status->errPar  = (reg & 0x01) != 0;

    return true;
}

static int32_t multiTurnCount = 0;
static uint16_t multiTurnLastRaw = 0;

void MA600_UpdateMultiTurn(void)
{
    uint16_t raw = MA600_ReadRawAngle();
    int32_t delta = (int32_t)raw - (int32_t)multiTurnLastRaw;

    /* The raw reading wraps at 0/65535 every revolution. A same-direction
     * step near that wrap point looks like a huge opposite-direction jump
     * unless corrected: e.g. 65530 -> 5 is a step of +11, not -65525. */
    if (delta > 32768)
    {
        delta -= 65536;
    }
    else if (delta < -32768)
    {
        delta += 65536;
    }

    multiTurnCount += delta;
    multiTurnLastRaw = raw;
}

float MA600_ReadMultiTurnDegrees(void)
{
    return (float)multiTurnCount * 360.0f / 65536.0f;
}

int32_t MA600_ReadMultiTurnRaw(void)
{
    return multiTurnCount;
}

void MA600_ResetMultiTurn(void)
{
    uint16_t raw = MA600_ReadRawAngle();
    multiTurnLastRaw = raw;
    multiTurnCount = (int32_t)raw;
}
