# Control A2F — fixed-phase power-envelope, P09/H500

## Mục tiêu

Firmware `CONTROL_A2F_FIXED_PHASE_ALIGN_P09_H500_V1` chỉ kiểm tra trình tự
alignment/enable. Nó không chạy HOME, PID, trajectory 1° hoặc measurement.
P08 đã đóng gate an toàn với 5/5 run, nhưng MATLAB cho circular range 31.247°
và `R=0.336`, nên chưa alignment về một equilibrium chung. P10/H500 đã có
`SAMPLE_STEP_LIMIT`; P09 là điểm còn thiếu duy nhất để bracket ngưỡng an toàn.
A2F giữ nguyên phase, ramp, hold và các guard; chỉ tăng power đỉnh từ 8% lên
9%. Đây là artifact cuối của hướng tăng fixed-phase power: không chạy mức cao
hơn nếu A2F chạm hard-gate hoặc không cải thiện hội tụ.

Trình tự active đã khóa:

```text
motor off
-> đọc baseline encoder
-> prime phase 0 tại power 0
-> enable tại power 0
-> ramp 0% đến 9% trong 500 ms
-> giữ phase 0 tại 9% trong 500 ms
-> motor off và clear PWM
-> dump UART
```

## Safety envelope

| Thuộc tính | Giá trị |
| --- | ---: |
| Cadence | 1 kHz |
| Evidence khi hoàn thành | 1001 mẫu |
| Max travel | 910 raw, xấp xỉ 5° |
| Max step giữa hai mẫu | 45 raw, xấp xỉ 0,247°/ms |
| Max active duration | 1200 ms (chuỗi danh định 1000 ms) |
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
AppProfile=CONTROL_A2F_FIXED_PHASE_ALIGN_P09_H500_V1
```

Nếu profile khác thì không chạy.

## Trình tự test phần cứng

1. Gá chắc motor, bảo đảm không có tải hoặc cơ cấu có thể va chạm trong 5°.
2. Mở UART3 `921600 8-N-1` và lưu log nguyên bản.
3. Chạy đúng một lần đầu tiên. Giữ sẵn khả năng cắt nguồn motor.
4. Nếu thấy rung mạnh, nóng, kẹt hoặc chuyển động nguy hiểm: nhấn nút lần hai
   để yêu cầu `OPERATOR_ABORT`; nếu không dừng thì cắt nguồn.
5. Chỉ khi lần đầu an toàn mới chạy tiếp. Thử tối thiểu 5 vị trí rotor ban đầu
   khác nhau trước khi đóng gate của profile này. Trải vị trí theo
   `encoderRaw mod electricalCycle`, **không** theo dải encoder cơ khí đầy đủ:
   với motor 6 pole-pair, electrical cycle chỉ dài 60° cơ khí, nên "trải rộng
   trong dải encoder" (360°) dễ khiến nhiều vị trí rơi trùng cùng một góc điện
   một cách ngẫu nhiên. Cách làm: chọn 5 vị trí cách nhau khoảng 12° cơ khí,
   nằm trong cùng một cung 60° bất kỳ (ví dụ 0°, 12°, 24°, 36°, 48° tính từ một
   mốc bất kỳ).
6. Không đẩy rotor bằng tay trong thời gian từ `CONTROL_A2_ARMED` tới lúc UART
   bắt đầu dump `CONTROL_A2_SUMMARY`.
7. Travel ở các mức power này chỉ cỡ 0,2°–1,1°, khó thấy bằng mắt nếu không có
   mốc tham chiếu cố định. Nếu cần xác nhận trực quan, dán một mốc cố định
   trên rotor và một mốc cố định trên khung trước khi chạy, so vị trí trước/
   sau; không dùng quan sát "nhìn tổng thể" để kết luận log sai.
8. Lưu kèm JigID, MotorID, SourceId và SHA-256 của HEX.

## Log mong đợi

Run hoàn thành safety envelope:

```text
CONTROL_A2_SUMMARY,...Profile=CONTROL_A2F_FIXED_PHASE_ALIGN_P09_H500_V1,...Result=OK,...EvidenceCount=1001,...
CONTROL_A2_SEQUENCE,PrimeStateValid=1,EnableStateValid=1,EnablePowerPpm=0
CONTROL_A2_HEALTH,DeadlineMisses=0,...TransportErrors=0,JumpRejects=0,FailedSamples=0
CONTROL_A2_DATA,Seq=0,Phase=ALIGN_RAMP,...PowerPpm=0,...CorrectionRaw=0
...
CONTROL_A2_DATA,Seq=500,Phase=ALIGN_RAMP,...PowerPpm=90000,...CorrectionRaw=0
CONTROL_A2_DATA,Seq=1000,Phase=ALIGN_HOLD,...PowerPpm=90000,...CorrectionRaw=0
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
  -LogPath '.\A2F lần 1.txt', '.\A2F lần 2.txt' `
  -SummaryCsv '.\a2f-summary.csv'
```

Các result cần diễn giải:

- `OK`: chuỗi chạy đủ 1000 ms; chưa có nghĩa motor đã đạt absolute zero.
- `SAMPLE_STEP_LIMIT`: rotor vẫn tạo bước lớn hơn khoảng 0,247° trong 1 ms.
- `TRAVEL_LIMIT`: fixed phase cần hành trình lớn hơn pilot 5°.
- `ACQUISITION_FAULT`: kiểm tra SPI/jump counter trước khi kết luận cơ khí.
- `PRIME_FAULT` hoặc `ENABLE_STATE_FAULT`: không tiếp tục test artifact này.
- `OPERATOR_ABORT`: dừng chủ động, không phải pass.

## Gate trước A3/A4

- 5/5 run (vị trí rotor ban đầu khác nhau, trải theo `encoderRaw mod
  electricalCycle` — xem mục 5 ở trên) có `PrimeStateValid=1`,
  `EnableStateValid=1`, `EnablePowerPpm=0`.
- Không rung/giật quan sát được khi enable hoặc trong power ramp.
- Zero SPI, deadline và evidence failure; `AccelerationSaturations=0`.
- Power tăng đơn điệu từ 0 tới 90000 ppm.
- Vị trí dừng phải được so sánh theo `encoderRaw mod electricalCycle`, không
  theo raw encoder tuyệt đối; với motor 6 pole-pair, electrical cycle là 60°.
- Chưa thay đổi PID, power hoặc safety limit trong tập dữ liệu này.
- Đánh giá hội tụ bằng **thống kê circular** của `SettledModuloRaw` giữa các
  run cùng mức power, không phải min-max range tuyến tính — `SettledModuloRaw`
  là đại lượng dạng vòng (mod electricalCycle), nên hai giá trị nằm sát hai
  bên biên wrap (gần 0 và gần electricalCycle) rất gần nhau về góc điện nhưng
  range tuyến tính lại tính ra xa. `analyze_control_a2.ps1` giờ tự in ra
  `circular mean`, `circular range` (theo phương pháp largest-gap) và `R`
  (độ dài vector kết quả, 0 = phân tán đều quanh vòng tròn, 1 = hội tụ tuyệt
  đối vào một điểm) cho mỗi profile có ≥2 run; dùng `-CircularSummaryCsv` để
  xuất ra file. Số liệu thật đã đo (tính lại đúng bằng circular, không phải
  linear range tôi đã tính tay ban đầu — con số linear trước đó cho P07/P08
  bị sai lệch do wrap):

  | Mức | Circular range | R |
  | --- | ---: | ---: |
  | P06 | 7350 raw | 0.183 |
  | P07 | 6967 raw | 0.210 |
  | P08 | 5688 raw | 0.336 |

  Cả circular range (giảm dần) và R (tăng dần) đều cho thấy xu hướng hội tụ
  thật qua 3 mức, dù còn yếu (R=0.336 vẫn còn xa 1). Vị trí rotor ban đầu chưa
  trải đều một electrical cycle không làm sai lệch chỉ số circular này, nhưng
  trải đều hơn (như đang làm cho batch kế tiếp) vẫn giúp ước lượng R đáng tin
  hơn với cùng cỡ mẫu 5 run. Coi là đủ tin cậy cho A3 khi R vượt khoảng 0.8–0.9
  và ổn định qua ≥2 mức power liên tiếp — chưa có ngưỡng cứng, sẽ chốt khi
  thấy xu hướng bão hòa rõ.
- Theo dõi `MaxAbsTravelMilliDeg` so với `TRAVEL_LIMIT` (5000 mdeg): ở P07 một
  run đã dùng tới ~22% ngân sách (1120 mdeg), P08 tới ~18% (906 mdeg). Ngân
  sách travel không tăng tuyến tính và dễ đoán theo power; nếu một vị trí bất
  kỳ tiến gần limit, dừng power-envelope tại đó thay vì chờ chạm
  `TRAVEL_LIMIT` thật.

Nếu chạm `SAMPLE_STEP_LIMIT` hoặc `TRAVEL_LIMIT` ở mức nào đó, dừng
power-envelope ngay tại đó, không chạy mức cao hơn.
