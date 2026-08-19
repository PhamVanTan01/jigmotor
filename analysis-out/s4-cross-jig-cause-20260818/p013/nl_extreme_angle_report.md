# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P013 / JIG7

- Eligible runs: 10
- Mean repeat-selection rate: top=92.0%, bottom=100.0%
- Top 5: 244°(+1.6512°), 274°(+1.6190°), 234°(+1.5784°), 243°(+1.5732°), 264°(+1.5663°)
- Bottom 5: 137°(-1.0748°), 136°(-1.0522°), 337°(-1.0508°), 336°(-1.0415°), 167°(-1.0249°)

### P013 / JIG8

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=86.0%
- Top 5: 234°(+1.9220°), 264°(+1.8260°), 233°(+1.8216°), 224°(+1.8146°), 263°(+1.7740°)
- Bottom 5: 57°(-1.1146°), 56°(-1.0825°), 96°(-1.0805°), 97°(-1.0505°), 47°(-1.0238°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P013 | JIG7→JIG8 | 0.9430 | 0.0° | 0.9430 | 0.2431° | +0.2363° | -0.0252° | +0.2615° | 8.20° | 68.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
