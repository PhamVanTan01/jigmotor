/* End-of-shaft mounting nonlinear sweep test (docs/end-of-shaft-mounting-test-plan.md
 * Part B). Blocking; prints the result over USART3 in a format
 * scripts/analyze_nonlinear_logs.ps1 already knows how to parse. */

#ifndef __NONLINEAR_TEST_H
#define __NONLINEAR_TEST_H

#ifdef __cplusplus
extern "C" {
#endif

/* Call once on every detected button-press edge. With ENABLE_AUTO_BATCH_TEST off (default),
 * this runs exactly one test, same as the old NonlinearTest_Run() this replaced. With it on,
 * a press starts a whole multi-run batch with a firmware-timed cooldown between runs -- see
 * nonlinear_test.c for details. */
void NonlinearBatch_OnButtonPress(void);

/* Call once per main-loop iteration (StartDefaultTask's ~200ms idle cadence). Never blocks --
 * a no-op unless a batch cooldown is in progress and due to advance to its next run. */
void NonlinearBatch_Poll(void);

#ifdef __cplusplus
}
#endif

#endif /* __NONLINEAR_TEST_H */
