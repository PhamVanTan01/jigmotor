---
type: "query"
date: "2026-08-11T01:51:44.573210+00:00"
question: "so sánh thuật toán điều khiển của gremsy và của dự án; các thông số pid được có trong gremsyProfiles_PM1505.h"
contributor: "graphify"
outcome: "useful"
source_nodes: ["position_controller.c", "PositionController_Init()", "RampCommandToTarget()", "CreepToUnwrappedTargetProfiled()", "gremsyMotor.c"]
---

# Q: so sánh thuật toán điều khiển của gremsy và của dự án; các thông số pid được có trong gremsyProfiles_PM1505.h

## Answer

Expanded from original query via vocab: [gremsy, motor, pid, controller, control, position, pwm, angle, ramp, creep]. Hai hệ thống cùng dùng PID gia tăng vị trí điện cho bước home, không phải FOC hay torque PID. Gremsy PM1505: Kp=0.5 Ki=0.0005 Kd=2.0 I-limit=5 output-limit=100 error-band=0.1 deg; integral vượt giới hạn bị reset 0, D không lọc, không slew, error không wrap, currentPos int16 làm mất phần lẻ, không reset state rõ ràng và điều kiện settle thiếu fabs. Dự án: Kp=2.0 Ki=0.003 Kd=0.3 I-limit=5 output-limit=400 derivativeAlpha=0.25 slew=8 error-band=0.05 deg; clamp integral, D lọc, wrap error, float accumulation, reset và verify state, acquisition checked, loop 2 ms và timeout. Không được copy gain trực tiếp vì cả hai không nhân dt và chạy ở cadence/filter khác nhau. PID chỉ ảnh hưởng home/reference/closure; sweep NL Gremsy là step 256 raw + fixed delay, còn dự án là S-curve 40 tick + settle và build V5.x có live-gap creep.

## Outcome

- Signal: useful

## Source Nodes

- position_controller.c
- PositionController_Init()
- RampCommandToTarget()
- CreepToUnwrappedTargetProfiled()
- gremsyMotor.c