# Codex handoff — Motion Control V2, lưới 1° và SPI1 DMA

Tài liệu này là điểm bắt đầu cho Codex hoặc kỹ sư khi clone project sang máy
khác. Đọc file này trước khi sửa motion, PID, SPI acquisition hoặc thuật toán
NL.

## 1. Trạng thái bàn giao

- Branch: `codex/motion-control-v2-dma`
- MCU: STM32F405RGTx
- Ngày bàn giao: 2026-07-16
- Trạng thái phần mềm: Debug/Release build thành công, 12/12 host contract test
  PASS, không có compiler warning.
- Trạng thái phần cứng: chưa qualification Motion V2 trên jig sau thay đổi cuối.
- Không được kết luận độ chính xác hoặc độ mượt đã đạt chỉ từ host test.

Mục tiêu của branch là thử quỹ đạo motor mượt và lặp lại hơn, chuyển transaction
đọc góc MA600A sang SPI1 DMA, đồng thời giữ nguyên ý nghĩa phép đo NL.

## 2. Measurement contract đang có hiệu lực

Các bất biến sau không được thay đổi trong quá trình tuning motion:

| Thành phần | Giá trị hiện tại |
| --- | --- |
| Sweep vật lý | 0..370°, tổng cộng 371 point |
| Vùng phân tích NL | point 0..359, tổng cộng 360 point |
| Closure | point 360 so với point 0 |
| Margin sau closure | point 361..370 |
| Grid | 1°/point |
| Target raw | `round(index * 65536 / 360)`, xen kẽ 182/183 raw |
| Samples | 64 accepted samples/point |
| Số accepted samples/run | 371 × 64 = 23.744 |
| Capture cuối mỗi point | open-loop, sau settle |
| Batch official | 1 precondition + 10 official runs, cooldown 120 s |

Điểm cuối không được PID hiệu chỉnh trong lúc lấy 64 mẫu. Nếu đóng position loop
tại official capture, firmware có thể tự triệt nonlinear error của motor và làm
sai mục đích phép đo.

## 3. Những thay đổi đã triển khai

### 3.1 Lưới đo 1°

- `NL_POINTS_PER_REV=360` và `NL_GRID_STEP_DEG=1.0f`.
- Target không cộng dồn 182 raw. Mỗi target được tính tuyệt đối và làm tròn từ
  index, bảo đảm point 360 bằng đúng 65536 raw.
- Analysis chỉ dùng một chu kỳ 0..359; 360 là closure, 361..370 là margin.
- Canonical error có API nhận exact signed target để không giả định step raw cố
  định.

### 3.2 SPI1 DMA cho MA600A

- Mặc định `MA600_USE_SPI_DMA=1`.
- Transport ID trong startup log: `SPI_DMA_BLOCKING_WRAPPER_V1`.
- SPI1 RX dùng DMA2 Stream2 Channel3; TX dùng DMA2 Stream3 Channel3.
- DMA buffer là static `.bss` SRAM vì DMA2 không truy cập CCM.
- Callback hoàn tất/error hạ `/CS`, ghi cycle hoàn tất và cập nhật state.
- Có timeout DWT 10 ms và abort/error path.
- Polling transport cũ vẫn nằm trong cùng source và có thể rollback bằng
  `MA600_USE_SPI_DMA=0`.

Lưu ý: đây là DMA transport nhưng caller vẫn bounded busy-wait tới khi frame 2
byte hoàn tất. Thiết kế này giữ timing của cửa sổ 64 mẫu gần baseline hơn; chưa
phải API DMA bất đồng bộ hoặc task notification.

### 3.3 Motion profile cho sweep

Profile mặc định: `SCURVE40_ABSOLUTE_TICK_V2`.

- Mỗi đoạn 1° có 40 command slot, cadence 1 ms.
- Dùng quintic smoothstep `10u^3 - 15u^4 + 6u^5`.
- `osDelayUntil` dùng deadline tuyệt đối để thời gian SPI không cộng dồn vào
  cadence của đoạn kế tiếp.
- Command cuối luôn clamp về exact target 182/183 raw.
- Power vẫn bằng 1.0 để không đổi đồng thời motion và drive power.
- Encoder được đọc sau từng command để ghi nhận backtrack và acquisition fault.
- Legacy profile `STAIRCASE8_RELATIVE_TICK_V1` còn tồn tại; chọn
  `NL_MOTION_PROFILE=1` để A/B hoặc rollback.

### 3.4 Điểm 0 và hướng tiếp cận

Profile: `SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`.

- Dither đổi hướng liên tục cũ bị bypass trong Motion V2.
- Electrical phase hiện tại đi tới phase-zero tương đương gần nhất bằng một
  S-curve.
- Point 0 dùng backoff 1° rồi tiến CW bằng cùng S-curve như closure point 360.
- Mục tiêu là loại khác biệt lịch sử hướng tải giữa point 0 và point 360; đây
  chưa phải bằng chứng closure đã đạt 0.2°.

### 3.5 Home controller

Profile: `WRAPPED_PID_SLEW_V2`.

- Angle error được wrap về `[-180°, 180°]`. Ví dụ 352° tới 0° trở thành -8°,
  không còn chạy gần một vòng không cần thiết.
- Giữ gain đầu tiên: `Kp=2`, `Ki=0.003`, `Kd=0.3` và loop 2 ms.
- Integral được clamp ở ±5 thay vì vượt giới hạn rồi reset về zero.
- Derivative dùng one-pole filter với `alpha=0.25`.
- Incremental controller output thay đổi tối đa 8 raw/update.
- Filter state và last output được reset/audit trước mỗi home.
- Firmware self-test kiểm tra P, saturation, integral clamp, derivative filter,
  output slew và reset persistent state.

### 3.6 Logging và observability

Mỗi sweep phát record `MOTION_PROFILE` sau khi motor đã tắt, gồm:

- motion/home profile ID;
- cadence và commands/degree;
- lock duration, command count và timing overrun;
- ramp segments/commands, max lateness;
- encoder backtrack count và backtrack raw lớn nhất.

`CONTROL_STATE` có thêm filtered derivative và last output step. Ba ramp đầu và
hai equal-approach leg có trace encoder per command. `GRID` chuyển sang buffer
log lớn để tránh nối/truncate record. Stack `TestTask` tăng lên 8192 byte; Debug
`-fstack-usage` đo chuỗi `PrintSweepLog -> LogLineLarge` khoảng 6472 byte.

## 4. File quan trọng

| File | Vai trò |
| --- | --- |
| `Core/Src/nonlinear_test.c` | Grid, motion profiles, settle, capture, analysis, telemetry và batch |
| `Core/Src/motor.c` | Home feedback, wrapped error và motor facade |
| `Core/Src/position_controller.c` | PID state, clamp/filter/slew và self-test |
| `Core/Src/ma600.c` | SPI polling/DMA transport, `/CS`, callback và raw frame |
| `Core/Src/ma600_acquisition.c` | Retry, unwrap, sampler và canonical target math |
| `Core/Src/stm32f4xx_hal_msp.c` | SPI1 DMA mapping/NVIC |
| `Core/Src/stm32f4xx_it.c` | DMA2 Stream2/3 và SPI1 IRQ handler |
| `jigmotor.ioc` | CubeMX source of truth cho SPI DMA |
| `scripts/test_motion_control_v2_contract.ps1` | Contract riêng của Motion V2 |
| `scripts/test_spi1_dma_contract.ps1` | Contract DMA source/CubeMX |
| `scripts/test_one_degree_grid_contract.ps1` | Contract grid 1° và exact target |
| `docs/motion-control-v2-implementation-plan.md` | Qualification/acceptance plan chi tiết |

`docs/system-design-v2-algorithm-preserving.md` và
`docs/spi-acquisition-optimization-plan.md` là tài liệu kiến trúc/plan được viết
trước hoặc trong quá trình thử nghiệm. Nếu nội dung của chúng nói giữ dither cũ,
không tuning PID hoặc chưa bật DMA thì đó là historical constraint, không phải
trạng thái runtime mới nhất. File handoff này và source code là nguồn sự thật
cho branch hiện tại.

## 5. Build và kiểm thử sau khi clone

```powershell
git fetch origin
git switch codex/motion-control-v2-dma

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_make.ps1 -Configuration Debug
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\build_make.ps1 -Configuration Release

$tests = Get-ChildItem .\scripts -Filter 'test_*contract.ps1'
foreach ($test in $tests) {
  powershell -NoProfile -ExecutionPolicy Bypass -File $test.FullName
  if ($LASTEXITCODE -ne 0) { throw "Contract failed: $($test.Name)" }
}
```

Artifact để flash: `Release/jigmotor.hex`.

Không copy artifact từ máy cũ rồi cho rằng source mới tương đương. Hãy build lại
và lưu commit SHA cùng SHA-256 của file hex trong log test.

## 6. Trình tự qualification trên jig

1. Flash Release và lưu startup line. Phải thấy
   `MA600 angle transport=SPI_DMA_BLOCKING_WRAPPER_V1`.
2. Chạy đúng batch hiện tại: một precondition rồi mười official runs.
3. Xem precondition và run official đầu như motion-safety screen. Dừng nếu motor
   rung, giật, stall, chạy sai hướng hoặc nóng bất thường.
4. Không tháo/lắp motor giữa 10 official runs.
5. Lưu toàn bộ UART log, commit SHA, hex SHA-256, JigID, MotorID và điều kiện gá.
6. Chỉ tuning một tham số trong mỗi firmware và dùng profile ID mới nếu thay đổi
   đường đi hoặc timing.

Acceptance gates ban đầu:

- `MeasurementValid=1`, `TrackingValid=1` cho mọi official run.
- `SpiFailures=0`, `AcqRetries=0`, `JumpRejects=0`, `FailedPoints=0`.
- `RampTimingOverruns=0` và không có CW backtrack lớn hơn 9 raw.
- `Captured=371`, `Analysis=360`, 23.744 canonical accepted samples/run.
- RMS_AC coefficient of variation không xấu hơn baseline 0.236%.
- Mean pointwise repeatability standard deviation không xấu hơn 0.0225°.
- Tracking maximum không xấu hơn vùng baseline khoảng 2.16°.
- Closure mục tiêu 0.2°. Không tuyên bố closure đã sửa nếu vẫn gần 0.69°.
- Báo cáo motor-active duration và xu hướng RMS_AC/A36 để phát hiện ảnh hưởng
  nhiệt do S-curve 40 ms/degree.

## 7. Quy tắc khi tiếp tục phát triển

- Không đổi motion, DMA timing, sample count, settle threshold và power trong
  cùng một firmware thử nghiệm.
- Không thêm motion health diagnostic vào official validity equation nếu chưa
  tạo measurement contract/version mới.
- Không phát UART khi motor đang enable.
- Không dùng PID tại official capture để ép encoder về nominal angle.
- Không đổi thứ tự phép toán NL/RMS/harmonic khi chỉ định tuning motion.
- Không xóa polling/staircase fallback trước khi hoàn tất A/B/A phần cứng.
- Khi regenerate từ CubeMX, kiểm tra lại DMA2 Stream2/3, SPI1 IRQ và USER CODE;
  sau đó chạy đủ 12 contract test.
- Log test, `.vscode`, build output và dữ liệu gá cá nhân không thuộc source
  commit trừ khi có yêu cầu riêng.

## 8. Việc chưa hoàn thành

- Flash và qualification Motion V2 trên phần cứng.
- So sánh A/B/A với baseline staircase/polling trên cùng motor, cùng jig.
- Xác nhận cadence 1 ms không overrun khi DMA, settle và IRQ chạy đồng thời.
- Đánh giá motor nhiệt do thời gian active tăng.
- Quyết định giữ 40 ms/degree hay thử 32 ms/degree sau khi có trace thực tế.
- Tách `nonlinear_test.c` theo kiến trúc modular chỉ sau khi numeric equivalence
  đã được đóng băng; không trộn refactor đó vào tuning hiện tại.

Khi nhận log mới, ưu tiên kiểm tra transport/profile ID và validity trước khi
phân tích RMS_AC hoặc NL. Một log thiếu đúng identity không được trộn vào dataset
của branch này.

## 9. Kiến trúc tiếp theo đã thống nhất

Motor control và official measurement sẽ được tách thành hai firmware image,
không chuyển mode trong cùng boot và không chia sẻ controller/acquisition state.
Thiết kế tài nguyên STM32F405 và plan triển khai nằm tại:

- `docs/stm32f405-dual-mode-system-design.md`
- `docs/stm32f405-dual-mode-implementation-plan.md`

P0 và P1 đã được triển khai ở mức source/build gate:

- `JIG_APP_MODE` chọn đúng một policy tại compile time;
- `scripts/build_dual_image.ps1` tạo hai ELF/HEX độc lập trong `Build/`;
- mỗi firmware log mode, profile, source ID và profile fingerprint;
- Control ELF không link nonlinear engine/buffer;
- Measurement vẫn giữ Motion V2 + SPI DMA và measurement math hiện tại.

Hardware C0 cho thấy workflow cũ fail trước trajectory: 5/10
`HOME_WRONG_WAY`, 5/10 `HOME_TIMEOUT`, mọi run `EvidenceCount=0`. Control image
hiện đã chuyển sang profile `CONTROL_A2_FIXED_PHASE_ALIGN_P10_V1` để cô lập
trình tự enable/alignment: prime phase 0 tại power 0, enable tại power 0, ramp
0->10% trong 500 ms, hold 100 ms, motor off rồi mới dump UART. Profile này
không chạy HOME, PID hoặc trajectory 1°. Hardware gate A2 chưa chạy; dùng
`docs/control-a2-alignment-hardware-test.md` và không mở A3/A4 trước khi review
log P10.
