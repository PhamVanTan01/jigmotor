---
type: "query"
date: "2026-08-11T05:17:59.963920+00:00"
question: "v5.8 đã hoàn thành chưa và có thể move qua v5.9 hay v6"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm", "7. Gate hardware đầu tiên", "CreepToUnwrappedTargetProfiled"]
---

# Q: v5.8 đã hoàn thành chưa và có thể move qua v5.9 hay v6

## Answer

Expanded query: [response, timing, measurement, creep, settle, hardware, validation, result, gate, build]. V5.8-TIME-DIAG firmware, build artifact, contract tests and analyzers are complete; contract test passes and multiple real logs have 1484 timing rows with TelemetryComplete=1 and Diagnostic PASS. It is not formally closed against its own hardware plan because the required matched P08/JIG8 two-remount run is absent, so repeated point-308 classification and matched V5.5 regression have not been signed off. V5.8 is diagnostic-only and EligibleForStatistics=0, never a production measurement version. Close it with two FAST3 P08/JIG8 remounts, then use V5.9 for the bounded terminal cap 320->400 one-variable experiment. Reserve V6 for an architectural controller/measurement-contract change, not a budget adjustment. The HOME_PID diagnostic is an orthogonal named diagnostic, not V6. Also regenerate one stale P09 analysis sidecar; current analyzer rechecks it as DIAGNOSTIC PASS with 1484 timing rows.

## Outcome

- Signal: useful

## Source Nodes

- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm
- 7. Gate hardware đầu tiên
- CreepToUnwrappedTargetProfiled