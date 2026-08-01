# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 01

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=86.7%
- Top 5: 254°(+1.8463°), 294°(+1.7485°), 253°(+1.7259°), 244°(+1.7204°), 134°(+1.6238°)
- Bottom 5: 347°(-0.9567°), 346°(-0.9342°), 27°(-0.9164°), 107°(-0.8749°), 67°(-0.8520°)

### P03 / 02

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=100.0%
- Top 5: 254°(+1.7343°), 294°(+1.6712°), 244°(+1.6053°), 253°(+1.6017°), 334°(+1.5540°)
- Bottom 5: 347°(-0.9977°), 107°(-0.9751°), 27°(-0.9699°), 346°(-0.9483°), 106°(-0.9324°)

### P03 / 03

- Eligible runs: 3
- Mean repeat-selection rate: top=80.0%, bottom=93.3%
- Top 5: 254°(+1.7716°), 294°(+1.7009°), 253°(+1.6290°), 244°(+1.6131°), 134°(+1.5804°)
- Bottom 5: 347°(-0.9732°), 346°(-0.9196°), 107°(-0.9103°), 27°(-0.9091°), 67°(-0.8770°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 01→02 | 0.9986 | 0.0° | 0.9986 | 0.0374° | -0.1014° | -0.0557° | -0.0458° | 32.00° | 7.80° |
| P03 | 01→03 | 0.9990 | 0.0° | 0.9990 | 0.0325° | -0.0756° | -0.0109° | -0.0647° | 0.00° | 0.00° |
| P03 | 02→03 | 0.9986 | 0.0° | 0.9986 | 0.0376° | +0.0258° | +0.0448° | -0.0190° | 32.00° | 7.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
