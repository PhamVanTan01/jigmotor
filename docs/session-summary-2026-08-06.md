# Nhật ký công việc 2026-08-06

Theo đúng rule đã ghi trong `session-summary-2026-08-05.md`: mỗi ngày 1 file MD duy nhất, không tách theo chủ đề.

Tiếp nối trạng thái chốt cuối ngày 2026-08-05 (xem file đó, mục 8): V5.3 fine-landing tại điểm 66 **PASS 8/8** qua 2 remount (bước đột phá thật sau chuỗi thất bại v3→v5.2), nhưng precondition remount02 vẫn FAIL vì breakaway tại **điểm 26** (chưa được fine-landing). Quyết định tiếp theo đã ghi sẵn: thiết kế **V5.4 generalized targeted fine landing**, không hardcode riêng điểm 66.

## Hoạt động trong ngày

### 1. Rà soát lại nhật ký 05/8, xác nhận điểm nổi bật: V5.3 fine-landing point 66

Đọc lại toàn bộ `session-summary-2026-08-05.md`, xác nhận với người vận hành đây đúng là phát hiện đáng chú ý nhất trong ngày — sau 4 lần thử thất bại (v3 giảm công suất → giật cục tệ hơn; v5-adaptive → mất ổn định; v5.1 crossing-guard → an toàn nhưng 0% dữ liệu dùng được; v5.2 bounded-recovery → cải thiện nhưng chưa thắng breakaway lớn), v5.3 (coarse 16 raw → fine 4 raw khi `|gap|≤64 raw`, kèm jump-guard 96 raw) là bản đầu tiên đạt PASS thật trên phần cứng.

### 2. Xây tool MATLAB phân tích chuyên sâu telemetry `SWEEP_CREEP_*` (thay cho proxy đã dùng trước đây)

Trước ngày 05/8, firmware chưa log per-point nên `analysis-out/p08-jig7-v4-creep-difficulty-spatial-analysis.md` phải dùng proxy `|MOTION.PositionErrorRaw|` để suy đoán "điểm khó". Từ v5.1 trở đi, firmware đã log trực tiếp `SWEEP_CREEP_CONFIG`/`SWEEP_CREEP_POINT`/`SWEEP_CREEP_STEP` (schema đổi qua từng bản) — đủ để phân tích thẳng bằng chứng thật, không cần proxy nữa.

**Tool mới** (`analysis/matlab/nl/`):
- `parse_sweep_creep_log.m` — parser cho cả 3 loại record trên + rollup `SweepPointCreep*` trong `END`, tự điền `NaN`/`""` cho field chưa tồn tại ở bản cũ (v5.1 thiếu `PreCrossGapRaw`/`Recovery*`, v5.1-v5.2 thiếu `FineLanding*`/`StickSlipJumpDetected`) thay vì lỗi — cho phép gộp log nhiều bản firmware khác schema trong cùng 1 lần chạy.
- `analyze_sweep_creep_batch.m` — gộp nhiều file/nhãn, xếp hạng "điểm khó" theo `TroubleScore` (tỷ lệ `Result≠OK`), kèm tỷ lệ `RecoveryAttempted`/`StickSlipJump`/`FineLandingAttempted` và gap cuối theo từng điểm; đồng thời tổng hợp tỷ lệ `IntegrityValid`/số lần `TargetCrossed`/`RecoveryRecrossed`/`StickSlipJump` theo từng file/bản để so sánh độ ổn định V5.1 vs V5.2 vs V5.3.
- Test: `test_sweep_creep_analysis()` trong `analysis/matlab/tests/test_nl_stability_analysis.m` — 2 sweep giả lập kiểu V5.1 (thiếu field) và V5.3 (đủ field), xác nhận field thiếu ra `NaN` đúng thay vì lỗi, và điểm "lỗi thật" xếp hạng đầu đúng. 5/5 bộ test regression PASS.

### 3. Chạy trên toàn bộ dữ liệu V5.x thật ngày 05/8 — phát hiện mới phục vụ trực tiếp thiết kế V5.4

Gộp 8 file (`S2-P03-JIG7-remount*-test-*-v5-{1,2,3}.txt`, cả 3 bản V5.1/V5.2/V5.3): **2223 dòng point-telemetry, 220 dòng step-trace, 26 sweep**.

**Danh sách đầy đủ điểm từng `TARGET_CROSSED`/`RECOVERY_RECROSSED`** (bằng chứng breakaway trực tiếp, không suy luận):
- **Điểm 66**: 8 lần trên cả 3 bản (V5.1×4, V5.2×3, V5.3×1) — nặng nhất, đã biết.
- **Điểm 26**: xuất hiện ở cả **V5.1 (remount02) lẫn V5.3 (remount02)** — tài liệu 05/8 trước đó chỉ ghi nhận nó từ V5.2 trở đi; nay xác nhận thêm nó đã crossing từ tận V5.1, củng cố đây là điểm tái diễn thật.
- **9 điểm một-lần chưa từng được ghi nhận ở đâu trước đây**: 5, 76, 125, 175, 184, 215, 264, 284, 344 (toàn bộ quan sát ở V5.1, trước khi có cơ chế recovery) — ứng viên bổ sung cho danh sách target V5.4, mức độ nhẹ hơn 66/26 nhưng chưa thể loại trừ.

**Đối chiếu ngược danh sách "điểm khó" cũ dựa trên proxy** (`analysis-out/p08-jig7-v4-creep-difficulty-spatial-analysis.md`, 14 điểm: 0,67,106,107,173,174,175,214,254,293,294,295,324,334): point 0 không có record tương đương, còn 13 point đánh giá được. Trong đó, **2 point có trouble lặp lại mạnh** — 67 (TroubleScore=0.68) và 107 (TroubleScore=0.93); **10 point có TroubleScore chỉ 0–0.08, gap cuối 15-17 raw**; point 175 có một crossing thật nhưng chưa đủ dữ liệu để phân loại là lỗi lặp lại. Kết luận: danh sách proxy cũ có tỷ lệ dương tính giả cao, **không nên dùng trực tiếp làm input chọn điểm cho V5.4**.

**Lưu ý khi đọc `TroubleScore`**: nó gộp chung `BUDGET_EXCEEDED` (nhẹ — vẫn hội tụ gần đích, chỉ chưa dùng hết ngân sách, gap cuối thường 20-70 raw, rất phổ biến ~14 iteration/điểm) với `TARGET_CROSSED`/`RECOVERY_RECROSSED` (nặng — vọt qua đích thật). Muốn chọn điểm cho V5.4, dùng bảng crossing/recrossed ở trên, không dùng thẳng top-`TroubleScore` (danh sách đó lẫn nhiều điểm chỉ bị `BUDGET_EXCEEDED` nhẹ).

## Việc chưa hoàn thành / đề xuất cho phiên sau

1. **Đã hoàn thành:** tạo plan **V5.4 universal live-gap fine landing**; runtime selection không dùng danh sách điểm, mà áp dụng fine profile cho mọi point và latch theo live gap.
2. Dùng danh sách 66, 26 và 9 điểm một-lần làm bộ kiểm chứng hardware/telemetry; không dùng làm lookup table điều khiển. Tiếp tục theo dõi xem 9 điểm một-lần có tái diễn ngoài V5.1 hay không.
3. Verify lại H1/H2/H36 "sạch" sau khi V5.4 đóng được toàn bộ điểm crossing đã biết (việc treo từ 04/8, càng cần dữ liệu ổn định hơn nữa mới đo được).
4. Test `LiveNlPlot` (`tools/stm32_uart_flasher.py`) trên phần cứng thật — vẫn chưa làm (đã ghi từ 04/8).

### 4. Khóa plan V5.4 — universal live-gap fine landing

Đã tạo `docs/sweep-point-creep-v5-4-universal-live-gap-fine-landing-plan.md`.

Quyết định quan trọng nhất: danh sách crossing lịch sử chỉ là bộ kiểm chứng, không phải lookup table
runtime. V5.4 áp dụng cùng profile coarse 16 → fine 4 cho mọi sweep point; fine mode chỉ latch khi
`abs(live gap) <= 64 raw`. Cách này xử lý cả crossing thuộc BASE budget như point 5/264 và tránh
overfit P03/JIG7.

Plan đã khóa:

- raw budget không đổi: BASE 220, EXTENDED 320;
- iteration guard tương ứng fine step 4: BASE 56, EXTENDED 81;
- power 1.0, deadband 16, jump guard 96, recovery 64 raw/17 iteration;
- không hardcode point index, không chase sau jump, chỉ một reversal;
- B0-B/acquisition/settle/công thức NL không đổi;
- chỉ một buffer step-trace, khóa tại integrity failure đầu tiên để không tăng RAM theo 360 point;
- pilot đầu tiên P03/JIG7: 1 precondition + 3 official, sau đó mới remount/cross-product.

Trạng thái: **IMPLEMENTED / SOFTWARE VERIFIED — HARDWARE PILOT PENDING**.

Kết quả triển khai V5.4:

- firmware áp dụng profile theo live gap cho toàn bộ main-sweep point, không dùng `pointIndex` làm
  input policy;
- giữ raw budget BASE/EXTENDED 220/320, tăng iteration guard lên 56/81 cho fine step 4 raw;
- trace RAM chỉ một buffer 100 entry, tái sử dụng và khóa tại integrity failure đầu tiên;
- telemetry mới: CONFIG/POINT schema 7, STEP schema 2, END có phân lớp fine BASE/EXTENDED và
  dynamic `SweepPointCreepTracePoint`;
- 31/31 PowerShell regression pass; default, V5.3 FAST3 và V5.4 FAST3 Release đều build pass;
- stack audit: deepest static chain 7664/12288 byte, margin 4624 byte;
- artifact pilot:
  `builds/sweep-point-creep-v5-4-universal-live-gap-fine-landing-fast3-20260806/`;
- source đã restore về creep/V5.3/V5.4 default-off và batch 10 official sau packaging;
- MATLAB synthetic schema test đã cập nhật, nhưng chưa chạy runtime trong phiên này vì máy build
  không có executable MATLAB.

### 5. Hardware V5.4 và triển khai V5.4a-DIAG

Đã đánh giá hai batch P03/JIG7 V5.4 trên remount01/remount02:

- hard integrity PASS: precondition hợp lệ, 6/6 official hợp lệ, không recovery failure/recross/jump;
- point 26 và 66 đạt deadband tổng cộng 8/8 cycle mỗi điểm;
- Robust NL giữa hai remount rất ổn định: 0.5624° và 0.5671°, chênh 0.0048° (0.85%);
- full-curve remount correlation `r=0.9677`, centered RMSE 0.0322°, best shift 0°;
- nhưng promotion gate FAIL: 157 + 148 = 305 fine-landing failure trong 6 official sweep;
- 48/75 vị trí lỗi dùng chung giữa hai remount, 21 vị trí lỗi đủ 6/6 run, tập trung tại
  `Point mod 10 = 6..9`.

Kết luận V5.4 là **MIXED / EFFECTIVENESS FAIL**: đã loại crossing nguy hiểm nhưng fixed fine step 4 raw
không đủ hiệu quả ở một pha điện lặp lại. Không chạy thêm remount03 cùng firmware.

Đã tạo và implement `docs/sweep-point-creep-v5-4a-first-fine-budget-trace-plan.md`:

- thêm flag nested mặc định tắt `ENABLE_SWEEP_POINT_CREEP_V54A_FINE_FAILURE_TRACE`;
- V5.4 gốc vẫn dùng `FIRST_INTEGRITY_FAILURE_V1`;
- V5.4a dùng `FIRST_FINE_BUDGET_OR_INTEGRITY_FAILURE_V1` và khóa buffer hiện hữu tại point đầu tiên
  có `FineLandingAttempted=1 && Result=BUDGET_EXCEEDED`;
- không đổi motor command, budget, iteration guard, settle, MA600 acquisition, validity hoặc công
  thức NL;
- giữ một buffer 100 entry, không thêm UART trong motion;
- default: 32/32 PowerShell test pass và Release build pass;
- frozen V5.3 FAST3, base V5.4 FAST3 và V5.4a FAST3 đều build Release thành công;
- V5.4a FAST3: 31/31 test áp dụng pass, Release text/data/bss = 89620/96/165288 byte;
- stack chain sâu nhất giữ nguyên 7664/12288 byte, margin tĩnh 4624 byte;
- artifact sẵn sàng flash tại
  `builds/sweep-point-creep-v5-4a-first-fine-budget-trace-fast3-20260806/`;
- source đã restore về creep/V5.3/V5.4/V5.4a default-off và batch 10 official.

### 6. Kết quả V5.4a và triển khai V5.5

Đã đánh giá V5.4a trên hai remount P03/JIG7:

- remount01 có 3/3 official đầy đủ; remount02 chỉ có 2/3 official dùng được cho NL vì run cuối mất
  `DATA` index 219–294 và một phần telemetry trên đường log/capture;
- trace usable lặp lại tại point 9: bốn trace fine hoàn chỉnh dùng 60–92 raw command, tạo 20–46 raw
  tiến triển có hướng (hiệu suất 33.3–53.9%), rồi dừng ở gap -17 đến -31 raw;
- một trace point 8 dùng 224 raw coarse, latch fine nhưng chưa kịp phát lệnh fine, dừng ở -57 raw;
- không trace nào có jump/recross/recovery failure;
- kết luận cơ chế: 4-raw response có hao hụt nhưng không bằng zero; giới hạn chính là BASE 220 raw
  không phản ánh đủ command demand sau khi thấy live response.

Đã tạo và implement
`docs/sweep-point-creep-v5-5-dynamic-base-escalation-plan.md`:

- flag nested mặc định tắt `ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION`;
- BASE giữ primary budget 220 raw; chỉ point thực sự cần command vượt 220 mới được tiếp tục tới hard
  cap 320 raw đã validate cho EXTENDED;
- không dùng point index/angle/motor whitelist; point thành công trước 220 không thay đổi motion;
- giữ coarse/fine 16→4, fine entry 64, deadband 16, power 1.0, jump guard 96 và recovery 64/17;
- protocol mới `ADAPTIVE_BASE_TO_EXTENDED_ESCALATION_UNIVERSAL_FINE_LANDING_V2`;
- CONFIG/POINT schema 8 và END rollup ghi attempted/succeeded/failed escalation + extra raw;
- trace buffer cũ khóa tại hard-cap budget failure hoặc integrity failure đầu tiên;
- parser/analyzer MATLAB đọc V5.1–V5.5 và tổng hợp success rate của BASE escalation;
- 32/32 PowerShell regression áp dụng cho FAST3 pass; test 10-official mặc định được skip đúng chủ ý;
- default-off và feature FAST3 Release đều build pass;
- feature image text/data/bss = 90292/96/165312 byte;
- stack chain sâu nhất vẫn 7664/12288 byte, static margin 4624 byte;
- artifact sẵn sàng tại
  `builds/sweep-point-creep-v5-5-dynamic-base-escalation-fast3-20260806/`;
- source đã restore về V5.x default-off và batch 10 official sau packaging.

### 7. V5.5 — pilot phần cứng đầu tiên, kết quả NL tốt nhất từ trước tới nay nhưng chưa đạt mechanism gate

**Test thực tế đầu tiên** (`captured-logs/S2-P03-JIG7-remount02-test-1-v5-5.txt`, BuildID
`Aug 6 2026 13:40:02`, khớp đúng build ở mục 6):

- **Hard gate: ĐẠT toàn bộ** — OfficialValid=3/3, `IntegrityValid=1` cả 4 chu kỳ, `RecoveryFailed=0`,
  `RecoveryRecrossed=0`, `StickSlipJump=0` toàn batch (3 lần target-crossed xảy ra nhưng cả 3 đều được
  recovery bắt và sửa thành công), stack high-water 1024 word (>768 yêu cầu).
- **Kết quả NL — tốt nhất từ trước tới nay**: RobustP2P mean=**0.4748°**, cv=**2.83%** (dưới ngưỡng gate
  ≤5.7%), A36 mean=0.1099° cv=1.46%. Giảm gần một nửa so với v4 (0.93°) mà vẫn ổn định hơn nhiều so
  với mọi bản v5/v5.1 trước đó.
- **Mechanism gate: CHƯA đạt ngưỡng đề ra trong kế hoạch** (dù kết quả NL tổng thể tốt):
  - `BaseBudgetExceeded` (=`BaseEscalationFailed`, đã xác nhận trùng số) trung bình 3 run official =
    13, so với baseline V5.4a (55-63/run) → giảm **~78%**, hụt nhẹ so với mục tiêu **≥80%**.
  - Tỷ lệ escalation BASE thành công: 51/63=81.0%, 49/65=75.4%, 51/62=82.3% → **75-82%**, dưới mục
    tiêu **≥90%**.
  - Điểm 8 tiếp tục xuất hiện là `TracePoint` (lần hard-cap-fail đầu tiên được ghi vết) ở 3/4 sweep —
    khớp đúng bằng chứng V5.4a đã ghi nhận trước đó (điểm 8: tiêu hết 224 raw coarse, 0 lệnh fine,
    dừng ở gap -57 raw).
- Theo đúng bảng quyết định trong kế hoạch (mục 9): kết quả này khớp nhánh **"BASE vẫn chạm trần 320
  với phản hồi 4-raw thấp → thiết kế V5.6 response-aware 16→8→4 landing"**, chưa phải nhánh "escalation
  thành công → promote sang remount thứ 2" (vì tỷ lệ thành công escalation chưa đạt 90%).

**Chưa làm**: chưa so sánh correlation/RMSE toàn đường cong 360 điểm với V5.4a baseline, chưa có số
liệu thời gian/motor-active-duration để kiểm tra gate "+15%", chưa xác nhận qua remount thứ 2.

### 8. V5.5 trên P02 — "product bị cho là lỗi" — hồ sơ mất ổn định KHÁC hẳn P03

Test cùng build v5.5 (`captured-logs/S2-P02-JIG7-remount02-test-2-v5-5.txt`, BuildID `Aug 6 2026
13:40:02`, cùng JIG7) trên motor P02, được người vận hành mô tả là "bị cho là bị lỗi". Đây là log P02
đầu tiên trong dự án — không có dữ liệu firmware cũ hơn để đối chiếu trước/sau trên chính con này.

- **NL cao và kém ổn định hơn P03 nhiều**: RobustP2P mean=0.8119°, cv=**17.95%** (P03 cùng build:
  0.4748°, cv 2.83%); A36 mean=0.0982° cv=5.92%.
- **Nhưng hồ sơ telemetry cơ chế lại TỐT hơn P03, không giống kiểu lỗi đã gặp cả ngày**:
  - `TargetCrossed=0` và `StickSlipJump=0` ở cả 4/4 sweep — **không có breakaway nào**, khác hẳn P03
    (0,1,1,2 lần/sweep).
  - Tỷ lệ escalation BASE thành công: 19/20, 25/25, 23/23, 26/27 = **95-100%** — vượt xa mục tiêu ≥90%
    (P03 cùng build chỉ 75-82%).
  - Nhưng số điểm rơi vào lớp EXTENDED (khe hở ban đầu >200 raw) cao gấp ~3 lần P03: 93-116 điểm/sweep
    so với 36-43 của P03 (~26-32% tổng số điểm so với ~10%) — motor này cần bù nhiều và rộng hơn hẳn.
- **Diễn giải**: mẫu mất ổn định của P02 không khớp cơ chế "breakaway/crossing" đã săn lùng suốt từ
  v5-adaptive đến v5.5 (ở đây bằng 0) — giống với **đặc tính vật lý thật của chính con motor này** hơn
  (khe hở under-travel lớn và trải rộng khắp đường quét, kèm dao động NL thật giữa các run) — phù hợp
  với mô tả "bị cho là lỗi" của người vận hành, không phải dấu hiệu firmware v5.5 hoạt động sai.
- **Giới hạn**: mới 1 remount, chưa có dữ liệu P02 dưới firmware cũ hơn (v4 trở về trước) để xác nhận
  đây là đặc tính có từ trước hay mới phát sinh; cần thêm ít nhất 1 remount nữa hoặc 1 lần đo bằng v4
  trên chính con P02 này để tách bạch rõ "lỗi motor thật" khỏi "firmware chưa xử lý hết trường hợp".

### 9. V5.5 trên JIG8 — cross-board, kết quả TỐT NHẤT dự án tính đến nay

Cùng build v5.5 (`captured-logs/S2-P03-JIG8-remount02-test-1-v5-5.txt`, BuildID `Aug 6 2026
13:40:02`), cùng motor P03 nhưng chuyển sang board **JIG8** (MCU_UID khớp đúng đăng ký JIG8 04/8,
`JigKnown=1`).

- **NL — tốt nhất từ trước tới nay trong toàn dự án**: RobustP2P mean=**0.2212°**, cv=**1.16%**; A36
  mean=0.0942° cv=1.14%. Thấp hơn khoảng **một nửa** so với chính P03 trên JIG7 cùng build (0.4748°,
  cv 2.83%).
- **Mechanism cũng tốt hơn JIG7 rõ rệt**: `ExtendedOk` 65/66, 64/64, 63/63 (98.5-100%, gần như hoàn
  hảo); crossing chỉ 2 lần/12 sweep (1 ở run 3), cả 2 đều recovery thành công
  (`RecoveryFailed=0`, `RecoveryRecrossed=0`); `StickSlipJump=0` toàn batch. Số điểm cần escalation ít
  hơn nhiều: chỉ 28-30 điểm/sweep cần vượt 220 raw (so với 62-65 của P03/JIG7) — bản thân khe hở cần
  bù trên tổ hợp JIG8 này nhỏ và hẹp hơn nhiều.
  - Tỷ lệ escalation BASE thành công gộp 3 run official: 79/89 = 88.8% — vẫn dưới mục tiêu 90% (dù
    gần đạt hơn nhiều so với 75-82% của JIG7).
- **Ý nghĩa**: đây là bằng chứng đầu tiên V5.5 tổng quát tốt (thậm chí tốt HƠN) khi đổi board — khớp
  với phát hiện "new board effect" từ 04/8 (JIG6/7/8 từng cho biên độ NL thấp hơn tham chiếu JIG4 trên
  cùng 1 cụm gá/sensor) — không phải dấu hiệu firmware chỉ ăn may trên combo P03/JIG7 cụ thể.
- **Giới hạn**: mới 1 remount trên JIG8; escalation-success vẫn chưa chạm 90% ở bất kỳ combo nào đo
  được hôm nay (P03/JIG7: 75-82%, P03/JIG8: 88.8%, riêng P02/JIG7: 95-100% nhưng motor này gần như
  không có điểm crossing/breakaway nên không cùng bối cảnh so sánh).

### 10. P09/JIG8 — NL sweep sạch nhất dự án, nhưng lỗi thật ở khâu hiệu chỉnh offset MA600 (khác tool)

**NL sweep (`captured-logs/S2-P09-JIG8-remount01-test-1-v5-5.txt`, cùng build v5.5)**: kết quả sạch
nhất từ đầu dự án — RobustP2P mean=**0.2189°**, cv=**0.17%**; A36 mean=0.0963° cv=0.75%. Mechanism
telemetry hoàn hảo tuyệt đối cả 4 sweep: `BaseEscalationSucceeded`/`Attempted` = 100% mỗi sweep,
`ExtendedOk`/`ExtendedPoints` = 100% mỗi sweep, `FineLandingFailed=0`, `BudgetExceeded=0`,
`TargetCrossed=0`, `StickSlipJump=0`, `RecoveryAttempted=0` (chưa từng cần recovery). Người vận hành
xác nhận con này cũng từng PASS đo NL theo code jig cũ (Gremsy).

**Nhưng đây là "motor khi tìm điểm để làm offset cho MA600 32 thanh ghi thì bị lỗi"** — quy trình này
**không phải** `jigmotor-nl2`/jig NL đo trong bảng trên, mà là 1 tool/firmware hoàn toàn khác: console
"Upgrade" của chính firmware gimbal Gremsy (QA/QC firmware, `FIRMWARE QA/QC FOR TESTTING LYNX PAYLOAD
V2.3`), module `ENCODER_MA600`, tính bảng hiệu chỉnh 32 điểm (CORR0-31) cho trục TILT. Đã tìm trong
`datacty/` (code Gremsy cũ có sẵn local) nhưng không thấy đoạn thuật toán này — thuộc firmware gimbal
thật, khác repo, không đối chiếu được source.

**Người vận hành cung cấp thêm 1 log PASS tham chiếu** (cùng tool, trục PAN, lặp lại 35 chu kỳ liên
tục) để đối chiếu. Kết luận rút ra:

1. **Thẻ `[ERROR]` trên các dòng "...done!" (`correct table was already written!`, `stored in NVM!`,
   `Open done!`) là red herring** — xuất hiện y hệt trên cả log PASS lẫn log P09, chỉ là quy ước
   log-level của tool cho các mốc offset-table, không phải tín hiệu lỗi thật.
2. **Nhưng có tín hiệu lỗi thật, đo được bằng số liệu — không dựa vào màu log**:

   | | PASS tham chiếu (PAN, 35 lần lặp) | P09 (TILT) |
   |---|---:|---:|
   | MAE of BCT164 | 0.3 (không đổi) | **0.7** |
   | Delta ideal/raw — Mean | 1.3–1.9° | 2.5–5.2° |
   | Delta ideal/raw — Max | 4.1–5.5° | 9.9–16.8° |
   | Vào nhánh spike/retry (`index=X,delta=...`, dump `nvm[]`) | không bao giờ (0/35 lần) | **có**, "spike points in table = 2" |

3. **Vùng bất thường cụ thể, lặp lại ở cả 2 lần chạy TILT**: `nvm[21]=nvm[22]=nvm[23]=-11.2` — 3 giá
   trị hiệu chỉnh thô liên tiếp giống hệt nhau (bất thường, giống kẹp giới hạn hơn tín hiệu thật); thuật
   toán tự flag `index=22, max_err=9.9,pos=483.0,ideal_ang=251.3`; dư sai số sau 16 lần dò lại
   (`retry:16`) tại điểm đó vẫn còn **-4.9°** — lớn nhất bảng, không hội tụ được.
4. **Lưu ý phương pháp quan trọng**: đã thử đối chiếu `ideal_ang=251.3°` của tool này với `Point=251`
   trong sweep NL của jig trên cùng con P09 — nhưng đây là **2 hệ quy chiếu góc khác nhau hoàn toàn**
   (tool Gremsy dùng thang raw nhỏ ~0-720, jig dùng raw MA600 16-bit ~65536, gốc 0° khác nhau) nên
   trùng số "251" chỉ là trùng hợp ngẫu nhiên — **không kết luận đây là cùng 1 vị trí vật lý**.

**Kết luận**: P09 có lỗi thật, đo được bằng số liệu, ở khâu hiệu chỉnh offset MA600 (MAE gấp ~2.3 lần,
Delta max gấp 2-3 lần tham chiếu PASS, và là log duy nhất kích hoạt + không giải quyết được nhánh
sửa-điểm-bất-thường) — **độc lập, không mâu thuẫn** với kết quả NL sweep rất sạch trên jig, vì 2 phép
đo nhắm vào 2 đặc tính khác nhau (NL sweep: độ lặp lại/tracking tổng thể cả hệ qua creep-correction;
hiệu chỉnh offset: đặc tính nội tại của cảm biến/từ trường tại từng điểm rời rạc, không qua correction).
Đây là bằng chứng dự án đầu tiên cho thấy 1 motor có thể "sạch" ở phép đo NL sweep nhưng vẫn lộ khuyết
điểm thật ở 1 phép đo khác nhạy hơn với đặc tính cục bộ.

**Giới hạn**: log PASS tham chiếu là trục PAN, không phải TILT (không có log TILT PASS để so sánh cùng
trục); chưa có source code của thuật toán hiệu chỉnh offset để xác nhận ngưỡng pass/fail chính thức của
tool (MAE/Delta bao nhiêu thì coi là fail); chưa xác định được vị trí vật lý thật (raw pos ~455-498 của
tool Gremsy) tương ứng góc nào trên hệ quy chiếu của jig.

**Nguyên nhân gốc đã xác nhận (người vận hành, 06/8)**: cụm board này **cố ý** đặt sensor MA600 lệch
1 bên item 8 thay vì vuông góc/đồng trục như cấu hình chuẩn — **để tiết kiệm không gian**, không phải
lỗi lắp ráp. Đây là biến thể thiết kế hợp lệ.

**Kết luận cuối**: P09 **không phải motor lỗi** — sensor lệch trục tạo từ trường có gradient dốc/méo
cục bộ hơn cấu hình chuẩn, phá vỡ đúng giả định "sai số biến thiên mượt" mà bảng nội suy 32-điểm của
MA600 cần để hội tụ, trong khi NL sweep của jig (bám target qua creep-correction, không giả định trước
dạng sóng) không bị ảnh hưởng — khớp hoàn toàn với việc jig cho kết quả sạch nhất dự án còn khâu hiệu
chỉnh offset lại lỗi trên cùng con này. Đây là vấn đề **tool/thuật toán hiệu chỉnh chưa hỗ trợ đúng
biến thể mounting lệch trục**, không phải khuyết tật phần cứng của P09. Đã lưu vào memory dài hạn
(`project_offaxis_ma600_mount_variant`) để nhận diện nhanh nếu gặp lại pattern "jig NL sạch nhưng
hiệu chỉnh offset MA600 lỗi" ở các board cùng biến thể lắp lệch trục.

### 11. P08/JIG8 (v5.5) — JIG8 tiếp tục cho kết quả sạch, và bằng chứng "điểm hard-cap-fail đặc thù
theo tổ hợp" phục vụ review plan V5.6

**Test** (`captured-logs/S2-P08-JIG8-remount01-test-1-v5-5.txt`, cùng build v5.5, BuildID
`Aug 6 2026 13:40:02`, MCU_UID khớp JIG8). Không có file `.analysis.*` tự động đi kèm — tính tay
RobustP2P từ `DATA` (top5−bottom5) cho 3 sweep official:

- RobustP2P: 0.2263°, 0.2250°, 0.2313° → mean=**0.2275°**, cv≈**1.47%**; A36 (từ `RESULT`): 0.0980,
  0.0962, 0.0992 → khá ổn định. **Đây là motor thứ 3 (sau P03, P09) cho kết quả rất sạch trên JIG8**,
  cùng thang độ lớn NL thấp (~0.22-0.23°) như 2 con kia — củng cố thêm "new board effect"/JIG8 tốt
  hơn JIG7 đã ghi nhận từ 04/8 và trong ngày hôm nay.
- Mechanism: BASE escalation **100%** cả 4 sweep (39/39, 34/34, 35/35, 31/31); Extended 96-98%;
  `TargetCrossed=0`, `StickSlipJump=0`, `RecoveryAttempted=0` toàn batch — sạch tương đương P09/JIG8.

**Bảng tổng hợp điểm hard-cap-fail lặp lại theo từng tổ hợp motor+board (v5.5, cả 4 tổ hợp đã đo
trong ngày)** — dùng cho việc review plan V5.6 (mục trước):

| Tổ hợp | Điểm fail lặp lại | Đặc điểm |
|---|---|---|
| P03/JIG7 | 8, 28, 66 | 3 điểm cô lập, plan V5.6 dựa vào đây |
| P03/JIG8 | 347 (4/4), 187 (3/4), 107 (2/3) | khác hoàn toàn P03/JIG7 dù cùng motor |
| P02/JIG7 | 142, 182, 260-303 (dải rộng) | ~81 lượt fail, khác hẳn 2 tổ hợp trên dù cùng board JIG7 |
| **P08/JIG8** (mới) | **308 (4/4), 148 (1/4)** | lại khác cả 3 tổ hợp trên |

**4/4 tổ hợp đã đo đều có điểm hard-cap-fail lặp lại RIÊNG, không trùng nhau, dù chia sẻ chung 1
motor hoặc 1 board với tổ hợp khác** — bằng chứng củng cố thêm cho nhận định đã đưa ra khi review
V5.6: đây là hiệu ứng tương tác cụ thể theo TỪNG CẶP motor+board tại 1 vùng góc riêng (khớp giả thuyết
H3 của plan — trạng thái cân bằng tĩnh/friction/cogging cục bộ), không phải lỗi cố định của riêng
motor hay riêng board. Củng cố thêm khuyến nghị: Pilot A/B của V5.6 nên mở rộng qua ít nhất 1 tổ hợp
JIG8 (ví dụ P03/JIG8 hoặc P08/JIG8) thay vì chỉ validate trên đúng P03/JIG7.

### 12. Đánh giá độ tin cậy dữ liệu H1/H2 sau creep — đủ dùng trên JIG8, chưa đủ trên JIG7

Trả lời câu hỏi treo từ 04/8 ("H1/H2 có sạch chưa"): **đủ tin cậy cho 3 tổ hợp JIG8 (P03/P08/P09)**
vì creep hội tụ gần hoàn toàn ở đó (88.8-100% escalation success), **chưa đủ cho JIG7** (P03/JIG7 còn
18-25% điểm chưa hội tụ, P02/JIG7 còn nhiều hơn).

Số liệu H1/H2 sạch đầu tiên (3 official run/motor, JIG8):

| | A1 (H1 amp) | A2 (H2 amp) |
|---|---:|---:|
| P03/JIG8 | 0.0119–0.0130° | 0.0112–0.0156° |
| P08/JIG8 | 0.0035–0.0058° | 0.0070–0.0090° |
| P09/JIG8 | 0.0094–0.0125° | 0.0061–0.0129° |

**Phát hiện lớn**: A1 giờ chỉ ~0.01-0.013° trên cả 3 motor — nhỏ hơn nhiều lần so với mọi giá trị H1
từng đo trong toàn dự án trước đây (0.12-0.55°, đều còn nhiễm artifact). Gợi ý phần lớn tín hiệu
"H1/H2 hình học/lệch tâm gá" trước đây thực ra chủ yếu là chính artifact settle-creep, không phải độ
lệch tâm cơ khí thật — có thể cần xem lại khung "họ harmonic hình học vs motor" đã xây dựng 04/8.
Biên độ nhỏ hơn cũng làm pha nhiễu hơn (H1 phase spread tới 44° ở P08 dù biên độ ổn định) — khớp đúng
dự đoán trước đó về gate vector-fingerprint cần ngưỡng thích ứng theo biên độ.

**Chưa tách được**: liệu A1/A2 nhỏ là do creep sạch, hay JIG8 vốn có độ lệch tâm nhỏ hơn JIG7 (gợi ý
từ "new board effect" 04/8) — cần dữ liệu JIG7 đạt độ sạch tương đương (chờ V5.6) để so sánh ngang hàng.

---

## Tổng kết ngày 2026-08-06

**Chuỗi tiến triển firmware creep**: kế thừa v4 (05/8) → V5.1 crossing-guard (an toàn nhưng 0% dữ liệu
dùng được) → V5.2 bounded-recovery → **V5.3 fine-landing point 66 (PASS 8/8, bước đột phá đầu tiên)**
→ V5.4 universal fine-landing (MIXED, 305 fine-landing failure/6 sweep, cụm `Point mod 10 = 6..9`) →
V5.4a diagnostic trace → **V5.5 dynamic BASE-to-EXTENDED escalation (kết quả NL tốt nhất từ trước tới
nay trên nhiều tổ hợp, nhưng mechanism gate escalation-success chưa đạt 90% trên JIG7)** → plan V5.6
three-stage 16→8→4 response-qualified landing (đã review, sẵn sàng code, khuyến nghị mở rộng validate
qua JIG8).

**Kết quả đo v5.5 trong ngày** (RobustP2P mean / cv, 3 official run):

| Tổ hợp | RobustP2P | cv | Ghi chú |
|---|---:|---:|---|
| P03/JIG7 | 0.4748° | 2.83% | escalation-success 75-82%, chưa đạt gate 90% |
| P02/JIG7 ("bị cho là lỗi") | 0.8119° | 17.95% | không breakaway, nhưng dải EXTENDED rộng gấp 3 — khả năng lỗi motor thật |
| P03/JIG8 | 0.2212° | 1.16% | escalation-success 88.8%, gần đạt gate |
| P09/JIG8 | 0.2189° | 0.17% | **100% mọi chỉ số mechanism, sạch nhất dự án** |
| P08/JIG8 | 0.2275° | 1.47% | 100% BASE escalation, sạch tương đương P09 |

**Phát hiện ngoài phạm vi firmware creep**: P09 lộ lỗi thật ở khâu hiệu chỉnh offset MA600 (tool
Gremsy riêng, không phải jig) — do thiết kế cố ý đặt sensor lệch trục item 8 để tiết kiệm không gian,
không phải lỗi motor hay lỗi jig NL. Đã lưu bài học vào memory dài hạn.

**Trạng thái cuối ngày / việc còn mở cho phiên sau**:
1. Code + hardware-test plan V5.6 (three-stage response-qualified landing), mở rộng Pilot A/B qua ít
   nhất 1 tổ hợp JIG8 theo khuyến nghị review.
2. P02 cần điều tra riêng (nghi lỗi motor thật, không phải vấn đề firmware creep) — không dùng làm căn
   cứ đánh giá V5.6.
3. Phân tích vector-fingerprint H1/H2 đầy đủ trên 3 bộ dữ liệu sạch JIG8 (P03/P08/P09) — mới có số thô,
   chưa dựng gate.
4. Xác nhận A1/A2 nhỏ là do creep sạch hay do đặc tính JIG8 — cần 1 tổ hợp JIG7 đủ sạch (sau V5.6) để
   so sánh ngang hàng.
5. Test `LiveNlPlot` trên phần cứng thật — vẫn treo từ 04/8, chưa làm.
6. Working tree đã xác nhận về đúng default (mọi flag `ENABLE_SWEEP_POINT_CREEP*`=0,
   `NL_TEST_REPEAT_10_RUNS=1`) trước khi commit.
