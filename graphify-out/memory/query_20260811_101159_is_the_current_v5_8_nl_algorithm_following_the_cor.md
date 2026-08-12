---
type: "query"
date: "2026-08-11T10:11:59.100971+00:00"
question: "Is the current V5.8 NL algorithm following the correct path for pure Gremsy-like open-loop NL?"
contributor: "graphify"
outcome: "useful"
---

# Q: Is the current V5.8 NL algorithm following the correct path for pure Gremsy-like open-loop NL?

## Answer

Partially. The 360-degree grid, deterministic PWM ramp, stability observation, canonical 64-sample acquisition, error curve, P2P and harmonic tooling are improvements over Gremsy. But V5.8 sweep-point creep reads MA600 and changes the electrical command before DATA capture, so the official path is no longer pure open-loop. Keep creep/V5.x as position-response diagnostic, restore an observe-only official profile, and use RawP2P as the direct Gremsy NL equivalent.

## Outcome

- Signal: useful