---
type: "review"
date: "2026-08-12T09:52:51.514657+00:00"
question: "What did S4 P03 JIG8 open-loop run01 prove, and what blocked qualification?"
contributor: "graphify"
outcome: "corrected"
---

# Q: What did S4 P03 JIG8 open-loop run01 prove, and what blocked qualification?

## Answer

Run01 contained one precondition and ten official-intent sweeps with clean acquisition and highly repeatable open-loop curves, but every schema-v6 META record was truncated at the 1900-byte LogLineLarge boundary. RunRole and EligibleForStatistics were lost/corrupted, so the batch is diagnostic-only and must not qualify S4. Firmware now uses a 2600-byte large-line buffer and emits only LOG_ERROR on overflow; schema-v6 plotting rejects records with missing roles. Replacement artifact: builds/gremsy-open-loop-nl-s4-meta-atomic-pilot-6pp-20260812. All 39 contract tests pass.

## Outcome

- Signal: corrected