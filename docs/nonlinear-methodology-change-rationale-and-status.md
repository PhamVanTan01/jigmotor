# Vì sao phải đổi cách tính "nonlinear", cách xác định giá trị đúng, và tình hình hiện tại

> Status note — 2026-07-14: the phase-status table in this historical review is
> superseded by `ma600-canonical-pipeline-improvement-plan.md` and
> `phase3b0-closure-measurement-review.md`. Phase 3A is implemented, but
> endpoint equivalence/closure is now the blocking gate before any 10-run
> repeatability qualification.

Báo cáo này tổng hợp lại ba câu hỏi: (1) vì sao cách tính "nonlinear angle"
hiện tại (schema v5, legacy) không đủ để tin cậy tuyệt đối, (2) giá trị
nonlinear "đúng" nên được xác định như thế nào theo hợp đồng
`CANONICAL_Q16_V1`, và (3) tình hình triển khai thật tính đến thời điểm
này — dựa trên các tài liệu đã có sẵn trong `docs/` (`ma600-canonical-
pipeline-improvement-plan.md`, `nonlinear-log-schema-v6.md`, `nonlinear-
metric-contract-v1.md`, `phase2a-canonical-sampler.md`, `phase2b-shadow-
checklist.md`, `architecture-migration-baseline.md`, `hardware-validation-
checklist.md`) và việc đọc trực tiếp code hiện hành, không suy đoán.

## 1. Vì sao phải thay đổi cách tính nonlinear hiện tại (legacy, schema v5)

### 1.1 — Có bằng chứng thật: một run tracking-lost từng bị báo "Motor OK"

`architecture-migration-baseline.md` ghi lại một fixture hồi quy âm tính
`p03-jig2.txt`, chạy trên **firmware cũ hơn** (trước khi thêm gross
tracking-integrity guard):

| Metric | Giá trị đo được |
| --- | ---: |
| Tracking RMS error | 102.06° |
| Tracking max abs error | 179.53° |
| Nonlinear angle báo ra | 317.03° |
| Trạng thái được ghi | `MeasurementValid=1`, in `Motor OK` |

Đây là một run **mất tracking hoàn toàn** (motor/encoder lệch nhau hàng
trăm độ — rõ ràng là lỗi cơ khí/điện, không phải nonlinearity) nhưng vẫn
được đánh giá là hợp lệ và báo "OK" — vì phiên bản đó chưa có bất kỳ điều
kiện nào kiểm tra "vị trí đo có thực sự bám theo lệnh không", chỉ tính toán
mù trên dữ liệu có sẵn. Đây là lý do trực tiếp khiến `NL_TRACKING_RMS_VALID_
DEG=15°`/`NL_TRACKING_MAX_VALID_DEG=30°` được thêm vào (schema v5) làm rào
chắn tối thiểu — nhưng đây vẫn chỉ là "chặn lỗi thô", không phải một định
nghĩa chặt về tính hợp lệ của từng điểm đo.

### 1.2 — Lỗi kiến trúc lấy mẫu: một điểm dữ liệu đến từ hai lần đọc khác thời điểm

Đã xác nhận trực tiếp trong `CaptureSweep()` (schema v5/legacy, xem phân
tích ở báo cáo trước): giá trị dùng để tính `ErrorDeg` (`encAngle`, trung
bình 64 mẫu) và giá trị ghi vào cột `AngleRaw` của dòng `DATA`
(`rawAtPoint`, một lần đọc riêng, sau đó) không phải cùng một lần đo. Đối
chiếu với log thật, RMS sai khác giữa hai nguồn này là 0.015–0.023°, tối đa
tới ~0.052° — nhỏ hơn nhiều so với sai khác jig-to-jig (mục 3), nhưng vẫn
là một lỗ hổng thật khiến `AngleRaw` và `ErrorDeg` của cùng một dòng log
không tái tạo lại được chính xác từ nhau.

### 1.3 — Settle chỉ kiểm tra "đã dừng", chưa kiểm tra "dừng đúng vị trí"

`WaitForPointSettle()` (schema v5) chỉ kiểm tra độ ổn định (delta giữa các
lần đọc liên tiếp nhỏ), **không kiểm tra shaft có dừng đúng gần vị trí lệnh
hay không**. Một shaft dừng ổn định nhưng ở SAI vị trí (ví dụ trượt bước,
kẹt tạm thời rồi đứng yên ở một chỗ khác) vẫn được coi là "settled". Hợp
đồng `CANONICAL_Q16_V1`/schema v6 gọi đúng trường hợp này là
`SETTLED_WRONG_POSITION` và bắt buộc phải có **cả hai** điều kiện
(`SettleStabilityValid` VÀ `SettleTargetProximityValid`) mới được coi là
hợp lệ — điều kiện thứ hai này **chưa tồn tại trong code hiện tại**, thuộc
Phase 3 (xem mục 3, "Chưa bắt đầu").

### 1.4 — Nhầm lẫn giữa "nonlinear của cả hệ thống" và "INL của riêng sensor"

Số liệu hiện tại đo `Commanded − Measured` của **cả hệ thống** (motor +
nam châm + mounting + jig + MA600A), không phải INL riêng của cảm biến
theo định nghĩa datasheet (đo với reference độc lập). Nếu không được đặt
tên/field rõ ràng (điều schema v6 chuẩn hóa bằng
`MeasurementPolicy=WHOLE_SYSTEM_REPORT_ONLY_V1`,
`ReferenceDefinition=POINT0_CANONICAL_MEAN`, `MeanDCComparableToLegacy=0`),
rất dễ có người đọc log và so sánh nhầm con số này với ngưỡng `<0.6°` của
datasheet — vốn chỉ áp dụng cho sensor đo với reference độc lập, không áp
dụng cho phép đo "cả hệ thống" này.

## 2. Cách xác định giá trị nonlinear "đúng" — hợp đồng `CANONICAL_Q16_V1`

Đã được khóa cứng trong `docs/nonlinear-metric-contract-v1.md`, tóm tắt lại
những điểm cốt lõi trả lời "giá trị đúng phải tính thế nào":

- **Một nguồn duy nhất cho mỗi điểm**: `pointMeanRawQ16` — trung bình Q16
  (int64, làm tròn "nearest, half away from zero") của đúng 64 mẫu đã
  accepted, snapshot anchor ngay sau khi settle thành công. Không còn tách
  riêng "giá trị tính error" và "giá trị ghi log" như mục 1.2.
- **Điểm 0 là reference chính xác bằng 0**: `pointMeanRawQ16[0]` là mốc; theo
  định nghĩa `Error_0 = 0` tuyệt đối, không phải "gần 0" sau khi quy đổi ra
  độ.
- **Chiều dấu**: `errorRawQ16[i] = (pointMeanRawQ16[i] − pointMeanRawQ16[0]) −
  targetRelativeRawQ16[i]`, tức **Measured − Target** (ngược dấu với công
  thức legacy `Target − Measured`) — mọi so sánh giữa hai đường số liệu
  phải đổi dấu tương ứng, không được trừ trực tiếp.
- **Closure**: điểm 256 (đúng một vòng) phải khớp target `65536LL ×
  65536LL` (Q16 của 360°); `ClosureErrorRawQ16` là thước đo tính toàn vẹn
  phép đo — ngưỡng pilot `0.20°` là **ngưỡng kiểm tra tính toàn vẹn acquisition,
  không phải ngưỡng chất lượng sản phẩm**.
- **Hợp lệ chính thức (`OfficialMeasurementValid`) phải đúng ĐỦ các điều
  kiện**: config gate pass, acquisition đủ điểm/không vượt budget, settle
  đạt cả stability và target-proximity, tracking-integrity guard pass,
  closure pass, `ContextReacquireCount==0`, không có motor fault. Thiếu một
  điều kiện là invalid — không được tính trung bình/độ lệch mà không kiểm
  tra đủ các cờ này.
- **Sweep invalid không được xuất field mang tên chính thức** (`RMS_AC`,
  `Motor_System_INL_Deg`, `Nonlinear N Angle`, `Motor OK`...) — chỉ được
  xuất dưới tiền tố `Diagnostic_` để không ai nhầm số liệu chẩn đoán với
  kết quả chính thức.
- **Vẫn không so sánh trực tiếp với ngưỡng INL sensor-only của datasheet** —
  chính sách đo vẫn là `WHOLE_SYSTEM_REPORT_ONLY_V1`/`REPORT_ONLY`, chỉ báo
  cáo, chưa áp ngưỡng pass/fail nonlinear nào cho tới khi có nghiên cứu
  thống kê trên nhiều unit hoặc có một reference encoder độc lập thật.

## 3. Tình hình triển khai hiện tại (theo đúng tài liệu trong `docs/`, không suy đoán)

Lộ trình đầy đủ nằm trong `docs/ma600-canonical-pipeline-improvement-plan.md`,
gồm 8 phase (0-7). Trạng thái từng phase, theo đúng ghi nhận mới nhất trong
các checklist:

| Phase | Nội dung | Trạng thái |
| --- | --- | --- |
| 0 | Khóa baseline + hợp đồng `CANONICAL_Q16_V1` | **Xong** — đã khóa trong `nonlinear-metric-contract-v1.md` |
| 1 | Checked I/O + Policy-A config gate | **Xong cho JIG1/JIG3** (profile audit khớp, `POLICY_A_LOCKED_V1`) — JIG3 vừa thêm, còn thiếu smoke record khóa cho JIG2 nếu JIG2 còn dùng production |
| 2A | Canonical point sampler (phần mềm) | **Xong** — self-test C pass, boot self-test pass trên JIG1/JIG3, đã có evidence CONFIG record |
| 2B | Shadow mode (chạy song song, không chính thức) | **Phần mềm xong, phần cứng CHƯA** — theo `phase2b-shadow-checklist.md`, toàn bộ "Matrix Phase 2B tối thiểu" (12 sweep: P03/P05 × JIG1/JIG3 × 3 lần) và "Điều kiện pass"/"Đánh giá sau 12 sweep" **vẫn còn nguyên checkbox trống `[ ]`** — đây là bước đang bị chặn (blocking) hiện tại |
| 3 | Continuous sweep context, settle target-proximity, PID Δt-aware | **Chưa bắt đầu** |
| 4 | Tách capture/analyze, `OfficialMeasurementValid`/`Quality` chính thức | **Chưa bắt đầu** |
| 5 | Schema v6 chính thức + parser | **Chưa** — schema v6 hiện chỉ là *thiết kế* (`nonlinear-log-schema-v6.md` ghi rõ "must not emit SchemaVersion=6 until...") |
| 6 | Xác nhận phần cứng (Phase A an toàn/đúng đắn, Phase B pilot sampling, Phase C/D so sánh) | **Chưa** — phải sau Phase 2B/3/4/5 |
| 7 | Quyết định production + release | **Chưa** |

**Bằng chứng số liệu thật đã có** (từ `ma600-canonical-pipeline-improvement-
plan.md`, cả JIG1 và JIG2 dùng đúng cùng cấu hình sensor đã audit khớp
100% — `ZERO=0x0000, DIR=0x00, FILT=0x05, STATUS=0x00, PRT=0x00,
RMAPID=0x00`, correction table toàn 0, CRC `0x190A55AD` giống nhau tuyệt
đối):

| Jig | P03 (3 lần, độ) |
| --- | --- |
| JIG1 | 3.52 / 3.07 / 3.00 |
| JIG2 | 2.51 / 2.47 / 2.46 |

Vì cấu hình sensor giống nhau tuyệt đối giữa hai jig, khoảng lệch ~0.5-1°
này **không thể do khác biệt cấu hình** — càng khẳng định lại kết luận ở
báo cáo trước: chênh lệch jig-to-jig là vật lý thật (mounting/air-gap/độ
lệch tâm/đặc tính riêng từng chip MA600A), không phải bug phần mềm.

### Việc đang cần làm ngay tiếp theo

Theo đúng `phase2b-shadow-checklist.md`: chạy đủ ma trận tối thiểu 12 sweep
phần cứng (P03 + P05, trên JIG1 + JIG3, 3 lần mỗi ô, cùng một file HEX cho
mỗi Motor ID), xác nhận toàn bộ "Điều kiện pass cho từng sweep" (legacy vẫn
`MeasurementValid=1` không đổi hành vi, shadow đủ 64 mẫu accepted mỗi
điểm, `Error0RawQ16=0` chính xác, closure log đầy đủ dù pass hay fail), rồi
mới tổng hợp thống kê theo cặp Motor/Jig để xét có đủ điều kiện đề xuất
sang Phase 3 hay không. **Chưa được phép** coi canonical là kết quả chính
thức hay đổi sang schema v6 chỉ vì canonical cho ra số khác/nhỏ hơn legacy —
đây là nguyên tắc được nhắc lại nhiều lần trong tài liệu gốc, chỉ được
quyết định bằng dữ liệu lặp lại/độ ổn định, không bằng việc "số nào đẹp
hơn".
