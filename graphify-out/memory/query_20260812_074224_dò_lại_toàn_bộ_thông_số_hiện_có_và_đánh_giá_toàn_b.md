---
type: "query"
date: "2026-08-12T07:42:24.087382+00:00"
question: "dò lại toàn bộ thông số hiện có và đánh giá toàn bộ thuật toán có thể sử dụng chung thuật toán nào để đánh giá cho motor vì hiện tại motor của chúng tôi chỉ khác nhau số cặp cực, và kích thước motor tôi nghĩ không ảnh hưởng đến NL"
contributor: "graphify"
outcome: "useful"
source_nodes: ["nonlinear_test.c", "motor_config.h", "MotorPwm_SetElectricalPos()", "RampCommandToTarget()", "WaitForPointSettle()", "gremsyMotorMovePos()"]
---

# Q: dò lại toàn bộ thông số hiện có và đánh giá toàn bộ thuật toán có thể sử dụng chung thuật toán nào để đánh giá cho motor vì hiện tại motor của chúng tôi chỉ khác nhau số cặp cực, và kích thước motor tôi nghĩ không ảnh hưởng đến NL

## Answer

Expanded from project graph vocabulary: [nonlinear, motor, electrical, pole, power, ramp, settle, sample, harmonic, error, profile, gremsy, pwm, creep, controller, measurement, open, loop]. Audit verdict: one common Gremsy-compatible open-loop NL algorithm is appropriate; motor size should not select a different algorithm. PolePairs is the required geometry input. Keep common mechanical grid, error formula, canonical 64-sample acquisition, stability criteria, validity and primary RawP2P. However current firmware is not yet a universal production implementation: default shifted-reversal A0 is hard-gated to 6PP in the main tree; electrical-cycle mapping uses ceil(65536/p); fixed harmonic model is tailored to H36/H72/H108 rather than dynamic H(6p); OfficialResultSource remains LEGACY/shadow duplicated; legacy headline/final average uses RobustP2P instead of Gremsy RawP2P; and per-point settle validity currently includes a +/-5 degree target-proximity gate, which can invalidate stable large-error points instead of measuring them. Power=1.0, S-curve 40 ticks x 1ms, stability 9 raw x 8 polls, timeout 100ms and 64 samples are reasonable common candidates, but common power is unqualified because PWM fraction is not equal physical current/torque across different resistance/Kt/size. Size is not in the NL formula and inertia should disappear after settle, but resistance, torque stiffness, cogging/friction ratio, heating and mounting can affect whole-system open-loop NL. Use one algorithm plus a pole-pair parameter, qualify the same global excitation on smallest/largest motors; only create versioned family excitation profiles if no common safe stable envelope exists, without changing the NL formula.

## Outcome

- Signal: useful

## Source Nodes

- nonlinear_test.c
- motor_config.h
- MotorPwm_SetElectricalPos()
- RampCommandToTarget()
- WaitForPointSettle()
- gremsyMotorMovePos()