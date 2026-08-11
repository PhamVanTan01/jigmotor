# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P08 / 01

- Eligible runs: 2
- Mean repeat-selection rate: top=30.0%, bottom=40.0%
- Top 5: 101°(+0.1128°), 31°(+0.1023°), 213°(+0.1013°), 202°(+0.1005°), 52°(+0.1002°)
- Bottom 5: 308°(-0.2348°), 237°(-0.1061°), 239°(-0.1045°), 319°(-0.1021°), 311°(-0.0994°)

### P08 / 02

- Eligible runs: 2
- Mean repeat-selection rate: top=60.0%, bottom=40.0%
- Top 5: 232°(+0.1088°), 130°(+0.1088°), 73°(+0.1011°), 153°(+0.0990°), 82°(+0.0988°)
- Bottom 5: 308°(-0.1842°), 156°(-0.1077°), 109°(-0.1005°), 118°(-0.1001°), 337°(-0.0997°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P08 | 01→02 | 0.9567 | 0.0° | 0.9567 | 0.0237° | -0.0008° | +0.0107° | -0.0116° | 33.80° | 75.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
