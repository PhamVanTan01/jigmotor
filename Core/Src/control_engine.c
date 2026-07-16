#include "control_engine.h"
#include "motor.h"

static bool controlEngineInitialized;

bool ControlEngine_Init(void)
{
    /* P1 contains no motion path by design. A successful build/link test must
     * precede plant characterization, so every entry point keeps the physical
     * output disabled. */
    Motor_Disable();
    controlEngineInitialized = true;
    return true;
}

bool ControlEngine_RequestStart(void)
{
    (void)controlEngineInitialized;
    Motor_Disable();
    return false;
}

bool ControlEngine_IsBusy(void)
{
    return false;
}
