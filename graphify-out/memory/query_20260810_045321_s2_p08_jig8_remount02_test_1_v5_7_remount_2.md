---
type: "query"
date: "2026-08-10T04:53:21.252277+00:00"
question: "S2-P08-JIG8-remount02-test-1-v5-7 remount 2"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.7-DIAG — Passive hold after the first V5.5 hard-cap failure", "HardcapHoldClassification()", "CreepToUnwrappedTargetProfiled()"]
---

# Q: S2-P08-JIG8-remount02-test-1-v5-7 remount 2

## Answer

Expanded from original query via graph vocab: [hardcap, hold, creep, sweep, settle, acquisition, classification, response, telemetry, gap, static, remount]. Remount02 is capture-complete on the same V5.7 build. Point 308 still reaches EXTENDED hard cap in 4/4 cycles; point 148 additionally reaches hard cap in 2/4 cycles, so total failures are 6 versus 4 in remount01. All BASE escalations succeed. Selected hold results are 3 STATIC_WITHIN_SETTLE_BAND and 1 RELAXES_TOWARD_TARGET exactly at the 9-raw threshold; across both remounts the selected-hold result is 7/8 static, while point 308 fails 8/8. Point-308 final gap is -40.75 raw mean in remount02 versus -37.5 raw in remount01. Therefore passive dwell is not the general lever; next diagnostic should be a bounded targeted terminal correction or extra command budget with safety and iteration guards. Scalar NL from V5.7 remains non-official because EligibleForStatistics is forced to zero.

## Outcome

- Signal: useful

## Source Nodes

- V5.7-DIAG — Passive hold after the first V5.5 hard-cap failure
- HardcapHoldClassification()
- CreepToUnwrappedTargetProfiled()