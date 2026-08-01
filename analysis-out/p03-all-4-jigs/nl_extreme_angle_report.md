# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG1

- Eligible runs: 10
- Mean repeat-selection rate: top=92.0%, bottom=92.0%
- Top 5: 334°(+1.5239°), 254°(+1.4603°), 294°(+1.4533°), 333°(+1.3770°), 293°(+1.3320°)
- Bottom 5: 187°(-1.2720°), 107°(-1.2367°), 186°(-1.1866°), 147°(-1.1743°), 106°(-1.1687°)

### P03 / JIG4

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=94.0%
- Top 5: 334°(+1.7508°), 294°(+1.7034°), 254°(+1.6290°), 333°(+1.5822°), 293°(+1.5689°)
- Bottom 5: 27°(-1.2062°), 26°(-1.0864°), 28°(-1.0264°), 107°(-0.9719°), 67°(-0.9497°)

### P03 / JIG5

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=100.0%
- Top 5: 304°(+1.8364°), 324°(+1.7960°), 344°(+1.7318°), 284°(+1.6936°), 303°(+1.6437°)
- Bottom 5: 76°(-1.6498°), 77°(-1.6117°), 56°(-1.5991°), 57°(-1.5425°), 96°(-1.4485°)

### P03 / JIG6

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=88.0%
- Top 5: 334°(+1.8209°), 294°(+1.7881°), 254°(+1.6811°), 293°(+1.6618°), 333°(+1.6574°)
- Bottom 5: 27°(-1.1753°), 26°(-1.1115°), 67°(-1.0045°), 107°(-0.9807°), 106°(-0.9640°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG1→JIG4 | 0.9664 | 0.0° | 0.9664 | 0.1830° | +0.2147° | +0.1641° | +0.0506° | 0.00° | 95.60° |
| P03 | JIG1→JIG5 | 0.7170 | 10.0° | 0.8357 | 0.4243° | +0.3090° | -0.3566° | +0.6656° | 7.80° | 84.20° |
| P03 | JIG1→JIG6 | 0.9702 | 0.0° | 0.9702 | 0.1728° | +0.2896° | +0.1626° | +0.1270° | 0.00° | 80.00° |
| P03 | JIG4→JIG5 | 0.7557 | 30.0° | 0.8831 | 0.3604° | +0.0943° | -0.5207° | +0.6151° | 19.80° | 15.80° |
| P03 | JIG4→JIG6 | 0.9958 | 0.0° | 0.9958 | 0.0649° | +0.0749° | -0.0015° | +0.0764° | 0.00° | 15.60° |
| P03 | JIG5→JIG6 | 0.7662 | 350.0° | 0.8919 | 0.3472° | -0.0194° | +0.5192° | -0.5386° | 7.80° | 20.20° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
