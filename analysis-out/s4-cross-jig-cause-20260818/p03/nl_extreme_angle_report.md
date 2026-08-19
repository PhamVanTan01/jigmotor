# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG7

- Eligible runs: 10
- Mean repeat-selection rate: top=98.0%, bottom=96.0%
- Top 5: 294°(+1.5398°), 174°(+1.4740°), 214°(+1.4442°), 293°(+1.3640°), 334°(+1.3586°)
- Bottom 5: 67°(-1.2877°), 106°(-1.2496°), 66°(-1.2323°), 107°(-1.2046°), 27°(-1.1213°)

### P03 / JIG8

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=96.0%
- Top 5: 254°(+1.8423°), 244°(+1.7597°), 294°(+1.7037°), 253°(+1.6941°), 334°(+1.6836°)
- Bottom 5: 346°(-1.0790°), 106°(-1.0596°), 107°(-1.0397°), 347°(-1.0395°), 27°(-0.9388°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG7→JIG8 | 0.9683 | 0.0° | 0.9683 | 0.1780° | +0.3049° | +0.1874° | +0.1175° | 29.60° | 32.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
