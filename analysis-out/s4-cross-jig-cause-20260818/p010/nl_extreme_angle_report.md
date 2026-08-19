# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P010 / JIG7

- Eligible runs: 10
- Mean repeat-selection rate: top=90.0%, bottom=84.0%
- Top 5: 304°(+1.8434°), 264°(+1.7875°), 303°(+1.6930°), 344°(+1.6310°), 263°(+1.6043°)
- Bottom 5: 77°(-1.3220°), 157°(-1.3107°), 126°(-1.3103°), 76°(-1.3070°), 127°(-1.3044°)

### P010 / JIG8

- Eligible runs: 10
- Mean repeat-selection rate: top=96.0%, bottom=80.0%
- Top 5: 304°(+2.3332°), 264°(+2.2060°), 303°(+2.1847°), 263°(+2.0746°), 344°(+2.0323°)
- Bottom 5: 206°(-1.1016°), 207°(-1.0849°), 46°(-1.0784°), 77°(-1.0761°), 47°(-1.0609°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P010 | JIG7→JIG8 | 0.9708 | 0.0° | 0.9708 | 0.1892° | +0.4543° | +0.2296° | +0.2247° | 0.00° | 47.60° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
