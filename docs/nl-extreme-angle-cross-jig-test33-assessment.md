# Test 33: NL extreme-angle cross-jig assessment

Date: 2026-07-30

Inputs: P02/P03/P05/P06/P07, each measured on JIG1 and JIG4. Every group
contains 10 declared `OFFICIAL` + `EligibleForStatistics=1` sweeps; the
precondition sweep is excluded by role rather than by run position.

Generated evidence:

- `analysis-out/test33-nl-extreme-angles/extreme_points.csv`
- `analysis-out/test33-nl-extreme-angles/cross_jig_curve_comparison.csv`
- `analysis-out/test33-nl-extreme-angles/nl_extreme_angle_report.md`

## Coordinate limitation

The MA600 raw zero belongs to each individual sensor/jig. JIG1 raw angle and
JIG4 raw angle are not a shared traceable mechanical coordinate. This
assessment therefore compares sweep-relative one-degree indices and reports
any circular alignment explicitly. It does not claim that equal MA600 raw
codes on different jigs are equal physical angles.

## Results

| Motor | r at zero shift | Best shift | Best r | Δ top-5 mean | Δ bottom-5 mean | Δ robust NL |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| P02 | 0.9841 | 0° | 0.9841 | +0.1636° | −0.1367° | +0.3003° |
| P03 | 0.9664 | 0° | 0.9664 | +0.2147° | +0.1641° | +0.0506° |
| P05 | 0.9619 | 0° | 0.9619 | +0.0665° | −0.3879° | +0.4544° |
| P06 | 0.9695 | 0° | 0.9695 | +0.5120° | +0.3874° | +0.1246° |
| P07 | 0.8782 | 240° | 0.9389 | +0.4069° | +0.0453° | +0.3616° |

The top/bottom points are highly repeatable inside each batch. Across the ten
motor/jig groups, the mean repeat-selection rate of the five points that form
each tail is 78% to 100%. The cross-jig NL difference is therefore systematic,
not selection noise from random SPI or encoder jitter.

For P02, P03, and P06, the same five top angles are recovered on JIG1 and JIG4
after alignment, while the bottom-tail locations differ substantially:

- P02 bottom-tail mean angular distance: 40.2°.
- P03 bottom-tail mean angular distance: 95.6°.
- P06 bottom-tail mean angular distance: 64.0°.

P05 differs in both tails; its +0.458° NL delta is dominated by a 0.389° deeper
negative trough on JIG4. P03 and P06 illustrate the opposite failure mode:
both tails move strongly in the same direction, so robust NL hides most of the
underlying cross-jig change through subtraction.

P07 requires a 240° circular shift for its best correlation. That makes its
comparison sector/orientation-confounded and prevents using it as evidence of
a shared absolute-angle feature without a common mechanical datum.

## Interpretation

The high zero-shift curve correlation for P02/P03/P05/P06 shows a strong
common sweep-relative periodic structure. The jig result is not arbitrary
noise. However, the amplitude and the localized troughs are modified by the
jig/mount/drive combination in a product-dependent way.

This explains why a scalar cross-jig offset cannot correct NL:

```text
ΔNL = Δ(top-5 mean) - Δ(bottom-5 mean)
```

The two terms can add (P02/P05) or largely cancel (P03/P06). A small ΔNL can
therefore coexist with a large change in both physical tails.

The result does not support tuning one global dead-time coefficient until NL
matches. Such tuning could improve the five currently limiting points on one
motor while moving a different limiting tail on another motor. The queued
dead-time builds remain useful as controlled sensitivity experiments, but
their decision metric must be the pointwise differential curve and both tail
components, not robust NL alone.

## Next decision experiment

1. For each queued dead-time coefficient, calculate
   `error_coefficient(angle)-error_baseline(angle)` on the same motor/jig.
2. Check whether the differential is:
   - smooth and shared across products: driver transfer-function candidate;
   - localized at current bottom/top points: breakaway/cogging interaction;
   - changed by remount on the same jig: mounting/sector effect.
3. Run one controlled same-jig remount repeat with fixed torque/orientation
   before assigning the remaining difference to JIG1/JIG4 electronics.
4. Do not select a production coefficient from minimum robust NL alone.
