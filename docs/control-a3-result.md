# Kết quả A3 — sub-mechanism PASS, arbitrary-start alignment FAIL; đóng A3, chuyển A4

Verdict chốt (sau review): **cơ chế bám-và-kéo PASS; alignment an toàn từ vị
trí bất kỳ FAIL**. Không chạy thêm firmware A3 hiện tại — chạy thêm chỉ lặp
lại snap trong power-ramp mà không giải quyết thiết kế. Offset đã đo đủ
dùng để seed A4 (xem mục 3/5).

## Dataset và integrity

- Firmware: `CONTROL_A3_ROTATING_CAPTURE_P35_V1` (commit `786c657`,
  hex SHA-256 `E173C8C8...66951DC`), Control image.
- Log: `A3 test 1.txt` … `A3 test 5.txt`, mỗi file 2 run → **10 run vật lý**.
- Health 10/10 run: `DeadlineMisses=0`, `Retries=0`, `TransportErrors=0`,
  `JumpRejects=0`, `FailedSamples=0`; loop max 3122 cycles (~18.6 µs);
  stack high-water 1148 words; heap không đổi.
- 8/10 run `Result=OK` hoàn thành đủ 3201 tick; 2/10 run
  `SAMPLE_STEP_LIMIT` dừng an toàn trong giai đoạn POWER_RAMP (phân tích ở
  mục 4 — đây không phải nhiễu, mà là vật lý đã dự đoán được).

## 1. Kết quả theo run

| Run | Kết quả | Start cách equilibrium (° điện) | Capture tại (° điện field) | Drag lag mean/max (° điện) | ElectricalOffsetRaw |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | OK | −2.9 | 22.6 | −1.7 / 13.9 | 6843 |
| 2 | OK | +2.7 | 22.5 | +6.5 / 22.2 | 6749 |
| 3 | SAMPLE_STEP_LIMIT | **−51.9 (xoay tay)** | — | — | (loại) |
| 4 | OK | +1.7 | 22.7 | +4.9 / 20.4 | 6780 |
| 5 | OK | −6.5 | 21.2 | +5.1 / 19.7 | 6672 |
| 6 | OK | −2.8 | 23.1 | −1.4 / 14.0 | 6850 |
| 7 | SAMPLE_STEP_LIMIT | **+71.5 (xoay tay)** | — | — | (loại) |
| 8 | OK | +3.5 | 31.4 | +6.1 / 22.4 | 6748 |
| 9 | OK | +2.7 | 21.0 | +7.5 / 22.7 | 6640 |
| 10 | OK | −4.0 | 22.5 | +5.3 / 20.9 | 6655 |

Hold tail-20 p2p của các run OK: 27-44 mdeg — đúng noise band quen thuộc.
Max step trong khi drag: 92-106 raw/ms (gate 150). Mỗi run OK đi đúng một
chu kỳ điện (+10923 raw ≈ 60° cơ) như thiết kế.

## 2. Vật lý khớp dự đoán từng con số

Dùng bộ hằng số ma sát đã suy từ A2F + sweep measurement
(μ_static ≈ 0.10, μ_kinetic ≈ 0.04 của torque max):

| Đại lượng | Dự đoán | Đo được | |
| --- | ---: | ---: | --- |
| Góc capture | asin(0.10/0.35) = 16.6° điện + trễ cửa sổ 100 ms | 21-31° điện | ✓ |
| Drag lag động | asin(0.04/0.35) = 6.6° điện | mean 5-7.5° điện | ✓ |
| Snap khi ramp power ở phase cố định, start xa | break khi P·sin(dist) > μs: run 3 ~15%, run 7 ~13% | trip ở 16% / 18% | ✓ |
| Step gate 150 raw/ms | drag đỉnh 30-100; snap vượt 150 | drag max 92-106; snap trip 152-154 | ✓ phân tách sạch |

Ba dataset độc lập (A2F fixed-phase, sweep measurement, A3 drag) giờ cùng
khớp một mô hình ma sát duy nhất. Mô hình này đủ tin cậy để thiết kế tiếp.

## 3. Con số vàng: `ElectricalOffsetRaw = 6742 ± 81 raw`

- 8/8 run hoàn thành đều kéo rotor về cùng một equilibrium:
  mean 6742.1, SD 81.3, range 210 raw (1.15° cơ).
- So với fixed-phase A2F (circular range 3804 raw): cải thiện **18×**.
- Đây là hằng số hiệu chuẩn encoder↔điện của cặp motor+gá hiện tại —
  điều kiện tiên quyết cho alignment êm khởi phát zero-torque (A4) và xa
  hơn là sensored commutation.
- Scatter ±81 raw là scatter "đậu xe" do ma sát giữ ở cuối hold; với mục
  đích seed phase (chỉ cần ≪90° điện) thì ±0.45° cơ = ±3.3° điện là thừa đủ.

## 4. Hai run STEP_LIMIT: lỗ hổng thiết kế đã lộ đúng chỗ — và gate đã cứu đúng lúc

Sự thật cần ghi thẳng:

- 8 run OK đều xuất phát **ngay tại equilibrium** (mỗi run đi đúng 1 chu kỳ
  điện nên modulo không đổi giữa các run liên tiếp — start diversity ≈ 0).
- Chỉ 2 run được xoay tay sang vị trí lạ (−52° / +71.5° điện) — và **cả 2
  đều snap trong giai đoạn POWER_RAMP** (phase đứng yên tại 0, power ramp
  lên 35%): đúng cơ chế snap của A2-P10, xảy ra khi P·sin(dist) vượt ma
  sát tĩnh giữa lúc power ramp (~16-18%).
- Giả định thiết kế "POWER_RAMP chỉ creep ≤1° như A2" là SAI cho start xa
  equilibrium: dữ liệu A2 chỉ bracket tới 9-10% power. Đây là lỗi dự đoán
  của thiết kế A3, không phải lỗi jig hay motor.
- Gate `MAX_SAMPLE_STEP 150 raw/ms` hoạt động hoàn hảo: trip ở 152-154,
  motor dừng an toàn, run kế tiếp bình thường. Khung an toàn được kiểm
  chứng bằng chính thất bại.

Hệ quả: **A3 chứng minh cơ chế capture-and-drag; nhưng bài toán alignment
"từ vị trí bất kỳ" chưa xong** — chính các start bất kỳ là trường hợp bị
snap ở giai đoạn ramp.

## 5. Đối chiếu acceptance đã đặt trước (plan A3)

| Tiêu chí | Kết quả | Đậu/Rớt |
| --- | --- | --- |
| Integrity/acquisition/timing | 10/10 sạch | ✓ |
| Run hoàn thành | 8/10 | ✗ |
| Capture trong run hoàn thành | 8/8 | ✓ có điều kiện (start ≈ equilibrium) |
| Random start thực sự | 2 run | ✗ chưa đủ |
| Random start hoàn thành | **0/2** | ✗ FAIL |
| 0 hard gate | 2/10 SAMPLE_STEP_LIMIT | ✗ |
| Settled range ≤ 182 raw (1°) | 210 raw | ✗ |
| R ≥ 0.99 | ~0.999 | ✓ |
| Offset trong noise band | range 210 raw vs noise hold ~5-8 raw | ✗ **FAIL theo tiêu chí gốc** — chỉ đủ chuẩn "seed", không phải calibration cấp noise encoder |

Verdict: **A3 không đạt acceptance tổng thể.** Chính xác:
PASS cho cơ chế rotor bám-và-drag sau khi đã ở gần equilibrium; PASS cho
acquisition/timing/safety gate; **FAIL cho mục tiêu alignment an toàn từ vị
trí bất kỳ.** Tám run OK bắt đầu gần equilibrium (run trước kết thúc đúng
một chu kỳ điện) nên chỉ chứng minh following/drag, chưa chứng minh
rotating capture từ vị trí bất kỳ.

### Offset có đủ dùng cho A4 không? CÓ — không cần chạy thêm A3

Sai số seed lớn nhất so với mean ≈ 108 raw ≈ 3.56° điện. Tại power 35%,
torque dư do sai số seed ≈ 0.35·sin(3.56°) ≈ **2.2% torque max**, rất xa
ngưỡng ma sát tĩnh 9-10% → ramp power tại phase seed sẽ không tạo snap.
Không cần thêm run A3 chỉ để lấy thêm offset.

## 6. A4 — ENCODER_SEEDED_DRAG (spec đã chốt sau review)

Một biến duy nhất so với A3: điểm bắt đầu phase được seed từ encoder.

1. Đọc baseline encoder → `F0 = (BaselineRaw − 6742) mod 10923`.
2. Prime PWM **tại F0**, power = 0 → torque ≈ 0 bất kể rotor ở đâu.
3. Ramp power 0→35% trong 300 ms tại F0 → không tồn tại giai đoạn snap.
4. Sweep phase **chỉ theo chiều dương** (chiều duy nhất A3 đã xác nhận):
   `Span = (10923 − F0) mod 10923` — không chọn "đường gần nhất" vì có
   thể chạy ngược.
5. Giữ cùng tốc độ trung bình A3: `SweepTicks ≈ 2400 × Span / 10923`
   (có sàn tick tối thiểu cho span nhỏ để giữ động học chậm).
6. Hold 500 ms tại phase 0; giữ nguyên toàn bộ acquisition + step/travel/
   deadline/pull-out gate của A3 (khung đã được kiểm chứng cả hai chiều).
7. Trường hợp `Span` rất nhỏ (rotor đã ở equilibrium trong scatter đo):
   đánh dấu `AlreadyAligned=1`, **không bắt buộc capture detector latch**;
   capture chỉ bắt buộc khi span đủ dài để cửa sổ phát hiện có ý nghĩa.
8. Log thêm: `SeedPhaseRaw`, `SeedOffsetRaw`, `SweepSpanRaw`,
   `SweepTicks`, `AlreadyAligned`.

### Acceptance A4

Ít nhất 5 start xoay tay có chủ đích, phủ ≥ 4 góc phần tư điện:

- 0 hard gate; 5/5 hoàn thành; không snap trong power-ramp; không drag-slip;
- final offset range mục tiêu ≤ 182 raw;
- acquisition + deadline sạch.

Giới hạn phạm vi: A4 chỉ giải quyết **alignment khởi động**. Nó chưa phải
closed-loop position controller và chưa chứng minh sai số bám từng điểm
0.05° — phần đó chỉ triển khai sau khi A4 vượt random-start acceptance.

Ghi chú: offset 6742 là hằng số theo cặp motor+gá — tháo lắp motor phải đo
lại (một run A3-kiểu từ equilibrium là đủ). Đo offset ngay đầu run để bỏ
hằng số compile-time là biến thứ hai — không trộn vào A4.

## Tái lập phân tích

Số liệu trích trực tiếp từ `CONTROL_A3_SUMMARY` (capture/lag/offset đã
được firmware tự tính); phân tích bổ sung (khoảng cách start-equilibrium,
đối chiếu vật lý) tính từ `BaselineRaw mod 10923` so với offset mean.
Tool phân tích A3 chuyên dụng (`analyze_control_a3.ps1`) sẽ làm cùng đợt
A4 khi record layout ổn định.
