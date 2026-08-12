# Kiến trúc hệ thống đo nonlinear — data flow, call graph, định nghĩa phép đo

Tài liệu này là output #1 của audit toàn diện, dựa trên đọc trực tiếp
`Core/Src/*.c`, `Core/Inc/*.h`, `docs/*.md` hiện có trong repo `jigmotor`.
**Không có thư mục `GremsyMotorTester-MainBoard` trong workspace này**
(`Glob` xác nhận 0 kết quả) — mọi tham chiếu tới file `gremsy*.c/.h` trong
tài liệu này là dữ liệu người dùng dán trực tiếp vào chat ở phiên trước, để
đối chiếu, không phải một phần của repo `jigmotor`.

## 1. Data-flow tổng thể

```text
Motor command (electrical, open-loop)
  │  int32_t pos (raw-count scale, 0-65535 = 1 vòng điện áp dụng qua PWM)
  ▼
Electrical phase generation
  │  MotorPwm_SetElectricalPos(uint16_t pos, float power)  [motor_pwm.c]
  │  stepA/B/C = (pos + offset_ABC) % MOTOR_COUNT_PER_CYCLE
  ▼
Sine LUT (tính trực tiếp bằng sinf(), KHÔNG dùng bảng LUT tĩnh)
  │  MotorPwm_PhaseValue(stepInCycle, power) = (sinf(2π·step/count_per_cycle)*0.5+0.5)*power
  ▼
PWM (TIM1 CH1/2/3, period=2154, 168MHz timer clock → ~77.958kHz)
  │  __HAL_TIM_SetCompare()
  ▼
Motor driver (3-phase, không có current sense/feedback loop điện)
  ▼
Rotor mechanical response (KHÔNG có mô hình/feedback nào xác nhận vị trí
  cơ khí thật khớp lệnh điện — đây là gốc rễ của ALG-003)
  ▼
Encoder magnet (gắn end-of-shaft) → MA600A (TMR bridge, hardware digital
  filter FW=0x05 mặc định → 12.5-bit noise-free resolution / 12kHz bandwidth
  theo Table 1 datasheet, ĐÃ audit khớp cả 3 jig — xem
  docs/hardware-validation-checklist.md)
  ▼
SPI (SPI1, mode 3, 25MHz max theo datasheet; cấu hình thật baud/16 trên
  APB2=84MHz → 5.25MHz)
  │  MA600_ReadRawChecked(uint16_t *raw, MA600_ReadMeta_t *meta)  [ma600.c]
  │  HAL_SPI_TransmitReceive(&hspi1, tx={0,0}, rx, 2 byte, timeout=10ms)
  │  KIỂM TRA return status (HAL_TIMEOUT/HAL_ERROR → MA600_Result_t lỗi,
  │  KHÔNG BAO GIỜ trả 0 để biểu diễn lỗi)
  ▼
Unwrap (per-consumer context, không dùng chung)
  │  MA600_UnwrapUpdate(ctx, raw, acceptedCycle, maxJumpRaw, &outUnwrapped)  [ma600.c]
  │  delta = raw - ctx->lastRaw; wrap-correct nếu |delta|>32768;
  │  reject nếu |delta sau wrap| > maxJumpRaw (do caller truyền, KHÔNG có
  │  một ngưỡng chung toàn hệ thống)
  ▼
Retry/counter layer
  │  MA600_AcquireSample(ctx, maxJumpRaw, maxAttempts, &out)  [ma600_acquisition.c]
  │  retry tới maxAttempts lần nếu SPI lỗi hoặc jump bị reject
  ▼
Averaging (CHỈ trong đường legacy hiện tại — xem ALG-001)
  │  CaptureSweep(): vòng lặp 64× MA600_AcquireSample → cộng dồn độ →
  │  encAngle = sum/64  [nonlinear_test.c]
  ▼
Nonlinear error
  │  error_i = signedTargetDeg_i − (encAngle_i − angleOffset)  [nonlinear_test.c]
  ▼
Max/Min, P2P, RMS, harmonic (DFT bậc cố định 1,2,3,6,9,12,18,27,36,45,72,108)
  │  ComputeSweepStats/ComputeHarmonicFull/ComputeResidualRms/
  │  ComputeModelMetricsByOrders  [nonlinear_test.c]
  ▼
Final result (Motor_Error_P2P_Deg, Motor_System_INL_Deg=P2P/2,
  legacyStats.robustPP → "Nonlinear N Angle")
  ▼
UART log (USART3, chỉ SAU Motor_Disable())
  │  PrintSweepLog() → LogLine/LogLineLarge → HAL_UART_Transmit  [nonlinear_test.c]
```

## 2. Bảng chi tiết từng block

| Block | Input | Output | Đơn vị | Kiểu | Sampling rate | Filter | State | Delay | Nguồn lỗi | Validity check | Failure handling |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Electrical phase gen | `pos` (raw count) | 3 PWM compare | count → 0-2154 | `uint16_t`/`float` | theo osDelay ramp (1ms/bước) | không | không (hàm thuần) | 0 | lượng tử hóa `sinf`+cast `uint16_t` | không | không |
| PWM/driver | compare value | dòng pha thật | A | tương tự | 77.958kHz | không (phần mềm) | HW timer | 0 | deadtime, mismatch driver | **UNKNOWN – NEED HARDWARE VERIFICATION** | không |
| Rotor | dòng pha | vị trí cơ khí thật | độ | vật lý | liên tục | cơ khí (quán tính) | vị trí+vận tốc thật | không xác định | cogging, friction, preload | **không có phép đo độc lập nào** | không |
| MA600A | từ trường | angle raw 16-bit | count (0-65535) | uint16_t | 800kHz refresh (theo datasheet), FW=5 → noise-free ~12kHz bandwidth | hardware digital filter FW=5 (mặc định, đã audit khớp 3 jig) | nội bộ chip | ~ vài chục µs (theo Table 1, FW=5 → latency thấp) | INL riêng chip (typ 0.2°/max 0.6° theo datasheet), field strength | STATUS register (ERRCRC/ERRMEM/ERRPAR/NVMB) | `MA600_ReadStatus()` có, nhưng KHÔNG được gọi trong vòng lặp `CaptureSweep` (chỉ ở batch-precheck và idle task) |
| SPI transaction | lệnh đọc | raw 16-bit + meta | count | uint16_t | theo caller (không cố định trong legacy path) | không | không (pure function) | timeout 10ms max | SPI timeout/lỗi bus | `HAL_StatusTypeDef` được check đầy đủ | trả `MA600_Result_t` lỗi cụ thể, không giả lập giá trị |
| Unwrap | raw + ctx cũ | int64 unwrapped | count | int64_t | mỗi accepted sample | không | `MA600_UnwrapContext_t` (per-consumer, KHÔNG dùng chung giữa PID/settle/sweep) | 0 | reject sai (ngưỡng quá chặt/quá lỏng tùy caller) | jump threshold do caller truyền | reject: không đổi state, chỉ tăng `rejectedCount` |
| Averaging (legacy) | 64 unwrapped | `encAngle` (float, độ) | độ | float32 | 64 SPI transaction độc lập, back-to-back | **arithmetic mean, KHÔNG có filter phần mềm nào khác** | tích lũy `angleSampleSum` cục bộ trong `CaptureSweep` | 0 delay giữa mẫu (có chủ đích, đã test không đổi hình dạng) | ALG-001 (raw riêng biệt) | không | không |
| Error calc | `encAngle`, `angleOffset`, `pos` | `error_i` | độ | float32 | 1/điểm | không | `angleOffset` (mẫu đơn, cố định cả sweep) | 0 | ALG-003 (whole-system), offset là mẫu đơn không average | `measurementValid` (structural+tracking) | điểm vẫn được lưu dù không settle đúng hạn (chỉ tăng `notSettledCount`) |
| Max/Min/P2P | mảng `errorSamples[0..255]` | `rawPP`, `robustPP` | độ | float32 | 1 lần/sweep (sort) | không | scratch buffer `nlSortScratch` | ~vài ms (sort O(n²)) | outlier đơn lẻ ảnh hưởng `rawPP` (không ảnh hưởng `robustPP`) | không | không |
| Final result | stats | `Motor_System_INL_Deg` v.v. | độ | float32 | 1/sweep | không | không | `FeatureComputeTimeMs` (~570ms thực đo) | xem ALG-XXX | `measurementValid`/`trackingValid` | sweep invalid vẫn tính (chỉ đổi field `Status=INVALID`, KHÔNG tuân thủ đúng "không xuất field official" — xem ALG-011 |

## 3. Call graph cho 9 luồng yêu cầu

### 3.1 Start nonlinear test
```
NonlinearBatch_OnButtonPress() [nonlinear_test.c]
 → MA600_PrecheckAndClearStatus() [ma600.c]
 → RunBatchSweep() → NonlinearTest_Run(...)
    → ReadLogAndGateConfiguration("BATCH_PRE_MOTOR")
       → MA600_ReadConfiguration() [ma600.c]
       → MA600_ValidateConfigurationLockedGate() [ma600.c]
    → Motor_Enable() [motor.c → motor_pwm.c]
```

### 3.2 Move-to-zero
```
MoveToZeroAndCheckDirection() [nonlinear_test.c]
 → Motor_MoveToAngle(0.0f, &error) [motor.c]  -- lặp trong vòng for(;;) có osDelay(2ms)
    → MA600_AcquireSample(&pidAcquisition, MOTOR_PID_MAX_JUMP_RAW=8192, 3, &sample)
       → MA600_ReadRawChecked() → MA600_UnwrapUpdate()
    → PositionController_Update(&positionController, error)  [position_controller.c]
    → MotorPwm_SetElectricalPos() [motor_pwm.c]
 → so sánh fabsf(error) < NL_MOVE_ZERO_ERROR_DEG(0.10°), cần >500 tick liên tiếp
 → so sánh fabsf(error)-fabsf(errorBefore) > 90° → NL_ZERO_DIRECTION_ERROR
 → timeout 20000ms → NL_ZERO_TIMEOUT
```

### 3.3 Move tới từng test point (ramp)
```
CaptureSweep() [nonlinear_test.c], vòng ramp trong while(sweptAngleDeg<370)
 → RampCommandToTarget(): command từ S-curve profile (mặc định) hoặc bước
   cố định (nhánh legacy); Motor_SetElectricalPos(pos,1.0f)
   -- STALE (2026-08-12): dòng "KHÔNG có lời gọi MA600 nào trong vòng này"
      không còn đúng. MA600_AcquireSample() ĐƯỢC gọi ở mỗi micro-step (cả
      2 nhánh) để ghi observability/backtrack — nhưng sample KHÔNG quay lại
      *pos*, ramp vẫn là open-loop actuation thuần túy. Xem ALG-005
      correction note trong nonlinear_algorithm_audit.md và
      docs/open-loop-nl-direction-correction-handoff-2026-08-12.md mục 5.3/7.1.
```

### 3.4 Đọc encoder
```
MA600_ReadRawChecked(uint16_t *raw, MA600_ReadMeta_t *meta) [ma600.c]
 → snapshot DWT->CYCCNT + TIM1->CNT (trước /CS)
 → HAL_SPI_TransmitReceive(&hspi1, {0,0}, rx, 2, 10ms)
 → check HAL_StatusTypeDef → MA600_Result_t
```

### 3.5 Unwrap
```
MA600_UnwrapUpdate(ctx, raw, acceptedCycle, maxJumpRaw, &out) [ma600.c]
 → nếu !ctx->initialized: raw làm anchor, chấp nhận vô điều kiện
 → else: delta=raw-ctx->lastRaw; wrap-correct nếu |delta|>32768;
         reject nếu |delta| > maxJumpRaw (không update state)
         accept: cập nhật lastRaw/unwrappedRaw/lastAcceptedCycle/acceptedCount ATOMIC
```

### 3.6 Average sample
```
CaptureSweep() [nonlinear_test.c]
 → for i in 0..63: MA600_AcquireSample(&sweepAcquisition, NL_SWEEP_MAX_JUMP_RAW=1821, 3, &sample)
                    angleSampleSum += MA600_UnwrappedRawToDegrees(sample.unwrappedRaw)
 → encAngle = angleSampleSum / 64
```

### 3.7 Tính error
```
sweptAngleDeg = 360×|pos|/65536
signedTargetDeg = ±sweptAngleDeg (theo direction)
error = signedTargetDeg − (encAngle − angleOffset)
```

### 3.8 Tính max/min
```
CaptureSweep(): errorMaxTrack/errorMinTrack cập nhật TRỰC TIẾP theo error_i
  (khởi tạo -1e9f/1e9f, không phải 0 — xem ALG-009 xác nhận KHÔNG có bug zero-init)
ComputeSweepStats() [nonlinear_test.c]: sort toàn bộ errorSamples[0..255] vào scratch,
  robustPP = avg(top-5) - avg(bottom-5); rawPP = scratch[N-1]-scratch[0]
```

### 3.9 Xuất kết quả
```
NonlinearTest_Run() → Motor_Disable() → PrintSweepLog(&nlCaptures[i])
 → LogLineLarge/LogLine → HAL_UART_Transmit(&huart3, ..., timeout 100-200ms)
```

## 4. Định nghĩa phép đo chính xác (đối chiếu code)

Xem phân tích công thức đầy đủ đã trình bày trong chat (Step 3 của audit) —
tóm tắt: `error_i = Reference(electrical command) − Measured(MA600A)`,
KHÔNG có reference cơ khí độc lập. `Motor_Error_P2P_Deg = max−min` (0..255);
`Motor_System_INL_Deg = P2P/2` (CÓ chia 2 — xác nhận đúng); `"Nonlinear N
Angle"` dùng `robustPP` (top/bottom-5 trung bình), KHÁC với `rawPP` dùng
cho `Motor_Error_P2P_Deg` — hai con số P2P này không bằng nhau trên cùng
một sweep.
