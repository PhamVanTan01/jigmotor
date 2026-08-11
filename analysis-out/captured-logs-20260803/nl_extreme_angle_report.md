# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### UNKNOWN / 114008

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 224°(+1.6581°), 254°(+1.6508°), 294°(+1.6241°), 304°(+1.6099°), 293°(+1.6009°)
- Bottom 5: 116°(-1.2802°), 77°(-1.2088°), 117°(-1.2030°), 76°(-1.1874°), 156°(-1.0712°)

### p03 / 100554

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=92.0%
- Top 5: 334°(+1.7121°), 294°(+1.7058°), 254°(+1.5623°), 333°(+1.5533°), 293°(+1.5443°)
- Bottom 5: 27°(-1.1792°), 26°(-1.0954°), 28°(-0.9917°), 7°(-0.9368°), 67°(-0.9069°)

### p03 / 103321

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=82.0%
- Top 5: 294°(+1.7071°), 334°(+1.6874°), 333°(+1.5583°), 293°(+1.5490°), 254°(+1.5455°)
- Bottom 5: 27°(-1.1779°), 26°(-1.0864°), 28°(-0.9944°), 7°(-0.9378°), 106°(-0.9084°)

### p03 / 112833

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 294°(+1.7764°), 254°(+1.7586°), 244°(+1.6276°), 253°(+1.6211°), 293°(+1.6183°)
- Bottom 5: 106°(-0.9933°), 187°(-0.9781°), 346°(-0.9765°), 347°(-0.9758°), 107°(-0.9582°)

### p05 / 111810

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 264°(+1.8207°), 254°(+1.8152°), 263°(+1.7911°), 253°(+1.7597°), 304°(+1.7383°)
- Bottom 5: 196°(-1.1140°), 116°(-1.1009°), 77°(-1.0947°), 197°(-1.0922°), 76°(-1.0838°)

### p05 / 115352

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.1218°), 254°(+2.0951°), 263°(+2.0882°), 294°(+2.0392°), 253°(+2.0253°)
- Bottom 5: 196°(-0.9842°), 356°(-0.9708°), 197°(-0.9289°), 357°(-0.9259°), 156°(-0.7887°)

### p07 / 112644

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=86.7%
- Top 5: 264°(+2.1705°), 284°(+2.1238°), 244°(+1.9992°), 263°(+1.9791°), 283°(+1.9491°)
- Bottom 5: 56°(-1.2406°), 57°(-1.1624°), 36°(-1.0728°), 37°(-1.0054°), 16°(-0.9929°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| p03 | 100554→103321 | 0.9996 | 0.0° | 0.9996 | 0.0201° | -0.0059° | -0.0036° | -0.0023° | 0.00° | 7.80° |
| p03 | 100554→112833 | 0.9823 | 0.0° | 0.9823 | 0.1316° | +0.0655° | +0.0466° | +0.0190° | 34.00° | 67.60° |
| p03 | 103321→112833 | 0.9827 | 0.0° | 0.9827 | 0.1300° | +0.0715° | +0.0502° | +0.0213° | 34.00° | 59.80° |
| p05 | 111810→115352 | 0.9789 | 0.0° | 0.9789 | 0.1462° | +0.2889° | +0.1786° | +0.1104° | 2.00° | 40.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
