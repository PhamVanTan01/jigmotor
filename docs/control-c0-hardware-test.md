# Control C0 — hardware test 1°

## Mục tiêu

Firmware `CONTROL_C0_OPEN_LOOP_1DEG_V1` đo phản ứng thật của motor trước khi
đóng vòng tracking hoặc tuning PID. Nó dùng PID hiện tại chỉ để home về encoder
0°, sau đó correction bị khóa bằng 0 và motor nhận một reference S-curve 1°.

Measurement firmware và công thức NL/RMS không tham gia test này.

## Profile đã khóa

| Thuộc tính | Giá trị |
| --- | ---: |
| Target | 1° / 182 raw |
| Power home và open-loop | 35% |
| Home update | 2 ms |
| Home timeout | 5.000 ms |
| S-curve | 40 command / 40 ms |
| Observation hold | 250 ms |
| Encoder cadence | 1 kHz |
| Evidence point | 291 |
| Max relative travel | khoảng 3° / 546 raw |
| Max active duration | 6.000 ms |
| Consecutive deadline miss | tối đa 2; lần thứ 3 safe-stop |
| Tracking correction trong C0 | 0 |

Mảng evidence nằm trong CCM CPU-only. UART không phát từ lúc motor enable đến
khi common exit đã gọi `Motor_Disable()`.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_cubeide.ps1 -Configuration Release
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_dual_image.ps1 -Mode Control
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_control_c0_contract.ps1
```

Artifact để flash:

```text
Build/Control/jigmotor_control.hex
```

Không flash `jigmotor_measurement.hex` cho test C0.

## Chuẩn bị an toàn

1. Gá chắc motor và magnet; bảo đảm MA600 đọc ổn định.
2. Không gắn tải có thể va chạm khi home về encoder 0°.
3. Có thể cắt nguồn motor ngay lập tức.
4. Mở UART3 ở 921600, 8-N-1 và lưu toàn bộ log.
5. Sau reset, xác nhận manifest có:

```text
AppMode=MOTOR_CONTROL
AppProfile=CONTROL_C0_OPEN_LOOP_1DEG_V1
Transport=SPI_DMA_BLOCKING_WRAPPER_V1
```

Nếu manifest khác, không nhấn nút chạy.

## Trình tự test

1. Quan sát idle angle và LED xanh trước khi chạy.
2. Nhấn nút một lần. Firmware precheck STATUS khi motor đang off.
3. Khi thấy `CONTROL_C0_ARMED`, không chạm motor hoặc UART cable.
4. Nếu rung mạnh, chạy sai hướng, kẹt hoặc có nguy cơ va chạm, nhấn nút lần hai
   để yêu cầu `OPERATOR_ABORT`; nếu không phản hồi thì cắt nguồn motor.
5. Chờ torque off và UART dump hoàn tất.
6. Lưu log nguyên bản, commit SHA, SHA-256 của HEX, JigID và MotorID.

Phân tích nhanh và xuất evidence CSV:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\analyze_control_c0.ps1 `
  -LogPath 'C:\path\control-c0.log' `
  -CsvPath 'C:\path\control-c0.csv'
```

## Log và gate

Một run không có fault phải có:

```text
CONTROL_C0_SUMMARY,...Result=OK,...EvidenceCount=291,...CorrectionRaw=0
CONTROL_C0_HEALTH,DeadlineMisses=0,...TransportErrors=0,JumpRejects=0,FailedSamples=0
CONTROL_C0_DATA,Seq=0..290,...CorrectionRaw=0
CONTROL_C0_RUNTIME,...ControlStackHighWaterWords=...
```

Không coi `Result=OK` là motor đã điều khiển chính xác. `OK` chỉ nghĩa safety và
data pipeline đã hoàn thành. Cần phân tích:

- `FinalActualMilliDeg` và `FinalErrorMilliDeg`;
- overshoot từ max actual so với 1.000 mdeg;
- backtrack;
- velocity/acceleration;
- `LoopCycles`, `SpiLatencyCycles`, `PwmCounterAtCs`;
- deadline miss, retry và resource high-water.

Các result sau bắt buộc dừng và không lặp lại trước khi tìm nguyên nhân:

```text
STATUS_FAULT
HOME_ACQUISITION_FAULT
HOME_TIMEOUT
HOME_WRONG_WAY
ACQUISITION_FAULT
TRAVEL_LIMIT
DEADLINE_FAULT
DURATION_LIMIT
EVIDENCE_OVERFLOW
```

`OPERATOR_ABORT` là dừng chủ động, không phải data pass.

## Điều kiện mở phase tiếp theo

Chỉ tạo profile 5° sau khi log 1° chứng minh:

- không rung/giật/stall/nóng bất thường;
- zero transport/jump/deadline failure;
- trajectory thực tế cùng chiều và không chạm travel limit;
- stack/heap còn margin;
- response đủ rõ để chọn C1 timing và C2 correction clamp.

Không tuning đồng thời power, trajectory và PID. Mỗi thay đổi phải có profile ID
và artifact hash mới.
