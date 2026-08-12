# Lộ trình đạt 70% / 80% / 90% — production readiness NL jig

Ngày: 2026-08-11, rebase 2026-08-12. Dựa trên khung chấm điểm 6 hạng mục/100 điểm đã thống nhất cùng ngày
(baseline 67/100).
Mỗi mốc dưới đây liệt kê chính xác việc gì cần xong ở từng hạng mục để đạt tổng điểm mục tiêu — không
phải ước lượng mơ hồ, mà gắn với deliverable cụ thể đã biết trong dự án.

> **REBASE 2026-08-12 — đọc trước khi dùng doc này**: `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md`
> + `AGENTS.md` (RULE 0) đã khóa lại mục tiêu chính thức của dự án là **Open-loop NL**
> (`GREMSY_COMPAT_OPEN_LOOP_NL_V1`). Toàn bộ V5.1-V5.9 (sweep-point creep/recovery/terminal
> correction) đã bị reclassify thành `POSITION_RESPONSE_DIAGNOSTIC_V5X` — **không phải điều kiện
> của Open-loop NL official**, dù vẫn là readiness thật cho khả năng điều khiển motor/jig. Điểm
> mục 3 (Điều khiển) bên dưới VẪN giữ nguyên vì phản ánh đúng readiness đã đạt (motion/response
> control), nhưng KHÔNG được coi là đã đóng góp cho open-loop NL official — mục đó cần một track
> riêng (S0-S6 trong handoff) chưa bắt đầu. Mọi việc "làm sạch JIG7"/Gage R&R/JIG1-JIG4 dùng dữ
> liệu creep-corrected (V5.x) chỉ đo được **response repeatability**, không phải **NL
> repeatability** — nếu dùng để promote schema v6/spec limit chính thức thì phải làm lại trên dữ
> liệu từ profile `GREMSY_COMPAT_OPEN_LOOP_NL_V1` sau khi S1-S3 xong.

## Baseline hiện tại (67/100)

| # | Hạng mục | Điểm/Max | Ghi chú |
|---|---|---:|---|
| 1 | MA600 config, transport, acquisition integrity | 14/15 | rất chín, còn 1 điểm treo (xem mốc 90%) |
| 2 | Thu 360 điểm, canonical shadow, công thức, tool | 18/20 | chín, còn schema v6 chưa chính thức |
| 3 | Điều khiển motor và settle từng điểm | 17/20* | *đánh giá thận trọng hơn: 14-15/20 (điểm 308 hóa ra phụ thuộc mount, chưa dự đoán trước được) |
| 4 | Kiểm soát mounting/sensor geometry | 7/15 | chưa có gate `MountValid` calibrate thật |
| 5 | Repeatability/remount/cross-jig/Gage R&R | 7/20 | hạng mục hổng nhất — gần như chưa làm gì chính thức |
| 6 | Schema official, production gate, release | 4/10 | vẫn `OfficialResultSource=LEGACY` |
| | **Tổng** | **67/100** | |

## Mốc 70% (+3 điểm) — việc đang làm dở, gần xong

| Hạng mục | Từ → Đến | Việc cụ thể |
|---|---:|---|
| 3. Điều khiển | 17→18 | **Response-control readiness đạt** — DONE 2026-08-12: 5 mount, 3 product (P08×2, P09×1, P03×2), terminal correction 49/49 thành công, guard chưa từng kích hoạt. Điểm này phản ánh khả năng jig ĐƯA rotor tới target, không phải open-loop NL — sau rebase 08-12, "17→18" không còn tự động đóng góp vào readiness Open-loop NL official (mục 6). Finding riêng: điểm 108/147/187/348 trên P03 bị BASE-classifier bỏ qua terminal + crossing lặp lại 3/6 official cycle — vẫn ghi làm V6.0 evidence. |
| 4. Mounting | 7→8 | Dựng **bản nháp gate `MountValid`** (heuristic, chỉ cần chạy được, chưa cần calibrate đầy đủ) trên 3 combo đã sạch (P03/P08/P09 × JIG8). Lưu ý: fingerprint (H2/RobustP2P) dùng để pilot gate này được đo trên sweep có creep bật — vẫn dùng được cho mounting/geometry vì đó là tính chất cơ khí, không phải open-loop NL, nhưng cần re-đo trên profile open-loop trước khi khóa ngưỡng chính thức. |
| 6. Schema | 4→5 | Viết **draft schema v6** — đã đổi hướng: mô tả field canonical cho `GREMSY_COMPAT_OPEN_LOOP_NL_V1` (xem `nonlinear-log-schema-v6.md`, đã lock `MeasurementProfile`/`FeedbackActuationEnabled` 08-12), không phải chỉ "thay LEGACY" chung chung. |

**Điều kiện đạt 70%**: response-control pilot xong (2026-08-12) — vẫn tính điểm mục 3, nhưng KHÔNG
còn là "gần xong 70%" cho open-loop NL vì đó là mục tiêu khác track. Còn 2 việc tài liệu/nháp nhỏ
(`MountValid` draft, schema v6 draft) trước khi đóng mốc 70% chính thức. Đóng gói V5.9b (production
candidate) hiện KHÔNG được khuyến nghị nữa dưới cách đóng gói cũ — xem cảnh báo eligibility-leak ở
`open-loop-nl-direction-correction-handoff-2026-08-12.md` mục 18.2, phải sửa trước khi build.

## Mốc 80% (+13 điểm từ baseline, +10 từ mốc 70%)

| Hạng mục | Từ → Đến | Việc cụ thể |
|---|---:|---|
| 3. Điều khiển | 18→20 | **Đã đổi track sau rebase 08-12.** Không còn "V5.9 xác nhận đủ" — mục 3 giờ đo bằng việc S0-S3 (handoff mục 11) xây xong một đường đo `GREMSY_COMPAT_OPEN_LOOP_NL_V1` thật, compile-verify profile isolation, và pilot A/B/A trên hardware xác nhận số ra hợp lý so với build creep-off hiện có. C1-C2 (`stm32f405-dual-mode-implementation-plan.md`) vẫn là nhánh kiến trúc riêng cho V6.0 thật (closed-loop 1kHz) — không phải điều kiện của mục này. |
| 4. Mounting | 8→12 | Calibrate `MountValid` **thật** trên ≥3 product × ≥2 jig (không chỉ JIG8) — cần JIG7 đạt độ sạch tương đương trước (phụ thuộc mục 3, nhưng nay là "sạch theo response-diagnostic", không tự động là "sạch theo open-loop"). Ngưỡng theo từng product/jig riêng (không dùng 1 ngưỡng H2 chung — đã quyết định 09/8). |
| 5. Repeatability | 8→14 | **(a)** Gage R&R quy mô nhỏ đầu tiên: 3 remount × 2 product × 2 jig, có phân tích thống kê chính thức (không chỉ so 2 số) — **phải chạy trên dữ liệu `GREMSY_COMPAT_OPEN_LOOP_NL_V1`** sau S3, không phải trên log creep-enabled hiện có, nếu muốn kết quả tính vào readiness open-loop NL. **(b)** Đóng vòng lặp gốc của dự án: so sánh **JIG1 vs JIG4** trên dữ liệu đã sạch VÀ open-loop — đây là việc quan trọng nhất trong mốc này. |
| 6. Schema | 5→6 | Promote canonical thành **official Schema v6** cho ít nhất 1 tổ hợp đã validate đầy đủ trên profile open-loop (P08 hoặc P09/JIG8) — thay `OfficialResultSource=LEGACY`, đúng `MeasurementProfile=GREMSY_COMPAT_OPEN_LOOP_NL_V1`, không phải bất kỳ pipeline canonical nào đang chạy song song với creep. |

**Điều kiện đạt 80%**: cần S0-S3 (open-loop profile isolation + canonical cutover) xong trước, sau đó
JIG7 sạch theo profile open-loop, rồi mới làm Gage R&R nhỏ + so sánh JIG1/JIG4 thật. Đây là mốc **tốn
nhiều thời gian đo đạc thật nhất** trong 3 mốc, và sau rebase 08-12 còn thêm một track code (S0-S3)
chưa từng tồn tại trong bản 08-11 gốc.

## Mốc 90% (+10 điểm từ mốc 80%)

| Hạng mục | Từ → Đến | Việc cụ thể |
|---|---:|---|
| 1. MA600/transport | 14→15 | Xác nhận bug capture/logger mất DATA đóng hẳn (đã sạch 6 batch liên tiếp, cần thêm vài chục batch thực tế qua nhiều ngày trước khi coi là đóng chính thức). |
| 2. Thu thập/tool | 19→20 | Không còn fallback contract 256-point/legacy nào trong pipeline chính; mọi tool (MATLAB+Python) đồng bộ 1 schema. |
| 4. Mounting | 12→14 | Mở rộng gate `MountValid` phủ **toàn bộ fleet đang test** (không chỉ 3-4 product mẫu), kể cả các biến thể lắp lệch trục (P09-class) có xử lý riêng đã biết. |
| 5. Repeatability | 14→18 | Gage R&R **đầy đủ**: nhiều ngày, nhiều lần remount hơn, phủ tất cả cặp jig đang dùng production (không chỉ JIG1/JIG4) — đúng chuẩn thống kê Gage R&R công nghiệp, không phải mẫu nhỏ chẩn đoán. |
| 6. Schema/release | 6→9 | Khóa ngưỡng pass/fail sản phẩm thật (spec limit NL + `MountValid`) đã validate chéo với vài đơn vị biết trước là lỗi/tốt (như P02/P09 đã có); quy trình release có version, không lẫn giữa build thử nghiệm và build production. |

**Điều kiện đạt 90%**: cần thời gian dài nhất — chủ yếu là khối lượng ĐO ĐẠC thật (nhiều ngày, nhiều
remount, nhiều product), không phải thêm code. Đây là ranh giới giữa "hệ thống hoạt động đúng" và "hệ
thống đã qualify theo chuẩn công nghiệp".

## Vì sao không có mốc 100%

Đã nêu rõ trong đánh giá gốc: đo NL tuyệt đối theo góc cơ khí thật không thể đạt 100% chỉ bằng firmware
vì thiếu encoder tham chiếu độc lập (measurement đang tự so với chính nó — `WHOLE_SYSTEM_COMMAND_TRACKING`,
không phải so với 1 chuẩn ngoài). 90% là trần thực tế cho kiến trúc hiện tại; vượt qua đó cần thêm phần
cứng (encoder tham chiếu độc lập), không phải thêm firmware/quy trình.

## Phụ thuộc giữa các mốc (không làm tắt được, đã rebase 08-12)

```
S0 (contract lock, PARTIAL) ──► S1 (profile isolation) ──► S2 (canonical cutover, sửa ALG-001/004)
                                                                    │
                                                                    ▼
                                                    S3 (đường đo GREMSY_COMPAT_OPEN_LOOP_NL_V1 thật)
                                                                    │
                                                                    ▼
                                          S4 (verify phần mềm) ──► S5 (pilot A/B/A hardware)
                                                                    │
                                                                    ▼
JIG7 đủ sạch (theo profile open-loop, KHÔNG dùng lại kết quả response-diagnostic V5.x)
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    ▼                                            ▼
     Gage R&R + JIG1/JIG4 (mục 5, mốc 80%)          MountValid calibrate thật (mục 4, mốc 80%)

Mốc 80% (schema v6 cho 1 combo, đúng profile open-loop) ──► Mốc 90% (spec limit khóa cho toàn fleet)
```

Track response-control (V5.1-V5.9, đã DONE cho mục 3 điểm 17→18) chạy **song song, không nằm trên
đường găng** của open-loop NL nữa — nó vẫn có giá trị (điều khiển motor tốt hơn, chẩn đoán friction/
breakaway), nhưng không thể dùng làm input cho Gage R&R/JIG1-JIG4/schema-v6-official ở mốc 80-90%.
Đường găng thật bây giờ là S0→S3 (chưa bắt đầu code, chỉ mới khóa contract), không phải "V5.9 pass".
