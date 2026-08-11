# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / test-1

- Eligible runs: 6
- Mean repeat-selection rate: top=90.0%, bottom=100.0%
- Top 5: 264°(+1.8200°), 294°(+1.8061°), 293°(+1.7368°), 304°(+1.7287°), 263°(+1.7074°)
- Bottom 5: 36°(-1.4246°), 37°(-1.3957°), 76°(-1.3766°), 77°(-1.3117°), 38°(-1.2396°)

### P05 / test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=86.7%
- Top 5: 294°(+1.5285°), 334°(+1.4275°), 304°(+1.4230°), 333°(+1.4015°), 293°(+1.3927°)
- Bottom 5: 76°(-1.9165°), 77°(-1.8593°), 78°(-1.6631°), 36°(-1.5523°), 37°(-1.5317°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | test-1→test-2 | 0.9610 | 40.0° | 0.9648 | 0.1963° | -0.3158° | -0.3688° | +0.0530° | 12.00° | 32.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
