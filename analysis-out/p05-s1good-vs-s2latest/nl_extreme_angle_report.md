# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / JIG4-B

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 304°(+1.7426°), 264°(+1.6735°), 294°(+1.6708°), 303°(+1.6697°), 254°(+1.6512°)
- Bottom 5: 37°(-1.2736°), 76°(-1.2622°), 36°(-1.2437°), 77°(-1.2223°), 116°(-1.2170°)

### P05 / JIG4-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 284°(+1.6711°), 283°(+1.6264°), 124°(+1.5921°), 123°(+1.5796°), 274°(+1.5526°)
- Bottom 5: 176°(-1.2759°), 16°(-1.2503°), 17°(-1.2090°), 177°(-1.1969°), 216°(-1.1372°)

### P05 / S1-P05-JIG1

- Eligible runs: 9
- Mean repeat-selection rate: top=97.8%, bottom=84.4%
- Top 5: 264°(+1.8986°), 254°(+1.8730°), 263°(+1.8696°), 253°(+1.8206°), 294°(+1.7137°)
- Bottom 5: 116°(-1.4469°), 196°(-1.4062°), 156°(-1.4045°), 117°(-1.3657°), 76°(-1.3507°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4-B→JIG4-test-1 | 0.7324 | 340.0° | 0.9133 | 0.2962° | -0.0772° | +0.0299° | -0.1071° | 46.20° | 72.00° |
| P05 | JIG4-B→S1-P05-JIG1 | 0.9539 | 0.0° | 0.9539 | 0.2298° | +0.1536° | -0.1532° | +0.3067° | 18.20° | 63.80° |
| P05 | JIG4-test-1→S1-P05-JIG1 | 0.7028 | 340.0° | 0.8667 | 0.3833° | +0.2308° | -0.1831° | +0.4138° | 63.60° | 47.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
