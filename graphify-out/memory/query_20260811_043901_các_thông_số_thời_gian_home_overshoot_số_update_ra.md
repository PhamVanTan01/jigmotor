---
type: "query"
date: "2026-08-11T04:39:01.742003+00:00"
question: "các thông số thời gian home overshoot số update raw command và raw encoder đã có chưa và đo như nào"
contributor: "graphify"
outcome: "useful"
source_nodes: ["NlZeroObservation_t", "MoveToZeroAndCheckDirection", "FinishMoveToZeroObservation", "Motor_MoveToAngle", "Motor_GetCommandedPos"]
---

# Q: các thông số thời gian home overshoot số update raw command và raw encoder đã có chưa và đo như nào

## Answer

Expanded query: [home, zero, observation, time, update, command, raw, encoder, overshoot, settle, telemetry, error]. Firmware already logs HomeDurationMs, HomeUpdateCount, HomeInitialErrorDeg, HomeFinalErrorDeg, HomeInitialCommandRaw and HomeFinalCommandRaw in META/CONTROL_STATE. Duration uses HAL_GetTick around MoveToZeroAndCheckDirection; count is successful Motor_MoveToAngle updates; final success requires 501 consecutive updates inside abs(error)<0.05 deg. Missing for exact retuning: first-band and final-band-entry times, peak overshoot/zero crossings, exact initial/final and per-update encoder unwrapped raw, per-update command/PID terms, saturation/slew counters and cumulative command/encoder travel. StartRaw is after LockStartPosition and is not the home endpoint. V5.8 point timing diagnoses sweep points, not the home PID. Add an O(1) HOME_RESPONSE aggregate from the already accepted encoder sample without extra SPI reads; use DWT timestamps and print after motor disable.

## Outcome

- Signal: useful

## Source Nodes

- NlZeroObservation_t
- MoveToZeroAndCheckDirection
- FinishMoveToZeroObservation
- Motor_MoveToAngle
- Motor_GetCommandedPos