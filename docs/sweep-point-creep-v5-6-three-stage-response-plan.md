# V5.6 — three-stage 16→8→4 response-qualified landing

Date: 2026-08-06

Status: PLAN AUDITED / READY FOR IMPLEMENTATION — NOT CODED

## 1. Quyết định

V5.5 được giữ làm baseline vì cơ chế BASE→EXTENDED động đã giảm mạnh số điểm hết ngân sách mà
không tăng power hoặc hard cap. Tuy nhiên V5.5 chưa đủ điều kiện promote:

- còn các hard-cap failure lặp lại tại point 8 và 28;
- một sweep remount01 invalid do crossing/recovery failure tại point 66;
- tỷ lệ BASE escalation thành công chưa đạt 90%;
- repeatability NL chưa đồng nhất giữa hai remount.

V5.6 **không tăng hard cap trên 320 raw** và **không tăng power trên 1.0**. Thay đổi chuyển động duy
nhất của build đầu tiên là thay landing hai tầng `16→4` bằng ba tầng theo live encoder gap:

```text
abs(liveGapRaw) > 96       -> COARSE, step 16 raw
64 < abs(liveGapRaw) <= 96 -> MID,    step 8 raw
16 < abs(liveGapRaw) <= 64 -> FINE,   step 4 raw
abs(liveGapRaw) <= 16      -> OK
```

State chỉ chuyển một chiều `COARSE→MID→FINE`; không quay lại step lớn hơn trong cùng point. Mỗi
quyết định dùng sample MA600 mới sau settle, không dùng point index, góc, motor ID, jig ID hoặc
whitelist.

Tên “response-qualified” có chủ ý: hiện chưa có dữ liệu phần cứng độc lập cho step 8 raw. Vì vậy:

1. **V5.6a** dùng các vùng live-gap cố định ở trên và đo response thật của cả ba phase.
2. Chỉ tạo **V5.6b adaptive** nếu batch V5.6a độc lập chứng minh MID-8 có response tốt hơn và không
   làm xấu safety/time/NL.
3. Không vừa suy ra threshold response vừa cho chính batch đó PASS.

## 2. Bằng chứng dẫn tới V5.6

Hai batch P03/JIG7 V5.5 dùng cùng firmware và hai remount:

| Chỉ số | Remount01 | Remount02 | Nhận định |
|---|---:|---:|---|
| Official valid | 2/3 | 3/3 | tổng 5/6 |
| BASE hard-cap mean | 7.5/run trên run valid | 13.0/run | giảm mạnh so với V5.4a nhưng chưa hết |
| BASE escalation success | 87.3% trên run valid; 85.4% nếu tính cả batch | 79.47% | chưa đạt gate 90% |
| Robust NL mean | 0.393657° | 0.474814° | lệch remount +0.081157° |
| Robust NL CV | 20.17% | 2.83% | remount01 fail repeatability |
| Integrity | point 66 recovery fail ở official 3 | sạch 4/4 cycle | còn failure phụ thuộc trạng thái cơ khí |
| Điểm lặp lại | point 28 fail mọi sweep | point 8 và 28 fail 3/3 official | nhóm endpoint chưa đóng |

Chi tiết response tại các điểm còn lỗi:

- point 8 remount02: coarse command 256–272 raw chỉ đạt khoảng 46.5–51.6%; fine command 48–64 raw
  đạt khoảng 54.7–66.7%; final gap `-28/-17/-27 raw`;
- point 28: coarse command thường 288 raw đạt khoảng 52.8–57.3%; fine command 32 raw đạt khoảng
  62.5–100% nhưng dừng ở final gap khoảng `-24…-41 raw`;
- point 66 remount01: crossing `-36→+22 raw`, recovery dùng hết 64 raw nhưng kết thúc `+67 raw`.

Những số này cho thấy step nhỏ có tiềm năng cải thiện hiệu suất/độ êm ở vùng gần target, nhưng chưa
chứng minh nguyên nhân là bản thân step size: fine luôn xuất hiện sau coarse nên trạng thái cơ học đã
khác. Step 8 là thí nghiệm cần thiết để lấp khoảng trống bằng chứng giữa 16 và 4 raw.

Kết quả full-curve V5.5 qua hai remount cũng buộc phải giữ hai verdict riêng:

- centered RMSE khoảng 0.0228°: đạt ngưỡng quan sát 0.05°;
- correlation `r0≈0.969`: dưới mục tiêu 0.98;
- top tail gần như ổn định, bottom tail dịch khoảng 0.080° và quyết định phần lớn scalar NL.

Vì vậy V5.6 chỉ được phép sửa motion endpoint; không được retune để ép scalar NL giữa hai remount
trùng nhau.

### 2.1 Bằng chứng cross-combination trước khi code

Các batch V5.5 không có cùng vai trò và không được gộp thành một nhận định chung “đều có hard-cap
failure”:

| Tổ hợp | BASE escalation success | Hard-cap failure | Robust NL | Vai trò trong V5.6 |
|---|---:|---|---:|---|
| P03/JIG7 | 79.47–87.3% tùy remount/run-valid | lặp lại point 8/28; từng có recovery failure ở 66 | 0.394–0.475° | hard-case đã biết |
| P03/JIG8 | 88.76% | point 347 fail 4/4; 187 fail 3/4; 107 fail 2/4 | 0.221163°, CV 1.16% | kiểm tra tổng quát cross-jig |
| P09/JIG8 | 100% | 0 hard-cap/crossing/recovery/jump ở 4/4 cycle | 0.218865°, CV 0.17% | non-regression control |
| P02/JIG7 | BASE success cao nhưng 93–116 point EXTENDED/sweep | không cùng kiểu 2–3 endpoint cô lập | 0.8119°, CV 17.95% | exploratory/product-characteristic |

Kết luận dùng cho thiết kế thực nghiệm:

- point 8/28/66 là marker chẩn đoán riêng của P03/JIG7, không phải whitelist hay gate phổ quát;
- P03/JIG8 chứng minh hard-cap family thay đổi theo tổ hợp motor×jig, nên cần gate theo tỷ lệ thành công và
  số family lặp lại thay vì ép mọi jig phải lỗi tại cùng góc;
- P09/JIG8 là control sạch để phát hiện thuật toán mới tự tạo dao động;
- P02 không được dùng để promote/reject V5.6 vì failure mode chính là vùng EXTENDED rộng, khác giả thuyết
  “step quá thô tại một số endpoint”.

## 3. Giả thuyết cần kiểm định

### H1 — MID-8 cải thiện landing

Trong vùng 64–96 raw, step 8 tạo response có hướng tốt hơn step 16 và giảm stored command deficit
trước khi latch fine-4. Khi đó point 8/28 cần ít tổng command hơn để vào ±16 raw.

### H2 — MID-8 giảm crossing/breakaway

Việc giảm 16→8 sớm hơn 32 raw làm giảm xác suất một command lớn kích hoạt breakaway khi rotor đã gần
target.

### H3 — response không phụ thuộc step size

Nếu efficiency 8 raw không tốt hơn 16 raw, hard-cap failure là do trạng thái cân bằng tĩnh,
friction/cogging hoặc command-to-rotor load tích lũy. Khi đó tiếp tục giảm step không phải đòn bẩy đúng.

V5.6a phải đủ telemetry để phân biệt ba giả thuyết này.

## 4. Mục tiêu và non-goals

### 4.1 Mục tiêu

1. Xác nhận response thật của step 8 raw trên cùng thuật toán và phần cứng.
2. Giảm BASE hard-cap failure còn không quá 6 điểm/official sweep trên P03/JIG7.
3. Đưa BASE escalation success lên ít nhất 90% mà không tăng hard cap/power.
4. Đưa point 8, 28 và 66 vào deadband ở 4/4 cycle của batch P03/JIG7, đồng thời chứng minh cải thiện
   tổng quát trên P03/JIG8 mà không hardcode theo point.
5. Giữ acquisition, integrity, B0-B và measurand NL không đổi.
6. Tách riêng verdict motion, within-mount measurement, cross-jig generalization và non-regression.

### 4.2 Không làm trong V5.6a

- không tăng BASE primary 220 raw hoặc hard cap 320 raw;
- không tăng recovery 64 raw/17 iterations;
- không đổi power 1.0;
- không đổi deadband ±16 raw, jump threshold 96 raw hoặc fine entry 64 raw;
- không đổi ramp, settle timing, sample count, MA600 filter/config hoặc công thức NL;
- không hardcode point 8/28/66;
- không dùng response gain được tính từ chính batch V5.6a để thay đổi lệnh trong batch đó;
- không thêm FOC/PID/closed-loop architecture;
- không tối ưu UART bằng cách bỏ record measurement bắt buộc;
- không thay đổi B0-B approach/creep.

## 5. Locked invariants

| Item | Giá trị khóa |
|---|---:|
| BASE primary budget | 220 raw |
| BASE hard cap sau escalation | 320 raw |
| EXTENDED hard cap | 320 raw |
| Coarse step | 16 raw |
| MID step | 8 raw — biến thử nghiệm duy nhất |
| MID entry | 96 raw — biến thử nghiệm duy nhất |
| Fine entry / fine step | 64 / 4 raw |
| Deadband | 16 raw |
| Ordinary iteration guard | 81 |
| Power | 1.0 |
| Jump threshold | 96 raw |
| Recovery budget / guard | 64 raw / 17 iterations |
| Reversal limit | một |
| Trace storage | một buffer 100 entry/sweep |

Hai giá trị `96 raw` ở bảng trên **độc lập về ngữ nghĩa**, chỉ tình cờ bằng nhau trong V5.6a:

- `MID entry=96 raw` áp dụng cho `abs(liveTargetGapRaw)` **trước command** và chỉ quyết định transition
  `COARSE→MID`;
- `Jump threshold=96 raw` áp dụng cho `abs(settledObservedDeltaRaw)` **sau một command** và chỉ phân loại
  safety event `STICK_SLIP_JUMP`.

Khi code phải dùng hai constant riêng, không alias lẫn nhau:

```c
#define NL_SWEEP_CREEP_V56_MID_ENTRY_GAP_RAW          96U
#define NL_SWEEP_CREEP_V56_STICK_SLIP_JUMP_DELTA_RAW 96U
```

Việc chỉnh một constant trong phase sau không được tự động chỉnh constant còn lại. Comment cạnh định nghĩa và
telemetry basis là một phần của contract bảo trì, không chỉ là ghi chú tùy chọn.

Ngoài ra phải giữ nguyên:

- quintic ramp và thứ tự `ramp→settle→creep→official capture`;
- `WaitForPointSettle()` và continuous MA600 unwrap context;
- fresh settled sample sau mỗi creep command;
- command clamp theo gap còn lại;
- jump classification trước crossing/recovery;
- restore nominal grid target sau creep;
- deferred UART logging sau `Motor_Disable()`;
- DATA/Error/Robust-NL/RMS_AC/harmonic/closure formulas và eligibility;
- đúng hai B0-B compatibility-wrapper call với fine profile `NULL`.

## 6. Firmware contract

### 6.1 Feature flag

Thêm nested flag mặc định tắt:

```c
#define ENABLE_SWEEP_POINT_CREEP_V56_THREE_STAGE_LANDING 0
```

Compile-time rules:

1. V5.6 yêu cầu `ENABLE_SWEEP_POINT_CREEP=1`.
2. V5.6 yêu cầu V5.4 universal fine landing và V5.5 dynamic BASE escalation.
3. V5.6 không được bật cùng V5.4a telemetry-only identity.
4. V5.3/V5.4/V5.4a/V5.5 frozen builds vẫn compile và giữ behavior cũ khi V5.6 tắt.
5. Sau packaging, source quay về toàn bộ V5.x default-off và 10 official.

### 6.2 Protocol identity

V5.6a phải có ID mới, không tái sử dụng V5.5:

```text
SweepPointCreepProtocol=ADAPTIVE_BASE_TO_EXTENDED_THREE_STAGE_LANDING_V3
BudgetEscalationProtocol=BASE_EXHAUSTION_TO_EXTENDED_CAP_V1
LandingProtocol=LIVE_GAP_MONOTONIC_16_8_4_DIAG_V1
StepSelectionRule=COARSE_GT96_MID_GT64_FINE_LE64
ResponsePolicy=MEASURE_ONLY_NO_RUNTIME_ADAPTATION_V1
RecoveryProtocol=MONOTONIC_PHASE_SINGLE_REVERSAL_V2
TracePolicy=FIRST_HARD_CAP_BUDGET_OR_INTEGRITY_FAILURE_V1
```

Đổi recovery protocol ID là bắt buộc vì crossing xảy ra trong MID sẽ tiếp tục recovery bằng MID-8;
đây là behavior chưa tồn tại ở V5.5.

## 7. State machine V5.6a

```text
START
  |
  +-- |gap| <= 16 ----------------------------------------> OK
  |
  +-- |gap| > 96 ---------------------------> COARSE (16)
  |                                                |
  |                                                +-- |gap| <= 96 -> MID latch
  |
  +-- 64 < |gap| <= 96 ------------------------> MID (8)
  |                                                |
  |                                                +-- |gap| <= 64 -> FINE latch
  |
  +-- 16 < |gap| <= 64 ------------------------> FINE (4)
                                                   |
                                                   +-- |observed delta| > 96
                                                   |      -> STICK_SLIP_JUMP
                                                   |
                                                   +-- crossing outside deadband
                                                          -> one bounded reversal
```

Quy tắc chi tiết:

1. Deadband được kiểm tra trước mọi phase transition và trước mọi command.
2. Phase transition một chiều: `COARSE→MID→FINE`; có thể bỏ qua COARSE hoặc MID nếu initial gap đã nhỏ.
3. Khi recovery bắt đầu, giữ phase hiện tại; không quay về step lớn hơn.
4. MID và FINE đều dùng jump guard 96 raw. Một jump lớn không được biến thành recovery/chase.
5. Crossing ngoài deadband được reversal đúng một lần; recross dừng trước command tiếp theo.
6. MID step được clamp theo live gap giống coarse/fine.
7. Raw budget tính theo tổng `abs(command step)` của mọi ordinary phase; thay step không cấp thêm budget.
8. Recovery vẫn có budget/iteration độc lập 64/17 nhưng dùng phase đã latch tại crossing.
9. Iteration guard 81 vẫn hợp lệ vì minimum step là 4 raw và `81 > ceil(320/4)=80`.
10. Trace capacity 100 vẫn phủ ordinary + recovery guards (`81+17=98`).

### 7.1 Định nghĩa response

Với mỗi non-recovery command:

```text
directedObservedRaw = directionBeforeStep × observedDeltaRaw
phaseEfficiencyPermille =
    1000 × sum(directedObservedRaw) / sum(abs(commandStepRaw))
```

Không clamp số âm trong tổng vì response ngược hướng là bằng chứng thật. Đồng thời đếm riêng:

- `ZeroResponseSteps`: `directedObservedRaw == 0`;
- `OppositeResponseSteps`: `directedObservedRaw < 0`;
- `LargeResponseSteps`: `abs(observedDeltaRaw) > 96`.

Response recovery được tổng hợp riêng, không trộn vào efficiency của COARSE/MID/FINE.

## 8. Telemetry và data-integrity contract

### 8.1 Schema

- `SWEEP_CREEP_CONFIG`: schema 9;
- `SWEEP_CREEP_POINT`: schema 9;
- `SWEEP_CREEP_STEP`: schema 3 vì có phase `MID` và `RECOVERY_MID`;
- parser phải tiếp tục đọc schema 5–8 và STEP schema 1–2.

CONFIG thêm:

- `LandingProtocol`, `StepSelectionRule`, `ResponsePolicy`;
- `CoarseStepRaw=16`, `MidEntryRaw=96`, `MidStepRaw=8`;
- `MidEntryBasis=ABS_LIVE_TARGET_GAP_BEFORE_COMMAND`;
- `StickSlipJumpThresholdRaw=96`, `JumpThresholdBasis=ABS_SETTLED_OBSERVED_DELTA_PER_COMMAND`;
- `FineEntryRaw=64`, `FineStepRaw=4`;
- protocol recovery mới.

POINT thêm tối thiểu:

- `MidLandingAttempted`;
- `MidIterations`;
- `MidCorrectionRaw`;
- `MidEntryGapRaw`;
- giữ nguyên toàn bộ V5.5 budget/escalation/fine/recovery/result fields.

END thêm rollup, tách non-recovery theo phase:

- iterations, commanded correction và signed directed response của COARSE/MID/FINE;
- zero/opposite/large-response count của từng phase;
- MID attempted-point count;
- expected/emitted POINT và STEP telemetry count.

RAM per-point mới phải giới hạn ở bốn mảng nhỏ:

- `uint16_t midCorrectionRaw[NL_MAX_SWEEP_POINTS]`;
- `int16_t midEntryGapRaw[NL_MAX_SWEEP_POINTS]`;
- `uint8_t midIterations[NL_MAX_SWEEP_POINTS]`;
- `uint8_t midFlags[NL_MAX_SWEEP_POINTS]`.

Tổng tăng dự kiến khoảng 2232 byte với 372 slot. Directed response theo phase được cộng vào rollup của
capture, không tạo ba mảng `int64[372]`. Step response chi tiết vẫn chỉ nằm trong một trace 100 entry.

STEP trace giữ các field cũ và bổ sung phase name mới. Không tăng trace capacity, không thêm trace cho
mọi point và không format/transmit trong `CaptureSweep()`.

### 8.2 Gate completeness

Mỗi cycle phải có:

- đủ `DATA` point 0–370 (371 record); canonical NL vẫn chỉ dùng 0–360;
- số `SWEEP_CREEP_POINT`/`SWEEP_CREEP_STEP` host nhận được khớp expected count trong END;
- không có dòng ghép, thiếu giữa dòng hoặc schema/protocol mâu thuẫn.

Nếu DATA đầy đủ nhưng point telemetry thiếu, batch vẫn có thể xem scalar/full-curve measurement nhưng
**không hợp lệ để kết luận cơ chế V5.6**. Phải sửa capture/logger rồi chạy lại cùng binary; không retune
motion từ log thiếu.

## 9. Tool phân tích

Cập nhật:

- `analysis/matlab/nl/parse_sweep_creep_log.m`;
- `analysis/matlab/nl/analyze_sweep_creep_batch.m`;
- `analysis/matlab/tests/test_nl_stability_analysis.m`.

Output bắt buộc:

1. efficiency COARSE/MID/FINE theo cycle và batch;
2. MID attempt/iteration/correction/zero/opposite response;
3. point 8/28/66 final gap và phase trace;
4. BASE escalation attempted/succeeded/failed;
5. total correction và motor-active duration;
6. Robust NL, RMS_AC, A36, closure và full-curve metrics;
7. top-5/bottom-5 angle, centered curve correlation và RMSE;
8. telemetry completeness verdict độc lập.

Không dùng proxy `MOTION.PositionErrorRaw` thay cho `SWEEP_CREEP_POINT/STEP` khi telemetry thật có sẵn.

## 10. Software implementation phases

### V5.6-S0 — contract

- thêm feature guard và protocol IDs;
- định nghĩa riêng MID-entry-gap và stick-slip-jump-delta constants dù cùng giá trị 96 raw;
- mở rộng phase enum với `MID`/`RECOVERY_MID`;
- thay bool fine-state bằng state ba phase chỉ trong V5.6 path;
- giữ branch legacy/V5.5 behavior khi flag tắt.

### V5.6-S1 — motion

- implement threshold 96/64 và monotonic latch;
- chọn active step 16/8/4 theo phase;
- áp jump-before-crossing cho MID/FINE;
- giữ phase qua một bounded recovery;
- không thay budget, power, settle hoặc acquisition.

### V5.6-S2 — telemetry/tool

- schema 9/3 và END phase-response rollup;
- bounded trace vẫn một buffer;
- MATLAB parser/analyzer backward-compatible;
- explicit completeness check.

### V5.6-S3 — verification/package

Tạo `scripts/test_sweep_point_creep_v5_6_contract.ps1`, chạy full regression, compile matrix,
Release build và package FAST3:

```text
builds/sweep-point-creep-v5-6-three-stage-response-fast3-20260806/
```

Package gồm HEX/ELF/MAP, `build_info.txt`, `SHA256SUMS.txt`; sau đó restore source defaults.

## 11. Software gates

Dedicated contract phải chứng minh:

1. feature dependency/mutual-exclusion đúng;
2. V5.5 và V5.6 có protocol identity khác nhau;
3. threshold/step đúng `96/8` và `64/4`;
4. MID-entry và jump-threshold dùng hai symbol riêng, log đúng hai `Basis` khác nhau và không dùng chung alias;
5. state không chuyển ngược MID→COARSE hoặc FINE→MID/COARSE;
6. phase được chọn từ live gap, không có point/angle/motor/jig lookup;
7. total raw cap vẫn 320 và iteration guard vẫn 81;
8. recovery vẫn một reversal, 64 raw/17 iteration;
9. MID/FINE jump guard chạy trước crossing recovery;
10. B0-B còn đúng hai wrapper call với profile `NULL`;
11. `CaptureSweep()` không gọi UART/log formatting;
12. trace RAM vẫn O(1), capacity 100 phủ 98 iteration tối đa;
13. schema cũ parse được và schema mới tính đúng signed phase efficiency;
14. default, V5.3, V5.4, V5.4a, V5.5 và V5.6 đều compile;
15. full PowerShell regression và Release build pass;
16. stack static margin không giảm quá 256 byte nếu chưa có giải trình; runtime high-water gate giữ 768 word.

## 12. Hardware validation

### 12.1 Điều kiện tiên quyết của pipeline

Trước khi dùng output analyzer làm pass/fail:

- thêm UID JIG8 `003E00323235511835383831` vào bảng jig hợp lệ của
  `scripts/analyze_nonlinear_logs.ps1` và thêm contract test tương ứng; firmware đã nhận JIG8 nhưng analyzer
  chính thức hiện còn reject log này;
- xác nhận analyzer parse đúng protocol/schema V5.6 và không fallback sang contract 256-point;
- tên P03/P09 trong filename hiện là operator label khi `MotorIDValid=0`; không tự động merge batch chỉ dựa
  vào field `MotorID` trong log;
- dùng cùng một phiên bản analyzer cho toàn bộ baseline V5.5 và candidate V5.6.

Nếu chưa đạt các điều kiện trên, firmware run vẫn có thể dùng để debug nhưng verdict qualification là
`ANALYSIS_PIPELINE_INVALID`.

### 12.2 Pilot A1 — hard-case P03/JIG7

Ưu tiên mounting tương đương remount02 vì V5.5 tại đó lặp lại point 8/28 nhưng NL trong batch ổn định.
Ghi orientation và lực siết; không tháo lắp trong batch. Chạy FAST3: 1 precondition + 3 official.

Gate riêng A1, so với matched V5.5 remount02:

- point 8, 28 và 66 đạt `abs(FinalGapRaw)<=16` ở 4/4 cycle;
- BASE escalation success tổng ≥90%, không official run nào dưới 85%;
- BASE hard-cap failure mean ≤6/official run;
- không tạo hard-cap family/crossing/jump/recross mới;
- total correction và motor-active duration tăng không quá 10%.

Point 8/28/66 chỉ là marker xác nhận giả thuyết trên tổ hợp này. Firmware và tool tuyệt đối không được dùng
danh sách này để chọn step hoặc tự cho PASS.

### 12.3 Hard safety/data gates chung

Mỗi pilot phải đạt 4/4 cycle:

- config/protocol/schema đúng V5.6;
- acquisition/transport clean;
- `SweepPointCreepIntegrityValid=1`;
- recovery failed/recross/stick-slip jump bằng 0;
- precondition valid và `OfficialValid=3/3`;
- stack high-water ≥768 word;
- DATA và point/step telemetry completeness đạt mục 8.2.

Bất kỳ pilot bắt buộc nào fail gate này đều là hard FAIL; không dùng kết quả NL của batch đó để cứu verdict.

### 12.4 Pilot A2 — generalization P03/JIG8

Chỉ chạy sau khi A1 không có hard safety/data failure. Giữ nguyên motor P03, chuyển sang JIG8, cố định
orientation/lực siết và chạy 1 precondition + 3 official.

So với baseline V5.5 P03/JIG8 (`BASE success=88.76%`, hard-cap mean `3.33/official run`):

- BASE escalation success tổng ≥90%, không official run nào dưới 85%;
- hard-cap mean ≤1/official run **hoặc** giảm ít nhất 50% so với baseline matched;
- không có một hard-cap point nào lặp lại quá 1/4 cycle;
- point 347/187/107 phải được báo riêng để kiểm chứng, nhưng không phải whitelist hay điều kiện duy nhất;
- không tạo family failure mới, crossing, failed recovery, recross hoặc stick-slip jump;
- total correction và motor-active duration tăng không quá 10%.

A2 trả lời câu hỏi “16→8→4 có cải thiện chung trên một jig khác hay chỉ sửa đúng point 8/28/66?”.

### 12.5 Pilot B — non-regression P09/JIG8

P09/JIG8 là control vốn đạt 0 hard-cap/crossing/recovery/jump ở V5.5. Giữ nguyên mounting trong batch và
chạy 1 precondition + 3 official.

Gate non-regression:

- 0 `BUDGET_EXCEEDED` ở 4/4 cycle;
- 0 crossing, failed recovery, recross và stick-slip jump;
- BASE escalation success giữ 100%;
- không tăng total correction hoặc motor-active duration quá 10% so với matched V5.5;
- measurement gates mục 12.7 không thoái lui ngoài repeatability envelope.

Pilot này không dùng để chứng minh V5.6 cải thiện endpoint; nó chỉ được dùng để chứng minh state machine ba
tầng không làm hỏng tổ hợp đang sạch.

### 12.6 P02 — exploratory only

P02 có thể chạy sau A1/A2/B để quan sát response ba phase, nhưng:

- không dùng P02 để promote hoặc reject V5.6a;
- báo riêng số point EXTENDED, spatial region, hard-cap và full curve;
- không coi vùng EXTENDED rộng là cùng failure mode với vài hard-cap endpoint cô lập;
- mọi thay đổi nhằm xử lý P02 phải là phase/plan riêng, không retune V5.6 theo batch này.

### 12.7 Measurement gates chung

Tách khỏi motion verdict và đánh giá riêng cho từng tổ hợp:

- Robust-NL CV trong batch ≤5.7%;
- RMS_AC và A36 CV trong batch ≤5%;
- closure absolute ≤0.20° ở 3/3 official;
- centered full-curve RMSE so với matched V5.5 ≤0.05°;
- correlation không được giảm quá 0.02 so với lower envelope của matched V5.5; `r≥0.98` là mục tiêu,
  không phải hard gate tuyệt đối vì baseline thật đang ở khoảng 0.95–0.97;
- báo riêng mean shift, top-5/bottom-5 và vị trí extreme; không dùng một scalar NL để retune step.

Motion có thể PASS trong khi measurement/cross-jig FAIL. Khi đó freeze motion candidate và quay lại
mounting/sensor/H2/A2; không dùng controller để ép scalar NL giữa jig.

### 12.8 Promotion matrix

| Pilot | Vai trò | Điều kiện bắt buộc để promote |
|---|---|---|
| A1 P03/JIG7 | hard-case | hard/data + endpoint/aggregate motion PASS |
| A2 P03/JIG8 | generalization | hard/data + aggregate improvement PASS |
| B P09/JIG8 | non-regression | hard/data + zero-regression PASS |
| P02 | exploratory | không tham gia quyết định |

Chỉ promote V5.6a khi A1, A2 và B cùng PASS. Remount độc lập/Gage R&R vẫn cần cho qualification cuối của
jig, nhưng không được trộn vào phép kiểm định cơ chế step 8 của phase này.

## 13. Decision tree

### V5.6a PASS đầy đủ

- giữ candidate 16→8→4;
- chưa cần V5.6b adaptive nếu endpoint/safety/time đã đạt;
- yêu cầu A1 P03/JIG7, A2 P03/JIG8 và B P09/JIG8 cùng PASS;
- P02 không thay đổi verdict; chuyển sang remount độc lập/Gage R&R như qualification riêng.

### MID-8 hiệu quả hơn và an toàn, nhưng endpoint vẫn marginal

- cho phép lập plan V5.6b riêng;
- chỉ dùng batch V5.6a làm calibration và batch mới làm confirmation;
- biến tiếp theo ưu tiên mở rộng MID entry `96→128 raw` hoặc response-based transition, chỉ chọn một;
- không tăng 320 raw/power/recovery trong cùng phase.

### MID-8 không tốt hơn COARSE-16

- reject nhánh giảm step;
- quay về artifact V5.5;
- chẩn đoán stored command deficit/static equilibrium/settle, không thử thêm step 6/2 raw theo kiểu dò số.

### Crossing/recovery/jump xuất hiện

- hard FAIL; trace phải khóa đúng point đầu tiên;
- không tăng jump threshold hoặc recovery budget;
- phân tích phase gây sự kiện trước khi tạo build mới.

### Motion PASS nhưng NL/full curve không repeatable giữa remount

- freeze V5.6 motion candidate;
- phân loại lỗi mounting/sensor/H2/A2 bằng full curve;
- không dùng motion controller để bù sai khác cơ khí của jig.

### Telemetry không đầy đủ

- verdict mechanism = INVALID;
- sửa logger/capture và rerun cùng binary, cùng mounting;
- không thay đổi motion constants.

## 14. File dự kiến thay đổi khi code

- `Core/Src/nonlinear_test.c`;
- `scripts/test_sweep_point_creep_v5_6_contract.ps1` (mới);
- các contract V5.3/V5.4/V5.4a/V5.5 nếu cần khóa backward compatibility;
- `analysis/matlab/nl/parse_sweep_creep_log.m`;
- `analysis/matlab/nl/analyze_sweep_creep_batch.m`;
- `analysis/matlab/tests/test_nl_stability_analysis.m`;
- `docs/session-summary-2026-08-06.md` sau implementation/test;
- Graphify output sau code hoàn tất.

## 15. Audit theo code hiện tại

| Hạng mục | Code hiện tại | Kết quả audit cho V5.6 |
|---|---|---|
| Feature hierarchy | `nonlinear_test.c:901–1058` | có thể thêm V5.6 nested trên V5.5 mà giữ frozen build |
| Phase selector | `CreepToUnwrappedTargetProfiled():2770–2822` | bool `finePhase` là điểm thay bằng enum ba state có guard |
| Fresh encoder response | `WaitForPointSettle():2826–2855` | đã có sample settled và `observedDeltaRaw` sau mỗi command |
| Safety ordering | `nonlinear_test.c:2876–2917` | jump-before-crossing và one-reversal đã đúng, mở rộng cho MID được |
| Hard cap/iteration | `nonlinear_test.c:1027–1069` | 320/81, recovery 64/17 và trace 100 đủ cho V5.6 |
| Main-sweep injection | `CaptureSweep():5218–5260` | profile chỉ đi vào main sweep, không cần chạm B0-B |
| B0-B isolation | wrapper calls tại `4205` và `4296` | tiếp tục truyền profile `NULL`, contract giữ được |
| Deferred logging | capture comment tại `3921`, print từ `5908` | schema mới có thể phát sau motor stop, không thêm UART vào motion |
| RAM | `NlShadowPointStorage_t:3017–3067` | dùng bốn mảng MID nhỏ + rollup, không cấp trace theo 372 point |

Kết luận audit: **không có blocker kiến trúc trước khi code**. Rủi ro chính không phải compile/RAM mà là
giả thuyết vật lý chưa được xác nhận cho step 8 raw; vì vậy V5.6a bắt buộc là build fixed-band +
measurement, chưa phải adaptive controller tự retune.

## 16. Definition of Done

- [x] V5.5 evidence từ hai remount được ghi vào plan;
- [x] thuật toán V5.6a và biến thử nghiệm được khóa trước khi code;
- [x] motion, measurement và telemetry verdict được tách riêng;
- [x] audit plan theo code thật hoàn tất;
- [ ] feature/protocol/state machine được implement default-off;
- [ ] schema/parser/analyzer hoàn tất và backward-compatible;
- [ ] dedicated contract + full regression + Release build pass;
- [ ] FAST3 artifact được package, source defaults được restore;
- [ ] official analyzer nhận JIG8 và contract test tương ứng pass;
- [ ] Pilot A1 P03/JIG7 đạt 1 pre + 3/3 official;
- [ ] Pilot A2 P03/JIG8 đạt 1 pre + 3/3 official;
- [ ] Pilot B P09/JIG8 non-regression đạt 1 pre + 3/3 official;
- [ ] P02 nếu chạy được đánh dấu exploratory, không tham gia promote/reject;
- [ ] quyết định promote/reject/V5.6b được ghi bằng dữ liệu phần cứng.
