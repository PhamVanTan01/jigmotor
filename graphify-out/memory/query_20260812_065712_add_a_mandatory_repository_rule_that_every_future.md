---
type: "query"
date: "2026-08-12T06:57:12.095620+00:00"
question: "Add a mandatory repository rule that every future change must serve pure Gremsy-compatible open-loop NL evaluation"
contributor: "graphify"
outcome: "useful"
---

# Q: Add a mandatory repository rule that every future change must serve pure Gremsy-compatible open-loop NL evaluation

## Answer

Added a Mandatory project objective section to root AGENTS.md and RULE 0 to docs/open-loop-nl-direction-correction-handoff-2026-08-12.md. Every firmware/tool/schema/build/test/hardware-validation change must state its open-loop NL purpose and measurement-contract impact, be classified OPEN_LOOP_MEASUREMENT or DIAGNOSTIC_ONLY, prohibit encoder feedback actuation in the official path, invalidate rather than rescue unstable points, isolate feedback diagnostics with OfficialOpenLoopNL=0 and EligibleForStatistics=0, use one canonical point mean, and validate the full 360-point curve rather than a single scalar.

## Outcome

- Signal: useful