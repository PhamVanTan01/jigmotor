# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 01

- Eligible runs: 3
- Mean repeat-selection rate: top=33.3%, bottom=60.0%
- Top 5: 280°(+0.1051°), 172°(+0.1008°), 161°(+0.0988°), 291°(+0.0962°), 55°(+0.0958°)
- Bottom 5: 108°(-0.4226°), 307°(-0.4127°), 227°(-0.4109°), 348°(-0.3990°), 148°(-0.3969°)

### P03 / 02

- Eligible runs: 2
- Mean repeat-selection rate: top=50.0%, bottom=60.0%
- Top 5: 292°(+0.1058°), 261°(+0.1050°), 173°(+0.1024°), 172°(+0.0986°), 121°(+0.0969°)
- Bottom 5: 68°(-0.4599°), 69°(-0.4548°), 98°(-0.4366°), 348°(-0.4337°), 108°(-0.4242°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 01→02 | 0.9561 | 0.0° | 0.9561 | 0.0386° | -0.0001° | -0.0531° | +0.0530° | 19.60° | 65.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
