# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG4_batch001

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=92.0%
- Top 5: 334°(+1.7121°), 294°(+1.7058°), 254°(+1.5623°), 333°(+1.5533°), 293°(+1.5443°)
- Bottom 5: 27°(-1.1792°), 26°(-1.0954°), 28°(-0.9917°), 7°(-0.9368°), 67°(-0.9069°)

### P03 / JIG4_batch002

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=82.0%
- Top 5: 294°(+1.7071°), 334°(+1.6874°), 333°(+1.5583°), 293°(+1.5490°), 254°(+1.5455°)
- Bottom 5: 27°(-1.1779°), 26°(-1.0864°), 28°(-0.9944°), 7°(-0.9378°), 106°(-0.9084°)

### P03 / JIG5-remount02

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=93.3%
- Top 5: 254°(+1.8202°), 294°(+1.7610°), 253°(+1.6781°), 244°(+1.6529°), 293°(+1.6517°)
- Bottom 5: 187°(-0.9613°), 347°(-0.9431°), 346°(-0.9358°), 107°(-0.9308°), 186°(-0.9208°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG4_batch001→JIG4_batch002 | 0.9996 | 0.0° | 0.9996 | 0.0201° | -0.0059° | -0.0036° | -0.0023° | 0.00° | 7.80° |
| P03 | JIG4_batch001→JIG5-remount02 | 0.9813 | 0.0° | 0.9813 | 0.1354° | +0.0991° | +0.0843° | +0.0148° | 34.00° | 83.60° |
| P03 | JIG4_batch002→JIG5-remount02 | 0.9821 | 0.0° | 0.9821 | 0.1325° | +0.1050° | +0.0879° | +0.0171° | 34.00° | 75.80° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
