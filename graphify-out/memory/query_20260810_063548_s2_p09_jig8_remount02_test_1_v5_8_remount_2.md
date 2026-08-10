---
type: "query"
date: "2026-08-10T06:35:48.528936+00:00"
question: "S2-P09-JIG8-remount02-test-1-v5-8 remount 2"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm", "CreepToUnwrappedTargetProfiled()", "HardcapHoldClassification()", "Preconditioned 10-run repeatability experiment"]
---

# Q: S2-P09-JIG8-remount02-test-1-v5-8 remount 2

## Answer

Expanded via graph vocab: response timing command creep motor point sweep tracking capture hardcap remount repeatability. V5.8 remount02 is timing-complete on p09/JIG8. Official main-360 reach is 1070/1080 (99.074%), down from remount01 1076/1080. Points 177 and 178 persist across all remount02 sweeps and across both remounts; remount02 adds local failures at 88, 98, and 168. Mean time-to-deadband remains essentially unchanged at 183.782 ms, proving no global timing slowdown. Full 360 curves remain strongly correlated r=0.9677 with best shift 0 deg and H36 amplitude/phase stable, but robust NL rises 0.221506 to 0.245877 deg because localized extreme points change. Conclusion: core periodic motor signature and timing are repeatable; endpoint extremes and hard-cap map are mounting-sensitive, while point 177-178 is a persistent motor/control-sector signature.

## Outcome

- Signal: useful

## Source Nodes

- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm
- CreepToUnwrappedTargetProfiled()
- HardcapHoldClassification()
- Preconditioned 10-run repeatability experiment