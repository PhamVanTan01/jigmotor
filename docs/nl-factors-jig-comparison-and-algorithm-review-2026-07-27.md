# Tổng hợp phát hiện: yếu tố ảnh hưởng NL, so sánh JIG, và rà soát thuật toán PID/sensor (2026-07-27)

Tài liệu này tổng hợp toàn bộ phát hiện từ một phiên phân tích MATLAB, gồm 5 chủ đề độc lập nhưng liên quan. Mỗi phần nêu rõ: công cụ dùng, dữ liệu thật đã chạy, số liệu, và giới hạn/độ tin cậy của kết luận — không phần nào được coi là "đã chốt" nếu chưa có bằng chứng đủ mạnh.

## Mục lục

1. [Yếu tố ảnh hưởng giá trị NL_RobustP2P_Deg](#1-yếu-tố-ảnh-hưởng-giá-trị-nl_robustp2p_deg)
2. [Công thức đo torque/ma sát bằng MA600 (không cần cảm biến dòng)](#2-công-thức-đo-torquema-sát-bằng-ma600)
3. [So sánh JIG4 vs JIG5](#3-so-sánh-jig4-vs-jig5)
4. [So sánh JIG1 vs JIG4 và nỗ lực sửa lỗi sector](#4-so-sánh-jig1-vs-jig4-và-nỗ-lực-sửa-lỗi-sector)
5. [Rà soát thuật toán PID điều khiển motor và thuật toán lấy dữ liệu sensor](#5-rà-soát-thuật-toán-pid-điều-khiển-motor-và-thuật-toán-lấy-dữ-liệu-sensor)

Toàn bộ tool MATLAB liên quan nằm trong `analysis/matlab/nl/`, `analysis/matlab/a4/`, `analysis/matlab/health/`, có test hồi quy trong `analysis/matlab/tests/` (đã chạy PASS cả 5 bộ: `test_a2_analysis`, `test_a3_a4_a5_analysis`, `test_b0b_analysis`, `test_nl_stability_analysis`, `test_health_analysis`).

---

## 1. Yếu tố ảnh hưởng giá trị NL_RobustP2P_Deg

**Tool**: [`analyze_nl_factors.m`](../analysis/matlab/nl/analyze_nl_factors.m)

**Dữ liệu**: 271 sweep pooled (test21-29, phương pháp V2/V3/A0, 5 sản phẩm) + 41 sweep bộ mounting-force (H2-remount, 10 nhóm).

### Kết quả (tương quan trong-nhóm, đã trừ trend RunOrder)

| Yếu tố | r | Đồng dấu bao nhiêu nhóm | Ghi chú |
| --- | ---: | --- | --- |
| **RMS_AC_Deg** | **0.90** | 12/12 | Mạnh nhất, nhất quán tuyệt đối |
| MeanDC_Deg | -0.68 | 7/12 | Có liên hệ nhưng không nhất quán |
| A36_Deg | -0.48 | 5/12 | p nhỏ nhưng KHÔNG đáng tin per-nhóm (nghịch lý Simpson) |
| ClosureErrorDeg | 0.22 | 7/12 | Yếu |
| AnalysisStartRaw (sector) | -0.20 | 6/12 | Gần như tung đồng xu ở mức pooled rộng |

**Kết luận**: `RMS_AC_Deg` là chỉ báo đại diện tốt nhất cho NL (cùng công thức nguồn dữ liệu, không phải quan hệ nhân quả độc lập — xem docstring `compute_nl_sweep_metrics.m`). Không nên dùng `RMS_AC` thay thế hoàn toàn `NL_RobustP2P` làm gate chính thức vì hai chỉ số phân kỳ đúng ở outlier cục bộ.

---

## 2. Công thức đo torque/ma sát bằng MA600

**Tool**: [`compute_a4_torque_margin.m`](../analysis/matlab/a4/compute_a4_torque_margin.m), [`analyze_a4_torque_margin_batch.m`](../analysis/matlab/a4/analyze_a4_torque_margin_batch.m)

### Công thức

```
T(t) / T_max@100% = Power(t) × sin(DragLagRaw(t) × 2π / 10923)
```

- **μs (ma sát tĩnh)**: `max(DragLagRaw)` trong PHASE_SWEEP — đỉnh lag ngay trước khi rotor bung ra khỏi trạng thái kẹt.
- **μk (ma sát động)**: trung bình `DragLagRaw` trong các tick `CaptureLatched=1`.

Đây là % công suất PWM (torque tương đối so với 100% power), **không phải N·m tuyệt đối** — cần thêm hiệu chuẩn tải biết trước mới ra được đơn vị vật lý thật.

### Kết quả trên 34 run thật (A4 + A4B test 1-5, "lần 1-5")

| Đại lượng | Trung bình | 95% CI |
| --- | ---: | ---: |
| μs (peak-lag method) | 0.1332 | [0.1206, 0.1448] |
| μs (firmware CaptureSeq, để so sánh — trễ do thiết kế) | 0.1555 | [0.1332, 0.1763] |
| μk | 0.0415 | [0.0279, 0.0543] |

μk khớp tốt với ước lượng cũ trong tài liệu (`docs/control-a3-result.md`, `docs/control-a2f-p09-result.md`: ~0.04) — xác nhận công thức đúng. μs (0.13) cao hơn ước lượng cũ (~0.09-0.10) vì số cũ chỉ dựa trên 2 sự kiện bracket đơn lẻ, số mới tính riêng góc thực đo trên 34 run — có cơ sở thống kê chắc hơn.

**Phát hiện phụ**: `DragLagRaw` dao động lớn (median ~1049 raw ≈ 34.6° điện) trong suốt pha kéo ở hầu hết mọi run — có thể là cộng hưởng cơ khí hoặc đặc tính vòng hở ở 35% power, chưa điều tra sâu.

---

## 3. So sánh JIG4 vs JIG5

**Tool**: [`analyze_jig_delta.m`](../analysis/matlab/nl/analyze_jig_delta.m) (tổng quát hóa, nhận nhãn jig bất kỳ)

**Bối cảnh**: JIG5 = board điều khiển MỚI gắn cùng bệ cơ khí, cảm biến MA600A của JIG4 (commit `57c76aa`). Ban đầu nghi ngờ Zero calibration khác nhau (JIG4=0x00E7 lúc đó, JIG5=0x0000) gây lệch sector → lệch NL.

### Kết quả trên 5 sản phẩm (test31, 100 sweep hợp lệ)

Tương quan |ΔSector| vs |ΔNL_RobustP2P|: **r = -0.005, p = 0.99 — gần như bằng KHÔNG.**

**Kết luận**: giả thuyết "Zero khác → sector khác → NL khác" **bị bác bỏ bởi dữ liệu** cho cặp JIG4-JIG5. (Về sau xác nhận thêm: field `Zero` trong registry firmware chỉ dùng để audit/gate an toàn, KHÔNG dùng để tính góc thực — MA600 tự trả về vị trí đã zero-hóa nội bộ trong chip, nên Zero registry sai không làm sai dữ liệu đo, chỉ chặn gate.)

Phát hiện phụ quan trọng: **`MotorIDValid=0` trên MỌI run** (cả 2 jig, cả 5 sản phẩm) — "cùng 1 motor" chỉ là nhãn thủ công của người vận hành, không được firmware xác thực bằng phần cứng. Sai khác motor-to-motor thật vẫn là một khả năng chưa loại trừ được.

---

## 4. So sánh JIG1 vs JIG4 và nỗ lực sửa lỗi sector

### 4.1. Đính chính cặp jig đúng

Theo xác nhận của người vận hành: **JIG1 và JIG4 mới là cặp "cùng bệ cơ khí, chỉ đổi board"**, không phải JIG4-JIG5. Khớp với `docs/hardware-validation-checklist.md`: Zero của JIG4 cuối cùng được sửa về `0x0000` (27/07/2026) sau 33 lần đọc ổn định — khớp JIG1 y hệt.

### 4.2. Kết quả ban đầu (n=4 sản phẩm, JIG1 test29 vs JIG4 test31)

| Product | ΔSector | ΔNL |
| --- | ---: | ---: |
| p02 | −171.9° | −0.625° |
| p03 | +124.1° | +0.009° |
| p05 | +133.9° | +0.163° |
| p06 | +119.5° | +0.191° |

Tương quan |ΔSector| vs |ΔNL|: **r = 0.927, p = 0.073**; với A36: **r = 0.964, p = 0.036**.

### 4.3. Kiểm tra mở rộng — hạ thấp mức độ tin tưởng ban đầu

Vì n=4 quá nhỏ, mở rộng ra **14 phiên đo A0 thật** (JIG1+JIG4+JIG5, 5 sản phẩm) bằng [`fit_sector_response.m`](../analysis/matlab/nl/fit_sector_response.m):

- Fit gộp thô (không tách sản phẩm): **R² = 0.01** — vô nghĩa.
- Fit sau khi trừ baseline riêng từng sản phẩm (đúng phương pháp): **R² = 0.22**.

→ **Đính chính: hiệu ứng sector CÓ THẬT nhưng chỉ giải thích ~22% phương sai**, không phải nguyên nhân chính như kết luận n=4 ban đầu gợi ý. ~78% khác biệt vẫn chưa có lời giải (motor-to-motor variation là ứng viên còn sống, xem mục 3).

### 4.4. Kiểm chứng phép sửa (before/after)

Dùng [`correct_delta_for_sector.m`](../analysis/matlab/nl/correct_delta_for_sector.m) áp mô hình R²=0.22 lên đúng 4 sản phẩm JIG1-vs-JIG4:

| Product | ΔNL gốc | Phần do sector | ΔNL sau sửa |
| --- | ---: | ---: | ---: |
| p02 | −0.625° | −0.216° | −0.409° |
| p03 | +0.009° | +0.089° | −0.080° |
| p05 | +0.163° | −0.075° | **+0.238° (tệ hơn)** |
| p06 | +0.191° | +0.222° | −0.031° |

RMS giảm từ 0.337° → 0.240° (~29%) — **cải thiện một phần, không giải quyết hết**, và **sai chiều ở p05**. Kết luận: công thức sửa hậu kỳ **không đủ tin cậy để dùng làm căn cứ chính thức**.

### 4.5. Khuyến nghị khắc phục thực sự

Vì phần mềm chỉ sửa được ~1/3 vấn đề, giải pháp nằm ở quy trình đo:

1. **Ngắn hạn**: dùng [`sector_match_gate.m`](../analysis/matlab/nl/sector_match_gate.m) làm điều kiện bắt buộc trước khi so sánh NL giữa 2 jig/phiên — nếu lệch sector > ngưỡng (mặc định 200 raw ≈ 6.6° điện), gắn nhãn "không so sánh trực tiếp được".
2. **Trung hạn**: thiết kế thí nghiệm quét sector chủ động trên 1 motor cố định (thay vì để rơi ngẫu nhiên theo vị trí nghỉ rotor) để fit mô hình sector-response tin cậy hơn.
3. **Dài hạn**: cân nhắc sửa firmware để A0 chọn sector cố định/kiểm soát được, loại bỏ nguồn nhiễu này tận gốc.

---

## 5. Rà soát thuật toán PID điều khiển motor và thuật toán lấy dữ liệu sensor

**Tool mới**: [`analyze_sensor_noise_floor.m`](../analysis/matlab/health/analyze_sensor_noise_floor.m), [`analyze_acquisition_health.m`](../analysis/matlab/health/analyze_acquisition_health.m), [`analyze_pid_timing_jitter.m`](../analysis/matlab/health/analyze_pid_timing_jitter.m). Quét 206 file log thật trong repo.

### 5.1. PID (`Core/Src/position_controller.c`)

**Điểm yếu code (đọc source):**

1. **Derivative-on-error** (`kd*(errorDeg - lastError)`) thay vì derivative-on-measurement — có thể gây "kick" khi setpoint đổi đột ngột mỗi điểm sweep mới.
2. **Không chuẩn hóa theo dt thực đo** — `integral += ki*errorDeg` giả định chu kỳ gọi luôn cố định, không có bù trừ khi jitter.
3. **Anti-windup chỉ bằng clamp đơn giản** trên số hạng tích phân (không phải back-calculation).
4. **Gain cố định toàn cục** (`kp=2.0, ki=0.003, kd=0.3`), không theo từng jig/motor dù ma sát đo được (mục 2) dao động 9-13% giữa các jig.

**Kiểm chứng bằng 27.274 tick thật (20 file A4/A4B):**

| Chỉ số | Giá trị đo |
| --- | ---: |
| LatenessTicks trung bình / tối đa | 0.0000 / 0 |
| % tick trễ | 0.0000% |
| Sai số dt ước tính (điểm yếu #2) | **0.0000%** — chưa từng xảy ra |
| LoopCycles trung bình | 3018 cycles (~2% ngân sách 1ms) |

→ Điểm yếu #2 có thật về code nhưng **chưa gây ảnh hưởng đo được** trong dữ liệu hiện có — nên vá cho chắc chắn, không phải bug khẩn cấp.

### 5.2. Sensor acquisition (`Core/Src/ma600.c`, `ma600_acquisition.c`)

**Điểm yếu code:**

1. **Không CRC/parity trên đường đọc góc nhanh** (`MA600_ReadRawChecked`) — chỉ kiểm tra STATUS khi đọc CONFIG (hiếm khi chạy). Lỗi bit SPI rơi trong ngưỡng `maxJumpRaw` sẽ không bị phát hiện.
2. **Vòng PID thời gian thực dùng đọc đơn, không lọc MAD/trung bình** — khác đường NL sweep (`MA600_ReadAveragedPointWithIo`, có lọc outlier kỹ). Nhiễu đi thẳng vào P và I; D được giảm nhẹ nhờ `derivativeAlpha=0.25`.

**Kiểm chứng bằng dữ liệu thật (20.443.016 lần đọc, 901 sweep, 111 file):**

| Chỉ số | Giá trị đo |
| --- | ---: |
| Retry / Transport error / Jump reject / Failed sample | **0 / 0 / 0 / 0** (0.0000%) |
| Nhiễu sensor lúc đứng yên, P2P trung bình (741 phép đo hợp lệ) | 0.0498° (~9.1× LSB 0.0055°) |
| P2P tối đa (hợp lệ) | 2.46° |

→ Cơ chế retry/jump-reject/MAD-filter **chưa từng bị kích hoạt** trong 20.4 triệu lần đọc thật — SPI cực kỳ tin cậy trong thực tế, nhưng đồng nghĩa các cơ chế an toàn này **chưa từng được kiểm chứng bằng lỗi thật ngoài hiện trường**, chỉ qua self-test tổng hợp.

**Lưu ý tự sửa lỗi**: lần chạy đầu `analyze_sensor_noise_floor.m` báo nhiễu trung bình 4.39° (vô lý) do gộp nhầm các phép đo firmware tự đánh dấu `valid=0` (đọc ngay sau lỗi `E502` homing). Đã sửa tách ALL vs VALID-only — số đúng thấp hơn 88 lần.

### 5.3. Bảng ưu tiên khắc phục

| Ưu tiên | Việc cần làm | Lý do |
| --- | --- | --- |
| Cao | Thêm parity/CRC check vào đường đọc góc nhanh | Lỗ hổng thật, chưa có lưới an toàn, dù chưa quan sát lỗi thật |
| Trung bình | Derivative-on-error → derivative-on-measurement | Tránh kick khi đổi setpoint, chuẩn ngành |
| Trung bình | Thêm dt thực đo vào ki/kd | Rẻ để sửa, không rủi ro downside, phòng khi tải hệ thống tăng |
| Thấp | Anti-windup back-calculation thay vì clamp | Cải thiện biên, không cấp thiết |
| Thấp | Gain PID theo từng jig/motor | Dữ liệu ma sát đã cho thấy khác biệt thật giữa các jig |

---

## Trạng thái tool và test

Tất cả tool trên đều có test hồi quy hand-checkable trong `analysis/matlab/tests/` (không phụ thuộc log phần cứng), cộng với ít nhất 1 lần chạy trên dữ liệu thật để đối chiếu. Chạy toàn bộ:

```powershell
matlab -batch "addpath('analysis/matlab'); addpath('analysis/matlab/tests'); test_a2_analysis; test_a3_a4_a5_analysis; test_b0b_analysis; test_nl_stability_analysis; test_health_analysis"
```

Trạng thái tại thời điểm viết tài liệu này: **PASS cả 5/5 bộ**.
