#ifndef __APP_ENGINE_H
#define __APP_ENGINE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Mode-neutral application boundary used by main/UI. Implementations are
 * compile-time selected; there is no runtime transition between modes. */
bool AppEngine_Init(void);
bool AppEngine_RequestStart(void);
bool AppEngine_IsBusy(void);
const char *AppEngine_ModeId(void);
const char *AppEngine_ProfileId(void);
const char *AppEngine_SourceId(void);
unsigned long AppEngine_ProfileFingerprint(void);

#ifdef __cplusplus
}
#endif

#endif /* __APP_ENGINE_H */
