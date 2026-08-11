# Nhật ký công việc 2026-08-05

Ghi lại toàn bộ hoạt động và kết quả trong ngày, theo đúng rule: mỗi ngày 1 file MD duy nhất, không
tách rời theo chủ đề (tránh lặp lại tình trạng ngày 2026-08-04 bị chia thành 2 file riêng biệt —
`session-summary-2026-08-04-board-effect-and-sensor-fixture-separation.md` và
`session-summary-2026-08-04-h1h2-creep-contamination-and-live-nl-plot.md`, từ 2 phiên làm việc khác
nhau cùng ngày).

Tiếp nối trực tiếp việc chưa hoàn thành cuối ngày 2026-08-04 (xem file
`session-summary-2026-08-04-h1h2-creep-contamination-and-live-nl-plot.md`, mục 8):

1. **Ưu tiên cao**: sửa vấn đề nhiệt/giật cục của `ENABLE_SWEEP_POINT_CREEP` (xem
   `session-summary-2026-08-04-board-effect-and-sensor-fixture-separation.md`, mục 6.5) trước khi
   đo thêm.
2. Sau khi creep "sạch" (đã sửa nhiệt/giật): đo lại H1/H2/H36 — hiện mọi số đo được trong dự án đều
   còn lẫn artifact settle-creep chưa fix hết (H1/H2 cũng bị nhiễm, không chỉ H36).
3. Verify bậc 36 (và H1/H2) có còn ổn định qua các board/sensor khác nhau sau khi creep fix triệt để.
4. Thiết kế gate `MountValid` theo H1/H2 (vector fingerprint) — chỉ tính ngưỡng trên dữ liệu đã xác
   nhận sạch (mục 2), không kỳ vọng bảng hiệu chuẩn 32 điểm sửa được H36.
5. Test `LiveNlPlot` (đồ thị NL trực tiếp trong `tools/stm32_uart_flasher.py`) trên phần cứng thật.

---

## Hoạt động trong ngày

### 1. Fix v3 cho `ENABLE_SWEEP_POINT_CREEP` — giải quyết vấn đề nhiệt/giật cục (mục 6.5, tài liệu 08-04)

**Thay đổi code** (`Core/Src/nonlinear_test.c`):
- `CreepToUnwrappedTarget()` được **tham số hóa** (step/deadband/budget/số lần lặp/công suất giờ là
  tham số truyền vào, không hardcode theo macro `NL_B0B_CREEP_*`/literal `1.0f` nữa) — cho phép vòng
  lặp quét chính dùng bộ tinh chỉnh RIÊNG mà không đụng hành vi B0-B (2 điểm gọi B0-B vẫn truyền
  đúng y nguyên hằng số + `1.0f` cũ, hành vi giữ nguyên tuyệt đối).
- Hằng số mới riêng cho vòng lặp chính (`NL_SWEEP_CREEP_*`):

| | v2 (cũ) | v3 (mới) | Lý do |
|---|---:|---:|---|
| Bước | 8 raw | 16 raw | Giảm ~1/2 số lệnh cho cùng quãng bù |
| Ngân sách | 150 raw | 220 raw | v2 chạm trần ở ~44% điểm (khe hở thật tới 181 raw) — 220 đủ dư |
| Số lần lặp tối đa | 30 | 15 | Tính lại theo tỷ lệ bước/ngân sách mới |
| Công suất | 1.0f (toàn phần) | 0.6f | Giảm nhiệt — **chưa xác minh đủ lực hay không** |

- Build sạch, 28/29 script pass (FAST3), `test_b0b_creep_contract.ps1` đã cập nhật (không làm yếu đi)
  để xác nhận B0-B không đổi hành vi + tinh chỉnh mới đúng như thiết kế.
- Đóng gói: `builds/sweep-point-creep-v3-heat-tuning-fast3-20260805/` — **chưa test phần cứng**.

**Kỳ vọng cần kiểm tra khi test** (xem chi tiết `build_info.txt`):
1. Cảm nhận chủ quan: nóng ít hơn / giật ít hơn so với v2 không?
2. `SweepPointCreepBudgetExceeded` giảm về gần 0 (so với ~44% ở v2).
3. `SweepPointCreepTotalIterations` giảm khoảng một nửa.
4. RobustP2P/A36 vẫn giữ gần mức v2 (~1.74-1.83°/~0.31° trên P08) — không được thụt lùi.
5. **Mới, theo phát hiện MATLAB (mục 2, tài liệu H1/H2 contamination 08-04)**: so sánh thêm H1/H2
   (không chỉ H36) — nếu ngân sách lớn hơn/bù trọn vẹn hơn giúp H1/H2 hội tụ gần fw cũ hơn nữa so
   với v2, đó là bằng chứng trực tiếp mức nhiễm H1/H2 tỷ lệ với việc bù settle chưa trọn vẹn tới đâu.

### 2. v3 THẤT BẠI trên phần cứng thật — công suất 0.6f không đủ lực, revert về v4

Test `S2-P08-JIG7-remount01-test-5.txt` (bản v3, BuildID `Aug 5 2026 08:36:53`) — người vận hành báo
**motor giật cục hơn, đường NL tệ hơn**. Xác nhận bằng số liệu:

| | v2 (đã fix) | v3 (công suất 0.6f) |
|---|---:|---:|
| RobustP2P | 1.74-1.83° | **3.126°** (gần bằng fw cũ 3.05-3.07°) |
| A36 | 0.31° | **0.42°** |
| `TotalCorrectionRaw` | ~39000 | **60368** (tăng, không giảm) |
| `BudgetExceeded` | 44% | **50.7%** (tệ hơn dù ngân sách tăng 150→220) |
| Độ lệch giữa 3 run/batch | thấp | cv(A2)=70.58% — bất thường |

**Nguyên nhân**: 0.6f không đủ lực thắng ma sát/cogging → mỗi bước lệnh 16 raw di chuyển thực tế ít
hơn → cần nhiều bước hơn để đóng cùng khe hở (giải thích `TotalCorrectionRaw` tăng) → có thể gây
"dính-trượt" (stick-slip: đứng yên rồi bật đột ngột) — khớp đúng báo cáo "giật cục hơn" của người
vận hành.

**Đã sửa (v4)**: trả `NL_SWEEP_CREEP_POWER` về **1.0f** (giữ nguyên bước 16 raw + ngân sách 220 —
2 thay đổi này không mang rủi ro lực, chỉ đổi cách chia nhỏ/giới hạn tổng bù, không đổi lực mỗi
lệnh). Build sạch, 28/29 test pass, `test_b0b_creep_contract.ps1` đã cập nhật khớp `1.0f`.
Đóng gói: `builds/sweep-point-creep-v4-power-revert-fast3-20260805/` — **chưa test phần cứng**.

**Bài học**: không giảm công suất theo bước nhảy lớn (1.0→0.6) mà chưa có dữ liệu hiệu chỉnh —
lần sau nếu vẫn muốn giảm nhiệt qua công suất, cần thử từng bước nhỏ (ví dụ 0.85f trước), không lặp
lại bước nhảy lớn như v3.

### 3. v4 bất ổn định (cv 18-39% qua 3 remount) — phân tích không gian "điểm khó"

Test v4 trên phần cứng thật (3 lần remount, P08/JIG7/sensor mới): trung bình cải thiện so với v2
(RobustP2P 1.48-1.65° so với v2's 1.74-1.83°) nhưng cv giữa 3 run trong cùng batch cao bất thường
(remount01=21.4%, remount02=18.7%, remount03=39.2% — so với v2's cv~1-1.5%). Tỷ lệ chọn lại đỉnh/đáy
giảm còn top=80%, bottom=66.7% (bình thường 90-100%). Đề xuất 3 hướng xử lý; theo quyết định "làm
hướng 2 trước" (rẻ, không cần phần cứng mới) — giao 1 agent khác phân tích sâu dữ liệu MOTION đã có.

**Kết quả phân tích** (`analysis-out/p08-jig7-v4-creep-difficulty-spatial-analysis.md`, dùng
`|MOTION.PositionErrorRaw|` — khe hở trước creep tại từng điểm — làm proxy độ khó, vì firmware không
log iteration/BudgetExceeded riêng từng điểm, chỉ tổng cả sweep trong `END`):

- Tương quan "difficulty theo góc" giữa 3 remount: Pearson 0.979-0.991, Spearman 0.978-0.990 — rất
  cao. Overlap top-15% điểm khó giữa các cặp remount: 80-90% (Jaccard).
- Điểm khó xuất hiện ổn định ở ≥2/3 remount: `0°,67°,106°,107°,173°,174°,175°,214°,254°,293°,294°,
  295°,324°,334°` — và trong nhóm này, 4 điểm trùng CHÍNH XÁC với cực trị NL đã biết trước đó
  (top/bottom-5 của báo cáo `nl_extreme_angle_report.md`): **67°, 107°, 173°, 293°**.
- **Kết luận nhị phân: CÓ cấu trúc lặp lại theo góc — không phải nhiễu ngẫu nhiên độc lập.**
- Phát hiện thêm quan trọng (DFT trên difficulty curve): "điểm khó" không phải 1 điểm cơ khí đơn lẻ
  mà là 1 họ harmonic tuần hoàn — H27, H36, H45, H72 (**trùng đúng họ harmonic "motor" đã xác lập từ
  trước trong dự án**, xem `session-summary-2026-08-04-board-effect-and-sensor-fixture-separation.md`
  mục 5) — cộng thêm các sideband gần H36 (H35, H37) và H81. Diễn giải: khe hở-trước-creep lớn nhất
  rơi đúng vào các pha mà torque ripple/cogging của rotor 6-cặp-cực biến thiên theo chu kỳ (không phải
  1 điểm gá/ổ bi hỏng cục bộ) — lực khả dụng lúc creep chạy thay đổi tuần hoàn theo góc quay, không
  phải bất thường cơ khí đơn điểm.

**Ý nghĩa cho quyết định hướng đi tiếp theo**:
- Hướng 1 (tăng ngân sách) giờ có cơ sở vững hơn nhiều so với đánh giá ban đầu — vì đã xác nhận đây
  KHÔNG phải nhiễu ngẫu nhiên/không thể sửa, mà là khe hở lặp lại, có vị trí xác định.
- Nhưng nên làm **có mục tiêu** thay vì tăng tràn lan cả 360 điểm: chỉ tăng ngân sách/bước tại nhóm
  ~54 điểm khó đã xác định (danh sách top-15% trong file phân tích), giữ nguyên 220 raw cho phần còn
  lại — giảm thêm iteration/nhiệt so với tăng đều 220→300-350 cho toàn bộ sweep.
- Ít nhất 1 phần tín hiệu NL cực trị đo được (67°,107°,173°,293°) hiện đang bị ảnh hưởng trực tiếp bởi
  việc creep CHƯA đóng hết khe hở tại đúng các góc đó, không hoàn toàn từ eccentricity/sensor độc lập.

**Giới hạn**: tương quan cao loại phần lớn giả thuyết nhiễu độc lập nhưng không tự chứng minh 1 lỗi cơ
khí đơn lẻ — pattern harmonic khả dĩ đến từ cogging/điện từ nội tại motor. remount03 (TestID 6) thiếu
13 MOTION record (280-292°, do lỗi UART); sensitivity analysis không đổi kết luận đáng kể (lệch tối đa
0.0017 hệ số tương quan).

**Cập nhật**: 1 phiên làm việc song song (parallel session, không phải tôi) đã tự triển khai đúng hướng
targeted-budget này trong lúc tôi chờ xác nhận — xem mục 4 bên dưới.

### 4. v5-adaptive-budget (phiên song song) — test trên P03, PHÁT HIỆN LỖI MỚI: target-crossing overshoot

Một phiên làm việc khác (không phải tôi) đã độc lập triển khai đúng ý tưởng "targeted extended budget"
đề xuất ở mục 3: `NL_SWEEP_CREEP_EXTENDED_*` — nếu khe hở sống trước creep tại 1 điểm `>200 raw` thì
dùng ngân sách mở rộng (320 raw/21 lần lặp) thay vì ngân sách cơ bản (220 raw/15 lần lặp). Đã build 2
bản: `sweep-point-creep-v5-adaptive-budget-fast3-20260805` (11:22, chưa có bảo vệ overshoot) và
`sweep-point-creep-v5-1-crossing-guard-fast3-20260805` (12:18, có bảo vệ). Tài liệu thiết kế:
`docs/sweep-point-creep-v5-adaptive-budget-plan.md`, `docs/sweep-point-creep-v5-1-target-crossing-guard-plan.md`.

**Test thực tế** (`captured-logs/S2-P03-JIG7-remount01-test-7.txt` = v4 baseline, `..._02.txt` = v5
adaptive-budget, cùng motor P03/JIG7, cùng remount, người vận hành gửi trực tiếp lên đây):

| | v4 (220 raw cố định) | v5-adaptive (200 raw trigger → 320 raw mở rộng) |
|---|---:|---:|
| RobustP2P 3 run | 0.9348 / 0.9169 / 0.9515° | **0.4977 / 0.8359 / 1.4591°** |
| cv (RobustP2P) | 1.85% | **52.39%** |
| BudgetExceeded | 49, 52, 52 | 48, 51, 52 (chỉ giảm 1.3%, không đáng kể) |
| Extended points OK | — | 82.2% (dưới ngưỡng gate 90% đã đặt ra) |

**v5-adaptive-budget làm TỆ HƠN v4 rất nhiều trên chính motor P03 vốn rất ổn định** — phủ định giả
thuyết "P08 mới là nguyên nhân bất ổn định" nêu ở mục 3; vấn đề nằm ở chính cơ chế creep, không phải
đặc thù của motor P08.

**Nguyên nhân đã được phiên song song xác định** (`sweep-point-creep-v5-1-target-crossing-guard-plan.md`
mục 1): `CreepToUnwrappedTarget()` khóa cứng HƯỚNG bù ngay từ khe hở ban đầu. Khi xảy ra stick-slip
(rotor đứng yên rồi bật đột ngột, đúng như nghi ngờ trước đó về v3/v4), rotor có thể vọt QUA target —
nhưng creep vẫn tiếp tục ra lệnh theo hướng cũ, đẩy rotor CÀNG XA target hơn. Ví dụ cụ thể từ log:
run 2 điểm 195° (khe hở đầu +54 → khe hở cuối -327 raw, lỗi NL -1.81°), run 3 điểm 66° (-233 → +315
raw, +1.72°), run 3 điểm 284° (+213 → -376 raw, -2.10°) — khớp chính xác với việc RobustP2P dao động
dữ dội giữa các run.

**Đã có sẵn bản sửa (v5.1, `TargetCrossingGuard=STOP_BEFORE_NEXT_COMMAND_V1`)**: sau mỗi bước
creep+settle, nếu dấu khe hở đảo ngược so với hướng ban đầu (đã vọt qua target) thì DỪNG NGAY, không ra
thêm lệnh nào — không cố gắng sửa tiếp theo hướng cũ (đã sai) hay hướng mới (chưa kiểm chứng). Sweep có
điểm bị `TARGET_CROSSED` sẽ tự động bị đánh dấu `SweepPointCreepIntegrityValid=0`/`END.Status=INVALID`,
không được dùng làm kết quả NL chính thức.

### 5. v5.1-crossing-guard — test trên P03, KẾT QUẢ: guard hoạt động đúng thiết kế nhưng KHÔNG đủ để dùng được

Test thực tế (`captured-logs/S2-P03-JIG7-remount01-test-1-v5-1.txt`, BuildID `Aug 5 2026 12:16:49`,
cùng P03/JIG7/remount01):

- Crossing vẫn xảy ra ở **CẢ 4/4 sweep** (kể cả precondition): 3, 4, 2, 3 điểm bị `TARGET_CROSSED` mỗi
  sweep (trên ~350 điểm đã hiệu chỉnh, tức ~0.6-1.1%/sweep) — guard hoạt động đúng thiết kế (dừng ngay,
  không đẩy xa thêm) nhưng **không loại bỏ được hiện tượng gốc** (stick-slip khiến rotor vọt qua target).
- Theo đúng chính sách validity đã thiết kế: `SweepPointCreepIntegrityValid=0` → `END.Status=INVALID` ở
  cả 4 sweep → **`OfficialValid=0/3`, `AutoVerdict=FAIL`** — v5.1 hiện tại **không tạo ra được bất kỳ
  kết quả NL chính thức nào** trên bộ test này (tệ hơn cả v5-adaptive, vốn còn cho 3/3 valid dù không
  ổn định).
- RobustP2P vẫn dao động dù đã giảm biên độ so với v5 (0.53/0.85/0.53/0.86° — dao động nhị phân giữa 2
  mức, thay vì 0.50-1.46° lộn xộn như v5) — khớp đúng nhánh quyết định đã ghi sẵn trong kế hoạch v5.1:
  *"crossing remains and NL spikes remain at the guarded final gap: do not use those sweeps; V5.2 needs
  a bounded recovery/re-settle operation"*.

**Kết luận cho quyết định hướng đi**: đã thử cả 2 biến thể sửa lỗi (v5-adaptive: ổn định kém, v5.1
crossing-guard: an toàn hơn nhưng 0% dữ liệu dùng được) — cả hai đều **chưa đạt yêu cầu để thay thế v4**.
v4 (ngân sách cố định 220 raw, không có cơ chế mở rộng/crossing-guard) vẫn là bản **duy nhất** cho kết
quả ổn định + dùng được (100% valid, cv thấp) trên cả P03 lẫn P08 (dù P08 còn spread lớn hơn P03).
Khuyến nghị: tạm dừng nhánh v5/v5.1 (cần thiết kế v5.2 "bounded recovery" — chưa có), quay lại v4 làm
baseline cho các việc đang chờ (re-verify H1/H2/H36, LiveNlPlot...).

### 6. v5.2 — bounded single recovery: thu hồi dữ liệu sau crossing nhưng chưa xử lý được breakaway lớn

V5.2 thay chính sách “crossing là invalid ngay” của V5.1 bằng đúng một nhánh recovery có giới hạn:

- dừng trước lệnh tiếp theo sau khi phát hiện đổi dấu khe hở;
- đảo chiều đúng một lần với cùng bước 16 raw;
- giới hạn recovery riêng, không cho phép chase vô hạn;
- recovery thành công được chấp nhận, còn `RECOVERY_RECROSSED`/recovery failure làm
  `SweepPointCreepIntegrityValid=0` và khóa toàn batch qua precondition gate;
- toàn bộ telemetry vẫn được in sau `Motor_Disable()`, không chèn UART vào cadence đo.

Firmware và tài liệu:

- `builds/sweep-point-creep-v5-2-single-recovery-fast3-20260805/`;
- `docs/sweep-point-creep-v5-2-single-recovery-plan.md`.

Kết quả P03/JIG7 cho thấy recovery giải quyết được phần lớn crossing nhỏ, nhưng vẫn còn một sự kiện
stick-slip lớn tại point 66 trong precondition remount01:

- `InitialGapRaw=-238`;
- crossing từ `PreCrossGapRaw=-18` sang `CrossingGapRaw=279`;
- recovery 144 raw lại recross, kết thúc `FinalGapRaw=-100`;
- precondition invalid nên ba official phía sau dù tự thân đo sạch vẫn có
  `EligibleForStatistics=0`.

Kết luận: V5.2 đúng về an toàn và chống chase, nhưng bước 16 raw khi gần target vẫn có thể kích hoạt
breakaway lớn. Không thể chỉ tăng thêm recovery budget vì sẽ biến thuật toán thành đuổi qua lại quanh
điểm cân bằng.

### 7. v5.3 — fine landing tại point 66 và jump guard

V5.3 giữ nguyên power/budget/settle của V5.2 và chỉ thay đổi cách hạ cánh tại point 66:

- coarse step 16 raw khi còn xa;
- khi `abs(live gap) <= 64 raw`, latch sang fine step 4 raw;
- giới hạn jump quan sát 96 raw;
- nếu jump vượt ngưỡng thì dừng, không recovery/chase;
- log `SWEEP_CREEP_STEP` từ buffer RAM sau capture để không làm nhiễu thời gian đo;
- `SWEEP_CREEP_CONFIG`/`SWEEP_CREEP_POINT` nâng lên schema 6;
- các điểm khác và B0-B giữ nguyên hành vi V5.2.

Tài liệu và contract:

- `docs/sweep-point-creep-v5-3-point66-fine-landing-plan.md`;
- `scripts/test_sweep_point_creep_v5_3_contract.ps1`.

#### 7.1 Lỗi chỉ chạy một precondition rồi đứng

Ba log đầu tiên của V5.3 đều hoàn tất precondition hợp lệ, in `COOLDOWN_START`, nhưng không bắt đầu
official run 1 sau 120 giây. Đây không phải lỗi motion/point 66.

Phân tích `.su` của compiler xác định chuỗi stack sâu nhất của `TestTask` dùng khoảng 7656 byte:

| Hàm | Stack tĩnh |
|---|---:|
| `NonlinearEngine_Task` | 64 byte |
| `RunBatchSweep` | 72 byte |
| `NonlinearTest_Run` | 1456 byte |
| `PrintSweepLog` | 4152 byte |
| `LogLineLarge` | 1912 byte |

Stack cũ chỉ 8192 byte, còn 536 byte cho context/ngắt. Lần context switch đầu tiên sau
`COOLDOWN_START` kích hoạt `configCHECK_FOR_STACK_OVERFLOW=2`, đi vào
`vApplicationStackOverflowHook()`/`Error_Handler()` nên firmware dừng im lặng.

Đã sửa:

- tăng `TestTask` từ 8192 lên 12288 byte;
- thêm `RUNTIME_CHECKPOINT` ngay sau `COOLDOWN_START`;
- thêm `COOLDOWN_PROGRESS` mỗi 30 giây;
- không đổi bất kỳ hằng số chuyển động nào.

Artifact đã sửa stack:

- `builds/sweep-point-creep-v5-3-point66-fine-landing-fast3-stackfix-20260805/`;
- SHA-256 HEX:
  `7a57369d99ccd28150061a9dd1becc86a016e96799f47cfba0106c7ddadf2ce6`.

Artifact `sweep-point-creep-v5-3-point66-fine-landing-fast3-20260805` cũ bị supersede, không dùng để
flash vì vẫn có stack 8192 byte.

#### 7.2 Hardware pilot remount01 — PASS đúng scope

Log `captured-logs/S2-P03-JIG7-remount01-test-2-v5-3.txt` chạy đủ một precondition + ba official:

- `OfficialValid=3/3`, batch `COMPLETE`;
- stack high-water còn 1026 word, tương đương khoảng 4104 byte; free heap 85544 byte;
- heartbeat cooldown xuất hiện tại khoảng 33/63/93 giây;
- point 66: `FinalGapRaw=-14/-13/-16/-10`, 4/4 trong +/-16 raw;
- fine landing 4/4 thành công, không jump, không recovery failure;
- acquisition sạch: không SPI failure, jump reject, failed sample, timing overrun hay UART failure.

Ba official của remount01:

| Metric | Mean | SD |
|---|---:|---:|
| NLAvg (top-5 minus bottom-5) | 0.52355° | 0.02998° |
| System INL | 0.30614° | 0.0152° |
| RMS_AC | 0.09946° | 0.0051° |
| A36 | 0.10450° | 0.0059° |

#### 7.3 Hardware pilot remount02 — point 66 PASS, toàn batch FAIL

Log `captured-logs/S2-P03-JIG7-remount02-test-2-v5-3.txt` xác nhận fine landing point 66 bền qua
remount:

- point 66: `FinalGapRaw=-12/-15/-11/-12`, tiếp tục 4/4 trong +/-16 raw;
- cộng hai remount: 8/8 cycle đạt, trung bình endpoint chỉ dịch 0.75 raw giữa hai lần gá;
- stack/cooldown tiếp tục sạch và batch chạy đủ bốn cycle.

Tuy nhiên precondition bị invalid tại **point 26**, nơi V5.3 chưa bật fine profile:

- `InitialGapRaw=-216`, budget class `EXTENDED`;
- coarse creep đi tới `PreCrossGapRaw=-26`;
- rotor breakaway sang `CrossingGapRaw=185`, bước nhảy quan sát 211 raw;
- recovery 96 raw lại recross và kết thúc `FinalGapRaw=-47`;
- `Result=RECOVERY_RECROSSED`, `SweepPointCreepIntegrityValid=0`;
- precondition khóa đúng ba official sau đó: `OfficialValid=0/3` dù acquisition riêng từng sweep sạch.

Điểm 26 không phải sự kiện hoàn toàn mới: V5.2 remount03 từng quan sát crossing lớn tại cùng điểm
(`-19 -> +248 raw`), khi đó recovery may mắn kết thúc đúng biên `+16 raw`. Vì vậy đây là cơ chế
stick-slip có khả năng tái diễn, không nên rerun để “chờ may mắn pass”.

Ba official remount02 không được dùng làm kết quả chính thức. Chỉ với mục đích chẩn đoán, các metric
vẫn gần remount01:

| Metric | Remount01 official | Remount02 diagnostic | Delta |
|---|---:|---:|---:|
| NLAvg | 0.52355° | 0.52871° | +0.00516° |
| System INL | 0.30614° | 0.29550° | -0.01064° |
| RMS_AC | 0.09946° | 0.09526° | -0.00420° |
| A36 | 0.10450° | 0.09956° | -0.00494° |

Điều này tách được hai kết luận: measurand NL chưa cho thấy dịch lớn sau remount, nhưng motion
integrity chưa đủ tin cậy để cho phép công bố kết quả đó.

### 8. Trạng thái chốt cuối ngày và bước tiếp theo

| Hạng mục | Trạng thái |
|---|---|
| V5 adaptive budget | FAIL — crossing bị chase sai hướng |
| V5.1 crossing guard | Cơ chế guard PASS, dữ liệu usable FAIL |
| V5.2 bounded recovery | Cải thiện crossing nhỏ, chưa chịu được breakaway lớn |
| V5.3 fine landing point 66 | **PASS mạnh: 8/8 qua hai remount** |
| V5.3 stack fix | **PASS trên phần cứng** |
| V5.3 toàn hệ thống | **CHƯA PROMOTE** — point 26 làm remount02 invalid |
| Acquisition/transport | PASS trong các batch V5.3 hoàn chỉnh |

Quyết định tiếp theo là thiết kế **V5.4 generalized targeted fine landing**, không hardcode point 66:

1. Áp dụng coarse-to-fine 16 -> 4 raw cho mọi điểm `EXTENDED` được chọn từ live initial gap.
2. Chuyển fine khi `abs(live gap) <= 64 raw`.
3. Áp dụng jump guard 96 raw cho toàn bộ nhóm fine.
4. Giữ nguyên power 1.0f, budget 320 raw, settle và acquisition contract.
5. Không chase/recovery sau một fine-step jump đã xác nhận.
6. Pilot FAST3 trên P03/JIG7/remount02 trước khi mở rộng motor/jig.

Source sau đóng gói đã trả về mặc định an toàn:

- `ENABLE_SWEEP_POINT_CREEP=0`;
- `ENABLE_SWEEP_POINT_CREEP_V53_POINT66_FINE_LANDING=0`;
- batch mặc định một precondition + mười official;
- stack `TestTask=12288` được giữ lại vì đây là fix hạ tầng, không phải feature thử nghiệm.

Verification cuối ngày:

- default Release build pass;
- feature-on V5.3 FAST3 Release build pass;
- 30/30 PowerShell contract suite pass;
- `git diff --check` trên source/script pass; các cảnh báo còn lại chỉ nằm trong file linker `.map`
  được sinh tự động;
- `graphify update .` pass.

*(chốt nhật ký cuối ngày 2026-08-05)*
