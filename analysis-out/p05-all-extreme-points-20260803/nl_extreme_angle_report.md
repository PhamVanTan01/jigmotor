# NL extreme-angle and cross-jig curve analysis

Only statistically eligible sweeps are included. `DATA.Error` is used with its logged sign; robust NL is unchanged by reversing the sign.

> MA600 raw zero is local to each sensor/jig. Equal raw codes across two jigs are not a shared physical angle. The comparison below uses sweep-relative angle and reports any circular alignment explicitly.

## Extreme points on each batch-mean curve

### P05 / 20260803-111810_UNKNOWN_JIG1_batch001_complete

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 264°(+1.8207°), 254°(+1.8152°), 263°(+1.7911°), 253°(+1.7597°), 304°(+1.7383°)
- Bottom 5: 196°(-1.1140°), 116°(-1.1009°), 77°(-1.0947°), 197°(-1.0922°), 76°(-1.0838°)

### P05 / 20260803-115352_UNKNOWN_JIG1_batch001_complete

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.1218°), 254°(+2.0951°), 263°(+2.0882°), 294°(+2.0392°), 253°(+2.0253°)
- Bottom 5: 196°(-0.9842°), 356°(-0.9708°), 197°(-0.9289°), 357°(-0.9259°), 156°(-0.7887°)

### P05 / S1-P05-JIG4-remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.7179°), 303°(+1.6814°), 254°(+1.6282°), 264°(+1.6255°), 334°(+1.6211°)
- Bottom 5: 77°(-1.7434°), 76°(-1.7413°), 36°(-1.6049°), 37°(-1.5953°), 78°(-1.5373°)

### P05 / S1-P05-JIG4-remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=86.7%, bottom=100.0%
- Top 5: 304°(+1.6608°), 303°(+1.5984°), 334°(+1.5889°), 254°(+1.5815°), 224°(+1.5420°)
- Bottom 5: 76°(-1.8186°), 77°(-1.8076°), 37°(-1.6392°), 36°(-1.6380°), 78°(-1.6211°)

### P05 / S1-P05-JIG4-remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=93.3%, bottom=100.0%
- Top 5: 304°(+1.6201°), 334°(+1.5829°), 303°(+1.5636°), 333°(+1.5539°), 254°(+1.5378°)
- Bottom 5: 76°(-1.8810°), 77°(-1.8392°), 36°(-1.6973°), 78°(-1.6723°), 37°(-1.6493°)

### P05 / S2-P05-JIG1-remount01

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2280°), 263°(+2.2002°), 254°(+2.1738°), 294°(+2.1541°), 293°(+2.1171°)
- Bottom 5: 356°(-0.9388°), 357°(-0.9096°), 196°(-0.9065°), 197°(-0.8708°), 156°(-0.7923°)

### P05 / S2-P05-JIG1-remount01-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.3821°), 263°(+2.3492°), 254°(+2.3336°), 294°(+2.2717°), 253°(+2.2691°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9125°), 196°(-0.8723°), 197°(-0.8237°), 156°(-0.7966°)

### P05 / S2-P05-JIG1-remount02

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 254°(+2.3343°), 264°(+2.3195°), 263°(+2.2924°), 253°(+2.2327°), 294°(+2.1979°)
- Bottom 5: 356°(-0.9570°), 357°(-0.9287°), 196°(-0.8495°), 156°(-0.8163°), 197°(-0.7918°)

### P05 / S2-P05-JIG1-remount02-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=93.3%
- Top 5: 263°(+2.3948°), 264°(+2.3926°), 254°(+2.3842°), 294°(+2.3215°), 253°(+2.3067°)
- Bottom 5: 356°(-0.9650°), 357°(-0.9390°), 156°(-0.8285°), 196°(-0.7812°), 197°(-0.7788°)

### P05 / S2-P05-JIG1-remount03-test-2

- Eligible runs: 3
- Mean repeat-selection rate: top=100.0%, bottom=100.0%
- Top 5: 264°(+2.2934°), 263°(+2.2603°), 254°(+2.2333°), 294°(+2.2148°), 293°(+2.1659°)
- Bottom 5: 356°(-0.9509°), 357°(-0.9128°), 196°(-0.9074°), 197°(-0.8755°), 156°(-0.8636°)

## Same-motor cross-jig comparison

Tail deltas below are differences between the batch means of each run's own top-5/bottom-5 means, so `ΔNL = Δtop-5 - Δbottom-5` matches the per-run robust-NL definition exactly.

| Motor | Pair | r at 0° | Best shift | Best r | Aligned RMSE | Δtop-5 | Δbottom-5 | ΔNL | Top angle distance | Bottom angle distance |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→20260803-115352_UNKNOWN_JIG1_batch001_complete | 0.9789 | 0.0° | 0.9789 | 0.1462° | +0.2889° | +0.1786° | +0.1104° | 2.00° | 40.00° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount01-test-2 | 0.9336 | 0.0° | 0.9336 | 0.2824° | -0.1286° | -0.5462° | +0.4175° | 24.20° | 71.60° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount02-test-2 | 0.9231 | 0.0° | 0.9231 | 0.3035° | -0.1897° | -0.6066° | +0.4169° | 27.80° | 71.60° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount03-test-2 | 0.9168 | 0.0° | 0.9168 | 0.3142° | -0.2132° | -0.6495° | +0.4364° | 38.00° | 71.60° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount01 | 0.9821 | 0.0° | 0.9821 | 0.1363° | +0.3896° | +0.2147° | +0.1750° | 10.00° | 40.00° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount01-test-2 | 0.9771 | 0.0° | 0.9771 | 0.1601° | +0.5362° | +0.2271° | +0.3091° | 2.00° | 40.00° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount02 | 0.9781 | 0.0° | 0.9781 | 0.1536° | +0.4904° | +0.2291° | +0.2612° | 2.00° | 40.00° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount02-test-2 | 0.9740 | 0.0° | 0.9740 | 0.1708° | +0.5750° | +0.2384° | +0.3366° | 2.00° | 40.00° |
| P05 | 20260803-111810_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount03-test-2 | 0.9814 | 0.0° | 0.9814 | 0.1419° | +0.4486° | +0.1962° | +0.2523° | 10.00° | 40.00° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount01-test-2 | 0.8618 | 40.0° | 0.8859 | 0.3644° | -0.4176° | -0.7247° | +0.3071° | 13.80° | 87.60° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount02-test-2 | 0.8451 | 40.0° | 0.8784 | 0.3769° | -0.4787° | -0.7852° | +0.3065° | 21.80° | 87.60° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S1-P05-JIG4-remount03-test-2 | 0.8351 | 40.0° | 0.8782 | 0.3765° | -0.5021° | -0.8281° | +0.3260° | 15.60° | 87.60° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount01 | 0.9981 | 0.0° | 0.9981 | 0.0453° | +0.1007° | +0.0361° | +0.0646° | 8.00° | 0.00° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount01-test-2 | 0.9921 | 0.0° | 0.9921 | 0.0969° | +0.2472° | +0.0485° | +0.1987° | 0.00° | 0.00° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount02 | 0.9955 | 0.0° | 0.9955 | 0.0720° | +0.2014° | +0.0506° | +0.1509° | 0.00° | 0.00° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount02-test-2 | 0.9907 | 0.0° | 0.9907 | 0.1052° | +0.2860° | +0.0599° | +0.2262° | 0.00° | 0.00° |
| P05 | 20260803-115352_UNKNOWN_JIG1_batch001_complete→S2-P05-JIG1-remount03-test-2 | 0.9946 | 0.0° | 0.9946 | 0.0778° | +0.1596° | +0.0177° | +0.1419° | 8.00° | 0.00° |
| P05 | S1-P05-JIG4-remount01-test-2→S1-P05-JIG4-remount02-test-2 | 0.9992 | 0.0° | 0.9992 | 0.0321° | -0.0611° | -0.0605° | -0.0006° | 8.00° | 0.00° |
| P05 | S1-P05-JIG4-remount01-test-2→S1-P05-JIG4-remount03-test-2 | 0.9976 | 0.0° | 0.9976 | 0.0539° | -0.0845° | -0.1034° | +0.0189° | 13.80° | 0.00° |
| P05 | S1-P05-JIG4-remount01-test-2→S2-P05-JIG1-remount01 | 0.8747 | 320.0° | 0.8913 | 0.3566° | +0.5183° | +0.7608° | -0.2425° | 21.80° | 87.60° |
| P05 | S1-P05-JIG4-remount01-test-2→S2-P05-JIG1-remount01-test-2 | 0.8761 | 320.0° | 0.9016 | 0.3415° | +0.6648° | +0.7732° | -0.1084° | 13.80° | 87.60° |
| P05 | S1-P05-JIG4-remount01-test-2→S2-P05-JIG1-remount02 | 0.8664 | 320.0° | 0.8894 | 0.3605° | +0.6190° | +0.7753° | -0.1563° | 13.80° | 87.60° |
| P05 | S1-P05-JIG4-remount01-test-2→S2-P05-JIG1-remount02-test-2 | 0.8715 | 320.0° | 0.8997 | 0.3450° | +0.7036° | +0.7846° | -0.0809° | 13.80° | 87.60° |
| P05 | S1-P05-JIG4-remount01-test-2→S2-P05-JIG1-remount03-test-2 | 0.8757 | 320.0° | 0.8906 | 0.3587° | +0.5772° | +0.7424° | -0.1652° | 21.80° | 87.60° |
| P05 | S1-P05-JIG4-remount02-test-2→S1-P05-JIG4-remount03-test-2 | 0.9993 | 0.0° | 0.9993 | 0.0302° | -0.0234° | -0.0429° | +0.0195° | 21.80° | 0.00° |
| P05 | S1-P05-JIG4-remount02-test-2→S2-P05-JIG1-remount01 | 0.8584 | 320.0° | 0.8841 | 0.3689° | +0.5794° | +0.8213° | -0.2419° | 29.80° | 87.60° |
| P05 | S1-P05-JIG4-remount02-test-2→S2-P05-JIG1-remount01-test-2 | 0.8594 | 320.0° | 0.8936 | 0.3558° | +0.7259° | +0.8337° | -0.1078° | 21.80° | 87.60° |
| P05 | S1-P05-JIG4-remount02-test-2→S2-P05-JIG1-remount02 | 0.8499 | 320.0° | 0.8805 | 0.3755° | +0.6801° | +0.8358° | -0.1557° | 21.80° | 87.60° |
| P05 | S1-P05-JIG4-remount02-test-2→S2-P05-JIG1-remount02-test-2 | 0.8546 | 320.0° | 0.8917 | 0.3592° | +0.7647° | +0.8451° | -0.0803° | 21.80° | 87.60° |
| P05 | S1-P05-JIG4-remount02-test-2→S2-P05-JIG1-remount03-test-2 | 0.8593 | 320.0° | 0.8825 | 0.3724° | +0.6383° | +0.8029° | -0.1646° | 29.80° | 87.60° |
| P05 | S1-P05-JIG4-remount03-test-2→S2-P05-JIG1-remount01 | 0.8483 | 320.0° | 0.8838 | 0.3686° | +0.6028° | +0.8642° | -0.2614° | 8.00° | 87.60° |
| P05 | S1-P05-JIG4-remount03-test-2→S2-P05-JIG1-remount01-test-2 | 0.8477 | 320.0° | 0.8921 | 0.3577° | +0.7493° | +0.8766° | -0.1273° | 15.60° | 87.60° |
| P05 | S1-P05-JIG4-remount03-test-2→S2-P05-JIG1-remount02 | 0.8386 | 320.0° | 0.8788 | 0.3775° | +0.7035° | +0.8787° | -0.1751° | 15.60° | 87.60° |
| P05 | S1-P05-JIG4-remount03-test-2→S2-P05-JIG1-remount02-test-2 | 0.8428 | 320.0° | 0.8903 | 0.3609° | +0.7881° | +0.8879° | -0.0998° | 15.60° | 87.60° |
| P05 | S1-P05-JIG4-remount03-test-2→S2-P05-JIG1-remount03-test-2 | 0.8482 | 320.0° | 0.8813 | 0.3736° | +0.6617° | +0.8458° | -0.1840° | 8.00° | 87.60° |
| P05 | S2-P05-JIG1-remount01→S2-P05-JIG1-remount01-test-2 | 0.9957 | 0.0° | 0.9957 | 0.0716° | +0.1465° | +0.0124° | +0.1341° | 8.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01→S2-P05-JIG1-remount02 | 0.9974 | 0.0° | 0.9974 | 0.0538° | +0.1007° | +0.0145° | +0.0863° | 8.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01→S2-P05-JIG1-remount02-test-2 | 0.9953 | 0.0° | 0.9953 | 0.0749° | +0.1853° | +0.0237° | +0.1616° | 8.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01→S2-P05-JIG1-remount03-test-2 | 0.9978 | 0.0° | 0.9978 | 0.0500° | +0.0589° | -0.0184° | +0.0773° | 0.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01-test-2→S2-P05-JIG1-remount02 | 0.9979 | 0.0° | 0.9979 | 0.0487° | -0.0458° | +0.0020° | -0.0478° | 0.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01-test-2→S2-P05-JIG1-remount02-test-2 | 0.9988 | 0.0° | 0.9988 | 0.0366° | +0.0388° | +0.0113° | +0.0275° | 0.00° | 0.00° |
| P05 | S2-P05-JIG1-remount01-test-2→S2-P05-JIG1-remount03-test-2 | 0.9989 | 0.0° | 0.9989 | 0.0368° | -0.0876° | -0.0308° | -0.0568° | 8.00° | 0.00° |
| P05 | S2-P05-JIG1-remount02→S2-P05-JIG1-remount02-test-2 | 0.9979 | 0.0° | 0.9979 | 0.0492° | +0.0846° | +0.0093° | +0.0753° | 0.00° | 0.00° |
| P05 | S2-P05-JIG1-remount02→S2-P05-JIG1-remount03-test-2 | 0.9988 | 0.0° | 0.9988 | 0.0354° | -0.0418° | -0.0329° | -0.0089° | 8.00° | 0.00° |
| P05 | S2-P05-JIG1-remount02-test-2→S2-P05-JIG1-remount03-test-2 | 0.9982 | 0.0° | 0.9982 | 0.0459° | -0.1264° | -0.0422° | -0.0842° | 8.00° | 0.00° |

Interpretation guard: high correlation after a shift supports a common periodic shape, but does not by itself assign that shape to the motor. Low correlation or large aligned extreme distances indicates a jig/mount/drive interaction or a localized event not preserved across the two setups.
