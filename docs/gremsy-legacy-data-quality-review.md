# Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)

## Phạm vi

Đánh giá 8 file firmware cũ (`gremsyEncoder.c/.h`, `gremsyMotor.c/.h`,
`gremsyTaskManager.c/.h`, `gremsyAnalog.c/.h`) do người dùng cung cấp trực
tiếp — đây là codebase "chị em" được nhắc tới rải rác trong comment của
`jigmotor` (`docs/end-of-shaft-mounting-test-plan.md`, các comment trong
`nonlinear_test.c`/`ma600.c` cũ), không phải file trong repo `jigmotor`
hiện tại. Mục tiêu: xác định vì sao cách đọc dữ liệu MA600A ở đây **không
đủ tin cậy để đánh giá motor đúng theo tinh thần datasheet MA600A**, đối
chiếu trực tiếp với các mục datasheet liên quan (Table 1 FW/bandwidth, SPI
Read Multi-Turn or Speed, Register Map, STATUS register).

## Tóm tắt

Bốn nhóm nguyên nhân chính, xếp theo mức độ ảnh hưởng đến độ chính xác số
liệu:

1. Cấu hình sensor (`FW=12`) triệt tiêu gần hết bandwidth cần để theo dõi
   một shaft đang quay — mâu thuẫn trực tiếp với mục đích "đo nonlinearity
   động".
2. Đọc "speed" bằng một giao dịch SPI sai kích thước — dữ liệu speed trả ra
   là rác, không phải theo đúng "SPI Read Multi-Turn or Speed" của
   datasheet.
3. Không có bất kỳ lớp kiểm tra nào (không check `HAL_SPI_*` return status,
   không đọc STATUS register, không xác nhận ghi register thành công,
   không biết CORR lookup table đang ở trạng thái nào) — mọi lỗi truyền dữ
   liệu hay cấu hình sai đều im lặng.
4. Phương pháp lấy mẫu cho bài test nonlinear (delay cố định thay vì chờ
   settle, nhảy một bước lớn thay vì ramp, lọc IIR chồng lên bộ lọc cứng
   của sensor, chỉ tính min/max thô) tạo ra số liệu bị trễ pha, bị nhiễu hệ
   thống, và không có audit trail để kiểm tra lại.

## 1. Cấu hình `FW=12` triệt tiêu bandwidth — sai mục đích ngay từ thiết kế

`gremsyEncoder.c`, `encoderSPIInit()`:

```c
encoderSpiWriteReg(13, 12); /// 15 bit
//	encoderSpiWriteReg(13, 0); /// 12.3 bit
//	encoderSpiWriteReg(13, 8); /// 14 bit
//	encoderSpiWriteReg(13, 7); /// 13.5 bit
```

Địa chỉ `13 = 0x0D` đúng là `FILT` register (FW bits) theo Register
Description của MA600A. Theo Table 1 của datasheet (Configurable Filter
Window để đánh đổi Resolution vs. Bandwidth):

| FW | Resolution (bit) | Bandwidth (kHz) |
| --- | --- | --- |
| 0 | 12.3 | 17 |
| 5 (default) | 12.5 | 12 |
| 8 | 14 | 1.3 |
| 12 | **15** | **0.075** |

Chọn `FW=12` để lấy 15-bit resolution đồng nghĩa chấp nhận bandwidth chỉ
**0.075 kHz** — tương đương hằng số thời gian đáp ứng cỡ hàng chục
milli-giây. Với một bài test "nonlinearity" đòi hỏi đo góc thực của shaft
**đang quay** ở từng vị trí lệnh, một cảm biến có bandwidth 0.075kHz sẽ trả
về góc bị trễ pha đáng kể so với vị trí cơ khí thật tại thời điểm đọc — độ
trễ này tự nó tạo ra một "sai lệch góc" giả, không phân biệt được với
nonlinearity thật của motor/nam châm. Đây không phải lỗi code kiểu
điền-sai-giá-trị, mà là một lựa chọn cấu hình mâu thuẫn trực tiếp với mục
đích sử dụng: muốn đo động (dynamic sweep) thì cần bandwidth cao (FW thấp,
ví dụ FW=0 hoặc FW=5 default), không phải FW=12.

## 2. Đọc "speed" bằng giao dịch SPI sai kích thước — dữ liệu là rác

`gremsyEncoder.c`, `encoderSPIProcess()`:

```c
encoderSpiSelect();
gremsyEncoderSPIPrivate.spiBufferTx[0] = 0x00;
gremsyEncoderSPIPrivate.spiBufferTx[1] = 0x00;
gremsyEncoderSPIPrivate.spiBufferTx[2] = 0x00;
gremsyEncoderSPIPrivate.spiBufferTx[3] = 0x00;

/// Only get angle
HAL_SPI_TransmitReceive(&hspi1, gremsyEncoderSPIPrivate.spiBufferTx, gremsyEncoderSPIPrivate.spiBufferRx, 2, 10);
encoderSpiUnselect();

gremsyEncoderSPIPrivate.encoderRaw = ((uint16_t)spiBufferRx[0] << 8) + (uint16_t)spiBufferRx[1];
gremsyEncoderSPIPrivate.encoderSpeedTMP = ((uint16_t)spiBufferRx[2] << 8) + (uint16_t)spiBufferRx[3];
```

Tham số độ dài truyền vào `HAL_SPI_TransmitReceive` là **`2`** (2 byte = 1
frame 16-bit) — đúng như comment tự ghi "Only get angle". Nhưng ngay dòng
sau, code vẫn đọc `spiBufferRx[2]`/`[3]` để tính `encoderSpeedTMP` — hai
byte này **không được HAL_SPI ghi trong giao dịch này** (length=2 chỉ động
tới `rx[0]`/`rx[1]`), nên chúng giữ nguyên giá trị từ lần gọi trước (hoặc
rác chưa khởi tạo). Theo đúng datasheet, mục "SPI Read Multi-Turn or Speed"
yêu cầu gửi **32 xung clock trong một frame duy nhất** (4 byte tx/rx, với
bit `MTSP` trong PRT register — ở đây được set qua `encoderSpiWriteReg(28,
0x80)`, đúng địa chỉ `28=0x1C=PRT`, đúng bit 0x80=MTSP — phần cấu hình này
làm đúng) để nhận về cả angle (16-bit đầu) và speed (16-bit sau) **trong
cùng một giao dịch**. Code này chỉ clock 16-bit rồi lấy luôn hai byte không
thuộc giao dịch đó làm "speed". Kết quả: `gremsyEncoderGetSpeed()` (được
lọc thêm bằng IIR `speed = speed*0.95 + speedTMP*0.05`) trả về một số làm
mượt từ **dữ liệu không có nguồn gốc thật**, không phải speed đọc đúng
protocol — trông có vẻ hợp lý (nhờ bộ lọc mượt) nhưng không đo được gì cả.

## 3. Không có lớp kiểm tra nào — mọi lỗi truyền/ghi dữ liệu đều im lặng

- `encoderSPIProcess()`/`encoderSpiReadReg()`/`encoderSpiWriteReg()`: không
  hàm nào kiểm tra giá trị trả về của `HAL_SPI_Transmit`/`Receive`/
  `TransmitReceive` — một timeout hay lỗi SPI vẫn cho ra `HAL_OK`-hay-không
  không được biết tới, dữ liệu cũ trong buffer vẫn bị dùng như thể mới.
- **Không có bước ghi-rồi-đọc-lại để xác nhận** sau mỗi lần
  `encoderSpiWriteReg()` trong `encoderSPIInit()` — nếu một trong các lệnh
  cấu hình (DIR, FW, IF, PWM, hay 32 lệnh reset CORR table) bị SPI lỗi giữa
  đường, sensor có thể chạy với cấu hình khác hoàn toàn so với ý định (ví
  dụ FW giữ nguyên giá trị mặc định thay vì 12, hoặc CORR table vẫn giữ giá
  trị cũ khác 0) mà không ai biết.
- **Không đọc STATUS register (địa chỉ `0x1A`)** ở đâu trong toàn bộ 4
  file — không có cách nào phát hiện `ERRCRC`/`ERRMEM`/`ERRPAR`/`NVMB` theo
  đúng cơ chế datasheet mô tả. Một lỗi parity hay NVM-restore-CRC-mismatch
  sẽ không bao giờ được biết tới trong suốt quá trình test.
- **Trạng thái LUT hiệu chỉnh (CORR0-31) không được audit lúc runtime**:
  `encoderSPIInit()` có hai nhánh `#if(1)/#else` — nhánh đang bật (`1`) reset
  CORR về 0 (khớp "Policy A" không dùng LUT), nhánh còn lại nạp
  `MA600_OFFSET_TABLE` (một bảng LUT theo từng unit) — quyết định này nằm
  hoàn toàn ở compile-time, **không có dòng log nào ghi lại sensor thực tế
  đang chạy với CORR nào** sau khi nạp. Với một log QC đã lưu (chỉ có
  `Nonlinear Max/Min/Angle`), không có cách nào xác nhận lại sau này liệu
  đơn vị đó được đo với LUT bật hay tắt.

## 4. Phương pháp lấy mẫu cho bài "nonlinear" tự tạo thêm nhiễu/trễ

`gremsyTaskManager.c`, trạng thái `ST_STATE_NON_LINEAR_PROCESS`:

```c
selftest.motorNL_PosAngle = 360.0f*selftest.motorNL_Pos/65535.0f;
selftest.motorNL_EncAngle = selftest.motorNL_EncAngleSum/selftest.motorNL_Count;
selftest.motorNL_ErrorTmp = selftest.motorNL_PosAngle - (selftest.motorNL_EncAngle - selftest.motorNL_EncAngleOffset);
...
selftest.motorNL_Pos += MOTOR_NONLINEAR_POS_INCREASE;
gremsyMotorMovePos((uint16_t)selftest.motorNL_Pos, 1.0f);   // một bước nhảy lớn, không ramp
...
osDelay(MOTOR_NONLINEAR_SLEEP_TIME);                        // delay CỐ ĐỊNH, không chờ settle
```

- **Nhảy một bước lớn (`MOTOR_NONLINEAR_POS_INCREASE`) rồi chỉ chờ một
  khoảng `osDelay` cố định** — không có cơ chế nào xác nhận shaft đã thực
  sự dừng trước khi lấy mẫu điểm kế tiếp. Hai motor/jig có ma sát hay quán
  tính khác nhau sẽ dừng ở hai thời điểm khác nhau sau cùng một lệnh nhảy —
  dùng cùng một `osDelay` cố định cho cả hai sẽ lấy mẫu ở hai trạng thái ổn
  định khác nhau (một đã dừng thật, một còn dao động dư) mà không hề biết.
- **`motorNL_EncAngle` là trung bình của N lần gọi
  `gremsyEncoderReadAngle()`** — nhưng như mục 1-2 đã chỉ ra, giá trị này
  không phải một lần đọc SPI trực tiếp mà là trạng thái đã bị lọc IIR
  (`encoderAngle = 0.4*encoderAngle + 0.6*encoderAngleTMP` trong
  `encoderSPIProcess()`, chạy nền mỗi ~1ms) CHỒNG LÊN bộ lọc cứng `FW=12`
  của chính sensor (mục 1). Hai lớp lọc nối tiếp làm bandwidth hiệu dụng
  thấp hơn nữa so với con số 0.075kHz đã rất thấp của riêng `FW=12` — trung
  bình N mẫu của một tín hiệu đã bị trễ pha nặng không "sửa" được độ trễ,
  chỉ làm mượt nhiễu ngẫu nhiên, còn thành phần lệch có hệ thống (do trễ
  pha) thì vẫn còn nguyên.
- **Điểm tham chiếu ban đầu (`motorNL_EncAngleOffset`) là một lần đọc
  đơn**, không phải trung bình — cùng loại vấn đề "điểm gốc kém tin cậy hơn
  các điểm đo sau" mà `jigmotor` (dự án hiện tại, phiên bản mới hơn) đã chủ
  động sửa bằng cách coi điểm 0 là một "canonical mean" giống mọi điểm khác
  (xem `docs/nonlinear-metric-contract-v1.md`), không phải một mẫu đơn.
- **Chỉ tính min/max thô** (`motorNL_ErrorMax - motorNL_ErrorMin`), không
  mean-removal, không RMS, không harmonic/DFT, không closure check. Một
  điểm nhiễu đơn lẻ (SPI glitch, hay chính artefact từ mục 2/3) đủ để quyết
  định toàn bộ kết quả "Nonlinear Angle" của một unit — đúng loại rủi ro mà
  các phiên bản sau của hệ thống đo (dự án `jigmotor` hiện tại) đã ghi nhận
  và chủ động phòng bằng cách lấy trung bình top/bottom-K điểm
  (`NL_ROBUST_EXTREME_COUNT`) thay vì một cặp max/min đơn.
- **Không có log per-point (`DATA`) nào được lưu** — chỉ ba dòng tổng hợp
  (`Nonlinear Max/Min/Angle`) được in ra. Khi một kết quả bất thường xuất
  hiện, không có dữ liệu thô nào để quay lại kiểm tra nguyên nhân (SPI lỗi
  ở điểm nào? có settle kịp không? góc tuyệt đối tại điểm max/min là gì?) —
  toàn bộ audit trail bị mất ngay khi test kết thúc.
- **Lỗi resistance và lỗi nonlinear bị gộp/đè lên nhau**: ở
  `ST_STATE_RES_CALCULATE`, nếu điện trở lệch chuẩn (không phải lost-phase)
  thì `errorType = E503` nhưng **vẫn tiếp tục chạy** sang
  `ST_STATE_NON_LINEAR_INIT`; nếu bước nonlinear sau đó cũng fail, dòng
  `selftest.errorType = ST_ERROR_TYPE_E505;` **ghi đè thẳng lên E503** mà
  không kiểm tra đã có lỗi trước đó chưa. Nếu một unit thực sự có cả hai
  vấn đề (điện trở lệch VÀ nonlinear vượt ngưỡng), báo cáo lên database chỉ
  còn lại E505 — thông tin lỗi điện trở bị mất, người xem log sau này sẽ
  hiểu sai nguyên nhân thực sự khiến unit đó fail QC.

## Kết luận

Bốn nhóm nguyên nhân trên đều độc lập với nhau và đều đủ để làm số liệu từ
bốn file này không phản ánh đúng góc/động học thật của motor theo tinh
thần datasheet MA600A: (1) cấu hình `FW=12` tự triệt tiêu bandwidth cần cho
đo động; (2) giao dịch đọc speed sai kích thước khiến speed là dữ liệu bịa;
(3) không có lớp kiểm tra SPI/STATUS/config nào nên mọi lỗi truyền dữ liệu
đều vô hình; (4) phương pháp lấy mẫu (delay cố định, nhảy lớn, lọc chồng
lọc, chỉ đo min/max, không log per-point, lỗi bị đè) khiến kết quả cuối
cùng vừa bị trễ pha có hệ thống, vừa dễ bị một điểm nhiễu đơn lẻ chi phối,
vừa không thể kiểm tra lại được sau khi test đã chạy xong.
