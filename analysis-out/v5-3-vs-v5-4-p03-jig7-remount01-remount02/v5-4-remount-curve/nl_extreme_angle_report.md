# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 01

- Eligible runs: 3
- Mean repeat-selection rate: top=26.7%, bottom=66.7%
- Top 5: 131°(+0.1006°), 111°(+0.0971°), 300°(+0.0960°), 294°(+0.0953°), 11°(+0.0941°)
- Bottom 5: 108°(-0.5014°), 148°(-0.4485°), 347°(-0.3753°), 227°(-0.3711°), 267°(-0.3683°)

### P03 / 02

- Eligible runs: 3
- Mean repeat-selection rate: top=20.0%, bottom=66.7%
- Top 5: 22°(+0.0970°), 111°(+0.0929°), 33°(+0.0923°), 231°(+0.0921°), 122°(+0.0921°)
- Bottom 5: 108°(-0.4632°), 227°(-0.4539°), 148°(-0.4386°), 307°(-0.4148°), 348°(-0.4077°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 01→02 | 0.9677 | 0.0° | 0.9677 | 0.0322° | -0.0021° | -0.0069° | +0.0048° | 35.20° | 8.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
