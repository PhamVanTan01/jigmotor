# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### p02 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=94.0%
- Top 5: 304°(+1.8733°), 344°(+1.8056°), 184°(+1.7422°), 303°(+1.7301°), 264°(+1.7265°)
- Bottom 5: 126°(-1.2694°), 127°(-1.2272°), 77°(-1.2141°), 76°(-1.2057°), 157°(-1.1808°)

### p02 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=78.0%
- Top 5: 304°(+2.0592°), 264°(+1.9701°), 303°(+1.9134°), 344°(+1.8893°), 184°(+1.8641°)
- Bottom 5: 86°(-1.3662°), 87°(-1.3596°), 77°(-1.3489°), 76°(-1.3090°), 36°(-1.2948°)

### p03 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=92.0%, bottom=92.0%
- Top 5: 334°(+1.5239°), 254°(+1.4603°), 294°(+1.4533°), 333°(+1.3770°), 293°(+1.3320°)
- Bottom 5: 187°(-1.2720°), 107°(-1.2367°), 186°(-1.1866°), 147°(-1.1743°), 106°(-1.1687°)

### p03 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=94.0%
- Top 5: 334°(+1.7508°), 294°(+1.7034°), 254°(+1.6290°), 333°(+1.5822°), 293°(+1.5689°)
- Bottom 5: 27°(-1.2062°), 26°(-1.0864°), 28°(-1.0264°), 107°(-0.9719°), 67°(-0.9497°)

### p05 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=94.0%
- Top 5: 264°(+1.4739°), 294°(+1.4686°), 293°(+1.4497°), 263°(+1.4295°), 344°(+1.4250°)
- Bottom 5: 116°(-1.2498°), 196°(-1.2455°), 197°(-1.2034°), 117°(-1.1685°), 76°(-1.1334°)

### p05 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=90.0%
- Top 5: 334°(+1.5668°), 304°(+1.5450°), 333°(+1.5356°), 344°(+1.4736°), 303°(+1.4685°)
- Bottom 5: 76°(-1.7022°), 77°(-1.6878°), 116°(-1.5522°), 78°(-1.5351°), 36°(-1.4696°)

### p06 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=90.0%
- Top 5: 264°(+1.7000°), 284°(+1.6793°), 304°(+1.6263°), 244°(+1.5857°), 263°(+1.5451°)
- Bottom 5: 76°(-1.2817°), 77°(-1.2672°), 96°(-1.2550°), 56°(-1.2456°), 97°(-1.2177°)

### p06 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2542°), 244°(+2.1460°), 284°(+2.1144°), 263°(+2.0949°), 304°(+2.0883°)
- Bottom 5: 156°(-0.9093°), 356°(-0.8924°), 157°(-0.8676°), 357°(-0.8458°), 16°(-0.8194°)

### p07 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=90.0%
- Top 5: 64°(+1.5324°), 224°(+1.4448°), 264°(+1.4124°), 63°(+1.3936°), 24°(+1.3762°)
- Bottom 5: 317°(-1.0730°), 167°(-1.0291°), 316°(-1.0103°), 318°(-0.9430°), 327°(-0.9414°)

### p07 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=96.0%
- Top 5: 264°(+1.9505°), 304°(+1.8714°), 263°(+1.8608°), 274°(+1.7566°), 303°(+1.7511°)
- Bottom 5: 47°(-1.0708°), 37°(-0.9578°), 46°(-0.9479°), 17°(-0.9058°), 48°(-0.8965°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| p02 | JIG1→JIG4 | 0.9841 | 0.0° | 0.9841 | 0.1426° | +0.1636° | -0.1367° | +0.3003° | 0.00° | 40.20° |
| p03 | JIG1→JIG4 | 0.9664 | 0.0° | 0.9664 | 0.1830° | +0.2147° | +0.1641° | +0.0506° | 0.00° | 95.60° |
| p05 | JIG1→JIG4 | 0.9619 | 0.0° | 0.9619 | 0.2040° | +0.0665° | -0.3879° | +0.4544° | 32.00° | 63.80° |
| p06 | JIG1→JIG4 | 0.9695 | 0.0° | 0.9695 | 0.1820° | +0.5120° | +0.3874° | +0.1246° | 0.00° | 64.00° |
| p07 | JIG1→JIG4 | 0.8782 | 240.0° | 0.9389 | 0.2434° | +0.4069° | +0.0453° | +0.3616° | 57.80° | 126.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
