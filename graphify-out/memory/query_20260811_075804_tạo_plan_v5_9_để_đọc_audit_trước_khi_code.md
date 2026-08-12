---
type: "implementation"
date: "2026-08-11T07:58:04.366617+00:00"
question: "Tạo plan V5.9 để đọc/audit trước khi code"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CreepToUnwrappedTargetProfiled", "V5.7-DIAG — Passive hold after the first V5.5 hard-cap failure", "V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm"]
---

# Q: Tạo plan V5.9 để đọc/audit trước khi code

## Answer

Đã tạo docs/sweep-point-terminal-correction-v5-9-plan.md. Plan khóa V5.9 là EXTENDED-only terminal correction: giữ nguyên V5.5 tới 320 raw, chỉ cho EXTENDED còn ngoài deadband thêm tối đa 80 raw tới ordinary cap 400; BASE giữ 220/320; fine step 4, ordinary max iterations 101, recovery riêng 64/17, trace 120. Thêm sweep safety envelope 10 terminal points/800 ordinary raw, telemetry schema 10, V5.9a timing diagnostic EligibleForStatistics=0, P08 same-mount A/B + independent remount, P09 non-regression, P03 generalization, mount filter P08-only, và điều kiện dừng rõ để mở V6.0 thay vì tiếp tục tăng cap.

## Outcome

- Signal: useful

## Source Nodes

- CreepToUnwrappedTargetProfiled
- V5.7-DIAG — Passive hold after the first V5.5 hard-cap failure
- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm