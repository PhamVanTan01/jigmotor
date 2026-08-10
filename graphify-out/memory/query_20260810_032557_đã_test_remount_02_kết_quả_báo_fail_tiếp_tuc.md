---
type: "query"
date: "2026-08-10T03:25:57.854773+00:00"
question: "đã test remount 02 kết quả báo fail tiếp tuc"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.6 — three-stage 16→8→4 response-qualified landing", "MID-8 không tốt hơn COARSE-16", "CreepToUnwrappedTargetProfiled()"]
---

# Q: đã test remount 02 kết quả báo fail tiếp tuc

## Answer

Expanded from graph vocabulary: remount, repeatability, sweep, creep, response, telemetry, landing, coarse, fine, point, extended, failure. Remount02 independently confirms rejection of the V5.6 MID-8 branch. Point 308 fails in all 4 cycles of remount02 and therefore 8/8 cycles across remount01 plus remount02. Aggregate official MID efficiency is 767 permille versus 962 permille for COARSE-tail, a deficit of 195 permille; remount01 showed the same direction at minus 213 permille. The pre-registered H1 gate required MID to exceed tail by 150 permille, so H1 fails twice and H3 is supported. No crossing, recovery failure, recross, or jump occurs: motion is stable but ineffective. Remount02 official hard-cap mean is 1.33 per run versus 2.00 in remount01, but recurring point 308 remains and final gaps are -44, -40, -26, -39 raw across its four cycles. Robust NL changes from 0.2428 degree in remount01 to 0.2312 degree in remount02; curve correlation is 0.9567 and RMSE 0.0237 degree, confirming mounting modulates severity but does not remove the deterministic hard point. Qualification is invalid again because one official run lost DATA indices 349 through closure; only 2/3 official runs are complete. Stop V5.6, do not run remount03 or tune step 6/2, restore V5.5, fix host capture, then use a separate no-motion-change diagnostic for stored-command deficit/static equilibrium/settle.

## Outcome

- Signal: useful

## Source Nodes

- V5.6 — three-stage 16→8→4 response-qualified landing
- MID-8 không tốt hơn COARSE-16
- CreepToUnwrappedTargetProfiled()