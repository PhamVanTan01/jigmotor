---
type: "query"
date: "2026-08-10T06:53:32.014619+00:00"
question: "S2-P09-JIG8-remount03-test-1-v5-8 remount 3"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm", "CreepToUnwrappedTargetProfiled()", "HardcapHoldClassification()", "Preconditioned 10-run repeatability experiment"]
---

# Q: S2-P09-JIG8-remount03-test-1-v5-8 remount 3

## Answer

Expanded via graph vocab: response timing command creep motor point sweep tracking capture hardcap remount repeatability. Remount03 V5.8 is telemetry-complete. Official main-360 reach is 1071/1080 (99.167%); mean reached time is 184.092 ms. Across three P09/JIG8 remounts, official reach is 3217/3240 (99.290%), mean time 184.311 ms, and point 178 fails 12/12 total sweeps, 9/9 official. Point 177 fails 8/12, while 58, 88, 168 and others are remount-specific. Pairwise full-curve correlations are 0.956-0.981 with best shift 0 deg; A36 and H36 phase remain stable, but robust NL ranges 0.221506-0.245877 deg because extreme points change. Conclusion: timing and core motor periodic signature are repeatable; point 178 is persistent motor/control-sector behavior; scalar NL extremes and auxiliary hard-cap points are mounting-sensitive.

## Outcome

- Signal: useful

## Source Nodes

- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm
- CreepToUnwrappedTargetProfiled()
- HardcapHoldClassification()
- Preconditioned 10-run repeatability experiment