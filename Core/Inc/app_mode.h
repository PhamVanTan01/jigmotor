#ifndef __APP_MODE_H
#define __APP_MODE_H

#include "test_profile.h"

/* Application mode is a build identity, not a runtime menu. A firmware image
 * must contain exactly one policy so controller/acquisition state can never
 * leak between motor characterization and official measurement. */
#define JIG_APP_CONTROL      1
#define JIG_APP_MEASUREMENT  2

#ifndef JIG_APP_MODE
#error "JIG_APP_MODE must be supplied by the Debug/Release build profile"
#endif

#if (JIG_APP_MODE != JIG_APP_CONTROL) && (JIG_APP_MODE != JIG_APP_MEASUREMENT)
#error "Unsupported JIG_APP_MODE"
#endif

#if JIG_APP_MODE == JIG_APP_CONTROL
#define JIG_APP_MODE_ID "MOTOR_CONTROL"
#define JIG_APP_PROFILE_ID "CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1"
#else
#define JIG_APP_MODE_ID "MEASUREMENT"
#define JIG_APP_PROFILE_ID TEST_PROFILE_ID
#endif

/* Official dual-image scripts inject the current git SHA. Direct IDE builds
 * remain clearly distinguishable rather than pretending to have traceable
 * source identity. */
#ifndef JIG_BUILD_SOURCE_ID
#define JIG_BUILD_SOURCE_ID "IDE_WORKTREE_UNTRACKED"
#endif

#endif /* __APP_MODE_H */
