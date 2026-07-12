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
uint16_t        MA600_ReadRawAngle(void);
float           MA600_RawToDegrees(uint16_t raw);
float           MA600_ReadAngleDegrees(void);
uint8_t         MA600_ReadReg(uint8_t addr);
bool            MA600_ReadStatus(MA600_Status_t *status);

/* Multi-turn (unwrapped) angle tracking, needed by the motor position PID
 * and the nonlinear sweep (both need a monotonic angle that doesn't wrap
 * every revolution, unlike MA600_ReadAngleDegrees()). */
void            MA600_UpdateMultiTurn(void);
float           MA600_ReadMultiTurnDegrees(void);
int32_t         MA600_ReadMultiTurnRaw(void);
void            MA600_ResetMultiTurn(void);

#ifdef __cplusplus
}
#endif

#endif /* __MA600_H */
