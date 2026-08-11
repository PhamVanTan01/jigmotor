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

- Eligible runs: 6
- Mean repeat-selection rate: top=90.0%, bottom=100.0%
- Top 5: 264°(+1.8200°), 294°(+1.8061°), 293°(+1.7368°), 304°(+1.7287°), 263°(+1.7074°)
- Bottom 5: 36°(-1.4246°), 37°(-1.3957°), 76°(-1.3766°), 77°(-1.3117°), 38°(-1.2396°)

### P05 / test-2

- Eligible runs: 6
- Mean repeat-selection rate: top=73.3%, bottom=83.3%
- Top 5: 294°(+1.5074°), 334°(+1.4162°), 264°(+1.3967°), 333°(+1.3809°), 293°(+1.3770°)
- Bottom 5: 76°(-2.0218°), 77°(-1.9393°), 78°(-1.7316°), 196°(-1.5991°), 36°(-1.5905°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4→JIG5 | 0.8605 | 320.0° | 0.8720 | 0.3865° | +0.4625° | +0.6975° | -0.2350° | 15.60° | 111.60° |
| P05 | JIG4→test-1 | 0.9681 | 0.0° | 0.9681 | 0.1982° | +0.1550° | +0.3494° | -0.1944° | 25.60° | 8.00° |
| P05 | JIG4→test-2 | 0.9623 | 0.0° | 0.9623 | 0.2136° | -0.1723° | -0.0926° | -0.0797° | 6.00° | 31.80° |
| P05 | JIG5→test-1 | 0.9293 | 0.0° | 0.9293 | 0.2748° | -0.3075° | -0.3481° | +0.0406° | 18.00° | 103.60° |
| P05 | JIG5→test-2 | 0.8593 | 40.0° | 0.9160 | 0.3036° | -0.6347° | -0.7901° | +0.1554° | 13.60° | 87.80° |
| P05 | test-1→test-2 | 0.9536 | 40.0° | 0.9606 | 0.2095° | -0.3272° | -0.4420° | +0.1147° | 20.00° | 31.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
