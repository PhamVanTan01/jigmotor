# Kế hoạch triển khai dual-image trên STM32F405

Plan này triển khai kiến trúc trong
`docs/stm32f405-dual-mode-system-design.md` theo từng thay đổi có thể build,
test và rollback độc lập.

## Trạng thái triển khai (2026-07-16)

- **P0 hoàn tất:** baseline commit, artifact hash, size/RAM inventory và rollback
  procedure đã lưu trong `docs/baselines/2026-07-16-motion-v2-dma/manifest.md`.
- **P1 hoàn tất ở mức source/build gate:** `JIG_APP_MODE` là compile-time
  identity; hai image được clean-build độc lập; startup có mode, profile,
  source ID và profile fingerprint; 17/17 test scripts PASS.
- **Control C0 đã triển khai source/build gate:** home dùng controller hiện tại
  với power giới hạn 35%, sau đó chạy open-loop S-curve đúng 1° ở cadence 1 kHz,
  giữ 250 ms và dump evidence khi motor đã off. Chưa đạt hardware gate nên chưa
  được mở 5°/10° và chưa được xem là closed-loop tracking controller.
- **Measurement giữ nguyên thuật toán:** vẫn dùng Motion V2, SPI DMA wrapper,
  lưới 1 độ và measurement math hiện tại.
- **P2 trở đi chưa triển khai:** chỉ thay memory/RTOS budget sau khi có hardware
  high-water evidence; không giảm heap dựa trên ước lượng tĩnh.

## 1. Nguyên tắc thực hiện

1. Motor Control và Measurement là hai image độc lập.
2. Mỗi phase chỉ thay một nhóm yếu tố có thể ảnh hưởng kết quả.
3. Không tuning PID trong phase tái cấu trúc resource/RTOS.
4. Không thay measurement math khi tạo mode boundary.
5. Mỗi phase có contract test, build gate, hardware gate và rollback point.
6. Không merge phase tiếp theo khi phase trước chưa có evidence.

## 2. Deliverable cuối

```text
Build/Control/jigmotor_control.elf
Build/Control/jigmotor_control.hex
Build/Measurement/jigmotor_measurement.elf
Build/Measurement/jigmotor_measurement.hex

Core/Inc/app/app_mode.h
Core/Inc/app/build_manifest.h
Core/Inc/platform/resource_contract.h
Core/Inc/control/control_engine.h
Core/Inc/control/control_types.h
Core/Inc/measurement/measurement_engine.h
Core/Inc/safety/safety_service.h

Core/Src/control/control_engine.c
Core/Src/control/control_feedback.c
Core/Src/control/control_trajectory.c
Core/Src/control/control_report.c
Core/Src/measurement/measurement_engine.c
Core/Src/safety/safety_service.c

scripts/build_control.ps1
scripts/build_measurement.ps1
scripts/test_mode_isolation_contract.ps1
scripts/test_resource_budget.ps1
scripts/analyze_control_log.ps1
```

Đây là cấu trúc đích. Giai đoạn đầu có thể giữ source phẳng để CubeIDE không bị
phá; interface/ownership phải được thiết lập trước khi di chuyển file vật lý.

## 3. Phase P0 — đóng băng baseline (hoàn tất)

### Công việc

- Tag/ghi commit SHA của branch trước refactor.
- Lưu Debug và Release map/size/stack-usage.
- Lưu hash của measurement HEX hiện tại.
- Chạy 12 contract scripts hiện có.
- Thu một log hardware xác nhận startup, DMA transport và measurement profile.
- Ghi silicon `DEV_ID/REV_ID`, clock tree, compiler version và optimization.

### Deliverable

- `docs/baselines/<date>/manifest.md`.
- `size-sections.txt`, `largest-symbols.txt`, `stack-usage.txt`.
- binary SHA-256.

### Gate

- Debug/Release: 0 error, 0 warning.
- 12/12 contract PASS.
- Có thể rebuild cùng source ra binary hash xác định hoặc giải thích được field
  thay đổi do build timestamp.

### Rollback

- Commit baseline là điểm rollback tuyệt đối.

## 4. Phase P1 — build identity và compile-time isolation (hoàn tất source/build gate)

### Công việc

- Thêm `JIG_APP_MODE` bắt buộc từ build profile.
- Tạo hai profile build nhưng chưa đổi behavior Measurement.
- Mỗi startup log một record `BUILD_MANIFEST` chứa:
  - app mode;
  - firmware/profile ID;
  - git SHA/build ID;
  - clock frequencies;
  - SPI transport;
  - motor geometry;
  - config CRC.
- Control image ban đầu chỉ self-test và motor-disabled smoke test; chưa chạy
  controller mới.
- Measurement image chạy đúng behavior hiện tại.

### Contract test

- Build thiếu `JIG_APP_MODE` phải fail.
- Build mode sai phải fail.
- Measurement link map không chứa `ControlEngine_Run`.
- Control link map không chứa `ComputeNonlinear`/official result buffers.
- Hai artifact phải có tên khác nhau.

### Gate

- Measurement output numeric/source contract không đổi.
- Control image không thể enable motor ngoài smoke test có guard.

## 5. Phase P2 — memory map và RTOS observability

### Công việc

- Tách linker region `SRAM1`, `SRAM2`, `CCMRAM`.
- Thêm section `.dma_sram`, `.ccm_control`, `.ccm_analysis`.
- Chuyển static DMA buffers vào SRAM2.
- Thêm linker assertion cho range/headroom.
- Log:
  - `xPortGetFreeHeapSize()`;
  - minimum-ever-free heap;
  - stack high-water từng task;
  - section sizes từ build script.
- Không giảm `configTOTAL_HEAP_SIZE` trước khi có high-water data.
- Sau data, chuyển task/queue quan trọng sang static allocation và đặt heap riêng
  cho từng image.

### Budget đề xuất sau profiling

- Control heap: 24–32 KB.
- Measurement heap: 32–48 KB.
- SRAM tổng còn ≥20% headroom.

### Contract test

- Parse map và fail nếu `.dma_sram` ngoài SRAM2.
- Fail nếu main SRAM/CCM vượt budget.
- Fail nếu DMA symbol nằm 0x10000000..0x1000FFFF.

### Hardware gate

- Chạy ít nhất một full workflow mỗi image.
- Không stack overflow/malloc failure.
- stack và minimum heap đáp ứng performance contract.

## 6. Phase P3 — shared platform và ownership

### Công việc

Thiết lập interface nhỏ, không refactor math:

- `MotorPwmPort`: enable/disable/set/get command.
- `EncoderTransactionPort`: một raw/status transaction.
- `MonotonicClock`: DWT cycles và conversion.
- `SafetyPort`: request stop/fault snapshot.
- `BuildManifest`.

Thêm owner token/state:

```text
NONE -> CONTROL
NONE -> MEASUREMENT
owner -> NONE chỉ sau Motor_Disable + transport idle
```

Default/UI task không gọi trực tiếp motor hoặc SPI khi owner khác `NONE`.

### Gate

- Fault injection owner collision phải safe-stop.
- UART không phát trong motor-enabled interval.
- Existing Measurement contract vẫn PASS.

## 7. Phase C0 — Control image quan sát plant, chưa đóng loop (source/build gate hoàn tất)

Mục tiêu là thu transfer behavior trước khi tuning.

### Workflow

1. Home bằng controller hiện tại.
2. Chạy reference S-curve tới các target giới hạn trước: 0, 1, 5, 10°.
3. Sau đó mở rộng 0..30°, 0..90° và cuối cùng 0..360°.
4. Ghi encoder response ở 1 kHz nhưng không correction.
5. Motor off rồi mới dump evidence.

### Evidence

- target/actual/error theo tick;
- PWM phase command và power;
- velocity/acceleration ước lượng;
- settle time;
- overshoot/backtrack;
- SPI latency, loop latency, PWM counter tại `/CS`;
- correction luôn bằng 0 trong C0.

### Safety gate

- Giới hạn travel, active duration và max error theo từng test nhỏ.
- Stop khi angle jump, sensor stale, deadline miss liên tiếp hoặc operator abort.
- Không chạy full turn trước khi các test nhỏ đạt.

### Output

- Plant report dùng để chọn controller rate, correction clamp và initial Kp.

## 8. Phase C1 — hardware-timed control pipeline

### Công việc

- Chọn hardware timer 1 kHz sau pin/peripheral conflict audit; ưu tiên TIM5 nếu
  board không dùng.
- ISR chỉ tăng sequence và notify ControlTask.
- Thay SPI busy-wait ở Control image bằng start/completion state machine hoặc
  direct notification; Measurement image giữ transport đã qualification.
- Mỗi control cycle:
  1. kiểm sequence/deadline;
  2. lấy feedback;
  3. unwrap/validate;
  4. tính reference;
  5. controller update;
  6. update PWM preload;
  7. append evidence.

### Timing budget 1 ms

| Stage | Budget khởi đầu |
| --- | ---: |
| ISR wake-up/jitter | 20 us worst |
| SPI transaction + decode | 50 us |
| unwrap/filter/controller | 100 us |
| PWM update/evidence | 50 us |
| tổng execution | 500 us worst |
| reserve | ≥500 us |

Budget là gate, không phải dự đoán cuối. Log DWT stage duration để chỉnh lại.

### Gate

- 100,000 cycle control test không missed deadline.
- Không SPI error, evidence overflow hoặc unsafe PWM update.
- UART disabled trong active run.

## 9. Phase C2 — controller P-only

### Công việc

- Feedforward exact command + bounded P correction.
- `Ki=0`, `Kd=0`.
- Tuning Kp theo firmware image riêng; power/PWM không đổi.
- Test step nhỏ trước, sau đó grid 1°.

### Theo dõi

- RMS/max steady error;
- overshoot/backtrack;
- correction distribution;
- saturation ratio;
- settle time;
- deadline/feedback health.

### Gate

- Không oscillation hoặc sustained saturation.
- Tracking cải thiện rõ so với open-loop baseline.
- Safe-stop hoạt động khi fault injection.

## 10. Phase C3 — damping và static-error removal

### Thứ tự

1. Thêm filtered D hoặc velocity feedback để giảm overshoot.
2. Chốt damping trước.
3. Thêm Ki nhỏ để thắng cogging/static torque error.
4. Thêm conditional integration/anti-windup.
5. Chỉ sau đó tối ưu correction slew/trajectory duration.

Mỗi mục là một firmware/profile ID. Không chỉnh Kp/Kd/Ki/power cùng lúc.

### Acceptance hai cấp

- Screening: tracking RMS ≤0.25°, max ≤0.5°.
- Target: RMS ≤0.1°, max ≤0.2° nếu sensor/mechanical system cho phép.
- Zero deadline miss, zero transport failure, zero evidence overflow.

Nếu target không đạt, phân loại giới hạn do sensor noise, cogging, driver power,
mechanical backlash hoặc controller; không tiếp tục tăng gain mù quáng.

## 11. Phase M0 — khóa Measurement image

### Công việc

- Tạo `MeasurementEngine` wrapper quanh implementation hiện tại trước khi tách
  file lớn.
- Compile/link guard cấm control engine/controller sweep.
- Giữ `Motor_MoveToAngle()` chỉ ở home nếu đó vẫn là measurement contract.
- Trong open-loop sweep/capture chỉ `MeasurementMotionPort` được ghi PWM.
- Reset encoder/control/transport context tại physical-test boundary.
- Giữ nguyên 371/360/64, target, settle, validity và analysis.

### Numeric gate

- Host fixture phải bit-identical hoặc trong tolerance đã đóng băng cho mọi
  official field.
- `MeasurementValid` equation không đổi.
- Link map chứng minh không có control correction symbol/table/state.

## 12. Phase M1 — measurement timing optimization độc lập

Chỉ thực hiện sau khi M0 ổn định:

- chuẩn hóa DMA transaction metadata;
- xem correlation sample với TIM1 PWM phase;
- nếu cần, scheduled sampler dùng hardware time source;
- giữ sample count/math không đổi;
- A/B polling vs DMA hoặc back-to-back vs scheduled từng yếu tố một.

Không dùng kết quả Control Mode để sửa official point angle.

## 13. Phase O1 — tối ưu CPU sau profiling

Chỉ tối ưu hàm xuất hiện trong cycle profile:

- thay `sinf()` PWM bằng LUT/interpolation nếu MotorPwm là bottleneck;
- dùng single-precision FPU, loại `double` khỏi active path;
- precompute constant scaling;
- dùng CMSIS-DSP cho non-official/offline analysis trước;
- giảm format string/stack bằng binary evidence và motor-off reporter;
- compile out feature không thuộc image.

Mỗi tối ưu phải có:

- cycle count trước/sau;
- output equivalence test;
- map size trước/sau;
- hardware A/B nếu ảnh hưởng PWM hoặc sampling.

## 14. Phase S1 — safety và watchdog

### Công việc

- Thêm `SafetyService` dùng chung.
- Fault taxonomy: sensor timeout, SPI error burst, angle jump, deadline miss,
  correction saturation, owner violation, ring overflow, stack/heap fault.
- Motor disable primitive không phụ thuộc scheduler.
- IWDG được refresh bởi supervisor chỉ khi owner task báo heartbeat hợp lệ.
- Log reset reason và last fault snapshot ở boot kế tiếp nếu có vùng retention
  phù hợp.

### Gate

- Fault injection từng loại đưa motor off trong latency đã đo.
- Không auto re-enable sau fault.
- Watchdog không che root cause; snapshot phải được lưu trước reset nếu có thể.

## 15. Phase Q — qualification cuối

### Control image

- Ít nhất 10 run không tháo jig cho mỗi controller profile ứng viên.
- Test nhiều vùng góc và cả direction cần thiết.
- Báo cáo tracking, settle, correction, saturation, thermal trend và deadline.
- A/B/A profile cũ/mới trên cùng hardware.

### Measurement image

- Một precondition + 10 official runs.
- Không tháo jig giữa run.
- So baseline RMS_AC, pointwise repeatability, tracking, closure, A36 và timing.
- Xác nhận hash/profile/transport ID trước khi gộp dataset.

### Release gate

- Build/test/resource/safety/qualification đều PASS.
- Handoff document cập nhật commit SHA và artifact hash.
- Không còn TODO có thể thay measurement meaning.

## 16. Thứ tự commit đề xuất

1. `docs: define dual-image STM32F405 architecture`
2. `build: add explicit control and measurement profiles`
3. `platform: split SRAM regions and enforce DMA placement`
4. `platform: add resource and timing telemetry`
5. `platform: enforce motor and SPI ownership`
6. `control: add open-loop plant characterization`
7. `control: add hardware-timed feedback pipeline`
8. `control: add bounded position controller`
9. `measurement: enforce control-free official capture`
10. `safety: add fault supervisor and watchdog contract`

Không gom các bước trên vào một commit lớn. Mỗi commit phải build được và có test
đúng phạm vi.

## 17. Definition of done

Plan hoàn tất khi:

- clone sạch build được hai HEX độc lập;
- mỗi HEX tự nhận diện mode/profile/hash;
- control loop đạt timing/tracking gate bằng hardware evidence;
- measurement giữ numeric/data contract và không link controller correction;
- SRAM còn ≥20% headroom, stack/heap đạt gate;
- DMA buffer placement được linker kiểm tra;
- safety fault injection đạt;
- tài liệu handoff đủ để Codex máy khác không trộn hai mode.
