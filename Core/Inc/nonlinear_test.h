/* End-of-shaft mounting nonlinear sweep engine. The dedicated test task owns
 * the motor and MA600A while busy; UI/health code only submits commands and
 * observes state. */

#ifndef __NONLINEAR_TEST_H
#define __NONLINEAR_TEST_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>

typedef enum
{
    NL_ENGINE_IDLE = 0,
    NL_ENGINE_PRECHECK,
    NL_ENGINE_HOME,
    NL_ENGINE_LOCK,
    NL_ENGINE_RAMP,
    NL_ENGINE_SETTLE,
    NL_ENGINE_ACQUIRE,
    NL_ENGINE_ANALYZE,
    NL_ENGINE_REPORT,
    NL_ENGINE_COOLDOWN,
    NL_ENGINE_SAFE_STOP,
} NonlinearEngineState_t;

/* Call after osKernelInitialize() and before osKernelStart(). Creates the
 * one-entry command queue and dedicated test task. */
bool NonlinearEngine_Init(void);

/* Non-blocking. Returns false when a test/batch is already queued, running,
 * or cooling down. */
bool NonlinearEngine_RequestStart(void);

bool NonlinearEngine_IsBusy(void);
NonlinearEngineState_t NonlinearEngine_GetState(void);

#ifdef __cplusplus
}
#endif

#endif /* __NONLINEAR_TEST_H */
