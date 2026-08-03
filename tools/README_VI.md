# STM32 UART Flasher

Ứng dụng Python có giao diện để flash STM32 bằng **bootloader UART có sẵn trong ROM**, không cần ST-Link. Sau khi firmware chạy, cùng ứng dụng có thể đọc UART APP, tự lưu log và tự phân tích kết quả nonlinear test.

## Chức năng

- Kết nối bootloader bằng byte đồng bộ `0x7F`.
- Đọc phiên bản bootloader, danh sách lệnh và Chip ID.
- Mass erase Flash.
- Ghi tối đa 256 byte mỗi frame, căn chỉnh 4 byte.
- Verify bằng cách đọc lại Flash.
- Hỗ trợ `.bin`, `.hex`, `.ihex`, `.elf`, `.axf`.
- Có tùy chọn gửi lệnh `Go` sau khi flash.
- Theo dõi UART APP `8N1` ở baud cấu hình được (mặc định `921600`).
- Tự phát hiện ranh giới một test bằng `BATCH,Status=START` và `BATCH,Status=COMPLETE/FAILED`.
- Tự lưu log nguyên bản, không cần copy/paste từ cửa sổ monitor.
- Hỏi tên file sau mỗi batch; Cancel vẫn lưu an toàn bằng tên tự động.
- Tự chạy `analyze_motor_logs.py`, tái tính kết quả từ các dòng `DATA` và xuất TXT/CSV/JSON.
- Lưu log với trạng thái `incomplete` nếu monitor bị đóng khi batch chưa hoàn tất.

## Kết nối STM32F405

| USB-UART | STM32F405 |
|---|---|
| TX | PC11 / USART3_RX |
| RX | PC10 / USART3_TX |
| GND | GND |

USB-UART phải dùng mức logic 3.3 V. Nếu bo STM32 đã có nguồn riêng thì không nối thêm chân nguồn từ USB-UART.

Trước khi kết nối:

1. `BOOT0 = 1`.
2. `BOOT1 = 0`.
3. Reset hoặc cấp nguồn lại STM32.
4. Mở ứng dụng và nhấn **Kết nối**.

Sau khi flash:

1. Đưa `BOOT0 = 0`.
2. Reset STM32.

## Cài đặt và chạy

Yêu cầu Python 3.10 trở lên.

```bash
python -m pip install -r requirements.txt
python stm32_uart_flasher.py
```

## Tự lưu và phân tích log

Trong giao diện:

1. Chọn **Mở UART APP** hoặc bật **Mở monitor sau GO**.
2. Giữ chọn **Tự lưu log khi test xong**.
3. Giữ chọn **Tự phân tích** nếu muốn nhận kết quả ngay sau test.
4. Giữ chọn **Hỏi tên file trước khi lưu**. Có thể bỏ chọn để chạy nhiều motor hoàn toàn tự động.
5. Chọn **Thư mục log**. Mặc định khi chạy source là `captured-logs` ở thư mục gốc project; khi chạy EXE là `captured-logs` cạnh file EXE.
6. Chạy test trên jig như bình thường. Không đóng monitor trong lúc batch đang chạy.

Khi firmware phát:

```text
BATCH,...,Status=START,...
...
BATCH,...,Status=COMPLETE,...
```

ứng dụng tự tạo bốn file có cùng timestamp, motor, jig và BatchID:

```text
20260803-101500_p03_JIG1_batch001_complete.txt
20260803-101500_p03_JIG1_batch001_complete.metrics.csv
20260803-101500_p03_JIG1_batch001_complete.analysis.json
20260803-101500_p03_JIG1_batch001_complete.analysis.txt
```

Khi batch kết thúc, hộp thoại sẽ đưa sẵn tên trên để sửa. Nếu nhập `P05-JIG1-lan-01`, bộ file kết quả sẽ là `P05-JIG1-lan-01.txt`, `P05-JIG1-lan-01.metrics.csv`, `P05-JIG1-lan-01.analysis.json` và `P05-JIG1-lan-01.analysis.txt`. Tên trùng không bị ghi đè; app tự thêm `_02`, `_03`, ...

Trong cửa sổ ứng dụng sẽ có dòng tóm tắt tương tự:

```text
AUTO ANALYSIS: PASS | p03/JIG1 | OFFICIAL 3/3 | NL=2.5827 deg | SD=0.0204 deg | RMS_AC=0.6891 deg | ClosureMax=0.0406 deg
```

Analyzer không tin trực tiếp dòng `RESULT`; nó tái tính từ `DATA`. Một batch chỉ PASS khi:

- `BATCH Status=COMPLETE`;
- đủ số OFFICIAL được khai báo trong `BATCH.RunCount`;
- từng OFFICIAL có `META`, `END Status=VALID`, `MeasurementValid=1`, `RunRole=OFFICIAL` và `EligibleForStatistics=1`;
- không có CONFIG gate thất bại tại `PRECONDITION_PRE_MOTOR` hoặc `BATCH_PRE_MOTOR`.

`BOOT_SMOKE` không hợp lệ được ghi thành cảnh báo, không tự làm batch FAIL vì đây là lần đọc sớm không điều khiển motor. Nếu monitor bị dừng, mất COM hoặc ứng dụng đóng giữa test, phần dữ liệu đã nhận được vẫn được lưu với trạng thái `incomplete` để điều tra nhưng kết quả phân tích là FAIL.

## File firmware

### BIN

Ứng dụng sử dụng địa chỉ nhập trong ô **Địa chỉ BIN**. Giá trị mặc định:

```text
0x08000000
```

### HEX

Địa chỉ được lấy trực tiếp từ Intel HEX.

### ELF/AXF

Ứng dụng lấy các `PT_LOAD` segment nằm trong vùng Flash bắt đầu tại `0x08000000`.

## Tạo file BIN và HEX trong STM32CubeIDE

```text
Project Properties
→ C/C++ Build
→ Settings
→ MCU Post build outputs
→ Convert to binary file
→ Convert to Intel Hex file
```

## Tạo file EXE Windows

PyInstaller chỉ cần khi đóng gói, không phải dependency lúc chạy source. Cài và build bằng:

```powershell
python -m pip install pyinstaller
python -m PyInstaller --noconfirm --clean STM32_UART_Flasher.spec
```

File EXE được tạo tại:

```text
dist\STM32_UART_Flasher.exe
```

## Lưu ý an toàn

- Ứng dụng thực hiện **mass erase toàn bộ Flash** trước khi ghi.
- Không dùng với firmware cần giữ lại bootloader hoặc dữ liệu riêng trong một vùng Flash khác, trừ khi đã sửa quy trình erase.
- Readout Protection hoặc Write Protection có thể làm lệnh đọc, ghi hoặc xóa bị NACK.
- Không ngắt nguồn khi đang erase hoặc write.
