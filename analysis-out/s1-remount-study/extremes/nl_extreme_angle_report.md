# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### p03 / JIG1

- Eligible runs: 9
- Mean repeat-selection rate: top=86.7%, bottom=86.7%
- Top 5: 254°(+1.7841°), 294°(+1.7069°), 253°(+1.6522°), 244°(+1.6463°), 334°(+1.5713°)
- Bottom 5: 347°(-0.9758°), 346°(-0.9340°), 27°(-0.9318°), 107°(-0.9201°), 67°(-0.8836°)

### p05 / JIG1

- Eligible runs: 9
- Mean repeat-selection rate: top=97.8%, bottom=84.4%
- Top 5: 264°(+1.8986°), 254°(+1.8730°), 263°(+1.8696°), 253°(+1.8206°), 294°(+1.7137°)
- Bottom 5: 116°(-1.4469°), 196°(-1.4062°), 156°(-1.4045°), 117°(-1.3657°), 76°(-1.3507°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
