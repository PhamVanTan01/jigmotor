---
type: "query"
date: "2026-08-10T01:58:30.642562+00:00"
question: "Có đồng ý giữ nguyên kiến trúc một trace buffer và chỉ sửa tài liệu ở điểm 2 không?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["V5.6 — three-stage 16→8→4 response-qualified landing", "V5.4a-DIAG — first fine-budget failure trace", "circular_shift()", "12. Hardware validation"]
---

# Q: Có đồng ý giữ nguyên kiến trúc một trace buffer và chỉ sửa tài liệu ở điểm 2 không?

## Answer

Expanded via graph vocab: [trace, buffer, telemetry, failure, phase, response, gate, extended, circular, sweep, point]. Đồng ý giữ một buffer O(1): SWEEP_CREEP_POINT là dữ liệu acceptance cho mọi điểm, SWEEP_CREEP_STEP chỉ là forensic trace cho một failure được chọn. Không cần ba buffer cho point 8/28/66. Cần sửa doc từ Point 0-359 thành acquisition order Point 1-370 và quy định zero STEP records là hợp lệ khi không có failure. Tuy nhiên gate EXTENDED chỉ theo success rate vẫn có thể pass khi denominator tăng và số failure tuyệt đối tăng; cần thêm ExtendedBudgetExceeded mean. COARSE-tail chưa có định nghĩa/schema telemetry để tính threshold 150 permille. Circular curve-alignment tools không định nghĩa hard-cap failure family; zero-shift nên là measurement hard gate, best-shift chỉ diagnostic.

## Outcome

- Signal: useful

## Source Nodes

- V5.6 — three-stage 16→8→4 response-qualified landing
- V5.4a-DIAG — first fine-budget failure trace
- circular_shift()
- 12. Hardware validation