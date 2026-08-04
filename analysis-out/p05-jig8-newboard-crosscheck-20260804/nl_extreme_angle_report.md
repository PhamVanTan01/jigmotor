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

### P05 / test-1

- Eligible runs: 21
- Mean repeat-selection rate: top=91.4%, bottom=100.0%
- Top 5: 304°(+1.8205°), 303°(+1.7587°), 294°(+1.7515°), 293°(+1.7143°), 264°(+1.7106°)
- Bottom 5: 36°(-1.4128°), 37°(-1.3675°), 76°(-1.2541°), 77°(-1.2103°), 38°(-1.1818°)

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
| P05 | JIG4→test-1 | 0.9659 | 0.0° | 0.9659 | 0.2069° | +0.1450° | +0.4138° | -0.2687° | 18.00° | 8.00° |
| P05 | JIG4→test-2 | 0.9179 | 0.0° | 0.9179 | 0.3117° | +0.2920° | +0.5173° | -0.2254° | 18.00° | 55.60° |
| P05 | JIG5→test-1 | 0.9338 | 0.0° | 0.9338 | 0.2628° | -0.3174° | -0.2837° | -0.0337° | 26.00° | 103.60° |
| P05 | JIG5→test-2 | 0.9776 | 0.0° | 0.9776 | 0.1535° | -0.1705° | -0.1802° | +0.0097° | 26.00° | 40.00° |
| P05 | test-1→test-2 | 0.9679 | 0.0° | 0.9679 | 0.1836° | +0.1469° | +0.1036° | +0.0434° | 0.00° | 63.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
