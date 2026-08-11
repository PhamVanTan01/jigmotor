# Tổng kết phiên làm việc 2026-08-04: nhiễm artifact creep lan sang H1/H2, giới hạn LUT 32 điểm, đồ thị NL trực tiếp trong flasher

Tài liệu này nối tiếp `docs/session-summary-2026-08-04-board-effect-and-sensor-fixture-separation.md` (gọi tắt "tài liệu creep") — không lặp lại nội dung đã có ở đó, chỉ ghi phát hiện mới và việc đã làm trong phiên hội thoại này.

## 1. Đối chiếu độc lập bộ dữ liệu creep-fix (không dùng tool đã build sẵn của tài liệu creep, dùng lại `analyze_nl_stability_batch.m` + `classify_jig_peak_signatures.m`)

Chạy trên đúng 6 file `captured-logs/S2-P08-JIG7-remount*-test-{1,2,3}.txt`:

- Xác nhận đúng ánh xạ: `test-1` = firmware cũ (BuildID `Aug 3 2026 11:14:03`), `test-2` (chỉ remount01) = build creep có bug (`Aug 4 2026 16:24:54`), `test-3` = build đã fix (`Aug 4 2026 16:49:46`).
- Số liệu khớp gần như tuyệt đối với tài liệu creep: `BUGGY_CREEP` RobustP2P=3.46° (tài liệu: 3.46°); `FIXED_CREEP` 3 remount RobustP2P=1.743/1.778/1.829° (tài liệu: 1.743/1.778/1.829° — khớp từng số).
- **Vị trí 36 đỉnh + 36 đáy khớp 100% giữa OLD_FW và FIXED_CREEP** (`classify_jig_peak_signatures.m`, `NMaxMatched=36/36`, `NMinMatched=36/36`, lệch vị trí 0-1 điểm) — xác nhận độc lập kết luận "vị trí do cơ khí, biên độ do biến số khác" bằng một tool khác với tool tài liệu creep đã dùng.
- 3 lần remount trong `FIXED_CREEP` phân loại `SAME_CLASS` với nhau (mean|Δ| chỉ 0.02-0.04°) dù RobustP2P trôi tăng dần — khớp giả thuyết "do nhiệt tích luỹ" của tài liệu creep mục 6.5.

## 2. Phát hiện mới #1 (quan trọng nhất): artifact settle-creep không chỉ nhiễm H36 — nó nhiễm cả H1/H2

Tài liệu creep chỉ đo H36 trước/sau fix. Phiên này chạy `compute_harmonic_spectrum.m` cho toàn bộ 18 bậc trên cùng dữ liệu:

```
Order          1       2       3       6       9      12      18      36
OLD_FW      0.277   0.054   0.018   0.019   0.442   0.096   0.036   0.894
FIXED_FW    0.120   0.035   0.007   0.009   0.204   0.069   0.036   0.310
Giảm       -57%    -34%    -60%    -55%    -54%    -28%     0%    -65%
```

**H1 giảm 57%, H2 giảm 34%** — cùng jig, cùng sensor, không tháo gá, chỉ đổi firmware. Theo khung phân loại harmonic "geometric" (H1,H2,H4,H8 — do lệch tâm/nghiêng gá quyết định) vs "motor" (H36... — do rotor quyết định) đã lập trong tài liệu creep mục 5, H1/H2 lẽ ra phải **độc lập với firmware**. Số liệu này cho thấy không phải vậy.

**Hệ quả**: mọi số H1/H2 đã đo trong dự án (kể cả các phân tích jig1-vs-jig4 ở phiên trước, kể cả đề xuất gate `MountValid` theo H1/H2 ở tài liệu creep mục 5.2) đều là hỗn hợp (lệch tâm/nghiêng thật) + (artifact creep chưa fix hết), chưa tách bạch được tỷ trọng mỗi phần.

## 3. Phát hiện mới #2: offset góc tuyệt đối biến mất, chưa từng được ghi trong tài liệu creep

```
MeanDC_Deg:  OLD_FW ≈ +0.28° đến +0.34°   →   FIXED_FW ≈ -0.01° đến -0.04°
```

Một lệch hằng số ~0.3° (không phải nhiễu biên độ mà lệch tâm-0 thật) tồn tại xuyên suốt firmware cũ, biến mất sau khi fix creep.

## 4. Review file mô phỏng `tools/m_ph_ng_test_non_linear_ng_c_bldc_sau_d_n_nam_ch_m.html` — phát hiện lỗi mô hình hiệu chuẩn LUT 32 điểm

Mô phỏng hiệu chuẩn bằng bảng 32 điểm (`NUM_LUT_POINTS=32`), nội suy tuyến tính giữa các mốc, tuyên bố (footer) sửa được mọi trường hợp xuống <0.08°. Kiểm chứng lại đúng công thức đó bằng MATLAB cho từng bậc `statorSlots`:

```
statorSlots   chu kỳ/đoạn LUT   sai số CÒN LẠI sau "hiệu chuẩn" (so với sai số gốc)
    6              0.19             16.5%
   12              0.38             57.4%
   18              0.56            117.6%  <- TỆ HƠN trước khi hiệu chuẩn
   24              0.75            135.6%  <- TỆ HƠN
   36 (*)          1.13            187.0%  <- TỆ HƠN
```
*(*) bậc 36 không có trong dropdown UI, tự thêm để đối chiếu — chính là hài chủ đạo thật của motor trong toàn dự án.*

**Kết nối với phần cứng thật**: `NUM_LUT_POINTS=32` trong mô phỏng khớp đúng số điểm hiệu chuẩn thật trên chip MA600 (`CORR0-31`, luôn `CorrNonZeroCount=0` trong mọi log dự án — chưa từng nạp). Về mặt toán học, **bảng 32 điểm không bao giờ có thể sửa đúng bậc 36** dù có nạp — chỉ có cơ hội sửa đúng các hài bậc thấp (H1, H2). Điều này **củng cố** hướng dùng H1/H2 làm gate `MountValid` (mục 5.2 tài liệu creep) — nhưng phải làm SAU khi H1/H2 đã "sạch" theo mục 2 ở trên.

## 5. Xác nhận lại: code hiện tại chưa kiểm tra H1/H2 ở bất kỳ đâu

Grep toàn bộ `Core/Src/nonlinear_test.c`: `harmonics[0]`/`harmonics[1]` (H1/H2) chỉ xuất hiện ở chỗ tính và log ra `MOUNT_PRECHECK_RESULT` (`:6521-6522`) — không có ngưỡng nào được áp dụng. `MountValid` (`:6357-6359`) chỉ dựa `TrackingValid && ClosureValid && AcquisitionResult==OK`, đúng như đã xác nhận ở phiên trước.

## 6. Đồ thị E(θ) đo thực tế (artifact, không lưu vào repo)

Dựng biểu đồ tương tác so sánh E(θ) thật (OLD_FW vs FIXED_CREEP, 360 điểm) đối chiếu trực quan với mô hình sin đơn giản của file mô phỏng — cho thấy rõ ~36 gợn sóng dày đặc mỗi vòng (không phải 1-2 hài như mô phỏng) và offset dương biến mất sau fix. Chỉ là artifact tham khảo, không phải file trong repo.

## 7. Thay đổi code: thêm đồ thị NL trực tiếp vào `tools/stm32_uart_flasher.py`

Thêm class `LiveNlPlot` (Canvas Tkinter thuần, không thêm dependency matplotlib — giữ nhẹ cho build PyInstaller `STM32_UART_Flasher.spec`) và 1 tab mới **"Đồ thị NL — ErrorDeg(θ)"** cạnh tab log cũ:

- Bắt từng dòng `DATA,...` real-time từ UART app (buffer dòng riêng `self._plot_pending`, tách khỏi `BatchLogRecorder`), parse positional field (index 7=Index, index 11=ErrorDeg theo đúng convention `parse_nl_log.m` đã dùng).
- Tự xoá vẽ lại khi gặp `Index=0` (sweep mới), chấm cam đánh dấu điểm mới nhất, trục Y cố định ±3.0° để không giật khi auto-scale.
- Đã test: dựng GUI headless (`FlasherApp()` không mainloop) thành công; feed 2 dòng `DATA,` thật qua `log_serial_data()` → xác nhận `reset()` gọi đúng lúc `Index=0`, giá trị điểm parse chính xác (`-0.00797`, `0.46857`).
- **Chưa test trên phần cứng thật** — chỉ mới test với dữ liệu giả lập qua hàm gọi trực tiếp, chưa chạy full flow UART thật.

## 8. Việc chưa hoàn thành / đề xuất cho phiên sau

1. **Ưu tiên cao**: sau khi vấn đề nhiệt/giật của `ENABLE_SWEEP_POINT_CREEP` được giải quyết (mục 6.5 tài liệu creep), đo lại H1/H2/H36 "sạch" — hiện mọi số H1/H2/H36 trong dự án đều còn lẫn artifact chưa fix hết.
2. Verify lại bậc 36 (và giờ cả H1/H2) có còn ổn định qua các board/sensor khác nhau sau khi creep đã fix triệt để hay không (mục 7 tài liệu creep, mở rộng thêm phạm vi H1/H2).
3. Khi thiết kế gate `MountValid` theo H1/H2 (mục 5.2 tài liệu creep): chỉ nên tính ngưỡng trên dữ liệu đã xác nhận sạch theo mục 1 ở trên; đồng thời chỉ nên kỳ vọng bảng hiệu chuẩn 32 điểm (nếu dùng) sửa được H1/H2, không kỳ vọng sửa được NL tổng/H36 (mục 4).
4. Test `LiveNlPlot` trên phần cứng thật (UART thật, không chỉ gọi hàm giả lập) — xác nhận hiệu năng vẽ real-time không làm chậm việc đọc UART, và trục Y ±3.0° đủ dùng cho mọi sản phẩm đã biết.
