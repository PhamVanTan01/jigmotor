# Kế hoạch debug root-cause: JIG1 vs JIG4 lệch NL (2026-08-03)

Tài liệu này tổng hợp các bước tiếp theo cần làm để tìm ra root cause thật sự của việc JIG1 và JIG4 (cùng bệ cơ khí, khác board — xem `docs/hardware-validation-checklist.md`) cho ra `NL_RobustP2P_Deg` khác nhau khi test cùng một motor/sản phẩm. Đây là phần nối tiếp của `docs/nl-factors-jig-comparison-and-algorithm-review-2026-07-27.md` (gọi tắt là "tài liệu 07-27" bên dưới) — không lặp lại phân tích đã có, chỉ bổ sung phát hiện mới từ phiên trao đổi 2026-08-03 và xếp thứ tự việc cần làm tiếp.

## 1. Tình trạng hiện tại — đã biết / đã loại trừ / còn mở

| # | Nhận định | Trạng thái | Nguồn |
|---|---|---|---|
| 1 | JIG4 = board mới, cùng bệ cơ khí với JIG1 (không phải JIG5) | **Đã xác nhận** | `docs/hardware-validation-checklist.md`, tài liệu 07-27 §4.1 |
| 2 | `Zero` registry trong CONFIG chỉ dùng để audit/gate, KHÔNG dùng để tính góc thực (MA600 tự trả góc đã zero-hoá nội bộ trong chip) | **Đã xác nhận, bác bỏ giả thuyết "Zero lock khác nhau gây lệch sector"** | Tài liệu 07-27 §3 |
| 3 | Lệch sector (`AnalysisStartRaw`) giữa 2 jig có tương quan thật với lệch NL, nhưng chỉ giải thích **R²≈0.22** phương sai trong-cùng-sản-phẩm (fit trên 14 phiên A0 thật) | **Đã xác nhận, nhưng chỉ là lời giải một phần** | Tài liệu 07-27 §4.3, `fit_sector_response.m` |
| 4 | Sửa hậu kỳ bằng mô hình sector (`correct_delta_for_sector.m`) chỉ giảm RMS ~29%, và **sai chiều ở p05** | **Đã kiểm chứng — không đủ tin cậy dùng chính thức** | Tài liệu 07-27 §4.4 |
| 5 | `MotorIDValid=0` trên **mọi run** đã log được (cả 2 jig) — "cùng 1 motor" hiện chỉ là nhãn thủ công của người vận hành, không được firmware xác thực | **Đã xác nhận là giới hạn thật, chưa khắc phục** | Tài liệu 07-27 §3; `docs/phase2b-shadow-checklist.md` (waived, không phải bug) |
| 6 | Xoay sensor MA600 cơ khí 90° trên JIG1 (test-2) → sector đo được dịch **−178.1°** điện, khớp gần đúng lý thuyết 90°×6 cặp cực = 540° ≡ 180° (mod 360°) | **Bằng chứng mới, đơn-biến, kiểm soát tốt hơn fit gộp 14 phiên** | Phiên 2026-08-03 — `S2-P03-JIG1-test-1.txt` vs `test-2.txt` |
| 7 | Vòng kẹp ôm thân motor khít + trục dẫn hướng giữ cố định X,Y của cả cụm | **Đã xác nhận qua trao đổi trực tiếp với người vận hành** | Phiên 2026-08-03 |
| 8 | **Không có gì chặn thân motor xoay quanh trục chính nó (clocking) trong vòng kẹp trước khi siết** | **Đã xác nhận — DOF cơ khí hở duy nhất còn lại phía kẹp motor** | Phiên 2026-08-03 |
| 9 | Biên độ + pha của harmonic1 ("mounting/concentricity signature", do firmware tự tính) đổi giữa các lần gá lại **cùng 1 motor vật lý, cùng 1 jig** (JIG1/p05: A1 0.41–0.43°/≈−47°, A2 0.41–0.46°/≈−71°, test-1 0.23°/≈−75°) | **Quan sát thật, chưa xác định nguyên nhân cơ khí chính xác** | Phiên 2026-08-03, log `S2-P05-JIG1-A1/A2/test-1.txt` |

**Giả thuyết đang dẫn đầu** (chưa kiểm chứng bằng thực nghiệm riêng): mục 8 + 9 liên hệ nhân quả — nếu bản thân motor có lệch tâm nhỏ giữa trục/nam châm và vỏ ngoài (dung sai sản xuất bình thường), thì mỗi góc "clocking" khác nhau khi kẹp sẽ khiến lệch tâm đó chỉ về hướng khác nhau so với sensor cố định, vừa đổi biên độ vừa đổi pha harmonic1 — khớp dữ liệu tốt hơn giả thuyết "X-Y bị trôi ngẫu nhiên" (đã loại vì mục 7).

## 2. Kế hoạch hành động — theo thứ tự ưu tiên

### Bước 1 — Witness-mark test xác nhận giả thuyết clocking (rẻ nhất, làm trước tiên)

- **Cách làm**: đánh 1 vạch dấu cố định trên vỏ motor và 1 vạch trên vòng kẹp. Đo 3–5 lần, mỗi lần tháo ra lắp lại nhưng **luôn xoay motor để 2 vạch trùng nhau** trước khi siết. Không đổi gì khác (cùng motor, cùng jig, cùng sensor).
- **Tiêu chí kết luận**:
  - Nếu harmonic1 **ổn định lại** (biên độ *và* pha lặp lại giữa các lần, không chỉ biên độ) → xác nhận đúng nguyên nhân là clocking, chuyển sang Bước 3.
  - Nếu vẫn dao động dù giữ đúng 1 góc → còn nguồn khác (lực siết làm xê dịch nhẹ dù vòng khít, hoặc vòng kẹp thật ra không khít như mô tả) → quay lại điều tra cơ khí phần kẹp trước khi làm tiếp.
- **Công cụ phân tích**: `analyze_nl_stability_batch.m` (labels = từng lần đo witness-mark) để lấy CV%/SD của harmonic1 và của `NL_RobustP2P_Deg` cùng lúc.

### Bước 2 — Quét clocking có kiểm soát để dựng đường cong NL(θ) (nếu Bước 1 xác nhận giả thuyết)

- **Cách làm**: cùng 1 motor, cùng 1 jig, cố ý kẹp ở nhiều góc clocking biết trước (vd. 0°, 45°, 90°, 135°... quanh vòng kẹp, đánh dấu góc bằng thước đo góc hoặc vạch chia sẵn trên vòng), mỗi góc chạy 1 sweep đầy đủ.
- **Mục tiêu**: kiểm tra xem pha harmonic1 có tăng tuyến tính theo đúng góc clocking đã đặt hay không (độ dốc kỳ vọng ≈ 1:1 nếu đúng là "xoay một vector lệch tâm cố định"), và biên độ harmonic1 có xấp xỉ hằng số qua các góc hay không.
- **Công cụ**: cần viết thêm 1 script nhỏ (không có sẵn) đọc trực tiếp dòng `NL harmonic1` từ log (xem `parse_nl_log.m` để mở rộng parser lấy dòng free-text đó, hiện tool chỉ parse các record `KEY,...`) hoặc trích bằng regex ngoài MATLAB rồi đối chiếu góc đặt vs pha đo.

### Bước 3 — Đo runout thân motor độc lập, không qua encoder (xác nhận vật lý, không suy luận gián tiếp)

- **Cách làm**: dùng đồng hồ so (dial indicator) đo trực tiếp độ đảo (TIR) của trục/đầu nam châm so với đường kính ngoài thân motor, độc lập với MA600.
- **Mục tiêu**: xác nhận trực tiếp có tồn tại lệch tâm trục-vỏ nội tại trong chính con motor đang test hay không, thay vì chỉ suy luận từ harmonic1 đo qua sensor. Nếu đo được lệch tâm cơ khí thật ~cùng độ lớn dự đoán từ harmonic1 → củng cố mạnh giả thuyết; nếu gần như bằng 0 → phải tìm nguyên nhân khác (vd. vòng kẹp không khít như mô tả, hoặc lực siết gây biến dạng).

### Bước 4 — Bật/khôi phục xác thực `MotorIDValid` để so sánh cross-jig có truy vết được

- **Vấn đề**: mọi so sánh JIG1-vs-JIG4 hiện tại (kể cả bộ dữ liệu mới `S2-*-test-1.txt`) đều dựa trên nhãn thủ công "cùng sản phẩm", không có xác thực phần cứng — không loại trừ được khả năng đang so sánh 2 motor vật lý khác nhau.
- **Cách làm**: theo đúng hướng dẫn đã có trong `docs/phase2b-shadow-checklist.md` (mục Motor ID) — build firmware với `compiler define MOTOR_ID` gán đúng theo từng con motor, hoặc tối thiểu ghi tay số serial motor vào tên thư mục/file test mỗi lần đo.
- **Vì sao quan trọng**: nếu không làm bước này, mọi kết luận root-cause ở các bước trên vẫn có một lỗ hổng logic không thể đóng lại hoàn toàn ("có chắc là cùng 1 motor không?").

### Bước 5 — Mở rộng bộ dữ liệu JIG1-vs-JIG4 để thống kê tin cậy hơn

- **Vấn đề hiện tại**: bộ `S2-P03/P05-JIG1/JIG4-test-1.txt` mới chỉ có **2 sản phẩm** (n=2) — không đủ để `analyze_jig_delta.m`'s `pearson_test` tính r/p có ý nghĩa (cần n≥3). Bộ 14-phiên trong tài liệu 07-27 đã cho R²=0.22 nhưng đó là fit gộp lịch sử, chưa riêng cho đúng cặp JIG1-JIG4 với đủ số sản phẩm.
- **Cách làm**: đo thêm ít nhất 3-4 sản phẩm nữa theo đúng mẫu `S2-P0X-JIG1-test-1.txt` / `S2-P0X-JIG4-test-1.txt` (cùng điều kiện gá, có xác thực MotorID theo Bước 4 nếu đã sẵn sàng), rồi chạy lại `analyze_jig_delta.m` để có tương quan sector-vs-delta đủ mạnh thống kê cho riêng cặp JIG1-JIG4.

### Bước 6 — Bổ sung log chẩn đoán khe hở Z (air-gap)/độ vuông góc

- **Vấn đề**: hiện log không có field AGC/field-strength của MA600, nên không kiểm chứng được đóng góp của khe hở dọc trục (Z) hay độ nghiêng (tilt) vào nhiễu đo — hai DOF này vẫn hoàn toàn là "hộp đen" trong toàn bộ phân tích tới nay.
- **Cách làm**: kiểm tra datasheet/driver MA600 xem có thanh ghi AGC hoặc field-strength đọc được không; nếu có, thêm vào record log hiện có (`SHADOW_META`/`CONFIG`) để dùng cho phân tích sau này. Việc này không khẩn cấp nếu Bước 1-3 đã giải thích được phần lớn biến động quan sát được.

## 3. Nếu Bước 1-3 xác nhận clocking là root cause — hành động khắc phục

1. **Ngắn hạn (quy trình, không cần gia công)**: quy định thao tác luôn lắp motor theo đúng witness-mark đã đánh dấu, cho tới khi có sửa cơ khí.
2. **Trung hạn (cơ khí)**: thêm 1 vít định vị góc xoay xuyên vòng kẹp, ăn vào mặt bằng/lỗ có sẵn trên vỏ motor (không cần bạc định tâm mới cho X-Y — phần đó đã tốt, xem mục 1.7).
3. **Kết hợp với khuyến nghị đã có trong tài liệu 07-27 §4.5** (vẫn còn nguyên giá trị, không phụ thuộc kết quả clocking):
   - Ngắn hạn: dùng `sector_match_gate.m` làm điều kiện bắt buộc trước khi so sánh NL giữa 2 jig/phiên (mặc định ngưỡng 200 raw ≈ 6.6° điện).
   - Trung hạn: thí nghiệm quét sector chủ động (đã mở rộng thành Bước 2 ở trên, gộp chung với thí nghiệm clocking vì cùng cơ chế nghi vấn).
   - Dài hạn: cân nhắc sửa firmware để A0 chọn sector cố định/kiểm soát được, loại bỏ nguồn nhiễu tận gốc — **chỉ nên làm sau khi Bước 1-3 xác nhận rõ tỷ trọng đóng góp của clocking vs sector-điện vs motor-to-motor**, để không sửa nhầm chỗ.

## 4. Bảng công cụ MATLAB dùng cho từng bước

| Bước | Tool | Vị trí |
|---|---|---|
| 1, 5 | Parse log, tính metric mỗi sweep | `analysis/matlab/nl/parse_nl_log.m`, `compute_nl_sweep_metrics.m` |
| 1 | Thống kê ổn định (CV%, SD, repeatability limit) theo từng leg | `analysis/matlab/nl/analyze_nl_stability_batch.m` |
| 5 | So lệch cặp jig cùng sản phẩm + tương quan sector-vs-delta | `analysis/matlab/nl/analyze_jig_delta.m` |
| 2 | Fit mô hình sector-response gộp nhiều phiên (tham khảo, không thay cho quét clocking riêng) | `analysis/matlab/nl/fit_sector_response.m` |
| 3 (đối chiếu phần mềm, sau khi có số đo cơ khí độc lập) | So NL đo được vs dự đoán từ mô hình sector | `analysis/matlab/nl/correct_delta_for_sector.m` |
| Bất kỳ so sánh cross-jig nào trong tương lai | Gate hợp lệ trước khi so sánh trực tiếp | `analysis/matlab/nl/sector_match_gate.m` |

## 5. Tiêu chí coi là "đã tìm ra root cause"

- Harmonic1 (biên độ + pha) **lặp lại ổn định** (dao động trong khoảng nhiễu đo nền, không còn đổi theo lần tháo/lắp) sau khi khoá được DOF nghi vấn — đối chiếu bằng `analyze_nl_stability_batch.m` (CV% harmonic1 nên về cùng bậc với CV% của `NL_RobustP2P_Deg` trong-phiên đã đo được, ~0.2–1.5%).
- Có ít nhất một thực nghiệm **đơn biến, có kiểm soát** (không phải suy luận từ dữ liệu gộp lịch sử) xác nhận chiều và độ lớn quan hệ nhân quả — witness-mark test (Bước 1) hoặc quét clocking (Bước 2) đóng vai trò này, tương tự cách thử nghiệm xoay sensor 90° đã làm với giả thuyết sector.
- Sau khi khoá DOF nghi vấn, chạy lại đúng cặp `S2-P0X-JIG1-test-*.txt` vs `S2-P0X-JIG4-test-*.txt` và thấy `ΔNL_RobustP2P_Deg` giữa 2 jig giảm rõ rệt so với baseline hiện tại (P03: −0.037°, P05: −0.240°) — nếu không giảm, root cause thật sự nằm ở nơi khác (nhiều khả năng nhất: motor-to-motor variation, xem Bước 4).
