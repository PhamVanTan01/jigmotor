---
type: "query"
date: "2026-08-12T06:36:51.551339+00:00"
question: "Why did the NL project drift from pure Gremsy open-loop, considering ALG-001, ALG-004 and ALG-005?"
contributor: "graphify"
outcome: "corrected"
correction: "Reclassify ALG-005: encoder observation during ramp is not feedback actuation. Reclassify ALG-001 severity for NL scalar: official error metrics remain based on the 64-sample mean; mismatch affects raw/angle traceability. Do not use the 64th sample as representative raw; use the averaged canonical raw/Q16."
---

# Q: Why did the NL project drift from pure Gremsy open-loop, considering ALG-001, ALG-004 and ALG-005?

## Answer

The three findings must be separated. RampCommandToTarget reads MA600 every micro-step only for observation/backtrack telemetry; samples never alter the precomputed S-curve command, so ALG-005 is fixed as observability, not closed-loop control, and open-loop is preserved there. The actual scope drift begins in sweep-point creep, where MA600 gap directly changes commandPos before capture, optimizing endpoint tracking and contaminating the open-loop measurand. ALG-001 is a real legacy traceability mismatch but does not change the error/P2P computed from the 64-sample mean; fix by logging the averaged/canonical mean raw, not the 64th sample. ALG-004 is real architecture debt: canonical remains shadow while legacy is official, but it is governance/cutover debt, not the cause of closed-loop drift. V6 should disable creep, rename ramp feedback as encoder observation, and promote a single canonical open-loop sampler to official schema v6.

## Outcome

- Signal: corrected
- Correction: Reclassify ALG-005: encoder observation during ramp is not feedback actuation. Reclassify ALG-001 severity for NL scalar: official error metrics remain based on the 64-sample mean; mismatch affects raw/angle traceability. Do not use the 64th sample as representative raw; use the averaged canonical raw/Q16.