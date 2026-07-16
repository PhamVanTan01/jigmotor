#ifndef __CONTROL_ENGINE_H
#define __CONTROL_ENGINE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* C0 motor characterization engine. A button press runs one bounded 1-degree
 * plant-observation profile; a second press requests fail-safe abort. */
bool ControlEngine_Init(void);
bool ControlEngine_RequestStart(void);
bool ControlEngine_IsBusy(void);

#ifdef __cplusplus
}
#endif

#endif /* __CONTROL_ENGINE_H */
