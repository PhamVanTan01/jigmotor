# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / 01

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+1.9049°), 254°(+1.8865°), 263°(+1.8813°), 253°(+1.8409°), 294°(+1.7346°)
- Bottom 5: 116°(-1.4282°), 196°(-1.3906°), 156°(-1.3765°), 117°(-1.3469°), 76°(-1.3425°)

### P05 / 02

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 264°(+1.9092°), 254°(+1.8714°), 263°(+1.8674°), 253°(+1.8152°), 294°(+1.7170°)
- Bottom 5: 116°(-1.4592°), 156°(-1.4126°), 196°(-1.4111°), 117°(-1.3765°), 157°(-1.3610°)

### P05 / 03

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 264°(+1.8816°), 254°(+1.8611°), 263°(+1.8602°), 253°(+1.8058°), 294°(+1.6895°)
- Bottom 5: 116°(-1.4534°), 156°(-1.4244°), 196°(-1.4170°), 157°(-1.3741°), 117°(-1.3738°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | 01→02 | 0.9998 | 0.0° | 0.9998 | 0.0162° | -0.0136° | -0.0280° | +0.0144° | 0.00° | 16.20° |
| P05 | 01→03 | 0.9997 | 0.0° | 0.9997 | 0.0183° | -0.0299° | -0.0319° | +0.0020° | 0.00° | 16.20° |
| P05 | 02→03 | 0.9999 | 0.0° | 0.9999 | 0.0114° | -0.0163° | -0.0039° | -0.0124° | 0.00° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
