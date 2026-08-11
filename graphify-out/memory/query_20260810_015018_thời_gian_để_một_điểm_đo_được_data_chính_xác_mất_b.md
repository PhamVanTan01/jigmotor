---
type: "query"
date: "2026-08-10T01:50:18.733096+00:00"
question: "thời gian để một điểm đo được data chính xác mất bao lâu ?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CaptureSweep()", "WaitForPointSettle()", "CreepToUnwrappedTargetProfiled()", "RampCommandToTarget()"]
---

# Q: thời gian để một điểm đo được data chính xác mất bao lâu ?

## Answer

Expanded from original query via graph vocab: [capture, sweep, settle, sample, timing, delay, point, creep, acquisition, motor, ramp]. Một điểm sweep thông thường gồm ramp S-curve khoảng 39 ms, settle tối thiểu 8 ms, creep khoảng 8 ms mỗi iteration, và 64 mẫu MA600 back-to-back khoảng 0-1 ms. Log P03/JIG7 V5.5 cho trung bình toàn sweep khoảng 205-206 ms/điểm; điểm dễ khoảng 48 ms; corrected-point median khoảng 216 ms, P90 khoảng 312 ms. Hard-cap normal-settle khoảng 696 ms ordinary hoặc khoảng 832 ms nếu dùng đủ recovery. Timeout lý thuyết có thể dài hơn nhiều và không được coi là điểm chính xác nếu settle/creep gate fail.

## Outcome

- Signal: useful

## Source Nodes

- CaptureSweep()
- WaitForPointSettle()
- CreepToUnwrappedTargetProfiled()
- RampCommandToTarget()