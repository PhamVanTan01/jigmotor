---
type: "query"
date: "2026-08-10T01:23:16.604900+00:00"
question: "Cần phân biệt lặp lại trong cùng tổ hợp và không lặp lại giữa các tổ hợp; thuật toán có vấn đề là bất ổn hay chưa đủ hiệu quả?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.6 — three-stage 16→8→4 response-qualified landing", "Nonlinear Algorithm Audit — toàn bộ finding, theo mục 6.1-6.13"]
---

# Q: Cần phân biệt lặp lại trong cùng tổ hợp và không lặp lại giữa các tổ hợp; thuật toán có vấn đề là bất ổn hay chưa đủ hiệu quả?

## Answer

Expanded from original query via graph vocab: [algorithm, repeatability, failure, motion, response, point, sweep, jig, curve, shift, zero, stability]. Dữ liệu loại trừ mạnh giả thuyết bất ổn ngẫu nhiên nhưng không loại trừ thiếu sót thuật toán có tính hệ thống. P03/JIG8 point347 fail 4/4 với gap -26/-25/-19/-22; P08/JIG8 point308 fail 4/4 với gap -30/-29/-27/-26. Cần gọi đây là deterministic controller-policy limitation hoặc deterministic physical load, và dùng V5.6 để phân biệt qua phase response. Cross-jig chỉ so sánh sau circular alignment vì point index/raw zero không phải datum cơ khí chung.

## Outcome

- Signal: useful

## Source Nodes

- V5.6 — three-stage 16→8→4 response-qualified landing
- Nonlinear Algorithm Audit — toàn bộ finding, theo mục 6.1-6.13