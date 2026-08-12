# Nonlinear Algorithm Audit — toàn bộ finding, theo mục 6.1-6.13

Tiếp nối 5 finding đã trình bày trong chat (ALG-001..ALG-005). Mỗi mục
6.1-6.13 dưới đây được xác nhận hoặc bác bỏ trực tiếp bằng code, không mặc
định đúng. Các mục "VERIFIED CORRECT" nghĩa là đã kiểm tra kỹ và **không**
tìm thấy lỗi — vẫn ghi evidence đầy đủ theo yêu cầu, không phải bỏ qua.

## 6.1 — Reference và target

Đã trình bày đầy đủ ở **ALG-003** (chat trước). Bổ sung: cogging, friction,
motor torque, driver mismatch và tracking error **đều bị gộp chung vào
`error_i`**, không có cơ chế nào trong `CaptureSweep()` tách các thành phần
này — hệ quả trực tiếp của việc không có reference cơ khí độc lập, không
phải một bug riêng lẻ có thể "sửa" bằng code.

## 6.2 — Pole-pair mapping

### Finding ID: ALG-006
**Title:** `MOTOR_COUNT_PER_CYCLE` không chia hết 65536 cho 6 → dư 2 count/vòng
**Severity:** LOW (xác định, nhỏ, không đổi giữa các lần chạy)
**Evidence:**
- File: `Core/Src/motor_pwm.c` (và lặp lại y hệt ở `Core/Src/motor.c`)
- Function: định nghĩa macro, không trong một hàm cụ thể
- Lines: `#define MOTOR_COUNT_PER_CYCLE (MOTOR_ENCODER_COUNT / MOTOR_POLE_PAIRS + 1)`

**Current implementation:** `65536 / 6 = 10922` (chia nguyên, làm tròn
xuống) `+ 1 = 10923`.

**Mathematical analysis:** `6 × 10923 = 65538 ≠ 65536`. Sau đúng "6 chu kỳ
điện" theo cách tính của firmware, góc commutation đã tiến thêm 65538
count trong khi 1 vòng cơ khí thật chỉ là 65536 count — dư **+2 count
(~0.011°)** mỗi vòng, tích lũy nếu quay nhiều vòng liên tục (ví dụ trong
move-to-zero nếu xuất phát xa gốc).

**Effect on measurement:** không ảnh hưởng trực tiếp `errorSamples[]` (vì
sweep dùng `pos` raw-count tuyệt đối, không dùng `MOTOR_COUNT_PER_CYCLE` để
tính vị trí/target) — chỉ ảnh hưởng độ mượt/độ chính xác pha commutation
tại một `pos` cho trước, một nguồn gợn sóng cực nhỏ, không phải nguồn chính
của A36 (xem ALG-007 mới là nguồn thật của A36).

**Recommended fix:** không cấp thiết ở mức 0.011°/vòng; nếu cần loại bỏ
hoàn toàn, có thể tính commutation phase bằng modulo trực tiếp trên
`65536` thay vì qua `MOTOR_COUNT_PER_CYCLE` trung gian.

**Confidence:** Confirmed by code (tính tay xác nhận).

---

### Finding ID: ALG-007
**Title:** Số cặp cực hardcode, lặp ở 2 file, không log — rủi ro nếu test motor khác PM1505
**Severity:** LOW hiện tại (đã xác nhận đúng cho P03/P05) / **CRITICAL nếu từng bị mismatch**
**Evidence:**
- File: `Core/Src/motor.c` VÀ `Core/Src/motor_pwm.c` (định nghĩa độc lập, không dùng chung 1 header)
- Lines: `#define MOTOR_POLE_PAIRS 6` ở cả hai file

**Current implementation:** Đối chiếu `gremsyProfiles_PM1505.h` do người
dùng cung cấp: `MOTOR_NUM_POLSE=12` (12 cực = 6 cặp cực) — **khớp** với
`MOTOR_POLE_PAIRS=6` trong `jigmotor`. Không có mismatch hiện tại cho P03
lẫn P05 (cả hai đều test motor PM1505 theo comment gốc `motor.h`: *"PM1505
(12-pole) test motor"*).

**Tính thử hậu quả nếu mismatch (7 cặp cực cấu hình, motor thật 6 cặp cực)**:
- `MOTOR_COUNT_PER_CYCLE(cấu hình 7)` = `65536/7+1 = 9362+1 = 9363`.
- Firmware sẽ hoàn thành 1 chu kỳ sin thương mại mỗi 9363 count, tức
  `65536/9363 ≈ 7.0` chu kỳ điện mỗi vòng cơ khí — nhưng motor thật (6 cặp
  cực) chỉ cần đúng 6 chu kỳ điện/vòng.
- Tỷ lệ lệch 7:6 nghĩa là từ trường stator quay nhanh hơn đồng bộ so với
  rotor thật → mất đồng bộ (loss-of-sync) kinh điển của PMSM chạy sai bảng
  commutation: torque ripple lớn, rung mạnh, khả năng không quay được mượt
  hoặc quay giật cục — không phải "sai nonlinearity tinh vi" mà là hỏng
  chức năng rõ ràng, gần như chắc chắn sẽ bị `NL_TRACKING_RMS/MAX_VALID_DEG`
  (15°/30°) bắt được và đánh `TrackingValid=0`.

**Effect on measurement:** hiện tại KHÔNG có ảnh hưởng (số cặp cực đúng).
Rủi ro là về sau: không có gate nào xác nhận số cặp cực khớp motor thật,
và `META` không ghi lại số cặp cực đang dùng để tự mô tả log.

**Recommended fix:** gộp `MOTOR_POLE_PAIRS` về một định nghĩa duy nhất; ghi
vào `META` (`MotorPolePairs=6`); nếu jig có kế hoạch test motor khác cực,
tham số hóa theo `MOTOR_ID` (tiền lệ: `gremsyProfiles_PM1505.h` đã làm đúng
việc này ở codebase cũ qua `MOTOR_NUM_POLSE`).

**Confidence:** Confirmed by code (hardcode) + confirmed by profile file
(giá trị khớp) + tính toán hậu quả hypothetical (chưa xảy ra thật —
**UNKNOWN – NEED HARDWARE VERIFICATION** nếu muốn xác nhận triệu chứng thật
khi mismatch).

## 6.3 — Full-scale và unwrap

**VERIFIED CORRECT** — không tìm thấy lỗi.

- File: `Core/Src/ma600.c`, function `MA600_UnwrapUpdate`, lines 239-291.
- Logic: `delta = raw - lastRaw`; `if (delta > 32768) delta -= 65536; else
  if (delta < -32768) delta += 65536;`.

Chạy đúng 4 test vector yêu cầu:

| Old | New | delta thô | Sau wrap-correct | Kỳ vọng đúng | Code cho ra |
| --- | --- | --- | --- | --- | --- |
| 65530 | 5 | −65525 | +11 | +11 (tiến 11 bước qua wrap) | **Khớp** |
| 5 | 65530 | +65525 | −11 | −11 (lùi 11 bước qua wrap) | **Khớp** |
| 65535 | 0 | −65535 | +1 | +1 | **Khớp** |
| 0 | 65535 | +65535 | −1 | −1 | **Khớp** |

**Quy ước biên đáng ghi chú** (không phải bug): tại đúng `delta=+32768`
hoặc `delta=−32768` (nửa vòng chẵn), điều kiện dùng `>`/`<` nghiêm ngặt nên
KHÔNG áp dụng wrap-correct ở đúng ranh giới này — đây là cách chọn "cung
ngắn hơn" tiêu chuẩn, và trong thực tế không bao giờ chạm ranh giới này vì
mọi `maxJumpRaw` thật dùng trong hệ thống (1821, 8192, 32768 cho idle) đều
được áp dụng SAU bước wrap-correct này như một bộ lọc riêng.

## 6.4 — Move-to-zero

**VERIFIED CORRECT** — có dùng `fabsf` đầy đủ, không tìm thấy bug thiếu trị tuyệt đối.

- File: `Core/Src/nonlinear_test.c`, function `MoveToZeroAndCheckDirection`, lines 849-922.
- Line 869: `if (fabsf(error) < NL_MOVE_ZERO_ERROR_DEG)` — dùng đúng `fabsf`.
- Line 883: `if (fabsf(error) - fabsf(errorBefore) > NL_CHECK_DIR_ANGLE_DEG)` — dùng đúng `fabsf` cho cả hai vế.

Với 4 ví dụ yêu cầu (`NL_MOVE_ZERO_ERROR_DEG=0.10`):
- `error=+0.05°` → `fabsf=0.05<0.10` → tính là "gần zero", tăng `settled`. Đúng.
- `error=-0.05°` → `fabsf=0.05<0.10` → tăng `settled`. Đúng (nếu thiếu `fabsf`, `-0.05<0.10` cũng đúng ở case này nên không lộ bug, nhưng...).
- `error=-2°` → `fabsf=2.0`, không `<0.10` → reset `settled=0`. Đúng. (Nếu thiếu `fabsf`: `-2 < 0.10` **cũng đúng** → sẽ SAI coi là đã hội tụ — đây là ví dụ lộ rõ bug giả định, nhưng code hiện tại đã dùng `fabsf` nên không xảy ra.)
- `error=-40°` → tương tự, `fabsf=40`, đúng bị coi là chưa hội tụ.

Số sample settle: `NL_MOVE_ZERO_SETTLE_TICKS=500` tick liên tiếp (mỗi tick cách nhau `osDelay(2ms)` → ~1s hội tụ liên tục); timeout `20000ms`; không có target-proximity riêng (chính error này đã là proximity-check); integral không bị reset thủ công trong hàm này (chỉ ở `PositionController_Update`, xem 6.11); hướng tiếp cận không bị ràng buộc (PID có thể approach từ cả hai phía).

## 6.5 — Settling tại từng test point

Đã trình bày ở **ALG-002**. Bổ sung phân biệt tĩnh/động theo yêu cầu:

- **Static nonlinear error**: phần `error_i` phản ánh đúng vị trí đã ổn định thật (khi `WaitForPointSettle` pass đúng nghĩa).
- **Dynamic tracking/transient error**: phần dư do đọc đúng lúc còn dao động — hiện tại chỉ được phát hiện gián tiếp qua `NL_POINT_SETTLE_TIMEOUT_MS=100` (đếm vào `notSettledCount`, KHÔNG loại điểm đó khỏi `errorSamples[]`).

Đối chiếu với `gremsyProfiles_PM1505.h` (`MOTOR_NONLINEAR_SLEEP_TIME=5ms`
cố định, không settle-check) — `jigmotor` đã thay bằng settle-detection
thật (poll 1ms × 8 lần ổn định liên tiếp), giải quyết đúng rủi ro
inertia/friction/damping khác nhau giữa các jig gây delay cố định sai lệch
— nhưng ALG-002 (thiếu target-proximity) vẫn là lỗ hổng còn lại.

## 6.6 — Acquisition và averaging

**VERIFIED CORRECT** (độc lập thật) với một điểm mở cần xác nhận thêm.

- File: `Core/Src/ma600.c`, function `MA600_ReadRawChecked`, lines 101-151: **mỗi lời gọi là một `HAL_SPI_TransmitReceive` thật**, không có biến cache/static nào giữ giá trị giữa các lần gọi.
- Kiến trúc `jigmotor` là **một task duy nhất (`NonlinearEngine_Task`) sở hữu toàn bộ SPI1/motor trong lúc test** — khác hẳn kiến trúc gremsy cũ (`TaskEncoder` nền cập nhật `encoderAngle` mỗi ~1ms, các nơi khác chỉ đọc biến cache). Do đó **không có race condition/stale-sample giữa các task** trong đường đo `CaptureSweep` (đã verify `StartDefaultTask` tự `continue`/skip khi `NonlinearEngine_IsBusy()`, `main.c:829-833`).
- 64 mẫu mỗi điểm là **64 transaction SPI độc lập thật, back-to-back, không có inter-sample delay** (có chủ đích, xem comment gốc `nonlinear_test.c`).

**Điểm mở, chưa kết luận**: các mẫu không được đồng bộ với pha PWM (không
có cơ chế "đọc tại một điểm cố định trong chu kỳ PWM"). Đây là thí nghiệm
đã được lên kế hoạch (`ma600-canonical-pipeline-improvement-plan.md`, Phase
6-B: "PWM-phase-stratified sampling") nhưng **chưa chạy**. **UNKNOWN – NEED
HARDWARE VERIFICATION** cho việc có bias thật theo pha PWM hay không.

## 6.7 — Filtering

**VERIFIED — chuỗi filter đơn giản hơn và ít rủi ro hơn codebase gremsy cũ.**

- Hardware filter: MA600A digital filter `FW=0x05` (mặc định, đã audit khớp cả 3 jig, `docs/hardware-validation-checklist.md`) — theo Table 1 datasheet: 12.5-bit noise-free resolution, latency cancellation có, bandwidth ~12kHz.
- Software: **không có IIR nào** trong `jigmotor`. `CaptureSweep()` chỉ cộng dồn `angleSampleSum += MA600_UnwrappedRawToDegrees(...)` rồi chia cho 64 — một **boxcar/moving-average không đệ quy (FIR bậc 64, hệ số bằng nhau 1/64)**, KHÔNG mang trạng thái/memory sang điểm kế tiếp (`angleSampleSum`/`sampleCount` cục bộ trong từng điểm, reset về 0 khi bắt đầu điểm mới).

**Transfer equation:**
```text
y[n] = (1/64) Σ x[n-k], k=0..63     (FIR, không hồi quy, không lag mang sang điểm sau)
```

So sánh trực tiếp với `gremsyEncoder.c` cũ:
```text
y[n] = 0.4·y[n-1] + 0.6·x[n]         (IIR, MANG lag từ điểm trước, chồng lên chính filter cứng FW=12 của sensor)
```

**Kết luận**: `jigmotor` **average đúng raw sample độc lập**, không average
output của một IIR — trả lời trực tiếp câu hỏi cuối mục 6.7. Đây là một cải
tiến thật so với codebase cũ, không phải một finding cần sửa.

## 6.8 — SPI validity

**VERIFIED CORRECT** — không có transaction lỗi nào được phép cập nhật state.

- File: `Core/Src/ma600.c`, `MA600_ReadRawChecked` (kiểm tra `HAL_StatusTypeDef`, trả `MA600_RESULT_SPI_TIMEOUT`/`_SPI_ERROR`, không bao giờ trả raw giả).
- File: `Core/Src/ma600.c`, `MA600_UnwrapUpdate`, lines 261-278: nhánh reject (`absoluteDelta > maxJumpRaw`) chỉ `ctx->rejectedCount++`, **return trước khi chạm bất kỳ field state nào khác** (`lastRaw`/`unwrappedRaw`/`lastAcceptedCycle`/`acceptedCount` giữ nguyên — xác nhận qua đọc trực tiếp thứ tự lệnh trong hàm, "commit" chỉ xảy ra sau toàn bộ điều kiện fail đã qua).
- `MA600_AcquireSample` [ma600_acquisition.c]: transaction lỗi → `ctx->transportErrorCount++`, `continue` sang attempt kế, **không đụng `ctx->unwrap`**.

Trả lời trực tiếp: **một transaction lỗi KHÔNG được phép cập nhật
`lastRaw`/`encoderCount`/`unwrapped count`/`filter state`/`max/min`** —
đúng như thiết kế mong muốn, đã verify bằng đọc code, không phải giả định.

## 6.9 — Max/min và P2P

**VERIFIED CORRECT**, kèm một lưu ý edge-case lý thuyết.

- File: `Core/Src/nonlinear_test.c`, `CaptureSweep`: `errorMaxTrack=-1.0e9f`, `errorMinTrack=1.0e9f` (sentinel, không phải 0 — an toàn cho error âm/dương thật).
- Thứ tự: `error_i` được tính **trước**, so sánh cập nhật extrema **ngay sau đó, cùng vòng lặp, dùng đúng `error` hiện tại của điểm này** — không dùng error vòng trước.
- Ví dụ theo `ComputeSweepStats` (`nonlinear_test.c:787-830`), K=`NL_ROBUST_EXTREME_COUNT`=5:
  - `Errors=[-3.0,-2.0,-0.5]`: `rawPP = -0.5-(-3.0) = 2.5`.
  - `Errors=[0.5,2.0,3.0]`: `rawPP = 3.0-0.5 = 2.5`.
  - **Hai tập cho cùng `rawPP=2.5`** dù offset khác hẳn — minh chứng trực tiếp `P2P(e-c)=P2P(e)` với hằng số dịch `c` (dùng lại ở mục cross-jig).
  - Lưu ý edge-case: với tập chỉ 3 phần tử, `k=min(5,3)=3` → `robustPP` suy biến về 0 (top-3 và bottom-3 trùng nhau hoàn toàn). **Không xảy ra trong pipeline thật** vì `analysisCount` luôn cố định = 256 (≫ 2×5), chỉ là hệ quả của việc dùng ví dụ nhỏ để test công thức.

## 6.10 — Phạm vi 360° và 370°

- `analysisCount` luôn giới hạn đúng 256 điểm (0..255) cho `mean`/`rmsAc`/DFT/harmonic — xác nhận qua `nonlinear_test.c` (`for (int i = 0; i < analysisCount; i++)` trong toàn bộ khối tính RMS/harmonic).
- Điểm 256..~264 (margin tới 370°) **được lưu trong `DATA`/`errorSamples[]` nhưng KHÔNG dùng cho RMS/P2P/DFT chính thức** — đúng khuyến nghị đề bài.

### Finding ID: ALG-014
**Title:** Schema v5 (legacy) không có closure check chính thức tại điểm 256
**Severity:** MEDIUM
**Evidence:**
- File: `Core/Src/nonlinear_test.c`, toàn bộ `CaptureSweep`/`PrintSweepLog` — không có biến/field nào tên `closure`/so sánh điểm 256 với target 360°.
- File: `docs/schema-v5-phase1-baseline.md`: tự xác nhận *"closure is diagnostic in schema v5 and does not affect its `Status=VALID`"*.

**Effect on measurement:** một sweep có drift/hysteresis đóng vòng kém
(điểm 370° không khớp điểm 0°) vẫn có thể `MeasurementValid=1` trong schema
v5, vì không có gate nào kiểm tra việc này — chỉ `notSettledCount`/tracking
guard mới có thể gián tiếp bắt được (không đảm bảo).

**Recommended fix:** đã có trong hợp đồng `CANONICAL_Q16_V1`/schema v6
(`ClosureErrorRawQ16` tại điểm 256, ngưỡng pilot 0.20°) — chưa cutover vào
schema v5/legacy.

**Confidence:** Confirmed by code + confirmed by doc.

## 6.11 — PID và scheduler

Đã xác nhận PID không Δt-aware trong lượt review trước (`position_controller.c:27-52`,
`I += Ki*error` theo iteration, không nhân `dt`; anti-windup reset về 0
thay vì clamp). Bổ sung theo yêu cầu lần này:

- `configTICK_RATE_HZ=1000` (tick 1ms), `configMAX_PRIORITIES=56`
  (`Core/Inc/FreeRTOSConfig.h`).
- `NonlinearEngine_Task` chạy `osPriorityAboveNormal` (`nonlinear_test.c`,
  `NonlinearEngine_Init`); `StartDefaultTask` — **UNKNOWN, chưa xác nhận
  priority chính xác trong lần đọc này** (cần đọc `main.c`'s
  `defaultTask_attributes`).
- Move-to-zero loop dùng `osDelay(NL_MOVE_ZERO_LOOP_DELAY_MS=2)` — nếu
  jitter scheduler (do task khác chiếm CPU) làm khoảng cách giữa hai lần
  gọi `Motor_MoveToAngle()` không đúng 2ms, `Ki`/`Kd` (không nhân `dt`) sẽ
  tích lũy/vi phân sai tỷ lệ so với thời gian thực — ảnh hưởng tốc độ/độ
  ổn định hội tụ move-to-zero, gián tiếp ảnh hưởng độ chính xác
  `angleOffset` (mẫu đơn, xem ALG-001 context).

**Trả lời câu hỏi "vì sao cùng firmware, hai board/jig vẫn có tracking khác
nhau nếu execution timing khác"**: vì PID không chuẩn hóa theo `dt` thật,
CÙNG một chuỗi lệnh nhưng thực thi ở nhịp thời gian khác nhau (do khác biệt
tải CPU/ngắt phần cứng giữa hai board, dù cùng firmware) sẽ cho ra tích
phân/đạo hàm khác nhau về mặt số — đây là nguồn lý thuyết hợp lệ, nhưng
**UNKNOWN – NEED HARDWARE VERIFICATION** cho việc mức độ jitter thật giữa
JIG1/JIG3 có đủ lớn để giải thích được phần nào trong khoảng lệch 0.5-1°
đã quan sát hay không (không thể kết luận chỉ từ code).

## 6.12 — Signed/unsigned

**VERIFIED CORRECT** — không tìm thấy UB.

- File: `Core/Src/nonlinear_test.c`, `LockStartPosition`, dòng
  `Motor_SetElectricalPos((uint16_t)(0 - d), 1.0f)` với `d` là `int32_t`
  dương (1..20): `0-d` cho ra `int32_t` âm, cast sang `uint16_t` — **well-
  defined theo C11 6.3.1.3p2** (cộng/trừ `65536` liên tiếp tới khi nằm
  trong `[0,65535]`, tương đương modulo đúng nghĩa toán học), không phải
  UB. Đây là hành vi wraparound CÓ CHỦ ĐÍCH (biểu diễn "lệch -d" bằng đúng
  quy ước raw-count 16-bit).
- File: `Core/Src/nonlinear_test.c`, ramp CCW: `pos -= NL_RAMP_STEP` có thể
  âm, `Motor_SetElectricalPos((uint16_t)pos, 1.0f)` — cùng cơ chế, cùng kết
  luận an toàn.
- Không tìm thấy left-shift số âm, không tìm thấy float-to-unsigned trực
  tiếp không qua bước trung gian `int32_t` (điểm này đã được chính code tự
  ghi chú và xử lý đúng ở `PositionController_Update`/`MotorPwm_SetElectricalPos`).

## 6.13 — Correction table

Đã xác nhận Policy A (CORR0-31 = 0, CRC `0x190A55AD`) khớp **cả 3 jig**
(`docs/hardware-validation-checklist.md`) trong các lượt trước.

**Trả lời trực tiếp "tại sao xóa LUT về zero vẫn khiến hai jig khác
nhau"**: theo datasheet (mục "User Output Calibration"), bảng CORR chỉ hiệu
chỉnh sai số góc **nội tại của chính con chip MA600A** (quan hệ giữa góc từ
trường thật và góc chip đọc ra) — được đo và nạp riêng cho từng chip qua
quy trình hiệu chuẩn với reference chính xác. Nó **không hề liên quan** và
**không thể bù được** sai số lắp đặt cơ khí (độ lệch tâm, air-gap, độ
nghiêng nam châm so với trục quay) — những đại lượng này là thuộc tính vật
lý của từng jig, nằm hoàn toàn ngoài phạm vi mà LUT có thể sửa. Xóa LUT về
0 chỉ đảm bảo "không có hiệu chỉnh nào được áp dụng thêm" (Policy A, đồng
nhất giữa các jig ở khía cạnh này) — nó không đồng nhất hóa alignment vật
lý, vốn dĩ vẫn khác nhau giữa các jig ngay cả khi LUT giống hệt nhau.

## Finding bổ sung — không thuộc mục 6.1-6.13 nhưng phát hiện trong lúc audit

### Finding ID: ALG-018
**Title:** Dòng `RESULT` (chứa `Motor_System_INL_Deg`/`RMS_AC`/harmonic) không tự mang cờ hợp lệ, in ra vô điều kiện kể cả khi sweep invalid

**Severity:** HIGH

**Evidence:**
- File: `Core/Src/nonlinear_test.c`
- Function: `PrintSweepLog`
- Lines: ~1712-1744 (khối `LogLineLarge("RESULT,...")`) so với dòng
  ~1746 (`if (c->direction == NL_SWEEP_CW && c->measurementValid)` — điều
  kiện này chỉ gate khối "legacy" phía sau, KHÔNG gate khối `RESULT` phía
  trước).

**Current implementation:** `RESULT` được in **không điều kiện** ngay sau
`DATA`, bất kể `c->measurementValid`. Bản thân dòng `RESULT` **không có
field `MeasurementValid`** (field đó chỉ tồn tại ở `META`, và `Status=
VALID/INVALID` chỉ ở `END` — hai dòng khác, phải cross-reference đúng
`TestID`/`SweepID` mới biết `RESULT` đó có đáng tin không).

**Mathematical analysis:** không áp dụng — đây là lỗi thiết kế log, không
phải lỗi công thức.

**Effect on measurement:** một sweep có `measurementValid=false` (ví dụ
tracking guard fail) vẫn phát ra đầy đủ `Motor_System_INL_Deg`/`RMS_AC`/
mọi harmonic amplitude/phase, trông giống hệt một kết quả hợp lệ nếu chỉ
đọc dòng `RESULT`.

**Effect on cross-jig synchronization:** bất kỳ phân tích cross-jig nào chỉ
`grep RESULT` (kể cả các phép tính A6/A36/`DominantSelectedOrder` tôi đã
làm ở các lượt trước trong phiên này) **có rủi ro lẫn số liệu từ sweep
invalid** nếu không tự kiểm tra `END.Status`/`META.MeasurementValid` tương
ứng trước. Cần xác nhận lại: các log `v5-p03-test3`/`v5-p05-test3` đã dùng
trước đó có sweep nào invalid lẫn vào không — **UNKNOWN – NEED thêm một
lượt kiểm tra chéo `END.Status` cho từng `RESULT` đã trích xuất trước khi
tin tuyệt đối các số A6/A36 đã báo cáo ở lượt trước**.

**Recommended fix:** thêm `MeasurementValid=%d` trực tiếp vào chính dòng
`RESULT`, hoặc (đúng hướng schema v6) không phát `RESULT` official cho
sweep invalid, chỉ phát `DIAGNOSTIC_RESULT` — đã có trong thiết kế
`nonlinear-log-schema-v6.md`, chưa áp dụng cho schema v5.

**Verification test:** A.13 (mục 11) — xác nhận điểm 257-264 không vào
official analysis; bổ sung thêm test case "sweep invalid không phát field
official" khi viết `tools/analyze_motor_logs.py`.

**Confidence:** Confirmed by code.

## Tổng hợp mức độ nghiêm trọng (đến thời điểm này)

| ID | Title | Severity |
| --- | --- | --- |
| ALG-001 | Dual-read (encAngle vs rawAtPoint) | CRITICAL |
| ALG-002 | Settle thiếu target-proximity | CRITICAL |
| ALG-003 | Whole-system, không phải INL riêng | CRITICAL (định nghĩa nền, không phải bug) |
| ALG-004 | Canonical sampler chưa cutover | HIGH |
| ALG-005 | Ramp không có feedback | HIGH |
| ALG-006 | MOTOR_COUNT_PER_CYCLE dư 2 count/vòng | LOW |
| ALG-007 | Pole-pair hardcode/không log | LOW hiện tại / CRITICAL nếu mismatch |
| ALG-014 | Thiếu closure gate chính thức schema v5 | MEDIUM |
| ALG-018 | RESULT không tự mang cờ hợp lệ | HIGH |

Các mục 6.3/6.4/6.6(một phần)/6.7/6.8/6.9/6.12/6.13: **VERIFIED CORRECT**,
không phải finding cần sửa — liệt kê đầy đủ ở trên theo đúng yêu cầu "xác
nhận hoặc bác bỏ", không bỏ qua.

Còn 2 file bắt buộc (`system_measurement_architecture.md` — đã xong,
`nonlinear_algorithm_audit.md` — file này) hoàn tất theo đúng lựa chọn ưu
tiên của bạn. Các phần còn lại (cross-jig analysis, error budget, canonical
design, test plan, Python parser, executive summary) cần dữ liệu log đã xử
lý qua parser độc lập — đúng như đã thống nhất, sẽ làm ở bước kế tiếp.

## Correction note (2026-08-12) — xem `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md`

Ba finding trên đã được re-audit trực tiếp trên code hiện tại, kết quả khác
với bảng gốc ở trên cho ALG-005, và thu hẹp phạm vi ảnh hưởng cho ALG-001:

- **ALG-005 — INTERPRETATION CORRECTED, không còn là finding cần sửa.**
  `RampCommandToTarget()` hiện có đọc MA600 ở mỗi micro-step (cả nhánh
  S-curve mặc định lẫn nhánh legacy), nhưng sample chỉ ghi vào
  `motionDiag`/backtrack-counter/step-log — không bao giờ quay lại `*pos`
  hay tái tính command profile. Đây vẫn là open-loop actuation với
  observability, không phải "không đọc encoder" (claim gốc sai) và cũng
  không phải "đã có feedback control" (một cách hiểu sai khác cần tránh).
  Không cần thêm feedback actuation vào ramp để đạt Open-loop NL — ngược
  lại, thêm vào sẽ VI PHẠM mục tiêu hiện tại. Tên field `RampFeedbackEnabled`
  nên đổi thành `RampEncoderObservationEnabled`/`RampFeedbackActuationEnabled=0`.
- **ALG-001 — FIXED (2026-08-12).** `CaptureSweep()` giờ tích lũy
  `unwrappedRawSum` (int64) cùng vòng lặp 64-mẫu tạo `angleSampleSum`, tính
  `meanUnwrappedRaw` (round-to-nearest away-from-zero), rồi derive
  `rawAtPoint` bằng modulo 65536 — không còn transaction SPI thứ 65 nào.
  `DATA.AngleRaw`/`rawAtMax`/`rawAtMin`/`absoluteAngleAtMax/Min` giờ luôn
  cùng nguồn với `Error` đã chọn chúng làm cực trị. Verify: compile sạch cả
  2 profile, negative-test xác nhận contract script bắt được nếu dòng
  `rawAtPoint` bị phá. Xem
  `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md` mục 18.5.
- **ALG-002 — vẫn đúng nhưng cần một ranh giới rõ:** target-proximity là
  gate hợp lệ (stable-nhưng-lệch-target → `MeasurementValid=0`, không sửa
  command) — không sai per se. Nó chỉ vi phạm Open-loop NL khi cùng gap đó
  bị dùng để TRIGGER command correction (đây là điều sweep-point creep
  V5.1-V5.9 làm — xem tài liệu correction handoff, không phải điều
  `WaitForPointSettle()`/`SettleTargetProximityValid` tự thân làm).
- **Nguyên nhân drift thật không nằm ở ALG-001/005** mà ở
  `CreepToUnwrappedTargetProfiled()` (và toàn bộ recovery/terminal
  correction liên quan) — dùng chính MA600 đang đo để sửa electrical
  command trước khi DATA được chốt. Đây là closed-loop feedback actuation
  thật, không tương đương Gremsy open-loop NL, dù rất hữu ích như
  `POSITION_RESPONSE_DIAGNOSTIC_V5X`.

Đọc `docs/open-loop-nl-direction-correction-handoff-2026-08-12.md` (mục 7,
18) để có bảng compliance đầy đủ trước khi dùng lại các finding ALG-001/005
ở trên cho bất kỳ quyết định nào.
