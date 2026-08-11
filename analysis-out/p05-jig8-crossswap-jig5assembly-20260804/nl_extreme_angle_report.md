# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / JIG4

- Eligible runs: 9
- Mean repeat-selection rate: top=82.2%, bottom=100.0%
- Top 5: 304°(+1.6663°), 303°(+1.6145°), 334°(+1.5976°), 254°(+1.5825°), 333°(+1.5554°)
- Bottom 5: 76°(-1.8136°), 77°(-1.7967°), 36°(-1.6467°), 37°(-1.6280°), 78°(-1.6102°)

### P05 / JIG5

- Eligible runs: 9
- Mean repeat-selection rate: top=91.1%, bottom=91.1%
- Top 5: 264°(+2.1378°), 263°(+2.1133°), 254°(+2.1084°), 253°(+2.0324°), 294°(+1.9550°)
- Bottom 5: 196°(-1.0315°), 156°(-1.0302°), 157°(-0.9883°), 197°(-0.9869°), 356°(-0.9625°)

### P05 / JIG8

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=86.7%
- Top 5: 294°(+1.5285°), 334°(+1.4275°), 304°(+1.4230°), 333°(+1.4015°), 293°(+1.3927°)
- Bottom 5: 76°(-1.9165°), 77°(-1.8593°), 78°(-1.6631°), 36°(-1.5523°), 37°(-1.5317°)

### P05 / test-2

- Eligible runs: 18
- Mean repeat-selection rate: top=91.1%, bottom=90.0%
- Top 5: 294°(+1.9540°), 293°(+1.9223°), 264°(+1.9033°), 304°(+1.8711°), 303°(+1.8435°)
- Bottom 5: 196°(-1.3052°), 197°(-1.2204°), 76°(-1.1468°), 77°(-1.1073°), 36°(-1.0939°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4→JIG5 | 0.8605 | 320.0° | 0.8720 | 0.3865° | +0.4625° | +0.6975° | -0.2350° | 15.60° | 111.60° |
| P05 | JIG4→JIG8 | 0.9700 | 0.0° | 0.9700 | 0.1919° | -0.1608° | -0.0194° | -0.1414° | 9.60° | 0.00° |
| P05 | JIG4→test-2 | 0.9179 | 0.0° | 0.9179 | 0.3117° | +0.2920° | +0.5173° | -0.2254° | 18.00° | 55.60° |
| P05 | JIG5→JIG8 | 0.8679 | 40.0° | 0.9224 | 0.2895° | -0.6233° | -0.7169° | +0.0936° | 6.00° | 111.60° |
| P05 | JIG5→test-2 | 0.9776 | 0.0° | 0.9776 | 0.1535° | -0.1705° | -0.1802° | +0.0097° | 26.00° | 40.00° |
| P05 | JIG8→test-2 | 0.9381 | 0.0° | 0.9381 | 0.2591° | +0.4528° | +0.5367° | -0.0840° | 20.00° | 55.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
