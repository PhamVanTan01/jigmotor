# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / remount01-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 264°(+2.0912°), 263°(+2.0593°), 254°(+2.0510°), 253°(+1.9741°), 294°(+1.9427°)
- Bottom 5: 156°(-1.1570°), 196°(-1.1224°), 157°(-1.0986°), 197°(-1.0722°), 116°(-0.9655°)

### P05 / remount02-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=86.7%
- Top 5: 254°(+2.1643°), 264°(+2.1441°), 263°(+2.1241°), 253°(+2.0691°), 293°(+1.9470°)
- Bottom 5: 356°(-0.9595°), 156°(-0.9470°), 196°(-0.9449°), 157°(-0.9225°), 197°(-0.9013°)

### P05 / remount03-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 264°(+2.1781°), 263°(+2.1563°), 254°(+2.1099°), 253°(+2.0539°), 294°(+1.9810°)
- Bottom 5: 196°(-1.0270°), 197°(-0.9871°), 156°(-0.9866°), 356°(-0.9731°), 157°(-0.9437°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | remount01-test-1→remount02-test-1 | 0.9942 | 0.0° | 0.9942 | 0.0782° | +0.0664° | +0.1493° | -0.0829° | 0.20° | 24.00° |
| P05 | remount01-test-1→remount03-test-1 | 0.9941 | 0.0° | 0.9941 | 0.0790° | +0.0716° | +0.1017° | -0.0301° | 0.00° | 24.00° |
| P05 | remount02-test-1→remount03-test-1 | 0.9986 | 0.0° | 0.9986 | 0.0388° | +0.0053° | -0.0476° | +0.0529° | 0.20° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
