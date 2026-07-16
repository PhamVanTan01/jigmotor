#include "app_engine.h"
#include "app_mode.h"

#if JIG_APP_MODE == JIG_APP_CONTROL
#include "control_engine.h"
#else
#include "nonlinear_test.h"
#endif

bool AppEngine_Init(void)
{
#if JIG_APP_MODE == JIG_APP_CONTROL
    return ControlEngine_Init();
#else
    return NonlinearEngine_Init();
#endif
}

bool AppEngine_RequestStart(void)
{
#if JIG_APP_MODE == JIG_APP_CONTROL
    return ControlEngine_RequestStart();
#else
    return NonlinearEngine_RequestStart();
#endif
}

bool AppEngine_IsBusy(void)
{
#if JIG_APP_MODE == JIG_APP_CONTROL
    return ControlEngine_IsBusy();
#else
    return NonlinearEngine_IsBusy();
#endif
}

const char *AppEngine_ModeId(void)
{
    return JIG_APP_MODE_ID;
}

const char *AppEngine_ProfileId(void)
{
    return JIG_APP_PROFILE_ID;
}

const char *AppEngine_SourceId(void)
{
    return JIG_BUILD_SOURCE_ID;
}

unsigned long AppEngine_ProfileFingerprint(void)
{
    /* FNV-1a over the two stable policy identifiers. It is an inexpensive
     * mix-detection fingerprint, not a cryptographic source hash. */
    unsigned long hash = 2166136261UL;
    const char *fields[] = { JIG_APP_MODE_ID, JIG_APP_PROFILE_ID };
    for (unsigned int field = 0U; field < 2U; field++)
    {
        const unsigned char *p = (const unsigned char *)fields[field];
        while (*p != 0U)
        {
            hash ^= (unsigned long)*p++;
            hash *= 16777619UL;
        }
        hash ^= 0xFFUL;
        hash *= 16777619UL;
    }
    return hash;
}
