# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P03 / JIG1-A1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=80.0%
- Top 5: 254°(+1.7069°), 294°(+1.6357°), 334°(+1.5864°), 253°(+1.5528°), 244°(+1.5515°)
- Bottom 5: 107°(-1.0204°), 106°(-0.9882°), 27°(-0.9600°), 67°(-0.9572°), 347°(-0.9333°)

### P03 / JIG1-A2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=93.3%
- Top 5: 254°(+1.7367°), 294°(+1.7082°), 253°(+1.6068°), 244°(+1.5888°), 274°(+1.5705°)
- Bottom 5: 107°(-0.9916°), 347°(-0.9681°), 27°(-0.9609°), 106°(-0.9428°), 346°(-0.9150°)

### P03 / JIG4-B

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=80.0%
- Top 5: 294°(+1.6752°), 334°(+1.6634°), 333°(+1.5197°), 293°(+1.5002°), 254°(+1.4618°)
- Bottom 5: 27°(-1.1441°), 26°(-1.0480°), 107°(-0.9679°), 106°(-0.9618°), 7°(-0.9472°)

### P03 / JIG4-test-1

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 94°(+1.2846°), 334°(+1.2200°), 134°(+1.1777°), 174°(+1.1517°), 93°(+1.0943°)
- Bottom 5: 227°(-1.4186°), 266°(-1.3669°), 267°(-1.3640°), 226°(-1.3486°), 67°(-1.2969°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P03 | JIG1-A1→JIG1-A2 | 0.9986 | 0.0° | 0.9986 | 0.0374° | +0.0352° | +0.0223° | +0.0128° | 12.00° | 16.20° |
| P03 | JIG1-A1→JIG4-B | 0.9896 | 0.0° | 0.9896 | 0.1006° | -0.0482° | -0.0415° | -0.0067° | 25.80° | 12.20° |
| P03 | JIG1-A1→JIG4-test-1 | 0.9374 | 240.0° | 0.9769 | 0.1492° | -0.4253° | -0.3805° | -0.0448° | 38.00° | 48.20° |
| P03 | JIG1-A2→JIG4-B | 0.9863 | 0.0° | 0.9863 | 0.1154° | -0.0834° | -0.0639° | -0.0195° | 37.80° | 12.00° |
| P03 | JIG1-A2→JIG4-test-1 | 0.9317 | 240.0° | 0.9763 | 0.1512° | -0.4604° | -0.4028° | -0.0576° | 50.00° | 32.00° |
| P03 | JIG4-B→JIG4-test-1 | 0.9481 | 240.0° | 0.9753 | 0.1546° | -0.3771° | -0.3390° | -0.0381° | 63.80° | 44.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
