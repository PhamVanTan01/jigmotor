# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / JIG1-remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.3821°), 263°(+2.3492°), 254°(+2.3336°), 294°(+2.2717°), 253°(+2.2691°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9125°), 196°(-0.8723°), 197°(-0.8237°), 156°(-0.7966°)

### P05 / JIG1-remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 263°(+2.3948°), 264°(+2.3926°), 254°(+2.3842°), 294°(+2.3215°), 253°(+2.3067°)
- Bottom 5: 356°(-0.9650°), 357°(-0.9390°), 156°(-0.8285°), 196°(-0.7812°), 197°(-0.7788°)

### P05 / JIG1-remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2934°), 263°(+2.2603°), 254°(+2.2333°), 294°(+2.2148°), 293°(+2.1659°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9128°), 196°(-0.9074°), 197°(-0.8755°), 156°(-0.8636°)

### P05 / JIG4-remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.7179°), 303°(+1.6814°), 254°(+1.6282°), 264°(+1.6255°), 334°(+1.6211°)
- Bottom 5: 77°(-1.7434°), 76°(-1.7413°), 36°(-1.6049°), 37°(-1.5953°), 78°(-1.5373°)

### P05 / JIG4-remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=100.0%
- Top 5: 304°(+1.6608°), 303°(+1.5984°), 334°(+1.5889°), 254°(+1.5815°), 224°(+1.5420°)
- Bottom 5: 76°(-1.8186°), 77°(-1.8076°), 37°(-1.6392°), 36°(-1.6380°), 78°(-1.6211°)

### P05 / JIG4-remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.6201°), 334°(+1.5829°), 303°(+1.5636°), 333°(+1.5539°), 254°(+1.5378°)
- Bottom 5: 76°(-1.8810°), 77°(-1.8392°), 36°(-1.6973°), 78°(-1.6723°), 37°(-1.6493°)

### P05 / JIG5-remount01-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 264°(+2.0912°), 263°(+2.0593°), 254°(+2.0510°), 253°(+1.9741°), 294°(+1.9427°)
- Bottom 5: 156°(-1.1570°), 196°(-1.1224°), 157°(-1.0986°), 197°(-1.0722°), 116°(-0.9655°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | JIG1-remount01-test-2→JIG1-remount02-test-2 | 0.9988 | 0.0° | 0.9988 | 0.0366° | +0.0388° | +0.0113° | +0.0275° | 0.00° | 0.00° |
| P05 | JIG1-remount01-test-2→JIG1-remount03-test-2 | 0.9989 | 0.0° | 0.9989 | 0.0368° | -0.0876° | -0.0308° | -0.0568° | 8.00° | 0.00° |
| P05 | JIG1-remount01-test-2→JIG4-remount01-test-2 | 0.8761 | 40.0° | 0.9016 | 0.3415° | -0.6648° | -0.7732° | +0.1084° | 13.80° | 87.60° |
| P05 | JIG1-remount01-test-2→JIG4-remount02-test-2 | 0.8594 | 40.0° | 0.8936 | 0.3558° | -0.7259° | -0.8337° | +0.1078° | 21.80° | 87.60° |
| P05 | JIG1-remount01-test-2→JIG4-remount03-test-2 | 0.8477 | 40.0° | 0.8921 | 0.3577° | -0.7493° | -0.8766° | +0.1273° | 15.60° | 87.60° |
| P05 | JIG1-remount01-test-2→JIG5-remount01-test-1 | 0.9886 | 0.0° | 0.9886 | 0.1125° | -0.2969° | -0.2141° | -0.0829° | 0.00° | 56.00° |
| P05 | JIG1-remount02-test-2→JIG1-remount03-test-2 | 0.9982 | 0.0° | 0.9982 | 0.0459° | -0.1264° | -0.0422° | -0.0842° | 8.00° | 0.00° |
| P05 | JIG1-remount02-test-2→JIG4-remount01-test-2 | 0.8715 | 40.0° | 0.8997 | 0.3450° | -0.7036° | -0.7846° | +0.0809° | 13.80° | 87.60° |
| P05 | JIG1-remount02-test-2→JIG4-remount02-test-2 | 0.8546 | 40.0° | 0.8917 | 0.3592° | -0.7647° | -0.8451° | +0.0803° | 21.80° | 87.60° |
| P05 | JIG1-remount02-test-2→JIG4-remount03-test-2 | 0.8428 | 40.0° | 0.8903 | 0.3609° | -0.7881° | -0.8879° | +0.0998° | 15.60° | 87.60° |
| P05 | JIG1-remount02-test-2→JIG5-remount01-test-1 | 0.9875 | 0.0° | 0.9875 | 0.1182° | -0.3357° | -0.2254° | -0.1103° | 0.00° | 56.00° |
| P05 | JIG1-remount03-test-2→JIG4-remount01-test-2 | 0.8757 | 40.0° | 0.8906 | 0.3587° | -0.5772° | -0.7424° | +0.1652° | 21.80° | 87.60° |
| P05 | JIG1-remount03-test-2→JIG4-remount02-test-2 | 0.8593 | 40.0° | 0.8825 | 0.3724° | -0.6383° | -0.8029° | +0.1646° | 29.80° | 87.60° |
| P05 | JIG1-remount03-test-2→JIG4-remount03-test-2 | 0.8482 | 40.0° | 0.8813 | 0.3736° | -0.6617° | -0.8458° | +0.1840° | 8.00° | 87.60° |
| P05 | JIG1-remount03-test-2→JIG5-remount01-test-1 | 0.9929 | 0.0° | 0.9929 | 0.0875° | -0.2093° | -0.1832° | -0.0261° | 8.00° | 56.00° |
| P05 | JIG4-remount01-test-2→JIG4-remount02-test-2 | 0.9992 | 0.0° | 0.9992 | 0.0321° | -0.0611° | -0.0605° | -0.0006° | 8.00° | 0.00° |
| P05 | JIG4-remount01-test-2→JIG4-remount03-test-2 | 0.9976 | 0.0° | 0.9976 | 0.0539° | -0.0845° | -0.1034° | +0.0189° | 13.80° | 0.00° |
| P05 | JIG4-remount01-test-2→JIG5-remount01-test-1 | 0.8500 | 80.0° | 0.8728 | 0.3853° | +0.3679° | +0.5592° | -0.1913° | 106.20° | 23.60° |
| P05 | JIG4-remount02-test-2→JIG4-remount03-test-2 | 0.9993 | 0.0° | 0.9993 | 0.0302° | -0.0234° | -0.0429° | +0.0195° | 21.80° | 0.00° |
| P05 | JIG4-remount02-test-2→JIG5-remount01-test-1 | 0.8339 | 80.0° | 0.8786 | 0.3777° | +0.4290° | +0.6197° | -0.1907° | 98.20° | 23.60° |
| P05 | JIG4-remount03-test-2→JIG5-remount01-test-1 | 0.8228 | 80.0° | 0.8841 | 0.3687° | +0.4524° | +0.6626° | -0.2101° | 120.00° | 23.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
