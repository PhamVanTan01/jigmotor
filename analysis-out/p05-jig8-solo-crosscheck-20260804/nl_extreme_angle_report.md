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
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 264°(+1.8385°), 294°(+1.8258°), 293°(+1.7637°), 304°(+1.7317°), 263°(+1.7284°)
- Bottom 5: 36°(-1.4064°), 37°(-1.3828°), 76°(-1.3726°), 77°(-1.3091°), 38°(-1.2379°)

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
| P05 | JIG4→JIG8 | 0.9667 | 0.0° | 0.9667 | 0.2019° | +0.1703° | +0.3573° | -0.1870° | 25.60° | 8.00° |
| P05 | JIG4→test-2 | 0.9179 | 0.0° | 0.9179 | 0.3117° | +0.2920° | +0.5173° | -0.2254° | 18.00° | 55.60° |
| P05 | JIG5→JIG8 | 0.9294 | 0.0° | 0.9294 | 0.2754° | -0.2922° | -0.3402° | +0.0480° | 18.00° | 103.60° |
| P05 | JIG5→test-2 | 0.9776 | 0.0° | 0.9776 | 0.1535° | -0.1705° | -0.1802° | +0.0097° | 26.00° | 40.00° |
| P05 | JIG8→test-2 | 0.9632 | 0.0° | 0.9632 | 0.1996° | +0.1217° | +0.1600° | -0.0384° | 8.00° | 63.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
