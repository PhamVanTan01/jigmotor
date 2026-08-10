# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P08 / v5-5

- Eligible runs: 3
- Mean repeat-selection rate: top=20.0%, bottom=40.0%
- Top 5: 131°(+0.0997°), 130°(+0.0982°), 260°(+0.0981°), 161°(+0.0978°), 111°(+0.0971°)
- Bottom 5: 308°(-0.1521°), 350°(-0.1030°), 46°(-0.1025°), 289°(-0.1014°), 208°(-0.0991°)

### P08 / v5-6

- Eligible runs: 2
- Mean repeat-selection rate: top=30.0%, bottom=40.0%
- Top 5: 101°(+0.1128°), 31°(+0.1023°), 213°(+0.1013°), 202°(+0.1005°), 52°(+0.1002°)
- Bottom 5: 308°(-0.2348°), 237°(-0.1061°), 239°(-0.1045°), 319°(-0.1021°), 311°(-0.0994°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P08 | v5-5→v5-6 | 0.9732 | 0.0° | 0.9732 | 0.0187° | +0.0002° | -0.0153° | +0.0155° | 55.20° | 41.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
