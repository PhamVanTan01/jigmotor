---
type: "query"
date: "2026-08-10T05:04:35.788674+00:00"
question: "Rotor chỉ đáp ứng trung bình khoảng 56.6% command đã phát; tôi muốn biết chính xác thời gian để một điểm đáp ứng command"
contributor: "graphify"
outcome: "useful"
source_nodes: ["CreepToUnwrappedTargetProfiled()", "WaitForPointSettle()", "RampCommandToTarget()", "Motor_SetElectricalPos()"]
---

# Q: Rotor chỉ đáp ứng trung bình khoảng 56.6% command đã phát; tôi muốn biết chính xác thời gian để một điểm đáp ứng command

## Answer

Expanded from original query via graph vocab: [motor, electrical, position, command, response, delay, settle, acquisition, creep, time, sample, target]. The 56.6 percent is displacement response per cumulative correction command at hard point 308, not a percentage of the 360 target points. One one-degree target uses 40 S-curve commands over nominal 39 ms, then WaitForPointSettle requires 8 consecutive 1 ms stable polls, and every creep correction command invokes the same settle routine. DWT ACQ cycle timestamps at 168 MHz show 2952 point transitions across the two V5.7 remount logs: mean 186.958 ms, median 195.998 ms, P95 288 ms. Point 308 stops at hard cap after mean 267.968 ms, range 246.217 to 295.218 ms, but never reaches deadband, so its time-to-target is undefined. Point 148 takes mean 310.718 ms, range 296.219 to 324.218 ms. Exact command-issued to first-deadband timing is not logged; add wrap-safe DWT timestamps for ramp start/end, settle end, creep start, first deadband, capture start/end. Current detection resolution is about 1 ms because settle polling is 1 ms.

## Outcome

- Signal: useful

## Source Nodes

- CreepToUnwrappedTargetProfiled()
- WaitForPointSettle()
- RampCommandToTarget()
- Motor_SetElectricalPos()