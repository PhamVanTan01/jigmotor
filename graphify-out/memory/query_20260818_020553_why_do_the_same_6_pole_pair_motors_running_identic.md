---
type: "review"
date: "2026-08-18T02:05:53.409497+00:00"
question: "Why do the same 6-pole-pair motors running identical S4 pure open-loop firmware produce different NL on JIG7 and JIG8?"
contributor: "graphify"
outcome: "useful"
---

# Q: Why do the same 6-pole-pair motors running identical S4 pure open-loop firmware produce different NL on JIG7 and JIG8?

## Answer

The difference is not firmware/config/acquisition: ten representative batches share BuildID Aug 12 2026 16:45:25, MA600 config, power 1.000, 1 ms/40-command S-curve, canonical 64 samples, 360 points, feedback actuation 0, clean transport and settle. Within-batch NL CV is 0.41-1.61% and curve r is 0.9976-0.9995, while paired cross-jig NL gaps are 1.95-12.93 pooled SD and curve r falls to 0.943-0.985. DFT of JIG7-JIG8 difference shows H1+H2 explain 30.9-74.5% of mismatch variance; H36 explains only about 0.0-0.1%, and original A36 differs <=0.76%. Removing H1-H8 diagnostically raises curve r to 0.9895-0.9952. Remount alone changes NL by 0.54-17.47%, proving a strong mount/motor/jig interaction. Best defensible model is motor/electrical component plus jig/sensor geometry plus mounting and interaction; exact separation among sensor silicon, magnet alignment/gap, clamp/bearing load, driver current/supply is impossible from current logs because there is no reference encoder/current/field telemetry. Do not correct official NL by removing harmonics or scalar offset.

## Outcome

- Signal: useful