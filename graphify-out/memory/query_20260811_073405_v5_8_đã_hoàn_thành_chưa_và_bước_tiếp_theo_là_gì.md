---
type: "implementation"
date: "2026-08-11T07:34:05.504805+00:00"
question: "V5.8 đã hoàn thành chưa và bước tiếp theo là gì?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CreepToUnwrappedTargetProfiled"]
---

# Q: V5.8 đã hoàn thành chưa và bước tiếp theo là gì?

## Answer

V5.8-TIME-DIAG đã hoàn thành mục tiêu chẩn đoán: telemetry complete 100%, DWT timing hợp lệ, dữ liệu nhiều motor/remount cho thấy time-to-deadband median khoảng 182-198 ms và reached rate trên mount tốt 98.11-99.64%. V5.8 không phải production measurement vì EligibleForStatistics=0 và vẫn giữ motion V5.5/cap 320 raw. Bước tiếp theo phù hợp là V5.9 bounded terminal correction: chỉ cho điểm EXTENDED còn ngoài deadband sau cap 320, mở trần có giới hạn lên 400 raw, giữ power/step/deadband/ramp/crossing/jump guard; validate trên mount tốt P08/JIG8 rồi P09 non-regression và P03 generalization. Không tune theo P08 remount02 lệch tâm; mount precheck H1/H2 cần được dùng làm điều kiện pilot/offline trước khi đủ dữ liệu product-specific để bật hard gate.

## Outcome

- Signal: useful

## Source Nodes

- CreepToUnwrappedTargetProfiled