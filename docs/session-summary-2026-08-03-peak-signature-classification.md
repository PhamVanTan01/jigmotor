# Tổng kết phiên làm việc 2026-08-03: full-curve peak analysis, MOUNT_PRECHECK pilot pool, jig peak-signature classifier

Tài liệu này ghi lại đúng những gì đã làm/tìm được trong phiên hội thoại này, để một agent/phiên khác đọc lại và tiếp tục mà không cần dựng lại ngữ cảnh từ đầu. Đây là phiên **khác** với phiên đã tạo `docs/session-summary-2026-08-03-mount-precheck-and-assembly-swap.md` (gọi tắt "session-swap" bên dưới) và tài liệu `docs/nl-jig1-jig4-rootcause-debug-plan-2026-08-03.md` (gọi tắt "debug-plan") — phiên này bắt đầu từ debug-plan, nhận thêm phát hiện swap từ session-swap giữa chừng, rồi mở rộng phân tích full-curve.

## 1. Bối cảnh nhận được giữa phiên

Người vận hành chia sẻ `session-swap` (viết bởi một phiên song song cùng ngày): cụm sensor+gá (MA600 + mounting) đã bị tráo giữa các board trong lúc thao tác, phát hiện qua so khớp chữ ký full-curve (`r=0.9984`). Kết luận: khác biệt NL giữa "JIG1/JIG4/JIG5" đi theo **cụm sensor+gá vật lý**, độc lập với board điều khiển/firmware. Tên `JigID` trong log **không đảm bảo** là định danh vật lý cố định.

## 2. Phân tích full-curve mở rộng (không phải công cụ mới, chỉ là cách chạy mới trên dữ liệu đã có)

### 2.1. So sánh tại 371 điểm (đầy đủ, thay vì 360 điểm `AnalysisPoints`)

Chạy trên `S2-P03/P05-JIG1/JIG4-test-1.txt` (dữ liệu 2026-07-31, trước vụ tráo). Kết quả:

- 11 điểm margin/closure (idx 360-370, lần lặp lại 0°-10°) **không chứa cực trị mới nào** — 0/5 top, 0/5 bottom ở cả 4 nhóm. Cửa sổ 360 điểm hiện tại không bỏ sót đỉnh/đáy nào.
- Nhưng lộ ra một pattern "closure-creep": lệch giữa lần đo lại (idx 360-370) và lần đầu (idx 0-10) tăng dần từ ~0 lên 0.07-0.12° khi đi qua idx 6-10, **giống hệt nhau giữa JIG1 và JIG4** (cross-jig r=0.86 với P03, r=0.95 với P05). Kết luận: hiệu ứng này đến từ motor/motion-profile, KHÔNG phải từ cụm sensor+gá — cần loại trừ khỏi phân tích root-cause "khác biệt do jig".

### 2.2. Toàn bộ đỉnh trên/dưới (không chỉ top-5/bottom-5)

Tìm toàn bộ 36 local maxima + 36 local minima (ripple bậc 36) trên cùng dữ liệu trên, ghép cặp JIG1↔JIG4 theo vị trí sau khi căn chỉnh (shift tốt nhất đã biết trước: P03=40°, P05=240°). Kết quả:

- **Vị trí 36 đỉnh trên + 36 đỉnh dưới khớp gần như tuyệt đối** (lệch 0-1 điểm) ở cả 2 sản phẩm — "khung xương" order-36 đến từ chính motor, bảo toàn qua các cụm sensor+gá khác nhau.
- **Biên độ từng đỉnh mới là thứ khác nhau**, và kiểu khác nhau khác hẳn theo sản phẩm:
  - P03: lệch vừa phải (mean|Δ|≈0.135°), pha trộn dấu, tập trung ở vài góc cụ thể.
  - P05: lệch lớn hơn (mean|Δ|≈0.35-0.37°), gần như đồng nhất MỘT chiều trên toàn bộ 72 đỉnh (71/72 điểm cùng dấu) — giống một phép scale/offset toàn cục hơn là lệch cục bộ, nghi ngờ khe hở Z hoặc gain sensor khác nhau giữa 2 cụm.

## 3. Cơ chế phát hiện lỗi cơ khí sensor — tổng hợp từ commit `fb143d4`

(Câu hỏi thuần giải thích, không tạo code mới ở bước này — nhưng feed trực tiếp vào thiết kế tool ở mục 4/5.)

`Core/Src/nonlinear_test.c:6350-6394` — mỗi sweep PRECONDITION tự log 1 dòng `MOUNT_PRECHECK_RESULT` (vân tay gá lắp): `RobustP2PDeg, H1AmplitudeDeg, H1PhaseDeg, H2AmplitudeDeg, H2PhaseDeg, ClosureErrorDeg, TrackingValid, ClosureValid, AcquisitionResult, MountValid, RejectReason`. `MountValid` hiện chỉ dựa 3 điều kiện an toàn tổng quát (`nonlinear_test.c:6357-6359`), **chưa dùng H1/H2** vì comment code (`nonlinear_test.c:1026-1037`) nói rõ: *"H1 shrinks and sometimes H2 grows under bad mounting... not yet calibrated (one clean vs. one confounded sample per product so far)"* — H1/H2 vẫn được log đầy đủ để dành hiệu chuẩn sau.

Các dấu hiệu khác đã dùng để tìm root cause thật (trong session-swap): signature-matching full-curve (r gần 1.0 trùng khớp jig khác), H36/A36 ổn định (loại trừ motor), remount-range gate ≤0.05° (JIG4 gốc 0.0195° pass, JIG1/JIG5 gốc 0.083-0.084° fail).

## 4. Tool mới: `analyze_mount_precheck_batch.m` — pilot pool cho ngưỡng H1/H2

**File**: `analysis/matlab/nl/parse_mount_precheck_log.m` (parser đứng độc lập cho record `MOUNT_PRECHECK_RESULT`), `analysis/matlab/nl/analyze_mount_precheck_batch.m` (gộp nhiều file/label, thống kê `H1AmplitudeDeg`/`H2AmplitudeDeg`/`H2OverH1`/`MountValidRatePct` theo từng label + breakdown `RejectReason`). Test: `test_mount_precheck()` trong `analysis/matlab/tests/test_nl_stability_analysis.m`.

Chạy trên 24 file thật có `MOUNT_PRECHECK_RESULT` trong `captured-logs/`: nhóm **H1 cao (0.42-0.54°), H2/H1 thấp** toàn bộ là `S1-P05-JIG4-remount*`/`JIG4-p07` (100% MountValid) — khớp "cụm tốt" đã biết. Nhóm **H1 thấp-trung (0.25-0.36°)**, toàn bộ 5 case `CLOSURE_INVALID` đều rơi vào family `S2-P05-JIG1-remount*` — khớp "cụm có vấn đề" đã biết. Hai phương pháp độc lập (remount-range vs H1/H2 fingerprint) ra cùng kết luận — bằng chứng cross-validate tốt, nhưng **`MotorID=UNKNOWN`** ở phần lớn record, và nhãn `JigID` chưa xác nhận vật lý (mục 1) nên chưa dùng để chốt ngưỡng chính thức.

## 5. Tool mới: phân loại jig theo toàn bộ đỉnh + góc lỗi tại đỉnh

**File**: `analysis/matlab/nl/find_circular_extrema.m` (tìm local max/min trên đường cong vòng tròn, xử lý đúng trường hợp 2 điểm liền kề trùng giá trị — lấy điểm đầu "thềm trùng" thay vì loại bỏ cả đỉnh, bug đã tìm và sửa qua unit test), `analysis/matlab/nl/match_circular_peaks.m` (ghép cặp đỉnh gần nhau giữa 2 đường cong), `analysis/matlab/nl/classify_jig_peak_signatures.m` (orchestrator: build đường cong trung bình mỗi jig qua `build_nl_group_curve.m`, ghép toàn bộ đỉnh/đáy, phân loại `SAME_CLASS`/`DIFFERENT_CLASS` theo ngưỡng `MeanAbsDeltaDeg` — mặc định 0.10°, **chưa hiệu chuẩn, chỉ là giá trị chẩn đoán** giống cách chọn ngưỡng của `sector_match_gate.m`). Test: `test_peak_signature_tools()` trong cùng file test, 3 nhóm cảnh giả lập (2 giống hệt, 1 scale biên độ khác) kiểm chứng toàn bộ pipeline.

**Chạy trên dữ liệu thật, P05 (JIG1/JIG4/JIG5, cùng phiên 2026-08-03, gộp 3 remount/jig)**:

| Cặp | Shift | Correlation | Mean\|Δ\| | Class |
|---|---|---|---|---|
| JIG1↔JIG4 | 40° | 0.916 | 0.421° | DIFFERENT_CLASS |
| JIG1↔JIG5 | 0° | 0.990 | 0.091° | **SAME_CLASS** |
| JIG4↔JIG5 | 320° | 0.872 | 0.429° | DIFFERENT_CLASS |

**Người vận hành xác nhận: bộ dữ liệu này được đo TRƯỚC KHI vụ tráo cụm được phát hiện** — nghĩa là nhãn `JigID` ở đây rất có thể đã ở đúng trạng thái bị lẫn (chưa ai biết) mô tả trong session-swap §3.5. Kết quả `JIG1(nhãn)≈JIG5(nhãn)` (cùng lớp) trong khi cả hai khác `JIG4(nhãn)` **khớp đúng kiểu bất thường** mà session-swap mô tả (2 board tên khác nhau ra cùng chữ ký) — khả năng cao là cùng loại tín hiệu hoặc liên quan trực tiếp đến vụ việc đã ghi nhận. **Chưa xác định được** cụm vật lý nào (JIG1-gốc/JIG4-gốc/JIG5-gốc) tương ứng chính xác với board nào trong bộ dữ liệu này — session-swap chỉ nêu rõ trạng thái cuối phiên cho JIG1/JIG5 (không nêu JIG4), nên nếu là hoán vị 3 chiều thì cần xác minh vật lý mới chốt được.

P03 (JIG1/JIG4 đo 2026-07-31, JIG5 đo 2026-08-03 — khác ngày) cũng chạy nhưng độ tin cậy thấp hơn vì lẫn yếu tố khác phiên đo; cả 3 cặp ra `DIFFERENT_CLASS`.

**Chi tiết theo đỉnh (P05, JIG1↔JIG4)**: khác biệt lớn nhất tập trung cục bộ ở cung ~27°-57° (delta tới -0.97°), JIG4↔JIG5 tập trung ở cung khác hẳn ~67°-94° — mỗi cặp có "vùng nóng" riêng, không phải một hiệu ứng toàn cục đồng nhất.

## 6. Trạng thái test

`test_a2_analysis`, `test_a3_a4_a5_analysis`, `test_b0b_analysis`, `test_nl_stability_analysis` (nay gồm cả `test_mount_precheck` và `test_peak_signature_tools`), `test_health_analysis` — **PASS 5/5** tại thời điểm viết tài liệu này.

## 7. Việc chưa hoàn thành / đề xuất cho phiên sau

Người vận hành đã ghi nhận sẽ cân nhắc, **chưa quyết định làm ngay** — để lại đây cho phiên sau chọn tiếp:

1. **Xác minh vật lý cấu hình hiện tại** (kế thừa mục 4 của session-swap, vẫn chưa làm): đánh nhãn A/B/C độc lập tên board lên từng cụm sensor+gá, đối chiếu với kết quả `JIG1≈JIG5` ở mục 5 để biết chính xác cụm nào đang ở đâu.
2. **Ghi phát hiện mục 5 vào session-swap hoặc debug-plan** một khi đã xác minh được vật lý — hiện tài liệu này chỉ ghi số liệu thô, chưa kết luận chính thức về danh tính cụm.
3. **Biến `classify_jig_peak_signatures.m` thành một check tự động** kiểu `sector_match_gate.m`: chạy ngay sau mỗi lần đổi board/cụm, cảnh báo tức thời nếu 2 board tên khác nhau rơi vào `SAME_CLASS` — để bắt lỗi tráo cụm ngay lúc xảy ra thay vì phải phân tích hậu kỳ như lần này.
4. Đo lại JIG5/P03 cùng ngày với JIG1/JIG4 để so sánh công bằng (hiện đang lệch ngày, mục 5).
5. Hiệu chuẩn ngưỡng `ClassifyThresholdDeg` (mục 5) và ngưỡng H1/H2 của `MOUNT_PRECHECK_V1` (mục 4) bằng cùng một bộ dữ liệu pilot mở rộng, một khi định danh vật lý đã được xác nhận (mục 1) — hai việc hiệu chuẩn này nên làm cùng lúc vì dùng chung tiền đề "biết chắc cụm nào đang gắn ở đâu".
