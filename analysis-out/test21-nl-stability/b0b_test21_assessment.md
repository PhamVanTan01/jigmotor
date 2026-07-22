# B0-B test 21 A-B-A assessment

Inputs:

- `B0-B p03 jig 1 test 21A.txt` — baseline A1, feedforward off
- `B0-B p03 jig 1 test 21B.txt` — `CREEP_DERIVED_BIAS_V1`, backoff bias 100 raw, forward bias 136 raw
- `B0-B p03 jig 1 test 21A2.txt` — baseline A2, feedforward off

Statistics exclude the three `PRECONDITION` sweeps. All 30 official sweeps are structurally and acquisition valid.

## Decision table

| Criterion | Result | Decision |
|---|---:|---|
| Feedforward extension executed exactly 13/17 steps | 10/10 | PASS |
| Approach structural/acquisition valid | 10/10 | PASS |
| Ramp and lock timing overruns | 0/10 | PASS |
| Backoff endpoint within +/-16 raw | 1/10 | FAIL |
| Forward endpoint within +/-16 raw | 8/10 | PARTIAL |
| Both endpoints within +/-16 raw | 1/10 | FAIL |
| Closure <=0.20 deg | 0/10 | FAIL |
| NL mean versus bracketed A baseline | +0.00024 deg | PASS / no material regression |
| H36 versus bracketed A baseline | -0.00123 deg | PASS / no material regression |

## A-B-A means

| Metric | A1 | B | A2 |
|---|---:|---:|---:|
| Backoff observed raw | -93.5 | -204.9 | -96.7 |
| Forward observed raw | +60.2 | +191.5 | +66.0 |
| Return error raw | -33.3 | -13.4 | -30.7 |
| Closure deg | 0.3701 | 0.2568 | 0.3547 |
| NL robust P2P deg | 3.00028 | 3.00230 | 3.00384 |
| H36 amplitude deg | 0.90808 | 0.90564 | 0.90565 |

The B leg improves mean closure by 0.1056 deg (29.1%) relative to the bracketed A mean, but no official B run passes the 0.20 deg pilot limit.

## Feedforward calibration result

Official B target errors:

- Backoff: mean -22.9 raw, SD 7.9, range -38..-13. All ten runs overshoot the target.
- Forward: mean +9.5 raw, SD 6.8, range 0..23. Nine runs overshoot and one lands exactly on target.
- Return: mean -13.4 raw, SD 3.6, range -18..-8.

Using the A1/A2 bracket as the zero-bias baseline gives the local command-to-motion estimates:

- backoff gain = `(204.9 - 95.1) / 100 = 1.098 actual raw / bias raw`
- forward gain = `(191.5 - 63.1) / 136 = 0.944 actual raw / bias raw`

Bias estimates for a zero-mean endpoint error:

- backoff: `(182 - 95.1) / 1.098 = 79.1 raw`
- forward: `(182 - 63.1) / 0.944 = 126.0 raw`

Recommended next feedforward-only calibration candidate: **79 raw backoff / 126 raw forward**. Keep creep disabled and repeat the same A-B-A protocol. Acceptance requires 10/10 official runs within +/-16 raw on both legs; closure remains a separate diagnostic and must not be used to hide endpoint failure.

Before enabling feedforward and creep together, add an explicit overshoot/direction guard. The current B data proves the need: backoff overshoots in 10/10 runs, so a residual creep implementation that follows the instantaneous target gap would reverse direction and violate the same-direction approach contract.

The A2 precondition has Closure=1.14155 deg and HomeInitialError=162.75 deg, then the official runs recover to 0.3258..0.3727 deg. This is additional evidence that the first physical sweep after a large state change is not ready to be treated as the production result.
