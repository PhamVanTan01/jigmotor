# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / v5-4

- Eligible runs: 3
- Mean repeat-selection rate: top=26.7%, bottom=66.7%
- Top 5: 131°(+0.1006°), 111°(+0.0971°), 300°(+0.0960°), 294°(+0.0953°), 11°(+0.0941°)
- Bottom 5: 108°(-0.5014°), 148°(-0.4485°), 347°(-0.3753°), 227°(-0.3711°), 267°(-0.3683°)

### P03 / v5-4a

- Eligible runs: 3
- Mean repeat-selection rate: top=33.3%, bottom=60.0%
- Top 5: 280°(+0.1051°), 172°(+0.1008°), 161°(+0.0988°), 291°(+0.0962°), 55°(+0.0958°)
- Bottom 5: 108°(-0.4226°), 307°(-0.4127°), 227°(-0.4109°), 348°(-0.3990°), 148°(-0.3969°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | v5-4→v5-4a | 0.9679 | 0.0° | 0.9679 | 0.0311° | +0.0021° | +0.0304° | -0.0284° | 31.60° | 8.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
