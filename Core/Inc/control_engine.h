#ifndef __CONTROL_ENGINE_H
#define __CONTROL_ENGINE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* P1 safe stub. It establishes a separately linked control image before any
 * plant characterization or closed-loop output is allowed. */
bool ControlEngine_Init(void);
bool ControlEngine_RequestStart(void);
bool ControlEngine_IsBusy(void);

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_ENGINE_H */
