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
- Mean repeat-selection rate: top=97.8%, bottom=100.0%
- Top 5: 304°(+1.7705°), 303°(+1.7038°), 294°(+1.6970°), 293°(+1.6611°), 264°(+1.6262°)
- Bottom 5: 36°(-1.5094°), 37°(-1.4551°), 76°(-1.3091°), 77°(-1.2715°), 38°(-1.2579°)

### P05 / test-2

- Eligible runs: 9
- Mean repeat-selection rate: top=93.3%, bottom=88.9%
- Top 5: 294°(+1.9427°), 293°(+1.8937°), 264°(+1.8639°), 304°(+1.8494°), 303°(+1.8198°)
- Bottom 5: 196°(-1.4240°), 197°(-1.3270°), 76°(-1.2388°), 77°(-1.2001°), 36°(-1.1840°)

### P05 / test-replay-sensor

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 264°(+1.6829°), 263°(+1.6313°), 294°(+1.5832°), 304°(+1.5795°), 184°(+1.5566°)
- Bottom 5: 36°(-1.1221°), 37°(-1.1039°), 76°(-1.0194°), 77°(-0.9719°), 156°(-0.9507°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG4→JIG5 | 0.8605 | 320.0° | 0.8720 | 0.3865° | +0.4625° | +0.6975° | -0.2350° | 15.60° | 111.60° |
| P05 | JIG4→test-1 | 0.9657 | 0.0° | 0.9657 | 0.2077° | +0.0841° | +0.3385° | -0.2544° | 18.00° | 8.00° |
| P05 | JIG4→test-2 | 0.9161 | 0.0° | 0.9161 | 0.3154° | +0.2663° | +0.4178° | -0.1515° | 18.00° | 55.60° |
| P05 | JIG4→test-replay-sensor | 0.9282 | 320.0° | 0.9330 | 0.2868° | +0.0002° | +0.6654° | -0.6652° | 8.20° | 55.60° |
| P05 | JIG5→test-1 | 0.9311 | 40.0° | 0.9356 | 0.2589° | -0.3783° | -0.3590° | -0.0193° | 14.00° | 112.40° |
| P05 | JIG5→test-2 | 0.9711 | 0.0° | 0.9711 | 0.1758° | -0.1962° | -0.2797° | +0.0835° | 26.00° | 40.00° |
| P05 | JIG5→test-replay-sensor | 0.9469 | 0.0° | 0.9469 | 0.2325° | -0.4622° | -0.0321° | -0.4302° | 23.80° | 80.00° |
| P05 | test-1→test-2 | 0.9656 | 0.0° | 0.9656 | 0.1915° | +0.1822° | +0.0793° | +0.1029° | 0.00° | 63.60° |
| P05 | test-1→test-replay-sensor | 0.9814 | 0.0° | 0.9814 | 0.1398° | -0.0839° | +0.3270° | -0.4109° | 29.80° | 23.60° |
| P05 | test-2→test-replay-sensor | 0.9543 | 0.0° | 0.9543 | 0.2204° | -0.2661° | +0.2477° | -0.5137° | 29.80° | 40.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
