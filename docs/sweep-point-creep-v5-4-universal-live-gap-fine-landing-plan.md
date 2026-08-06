# V5.4 — universal live-gap fine landing

Date: 2026-08-06

Status: IMPLEMENTED / SOFTWARE VERIFIED — HARDWARE PILOT PENDING

## 1. Kết luận thiết kế

V5.4 tổng quát hóa cơ chế đã PASS của V5.3 tại point 66 thành một policy theo trạng thái vật lý:

> Mọi sweep point đang creep đều dùng coarse step 16 raw khi còn xa và tự latch sang fine step
> 4 raw khi `abs(live gap) <= 64 raw`.

Không dùng `pointIndex`, góc cơ khí, motor ID, jig ID hoặc bảng whitelist để quyết định bật fine
landing. Danh sách crossing lịch sử chỉ dùng làm bộ kiểm chứng hardware.

Lý do:

- V5.3 đã đưa point 66 vào deadband `+/-16 raw` ở 8/8 cycle qua hai remount;
- V5.3 remount02 vẫn invalid vì point 26 chưa dùng fine landing;
- telemetry thật cho thấy crossing không chỉ thuộc class `EXTENDED`: point 5 từng crossing với
  `InitialGapRaw=35` và point 264 với `InitialGapRaw=191`, đều là `BASE`;
- hardcode danh sách điểm sẽ overfit P03/JIG7/sector hiện tại và có thể bỏ lọt điểm nguy hiểm trên
  motor, jig hoặc mounting khác;
- live-gap là đại lượng trực tiếp mà thuật toán đang điều khiển, nên phù hợp hơn mọi proxy hoặc
  lookup table theo góc.

## 2. Evidence baseline

### 2.1 V5.3 đã xác nhận cơ chế

Profile V5.3:

- coarse step: 16 raw;
- fine entry: `abs(live gap) <= 64 raw`;
- fine step: 4 raw;
- deadband: `+/-16 raw`;
- jump guard: 96 raw;
- power: 1.0;
- fine mode latch một chiều cho phần còn lại của point.

Kết quả point 66:

| Batch | FinalGapRaw của 4 cycle | Kết quả |
|---|---|---|
| P03/JIG7/remount01 | -14 / -13 / -16 / -10 | PASS 4/4 |
| P03/JIG7/remount02 | -12 / -15 / -11 / -12 | PASS 4/4 |
| Tổng | 8/8 trong deadband | PASS |

### 2.2 Failure còn lại cần giải quyết

V5.3 remount02 precondition thất bại tại point 26:

- `InitialGapRaw=-216` (`EXTENDED`);
- coarse creep tới `PreCrossGapRaw=-26`;
- một bước tiếp theo làm rotor breakaway tới `CrossingGapRaw=185`;
- observed jump: 211 raw;
- bounded recovery recross và kết thúc `FinalGapRaw=-47`;
- precondition invalid, ba official cycle bị khóa khỏi statistics.

Telemetry V5.1–V5.3 còn ghi nhận crossing tại 5, 76, 125, 175, 184, 215, 264, 284 và 344.
Các điểm một-lần này không đủ bằng chứng để hardcode thành bảng điều khiển, nhưng đủ để bác bỏ thiết
kế chỉ sửa point 26/66.

### 2.3 Sửa cách diễn giải proxy cũ

Danh sách proxy cũ có 14 point; point 0 không có record tương đương để đối chiếu, còn 13 point đánh
giá được. Trong 13 point đó:

- 2 point có trouble lặp lại mạnh: 67 và 107;
- 10 point có `TroubleScore` thấp 0–0.08;
- point 175 có một crossing thật nhưng chưa đủ dữ liệu để gọi là lỗi lặp lại.

Vì vậy không dùng tỷ lệ proxy làm input runtime cho V5.4.

## 3. Mục tiêu và non-goals

### 3.1 Mục tiêu

1. Loại phụ thuộc hardcode point 66 khỏi policy fine landing.
2. Giảm xác suất kích hoạt stick-slip khi tiến gần target tại cả BASE và EXTENDED point.
3. Giữ mọi command bounded, chỉ cho phép tối đa một reversal và không chase sau jump lớn.
4. Duy trì continuous MA600 unwrap context, acquisition cadence và deferred UART logging.
5. Giữ B0-B hoàn toàn không đổi.
6. Thu đủ telemetry để phân biệt:
   - fine landing thành công;
   - normal crossing được recovery;
   - recovery recross;
   - stick-slip jump;
   - hết budget/iteration nhưng không có sự kiện nguy hiểm.

### 3.2 Không làm trong V5.4

- không đổi power 1.0;
- không đổi ramp/S-curve, settle threshold hoặc thời gian settle;
- không đổi MA600 acquisition, filter/config hoặc công thức NL;
- không tăng raw budget 220/320;
- không thêm reversal thứ hai;
- không dùng lookup table góc, motor hoặc jig;
- không đồng thời retune H1/H2/H36, closure hoặc B0-B;
- không biến `BUDGET_EXCEEDED` thông thường thành hard-invalid trong cùng thay đổi này;
- không tối ưu thời gian test trước khi motion integrity PASS.

## 4. Feature và protocol contract

### 4.1 Feature flag

Thêm flag độc lập:

```c
#define ENABLE_SWEEP_POINT_CREEP_V54_UNIVERSAL_FINE_LANDING 0
```

Compile-time guards:

1. V5.4 yêu cầu `ENABLE_SWEEP_POINT_CREEP=1`.
2. V5.3 và V5.4 không được bật đồng thời.
3. Default source sau packaging phải là:
   - `ENABLE_SWEEP_POINT_CREEP=0`;
   - V5.3 = 0;
   - V5.4 = 0;
   - batch mặc định 1 precondition + 10 official.

V5.3 được giữ nguyên để có thể build lại baseline; không sửa hằng số hoặc protocol ID của V5.3.

### 4.2 Protocol IDs mới

Khi V5.4 bật:

- `SweepPointCreepProtocol=ADAPTIVE_GAP_BUDGET_UNIVERSAL_FINE_LANDING_V1`;
- `FineLandingProtocol=UNIVERSAL_LIVE_GAP_FINE_STEP4_JUMP_GUARD_V1`;
- `RecoveryProtocol=UNIVERSAL_FINE_SINGLE_REVERSAL_V1`;
- `FineSelectionRule=ALL_POINTS_LIVE_GAP_LE_ENTRY`;
- `TracePolicy=FIRST_INTEGRITY_FAILURE_V1`.

Không tái sử dụng ID V5.3 vì measurand motion contract đã thay đổi từ một point sang toàn sweep.

## 5. Locked motion algorithm

### 5.1 Budget class giữ nguyên

Budget class vẫn được chọn một lần từ encoder gap ngay sau settle:

```text
abs(initialGapRaw) > 200  -> EXTENDED, maxTotalRaw=320
abs(initialGapRaw) <= 200 -> BASE,     maxTotalRaw=220
```

Không dùng class này để quyết định có fine landing hay không. BASE và EXTENDED đều nhận cùng fine
profile; class chỉ quyết định raw budget và iteration guard.

### 5.2 State machine trong một point

```text
START
  |
  +-- abs(gap) <= 16 ------------------------------> OK
  |
  +-- abs(gap) > 64 -------------------------------> COARSE, step=16
  |
  +-- 16 < abs(gap) <= 64 -------------------------> FINE, step=4 (latch)
                                                        |
                                                        +-- observed delta > 96
                                                        |      -> STICK_SLIP_JUMP, STOP
                                                        |
                                                        +-- crossing outside deadband
                                                               -> one bounded fine recovery
                                                                      |
                                                                      +-- second crossing
                                                                             -> RECOVERY_RECROSSED, STOP
```

Quy tắc khóa:

1. Deadband success luôn được kiểm tra trước khi phát lệnh tiếp theo.
2. Fine mode latch: sau khi vào fine không được quay lại coarse, kể cả khi reversal.
3. Lệnh cuối được clamp theo gap còn lại; không cố ý command vượt target.
4. Sau mỗi command phải dùng fresh settled MA600 sample để cập nhật live gap.
5. Jump guard chạy trước crossing-recovery classification.
6. `STICK_SLIP_JUMP` không được recovery.
7. Normal crossing ngoài deadband chỉ được reversal đúng một lần.
8. Recovery recross dừng trước command tiếp theo.
9. Acquisition error được trả về riêng, không biến thành motion timeout.
10. `pos` tiếp tục được restore về nominal grid target sau creep để không làm lệch target của point
    tiếp theo.

### 5.3 Hằng số V5.4

| Thông số | BASE | EXTENDED | Ghi chú |
|---|---:|---:|---|
| Coarse step | 16 raw | 16 raw | giữ V5.3 |
| Fine entry | 64 raw | 64 raw | live gap |
| Fine step | 4 raw | 4 raw | giữ V5.3 |
| Deadband | 16 raw | 16 raw | giữ nguyên |
| Raw budget | 220 raw | 320 raw | không tăng |
| Max iterations | 56 | 81 | lớn hơn `ceil(budget/4)` |
| Power | 1.0 | 1.0 | không đổi |
| Jump threshold | 96 raw | 96 raw | chỉ áp dụng sau fine command |
| Recovery budget | 64 raw | 64 raw | một reversal |
| Recovery iterations | 17 | 17 | lớn hơn `ceil(64/4)` |

Compile-time assertions phải xác nhận:

```text
BASE_MAX_ITERATIONS     > ceil(220/4) = 55
EXTENDED_MAX_ITERATIONS > ceil(320/4) = 80
RECOVERY_MAX_ITERATIONS > ceil(64/4)  = 16
```

Iteration guard lớn hơn không đồng nghĩa tăng raw motion budget. `maxTotalRaw` vẫn là giới hạn cứng.

## 6. B0-B và measurement invariants

Các call site B0-B tiếp tục gọi compatibility wrapper `CreepToUnwrappedTarget()` với:

- fine profile = `NULL`;
- hằng số `NL_B0B_CREEP_*` hiện tại;
- power 1.0;
- crossing recovery disabled bằng budget/iteration bằng 0.

V5.4 không được thay đổi:

- B0-B approach output;
- `WaitForPointSettle()`;
- `RampCommandToTarget()`;
- số sample chính thức mỗi point;
- thứ tự ramp → settle → creep → capture;
- continuous unwrap context;
- công thức DATA/Error/NL/harmonic;
- UART cadence trong capture.

## 7. Telemetry và giới hạn tài nguyên

### 7.1 Per-point summary

Nâng `SWEEP_CREEP_CONFIG` và `SWEEP_CREEP_POINT` lên schema 7. Parser phải tiếp tục đọc được schema
5/6.

Mọi point có fine attempt, recovery hoặc result khác OK phải có `SWEEP_CREEP_POINT` với tối thiểu:

- budget class và selected max iterations;
- initial/final gap;
- coarse/fine/recovery iteration và correction;
- `FineLandingAttempted`, `FineLandingSucceeded`;
- crossing/recovery fields;
- `StickSlipJumpDetected`, `MaxObservedStepDeltaRaw`;
- `TraceCaptured`, `TraceCount`;
- final result.

`END` tiếp tục tổng hợp attempted/succeeded/failed, recovery, jump và max observed delta. Thêm nếu cần:

- `SweepPointCreepFineBaseAttempted`;
- `SweepPointCreepFineExtendedAttempted`;
- `SweepPointCreepTracePoint` (`-1` nếu không có failure trace).

### 7.2 Bounded step trace

Không cấp phát `360 x 100` step records. Giữ đúng một buffer 100 entry trong capture storage.

Policy:

1. Buffer được dùng như scratch cho point đang chạy.
2. Nếu point kết thúc bằng integrity failure (`TARGET_CROSSED` không recovery được,
   `RECOVERY_*` failure, `STICK_SLIP_JUMP` hoặc acquisition error), khóa buffer đó làm trace failure
   đầu tiên của sweep.
3. Sau khi khóa, các point sau vẫn chạy/log summary nhưng không được overwrite buffer.
4. Nếu cả sweep sạch, `TracePoint=-1`, `TraceCount=0`; không in step trace chỉ để chứng minh success.
5. `SWEEP_CREEP_STEP` schema 2 lấy point từ `TracePoint`, không hardcode 66.

Điều này giữ RAM bounded tương đương V5.3 và vẫn thu được bằng chứng chi tiết cho failure đầu tiên.

### 7.3 Timing/stack invariants

- Không `LogLine*`, `printf`, format chuỗi hoặc UART trong `CaptureSweep()`.
- Telemetry chỉ format/in sau `Motor_Disable()`.
- Không thêm trace array trên stack.
- Giữ `TestTask=12288` byte.
- Feature-on build phải kiểm tra `.su`; deepest static task chain không được tăng quá 256 byte nếu
  chưa có giải trình.

## 8. Validity contract

Giữ semantics V5.3:

- acquisition error: hard invalid;
- `STICK_SLIP_JUMP`: creep-integrity invalid;
- recovery timeout/budget/recross/failure: creep-integrity invalid;
- successful one-reversal recovery: valid;
- ordinary `BUDGET_EXCEEDED` không tự động trở thành hard-invalid trong V5.4;
- `FineLandingFailed` do hết ordinary budget là diagnostic/effectiveness failure, không được trá hình
  thành acquisition failure.

`EligibleForStatistics` chỉ được bật khi precondition hợp lệ và toàn bộ validity contract hiện hữu
đạt. Plan hardware bên dưới áp thêm gate promotion nghiêm hơn firmware eligibility.

## 9. Software implementation phases

### V5.4-S0 — source contract

- thêm feature flag, protocol IDs và compile guards;
- thay điều kiện `pointIndex == 66` bằng policy profile áp dụng cho mọi creep point;
- chọn max iteration 56/81 theo budget class;
- giữ implementation `CreepToUnwrappedTargetProfiled()` và thứ tự jump-before-recovery;
- xóa mọi phụ thuộc point index khỏi V5.4 motion decision.

### V5.4-S1 — bounded telemetry

- tổng quát hóa fine summary arrays hiện có;
- thay `creepV53TraceCount`/hardcoded point 66 bằng first-integrity-failure trace metadata;
- schema 7/step schema 2;
- cập nhật MATLAB parser để field mới optional và tương thích schema 5/6.

### V5.4-S2 — contract tests

Tạo `scripts/test_sweep_point_creep_v5_4_contract.ps1` và kiểm tra:

1. V5.4 không compile nếu creep tổng bị tắt.
2. V5.3/V5.4 mutual exclusion.
3. Không có `pointIndex == constant` trong V5.4 selection block.
4. BASE và EXTENDED đều truyền non-NULL fine profile.
5. Max iteration 56/81 và budget 220/320 đúng.
6. Fine latch và jump-before-recovery giữ nguyên.
7. Chỉ một reversal; recross dừng trước command tiếp theo.
8. B0-B vẫn có đúng hai call wrapper cũ và fine disabled.
9. Không UART trong `CaptureSweep()`.
10. Trace buffer duy nhất, không per-point trace array.
11. Schema/parser MATLAB đọc được V5.1/V5.2/V5.3/V5.4.
12. Default-off, V5.3-on và V5.4-on đều compile.

### V5.4-S3 — build/package

Build label dự kiến:

```text
sweep-point-creep-v5-4-universal-live-gap-fine-landing-fast3-20260806
```

Đóng gói `.hex/.elf/.map`, `build_info.txt`, `SHA256SUMS.txt`; sau đó restore source default-off và
10 official.

## 10. Hardware validation

### 10.1 Pilot A — known failure mounting

Thiết bị: P03/JIG7, ưu tiên mounting tương đương remount02. Không tháo lắp trong batch.

Chạy một batch FAST3:

- 1 precondition;
- 3 official.

Hard safety gates, phải đạt 4/4 cycle:

- acquisition/transport clean;
- `TargetCrossed=0` hoặc mọi crossing đều recovered thành công;
- `RecoveryFailed=0`;
- `RecoveryRecrossed=0`;
- `StickSlipJump=0`;
- cooldown heartbeat đủ và batch hoàn tất;
- stack high-water tối thiểu 768 words;
- precondition valid;
- `OfficialValid=3/3`.

Mechanism gates:

- point 26 và 66: `FineLandingAttempted=1`, `FineLandingSucceeded=1`;
- point 26 và 66: `abs(FinalGapRaw) <= 16` ở 4/4 cycle;
- mọi historical crossing point xuất hiện trong telemetry phải không còn kết thúc bằng crossing,
  recross hoặc jump;
- `FineLandingFailed=0` là gate promotion. Nếu khác 0 nhưng safety vẫn sạch, phân loại MIXED, không
  chỉnh budget ngay trong cùng phase.

Measurement observation gates:

- tính NLAvg, System INL, RMS_AC, A36 và full 360-point curve cho 3 official;
- mục tiêu repeatability ban đầu: NLAvg CV không vượt baseline V5.3 remount01 (~5.7%);
- không kết luận bằng một giá trị NL duy nhất: bắt buộc xem curve correlation, centered RMSE và vị trí
  top-5/bottom-5;
- NL mean có thể dịch vì motion endpoint đã thay đổi; một mean shift không tự động là FAIL nếu curve
  repeatable và motion sạch.

### 10.2 Pilot B — remount repeatability

Chỉ chạy nếu Pilot A PASS. Thực hiện thêm hai remount độc lập, mỗi remount 1 pre + 3 official.

Gate:

- lặp lại toàn bộ hard safety/mechanism gate;
- point 26/66 đạt tổng 12/12 cycle;
- không xuất hiện point failure mới bị che bởi hardcoded policy;
- between-remount delta phải được so với `2.77 x pooled within-batch SD`, không dùng một ngưỡng đoán
  trước;
- full-curve shift phải được phân loại thành mounting shift hay motion regression trước khi promote.

### 10.3 Pilot C — cross-product

Chỉ chạy nếu hai remount bổ sung PASS. Test tối thiểu một motor thứ hai trên cùng JIG7, ưu tiên P08
vì đã có baseline V4/V5. Sau đó mới mở rộng cross-jig.

V5.4 chỉ đủ điều kiện thay baseline khi:

- ít nhất 2 motor pass;
- không motor nào có integrity failure;
- fine success không phụ thuộc point-index cụ thể;
- NL/full-curve repeatability không xấu hơn baseline tương ứng.

## 11. Decision tree

### PASS

Tất cả safety, mechanism và repeatability gates đạt:

- giữ V5.4 làm candidate;
- chuyển sang remount/cross-product;
- sau đó mới verify lại H1/H2/H36 sạch.

### Point 26/66 PASS nhưng point khác jump/recross

- firmware phải invalid đúng và lưu first-failure trace;
- không tăng jump threshold;
- không tăng recovery budget;
- phân tích step trace của point mới trước khi tạo phase kế tiếp.

### Safety sạch nhưng `FineLandingFailed>0`

- phân loại MIXED/EFFECTIVENESS;
- không promote;
- tách xem failure do ordinary raw budget đã cạn trước khi vào fine hay do fine response gần zero;
- mọi thay đổi budget/accounting là V5.5 riêng, không sửa lẫn vào V5.4.

### Motion PASS nhưng NL/full curve không repeatable

- không retune fine step theo scalar NL;
- đối chiếu curve và mounting fingerprints H1/H2;
- kết luận motion và measurand thành hai gate độc lập.

### Acquisition/transport fault

- rerun cùng binary và mounting;
- không đổi motion constants dựa trên batch acquisition-bẩn.

### Time/heat tăng quá mức

- ghi nhận tổng fine iterations, duration và nhiệt thực tế;
- không tối ưu trong V5.4;
- chỉ sau khi motion PASS mới thử giảm fine-entry window hoặc scheduler optimization trong phase riêng.

## 12. File dự kiến thay đổi

- `Core/Src/nonlinear_test.c`;
- `scripts/test_sweep_point_creep_v5_4_contract.ps1` (mới);
- `scripts/test_sweep_point_creep_v5_3_contract.ps1`;
- `scripts/test_b0b_creep_contract.ps1`;
- `analysis/matlab/nl/parse_sweep_creep_log.m`;
- `analysis/matlab/nl/analyze_sweep_creep_batch.m` nếu cần field schema 7;
- `analysis/matlab/tests/test_nl_stability_analysis.m`;
- `docs/session-summary-2026-08-06.md`;
- graphify outputs sau khi code hoàn tất.

## 13. Definition of Done

V5.4 chỉ hoàn tất khi:

- [x] plan được audit trước code;
- [x] runtime selection không chứa point whitelist/index;
- [x] BASE/EXTENDED fine iteration guards đúng bằng chứng toán học;
- [x] B0-B và measurement cadence không đổi;
- [x] trace RAM bounded một buffer;
- [x] default/V5.3/V5.4 Release build pass;
- [x] toàn bộ 31 PowerShell regression pass;
- [ ] MATLAB runtime regression pass — schema-7/schema-2 synthetic test đã cập nhật, nhưng máy build
  hiện tại không có lệnh MATLAB để thực thi;
- [x] `.su`/stack audit pass: deepest static chain 7664/12288 byte, margin 4624 byte;
- [x] artifact FAST3 có checksum và manifest tại
  `builds/sweep-point-creep-v5-4-universal-live-gap-fine-landing-fast3-20260806/`;
- [ ] Pilot A đạt 1 precondition + 3/3 official valid;
- [ ] point 26/66 đạt 4/4 endpoint trong deadband;
- [ ] không crossing failure, recross hoặc jump;
- [ ] full-curve/NL repeatability được đánh giá độc lập với motion gate;
- [x] source được restore về default-off/10 official sau packaging.
