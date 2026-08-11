# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG7

- Eligible runs: 3
- Mean repeat-selection rate: top=40.0%, bottom=100.0%
- Top 5: 141°(+0.1010°), 111°(+0.0990°), 330°(+0.0972°), 83°(+0.0971°), 33°(+0.0950°)
- Bottom 5: 67°(-0.4925°), 68°(-0.4678°), 107°(-0.3252°), 347°(-0.2815°), 108°(-0.2743°)

### P03 / JIG8

- Eligible runs: 3
- Mean repeat-selection rate: top=26.7%, bottom=40.0%
- Top 5: 239°(+0.0983°), 115°(+0.0977°), 232°(+0.0960°), 261°(+0.0959°), 321°(+0.0954°)
- Bottom 5: 347°(-0.1187°), 187°(-0.1119°), 107°(-0.1043°), 157°(-0.0993°), 28°(-0.0977°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG7→JIG8 | 0.7792 | 40.0° | 0.7831 | 0.0577° | +0.0018° | +0.2554° | -0.2537° | 73.60° | 33.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
