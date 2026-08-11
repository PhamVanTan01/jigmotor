# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.7179°), 303°(+1.6814°), 254°(+1.6282°), 264°(+1.6255°), 334°(+1.6211°)
- Bottom 5: 77°(-1.7434°), 76°(-1.7413°), 36°(-1.6049°), 37°(-1.5953°), 78°(-1.5373°)

### P05 / remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=100.0%
- Top 5: 304°(+1.6608°), 303°(+1.5984°), 334°(+1.5889°), 254°(+1.5815°), 224°(+1.5420°)
- Bottom 5: 76°(-1.8186°), 77°(-1.8076°), 37°(-1.6392°), 36°(-1.6380°), 78°(-1.6211°)

### P05 / remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.6201°), 334°(+1.5829°), 303°(+1.5636°), 333°(+1.5539°), 254°(+1.5378°)
- Bottom 5: 76°(-1.8810°), 77°(-1.8392°), 36°(-1.6973°), 78°(-1.6723°), 37°(-1.6493°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | remount01-test-2→remount02-test-2 | 0.9992 | 0.0° | 0.9992 | 0.0321° | -0.0611° | -0.0605° | -0.0006° | 8.00° | 0.00° |
| P05 | remount01-test-2→remount03-test-2 | 0.9976 | 0.0° | 0.9976 | 0.0539° | -0.0845° | -0.1034° | +0.0189° | 13.80° | 0.00° |
| P05 | remount02-test-2→remount03-test-2 | 0.9993 | 0.0° | 0.9993 | 0.0302° | -0.0234° | -0.0429° | +0.0195° | 21.80° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
