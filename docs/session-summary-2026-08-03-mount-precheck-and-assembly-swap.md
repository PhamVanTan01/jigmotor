# Tổng kết phiên làm việc 2026-08-03: MOUNT_PRECHECK_V1 M0 + phát hiện root-cause "cụm sensor+gá"

Tài liệu này tổng kết công việc hoàn thành trong phiên làm việc ngày 2026-08-03 (tiếp nối
`docs/CODEX_HANDOFF_NL_JIG_SYNC_2026-07-30.md`). Không lặp lại nội dung của
`docs/nl-jig1-jig4-rootcause-debug-plan-2026-08-03.md` (tài liệu song song, phiên khác,
cùng ngày) — tài liệu này ghi lại đúng những gì đã làm/tìm được trong phiên hội thoại này.

## 1. Thay đổi firmware (permanent, không phải flag thử nghiệm)

### 1.1. UART transmit failure tracking

`Core/Src/nonlinear_test.c`: `LogLine()`/`LogLineLarge()` trước đây bỏ qua giá trị trả về
của `HAL_UART_Transmit()`. Một lần truyền thất bại/timeout có thể làm 2 dòng log kề nhau bị
ghép (đã thấy trên hardware: `DATA,...,37839,ection=CW,Point=152,...` — mảnh của dòng
`MOTION` đè lên đuôi dòng `DATA`). Đã thêm:

- Counter `nlUartTransmitFailureCount`, reset đầu mỗi sweep, tăng khi `HAL_UART_Transmit`
  không trả `HAL_OK`.
- Field mới `UartTransmitFailures=<n>` trong record `END`.
- `Status` trong `END` chuyển `INVALID` nếu counter > 0, dù `measurementValid` vẫn đúng —
  vì log của sweep đó không còn tin cậy point-by-point.

Build: `builds/uart-transmit-failure-tracking-v1-20260803/`.

### 1.2. MOUNT_PRECHECK_V1 — milestone M0

Tận dụng đúng sweep PRECONDITION (đã có sẵn, 360 điểm đầy đủ) để tính gate mounting trước
khi vào OFFICIAL, không thêm motion mới. Record mới `MOUNT_PRECHECK_RESULT` (in ngay sau
PRECONDITION_RESULT):

```
MOUNT_PRECHECK_RESULT,SchemaVersion=5,BatchID=...,CycleOrder=...,TestID=...,
Protocol=PRECONDITION_FULL_SWEEP_MOUNT_GATE_V1,JigID=...,MotorID=...,
RobustP2PDeg=...,H1AmplitudeDeg=...,H1PhaseDeg=...,H2AmplitudeDeg=...,H2PhaseDeg=...,
ClosureErrorDeg=...,TrackingValid=...,ClosureValid=...,AcquisitionResult=...,
MountValid=...,RejectReason=...,GateEnabled=...
```

- `MountValid` hiện chỉ dựa trên 3 tiêu chí an toàn/không phụ thuộc sản phẩm đã có sẵn
  trong pipeline: `TrackingValid && ClosureValid && AcquisitionResult==OK`. **Chưa đưa
  ngưỡng H1/H2 vào** — chưa đủ dữ liệu pilot đa sản phẩm để hiệu chuẩn (xem mục 3).
- `ENABLE_MOUNT_PRECHECK_GATE` (mặc định 0): khi 0, record chỉ ghi log, không chặn batch.
  Khi 1, `MountValid=0` sẽ dừng batch trước OFFICIAL (`BATCH,Status=MOUNT_INVALID`).
- Đã xác nhận hoạt động đúng trên phần cứng thật: batch P03/JIG4 lúc 10:05 có
  `ClosureErrorDeg=0.264°` (>0.20° ngưỡng) → `MountValid=0,RejectReason=CLOSURE_INVALID`
  đúng như thiết kế.

Build: `builds/mount-precheck-v1-m0-diagnostic-20260803/` (1 pre + 10 official) và
`builds/mount-precheck-v1-m0-fast3-20260803/` (1 pre + 3 official, dùng cho các test
remount nhanh trong phiên này).

Cả 2 build đều: build sạch, 29/29 (hoặc 28/29 với build FAST3, do
`test_preconditioned_10run_contract.ps1` cố ý không áp dụng) test PowerShell pass.

## 2. Mở rộng tool `tools/analyze_nl_extreme_angles.py`

- Tính biên độ harmonic offline cho đủ 14 bậc (`H1,H2,H3,H4,H6,H8,H9,H12,H18,H27,H36,H45,H72,H108`)
  từ đường cong 360 điểm thô — đã verify khớp firmware đến 4 chữ số thập phân (H2).
- Xuất 3 biểu đồ mỗi motor: raw curve, centered curve (mean±1SD, đánh dấu top-5/bottom-5),
  harmonic spectrum — theo palette đã validate của skill `dataviz`.
- Thêm `--group-label-regex` và `--motor-label`: cho phép nhóm theo nhãn tùy ý (vd. tách
  từng lần remount, hoặc gộp nhiều file cùng 1 label) thay vì chỉ nhóm theo `JigID` gốc
  trong log — cần thiết cho các test remount-lặp-lại trong cùng 1 jig.
- Không đổi số liệu của các phép tính đã có (đã regression-check trước/sau khi mở rộng).

## 3. Phát hiện chính trong phiên — theo trình tự khám phá

### 3.1. Nhiễu remount trong 1 jig có thể lớn ngang khoảng cách cross-jig

3 lần remount P05/JIG1 (khóa lực siết + kiểm soát chiều xoay khi kiểm tra kẹt): NL dao động
range **0.084°** — cùng độ lớn với nhiều khoảng cách "cross-jig" đã ghi nhận trước đây trong
dự án. Kết luận: một phần đáng kể của "khác biệt jig" trong dữ liệu lịch sử có thể chỉ là
nhiễu remount chưa kiểm soát, không phải bias phần cứng cố định.

### 3.2. JIG4 (bản gốc) đạt gate repeatability rất sạch; JIG1, JIG5 (bản gốc) thì không

| Assembly (bản gốc, trước khi phát hiện mục 3.5) | NL range (3 remount) | Gate ≤0.05° |
|---|---:|---|
| JIG4 | 0.0195° | Đạt |
| JIG1 | 0.084° | Không đạt |
| JIG5 | 0.083° | Không đạt |

### 3.3. NL trôi gần như tuyến tính suốt phiên đo dài trên JIG1

7 lần đo P05/JIG1 trải dài 11:18–14:33: NL tăng gần đơn điệu 2.883°→3.220° trước khi giảm
nhẹ ở điểm cuối. H36 (chữ ký điện motor) giữ phẳng tuyệt đối suốt (<1% dao động) — loại trừ
motor, gợi ý hiệu ứng nhiệt hoặc lỏng cơ khí tích lũy theo thời gian, chưa xác định được
vì JIG4 mới chỉ đo trong cửa sổ 22 phút (chưa đủ để so sánh công bằng).

### 3.4. Vị trí đỉnh/đáy lỗi (top-5/bottom-5) ổn định trong từng jig, tách biệt đỉnh/đáy khi so 2 jig

JIG1↔JIG4 cần dịch góc ~320° mới khớp phần đỉnh (top, có vẻ do motor quyết định — khớp với
H36 luôn ổn định); phần đáy (bottom) **không khớp dù đã dịch** — gợi ý đáy do đặc tính riêng
từng cụm sensor+gá quyết định.

### 3.5. PHÁT HIỆN QUYẾT ĐỊNH: chữ ký lỗi đi theo cụm sensor+gá, không đi theo board điều khiển

Trong lúc thao tác, cụm sensor+gá của JIG1 và JIG5 (bản gốc) bị hoán đổi giữa 2 board mà
không nhận ra ngay. Dữ liệu tự lộ ra bất thường (1 file gắn nhãn "JIG1" cho ra đúng chữ ký
đáy của JIG4; 1 file gắn nhãn "JIG5" cho ra đúng chữ ký của JIG1 gốc, correlation r=0.9984
— cao nhất từng đo được trong toàn bộ cross-jig comparison của dự án). Người vận hành xác
nhận: đã tháo lắp cụm sensor+gá giữa các board trong phiên, và **gá không tách rời được khỏi
sensor** (là 1 khối cơ khí liền).

**Kết luận đã xác nhận, không còn nghi ngờ**: nguồn gốc khác biệt NL giữa "JIG1 vs JIG4 vs
JIG5" nằm ở cụm sensor+gá cơ khí (MA600 + mounting), **hoàn toàn độc lập với board điều
khiển/driver/firmware** (chạy chung 1 file hex suốt cả ngày). Tên gọi "JIG1/JIG4/JIG5" từ
nay cần hiểu là "board + cụm đang gắn tại thời điểm đo", không phải một thực thể cố định.

## 4. Trạng thái cấu hình vật lý cuối phiên (quan trọng cho phiên sau)

Tại thời điểm kết thúc phiên, cụm sensor+gá **chưa được trả lại đúng vị trí ban đầu**:

- Board **JIG1** đang mang cụm vốn thuộc **JIG4** (cụm "tốt", ~0.02° range).
- Board **JIG5** đang mang cụm vốn thuộc **JIG1** (cụm có vấn đề lặp lại, ~0.08° range).

**Trước khi tiếp tục bất kỳ so sánh cross-jig nào ở phiên sau, cần xác minh lại vật lý xem
cấu hình có còn đúng như trên không** — khuyến nghị đánh dấu vật lý cố định (nhãn A/B/C) lên
từng cụm sensor+gá, độc lập với tên board, để tránh lặp lại nhầm lẫn này.

## 5. Việc chưa hoàn thành / đề xuất cho phiên sau

1. Kiểm chứng thêm 1 lần: đặt cụm "tốt" (hiện ở board JIG1) lên board khác nữa, xác nhận vẫn
   giữ ~0.02° — đóng hẳn giả thuyết mục 3.5.
2. Tìm hiểu vật lý: cụm "tốt" khác gì về cơ khí (độ rơ khớp nối, mặt tỳ...) so với 2 cụm còn
   lại — đây mới là gốc rễ cần sửa, không phải firmware/thuật toán điều khiển.
3. Phân biệt trôi theo thời gian (mục 3.3) là do nhiệt hay do cơ khí — cần 1 phiên đo dài
   tương đương trên board đang mang cụm "tốt" để đối chứng.
4. Sau khi cấu hình vật lý được xác minh lại và đánh dấu rõ ràng, chạy lại Q1/Q2/Q3 theo
   đúng cụm (không theo tên board) để có kết luận cuối cùng.
5. Hệ số bù dead-time JIG1 (~0.6%, còn treo từ trước) — độ ưu tiên thấp hơn, vì root cause
   chính đã xác định là cơ khí, không phải driver.

## 6. Build đã đóng gói trong phiên

- `builds/uart-transmit-failure-tracking-v1-20260803/`
- `builds/mount-precheck-v1-m0-diagnostic-20260803/`
- `builds/mount-precheck-v1-m0-fast3-20260803/`

## 7. Dữ liệu/log thu thập trong phiên

Toàn bộ trong `captured-logs/` (kèm `.analysis.json/.txt` và `.metrics.csv` tự sinh) và các
thư mục `analysis-out/*-20260803/` tương ứng (CSV + biểu đồ) — xem chi tiết đường dẫn trong
từng mục ở trên.
