# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / 111810

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 264°(+1.8207°), 254°(+1.8152°), 263°(+1.7911°), 253°(+1.7597°), 304°(+1.7383°)
- Bottom 5: 196°(-1.1140°), 116°(-1.1009°), 77°(-1.0947°), 197°(-1.0922°), 76°(-1.0838°)

### P05 / 115352

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.1218°), 254°(+2.0951°), 263°(+2.0882°), 294°(+2.0392°), 253°(+2.0253°)
- Bottom 5: 196°(-0.9842°), 356°(-0.9708°), 197°(-0.9289°), 357°(-0.9259°), 156°(-0.7887°)

### P05 / remount01

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2280°), 263°(+2.2002°), 254°(+2.1738°), 294°(+2.1541°), 293°(+2.1171°)
- Bottom 5: 356°(-0.9388°), 357°(-0.9096°), 196°(-0.9065°), 197°(-0.8708°), 156°(-0.7923°)

### P05 / remount02

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 254°(+2.3343°), 264°(+2.3195°), 263°(+2.2924°), 253°(+2.2327°), 294°(+2.1979°)
- Bottom 5: 356°(-0.9570°), 357°(-0.9287°), 196°(-0.8495°), 156°(-0.8163°), 197°(-0.7918°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | 111810→115352 | 0.9789 | 0.0° | 0.9789 | 0.1462° | +0.2889° | +0.1786° | +0.1104° | 2.00° | 40.00° |
| P05 | 111810→remount01 | 0.9821 | 0.0° | 0.9821 | 0.1363° | +0.3896° | +0.2147° | +0.1750° | 10.00° | 40.00° |
| P05 | 111810→remount02 | 0.9781 | 0.0° | 0.9781 | 0.1536° | +0.4904° | +0.2291° | +0.2612° | 2.00° | 40.00° |
| P05 | 115352→remount01 | 0.9981 | 0.0° | 0.9981 | 0.0453° | +0.1007° | +0.0361° | +0.0646° | 8.00° | 0.00° |
| P05 | 115352→remount02 | 0.9955 | 0.0° | 0.9955 | 0.0720° | +0.2014° | +0.0506° | +0.1509° | 0.00° | 0.00° |
| P05 | remount01→remount02 | 0.9974 | 0.0° | 0.9974 | 0.0538° | +0.1007° | +0.0145° | +0.0863° | 8.00° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
