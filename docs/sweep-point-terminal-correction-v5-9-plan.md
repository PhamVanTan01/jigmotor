# V5.9 — bounded EXTENDED terminal correction

Ngày lập plan: 2026-08-11  
Trạng thái: **IMPLEMENTED, VALIDATED (2026-08-12), RECLASSIFIED AS `POSITION_RESPONSE_DIAGNOSTIC_V5X`**

> **Reclassification 2026-08-12**: đọc `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md`
> và `AGENTS.md` (RULE 0) trước khi dùng plan này. Toàn bộ cơ chế creep/recovery/terminal correction
> mô tả dưới đây dùng chính MA600 để sửa electrical command trước khi chốt điểm đo — đây là feedback
> actuation thật, KHÔNG phải Open-loop NL tương thích Gremsy (mục tiêu chính thức hiện tại của dự
> án). Plan này và mọi kết quả hardware của nó vẫn có giá trị làm `POSITION_RESPONSE_DIAGNOSTIC_V5X`
> (đo khả năng điều khiển/recovery của motor+jig), nhưng KHÔNG được dùng làm định nghĩa hay bằng
> chứng cho NL chính thức của motor. Không tiếp tục tăng cap/tối ưu creep với mục tiêu "cải thiện
> NL" — measurand đã đổi ngay khi creep tham gia, xem handoff mục 6.

## 1. Quyết định

V5.8-TIME-DIAG đã hoàn thành nhiệm vụ đo response theo từng point nhưng không thay đổi motion V5.5:

- BASE primary budget = 220 raw, hard cap = 320 raw;
- EXTENDED hard cap = 320 raw;
- coarse/fine = 16/4 raw;
- deadband = ±16 raw;
- V5.8 chỉ thêm DWT timestamp và được giữ `EligibleForStatistics=0`.

Bước tiếp theo là V5.9, một thay đổi motion có giới hạn:

```text
EXTENDED point
    chạy nguyên trạng V5.5 tới primary cap 320 raw
    nếu đã vào deadband       -> dừng, V5.9 không tác động
    nếu crossing/jump/error   -> dừng theo guard cũ, V5.9 không override
    nếu còn ngoài deadband    -> mở terminal correction tối đa tới hard cap 400 raw
    vào deadband              -> PASS terminal
    hết 400 raw               -> BUDGET_EXCEEDED như cũ, không thử thêm

BASE point
    giữ nguyên V5.5: primary 220 raw, hard cap 320 raw
    không được dùng terminal cap 400 raw
```

V5.9 không phải tăng budget đồng loạt cho 360 điểm. Phần thêm chỉ chạy sau khi một point ban đầu thuộc
`EXTENDED` đã đi hết đúng hành vi 320 raw của V5.5 và vẫn còn ngoài deadband.

## 2. Phân biệt tên phiên bản

- `V5.8-TIME-DIAG` là phiên bản motion V5.5 + timing telemetry.
- Đề xuất cũ trong session 2026-08-10 từng gọi cap 400 là “V5.8”, nhưng artifact V5.8 thực tế đã được
  dùng cho timing. Từ plan này, cap 400 được khóa tên là **V5.9**.
- `V6.0 motion` chưa được triển khai.
- `SchemaVersion=6` trong tài liệu log là hợp đồng dữ liệu khác, không phải motion V6.0.

## 3. Mục tiêu

V5.9 phải trả lời một câu hỏi duy nhất:

> Với mount hợp lệ, các cân bằng tĩnh còn lại tại cap 320 raw có thể được kéo vào deadband bằng tối đa
> 80 raw command bổ sung hay không?

Mục tiêu kỹ thuật:

1. Giữ nguyên byte-for-byte chuỗi command trước khi V5.5 chạm cap 320 raw.
2. Chỉ cho phép tối đa 80 raw command bổ sung trên một EXTENDED point.
3. Dừng ngay khi vào deadband; không bắt buộc dùng hết 400 raw.
4. Đo riêng trạng thái tại lúc vào terminal phase và hiệu quả của phần command bổ sung.
5. Không dùng point index, góc, MotorID hoặc whitelist để chọn point.
6. Không dùng dữ liệu V5.9 của chính batch đang chạy để thay đổi command trong batch đó.
7. Giữ response timing để đánh giá thời gian/nhiệt trong pilot.

## 4. Non-goals

V5.9 không:

- đổi ramp quintic, power, PWM phase law hoặc số cặp cực;
- thêm MID-8, FOC, PID mới hoặc current loop;
- đổi deadband, settle cadence, số mẫu legacy/shadow hoặc công thức NL;
- sửa lỗi mounting bằng command lớn hơn;
- hardcode point 148/157/158/308 hoặc bất kỳ danh sách góc nào;
- bật global H1/H2 mount gate cho mọi product;
- promote canonical/schema v6 hoặc tạo kết luận product PASS/FAIL;
- tiếp tục tăng cap lên 480/500 nếu 400 raw không đạt.

## 5. Bằng chứng đầu vào từ V5.8

### 5.1. Mount tốt

Ước lượng command cần thiết dùng `FinalGapRaw` và response efficiency đã đo ở V5.8. Đây là dự báo cho
batch độc lập V5.9, không phải tự-calibration trong cùng batch.

| Dataset mount tốt | Số hard-cap fail official | Ước lượng nằm trong cap 400 | Cap ước lượng lớn nhất |
|---|---:|---:|---:|
| P08/JIG8 remount03 | 10 | 10/10 | 380 raw |
| P08/JIG8 remount04 | 9 | 9/9 | 368 raw |
| P03/JIG8 remount01 | 17 | 16/17 | 412 raw |
| P03/JIG8 remount02 | 21 | 21/21 | 372 raw |
| P09/JIG8 remount01..03 | 23 | 23/23 | 376 raw |
| **Tổng** | **80** | **79/80 (98.8%)** | — |

Các point fail trên mount tốt xuất hiện tối đa 8 point/sweep. Thời gian một creep iteration trên 80
failure này:

- mean ≈ 8.13 ms;
- median ≈ 8.06 ms;
- P95 ≈ 8.48 ms.

80 raw bổ sung tương ứng tối đa 20 lệnh fine 4 raw, ước lượng P95 khoảng 170 ms/point.

### 5.2. Mount lệch tâm không được dùng để tune

P08/JIG8 remount02 bị lệch tâm:

- official reached rate = 95.59%;
- 49 hard-cap failure, khoảng 16–17 point/sweep;
- chỉ 37/49 failure được dự báo nằm trong 400 raw;
- cap ước lượng lớn nhất = 472 raw;
- H2 precondition = 0.04840°, trong khi remount03/04 tốt là 0.01394°/0.01386°;
- RobustP2P precondition = 0.53696°, trong khi remount03/04 là 0.24121°/0.24707°.

Kết luận khóa trước: **không dùng V5.9 để bù một mount lệch tâm**. Nếu profile mount không hợp lệ, batch
không có giá trị để tune motion dù terminal correction có làm scalar NL nhỏ hơn.

## 6. Locked invariants

| Đại lượng | Giá trị khóa |
|---|---:|
| Coarse step | 16 raw |
| Fine entry | 64 raw |
| Fine step | 4 raw |
| Deadband | ±16 raw |
| BASE primary / hard cap | 220 / 320 raw |
| EXTENDED primary cap | 320 raw |
| **EXTENDED V5.9 hard cap** | **400 raw** |
| EXTENDED terminal allowance | 80 raw tối đa |
| V5.9 max iterations | 101 |
| Power | 1.0 |
| Jump threshold | 96 raw |
| Recovery allowance | 64 raw / 17 iterations |
| Reversal limit | một lần |
| Settle | poll 1 ms, 8 mẫu ổn định, timeout 100 ms |
| Ramp | quintic 40 tick, 1 ms/tick |
| Capture | legacy 64 + shadow 64, không đổi |

Ngoài ra giữ nguyên:

- continuous unwrap/acquisition context;
- thứ tự deadband → guard → command trong `CreepToUnwrappedTargetProfiled()`;
- clamp command step theo live gap;
- crossing/recovery và stick-slip classification;
- B0-B approach legs và compatibility wrapper;
- nominal grid restore sau creep;
- không UART trong motor-on path;
- công thức DATA/Error/RMS/A36/Robust NL/closure.

## 7. Firmware feature contract

Thêm feature mặc định OFF:

```c
#define ENABLE_SWEEP_POINT_CREEP_V59_EXTENDED_TERMINAL_CORRECTION 0
```

Compile-time rules:

1. V5.9 yêu cầu:
   - `ENABLE_SWEEP_POINT_CREEP=1`;
   - `ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING=1`;
   - `ENABLE_SWEEP_POINT_CREEP_V55_DYNAMIC_BASE_ESCALATION=1`.
2. V5.6 MID và V5.7 passive hold phải OFF.
3. V5.4a trace experiment phải OFF.
4. V5.8 response timing được phép ON trong artifact pilot V5.9a.
5. Khi V5.9 OFF, V5.5 và V5.8 phải giữ nguyên hành vi hiện tại.

Protocol IDs dự kiến:

```text
SweepPointCreepProtocol=
  ADAPTIVE_BASE_TO_EXTENDED_ESCALATION_WITH_EXTENDED_TERMINAL_CAP_V1
BudgetEscalationProtocol=BASE_EXHAUSTION_TO_EXTENDED_CAP_V1
TerminalCorrectionProtocol=EXTENDED_PRIMARY320_TO_HARDCAP400_V1
FineLandingProtocol=UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1
ResponseTimingProtocol=DWT_COMMAND_TO_DEADBAND_AND_CAPTURE_V1
```

## 8. State machine V5.9

### 8.1. Selection

Budget class vẫn được chọn duy nhất từ live gap sau ramp + initial settle:

```text
abs(initialGapRaw) > 200 -> EXTENDED
otherwise                -> BASE
```

Không được đổi budget class theo point index hoặc theo kết quả batch trước.

### 8.2. BASE

BASE giữ nguyên V5.5:

```text
primary 220 -> nếu cần thì tiếp tục tới hard 320 -> stop
```

V5.9 không cho BASE dùng 400 raw. Nếu BASE vẫn fail tại 320, đó là một failure khác và phải được log,
không được che bằng terminal extension.

### 8.3. EXTENDED

`CreepToUnwrappedTargetProfiled()` nhận optional terminal config cho caller main sweep. B0-B truyền
`NULL` và không đổi hành vi.

Pseudo-code:

```text
while true:
    if abs(gap) <= 16:
        result = OK
        break

    apply existing phase/crossing/jump/acquisition checks

    if terminal disabled:
        preserve existing budget behavior

    if EXTENDED and totalCorrection >= 320 and terminal not latched:
        terminalAttempted = true
        terminalEntryGapRaw = gap
        terminalEntryIteration = iterations

    if totalCorrection >= 400:
        result = BUDGET_EXCEEDED
        break

    issue the same active 16/4-raw command and settle as V5.5
```

Deadband success phải được kiểm tra trước hard-cap failure. Do đó point vừa đạt deadband sau command
làm tổng correction bằng 400 raw vẫn được ghi `OK`, không bị báo sai `BUDGET_EXCEEDED`.

### 8.4. Terminal evidence

Không thêm MA600 read. Tại thời điểm V5.5 cũ sẽ dừng ở cap 320, firmware latch từ sample/gap hiện có:

- `TerminalEntryGapRaw`;
- `TerminalEntryIteration`;
- `TerminalCorrectionRaw` được cộng từ đúng các command phát **sau** khi terminal phase latch;
- `TerminalIterations = Iterations - TerminalEntryIteration`;
- `TerminalSucceeded` chỉ khi kết quả cuối là `OK` và không chạy recovery;
- terminal response efficiency do tool tính:

```text
TerminalObservedTowardTargetRaw =
    abs(TerminalEntryGapRaw) - abs(FinalGapRaw)

TerminalResponseEfficiencyPermille =
    1000 * TerminalObservedTowardTargetRaw / TerminalCorrectionRaw
```

Không suy `TerminalCorrectionRaw` bằng `TotalCorrectionRaw - 320`, vì budget loop hiện tại cho phép
command cuối của primary phase chạm/vượt biên theo active step. Accumulator riêng giữ accounting đúng
và bảo đảm chuỗi command V5.5 trước terminal không bị gán nhầm cho V5.9.

Giữ giá trị efficiency âm; không clamp để không che phản hồi ngược hướng. Nếu crossing làm recovery
phase chạy, terminal efficiency ghi `NA` và dùng các field recovery hiện có; không trộn command thuận
và command đảo chiều vào cùng một efficiency.

Hard cap 400 là cap của ordinary forward correction. Existing single-reversal recovery vẫn có ngân
sách riêng 64 raw/17 iterations và chỉ chạy khi crossing guard kích hoạt. `OK_RECOVERED` vẫn được giữ
trong result gốc để không mất bằng chứng, nhưng mọi crossing/recovery trong pilot V5.9 là một mechanism
failure, không được coi là `TerminalSucceeded` dù cuối cùng vào deadband.

## 9. Safety envelope theo sweep

Per-point cap 400 chưa đủ bảo vệ nếu mount xấu làm nhiều vùng cùng fail. V5.9 thêm guard chỉ kích hoạt
trong trạng thái bất thường:

| Guard | Giá trị pilot |
|---|---:|
| Số point được phép vào terminal/sweep | 10 |
| Tổng ordinary terminal allowance/sweep | 800 raw |

Hai giới hạn tương đương worst-case 10 point × 80 raw nhưng được log riêng để bắt sai accounting.
Recovery correction không được tính vào allowance 800 raw vì đã có guard 64 raw riêng; nếu recovery
xảy ra thì hardware gate vẫn FAIL.

Khi guard đã hết:

- các point sau vẫn chạy motion V5.5 tới 320 raw;
- không được mở terminal extension;
- set `TerminalSweepGuardExceeded=1`;
- run là diagnostic-invalid cho quyết định promote;
- không tăng cap và không tự bỏ qua lỗi.

Guard 10 point cao hơn max 8 point/sweep trên các mount tốt V5.8, nhưng thấp hơn rõ ràng profile lệch
tâm P08 remount02 (16–17 point/sweep). Đây là safety gate pilot, chưa phải ngưỡng product production.

## 10. RAM và trace

V5.8 map còn khoảng 15,712 byte CCMRAM. V5.9 cần:

- một số field scalar trong `NlCreepDiagnostics_t`;
- per-point terminal entry/iteration/flags trong shadow storage;
- trace đủ bao phủ ordinary + recovery guard.

Với fine-step 4 raw:

```text
ceil(400 / 4) = 100
maxIterations phải > 100 -> chọn 101
trace requirement = 101 ordinary + 17 recovery = 118 entry
```

Chọn trace capacity pilot = 120. Không tăng lên tùy ý.

Build gate:

- compile-time assert iteration > `ceil(hardCap/fineStep)`;
- compile-time assert trace capacity ≥ ordinary + recovery;
- `.ccmram_bss` không vượt 65,536 byte;
- giữ tối thiểu 8 KB CCM headroom sau link;
- kiểm tra stack high-water trên hardware.

## 11. Telemetry contract

### 11.1. CONFIG

`SWEEP_CREEP_CONFIG` thêm:

- `TerminalCorrectionProtocol`;
- `ExtendedPrimaryBudgetRaw=320`;
- `ExtendedHardBudgetRaw=400`;
- `ExtendedTerminalAllowanceRaw=80`;
- `ExtendedMaxIterations=101`;
- `TerminalMaxPointsPerSweep=10`;
- `TerminalMaxTotalRawPerSweep=800`.

### 11.2. POINT

Bump `SWEEP_CREEP_POINT` lên schema 10 cho V5.9. Thêm:

- `TerminalEligible`;
- `TerminalAttempted`;
- `TerminalEntryGapRaw`;
- `TerminalEntryIteration`;
- `TerminalIterations`;
- `TerminalCorrectionRaw`;
- `TerminalObservedTowardTargetRaw`;
- `TerminalResponseEfficiencyPermille`;
- `TerminalSucceeded`;
- `TerminalSuppressedBySweepGuard`.

Quy ước:

- BASE: `TerminalEligible=0`, các field không áp dụng ghi `NA`, không giả thành 0;
- EXTENDED đạt trước/equal 320: eligible nhưng `TerminalAttempted=0`;
- EXTENDED cần command sau 320: `TerminalAttempted=1`;
- efficiency chỉ numeric khi correction > 0;
- `Official=0` trong pilot.

### 11.3. END

Thêm:

- `SweepPointTerminalEligible`;
- `SweepPointTerminalAttempted`;
- `SweepPointTerminalSucceeded`;
- `SweepPointTerminalFailed`;
- `SweepPointTerminalSuppressed`;
- `SweepPointTerminalTotalIterations`;
- `SweepPointTerminalTotalCorrectionRaw`;
- `SweepPointTerminalSweepGuardExceeded`.

### 11.4. Tool

Python/UART analyzer và MATLAB phải báo riêng:

- terminal attempt/success rate;
- entry gap, final gap, gap reduction;
- correction raw và iterations;
- terminal response efficiency, giữ cả giá trị âm;
- extra time trên terminal point;
- số point bị sweep guard suppress;
- baseline 320 result và final 400 result không được gộp thành một tỷ lệ mơ hồ.

## 12. Statistical status và artifact

### V5.9a — diagnostic pilot

- V5.9 terminal correction ON;
- V5.8 DWT timing ON;
- FAST3: 1 PRECONDITION + 3 OFFICIAL-labelled;
- mọi run `EligibleForStatistics=0`;
- mục đích: causal motion/timing evidence, không phán product NL.

Artifact dự kiến:

```text
builds/sweep-point-terminal-correction-v5-9a-fast3-YYYYMMDD/
```

### V5.9b — production candidate

Chỉ tạo sau khi toàn bộ gate V5.9a PASS:

- terminal correction ON;
- timing diagnostic OFF, hoặc phải có A/B instrumentation-neutral riêng;
- source defaults được restore sau packaging;
- chưa promote schema v6 cho tới qualification tương ứng.

## 13. Mount prerequisite

Firmware `MOUNT_PRECHECK_V1` hiện chưa dùng H1/H2 để hard gate và
`ENABLE_MOUNT_PRECHECK_GATE=0`. V5.9 không tự ý đổi điều này.

### Pilot P08/JIG8

Chỉ nhận batch causal khi PRECONDITION thỏa:

- acquisition OK;
- tracking/closure valid;
- `H2AmplitudeDeg <= 0.020°`;
- `RobustP2PDeg <= 0.30°`;
- operator xác nhận không tháo/lệch mount giữa A và B.

Các ngưỡng trên chỉ là **P08/JIG8 pilot filter**, nằm giữa family tốt và lần lệch tâm đã biết. Không
được áp cho P02/P03/P09 hoặc compile thành production threshold chung.

P03/P09 chỉ được dùng ở bước generalization sau P08; phải ghi product/mount label trong filename và
đối chiếu với family precondition đã có. Muốn hard gate production theo product thì product family
phải được xác định trước PRECONDITION, không thể dựa vào `MotorID=UNKNOWN` sau khi test xong.

## 14. Software implementation phases

### S0 — feature skeleton

- thêm feature flag và compile guards;
- thêm constants 320/400/80/101/10/800;
- protocol IDs riêng;
- default OFF không đổi behavior.

### S1 — terminal state/evidence

- thêm optional terminal config vào profiled creep;
- B0-B và caller cũ truyền NULL;
- latch entry state tại đúng stop boundary của V5.5;
- giữ deadband/crossing/jump priority;
- thêm per-sweep safety guard.

### S2 — storage/telemetry

- thêm per-point terminal storage;
- schema-10 CONFIG/POINT/END;
- giữ UART deferred sau motor disable;
- mở trace capacity có kiểm soát tới 120;
- kiểm tra CCM/link map.

### S3 — tools/tests

- cập nhật Python response analyzer, UART app và MATLAB parser;
- thêm fixtures cho schema 10;
- không làm hỏng schema 7/8/9 và log V5.8;
- tool phải tách PRECONDITION khỏi official-labelled rows.

### S4 — build/package

- Release build sạch;
- chạy full regression;
- đóng gói V5.9a FAST3;
- ghi SHA256, map, build info và feature fingerprint;
- restore source flag về safe defaults.

## 15. Software verification matrix

Test bắt buộc:

1. EXTENDED đạt deadband trước 320: không terminal attempt.
2. EXTENDED còn ngoài tại 320, đạt ở 324–396: terminal PASS.
3. EXTENDED đạt đúng sau command làm total = 400: PASS, không bị báo budget fail.
4. EXTENDED còn ngoài tại 400: `BUDGET_EXCEEDED`.
5. BASE đạt sau escalation 220→320: hành vi V5.5 giữ nguyên.
6. BASE fail tại 320: không được dùng 400.
7. Crossing trước/sau terminal: guard cũ dừng đúng thứ tự.
8. Stick-slip jump: dừng ngay, không tiếp tục terminal.
9. Acquisition error: giữ sample cuối và invalid đúng contract.
10. Point terminal thứ 11: bị suppress, sweep guard được log.
11. Tổng allowance chạm 800 raw: không phát thêm terminal command.
12. Trace capacity bao phủ 101 + 17 entry.
13. B0-B two-leg wrapper giữ nguyên constants và không nhận terminal config.
14. Không point-index/motor-ID lookup trong policy.
15. `CaptureSweep()` không format/transmit UART khi motor đang chạy.
16. V5.5, V5.8 và default build compile/pass khi V5.9 OFF.
17. V5.9a compile với timing ON; V5.6/V5.7 conflict build phải fail có chủ ý.
18. Parser cũ đọc được schema 7/8/9; parser mới đọc schema 10.
19. Response timing completeness = captured points.
20. Full PowerShell/Python/MATLAB regression pass.

## 16. Hardware validation

### 16.1. Pilot A/B — P08/JIG8, cùng mount

Không tháo motor giữa A và B:

1. Flash A = V5.8 timing baseline, cap 320.
2. Chạy FAST3 đầy đủ.
3. Kiểm tra P08 pilot mount filter.
4. Không chạm cụm motor/sensor.
5. Flash B = V5.9a timing, cap 400.
6. Chạy FAST3 đầy đủ.

A2 chỉ cần khi A→B cho kết quả mâu thuẫn với mount fingerprint hoặc có drift không giải thích được.

Nếu A không tạo ít nhất ba primary-cap candidate trong 3 official cycles thì batch đó không đủ mạnh
để đánh giá terminal mechanism; không được tuyên bố PASS chỉ vì B không có failure.

### 16.2. Remount độc lập P08

Sau khi A/B đầu PASS:

- remount P08 lần mới;
- PRECONDITION phải qua pilot mount filter;
- chạy một V5.9a FAST3;
- xác nhận terminal success không phụ thuộc duy nhất một mount.

### 16.3. Non-regression P09

- một mount P09/JIG8;
- một V5.9a FAST3;
- không dùng H2 threshold của P08;
- xác nhận các point vốn đạt trước 320 không thay đổi;
- terminal chỉ cải thiện hoặc giữ nguyên failure population.

### 16.4. Generalization P03

- một mount P03/JIG8;
- một V5.9a FAST3;
- terminal success ≥ 90%;
- cho phép tối đa một 400-raw failure trong pilot theo dự báo V5.8;
- nếu failure còn lại lặp đúng point qua 3/3 cycle thì giữ làm bằng chứng cho V6.0, không tăng cap.

## 17. Hardware gates

### 17.1. Data/integrity

- 1 PRE + 3 official-labelled đầy đủ;
- 371 timing rows/sweep, 370 command points/sweep;
- timing completeness = 100%;
- phase-sum error ≤ 0.01 ms;
- acquisition/transport/UART clean;
- creep integrity valid;
- zero target crossing, recovery recross và stick-slip jump;
- stack high-water ≥ 768 words;
- terminal sweep guard không được kích hoạt trên mount tốt.

### 17.2. Motion mechanism

P08:

- terminal attempted candidates success = 100% trên hai mount tốt;
- family 148/157/158 hoặc family hard-cap tương đương trong baseline phải vào deadband;
- không còn repeated 400-raw failure;
- final gap của success nằm trong ±16 raw.

P09:

- reached rate không giảm quá 0.5 điểm phần trăm so với matched baseline;
- không sinh crossing/jump/new repeated family.

P03:

- terminal success ≥ 90%;
- không quá một 400-raw failure toàn pilot;
- failure còn lại không được che hoặc trung bình hóa thành PASS.

### 17.3. Timing/thermal

- non-terminal point `CommandToStopMs` không đổi vật chất so với A;
- terminal extra time P95 ≤ 200 ms/point;
- motor active duration tăng ≤ 2 s/sweep hoặc ≤ 3%, lấy ngưỡng lớn hơn;
- terminal attempted ≤ 10 point/sweep và total extension ≤ 800 raw;
- không tăng thời gian capture 64-sample.

### 17.4. Measurement regression — report riêng

V5.9a không official. Dùng các trường sau chỉ để phát hiện motion/instrumentation regression:

- A36 chênh matched A/B ≤ 0.005°;
- Tracking RMS không xấu hơn quá 0.01°;
- full-curve centered correlation ≥ 0.98;
- báo RMSE và top-5/bottom-5 point;
- Robust NL phải được báo nhưng **không đặt mục tiêu phải giảm**;
- không dùng một scalar NL để retune cap/step.

Nếu motion PASS nhưng curve/NL không lặp lại, đóng băng motion và chuyển sang mounting/measurement
qualification; không tiếp tục tăng command để ép scalar NL.

## 18. Decision tree

### Promote V5.9a → V5.9b

Chỉ khi:

- P08 hai mount PASS;
- P09 non-regression PASS;
- P03 generalization PASS;
- timing/thermal/integrity PASS;
- không có mount-confounded batch trong nguồn quyết định.

### Dừng V5.9 và mở plan V6.0

Mở V6.0 khi một trong các điều kiện sau lặp lại trên mount hợp lệ:

- terminal success < 90%;
- cùng point vẫn fail tại 400 raw;
- response efficiency terminal gần 0 hoặc âm;
- crossing/jump xuất hiện;
- sweep guard kích hoạt;
- time/heat vượt gate.

V6.0 khi đó là nhánh kiến trúc controller hardware-timed/feedback định kỳ; **không mặc định là FOC**.

### Không được làm

- không tạo V5.10 chỉ để tăng cap 400→480/500;
- không tune theo batch lệch tâm;
- không promote vì scalar NL nhỏ hơn;
- không gộp PRECONDITION vào official statistics;
- không coi `EligibleForStatistics=0` là product FAIL.

## 19. Quan hệ với firmware chuẩn đo NL

V5.9 chỉ đóng hạng mục motion endpoint. Sau V5.9 PASS vẫn còn:

1. hiệu chuẩn mount gate theo product/jig;
2. production candidate không timing hoặc A/B chứng minh timing-neutral;
3. canonical official/schema v6 promotion;
4. 10-run no-remount;
5. remount/different-day/cross-jig Gage R&R;
6. release gate và golden artifact.

V5.9 PASS không tự động biến firmware thành phép đo INL tuyệt đối của riêng MA600/motor. Claim đó vẫn cần
reference encoder cơ khí độc lập.

## 20. Definition of Done

### Plan

- [x] Bằng chứng V5.8 được tách mount tốt/xấu.
- [x] Cap 400 và iteration 101 có tính toán trước.
- [x] BASE được khóa ở 320; chỉ EXTENDED được terminal extension.
- [x] Có per-point và per-sweep safety envelope.
- [x] Có telemetry để đo entry/final response thay vì chỉ nhìn scalar NL.
- [x] Có mount prerequisite và chống overfit.
- [x] Có A/B, remount, non-regression và generalization gate.
- [x] Có điều kiện dừng để chuyển V6.0.
- [ ] Người review phê duyệt plan trước khi code.

### Implementation — chưa bắt đầu

- [ ] S0 feature skeleton.
- [ ] S1 terminal state/evidence.
- [ ] S2 storage/telemetry/RAM.
- [ ] S3 tools/tests.
- [ ] S4 Release build/package.
- [ ] P08 same-mount A/B.
- [ ] P08 independent remount.
- [ ] P09 non-regression.
- [ ] P03 generalization.
- [ ] Quyết định promote V5.9b hoặc mở V6.0.
