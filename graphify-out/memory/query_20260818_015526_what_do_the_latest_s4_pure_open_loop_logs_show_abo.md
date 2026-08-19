---
type: "review"
date: "2026-08-18T01:55:26.592575+00:00"
question: "What do the latest S4 pure open-loop logs show about NL stability and synchronization between JIG7 and JIG8?"
contributor: "graphify"
outcome: "useful"
---

# Q: What do the latest S4 pure open-loop logs show about NL stability and synchronization between JIG7 and JIG8?

## Answer

Across latest representative pairs for P03, P08, P010, P011 and P013, within-batch stability is strong: OpenLoopNL CV 0.41-1.61% and mean full-curve correlation 0.9976-0.9995. Cross-jig synchronization remains open: JIG7 RawP2P is lower than JIG8 for 5/5 products by 2.09-16.59% (mean -7.96%); cross-jig curve correlation is 0.9430-0.9851 (mean 0.9637), with optimum circular shift 0, so mismatch is not a simple zero/index offset. A36 is exceptionally stable cross-jig, differing only +0.06% to +0.76%, while A1/A2, extrema, and low-order/full-curve amplitude differ. Pure open-loop measurement/capture is credible within a jig, but JIG7/JIG8 are not yet interchangeable for production NL evaluation. No product threshold exists. Next step is frozen-contract designed Gage R&R/variance-components with controlled remounts; do not retune command or apply scalar offset.

## Outcome

- Signal: useful