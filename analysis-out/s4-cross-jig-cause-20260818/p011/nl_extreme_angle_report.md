# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P011 / JIG7

- Eligible runs: 10
- Mean repeat-selection rate: top=88.0%, bottom=82.0%
- Top 5: 234°(+1.2939°), 274°(+1.2936°), 354°(+1.2934°), 194°(+1.2614°), 273°(+1.2319°)
- Bottom 5: 96°(-1.3376°), 97°(-1.3293°), 17°(-1.3059°), 16°(-1.2998°), 337°(-1.2274°)

### P011 / JIG8

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=98.0%
- Top 5: 274°(+1.7008°), 273°(+1.6209°), 314°(+1.6018°), 313°(+1.4738°), 234°(+1.4535°)
- Bottom 5: 96°(-1.5058°), 97°(-1.5026°), 87°(-1.3758°), 98°(-1.3210°), 86°(-1.2841°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P011 | JIG7→JIG8 | 0.9511 | 0.0° | 0.9511 | 0.2232° | +0.2909° | -0.0963° | +0.3872° | 31.80° | 52.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
