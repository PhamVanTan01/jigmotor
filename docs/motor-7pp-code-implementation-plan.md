# Code implementation plan — test motor 7 cặp cực

Updated: 2026-07-24

Branch: `codex/motor-7pp-engineering-test`

Status: **HISTORICAL INITIAL BRING-UP PLAN — superseded**

Plan này ghi lại thiết kế lock-only ban đầu trước khi V3.2 mode 3 được tổng
quát hóa cho 7PP. Các yêu cầu trong tài liệu về việc cấm mọi V3+7PP, profile
`LOCK_ONLY` và negative build V3+14 pole không còn mô tả firmware hiện hành.
Không dùng tài liệu này để chọn profile hoặc build test mới.

Plan đang có hiệu lực:

- `docs/motor-7pp-a-b-evidence-derived-test-plan.md`
- `docs/motor-7pp-stutter-diagnostic-plan.md`
- `docs/motor-7pp-engineering-test-plan.md`, mục P7.8 trở đi

Nguồn yêu cầu:
`D:\tanpham\QAtoool\jigtest\motor\jigmotor\docs\motor-7pp-engineering-test-plan.md`

## 1. Mục tiêu code

Tạo đúng **một build engineering 1-run** cho motor 14 pole/7 pole-pair mà không
thay đổi default 12-pole/6PP hiện tại:

```text
motor-7pp-lock-only-1run-v1
```

Mỗi lần bấm nút chỉ chạy đúng một sweep. Trình tự thử ban đầu:

1. chạy smoke test lần 1 để xác nhận motor có di chuyển đúng chiều và hoàn tất sweep;
2. chỉ khi lần 1 sạch mới nghỉ motor-off tối thiểu 120 giây rồi chạy tùy chọn lần 2
   bằng đúng cùng HEX, JIG và lần gá;
3. dừng sau tối đa hai run; không tự động chạy run thứ 3 và không có batch 10-run.

Mục tiêu của hai run này chỉ là xác nhận feasibility/chuyển động sơ bộ, chưa dùng để
kết luận repeatability thống kê.

Kết quả của build và log phải tự chứng minh:

- `MotorPoleCount=14`;
- `MotorPolePairs=7`;
- `ElectricalRippleOrder=42`;
- `ApproachProtocol=SCURVE_LOCK_V2`;
- profile mang nhãn `ENGINEERING_ONLY`;
- không có B0-B/V2/V3, CCW, feedforward, creep hoặc soft-start thử nghiệm;
- 371 point được capture cho 0..370°, 360 point được dùng phân tích và point 360
  được dùng làm Closure;
- mọi metric 7PP được group riêng, không nhập chung baseline 6PP.

## 2. Baseline gap của branch hiện tại

Không được triển khai bằng cách chỉ đổi `MOTOR_POLE_PAIRS` từ 6 thành 7.

Branch hiện tại chưa đồng nhất với mục “Trạng thái hiện tại” của engineering plan:

| Hạng mục | Code hiện tại | Contract 7PP cần đạt |
| --- | --- | --- |
| Geometry | `Core/Src/motor.c` hardcode `MOTOR_POLE_PAIRS 6` | Một nguồn chung bắt đầu từ physical pole count `MOTOR_NUM_POLSE=14U` |
| Guard | Không có guard pole lẻ/range | Compile fail nếu pole lẻ, ngoài range hoặc chọn V3 với 7PP |
| PWM cycle | `65536 / pairs + 1` | `ceil(65536 / pairs)`, log rõ integer-cycle mapping |
| Grid | Step 256 raw, khoảng 1.40625°, khoảng 264 point/370° | Absolute rounded 1° grid, 371 point |
| Ramp | Linear, 8 raw/1 ms | `SCURVE40_ABSOLUTE_TICK_V2`, 40 feedback sample/segment |
| Settle | Chỉ kiểm tra encoder ít thay đổi | Stability + target proximity, phân biệt timeout/wrong-position |
| Acquisition | Read trực tiếp, chưa có continuous context/counter contract | Một context xuyên suốt ramp/settle/capture, fail-closed |
| Manifest | Chỉ có `Firmware`/compile time trong META | Boot `BUILD_MANIFEST` + profile identity/fingerprint |
| Batch | Default auto-batch 3 run | Auto batch OFF cho bring-up; precondition 1 + official 10 cho P7.3 |
| Harmonic | Danh sách cố định có 36/72/108 | Dynamic electrical order 42 và family 42/84/126 |
| Offline tool | Không có `tools/analyze_one_turn_pattern.py` | CLI nhận pole-pairs; không fold integer khi 360 không chia hết cho 42 |
| Build archive | Chưa có profile/package script | HEX/ELF/MAP, commit/dirty, SHA-256 và toàn bộ defines |

Vì khoảng cách này lớn, implementation phải đi theo gate dưới đây. Không flash motor
trước khi hoàn tất Gate G0–G4.

## 3. Thiết kế cấu hình

### 3.1. Geometry dùng chung

Tạo `Core/Inc/motor_config.h` và dùng file này ở cả commutator lẫn measurement:

```c
#ifndef MOTOR_NUM_POLSE
#define MOTOR_NUM_POLSE 12U
#endif

#if (MOTOR_NUM_POLSE < 2U) || (MOTOR_NUM_POLSE > 128U)
#error "MOTOR_NUM_POLSE must be in the range 2..128"
#endif

#if ((MOTOR_NUM_POLSE % 2U) != 0U)
#error "MOTOR_NUM_POLSE must be even"
#endif

#define MOTOR_POLE_PAIRS                  (MOTOR_NUM_POLSE / 2U)
#define MOTOR_MECHANICAL_COUNTS_PER_REV  65536U
#define MOTOR_COUNT_PER_ELECTRICAL_CYCLE \
    ((MOTOR_MECHANICAL_COUNTS_PER_REV + MOTOR_POLE_PAIRS - 1U) / MOTOR_POLE_PAIRS)
#define MOTOR_ELECTRICAL_RIPPLE_MULTIPLE 6U
#define MOTOR_ELECTRICAL_RIPPLE_ORDER \
    (MOTOR_POLE_PAIRS * MOTOR_ELECTRICAL_RIPPLE_MULTIPLE)
```

Yêu cầu:

- default vẫn là `12U`;
- profile 7PP inject `MOTOR_NUM_POLSE=14U`;
- không định nghĩa một bản sao pole-pair trong `motor.c` hoặc `nonlinear_test.c`;
- thêm compile-time assertions cho 14 pole:
  `pairs=7`, `cycle=9363`, `ripple order=42`;
- giữ mapping hiện tại `pos % 9363` cho lần bring-up;
- direct-Q16 chỉ được thêm ở thí nghiệm P7.5 độc lập.

### 3.2. Profile identity

Tạo `Core/Inc/test_profile.h` với các profile ID ổn định:

```text
DEFAULT_6PP
7PP_ENGINEERING_LOCK_ONLY_1RUN_V1
```

Profile phải resolve thành một cấu hình đầy đủ, không chỉ pole count:

| Field | Giá trị |
| --- | ---: |
| `MOTOR_NUM_POLSE` | 14U |
| `NL_APPROACH_MODE` | LOCK_ONLY |
| `ENABLE_AUTO_BATCH_TEST` | 0 |
| Sweep mỗi lần bấm | 1 |
| Tổng run ban đầu | 1 bắt buộc + 1 tùy chọn |
| Cooldown giữa hai run | manual, tối thiểu 120000 ms |
| CCW | 0 |
| B0-B/V2/V3 | 0 |
| Ramp/sweep soft-start | 0 |
| Motion profile | S-curve V2 |
| Closure hold probe | diagnostic |
| Result label | ENGINEERING_ONLY |

Thêm `#error` cho mọi tổ hợp trái contract, đặc biệt:

- `MOTOR_NUM_POLSE=14U` + V3;
- 7PP + B0-B bias/feedforward/creep;
- 7PP + Control A5 offset 7971;
- profile 1-run nhưng auto batch bật;
- cấu hình một lần bấm chạy nhiều hơn một sweep.

## 4. Work packages

### WP0 — Khóa baseline và contract tests

Files:

- `scripts/test_motor_geometry_contract.ps1` — mới;
- `scripts/test_motor_7pp_profile_contract.ps1` — mới;
- `scripts/run_contract_tests.ps1` — mới.

Việc làm:

1. Ghi test source/compile contract trước khi sửa firmware.
2. Test default 12 pole không đổi.
3. Test profile 7PP suy ra 7 pair, cycle 9363, order 42.
4. Test negative profile V3+14 pole phải compile fail.
5. Test không có hằng 6PP riêng trong commutator/measurement.

Gate G0:

- contract test chạy được và các test mới fail đúng lý do trên baseline hiện tại;
- lưu output baseline trong review/CI log, không sửa threshold để làm test pass.

### WP1 — Geometry và PWM commutation

Files:

- `Core/Inc/motor_config.h` — mới;
- `Core/Src/motor.c`;
- `Core/Inc/motor.h`.

Việc làm:

1. Chuyển pole geometry khỏi `motor.c` sang `motor_config.h`.
2. Giữ nguyên PID gains, power và API hiện tại.
3. Đổi tên nội bộ sang `MOTOR_COUNT_PER_ELECTRICAL_CYCLE`.
4. Thêm getters/audit helpers cho pole count, pairs, electrical cycle và ripple order.
5. Thêm unit-style host/reference test cho các giá trị:
   - 12 pole → 6 pair → 10923 raw;
   - 14 pole → 7 pair → 9363 raw;
   - 7 × 9363 = 65541, phase-boundary surplus = 5 raw.
6. Không sửa thuật toán mapping trong WP này.

Gate G1:

- Debug và Release của default 6PP build được;
- 7PP profile build được;
- odd pole negative build fail;
- binary 6PP vẫn log/điều khiển theo geometry cũ.

### WP2 — Measurement grid, motion và acquisition contract

Files:

- `Core/Src/nonlinear_test.c`;
- `Core/Inc/nonlinear_test.h`;
- nếu tách module: `Core/Inc/ma600_acquisition.h`,
  `Core/Src/ma600_acquisition.c`;
- `.cproject` để đưa module mới vào Debug/Release.

Việc làm:

1. Thay fixed `NL_POS_INCREASE=256` bằng target tuyệt đối:

   ```text
   targetRaw(i) = round(i × 65536 / 360), i=0..370
   ```

2. Buffer tối thiểu 372 slot; capture đúng 371 point.
3. `AnalysisPoints=360` cho point 0..359; Closure dùng point 360.
4. Tạo boot self-test cho grid:
   - target 0 = 0;
   - target 180 = 32768;
   - target 360 = 65536;
   - mọi delta chỉ là 182 hoặc 183 raw.
5. Thay linear ramp bằng S-curve 40 tick dùng absolute deadline.
6. Mỗi tick ramp phải lấy feedback và cập nhật counters.
7. Dùng một acquisition context xuyên suốt ramp → settle → averaged point.
8. Settle chỉ OK khi đồng thời:
   - encoder ổn định;
   - gần target.
9. Phân loại riêng `OK`, `TIMEOUT`, `WRONG_POSITION`.
10. Bất kỳ lỗi transport/jump/context/metadata nào làm measurement invalid;
    không “sample anyway” sau settle timeout.
11. Giữ nguyên PID, power và settle limits trong first 7PP trial; chỉ thay contract
    structural cần thiết để đúng engineering plan.

Gate G2:

- grid contract pass;
- S-curve contract pass;
- synthetic acquisition failure test fail-closed;
- một sweep không retry/fault có:
  `371 points`, `360 analysis points`, `14800 ramp samples`;
- tất cả counters được log và analyzer kiểm tra.

### WP3 — Manifest, log schema và fail-closed validity

Files:

- `Core/Src/main.c`;
- `Core/Src/nonlinear_test.c`;
- `Core/Inc/test_profile.h`;
- `docs/motor-7pp-log-contract.md` — mới.

Boot log bắt buộc:

```text
BUILD_MANIFEST,
AppMode=MEASUREMENT,
AppProfile=7PP_ENGINEERING_LOCK_ONLY_...,
EngineeringOnly=1,
MotorPoleCount=14,
MotorPolePairs=7,
ElectricalCycleRaw=9363,
ElectricalRippleMultiple=6,
ElectricalRippleOrder=42,
ApproachMode=LOCK_ONLY,
MotionProfile=SCURVE40_ABSOLUTE_TICK_V2,
AutoBatch=0|1,
ProfileFingerprint=...,
SourceId=...
```

Per-run `META/RESULT/END` phải mang lại geometry/profile identity; analyzer phải
reject nếu boot manifest và run metadata không khớp.

Thêm các field/gate:

- `MeasurementValid`;
- `TrackingValid`;
- `AcquisitionResult`;
- `ApproachProtocol=SCURVE_LOCK_V2`;
- `ApproachStructuralValid`;
- `CapturedPoints`, `AnalysisPoints`;
- ramp/settle/transport counters;
- `ClosureErrorDeg`, `ClosureValid`;
- `AElectrical6` được lấy tại dynamic order 42;
- `EligibleForStatistics`;
- `RunRole=PRECONDITION|OFFICIAL`;
- `EngineState`/fault reason khi abort.

Không emit result “valid” nếu:

- geometry/profile mismatch;
- MA600/config gate fail;
- move-to-zero/direction fail;
- capture thiếu point;
- settle timeout/wrong-position;
- transport/jump/context error;
- Closure point không hợp lệ.

Gate G3:

- fixture hợp lệ 7PP được parser nhận;
- từng fixture bị sửa sai một field quan trọng đều bị reject;
- log 6PP cũ vẫn parse được nhưng group riêng;
- không có metric hợp lệ nếu structural gate fail.

### WP4 — Build profiles, artifact manifest và negative build

Files:

- `.cproject` — thêm cấu hình build riêng hoặc defines tương đương;
- `scripts/build_motor_7pp.ps1` — mới;
- `scripts/save_build.ps1` — mới hoặc port bản đã audit;
- `scripts/verify_motor_7pp_build.ps1` — mới.

Build wrapper phải:

1. Build sạch Debug và Release.
2. Dừng nếu có compiler warning hoặc error.
3. Xác minh profile defines trong compile command/map/ELF.
4. Chạy negative build V3+14 pole và chỉ pass khi build đó fail đúng guard.
5. Lưu:
   - HEX, ELF, MAP;
   - git commit;
   - dirty state;
   - SHA-256 của HEX;
   - profile ID/fingerprint;
   - toàn bộ define liên quan;
   - toolchain version;
   - build output của Debug/Release và negative build.
6. Không ghi đè artifact 6PP.

Output:

```text
builds/
  motor-7pp-lock-only-1run-v1-YYYYMMDD-HHMMSS/
```

Gate G4:

- profile 1-run pass Debug + Release với 0 warning;
- negative V3+7PP fail;
- SHA-256 trong manifest khớp file HEX;
- `BUILD_MANIFEST` lấy đúng cùng profile/fingerprint đã archive.

Chỉ sau G4 và checklist phần cứng P7.0 mới được flash build 1-run.

### WP5 — Smoke run 1 và optional run 2

Dùng cùng HEX 1-run và operator bấm đúng một lần cho mỗi run.

Run 1 bắt buộc quan sát trực tiếp:

- motor bắt đầu quay đúng chiều;
- không rung mạnh, kẹt, mất bước rõ rệt hoặc phát tiếng bất thường;
- current limit không tác động;
- không tăng nhiệt nhanh;
- home, ramp, settle, acquisition và Closure hoàn tất không fault;
- motor được disable sau khi kết thúc hoặc abort.

Chỉ chạy run 2 nếu run 1 không có lỗi safety/structural. Trước run 2:

- giữ nguyên HEX, JIG, motor và lần gá;
- motor-off tối thiểu 120 giây;
- bắt đầu log mới từ boot manifest hoặc đánh dấu rõ session/run;
- không thay PID, power, wiring hoặc profile.

Analyzer phải xuất một hàng/run và bảng so sánh thô giữa run 1 và run 2. Với chỉ hai
run, không dùng CV/SD làm PASS/FAIL chính thức; chỉ báo chênh lệch tuyệt đối của:

- Closure;
- `RMS_AC`;
- `Motor_Error_P2P_Deg`;
- `Motor_System_INL_Deg`;
- tracking RMS/max;
- motor-active time và settle counters.

Gate G5:

- mỗi lần bấm tạo đúng một run;
- run 2 không tự khởi động sau run 1;
- log chứng minh motor disable trong khoảng nghỉ;
- hai run đều được giữ lại, không loại run đầu;
- nếu một run lỗi thì kết luận `STOP/DIAGNOSE`, không chạy thêm để lấy trung bình.

### WP6 — Batch precondition 1 + official 10 — hoãn

WP này **không thuộc scope implementation ban đầu**. Chỉ mở lại sau khi run 1 và
run 2 chứng minh motor di chuyển an toàn, direction/motion/acquisition đều hợp lệ và
người review chủ động phê duyệt bước repeatability.

Files:

- `Core/Src/nonlinear_test.c`;
- `scripts/test_preconditioned_10run_contract.ps1` — mới;
- fixture batch 7PP — mới.

State machine:

```text
button
  -> PRECONDITION cycle, RunOrder=0, EligibleForStatistics=0
  -> cooldown 120000 ms motor-off
  -> OFFICIAL 1..10, EligibleForStatistics=1
  -> cooldown 120000 ms giữa từng cycle
  -> COMPLETE
```

Yêu cầu:

- không reset/remount giữa batch;
- precondition phải structural-valid mới chạy official;
- bất kỳ official run invalid nào làm batch invalid;
- actual cooldown và tolerance được log;
- precondition không emit official aggregate result;
- official run 1 không được loại khỏi thống kê.

Gate G6:

- fixture có đúng 11 cycle: 1 precondition + 10 official;
- analyzer chỉ thống kê 10 official;
- firmware abort khi precondition invalid;
- cooldown tính từ thời điểm `Motor_Disable()`.

### WP7 — Harmonic/signature tooling cho 7PP — hoãn

WP này không chặn smoke test chuyển động 1–2 run. Chỉ triển khai sau khi G5 pass và
cần phân tích signature/order 42; log ban đầu vẫn phải mang geometry/order 42 để dữ
liệu không bị gắn nhãn sai.

Files:

- `tools/analyze_one_turn_pattern.py` — mới/port và tổng quát hóa;
- `scripts/analyze_nonlinear_logs.ps1`;
- `scripts/test_analyze_one_turn_pattern.ps1` hoặc Python tests;
- fixtures synthetic 6PP và 7PP.

CLI:

```text
--pole-pairs 7
--electrical-ripple-multiple 6
```

Output bắt buộc:

- spectrum order 1..179;
- amplitude và energy ratio tại 7, 14, 21, 28, 35, 42, 49;
- electrical family 42, 84, 126;
- dominant order/top harmonics;
- phase coherence trong cùng một lần gá;
- `AElectrical6` đối chiếu đúng order 42;
- RMS, raw/robust P2P, INL system, Closure, post-turn residual và motion diagnostics.

Folding:

- không dùng integer sector width `360/42`;
- chọn một trong hai contract:
  1. circular phase bin + interpolation, có coverage/weight diagnostics; hoặc
  2. `fold unavailable` và vẫn xuất spectrum hợp lệ.
- không tạo file mang tên `folded_10deg` cho 7PP.

Gate G7:

- synthetic sine order 42 phục hồi đúng amplitude/phase trong tolerance;
- family 42/84/126 được xuất đúng;
- 6PP regression order 36 vẫn pass;
- tool reject pole-pair không khớp metadata;
- group key tối thiểu gồm `MotorPolePairs`, motor, jig và mount/session.

## 5. Thứ tự commit đề xuất

1. `Add shared motor geometry and 7PP compile guards`
2. `Add 7PP engineering profile contracts`
3. `Add one-degree grid and S-curve motion contract`
4. `Add fail-closed acquisition and settle diagnostics`
5. `Add build manifest and 7PP log identity`
6. `Add reproducible 7PP build and artifact packaging`
7. `Document 7PP one-run and optional second-run procedure`

Các commit batch 10-run và harmonic tooling chỉ được lập kế hoạch ở phase sau G5.

Mỗi commit phải build được và giữ default 6PP. Không gộp direct-Q16 mapping hoặc V3-7PP
vào chuỗi commit này.

## 6. Verification matrix

| Test | 6PP default | 7PP 1-run | Negative |
| --- | ---: | ---: | ---: |
| Geometry compile contract | PASS | PASS | odd pole FAIL |
| V3 guard | N/A | PASS | V3+14 pole FAIL |
| Debug build | PASS | PASS | — |
| Release build | PASS | PASS | — |
| Grid self-test | PASS | PASS | corrupted target FAIL |
| Motion/acquisition fixture | PASS | PASS | counter/settle error reject |
| Manifest/parser fixture | PASS | PASS | mismatch reject |
| One-button run count | 1 | 1 | auto/multi-run reject |

## 7. Definition of done cho code

Code implementation cho smoke test hoàn tất khi:

1. G0–G4 pass trước khi flash và G5 pass sau tối đa hai physical run;
2. default 12-pole/6PP không đổi hành vi ngoài các audit log đã chủ ý thêm;
3. một build 7PP 1-run reproducible có artifact + manifest + checksum;
4. negative build chứng minh V3 không thể chạy với 7PP;
5. analyzer tách tuyệt đối dữ liệu 6PP và 7PP;
6. không có hardcode 36/72/108 trong đường tính electrical metric động;
7. chưa có direct-Q16 hoặc V3-7PP trong first-trial build;
8. review xác nhận P7.0 vẫn là gate thủ công bắt buộc trước flash.

## 8. Ngoài phạm vi first implementation

- kết luận MA600A đạt datasheet/ISO;
- tự suy ra pole count từ spectrum;
- tune PID, power, settle threshold hoặc S-curve cho đẹp số;
- tái sử dụng B0-B bias 79/126;
- dùng Control A5 offset 7971;
- direct-Q16 mapping trước khi P7.5 được kích hoạt;
- mở rộng V3 cho 7PP;
- auto batch, precondition + 10 official run;
- đánh giá repeatability thống kê bằng CV/SD từ chỉ 1–2 run;
- tự động loại outlier/run đầu khỏi thống kê.

## 9. Điểm review bắt buộc trước khi bắt đầu code

Repository chứa engineering plan đã có các contract/schema/motion/acquisition mới hơn
branch hiện tại. Cách ít rủi ro nhất là port có chọn lọc các module và contract đã audit
từ repository đó, giữ lịch sử commit nhỏ theo WP, thay vì tái tạo thuật toán từ đầu trong
`Core/Src/nonlinear_test.c` hiện tại.

Trước WP2 cần chốt một trong hai chiến lược:

1. **Port audited measurement stack**: khuyến nghị; đưa geometry, acquisition,
   one-degree grid, Motion V2, schema/analyzer và contract tests sang branch này;
2. **Reimplement locally**: phạm vi lớn hơn, cần review công thức và fixture độc lập
   cho từng contract.

Cả hai chiến lược đều phải giữ G0–G5 cho smoke test. G6–G7 là phase sau, không được
làm tăng số run hoặc trì hoãn mục tiêu đầu tiên là xác nhận motor có di chuyển an toàn.
