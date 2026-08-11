# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### p03 / JIG1

- Eligible runs: 6
- Mean repeat-selection rate: top=86.7%, bottom=83.3%
- Top 5: 254°(+1.7218°), 294°(+1.6719°), 253°(+1.5798°), 244°(+1.5701°), 334°(+1.5568°)
- Bottom 5: 107°(-1.0060°), 106°(-0.9655°), 27°(-0.9604°), 347°(-0.9507°), 67°(-0.9338°)

### p03 / JIG4

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=80.0%
- Top 5: 294°(+1.6752°), 334°(+1.6634°), 333°(+1.5197°), 293°(+1.5002°), 254°(+1.4618°)
- Bottom 5: 27°(-1.1441°), 26°(-1.0480°), 107°(-0.9679°), 106°(-0.9618°), 7°(-0.9472°)

### p05 / JIG1

- Eligible runs: 6
- Mean repeat-selection rate: top=73.3%, bottom=73.3%
- Top 5: 334°(+1.5430°), 344°(+1.5255°), 333°(+1.4839°), 343°(+1.4766°), 304°(+1.4422°)
- Bottom 5: 76°(-1.6102°), 116°(-1.6058°), 77°(-1.5729°), 117°(-1.5223°), 196°(-1.4829°)

### p05 / JIG4

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 304°(+1.7426°), 264°(+1.6735°), 294°(+1.6708°), 303°(+1.6697°), 254°(+1.6512°)
- Bottom 5: 37°(-1.2736°), 76°(-1.2622°), 36°(-1.2437°), 77°(-1.2223°), 116°(-1.2170°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| p03 | JIG1→JIG4 | 0.9883 | 0.0° | 0.9883 | 0.1066° | -0.0658° | -0.0527° | -0.0131° | 25.80° | 12.20° |
| p05 | JIG1→JIG4 | 0.9648 | 320.0° | 0.9864 | 0.1201° | +0.1723° | +0.3292° | -0.1569° | 7.80° | 8.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
