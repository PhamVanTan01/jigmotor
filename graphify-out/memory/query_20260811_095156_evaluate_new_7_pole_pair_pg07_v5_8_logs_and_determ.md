---
type: "query"
date: "2026-08-11T09:51:56.904228+00:00"
question: "Evaluate new 7 pole-pair PG07 V5.8 logs and determine next diagnostic step"
contributor: "graphify"
outcome: "useful"
---

# Q: Evaluate new 7 pole-pair PG07 V5.8 logs and determine next diagnostic step

## Answer

Geometry and acquisition pass, but motion feasibility fails: 147-159 points fail recurrently across four official sweeps, low-order H2/H6 dominate expected H42, and both files report the same JIG5 UID despite one filename saying JIG1. Do not apply V5.9 terminal correction; diagnose 7PP commutation mapping/home branch and use controlled integer-cycle versus direct-Q16 A-B-A.

## Outcome

- Signal: useful