---
type: "architecture"
date: "2026-08-12T08:57:53.976979+00:00"
question: "Close S0-S3 for the 6-pole-pair Gremsy-compatible pure open-loop NL measurement path"
contributor: "graphify"
outcome: "useful"
---

# Q: Close S0-S3 for the 6-pole-pair Gremsy-compatible pure open-loop NL measurement path

## Answer

S0-S3 closed at software-contract level: compile-time profile isolation forbids encoder-derived actuation in official open-loop; schema v6 promotes one 64-sample canonical Q16 window per point as the only official source; stability-only capture preserves open-loop command history; RawP2P/OpenLoopNL is primary, robust P2P supporting; diagnostic V5.x remains schema-v5 and statistically ineligible. Release build passes and all 38 tests pass. Hardware A/B/A pilot S5 remains required before production qualification.

## Outcome

- Signal: useful