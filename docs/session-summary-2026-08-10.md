# Nhật ký công việc 2026-08-10

Theo đúng rule: mỗi ngày 1 file MD duy nhất, không tách theo chủ đề.

Tiếp nối trạng thái chốt cuối ngày 2026-08-06 (`session-summary-2026-08-06.md`): plan V5.6
three-stage 16→8→4 response-qualified landing đã khóa xong, sẵn sàng code.

## Hoạt động trong ngày

### 1. Review plan V5.6 (Graphify tự động + người vận hành) và sửa trước khi code

Một review tự động (Graphify) nêu 4 điểm: (1) gate promotion chỉ xét BASE, bỏ EXTENDED; (2) yêu cầu
phase trace cho point 8/28/66 trong khi firmware chỉ giữ 1 trace/sweep; (3) phase-efficiency
COARSE/MID/FINE bị confound bởi trạng thái cơ học, chưa có ngưỡng định lượng cho H1; (4) gate
family/correlation cần công thức circular rõ ràng. Đã sửa cả 4 điểm vào
`docs/sweep-point-creep-v5-6-three-stage-response-plan.md`:

- Thêm gate EXTENDED độc lập (success rate + failure-mean tuyệt đối) cho Pilot A1/A2, dùng số chính
  xác: P03/JIG7 baseline success=74.775%/failure mean=9.333/run; P03/JIG8 baseline
  success=99.482%/failure mean=0.333/run (verify khớp 100% với dữ liệu END record gốc).
- Làm rõ: final gap luôn có (sau khi bỏ nhánh lọc BASE-OK trong `SWEEP_CREEP_POINT`,
  `nonlinear_test.c:6413-6419`), phase trace chỉ đảm bảo có cho 1 điểm/sweep (điểm đầu tiên fail theo
  thứ tự Point 1→370 — verify: `pointIndex` khởi tạo 0, tăng sau khi point 0 capture, point 0 không
  qua creep). Giữ nguyên kiến trúc 1 trace buffer O(1) (không thiết kế 3 buffer riêng) — quyết định có
  chủ ý để giữ RAM, chỉ sửa tài liệu/kỳ vọng.
- Định nghĩa cụ thể "COARSE-tail" (3 lệnh COARSE cuối trước latch MID) thành field telemetry mới, khóa
  ngưỡng H1 = MID phải cao hơn COARSE-tail ≥150‰ (không suy ra sau khi có dữ liệu).
- Tách công thức "hard-cap failure family": cùng mounting dùng zero-shift/so đúng point-index (hard
  gate); khác mounting/jig/motor dùng best-shift search có sẵn (`analyze_nl_extreme_angles.py`,
  `compare_nl_group_curves.m`) nhưng chỉ mang tính chẩn đoán.

Đã sửa `scripts/analyze_nonlinear_logs.ps1` + `scripts/test_phase2b_shadow_contract.ps1` thêm UID
JIG8 (điều kiện tiên quyết pipeline plan tự đặt ra) — verify: contract test PASS, functional test trên
log thật parse đúng JigID=JIG8/Product=P08/NLAvgMean khớp số tính tay.

### 2. Code V5.6a (song song, không phải tôi) và hardware pilot trên P08/JIG8 — KẾT QUẢ: REJECT

Một phiên song song đã code, build (`builds/sweep-point-creep-v5-6-three-stage-response-fast3-20260810/`)
và chạy pilot 2 remount trên P08/JIG8 (không phải đúng combo A1=P03/JIG7 đã định, nhưng H1 là giả
thuyết vật lý không ràng buộc combo cụ thể).

**Kết quả (`analysis-out/p08-jig8-v56-remount01-02/nl_report.txt`)**:

| Chỉ số | Remount01 | Remount02 |
|---|---:|---:|
| Điểm 308 fail | 4/4 | 4/4 |
| MID efficiency | 751‰ | 767‰ |
| COARSE-tail efficiency | 964‰ | 962‰ |
| MID − COARSE-tail | **−213‰** | **−195‰** |
| Hard-cap official | 2.00/run | 1.33/run |

- **H1 KHÔNG xác nhận** — MID-8 kém hơn COARSE-tail gần 200‰ ở cả 2 remount (ngưỡng khóa trước là
  ≥+150‰), đảo dấu hoàn toàn chứ không chỉ chưa đạt ngưỡng. Điểm 308 fail **8/8 cycle** qua 2 remount.
- Không crossing/recross/recovery-failure/jump — thuật toán vẫn **ổn định về hành vi**, chỉ là MID-8
  **không hiệu quả** (đúng khung Stability/Effectiveness đã thống nhất trước khi code).
- Mounting đổi biên độ NL (0.2428°/0.2312°, r=0.9567) nhưng không loại bỏ được điểm 308 — củng cố đây
  là hiệu ứng cơ học hệ thống, không phải nhiễu.
- **Bug capture/logger mất khối DATA tái diễn lần 2** (lần đầu: V5.4a remount02, 06/8) — remount01
  thiếu 89/360 điểm 1 run, remount02 thiếu 11/360 điểm 1 run → chỉ 4/8 sweep dùng được cho stats.

**Quyết định** (khớp đúng nhánh "MID-8 không tốt hơn COARSE-16" trong plan, mục 13):
1. Dừng V5.6, không thử step 6/2 raw.
2. Quay lại firmware V5.5 làm baseline.
3. Sửa lỗi capture mất khối DATA (bug độc lập, ưu tiên, tái diễn lần 2).
4. Thiết kế phase diagnostic riêng cho stored-command deficit/static equilibrium/settle (khớp H3), giữ
   nguyên motion V5.5.

Đã cập nhật đầy đủ vào `docs/sweep-point-creep-v5-6-three-stage-response-plan.md` (status + mục 17).
Working tree đã xác nhận đúng default (`ENABLE_SWEEP_POINT_CREEP*`=0) sau khi package V5.6a.

## 3. Triển khai bước 3 — chống mất DATA trong app UART

Đã khoanh vùng rủi ro ở kiến trúc host: reader 921600 baud chuyển mỗi chunk qua
`Tk.after`, cập nhật textbox và redraw canvas quá thường xuyên; khi GUI bận,
Windows COM RX buffer có thể tràn dù firmware vẫn phát đủ dữ liệu. Đã sửa
`tools/stm32_uart_flasher.py` lên v1.10:

- reader thread đưa byte thẳng vào `BatchLogRecorder`, không chờ Tk;
- queue chuyển giao cho UI được gom burst 40 ms, plot redraw một lần/burst;
- yêu cầu RX buffer 1 MiB nếu driver hỗ trợ, đọc chunk tối đa 64 KiB;
- incremental UTF-8 decoder giữ đúng ký tự khi một code point bị cắt giữa hai chunk;
- khi đóng app, capture hoàn thành đang chờ trong queue vẫn được lưu;
- analyzer thêm gate `CaptureIntegrityValid`: terminal COMPLETE, không lỗi giải
  mã, đủ OFFICIAL, mỗi sweep đủ META/END/metrics/toàn bộ DATA index/closure.

Verdict được tách thành `PASS`, `CAPTURE INVALID`, `MEASUREMENT FAIL`, tránh coi
file UART thiếu DATA là motor FAIL. Unit test mới bơm stream telemetry >1 MiB
qua các chunk 1/2/3/5/... byte và đối chiếu byte-for-byte; test mất đúng một
dòng DATA phải trả `CAPTURE INVALID`. Kết quả: 6/6 Python tests PASS.

## 4. Triển khai bước 4 — V5.7-DIAG hard-cap passive hold

Đã implement diagnostic default-off trên đúng nền motion V5.5, không retune
step/power/budget:

- chọn điểm 0..359 đầu tiên có `NL_CREEP_BUDGET_EXCEEDED`;
- giữ nguyên actual stored command mà V5.5 vừa đạt, tuyệt đối không gửi thêm
  motor command trong cửa sổ chẩn đoán;
- lấy MA600 tại 0/10/25/50/100/200 ms;
- đóng băng DATA chính thức trước hold và tách acquisition counter diagnostic;
- phân loại `RELAXES_TOWARD_TARGET`, `DRIFTS_AWAY_FROM_TARGET` hoặc
  `STATIC_WITHIN_SETTLE_BAND` với ngưỡng vật chất khóa trước 9 raw. Classification
  dùng tổng thay đổi từ final creep sample tới hold 200 ms; đồng thời tách
  pre-hold DATA window và passive-hold window để không bỏ sót relaxation sớm;
- phát `SWEEP_CREEP_HOLD_CONFIG/SAMPLE/RESULT` sau khi motor dừng;
- ép `EligibleForStatistics=0` cho toàn bộ build vì hold 200 ms làm đổi cadence
  các điểm sau. Scalar NL từ build này không được dùng làm kết quả sản phẩm.

MATLAB parser/analyzer đã nhận schema mới và xuất `HoldByLabel`. Dedicated
contract V5.7, contract kế thừa V5.4/V5.5, toàn bộ contract PowerShell hiện có
và Release build đều PASS. MATLAB runtime không có trên máy build nên synthetic
MATLAB test đã thêm nhưng còn cần chạy tại máy có MATLAB.

Artifact sẵn sàng flash:
`builds/sweep-point-creep-v5-7-hardcap-hold-diag-fast3-20260810/jigmotor.hex`.
Quy trình/decision gate đầy đủ ở
`docs/sweep-point-creep-v5-7-hardcap-hold-diag-plan.md`.

Source đã được trả về cấu hình an toàn mặc định sau khi package: toàn bộ
`ENABLE_SWEEP_POINT_CREEP*` tắt và batch mặc định 1 precondition + 10 official.

## 5. Kết quả V5.7-DIAG (2 remount P08/JIG8) — xác nhận H3, đề xuất V5.8

Chạy V5.7-DIAG 2 remount trên P08/JIG8. Cả 2 batch đều "Sweep đầy đủ 4/4" — xác nhận fix UART v1.10
(mục 3) đã giải quyết được bug mất khối DATA (lần thứ 2, nay đã sạch).

| Kết quả | Remount01 | Remount02 |
|---|---:|---:|
| Hard-cap fail | 4 | 6 |
| Điểm 308 fail | 4/4 | 4/4 |
| Điểm 148 fail | 0/4 | 2/4 |
| Phân loại hold | 4 STATIC | 3 STATIC + 1 RELAX |
| Final gap điểm 308 | −37.5 ± 2.9 raw | −40.75 ± 3.3 raw |

- Điểm 308 fail **8/8** qua 2 remount — lỗi hệ thống, không phải nhiễu ngẫu nhiên.
- Hold verdict gộp: **7/8 STATIC_WITHIN_SETTLE_BAND** — rotor đứng yên khi dừng lệnh, không tự trôi
  vào target. Trường hợp RELAX duy nhất chạm ngưỡng 9 raw nhưng sau 200ms vẫn còn -28 raw (ngoài
  deadband ±9) — loại bỏ giả thuyết "chờ thêm sẽ tự vào".
- Không crossing/recovery/jump; acquisition/UART sạch.
- **Kết luận: H3 (static equilibrium) được xác nhận** — không phải vấn đề settle/dwell.

**Đề xuất V5.8** (bounded targeted terminal correction, chưa code): không thêm dwell; chỉ mở rộng
budget cho điểm EXTENDED đã hết 320 raw lên cap 400 raw (ước tính cần thêm ~64-66 raw dựa trên final
gap quan sát được / hiệu suất phản hồi ~55%), fine-step giữ 4 raw, iteration guard tối thiểu 101, giữ
nguyên crossing/jump guard. Mục tiêu: xác định cân bằng tĩnh là "mềm" (thêm lực thắng được) hay "cứng"
(cần giải pháp cơ khí, không phải firmware) — kết quả sẽ đóng dứt điểm câu hỏi firmware cho JIG7-class.

## 6. Re-verify H1/H2/H36 trên dữ liệu sạch (JIG8, V5.5) — việc treo từ 04/8

Dùng 3 motor khác nhau (P03/P08/P09) cùng board JIG8, cùng build V5.5 (creep hội tụ 88.8-100%, đủ sạch).
Chi tiết đầy đủ: `analysis-out/h1-h2-h36-reverify-clean-jig8-20260810.md`.

**Kết quả cross-motor (3 motor khác nhau, cùng board)**:

| Harmonic | cv cross-motor | Relative range |
|---|---:|---:|
| A36 (họ motor) | **1.88%** | 3.7% |
| A1/H1 (họ hình học) | 46.01% | 86.6% |
| A2/H2 (họ hình học) | 25.73% | 50.5% |

- **Khung "họ harmonic hình học vs motor" (04/8) được xác nhận rõ ràng trên dữ liệu sạch** — A36 ổn
  định 1.88% cv dù đổi cả 3 motor vật lý khác nhau (mạnh hơn phép thử 04/8, lúc đó chỉ đổi mount của
  cùng 1 motor qua các board, còn nhiễm artifact).
- **A1 giờ chỉ ~0.004-0.012°** — nhỏ hơn 10-100 lần mọi giá trị H1 từng đo trước 05/8 (0.12-0.55°) —
  xác nhận phần lớn "tín hiệu H1/H2" trước đây là chính artifact settle-creep, không phải lệch tâm
  cơ khí thật.
- **Giới hạn**: chưa đóng được vòng lặp gốc thật sự (yêu cầu 04/8 là cùng 1 motor ổn định qua các
  BOARD khác nhau) — JIG7 chưa đủ sạch để làm vế so sánh thứ 2. Cần chờ V5.8 (hoặc hướng thay thế)
  đưa JIG7 lên độ sạch tương đương.
- **Chưa làm**: gate `MountValid` theo vector H1/H2 (biên độ quá nhỏ/nhiễu pha còn cao để dựng ngưỡng
  tin cậy ngay); so sánh JIG1/JIG4 (mục tiêu gốc dự án, cần ít nhất 1 cặp board đều sạch).

## 7. Phân tích log V5.8 (`tools/dist/captured-logs`) — vì sao NL thu hẹp từ 3° còn 0.24°, và bằng
   chứng P02 là lỗi motor thật

Chạy `analyze_nl_stability_batch`/`analyze_sweep_creep_batch` trên 4 file V5.8 (P02 + P09 x3 remount,
JIG8). **Lưu ý**: cả 4 file tự khai `EligibleForStatistics=0` cho mọi sweep — đúng thiết kế theo
`docs/sweep-point-response-timing-v5-8-plan.md:39` (build DWT-timing diagnostic, chưa A/B xác nhận
không làm lệch cadence). Số liệu dưới đây là **thăm dò** (bật `includePrecondition=true` để vượt gate),
không phải thống kê chính thức.

**Số liệu thăm dò**: P02/JIG-thật (xem phần đính chính bên dưới) mean=0.464° (cv=0.75%); P09/JIG8 3
remount mean=0.223°/0.249°/0.229° (cv 1.7-4.1%) — khớp vùng đã biết trước đó cho JIG8.

**Mechanism telemetry sạch nhất từ trước tới nay**: 100% IntegrityValid, 100% BaseEscalationSuccessRate,
0 TargetCrossed/RecoveryRecrossed/StickSlipJump trên cả 16 sweep gộp. Telemetry DWT mới (lần đầu có):
hiệu suất creep 82.7-97% (so với 33-54% đo thủ công ở V5.4a), tỉ lệ về deadband kịp thời 98.4-99.5%.

**Giải thích "3° → 0.24°" — 4 lớp cộng dồn**: (1) sửa settle-creep gốc 3.05→1.78° (~42%, 04-05/8);
(2) dẹp crossing/stick-slip/overshoot V5.1→V5.5 để phép bù có tác dụng ở MỌI điểm; (3) JIG8 tự nó lệch
tâm cơ khí nhỏ hơn JIG7 ~2 lần (đã biết từ 04/8); (4) V5.6→V5.8 tiệm cận hiệu suất 83-97%, loại nốt
nhiễu do chưa hội tụ.

### Bằng chứng P02 là lỗi motor thật (không phải mounting/firmware)

So sánh harmonic H1(360°)/H2(180°) — "họ hình học" — với H36(10°) — "họ motor/cogging" — trên dữ liệu
JIG1 cũ (`analysis-out/b0b-p02-p07-within-product/`):

- P02 lệch cao hơn P03/P06 ~8%, cao hơn P07 ~32%, lặp lại ổn định qua 2 lần remount độc lập (CV<0.6%).
- H36 của P02 bình thường (0.90°, giữa dải 0.82-0.91° các sản phẩm khác) — không phải "cogging mạnh
  hơn". H2 của P02 (~0.25°) cao gần gấp 2.7 lần P07 (0.095°, sản phẩm tốt nhất).
- **Bằng chứng mấu chốt**: H2 amplitude VÀ phase gần như không đổi giữa 2 lần remount vật lý độc lập
  (amp lệch 0.7%, phase lệch 0.7°: -88.65° vs -87.94°) — nếu là lỗi ngàm/mounting thì phase phải xoay
  ngẫu nhiên theo mỗi lần gá lại; ở đây nó khóa theo rotor → lệch nằm trong chính motor.
- Xác nhận chéo trên dữ liệu V5.8 hôm nay: P02 vẫn cho H2 cao gấp 4-10 lần P09 (đối chứng) trên cùng
  điều kiện đo, trong khi phase H2 của P09 (đối chứng "tốt") trôi dạt qua từng lần remount — khác hẳn
  kiểu khóa pha ổn định của P02.

### Tool mới: quét quần thể H2/H36 toàn repo

`analysis/matlab/nl/scan_h2_geometric_signature.m` — quét 1 danh sách file log, tách ProductId (từ tên
file, pattern P0[2-9]) và JigId (ưu tiên `Meta.JigID`, fallback tên file), tính tỉ lệ RatioH2H36 =
H2/H36 mỗi sweep (chuẩn hóa cross-era vì cả H2 lẫn H36 tuyệt đối đều co lại nhiều lần qua các thế hệ
firmware — không chỉ riêng "họ hình học" bị nhiễm artifact như tưởng ban đầu). Chạy trên 237/379 file có
tag sản phẩm trong tên (1279 sweep hợp lệ), kết quả: `analysis-out/h2_geometric_scan_summary.csv` +
`_detail.csv`.

**Phát hiện quan trọng — phải đính chính kết luận trước đó**: gộp tỉ lệ H2/H36 xuyên-jig cho CV rất cao
(P03 CV=141%) — mỗi jig có nền hình học riêng, không thể so sánh trực tiếp giữa các jig khác nhau. Tách
lại theo từng jig cụ thể:

| Jig | Product cao nhất | Ratio | CV |
|---|---|---:|---:|
| JIG1 (N lớn nhất) | **P04** | 0.332 | 12% (rất chụm) |
| JIG1 | P02 (giữa bảng) | 0.205 | 41% |
| JIG7 | P02 | 0.261-0.375 | 7-37% |

→ Trên JIG1, P02 **không** phải outlier — P04 mới là ứng viên lệch hình học motor-intrinsic rõ và ổn
định nhất (CV thấp nhất hẳn). Kết luận "P02 luôn tệ hơn mọi sản phẩm" bị bác bỏ; kết luận đúng là "H2/H36
phải so sánh trong cùng 1 jig, không được gộp xuyên-jig".

**Phát hiện lỗi nhãn file**: `S2-P02-JIG8-remount01-test-1-v5-8.txt` — tên file ghi JIG8 nhưng field
`JigID` do chính firmware ghi trong META là `JIG7` (trùng MCU_UID=0046... với file
`S2-P02-JIG7-remount01-test-1-v5-7.txt` đã gắn đúng nhãn). Người vận hành gõ nhầm tên khi đặt tên file
phiên V5.8. Đã đổi tên lại thành `S2-P02-JIG7-remount01-test-1-v5-8.*` (5 file: txt/analysis.json/
analysis.txt/metrics.csv/response.csv) cho khớp firmware. Hệ quả: so sánh "P02 vs P09 cùng JIG8" ở phần
đầu mục này thực ra là P02-trên-JIG7 vs P09-trên-JIG8 — khác jig, một phần khoảng cách 2x có thể do jig
(JIG7 vốn NL nền cao hơn JIG8, "hiệu ứng board mới" đã biết từ 04/8), không thuần túy do motor.

**Bài học quy trình**: không tin tên file khi nhóm dữ liệu theo jig — luôn đọc field `JigID` trong chính
log (đã áp dụng trong `scan_h2_geometric_signature.m`).

## Việc còn lại / đề xuất cho phiên sau

1. Build + pilot V5.8 (bounded targeted terminal correction, cap 400 raw) trên P08/JIG8 — xác định
   cân bằng tĩnh tại điểm 308 mềm hay cứng; báo riêng hội tụ thật (final gap có về deadband hay không),
   không chỉ tỷ lệ EXTENDED success chung; theo dõi điểm 148 có lan rộng thêm không.
2. Sau khi có kết quả V5.8: nếu JIG7 đạt độ sạch tương đương JIG8, đo lại P03/JIG7 và đối chiếu trực
   tiếp A36/H36-phase với P03/JIG8 để đóng vòng lặp gốc của việc re-verify H1/H2/H36.
3. EXE v1.10 đã smoke-test PASS; đã xác nhận thêm qua 2 batch V5.7-DIAG thực tế (0 lỗi mất DATA) — có
   thể coi bug capture đã đóng, nhưng nên tiếp tục theo dõi thêm vài batch nữa trước khi coi là đóng
   hẳn.
4. Thiết kế gate `MountValid` theo vector H1/H2 trên dữ liệu sạch — cần thêm dữ liệu hoặc phương pháp
   giảm nhiễu pha trước khi dựng ngưỡng.
