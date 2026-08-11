# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 5-3

- Eligible runs: 3
- Mean repeat-selection rate: top=26.7%, bottom=86.7%
- Top 5: 292°(+0.1001°), 250°(+0.0864°), 312°(+0.0858°), 280°(+0.0853°), 232°(+0.0833°)
- Bottom 5: 347°(-0.4619°), 108°(-0.4111°), 227°(-0.4036°), 148°(-0.3876°), 77°(-0.3608°)

### P03 / 5-4

- Eligible runs: 3
- Mean repeat-selection rate: top=26.7%, bottom=66.7%
- Top 5: 131°(+0.1006°), 111°(+0.0971°), 300°(+0.0960°), 294°(+0.0953°), 11°(+0.0941°)
- Bottom 5: 108°(-0.5014°), 148°(-0.4485°), 347°(-0.3753°), 227°(-0.3711°), 267°(-0.3683°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 5-3→5-4 | 0.9288 | 0.0° | 0.9288 | 0.0494° | +0.0029° | -0.0359° | +0.0388° | 64.20° | 34.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
