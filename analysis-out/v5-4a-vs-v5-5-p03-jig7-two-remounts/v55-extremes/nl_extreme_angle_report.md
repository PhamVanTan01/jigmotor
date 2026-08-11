# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / 01

- Eligible runs: 2
- Mean repeat-selection rate: top=30.0%, bottom=90.0%
- Top 5: 180°(+0.1021°), 262°(+0.0984°), 191°(+0.0982°), 341°(+0.0972°), 242°(+0.0962°)
- Bottom 5: 68°(-0.3627°), 67°(-0.3415°), 107°(-0.2808°), 108°(-0.2377°), 147°(-0.2023°)

### P03 / 02

- Eligible runs: 3
- Mean repeat-selection rate: top=40.0%, bottom=100.0%
- Top 5: 141°(+0.1010°), 111°(+0.0990°), 330°(+0.0972°), 83°(+0.0971°), 33°(+0.0950°)
- Bottom 5: 67°(-0.4925°), 68°(-0.4678°), 107°(-0.3252°), 347°(-0.2815°), 108°(-0.2743°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | 01→02 | 0.9692 | 0.0° | 0.9692 | 0.0228° | +0.0007° | -0.0804° | +0.0812° | 79.60° | 32.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
