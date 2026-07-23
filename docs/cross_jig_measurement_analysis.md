# Cross-jig measurement analysis — P03/P05 × JIG1/JIG3

Toàn bộ số liệu trong tài liệu này được tính lại **độc lập từ `DATA`** bằng
`tools/analyze_motor_logs.py` (self-test DFT đã pass, khớp chính xác
`NlSelfTestCase1/2` của firmware — xem file đó) — **không dùng bất kỳ giá
trị `RESULT` nào của firmware làm ground truth**, đúng nguyên tắc đã đặt ra.

## 0. Xác nhận tính hợp lệ dữ liệu đầu vào (trả lời trực tiếp ALG-018)

Chạy parser trên 4 file chính (`v5-p03-test3 jig 1.txt`, `v5-p03-test3 jig
3.txt`, `v5-p05-test3 jig 1.txt`, `v5-p05-test3 jig 3.txt`): **cả 12/12
sweep đều `OFFICIAL-VALID`** (có META, có END với `Status=VALID`,
`MeasurementValid=1`, đủ 256/256 điểm phân tích, không có warning parse
nào). Kết luận: các số A6/A36/`DominantSelectedOrder` tôi báo cáo ở các
lượt trước trong phiên này (dựa trên grep trực tiếp `RESULT`) **không bị
lẫn sweep invalid** — may mắn không bị ảnh hưởng bởi lỗ hổng ALG-018 trong
trường hợp cụ thể này, nhưng đây là may mắn của bộ dữ liệu này, không phải
vì cách làm cũ (grep RESULT) vốn dĩ an toàn.

**Cảnh báo dữ liệu cần làm rõ, không được bỏ qua**: `docs/architecture-
migration-baseline.md` mô tả `p03-jig2.txt` là "negative regression
fixture" với `Tracking RMS error 102.0610°`/`Tracking max abs error
179.5331°`. Chạy parser (tự tính tracking độc lập từ cột `AngleRaw`/
`TargetRawAbs`, không phụ thuộc field nào firmware tự báo) trên file
`p03-jig2.txt` **hiện có trong workspace** cho ra 3 sweep hoàn toàn bình
thường (`TrackRMS` 1.06–1.38°, không phải 102°/179°) — và `grep` trực tiếp
file này cho "179"/"102"/`TrackingError_MaxAbs_Deg=1XX` **không tìm thấy
kết quả nào**. **UNKNOWN – file `p03-jig2.txt` hiện tại KHÔNG khớp mô tả
trong `architecture-migration-baseline.md`** — có thể file đã bị ghi đè bởi
một lần capture khác sau khi doc được viết, hoặc doc mô tả một file khác đã
đổi tên. Cần xác nhận với bạn trước khi coi bất kỳ nguồn nào (doc hay file)
là đúng — tôi không tự ý kết luận.

## 1. Bảng per-sweep (Run 1 = precondition)

| Motor | Jig | Run | RMS_AC | RawP2P | System_INL | RobustP2P | Closure | TrackRMS | TrackMax |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| p03 | JIG1 | 1 | 0.7754 | 3.7301 | 1.8650 | 3.2471 | −0.7330 | 1.0960 | 2.2632 |
| p03 | JIG1 | 2 | 0.7290 | 3.2308 | 1.6154 | 2.8730 | −0.3497 | 0.8525 | 1.8732 |
| p03 | JIG1 | 3 | 0.7202 | 2.9965 | 1.4982 | 2.7517 | −0.2277 | 0.7908 | 1.7084 |
| p03 | JIG3 | 1 | 0.7221 | 3.1254 | 1.5627 | 2.7762 | −0.6453 | 0.8598 | 1.9995 |
| p03 | JIG3 | 2 | 0.7036 | 2.6635 | 1.3317 | 2.5317 | −0.3535 | 0.7310 | 1.5601 |
| p03 | JIG3 | 3 | 0.6957 | 2.6393 | 1.3197 | 2.4985 | −0.4190 | 0.7494 | 1.6479 |
| p05 | JIG1 | 1 | 0.8484 | 4.2235 | 2.1118 | 3.7507 | −0.9684 | 1.4923 | 3.2135 |
| p05 | JIG1 | 2 | 0.8346 | 4.0716 | 2.0358 | 3.5969 | −0.7170 | 1.3193 | 2.9773 |
| p05 | JIG1 | 3 | 0.8204 | 3.9470 | 1.9735 | 3.5787 | −0.7820 | 1.3293 | 2.9224 |
| p05 | JIG3 | 1 | 0.7810 | 3.2908 | 1.6454 | 3.0804 | −0.7517 | 0.8990 | 2.0325 |
| p05 | JIG3 | 2 | 0.7387 | 2.9256 | 1.4628 | 2.8027 | −0.1545 | 0.7450 | 1.6370 |
| p05 | JIG3 | 3 | 0.7398 | 2.9047 | 1.4524 | 2.7711 | −0.1704 | 0.7432 | 1.5765 |

## 2. Mean/SD/CV theo run 2-3 (conditioned), theo Motor×Jig

| Motor/Jig | RMS_AC | RawP2P | System_INL | A1 | A2 | A9 | A36 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| p03/JIG1 | 0.7246 ± 0.0062 (0.85%) | 3.1136 ± 0.166 (5.3%) | 1.5568 ± 0.083 (5.3%) | 0.2185 ± 0.014 (6.2%) | 0.1840 ± 0.011 (6.0%) | 0.1897 ± 0.014 (7.6%) | **0.9079 ± 0.002 (0.18%)** |
| p03/JIG3 | 0.6997 ± 0.0056 (0.80%) | 2.6514 ± 0.017 (0.64%) | 1.3257 ± 0.009 (0.64%) | 0.1837 ± 0.009 (4.8%) | 0.0821 ± 0.007 (8.7%) | 0.1363 ± 0.002 (1.3%) | **0.9056 ± 0.003 (0.31%)** |
| p05/JIG1 | 0.8275 ± 0.0100 (1.2%) | 4.0093 ± 0.088 (2.2%) | 2.0047 ± 0.044 (2.2%) | 0.3255 ± 0.002 (0.6%) | 0.1834 ± 0.021 (11.6%) | 0.4080 ± 0.002 (0.5%) | **0.9304 ± 0.001 (0.13%)** |
| p05/JIG3 | 0.7392 ± 0.0008 (0.11%) | 2.9152 ± 0.015 (0.51%) | 1.4576 ± 0.007 (0.51%) | 0.0962 ± 0.004 (3.6%) | 0.0519 ± 0.008 (15.7%) | 0.3811 ± 0.005 (1.4%) | **0.9085 ± 0.0001 (0.02%)** |

## 3. Phân tích harmonic — bằng chứng phân tách motor-signature vs jig-signature

**A36 gần như bất biến** qua cả 4 tổ hợp motor×jig (0.906–0.930, CV nội bộ
mỗi nhóm chỉ 0.02–0.31%) — trong khi **A1/A2 biến động rất mạnh giữa hai
jig của cùng một motor** (P05: A1 từ 0.3255 xuống 0.0962, **giảm 70.4%**;
A2 từ 0.1834 xuống 0.0519, giảm 71.7%). A9 có hành vi trung gian: giảm 28%
ở P03 nhưng chỉ 6.6% ở P05.

**Trả lời trực tiếp mục 8, câu 1-3**:
1. **A36 (và ở mức độ thấp hơn, A9 cho P05) nhiều khả năng là motor
   signature** — ổn định cực cao dù đổi jig, đúng với cơ chế đã xác nhận
   trước đó (harmonic = pole_pairs × k, gắn với commutation/back-EMF của
   chính motor, không phải mounting).
2. **A1/A2 nhiều khả năng là jig/alignment signature** — biến động rất lớn
   khi đổi jig CÙNG một motor, khớp đúng ý nghĩa vật lý (harmonic bậc thấp
   1-2 = lệch tâm/mounting, theo chính comment gốc trong `nonlinear_test.c`).
3. **A36 gần nhau NHƯNG A1/A2 khác** vì hai bậc hài này có nguồn gốc vật lý
   khác nhau: A36 phụ thuộc cấu trúc điện của motor (không đổi khi đổi
   jig), A1/A2 phụ thuộc lắp đặt cơ khí (đổi hẳn khi đổi jig).

## 4. Vì sao P2P khác nhiều dù A36 gần nhau

`System_INL`/`RawP2P` là tổng hợp CỦA TẤT CẢ 12 bậc hài cộng với phần dư
residual — không chỉ A36. P03: JIG1→JIG3 P2P giảm 14.8% dù A36 gần như
không đổi (−0.3%); P05: P2P giảm tới 27.3% dù A36 chỉ đổi −2.3%. Phần lớn
chênh lệch P2P đến từ **A1/A2/A9 cộng dồn qua pha** (không chỉ biên độ) —
P2P là hàm phi tuyến của TOÀN BỘ phổ (max−min của tổng các sin/cos ở nhiều
pha khác nhau), nên một thay đổi nhỏ ở nhiều bậc hài thấp có thể cộng hưởng
pha và tạo chênh P2P lớn hơn nhiều so với chênh biên độ từng hài riêng lẻ.

## 5. Delta P03 khác delta P05 → có Product × Jig interaction thật không?

| Metric | Delta JIG1→JIG3, P03 | Delta JIG1→JIG3, P05 |
| --- | ---: | ---: |
| RawP2P | −14.8% | −27.3% |
| A1 | −15.9% | −70.4% |
| A2 | −55.4% | −71.7% |
| Closure | +33.8% | −78.3% |
| TrackMax | −10.4% | −45.5% |

**Delta của P03 và P05 KHÁC NHAU RÕ RỆT** (không chỉ khác độ lớn mà cả
dấu ở Closure) — đây LÀ bằng chứng ủng hộ mô hình có **Product × Jig
interaction thật**, không phải một offset cố định jig-only cộng thêm vào
mọi motor. Nếu jig-error là một hàm cộng tính thuần túy không phụ thuộc
motor, delta JIG1→JIG3 phải xấp xỉ NHAU cho mọi motor — thực tế không phải
vậy.

**Trả lời trực tiếp mục 8, câu 5-6**: delta P03 khác delta P05 **có**,
và **có** hỗ trợ giả thuyết `MotorJigInteraction_motor,jig(θ)` khác 0 trong
mô hình đề bài — dữ liệu 2 motor × 2 jig là quá ít để tách bạch hoàn toàn
interaction khỏi nhiễu đo (`AcquisitionError`) hay khỏi chính
`MotorSignature`/`JigError` từng phần riêng lẻ, nhưng độ lớn khác biệt delta
(gần gấp đôi giữa P03 và P05) **vượt xa** mức dao động run-to-run (CV nội
bộ nhóm chỉ 0.5-8%, xem mục 2) — nên khó giải thích chỉ bằng nhiễu ngẫu
nhiên. Cần thêm motor thứ 3 trở lên trên cùng 2 jig để tách bạch chắc chắn
(đúng thiết kế DOE mục 11.C của đề bài, chưa chạy).

## 6. Closure — phát hiện quan trọng nhất của phần này

Ngưỡng pilot theo `docs/nonlinear-metric-contract-v1.md`: `|ClosureErrorDeg|
≤ 0.20°`. Áp trực tiếp lên 12 sweep vừa tính (KHÔNG dùng field nào của
firmware, tự tính từ `error_deg` tại index 256):

| Motor/Jig/Run | Closure (°) | Đạt 0.20°? |
| --- | ---: | --- |
| p03/JIG1/1,2,3 | −0.733, −0.350, −0.228 | Không, không, không (sát biên) |
| p03/JIG3/1,2,3 | −0.645, −0.354, −0.419 | Không cả 3 |
| p05/JIG1/1,2,3 | −0.968, −0.717, −0.782 | Không cả 3 |
| p05/JIG3/1,2,3 | −0.752, −0.155, −0.170 | Không, **Đạt**, **Đạt** |

**Chỉ 2/12 sweep đạt ngưỡng closure pilot** (cả hai đều p05/JIG3, run 2-3).
Con số "2/12" này **được xác nhận độc lập** bằng chính công cụ mới viết,
khớp với số liệu đã nhắc tới ở một phiên review trước — nhưng lần này có
bằng chứng tính toán trực tiếp từ `DATA`, không dựa vào lời thuật lại.
**Kết luận: theo đúng gate đã định nghĩa trong `nonlinear-metric-contract-
v1.md`, 10/12 sweep hiện có sẽ KHÔNG đạt điều kiện cutover sang schema v6/
canonical official** — đây là bằng chứng cụ thể, độc lập, ủng hộ việc CHƯA
nên tiến sang Phase 3+ cho tới khi tìm ra nguyên nhân closure lệch lớn
(shaft chưa ổn định tại điểm 256, hysteresis, context unwrap gián đoạn qua
ramp — xem ALG-002/ALG-005 — hay khác biệt jig).

## 7. Có thể đồng bộ hai jig bằng một scalar offset không?

**Không — chứng minh toán học + bằng chứng số liệu.**

Với `values=[-3.0,-2.0,-0.5,1.0,2.5]` và hằng số dịch `c=7.25`:
```text
P2P(e)   = max(e) - min(e)     = 2.5 - (-3.0) = 5.5000
P2P(e-c) = max(e-c) - min(e-c) = (2.5-7.25) - (-3.0-7.25) = -4.75 - (-10.25) = 5.5000
```
(xác nhận bằng `tools/analyze_motor_logs.py --self-test`, case "P2P
shift-invariance": PASS, `P2P(e)=5.5000`, `P2P(e-c)=5.5000`).

**Tổng quát**: với mọi hằng số `c`, `max(e-c)-min(e-c) = (max(e)-c)-(min(e)-c)
= max(e)-min(e)`. Một scalar offset **chỉ dịch DC (mean)**, không đổi
`max-min`. Áp dụng vào dữ liệu thật: `System_INL`/`RawP2P` giữa JIG1 và
JIG3 khác nhau 14.8-27.3% — **không thể sửa bằng một offset cộng thêm**,
vì theo đúng chứng minh trên, P2P bất biến với mọi phép dịch DC. Tương tự:
- **Biên độ harmonic** (`a`, `b` trong `compute_harmonic`) được tính từ
  `centered = error - mean` — một offset hằng số bị trừ đi NGAY TRONG công
  thức trước khi chiếu lên `cos`/`sin`, nên hoàn toàn không ảnh hưởng `a`,
  `b`, biên độ hay pha.
- **Closure** (`error_deg` tại điểm 256) sẽ dịch đúng bằng `c`, nhưng nếu
  closure của hai jig khác nhau vì lý do KHÁC offset DC (ví dụ hysteresis
  khác nhau theo hướng quay), một `c` cố định không thể sửa đồng thời cả
  DC lẫn closure trừ khi hai đại lượng này tình cờ cùng một giá trị dịch —
  không có gì đảm bảo điều đó, và số liệu mục 6 cho thấy closure của các
  jig không tỷ lệ đơn giản với `mean_dc` của chúng.
- **Tracking waveform** (dạng sóng lỗi theo góc) hoàn toàn không đổi dạng
  khi trừ một hằng số — chỉ dịch lên/xuống, không sửa được hình dạng khác
  biệt giữa hai jig.

**Trả lời trực tiếp mục 8, câu 7**: **Không** — một scalar offset chỉ có
thể đồng bộ `MeanDC`, không thể đồng bộ `RMS_AC`, `P2P`/`System_INL`, biên
độ/pha harmonic, hay `Closure` giữa hai jig.

## Việc cần làm tiếp

Còn 4 file bắt buộc: `measurement_error_budget.md`,
`canonical_measurement_design.md`, `verification_test_plan.md`,
`executive_summary.md`. Tiếp tục theo đúng thứ tự đã thống nhất.
