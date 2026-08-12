---
type: "architecture"
date: "2026-08-11T07:39:12.608073+00:00"
question: "V6.0 có nhiệm vụ gì và tiến độ hiện tại để đạt firmware chuẩn đo NL là bao nhiêu phần trăm?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Phase C1 — hardware-timed control pipeline", "Nonlinear Log Schema v6 Contract", "V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm"]
---

# Q: V6.0 có nhiệm vụ gì và tiến độ hiện tại để đạt firmware chuẩn đo NL là bao nhiêu phần trăm?

## Answer

Repo hiện chưa có motion-plan V6.0 được khóa; các tài liệu v6 hiện có chủ yếu là Nonlinear Log Schema v6, không phải thuật toán motion V6. Nếu V5.9 bounded terminal correction thất bại trên mount hợp lệ, V6.0 nên là kiến trúc điều khiển chuyển động deterministic: scheduler hardware-timed khoảng 1 kHz, feedback position liên tục có dt-aware/anti-windup/saturation telemetry, tách controller khỏi cửa sổ capture chính thức, và không mặc định dùng FOC. Mức sẵn sàng hiện tại ước lượng khoảng 65-70% cho firmware production đo WHOLE_SYSTEM_COMMAND_TRACKING NL: acquisition/config/tooling mạnh, canonical 360-point và timing đã có, motion đạt khoảng 98-99.6% trên mount tốt; còn thiếu V5.9, mount gate product-specific, schema-v6 official promotion, 10-run/remount/cross-jig Gage R&R và release qualification. Với mục tiêu intrinsic motor/sensor NL theo góc cơ khí thật, firmware hiện tại không thể đạt 100% nếu không có reference encoder độc lập.

## Outcome

- Signal: useful

## Source Nodes

- Phase C1 — hardware-timed control pipeline
- Nonlinear Log Schema v6 Contract
- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm