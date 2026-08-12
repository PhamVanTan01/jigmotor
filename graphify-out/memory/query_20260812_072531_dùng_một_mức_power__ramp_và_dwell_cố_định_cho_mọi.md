---
type: "query"
date: "2026-08-12T07:25:31.339931+00:00"
question: "dùng một mức power, ramp và dwell cố định cho mọi motor; vì tôi có nhiều motor với nhiều cặp cực khác nhau thì dùng chung 1 thuật toán này để đánh giá hay là mỗi motor sẽ có 1 thuật toán riêng biệt ?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["motor_config.h", "MotorPwm_SetElectricalPos()", "Motor_GetPolePairs()", "nonlinear_test.c", "gremsyMotorMovePos()"]
---

# Q: dùng một mức power, ramp và dwell cố định cho mọi motor; vì tôi có nhiều motor với nhiều cặp cực khác nhau thì dùng chung 1 thuật toán này để đánh giá hay là mỗi motor sẽ có 1 thuật toán riêng biệt ?

## Answer

Expanded from original query via graph vocabulary: [motor, pole, electrical, mechanical, power, ramp, settle, profile, nonlinear, gremsy, position, pwm]. Kết luận: dùng một thuật toán/measurement contract open-loop chung, nhưng dùng profile tham số cố định theo họ sản phẩm hoặc số cặp cực; không tạo thuật toán hay tự tune theo từng motor serial. Giữ chung lưới 360 điểm, sampler, công thức Error/NL, gate hợp lệ và cấm feedback thay command. Profile phải khai báo trước polePairs, ánh xạ góc điện, harmonic kỳ vọng, power, ramp và giới hạn settle/dwell. Cùng một PWM power không đồng nghĩa cùng torque/current ở motor khác điện trở/Kt, nên chỉ dùng một bộ số cho mọi họ motor sau khi qualification chứng minh tất cả đều bám ổn định và không quá nhiệt. Với 6 pole-pairs dùng 12 poles và ripple H36; với 7 pole-pairs dùng 14 poles và ripple H42. So sánh NL trực tiếp giữa các họ chỉ hợp lệ nếu cùng excitation contract; nếu dùng profile khác thì dùng limit riêng theo họ và ghi ProfileID.

## Outcome

- Signal: useful

## Source Nodes

- motor_config.h
- MotorPwm_SetElectricalPos()
- Motor_GetPolePairs()
- nonlinear_test.c
- gremsyMotorMovePos()