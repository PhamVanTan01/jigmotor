# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG4-B

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=80.0%
- Top 5: 294°(+1.6752°), 334°(+1.6634°), 333°(+1.5197°), 293°(+1.5002°), 254°(+1.4618°)
- Bottom 5: 27°(-1.1441°), 26°(-1.0480°), 107°(-0.9679°), 106°(-0.9618°), 7°(-0.9472°)

### P03 / JIG4-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 94°(+1.2846°), 334°(+1.2200°), 134°(+1.1777°), 174°(+1.1517°), 93°(+1.0943°)
- Bottom 5: 227°(-1.4186°), 266°(-1.3669°), 267°(-1.3640°), 226°(-1.3486°), 67°(-1.2969°)

### P03 / S1-P03-JIG1

- Eligible runs: 9
- Mean repeat-selection rate: top=86.7%, bottom=86.7%
- Top 5: 254°(+1.7841°), 294°(+1.7069°), 253°(+1.6522°), 244°(+1.6463°), 334°(+1.5713°)
- Bottom 5: 347°(-0.9758°), 346°(-0.9340°), 27°(-0.9318°), 107°(-0.9201°), 67°(-0.8836°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG4-B→JIG4-test-1 | 0.9481 | 240.0° | 0.9753 | 0.1546° | -0.3771° | -0.3390° | -0.0381° | 63.80° | 44.00° |
| P03 | JIG4-B→S1-P03-JIG1 | 0.9862 | 0.0° | 0.9862 | 0.1157° | +0.1138° | +0.0889° | +0.0249° | 25.80° | 19.80° |
| P03 | JIG4-test-1→S1-P03-JIG1 | 0.9325 | 120.0° | 0.9798 | 0.1395° | +0.4909° | +0.4278° | +0.0630° | 38.00° | 24.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
