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
  | P09 | 5876 raw | 0.457 |

  Circular range giảm và R tăng qua P06→P09, nhưng **con số R một mình không
  đủ để kết luận hội tụ** — với n=5 mỗi mức, cần kiểm định thống kê chứ không
  nhìn R theo cảm tính. Bộ MATLAB (`analysis/matlab/`,
  `compute_circular_significance.m`) tính Rayleigh test (bác bỏ giả thuyết
  "phân bố đều/không phase-lock") và bootstrap 95% CI cho R. Kết quả thật đo
  qua P06–P10 (`a2*-summary.csv` + `a2*-evidence/`):

  | Mức | R | Rayleigh p | Bootstrap 95% CI |
  | --- | ---: | ---: | ---: |
  | P06 | 0.183 | 0.859 | [0.166, 0.894] |
  | P07 | 0.210 | 0.817 | [0.137, 0.910] |
  | P08 | 0.336 | 0.592 | [0.160, 0.9998] |
  | P09 | 0.457 | 0.372 | [0.138, 0.902] |
  | P10 | 0.300 | 0.417 | [0.101, 0.741] |

  **Không mức nào có p<0.05**, kể cả P09 (R cao nhất trong tập). Về mặt thống
  kê, chưa mức power nào đủ bằng chứng bác bỏ "chưa có phase-lock thật". Tiêu
  chí "đủ cho A3" là **Rayleigh p<0.05 và ổn định qua ≥2 mức power liên
  tiếp**, không phải "R cao hơn mức trước" — theo tiêu chí đó, P06–P10 đều
  chưa đạt.
- **Safety envelope, tính cả run fault** (`build_a2_safety_envelope.m`): P10
  (10%, profile A2/A2B gốc) có 2/12 run fault thật — `SAMPLE_STEP_LIMIT`
  (52/45 raw, 116% ngân sách) và `TRAVEL_LIMIT` (5026/5000 mdeg, 100.5%
  ngân sách). **P09 (`A2F làn 1`) đã dùng đúng 45/45 raw step budget (100%)
  ở 1/5 run** — chưa fault (limit là `>45` không phải `>=45`) nhưng không còn
  margin. Fit tuyến tính qua 5 mức cho ước lượng ranh giới step budget
  **~9.65% power** — gần như trùng khít P09 thực đo, không còn là ngoại suy xa.

### Quyết định: dừng power-envelope tại P09

P10 đã có fault thật, P09 đã chạm 100% ngân sách step ở 1/5 run — đúng điều
kiện dừng đã khóa sẵn ở trên. Không chạy P10 lại và không thử mức cao hơn.
Ngay ở mức R cao nhất (P09), Rayleigh p vẫn xa 0.05, nên tăng power tiếp
không có cơ sở kỳ vọng đạt phase-lock có ý nghĩa thống kê trước khi hết ngân
sách an toàn.

### Kết quả: fit mô hình phục hồi gộp toàn bộ dữ liệu an toàn (P06–P10)

Thay vì tăng power tiếp, gộp toàn bộ run `GatePass=true` qua cả 5 mức (P06,
P07, P08, P09, P10 — 30 run) và fit `FinalTravelRaw ≈ a·sin(θ)+b·cos(θ)+c`
với `θ = 2π·(BaselineRaw mod electricalCycle)/electricalCycle`
(`analysis/matlab/fit_a2_restoring_torque.m`). Kết quả thật:

| Mức | n | Amplitude (raw) | Phase (raw / deg) | R² | p |
| --- | ---: | ---: | ---: | ---: | ---: |
| P06 | 5 | 49.4 | 1992 / 10.9° | 0.826 | 0.174 |
| P07 | 5 | 97.2 | 2429 / 13.3° | 0.739 | 0.261 |
| P08 | 5 | 128.2 | 2146 / 11.8° | 0.914 | 0.086 |
| P09 | 5 | 365.9* | 3038 / 16.7° | 0.802 | 0.198 |
| P10 | 10 | 158.8 | 2344 / 12.9° | 0.970 | **4.4e-6** |
| **Gộp (30 run)** | 30 | 145.3 | **2356 / 12.9°** | 0.659 | **~0** |

\*P09 có 1 run (`A2F làn 1`) travel lớn gấp ~2–20 lần các run cùng mức, khả
năng là điểm đòn bẩy cao (high-leverage) kéo lệch amplitude ước lượng riêng
mức này.

**Fit gộp có ý nghĩa thống kê rất mạnh (p≈0, R²=0.66)** — hoàn toàn trái
ngược với Rayleigh test riêng từng mức (không mức nào p<0.05): từng mức
n=5 không đủ mạnh để phát hiện, nhưng gộp lại tín hiệu rất rõ. Amplitude
tăng theo power (49→97→128 từ P06→P08, P10=159 ở 10%), đúng hướng vật lý
kỳ vọng.

**Robustness check (leave-one-out) đã làm**:
- Bỏ hẳn P09 (còn 25 run: P06/P07/P08/P10): phase=**11.70°**, R² tăng lên
  **0.824** (tốt hơn khi có P09), p≈0 — phase gần như không đổi so với gộp
  đủ 5 mức (12.94°), chỉ lệch ~1.2°.
- Bỏ từng run một trong 30 run gộp: phase dao động rất hẹp
  **11.85°–13.03°**, R²=0.64–0.82, p luôn ≈0 (tệ nhất 2e-6) — ước lượng gộp
  không phụ thuộc vào một run đơn lẻ nào.
- Bỏ từng run một **chỉ trong nội bộ P09** (n=5→4): phase dao động rất rộng
  (7°–17.6°), p không ổn định (0.0036–0.40) — xác nhận P09 tự thân quá nhiễu
  để tin cậy một mình, đúng như nghi ngờ; nhưng vì fit gộp không dựa vào P09
  để có ý nghĩa (xem trên), điều này không hạ thấp độ tin cậy của phase gộp.

**Candidate phase offset cho A3: 11.7°–12.9° mechanical (raw ~2131–2356)
trong một electrical cycle**, ổn định qua toàn bộ robustness check ở trên.
Đây là ước lượng có cơ sở thống kê vững, nhưng trước khi đưa vào firmware
`CONTROL_A3_ENCODER_SEEDED_ALIGN_P10_V1` vẫn cần xác nhận bằng ít nhất một
batch run mới thiết kế riêng để kiểm tra đúng phase này (không chỉ dựa dữ
liệu power-envelope sẵn có, vốn không được thiết kế cho mục đích này), theo
đúng yêu cầu A3 trong plan gốc — "không được seed phase trực tiếp từ encoder
khi phase offset chưa được chứng minh".
