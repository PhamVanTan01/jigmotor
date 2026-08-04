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

- Eligible runs: 9
- Mean repeat-selection rate: top=86.7%, bottom=100.0%
- Top 5: 304°(+1.9000°), 303°(+1.8280°), 294°(+1.7812°), 264°(+1.7525°), 293°(+1.7511°)
- Bottom 5: 36°(-1.3184°), 37°(-1.2749°), 76°(-1.1595°), 77°(-1.1162°), 38°(-1.0870°)

### P05 / test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 294°(+1.9486°), 293°(+1.9326°), 264°(+1.9266°), 304°(+1.8603°), 263°(+1.8562°)
- Bottom 5: 196°(-1.1796°), 197°(-1.1158°), 76°(-1.0781°), 77°(-1.0456°), 36°(-1.0148°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4→JIG5 | 0.8605 | 320.0° | 0.8720 | 0.3865° | +0.4625° | +0.6975° | -0.2350° | 15.60° | 111.60° |
| P05 | JIG4→test-1 | 0.9621 | 0.0° | 0.9621 | 0.2173° | +0.1976° | +0.5079° | -0.3103° | 18.00° | 8.00° |
| P05 | JIG4→test-2 | 0.9197 | 0.0° | 0.9197 | 0.3085° | +0.2973° | +0.6123° | -0.3149° | 25.60° | 55.60° |
| P05 | JIG5→test-1 | 0.9345 | 0.0° | 0.9345 | 0.2611° | -0.2649° | -0.1896° | -0.0753° | 26.00° | 103.60° |
| P05 | JIG5→test-2 | 0.9833 | 0.0° | 0.9833 | 0.1320° | -0.1651° | -0.0852° | -0.0799° | 18.00° | 40.00° |
| P05 | test-1→test-2 | 0.9704 | 0.0° | 0.9704 | 0.1753° | +0.0998° | +0.1044° | -0.0046° | 8.00° | 63.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
