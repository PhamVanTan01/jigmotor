# Plan sửa trình tự alignment/enable cho Motor Control C0

> Trạng thái source: A1 và firmware A2 alignment-only đã được triển khai dưới
> profile `CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1`; hardware gate A2 vẫn đang chờ.
> Hướng dẫn test: `docs/control-a2-alignment-hardware-test.md`.

## 1. Mục tiêu và phạm vi

Plan này sửa nguyên nhân rung/giật trước khi tiếp tục đánh giá trajectory 1°.
Không tuning `Kp/Ki/Kd`, không tăng power để che lỗi, không thay Measurement
firmware và không mở target 5°/10° trong cùng phase.

Rollback source hiện tại:

```text
branch: codex/motion-control-v2-dma
commit: dcfb6c2ed4e24b9ddab24c503c38c8cf084d4b88
profile: CONTROL_C0_OPEN_LOOP_1DEG_V1
```

## 2. Evidence phần cứng đã có

Mười lần nhấn đều fail trước trajectory 1°; mọi run có `EvidenceCount=0`:

| Result | Số lần | Đặc điểm |
| --- | ---: | --- |
| `HOME_WRONG_WAY` | 5 | dừng sau 8–10 ms, encoder nhảy khoảng 11–25° |
| `HOME_TIMEOUT` | 5 | chạy 5.000 ms, final error còn khoảng 0,9–2,6° |

Hai kiểu result gần như xen kẽ theo vị trí rotor sau lần dừng trước. Idle noise
khi motor đứng yên trở lại khoảng P2P 0,03–0,04°, StdDev 0,01°, nên chưa có
evidence chỉ ra SPI/DMA là nguyên nhân rung.

## 3. Root-cause cần kiểm chứng

Chuỗi hiện tại:

```text
Motor_Disable
-> Motor_ResetControlSession
-> controller.commandedPosition = 0
-> PWM command = phase 0, power 0
-> tính home command quanh phase 0
-> Motor_Enable ngay ở power 35%
```

Rotor có thể đang ở electrical phase khác phase 0. Enable trực tiếp tại 35% tạo
phase/power discontinuity và kéo rotor đột ngột sang equilibrium gần nhất.

Đây là giả thuyết mạnh từ log, nhưng chưa được coi là kết luận cuối cho tới khi
firmware ghi được encoder raw, command phase, power và response trong từng tick
của alignment. Không được lấy `encoderRaw % electricalCycle` làm command seed
ngay khi chưa xác định phase offset thật của motor/magnet/encoder.

## 4. Kiến trúc state machine đích

```text
IDLE
  -> PRECHECK_OFF
  -> CAPTURE_INITIAL_OFF
  -> PRIME_PHASE_POWER_ZERO
  -> ENABLE_AT_ZERO_POWER
  -> ALIGN_POWER_RAMP
  -> ALIGN_HOLD
  -> MOTOR_OFF_REPORT                 (profile alignment-only)

Sau khi alignment-only đạt hardware gate:

ALIGN_HOLD
  -> PRIME_HOME_CONTROLLER
  -> HOME_CONTROL
  -> LOCAL_ZERO_CAPTURE
  -> MOTOR_OFF_REPORT                 (profile alignment+home)

Sau khi alignment+home đạt hardware gate:

LOCAL_ZERO_CAPTURE
  -> C0_OPEN_LOOP_1DEG
  -> MOTOR_OFF
  -> REPORT
```

Mọi fault/abort từ mọi state phải đi qua đúng một common exit:

```text
FAULT_OR_ABORT -> Motor_Disable -> snapshot output state -> UART report
```

## 5. Nguyên tắc kỹ thuật bắt buộc

1. Preload phase khi motor off và power bằng 0.
2. Enable driver khi power vẫn bằng 0.
3. Power chỉ tăng bằng ramp absolute-tick; không có bước nhảy 0 -> 35%.
4. Controller command phải được seed bằng phase đã align; không reset cứng về 0
   ngay trước khi đóng home loop.
5. UART bị cấm từ trước `Motor_Enable()` tới sau `Motor_Disable()`.
6. Encoder acquisition có context riêng cho alignment/home/C0 trajectory.
7. Không catch-up bằng các command liên tiếp sau deadline miss.
8. Mỗi power/travel envelope là profile ID và artifact riêng.
9. Measurement image giữ nguyên hàm home, motion, DMA và measurement math.

## 6. Phase A0 — đóng băng failure baseline

### Công việc

- Ghi summary 10 run hiện tại vào hardware evidence manifest.
- Lưu commit, HEX SHA-256, JigID, MotorID và điều kiện gá.
- Đóng băng các giá trị hiện tại: power 35%, home period 2 ms, timeout 5 s.
- Thêm regression fixture cho parser với cả `HOME_WRONG_WAY` và
  `HOME_TIMEOUT` không có `CONTROL_C0_DATA`.

### Gate

- Analyzer phải báo được `HOME_ONLY_FAILURE`; không throw chỉ vì
  `EvidenceCount=0`.
- Không diễn giải health counter của trajectory bằng 0 thành home SPI pass.

## 7. Phase A1 — tách reset software và prime output

### API dự kiến

```c
void Motor_ResetControllerState(void);
bool Motor_PrimeControlSession(int32_t commandedPositionRaw,
                               float initialPower);
```

`Motor_PrimeControlSession()` chỉ hợp lệ khi output disabled và
`initialPower == 0`. Nó phải:

- reset integral, derivative, last error và acquisition tracker;
- seed `commandedPosition` bằng phase được caller cung cấp;
- reset `lastOutput` về 0 để correction đầu không có history;
- preload PWM phase với power 0;
- không enable motor.

`Motor_ResetControlSession()` cũ tiếp tục tồn tại cho Measurement và giữ behavior
đã qualification. API prime mới chỉ compile trong `JIG_APP_CONTROL`.

### Contract

- Prime với output đang enable phải fail và disable motor.
- Prime với power khác 0 phải fail.
- Snapshot sau prime phải có đúng command seed, power 0, output disabled và
  controller history bằng 0.
- Measurement ELF không link API/state alignment.

## 8. Phase A2 — firmware alignment-only đầu tiên

Profile đầu tiên:

```text
CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1
```

Workflow:

1. Motor off, precheck STATUS và đọc baseline encoder.
2. Prime command phase 0 với power 0.
3. Enable tại power 0.
4. Ramp power 0 -> 10% trong 500 ms, command phase giữ nguyên.
5. Hold 100 ms.
6. Motor off, sau đó mới dump toàn bộ evidence.

Giá trị 10% là pilot an toàn, không phải power tối ưu. Nếu không đủ torque thì
tạo profile P15 riêng sau review; không sửa cùng artifact thành 15/20/35%.

### Evidence 1 kHz

Mỗi tick lưu:

- state/sequence/scheduled tick/actual tick;
- encoder raw và unwrapped relative raw;
- command electrical phase;
- commanded power;
- delta raw, filtered velocity và acceleration;
- SPI latency, loop cycles, PWM counter at `/CS`;
- travel từ baseline;
- abort/fault reason.

### Safety envelope pilot

- active duration tối đa 750 ms;
- travel limit ban đầu 5°;
- max single-sample step pilot 0,25° tại cadence 1 ms;
- ba deadline miss liên tiếp: safe-stop;
- bất kỳ SPI failure/jump rejection/stale feedback: safe-stop;
- nhấn nút lần hai: operator abort.

`TRAVEL_LIMIT` trong pilot là evidence hữu ích rằng rotor cần alignment travel lớn
hơn; nó không được tự động xử lý bằng cách nới limit trong cùng firmware.

### Hardware matrix

- Ít nhất 10 lần start.
- Trước mỗi run, motor off và đặt rotor ở nhiều vị trí khác nhau trong một
  electrical cycle, nếu gá cho phép.
- Không chạy liên tục khi có rung mạnh hoặc motor nóng.

### Gate A2

- Không còn bước enable làm encoder nhảy 10–25° trong 8–10 ms.
- Power monotonic, không command discontinuity, `CorrectionRaw=0`.
- Zero deadline/SPI/evidence failure.
- Có thể kết thúc `OK`, `NO_TORQUE` hoặc `TRAVEL_LIMIT`; nhưng không được có
  visible jerk, wrong-way burst hoặc unsafe velocity.

## 9. Phase A3 — xác định quan hệ encoder/electrical phase

Chỉ thực hiện sau A2 không rung.

Từ nhiều lần fixed-phase alignment, tính circular offset:

```text
phaseOffsetRaw = commandPhaseRaw
               - (encoderRaw mod MOTOR_COUNT_PER_ELECTRICAL_CYCLE)
```

Phải xử lý modulo và six-pole-pair ambiguity đúng miền electrical cycle. Nếu
offset sau settle không tạo thành một cụm ổn định giữa nhiều vị trí ban đầu,
không được seed phase trực tiếp từ encoder; tiếp tục dùng soft fixed-phase
alignment ở mỗi run.

Nếu offset ổn định, tạo profile mới:

```text
CONTROL_A3_ENCODER_SEEDED_ALIGN_P10_V1
```

Trong profile này:

```text
seedPhase = Motor_ElectricalOffset(initialEncoderRaw) + calibratedPhaseOffset
```

vẫn phải preload ở power 0, enable ở power 0 và ramp power. Encoder-derived seed
không được phép bỏ qua power ramp.

### Gate A3

- Offset circular có spread nhỏ, không chia thành nhiều cluster mâu thuẫn.
- Encoder-seeded alignment làm travel/velocity nhỏ hơn fixed-phase alignment.
- 10/10 run không visible jerk và không direction burst.

## 10. Phase A4 — alignment + home, chưa chạy 1°

Profile:

```text
CONTROL_A4_BUMPLESS_ALIGN_HOME_V1
```

Sau `ALIGN_HOLD`:

1. Giữ nguyên phase/power đang align.
2. Seed `controller.commandedPosition` bằng đúng phase command hiện tại.
3. Reset integral/derivative/acquisition nhưng không reset PWM phase.
4. Bắt đầu home update 2 ms bằng gains hiện tại.
5. Buffer toàn bộ 500 ms đầu; sau đó có thể decimate nhưng không UART.
6. Motor off rồi report.

### Sửa direction detector

`HOME_WRONG_WAY` không đánh giá từ 4–5 sample đầu. Dùng cửa sổ thời gian cố định
và filtered error slope:

- bỏ qua khoảng alignment-to-home transient đã định nghĩa;
- so sánh signed progress trên cửa sổ, không chỉ `abs(error)` của một sample;
- vẫn safe-stop ngay nếu vượt travel/velocity hard limit.

### Hai mức home result

```text
HOME_STABLE_LOCAL
HOME_ABSOLUTE_SETTLED
```

- `HOME_STABLE_LOCAL`: encoder đã ổn định và nằm trong safety envelope; cho phép
  dùng vị trí đó làm local zero cho plant test tương đối.
- `HOME_ABSOLUTE_SETTLED`: đạt yêu cầu absolute error nghiêm ngặt, dành cho phase
  qualification chính xác sau này.

Không nới điều kiện 0,15° rồi gọi đó là absolute pass. Các run hiện tại dừng ở
0,9–2,6° phải được phân loại là static home error, không phải alignment success.

### Gate A4

- 10/10 run không visible jerk.
- Không `HOME_WRONG_WAY` trong transient đầu.
- Command phase liên tục qua biên `ALIGN_HOLD -> HOME_CONTROL`.
- Home trace đủ để tách stiction/torque limit/controller convergence.
- Chưa đổi `Kp/Ki/Kd` hoặc power trong phase này.

## 11. Phase A5 — khôi phục C0 open-loop 1°

Chỉ sau A4 đạt gate:

1. Alignment và home hoàn tất.
2. Chụp local-zero baseline encoder.
3. Chạy lại S-curve 1°, 40 ms, correction bằng 0.
4. Hold 250 ms, motor off, dump 291 point.

### Gate A5

- 10/10 run có `EvidenceCount=291`.
- Zero alignment/home/acquisition/deadline/travel failure.
- Không visible jerk ở enable hoặc transition sang trajectory.
- Tính được rise time, settle, overshoot, backtrack và hold RMS.

Sau gate này mới quyết định:

- mở target 5° để tiếp tục plant characterization; hoặc
- chuyển C1 hardware timing/C2 P-only correction.

## 12. File dự kiến thay đổi

```text
Core/Inc/app_mode.h
Core/Inc/control_engine.h
Core/Inc/motor.h
Core/Inc/motor_pwm.h
Core/Src/control_engine.c
Core/Src/motor.c
Core/Src/motor_pwm.c
scripts/analyze_control_c0.ps1
scripts/test_control_alignment_contract.ps1
scripts/test_analyze_control_c0.ps1
docs/control-c0-hardware-test.md
docs/CODEX_HANDOFF_MOTION_V2_DMA.md
```

Nếu số state/evidence tiếp tục tăng, tách thành:

```text
Core/Inc/control_alignment.h
Core/Src/control_alignment.c
```

thay vì tiếp tục làm `control_engine.c` lớn hơn.

## 13. Contract/build gate mỗi commit

- Release Measurement: 0 error, 0 warning.
- Control image: 0 error, 0 warning.
- Toàn bộ existing tests PASS.
- Measurement ELF không chứa alignment engine/trace/profile string.
- Static call-order contract:

```text
Motor_Disable
-> capture initial encoder
-> prime phase at power 0
-> Motor_Enable
-> monotonic power ramp
-> active workflow
-> Motor_Disable
-> UART report
```

- Fault injection tại mọi state phải kết thúc output disabled.
- Mọi buffer CCM `NOLOAD` phải được clear trước run và có capacity assertion.

## 14. Điều không được làm trong plan này

- Không tăng ngay power 35% lên 100%.
- Không tăng timeout để biến timeout thành pass.
- Không giảm/đổi `HOME_SETTLE_ERROR` rồi gọi là absolute accuracy.
- Không seed từ `encoderRaw % cycle` khi phase offset chưa được chứng minh.
- Không tuning nhiều tham số PID/power/trajectory trong cùng artifact.
- Không dùng Measurement image để thử alignment experiment.

## 15. Definition of Done

Alignment/enable fix chỉ hoàn tất khi:

1. Có artifact/profile riêng cho từng gate A2, A3, A4, A5.
2. 10/10 alignment+home run không visible jerk ở nhiều vị trí ban đầu.
3. Không phase/power discontinuity tại enable và transition sang home.
4. Hardware log có encoder/phase/power/timing evidence, không chỉ summary.
5. C0 1° tạo đủ 291 point trên 10/10 run.
6. Measurement contracts và numeric behavior không đổi.
7. Mọi failure/abort đều motor-off trước UART.
