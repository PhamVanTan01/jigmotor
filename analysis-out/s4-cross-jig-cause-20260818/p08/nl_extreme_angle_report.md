# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P08 / JIG7

- Eligible runs: 9
- Mean repeat-selection rate: top=93.3%, bottom=91.1%
- Top 5: 174°(+1.8569°), 294°(+1.8509°), 254°(+1.7973°), 134°(+1.7756°), 334°(+1.7550°)
- Bottom 5: 37°(-1.2118°), 36°(-1.2056°), 27°(-1.1730°), 67°(-1.1662°), 66°(-1.0387°)

### P08 / JIG8

- Eligible runs: 10
- Mean repeat-selection rate: top=100.0%, bottom=94.0%
- Top 5: 134°(+2.0162°), 254°(+1.8580°), 133°(+1.8321°), 124°(+1.8283°), 214°(+1.8237°)
- Bottom 5: 27°(-1.1298°), 67°(-1.1003°), 347°(-1.0501°), 26°(-0.9891°), 37°(-0.9556°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P08 | JIG7→JIG8 | 0.9851 | 0.0° | 0.9851 | 0.1293° | +0.0632° | +0.1151° | -0.0519° | 54.20° | 17.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
