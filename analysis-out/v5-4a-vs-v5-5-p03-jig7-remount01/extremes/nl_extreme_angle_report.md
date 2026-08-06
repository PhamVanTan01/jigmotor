# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 4a

- Eligible runs: 3
- Mean repeat-selection rate: top=33.3%, bottom=60.0%
- Top 5: 280°(+0.1051°), 172°(+0.1008°), 161°(+0.0988°), 291°(+0.0962°), 55°(+0.0958°)
- Bottom 5: 108°(-0.4226°), 307°(-0.4127°), 227°(-0.4109°), 348°(-0.3990°), 148°(-0.3969°)

### P03 / 5

- Eligible runs: 2
- Mean repeat-selection rate: top=30.0%, bottom=90.0%
- Top 5: 180°(+0.1021°), 262°(+0.0984°), 191°(+0.0982°), 341°(+0.0972°), 242°(+0.0962°)
- Bottom 5: 68°(-0.3627°), 67°(-0.3415°), 107°(-0.2808°), 108°(-0.2377°), 147°(-0.2023°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 4a→5 | 0.8719 | 0.0° | 0.8719 | 0.0625° | -0.0022° | +0.1381° | -0.1403° | 35.80° | 64.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
