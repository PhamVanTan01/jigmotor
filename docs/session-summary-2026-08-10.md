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
