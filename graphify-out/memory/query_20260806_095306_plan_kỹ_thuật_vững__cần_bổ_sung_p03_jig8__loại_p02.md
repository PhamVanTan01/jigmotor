---
type: "query"
date: "2026-08-06T09:53:06.368757+00:00"
question: "Plan kỹ thuật vững, cần bổ sung P03/JIG8, loại P02 khỏi pass/fail và làm rõ hai hằng số 96 raw."
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.6 — three-stage 16→8→4 response-qualified landing", "12.4 Pilot A2 — generalization P03/JIG8"]
---

# Q: Plan kỹ thuật vững, cần bổ sung P03/JIG8, loại P02 khỏi pass/fail và làm rõ hai hằng số 96 raw.

## Answer

Expanded from original query via graph vocab: [three, stage, landing, pilot, generalization, regression, threshold, telemetry, jump, response, validation, jig]. Bản plan hiện tại đã có A2 P03/JIG8 generalization và P02 exploratory-only. Bổ sung còn thiếu đã được áp dụng: MID-entry 96 raw là abs live target gap trước command; jump threshold 96 raw là abs settled observed delta sau command. Hai constant, hai telemetry Basis và contract gate phải độc lập dù cùng giá trị ban đầu.

## Outcome

- Signal: useful

## Source Nodes

- V5.6 — three-stage 16→8→4 response-qualified landing
- 12.4 Pilot A2 — generalization P03/JIG8