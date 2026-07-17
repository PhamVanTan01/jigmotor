# Control A2 — hardware test alignment-only

## Mục tiêu

Firmware `CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1` chỉ kiểm tra trình tự
alignment/enable. Nó không chạy HOME, PID, trajectory 1° hoặc measurement.

Trình tự active đã khóa:

```text
motor off
-> đọc baseline encoder
-> prime phase 0 tại power 0
-> enable tại power 0
-> ramp 0% đến 10% trong 500 ms
-> giữ phase 0 tại 10% trong 100 ms
-> motor off và clear PWM
-> dump UART
```

## Safety envelope

| Thuộc tính | Giá trị |
| --- | ---: |
| Cadence | 1 kHz |
| Evidence khi hoàn thành | 601 mẫu |
| Max travel | 910 raw, xấp xỉ 5° |
| Max step giữa hai mẫu | 45 raw, xấp xỉ 0,247°/ms |
| Max active duration | 750 ms |
| Deadline miss liên tiếp | lần thứ 3 safe-stop |
| SPI attempts mỗi tick | tối đa 3 |
| PID/HOME/correction | không chạy / 0 |

`SAMPLE_STEP_LIMIT` và `TRAVEL_LIMIT` là kết quả safety hợp lệ, không phải lý do
để tự tăng limit hoặc power trong cùng firmware.

## Build và artifact

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_dual_image.ps1 -Mode Control
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_control_alignment_contract.ps1
Get-FileHash .\Build\Control\jigmotor_control.hex -Algorithm SHA256
```

Chỉ flash:

```text
Build/Control/jigmotor_control.hex
```

Sau reset phải thấy:

```text
AppMode=MOTOR_CONTROL
AppProfile=CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1
```

Nếu profile khác thì không chạy.

## Trình tự test phần cứng

1. Gá chắc motor, bảo đảm không có tải hoặc cơ cấu có thể va chạm trong 5°.
2. Mở UART3 `921600 8-N-1` và lưu log nguyên bản.
3. Chạy đúng một lần đầu tiên. Giữ sẵn khả năng cắt nguồn motor.
4. Nếu thấy rung mạnh, nóng, kẹt hoặc chuyển động nguy hiểm: nhấn nút lần hai
   để yêu cầu `OPERATOR_ABORT`; nếu không dừng thì cắt nguồn.
5. Chỉ khi lần đầu an toàn mới chạy tiếp. Thử tối đa 10 vị trí rotor ban đầu
   khác nhau trong một electrical cycle nếu gá cho phép.
6. Không đẩy rotor bằng tay trong thời gian từ `CONTROL_A2_ARMED` tới lúc UART
   bắt đầu dump `CONTROL_A2_SUMMARY`.
7. Lưu kèm JigID, MotorID, SourceId và SHA-256 của HEX.

## Log mong đợi

Run hoàn thành safety envelope:

```text
CONTROL_A2_SUMMARY,...Result=OK,...EvidenceCount=601,...
CONTROL_A2_SEQUENCE,PrimeStateValid=1,EnableStateValid=1,EnablePowerPpm=0
CONTROL_A2_HEALTH,DeadlineMisses=0,...TransportErrors=0,JumpRejects=0,FailedSamples=0
CONTROL_A2_DATA,Seq=0,Phase=ALIGN_RAMP,...PowerPpm=0,...CorrectionRaw=0
...
CONTROL_A2_DATA,Seq=500,Phase=ALIGN_RAMP,...PowerPpm=100000,...CorrectionRaw=0
CONTROL_A2_DATA,Seq=600,Phase=ALIGN_HOLD,...PowerPpm=100000,...CorrectionRaw=0
CONTROL_A2_RUNTIME,...ControlStackHighWaterWords=...
```

`AccelerationSaturations` trong `CONTROL_A2_HEALTH` phải bằng 0. Trường
`AccelerationRawPerSecond2` được serialize bằng signed 32-bit tương thích
`newlib-nano`; phép tính trung gian vẫn là 64-bit và được saturate có đếm nếu
vượt miền biểu diễn.

Phân tích một hoặc nhiều file log bằng tool dùng chung:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\analyze_control_a2.ps1 `
  -LogPath '.\A2 lần 2.txt', '.\A2 lần 3.txt' `
  -SummaryCsv '.\a2-summary.csv'
```

Các result cần diễn giải:

- `OK`: chuỗi chạy đủ 600 ms; chưa có nghĩa motor đã đạt absolute zero.
- `SAMPLE_STEP_LIMIT`: rotor vẫn tạo bước lớn hơn khoảng 0,247° trong 1 ms.
- `TRAVEL_LIMIT`: fixed phase cần hành trình lớn hơn pilot 5°.
- `ACQUISITION_FAULT`: kiểm tra SPI/jump counter trước khi kết luận cơ khí.
- `PRIME_FAULT` hoặc `ENABLE_STATE_FAULT`: không tiếp tục test artifact này.
- `OPERATOR_ABORT`: dừng chủ động, không phải pass.

## Gate trước A3/A4

- 10/10 run có `PrimeStateValid=1`, `EnableStateValid=1`, `EnablePowerPpm=0`.
- Không rung/giật quan sát được khi enable hoặc trong power ramp.
- Zero SPI, deadline và evidence failure.
- Power tăng đơn điệu từ 0 tới 100000 ppm.
- Chưa thay đổi PID, power hoặc safety limit trong tập dữ liệu này.

Nếu motor không chuyển động ở 10% nhưng vẫn êm, ghi nhận là pilot chưa đủ torque;
không gọi đó là alignment thành công. Profile P15 phải là artifact riêng sau khi
review log P10.
