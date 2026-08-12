---
type: "query"
date: "2026-08-11T10:06:58.734214+00:00"
question: "Should the motor-control algorithm be adjusted to measure PG07 7PP NL accurately, and how should control feedback be separated from measurement?"
contributor: "graphify"
outcome: "useful"
---

# Q: Should the motor-control algorithm be adjusted to measure PG07 7PP NL accurately, and how should control feedback be separated from measurement?

## Answer

Yes, but not by blindly increasing PID or creep budget. Current V5.8 modifies electrical command using MA600 feedback before capturing DATA, so it is a position-response diagnostic and can alter/erase the natural open-loop NL measurand. Split into an official observe-only 7PP open-loop NL mode with deterministic home/phase, stability-only wait, fixed command and 64-sample capture, and a separate closed-loop/creep diagnostic mode. Absolute sensor/motor trueness still requires an independent reference encoder.

## Outcome

- Signal: useful