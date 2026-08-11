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

### P05 / JIG6

- Eligible runs: 9
- Mean repeat-selection rate: top=86.7%, bottom=91.1%
- Top 5: 294°(+1.9653°), 293°(+1.9510°), 264°(+1.9427°), 304°(+1.8929°), 263°(+1.8707°)
- Bottom 5: 196°(-1.1863°), 197°(-1.1137°), 76°(-1.0548°), 77°(-1.0144°), 36°(-1.0038°)

### P05 / JIG7

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 294°(+1.9256°), 293°(+1.8751°), 304°(+1.8482°), 264°(+1.8274°), 303°(+1.8095°)
- Bottom 5: 196°(-1.4583°), 197°(-1.3498°), 76°(-1.2617°), 77°(-1.2302°), 36°(-1.2046°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4→JIG5 | 0.8605 | 320.0° | 0.8720 | 0.3865° | +0.4625° | +0.6975° | -0.2350° | 15.60° | 111.60° |
| P05 | JIG4→JIG6 | 0.9181 | 0.0° | 0.9181 | 0.3112° | +0.3177° | +0.6169° | -0.2992° | 25.60° | 55.60° |
| P05 | JIG4→JIG7 | 0.9182 | 0.0° | 0.9182 | 0.3114° | +0.2493° | +0.3979° | -0.1486° | 18.00° | 55.60° |
| P05 | JIG5→JIG6 | 0.9826 | 0.0° | 0.9826 | 0.1350° | -0.1448° | -0.0806° | -0.0642° | 18.00° | 40.00° |
| P05 | JIG5→JIG7 | 0.9684 | 0.0° | 0.9684 | 0.1839° | -0.2131° | -0.2996° | +0.0865° | 26.00° | 40.00° |
| P05 | JIG6→JIG7 | 0.9958 | 0.0° | 0.9958 | 0.0685° | -0.0683° | -0.2190° | +0.1506° | 8.00° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
