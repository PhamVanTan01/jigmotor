# Kế hoạch debug root-cause: JIG1 vs JIG4 lệch NL (2026-08-03, rev. 2)

Tài liệu này tổng hợp các bước tiếp theo cần làm để tìm ra root cause thật sự của việc JIG1 và JIG4 (cùng bệ cơ khí, khác board — xem `docs/hardware-validation-checklist.md`) cho ra `NL_RobustP2P_Deg` khác nhau khi test cùng một motor/sản phẩm. Đây là phần nối tiếp của `docs/nl-factors-jig-comparison-and-algorithm-review-2026-07-27.md` (gọi tắt "tài liệu 07-27") và `docs/nl-extreme-angle-cross-jig-test33-assessment.md` (gọi tắt "Test 33") — không lặp lại phân tích đã có, chỉ bổ sung phát hiện mới và xếp thứ tự việc cần làm tiếp.

**rev. 2** sửa 2 lỗi kỹ thuật của rev. 1 sau một vòng review, và tích hợp dữ liệu Test 33 đã có sẵn nhưng rev. 1 bỏ sót:

1. `parse_nl_log.m` **đã** parse sẵn `RESULT.A1`, `RESULT.H1_PhaseSweepDeg`, `RESULT.PhaseValidMask` (đã kiểm chứng trực tiếp trong log, vd. `S2-P03-JIG1-test-1.txt:1888`) — rev. 1 nói sai là "cần mở rộng parser lấy dòng free-text". Không cần regex; chỉ thiếu một tool tổng hợp thống kê từ các field đã có sẵn này.
2. `H1_PhaseSweepDeg` là pha **tương đối theo sweep** (mốc 0 tại điểm bắt đầu sweep), không phải pha cơ khí/điện tuyệt đối — so sánh trực tiếp giữa các phiên/jig mà không quy về cùng hệ quy chiếu (qua `AnalysisStartRaw`) là sai.

**Kết luận tổng quát (không đổi bởi rev. 2, chỉ chính xác hoá)**: dự án đã đạt **repeatability trong một lần gá** (SPI/acquisition/PID đã kiểm chứng ổn định — tài liệu 07-27 §5), nhưng **chưa đạt reproducibility giữa 2 jig và sau remount**. Đây là bài toán Measurement System Analysis / Gauge R&R, chưa phải bằng chứng đọc sai dữ liệu hay lỗi thuật toán. Các giá trị NL/RMS_AC/A36/H1/H2 hiện là thông số của **toàn hệ thống motor+jig+sensor+controller+gá**, chưa thể coi là thông số nội tại riêng của motor.

## 1. Tình trạng hiện tại — đã biết / đã loại trừ / còn mở

| # | Nhận định | Trạng thái | Nguồn |
|---|---|---|---|
| 1 | JIG4 = board mới, cùng bệ cơ khí với JIG1 (không phải JIG5) | **Đã xác nhận** | `docs/hardware-validation-checklist.md`, tài liệu 07-27 §4.1 |
| 2 | `Zero` registry trong CONFIG chỉ dùng để audit/gate, KHÔNG dùng để tính góc thực | **Đã xác nhận, bác bỏ giả thuyết "Zero lock khác nhau gây lệch sector"** | Tài liệu 07-27 §3 |
| 3 | Lệch sector (`AnalysisStartRaw`) giữa 2 jig có tương quan thật với lệch NL, nhưng chỉ giải thích **R²≈0.22** phương sai trong-cùng-sản-phẩm (fit trên 14 phiên A0) | **Đã xác nhận, chỉ là lời giải một phần** | Tài liệu 07-27 §4.3, `fit_sector_response.m` |
| 4 | Sửa hậu kỳ bằng mô hình sector chỉ giảm RMS ~29%, **sai chiều ở p05** | **Đã kiểm chứng — không đủ tin cậy dùng chính thức** | Tài liệu 07-27 §4.4 |
| 5 | `MotorIDValid=0` trên **mọi run** đã log được (cả 2 jig, cả Test 33 lẫn bộ S2 mới) | **Giới hạn thật, chưa khắc phục — xem Bước 0** | Tài liệu 07-27 §3; `docs/phase2b-shadow-checklist.md` |
| 6 | Xoay sensor MA600 cơ khí 90° trên JIG1 (test-2) → sector đo được dịch **−178.1°** điện, khớp gần đúng lý thuyết 90°×6 cặp cực = 540° ≡ 180° (mod 360°) | **Bằng chứng đơn-biến, kiểm soát tốt** | Phiên 2026-08-03 — `S2-P03-JIG1-test-1.txt` vs `test-2.txt` |
| 7 | Vòng kẹp ôm thân motor khít + trục dẫn hướng giữ cố định X,Y của cả cụm | **Đã xác nhận qua trao đổi trực tiếp** | Phiên 2026-08-03 |
| 8 | Không có gì chặn thân motor xoay quanh trục chính nó (clocking) trong vòng kẹp trước khi siết | **Đã xác nhận — DOF cơ khí hở còn lại phía kẹp motor** | Phiên 2026-08-03 |
| 9 | Biên độ + pha harmonic1 đổi giữa các lần gá lại cùng 1 motor, cùng 1 jig (JIG1/p05: A1 0.41–0.46°, test-1: 0.23°) | Quan sát thật; **pha đọc từ free-text log trong rev. 1 chưa quy về hệ quy chiếu chung — xem mục 2 rev. 2** | Phiên 2026-08-03, log `S2-P05-JIG1-A1/A2/test-1.txt` |
| 10 | **Test 33**: 5 motor (P02/P03/P05/P06/P07) × JIG1+JIG4 × 10 run hợp lệ/nhóm = 100 run. Curve shape tương quan cao (`r=0.878–0.984`, hầu hết 0° shift); ΔNL từ **+0.05° đến +0.45°**, luôn dương (JIG4 cao hơn) trong bộ này | **Đã có sẵn trong repo, rev. 1 bỏ sót** | `docs/nl-extreme-angle-cross-jig-test33-assessment.md`, `analysis-out/test33-nl-extreme-angles/*.csv` |
| 11 | Bộ S2 mới (2026-08-03, n=2 sản phẩm): ΔNL **âm** cả 2 sản phẩm (P03 −0.037°, P05 −0.240°) — **ngược dấu** với Test 33 cùng sản phẩm | **Mâu thuẫn trực tiếp với giả thuyết "JIG4 có bias cố định"** | Đối chiếu mục 10 |
| 12 | A36 luôn cao hơn trên JIG4, cả Test 33 lẫn bộ S2, nhưng biên độ chỉ ~0.01–0.016° | **Đầu mối hệ thống đáng chú ý, không đủ giải thích ΔNL tới 0.45°** | Test 33 (theo review), cần đối chiếu lại bằng `compute_nl_sweep_metrics.m` |

### 1.1. Vì sao không có "bias JIG4" ổn định

So Test 33 với bộ S2 mới, cùng sản phẩm P03/P05, dấu ΔNL đảo chiều hoàn toàn (mục 10 vs 11). Điều này **không phù hợp với một lỗi board cố định** (nếu vậy dấu phải nhất quán). Nó phù hợp hơn với một tương tác nhiều biến:

```text
ΔNL = f(motor × clocking × remount × sensor-geometry × jig/drive)
```

Test 33 tự thân cũng cho thấy robust-NL scalar có thể **che mất** biến đổi thật: P03/P06 có cả top-5 và bottom-5 cùng dịch chuyển nên phép trừ `ΔNL = Δtop5 − Δbottom5` gần như triệt tiêu (P03: `+0.215°` và `+0.164°` → `ΔNL` chỉ `+0.051°`), trong khi P05 lệch chủ yếu do đáy JIG4 sâu hơn `0.388°` với đỉnh gần như không đổi. P07 cần dịch vòng 240° để đạt tương quan cao nhất — nghĩa là so sánh của P07 bị confound bởi orientation/sector, không dùng được làm bằng chứng "feature góc tuyệt đối chung" nếu chưa có datum cơ khí chung giữa 2 jig.

**Hệ quả cho toàn bộ kế hoạch**: mọi bước dưới đây phải theo dõi **cả full-curve và top-5/bottom-5 riêng biệt**, không chỉ một số `NL_RobustP2P_Deg` — nếu không sẽ đọc nhầm "không đổi" trong khi thực ra 2 đuôi đang dịch chuyển cùng chiều và tự triệt tiêu nhau trong phép trừ.

## 2. Vấn đề hệ quy chiếu pha harmonic — phải sửa trước khi diễn giải bất kỳ số H1/H2 nào

`H1_PhaseSweepDeg` (và `H2_PhaseSweepDeg`, v.v.) trong record `RESULT` là pha **tương đối theo sweep**, không phải pha cơ khí/điện tuyệt đối trong không gian jig. So sánh trực tiếp giá trị này giữa các lần gá khác nhau (hoặc giữa 2 jig) mà không quy đổi là sai hệ quy chiếu — có thể khiến clocking cơ khí, sector điện, và pha harmonic bị **trộn lẫn thành một "nguyên nhân" giả**.

**Cách sửa**: chuyển về cùng hệ quy chiếu bằng `AnalysisStartRaw` của mỗi sweep, rồi phân tích bằng vector thay vì trừ trực tiếp góc (góc là đại lượng vòng, không được lấy trung bình/hiệu số tuyến tính):

```text
C1 = A1 × cos(phase_absolute)
S1 = A1 × sin(phase_absolute)
```

với `phase_absolute` đã cộng/trừ offset suy từ `AnalysisStartRaw`. Giữa JIG1 và JIG4 vẫn cần thêm **một datum cơ khí chung** (vd. witness-mark ở Bước 0) vì `AnalysisStartRaw` tự nó không phải toạ độ cơ khí chia sẻ giữa 2 jig (đúng cảnh báo đã có trong Test 33: *"MA600 raw zero belongs to each individual sensor/jig... not a shared traceable mechanical coordinate"*).

**Gate biên độ trước khi tin bất kỳ pha nào**: pha của một hài không có ý nghĩa khi biên độ quá nhỏ so với nhiễu nền. Ngưỡng đề xuất: chỉ dùng pha khi amplitude ≥ 0.05°. Ví dụ P05/JIG4 có `A1≈0.0233°` trong một số nhóm — pha H1 của nhóm này **không được dùng** để kết luận về clocking. `PhaseValidMask` (đã có sẵn trong `RESULT`, xem `S2-P03-JIG1-test-1.txt:1888`) cần được đọc và tôn trọng, không bỏ qua.

## 3. Kế hoạch hành động — theo thứ tự ưu tiên

### Bước 0 — Khoá định danh & điều kiện đo (bắt buộc TRƯỚC mọi thực nghiệm nhân quả)

Chuyển lên trước witness-mark vì mọi kết luận nhân quả ở các bước sau đều vô nghĩa nếu không chắc "cùng 1 motor thật":

- Serial vật lý của motor đang test (ghi tay nếu firmware chưa hỗ trợ `MotorIDValid=1` — xem `docs/phase2b-shadow-checklist.md`).
- Witness mark cố định trên vỏ motor + vòng kẹp (dùng chung cho Bước 1 và Bước 2).
- Manifest ghi rõ: motor–jig–firmware BuildID/HEX checksum–ngày giờ–người vận hành cho mỗi lần đo.
- Lực siết vít kẹp (torque) — cố định bằng cờ-lê lực nếu có, ghi lại giá trị.
- Cable routing và khe hở Z — chụp ảnh/ghi chú tình trạng lắp mỗi lần, vì đây vẫn là DOF chưa đo được (xem Bước 6).

### Bước 1 — Baseline nhiễu nền, không remount

Trước khi test remount/clocking, đo baseline: cùng 1 lần gá, chạy nhiều sweep liên tiếp KHÔNG tháo ra, để tách nhiễu nền (thermal/session drift) khỏi hiệu ứng remount ở các bước sau. Đây là mức "sàn" để so sánh — nếu witness-mark test ở Bước 2 cho biến động cùng bậc với baseline này thì coi như đã ổn định.

### Bước 2 — Witness-mark test (≥5 lần gá lại độc lập, không chỉ 3–5 sweep đơn lẻ)

- **Cách làm**: dùng witness mark từ Bước 0. Thực hiện **tối thiểu 5 lần tháo/lắp độc lập**, mỗi lần trùng đúng vạch dấu trước khi siết; mỗi lần lắp chạy đủ 1 precondition + ~3 official sweep (không phải 1 sweep/lần — một sweep không tách được hiệu ứng remount khỏi trôi nhiệt/phiên).
- **Tiêu chí kết luận**: so biến động (biên độ *và* vector C1/S1, không phải pha thô) với baseline Bước 1.
  - Về cùng bậc với baseline → X-Y/clocking đã đủ ổn định trong điều kiện witness-mark, chuyển sang Bước 4 (đo runout độc lập) để xác nhận vật lý, hoặc thẳng tới Bước 5 nếu ưu tiên thời gian.
  - Vẫn dao động rõ rệt dù giữ đúng vạch → còn nguồn khác (lực siết làm xê dịch nhẹ dù vòng khít, torque không đồng nhất) → điều tra tiếp phần cơ khí kẹp trước khi làm Bước 3.
- **Công cụ**: `analyze_nl_stability_batch.m` cho `NL_RobustP2P_Deg`/closure (đã có); **cần viết mới** một tool tổng hợp circular/vector statistics cho `RESULT.A1`+`RESULT.H1_PhaseSweepDeg` (quy đổi qua `AnalysisStartRaw` theo mục 2) — không cần regex, các field nguồn đã được `parse_nl_log.m` parse sẵn vào `sweep.RESULT`.

### Bước 3 — Clocking test: tách rõ khỏi sector điện

Motor có 6 cặp cực, nên `Δθ_điện = 6 × Δθ_cơ`. Một sweep clocking 0°/45°/90° đồng thời đổi cả sector điện — **nếu không tách, có thể xác nhận nhầm clocking là root cause trong khi thực ra đang đo hiệu ứng sector đã biết (tài liệu 07-27 §4.3)**. Cần 2 thực nghiệm riêng:

1. **Sector-only sweep** (clocking cơ khí giữ cố định): theo khuyến nghị trung hạn đã có ở tài liệu 07-27 §4.5 mục 2 — quét sector chủ động (nếu firmware/quy trình cho phép chọn điểm dừng rotor khác nhau mà không tháo motor), dùng để tách riêng phần đóng góp đã biết (R²≈0.22) khỏi phần còn lại.
2. **Clocking-only sweep, bước 60° cơ khí**: 60°×6=360°≡0° điện — mỗi bước clocking 60° quay trở lại **cùng một sector điện**, cô lập được hiệu ứng cơ khí thuần tuý. Mỗi góc (0°/60°/120°/180°/240°/300°) cần **≥3 lần gá lại độc lập**, thứ tự góc phải **randomize** (không đo tuần tự 0→60→120... để tránh nhầm với trôi theo thời gian), và có **bracket quay lại 0° (A–B–A)** ở đầu/cuối để phát hiện drift. Sau mỗi góc, **vẫn phải gate `AnalysisStartRaw` bằng `sector_match_gate.m`** để xác nhận sector điện thực sự không đổi như tính toán — nếu lệch vượt ngưỡng, góc đó bị confound và phải loại khỏi kết luận clocking.
- **Tiêu chí kết luận**: pha (vector C1/S1, sau khi quy đổi hệ quy chiếu theo mục 2) có xoay tuyến tính đúng theo góc clocking đã đặt (độ dốc ≈ 1:1) hay không, trong khi biên độ A1 giữ xấp xỉ hằng số.

### Bước 4 — Đo runout thân motor độc lập, không qua encoder

- **Cách làm**: dùng đồng hồ so (dial indicator) đo trực tiếp độ đảo (TIR) của trục/đầu nam châm so với đường kính ngoài thân motor, độc lập với MA600.
- **Mục tiêu**: xác nhận trực tiếp có tồn tại lệch tâm trục-vỏ nội tại trong motor hay không, thay vì chỉ suy luận qua harmonic1 đo bằng sensor. Khớp cả hướng lẫn độ lớn với Bước 3 → củng cố mạnh giả thuyết; lệch gần 0 → tìm nguyên nhân khác.

### Bước 5 — Cross-jig JIG1→JIG4→JIG1, chỉ sau khi same-jig đã đạt gate

Chỉ chạy bước này sau khi Bước 2/3 xác nhận same-jig remount đã ổn định trong ngưỡng chấp nhận được. Với mỗi cặp sản phẩm, đo theo thứ tự JIG1→JIG4→JIG1 (không chỉ JIG1→JIG4) để phát hiện drift theo thời gian độc lập với hiệu ứng jig.

- Mở rộng số sản phẩm lên **n≥5**, tái sử dụng khung Test 33 (đã có 5 motor) nhưng **bổ sung đầy đủ Bước 0** (Test 33 hiện chưa khoá MotorID/torque/clocking/gap, nên dù n=5 vẫn chưa đủ để chốt root cause — chỉ đủ để thấy hiệu ứng "có thật và có cấu trúc", như phần 1.1 đã phân tích).
- Theo dõi đồng thời cho mỗi run: full 360-point differential curve, top-5/bottom-5 riêng biệt, `NL_RobustP2P_Deg`/`RMS_AC_Deg`/`A36_Deg`, vector `C1/S1` và `C2/S2` (mục 2), `ClosureErrorDeg` và post-turn residual, `AnalysisStartRaw`, tracking RMS/max, settle error.
- **Công cụ**: `analyze_jig_delta.m` (đã có, cần n≥3 sản phẩm để `pearson_test` có ý nghĩa — bộ S2 hiện tại n=2 không đủ, xem mục 1); `sector_match_gate.m` để gate từng cặp trước khi diễn giải.

### Bước 6 — Bổ sung log chẩn đoán khe hở Z (air-gap)/độ vuông góc

Không đổi so với rev. 1: hiện log không có field AGC/field-strength của MA600, Z và tilt vẫn là "hộp đen". Không khẩn cấp nếu Bước 1-4 đã giải thích được phần lớn biến động quan sát được; nếu residual sau Bước 5 vẫn lớn, đây là ứng viên tiếp theo cần điều tra.

## 4. Hành động khắc phục, theo kết quả từng nhánh

1. **Nếu Bước 2/3 xác nhận clocking là nguồn chính** (same-jig): thêm 1 vít định vị góc xoay xuyên vòng kẹp, ăn vào mặt bằng/lỗ có sẵn trên vỏ motor — không cần bạc định tâm mới cho X-Y (đã tốt, mục 1 #7).
2. **Không phụ thuộc kết quả clocking**, khuyến nghị đã có ở tài liệu 07-27 §4.5 vẫn còn nguyên giá trị:
   - Ngắn hạn: `sector_match_gate.m` bắt buộc trước khi so sánh NL giữa 2 jig/phiên bất kỳ (ngưỡng mặc định 200 raw ≈ 6.6° điện).
   - Trung hạn: thí nghiệm sector-only đã tách riêng ở Bước 3.1.
   - Dài hạn: sửa firmware để A0 chọn sector cố định — **chỉ làm sau khi Bước 3-5 xác nhận rõ tỷ trọng đóng góp của clocking vs sector-điện vs motor-to-motor**, tránh sửa nhầm chỗ.
3. **Nếu sau Bước 0+5 vẫn còn residual lớn không giải thích được bởi clocking/sector**: A36 elevated nhất quán trên JIG4 (mục 1 #12, cần verify lại bằng `compute_nl_sweep_metrics.m` trên chính dữ liệu Test 33/S2) là đầu mối hệ thống kế tiếp đáng điều tra (khác biệt drive/board giữa JIG1-JIG4), song với biên độ hiện thấy (~0.01–0.016°) khó giải thích hết dao động ΔNL tới 0.45° — không dùng làm kết luận chính khi chưa có thêm dữ liệu.

## 5. Bảng công cụ MATLAB dùng cho từng bước

| Bước | Tool | Vị trí | Ghi chú |
|---|---|---|---|
| Mọi bước | Parse log, tính metric mỗi sweep | `analysis/matlab/nl/parse_nl_log.m`, `compute_nl_sweep_metrics.m` | `RESULT.A1/H1_PhaseSweepDeg/PhaseValidMask` đã được parse sẵn, không cần sửa |
| 1, 2 | Thống kê ổn định (CV%, SD, repeatability limit) | `analysis/matlab/nl/analyze_nl_stability_batch.m` | Chỉ tổng hợp NL/closure — **cần viết mới** phần vector/circular stats cho H1/H2 |
| 3.1 | Fit mô hình sector-response gộp nhiều phiên | `analysis/matlab/nl/fit_sector_response.m` | Tham khảo, không thay cho sector-only sweep có kiểm soát |
| 3, 5 | Gate hợp lệ trước khi so sánh trực tiếp cross-jig/cross-remount | `analysis/matlab/nl/sector_match_gate.m` | Dùng ở MỌI bước có so sánh giữa 2 điều kiện, không chỉ cross-jig |
| 4 (đối chiếu phần mềm, sau khi có số đo cơ khí độc lập) | So NL đo được vs dự đoán từ mô hình sector | `analysis/matlab/nl/correct_delta_for_sector.m` | Đã kiểm chứng chỉ giảm ~29% RMS — không dùng làm sửa chính thức |
| 5 | So lệch cặp jig cùng sản phẩm + tương quan sector-vs-delta | `analysis/matlab/nl/analyze_jig_delta.m` | Cần n≥3 sản phẩm để `pearson_test` có ý nghĩa |
| 5 (tái sử dụng khung) | Phân tích extreme-angle/top-bottom + cross-jig curve correlation | `analysis/matlab/nl/analyze_nl_extreme_angles.m` (MATLAB) hoặc `tools/analyze_nl_extreme_angles.py` | Đã dùng cho Test 33; tái dùng cho bộ dữ liệu mở rộng ở Bước 5 |

## 6. Tiêu chí coi là "đã tìm ra root cause"

- Có **datum cơ khí chung** giữa các phiên đo trước khi so sánh bất kỳ pha nào (mục 2) — không dùng `H1_PhaseSweepDeg` thô làm bằng chứng.
- Vector C1/S1 của harmonic1 **lặp lại ổn định** (nằm trong bậc nhiễu nền đo ở Bước 1), sau khi khoá DOF nghi vấn — không chỉ biên độ, phải cả pha.
- Có ít nhất một thực nghiệm **đơn biến, có kiểm soát, đã tách sector khỏi clocking** (Bước 3) xác nhận chiều và độ lớn quan hệ nhân quả — không suy luận từ dữ liệu gộp lịch sử hay từ một sweep đơn lẻ mỗi điều kiện.
- Kết luận dùng **cả full-curve và top-5/bottom-5 riêng biệt**, không chỉ `NL_RobustP2P_Deg` scalar (mục 1.1 đã cho thấy scalar này có thể tự triệt tiêu).
- Sau khi khoá DOF nghi vấn và làm đủ Bước 0, chạy lại JIG1→JIG4→JIG1 trên n≥5 sản phẩm và thấy `ΔNL_RobustP2P_Deg` **cùng dấu, ổn định** giữa các sản phẩm (không còn đảo dấu như Test 33 vs bộ S2 hiện tại) — đây là tiêu chí quan trọng nhất vì một "root cause" thật phải tạo ra hiệu ứng nhất quán, không phải một hiệu ứng đổi dấu tuỳ phiên.
- Nếu vẫn đảo dấu sau khi đã khoá clocking/sector và khoá MotorID: chuyển trọng tâm điều tra sang motor-to-motor variation hoặc drive/board (A36, mục 1 #12) thay vì tiếp tục coi là vấn đề gá lắp.
