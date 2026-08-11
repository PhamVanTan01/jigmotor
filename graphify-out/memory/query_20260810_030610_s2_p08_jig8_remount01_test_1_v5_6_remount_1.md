---
type: "query"
date: "2026-08-10T03:06:10.097181+00:00"
question: "S2-P08-JIG8-remount01-test-1-v5-6 remount 1"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.6 — three-stage 16→8→4 response-qualified landing", "CreepToUnwrappedTargetProfiled()", "CaptureSweep()"]
---

# Q: S2-P08-JIG8-remount01-test-1-v5-6 remount 1

## Answer

Expanded from graph vocabulary: sweep, creep, response, telemetry, landing, coarse, fine, phase, point, baseline, extended, failure. P08/JIG8 V5.6 has complete creep POINT/STEP/RESPONSE telemetry in all four cycles, no crossing/recovery/jump, but MID efficiency is about 751 permille versus 964 permille for matched COARSE-tail, a deficit of about 213 permille; MID opposite-response rate is also worse. H1 is rejected and H3 is supported. The recurring point-308 hard-cap failure remains 4/4 and final gap worsens from about -26 to -30 raw on matched V5.5 to -37 to -44 raw on V5.6; official failures increase from 1.33/run to 2.00/run. V5.6 therefore regresses endpoint effectiveness while increasing iterations about 11 percent. Measurement verdict is invalid because official run 3 lost 89 DATA records and contains a fused MOTION/DATA line, even though firmware acquisition and creep telemetry are clean. Two complete official curves show provisional robust NL +0.0155 degree, zero-shift correlation 0.9732, RMSE 0.0187 degree, and a deeper negative extreme at point 308. Recommendation: reject the MID-8 branch per the locked decision tree, return to V5.5, and rerun the same V5.6 binary only if a clean capture is needed for documentary confirmation.

## Outcome

- Signal: useful

## Source Nodes

- V5.6 — three-stage 16→8→4 response-qualified landing
- CreepToUnwrappedTargetProfiled()
- CaptureSweep()