#ifndef __APP_MODE_H
#define __APP_MODE_H

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
#define JIG_APP_PROFILE_ID "CONTROL_A2C_FIXED_PHASE_ALIGN_P06_H500_V1"
#else
#define JIG_APP_MODE_ID "MEASUREMENT"
#define JIG_APP_PROFILE_ID "MEASUREMENT_MOTION_V2_DMA_P1"
#endif

/* Official dual-image scripts inject the current git SHA. Direct IDE builds
 * remain clearly distinguishable rather than pretending to have traceable
 * source identity. */
#ifndef JIG_BUILD_SOURCE_ID
#define JIG_BUILD_SOURCE_ID "IDE_WORKTREE_UNTRACKED"
#endif

#endif /* __APP_MODE_H */
