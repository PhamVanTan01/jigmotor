# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P08 / JIG7

- Eligible runs: 3
- Mean repeat-selection rate: top=80.0%, bottom=66.7%
- Top 5: 293°(+0.6164°), 173°(+0.4847°), 292°(+0.4535°), 26°(+0.4522°), 186°(+0.4480°)
- Bottom 5: 107°(-0.7120°), 67°(-0.6845°), 68°(-0.6658°), 45°(-0.6521°), 37°(-0.6192°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
