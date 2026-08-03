# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.3821°), 263°(+2.3492°), 254°(+2.3336°), 294°(+2.2717°), 253°(+2.2691°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9125°), 196°(-0.8723°), 197°(-0.8237°), 156°(-0.7966°)

### P05 / remount02-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 304°(+1.8820°), 254°(+1.8592°), 303°(+1.8348°), 294°(+1.8245°), 293°(+1.7953°)
- Bottom 5: 36°(-1.2545°), 37°(-1.2304°), 76°(-1.0530°), 77°(-1.0248°), 356°(-1.0125°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | remount01-test-2→remount02-test-1 | 0.9624 | 0.0° | 0.9624 | 0.2025° | -0.4809° | -0.2449° | -0.2360° | 24.00° | 79.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
