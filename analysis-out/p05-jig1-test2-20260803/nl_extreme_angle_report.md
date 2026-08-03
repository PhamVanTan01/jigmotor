# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.3821°), 263°(+2.3492°), 254°(+2.3336°), 294°(+2.2717°), 253°(+2.2691°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9125°), 196°(-0.8723°), 197°(-0.8237°), 156°(-0.7966°)

### P05 / remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 263°(+2.3948°), 264°(+2.3926°), 254°(+2.3842°), 294°(+2.3215°), 253°(+2.3067°)
- Bottom 5: 356°(-0.9650°), 357°(-0.9390°), 156°(-0.8285°), 196°(-0.7812°), 197°(-0.7788°)

### P05 / remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2934°), 263°(+2.2603°), 254°(+2.2333°), 294°(+2.2148°), 293°(+2.1659°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9128°), 196°(-0.9074°), 197°(-0.8755°), 156°(-0.8636°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | remount01-test-2→remount02-test-2 | 0.9988 | 0.0° | 0.9988 | 0.0366° | +0.0388° | +0.0113° | +0.0275° | 0.00° | 0.00° |
| P05 | remount01-test-2→remount03-test-2 | 0.9989 | 0.0° | 0.9989 | 0.0368° | -0.0876° | -0.0308° | -0.0568° | 8.00° | 0.00° |
| P05 | remount02-test-2→remount03-test-2 | 0.9982 | 0.0° | 0.9982 | 0.0459° | -0.1264° | -0.0422° | -0.0842° | 8.00° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
