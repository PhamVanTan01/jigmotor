# V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm

Ngày: 2026-08-10  
Trạng thái: thiết kế đã khóa để triển khai firmware/tool

## 1. Mục tiêu

V5.8 trả lời riêng cho từng point 1..371:

1. ramp phát chuỗi command mất bao lâu;
2. rotor mất bao lâu để ổn định lần đầu sau ramp;
3. creep feedback mất bao lâu để đạt deadband, hoặc mất bao lâu trước khi dừng vì hard cap/lỗi;
4. cửa sổ đo legacy 64 mẫu và cửa sổ shadow 64 mẫu mất bao lâu;
5. tổng thời gian từ command đầu tiên của point tới khi data của point được đóng băng;
6. hiệu quả chuyển động: command raw, dịch chuyển thực theo hướng target, tỷ lệ response/command và response theo thời gian.

Không diễn giải `N điểm đạt / 360 điểm` từ một tỷ lệ response trung bình. Một point có thể đạt deadband dù response/command dưới 100%, vì controller phát nhiều correction command. Verdict phải tách:

- `REACHED_DEADBAND`: có thời gian đáp ứng hợp lệ;
- `STOPPED_OUTSIDE_DEADBAND`: không tồn tại time-to-target; chỉ có stop latency;
- `ACQUISITION_ERROR`: dữ liệu timing không đủ điều kiện kết luận.

## 2. Profile được giữ nguyên

V5.8 là telemetry-only trên motion V5.5 đã đóng băng:

- COARSE = 16 raw;
- FINE = 4 raw khi live gap <= 64 raw;
- BASE primary budget = 220 raw, hard cap = 320 raw;
- EXTENDED hard cap = 320 raw;
- power = 1.0;
- deadband = +/-16 raw;
- ramp quintic 40 tick, delay 1 ms/tick;
- `WaitForPointSettle()` giữ nguyên: poll 1 ms, 8 mẫu ổn định liên tiếp, timeout 100 ms;
- 64 mẫu legacy và 64 mẫu shadow không đổi;
- không bật V5.6 MID, không bật V5.7 passive hold;
- không log UART khi motor đang chạy.

Build V5.8 phải bị loại khỏi thống kê official (`EligibleForStatistics=0`) cho tới khi A/B xác nhận các lần đọc DWT không làm thay đổi cadence/measurement.

## 3. Clock và phép đo

Nguồn thời gian là `DWT->CYCCNT`, đã được `MA600_DwtInit()` bật trước test. Firmware lưu **duration cycles** bằng phép trừ `uint32_t`, wrap-safe khi mỗi phase ngắn hơn một vòng DWT (~25.6 s ở 168 MHz).

Độ phân giải timestamp là 1 CPU cycle, nhưng độ phân giải phát hiện rotor vào deadband bị giới hạn bởi cadence đọc encoder/settle hiện tại (xấp xỉ 1 ms), không được quảng bá là phản ứng cơ khí cấp nano/microsecond.

## 4. Ranh giới phase

Cho point `i > 0`:

- `RampCycles`: ngay trước `RampCommandToTarget()` đến lúc hàm trả về;
- `InitialSettleCycles`: ngay trước tới ngay sau `WaitForPointSettle()` đầu tiên;
- `CreepCycles`: ngay trước tới ngay sau `CreepToUnwrappedTargetProfiled()`;
- `CommandToStopCycles`: từ trước ramp đến khi creep dừng;
- `TimeToDeadbandCycles`: bằng `CommandToStopCycles` chỉ khi creep kết thúc `OK/OK_RECOVERED`; ngược lại là `NA`;
- `LegacyCaptureCycles`: 64 mẫu average + raw anchor dùng cho DATA;
- `ShadowCaptureCycles`: cửa sổ canonical shadow của point;
- `CommandToDataFrozenCycles`: từ trước ramp đến sau raw anchor legacy;
- `CommandToAllCaptureDoneCycles`: từ trước ramp đến sau shadow window.

Point 0 không có ramp từ point trước, nên phát `HasCommand=0`; timing capture vẫn có, các trường command-response là `NA`.

## 5. Telemetry contract

Một record cho mọi point đã capture:

```text
SWEEP_POINT_TIMING,SchemaVersion=1,TestID=...,SweepID=...,JigID=...,MotorID=...,
Direction=CW,Point=...,Official=0,ClockHz=168000000,HasCommand=1,TimingValid=1,
RampCycles=...,InitialSettleCycles=...,CreepCycles=...,
CommandToStopCycles=...,ReachedDeadband=1,TimeToDeadbandCycles=...,
LegacyCaptureCycles=...,ShadowCaptureCycles=...,
CommandToDataFrozenCycles=...,CommandToAllCaptureDoneCycles=...,
CreepResult=OK
```

Quy ước `NA`:

- `TimeToDeadbandCycles=NA` nếu result không phải `OK/OK_RECOVERED`;
- phase không chạy do feature/path không có: `NA`, không được ghi 0 như một thời gian thật;
- `TimingValid=0` nếu point chưa đóng băng đầy đủ hoặc clock bằng 0.

Firmware ghi duration vào CCM khi motor đang chạy và chỉ format/phát UART sau `Motor_Disable()`.

## 6. Tool và đại lượng tổng hợp

`SWEEP_POINT_TIMING` mang sẵn target/step, gap trước-sau, correction command, iteration và settle poll; tool không phụ thuộc việc `SWEEP_CREEP_POINT` có được emit cho BASE-OK hay không. Tool xuất:

- mean/median/P90/P95/P99/max của `CommandToStopMs`, `TimeToDeadbandMs`, `CommandToDataFrozenMs`;
- riêng nhóm reached-deadband và failed/hard-cap;
- top point chậm nhất và top point không đạt lặp lại;
- `ObservedTowardTargetRaw = |InitialGapRaw| - |FinalGapRaw|`;
- `ResponseEfficiencyPermille = 1000 * ObservedTowardTargetRaw / TotalCorrectionRaw` khi command correction > 0;
- `ObservedTowardTargetRawPerSecond = ObservedTowardTargetRaw / CreepTime`;
- completeness: số timing row phải bằng số point DATA/captured được khai báo.

Ứng dụng UART tự động thêm summary timing vào `.analysis.txt` và tạo sidecar `.response.csv`. MATLAB parser/batch analyzer dùng cùng field names và cùng công thức.

## 7. Gate hardware đầu tiên

Chạy FAST3 trên P08/JIG8, hai remount như V5.7 để so trực tiếp.

1. transport/acquisition clean;
2. timing completeness = 100%;
3. point 308 phải được phân loại nhất quán: reached hay stopped-outside-deadband;
4. phase sums khớp total theo ranh giới đã định;
5. V5.8 timing row không được dùng để tự retune motion trong chính batch này;
6. so NL/A36/creep outcome với V5.5 matched chỉ để phát hiện instrumentation regression, không promote V5.8 thành production measurement.

## 8. RAM và safety

V5.7 map: `.ccmram_bss = 0x92b0` (37,552 B) trên CCMRAM 65,536 B. Tám mảng `uint32_t[372]` + flags của V5.8 cần khoảng 12 KB, giữ CCM dưới giới hạn với headroom xấp xỉ 16 KB. Build gate phải kiểm lại `.map` và `arm-none-eabi-size`.

Không tăng command, power, budget, timeout, sample count hoặc số phép đọc MA600. Chỉ thêm đọc DWT và lưu RAM O(points).
