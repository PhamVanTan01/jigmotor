---
type: "codebase"
date: "2026-08-11T04:20:46.236082+00:00"
question: "tại sao dự án lại có kp ki kd lớn hơn Gremsy và ảnh hưởng tới thời gian phản hồi cùng số lượng raw như nào"
contributor: "graphify"
outcome: "useful"
source_nodes: ["PositionController_Update", "Motor_MoveToAngle", "MoveToZeroAndCheckDirection", "gremsyMotorMoveAngle"]
---

# Q: tại sao dự án lại có kp ki kd lớn hơn Gremsy và ảnh hưởng tới thời gian phản hồi cùng số lượng raw như nào

## Answer

Kp current 2.0 vs 0.5 and Ki 0.003 vs 0.0005 are larger, but Kd current 0.3 vs 2.0 is smaller. Gains are discrete per-update values tied to different loop cadence, filtering, slew and output limits. Current home loop uses 2 ms cadence, derivative LPF alpha 0.25, output slew 8 raw/update and output limit 400; Gremsy runs about 1 ms with no derivative LPF/slew and output limit 100. Larger gains can reduce sustained home convergence time but may overshoot; slew limits the first response. Gains do not change encoder resolution 65536 raw/rev, only the electrical-position command delta in raw/update; actual measured raw motion depends on motor dynamics. This PID is home-only, not the 360-point V5.x sweep controller.

## Outcome

- Signal: useful

## Source Nodes

- PositionController_Update
- Motor_MoveToAngle
- MoveToZeroAndCheckDirection
- gremsyMotorMoveAngle