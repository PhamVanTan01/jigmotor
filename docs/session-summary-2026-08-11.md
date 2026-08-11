# Nhật ký công việc 2026-08-11

Theo quy ước của dự án: mỗi ngày dùng một file nhật ký duy nhất. Tài liệu này
ghi lại kết quả kiểm tra V5.8 trên motor PG07 7 pole-pair, audit lại định nghĩa
NL so với firmware Gremsy và quyết định kiến trúc cho bước V6.0.

## 1. Kết luận điều hành

1. Build V5.8 nhận đúng hình học motor PG07: 14 pole, 7 pole-pair và harmonic
   điện dự kiến tại order 42.
2. Acquisition MA600/SPI, unwrap, capture 371 điểm và timing đều sạch.
3. Khả năng bám vị trí của PG07 với thuật toán V5.8 hiện tại **không đạt**:
   chỉ 51-60% điểm OFFICIAL đi vào deadband ±16 raw; 159-180 điểm mỗi run hết
   ngân sách correction.
4. Dạng lỗi lặp lại rất mạnh qua run/remount. Đây không phải nhiễu đọc encoder
   ngẫu nhiên hoặc mất command.
5. Tuy nhiên, các số NL hiện tại **không được dùng để kết luận motor PG07 có NL
   xấu**, vì V5.8 dùng chính MA600 để thay đổi electrical command trước khi
   capture. V5.8 đang đo position-response/correction, không còn là open-loop NL
   thuần túy theo Gremsy.
6. Mục tiêu chính thức được khóa lại: **đo whole-system open-loop NL tương thích
   định nghĩa Gremsy**. Nhánh V5.x creep được giữ làm diagnostic; không promote
   V5.9 thành firmware đo NL chính thức.
7. Bước tiếp theo đề xuất là V6.0 `GREMSY_COMPAT_OPEN_LOOP_NL_V1`: command cố
   định, MA600 chỉ quan sát settle và lấy mẫu, tuyệt đối không dùng feedback để
   thay đổi command trong cửa sổ đo.

## 2. Dữ liệu được đánh giá

### 2.1. Log PG07

1. Remount01:
   `D:/tanpham/QAtoool/jigtest/motor/jigmotor/tools/dist/captured-logs/S2-PG07-JIG1-remount01-test-1-v5-8.txt`
2. Remount02:
   `captured-logs/S2-PG07-JIG5-remount02-test-1-v5-8.txt`

Mỗi file chứa một PRECONDITION và hai run OFFICIAL. V5.8 là build chẩn đoán
response timing nên toàn bộ run có `EligibleForStatistics=0`; điều này là đúng
contract và không phải lỗi motor.

### 2.2. Lỗi nhận dạng tên file

Cả hai log đều tự khai báo cùng:

```text
JigID=JIG5
MCU_UID=001D00283234470438353535
BuildID=Aug 11 2026 15:59:17
```

Do đó file remount01 mang chữ `JIG1` trong tên nhưng nội dung firmware xác định
là `JIG5`. Hai file chỉ chứng minh repeatability/remount trên cùng UID, không
thể dùng làm bằng chứng cross-jig JIG1-vs-JIG5. Trước mọi phân tích cross-jig
tiếp theo phải sửa tên file hoặc sửa mapping UID nếu phần cứng thực tế đúng là
hai jig khác nhau.

### 2.3. Contract motor 7PP

Các field quan trọng đều đúng:

```text
MotorPoleCount=14
MotorPolePairs=7
ElectricalRippleMultiple=6
ElectricalRippleOrder=42
AnalysisPoints=360
CapturedPoints=371
ApproachProtocol=SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2
```

Không có `AcqRetries`, `AcqTransportErrors`, `AcqJumpRejects`,
`AcqFailedSamples` hoặc `ContextReacquireCount`.

## 3. Kết quả định lượng PG07 V5.8

### 3.1. Bốn run OFFICIAL

| Batch | Run | Đạt ±16 raw | Hard-cap fail | RMS_AC | RawP2P | RobustP2P | System INL | Tracking RMS | Tracking max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Remount01 | OFF1 | 223/370 (60.27%) | 147 | 0.4572° | 1.8977° | 1.8183° | 0.9488° | 0.5389° | 1.8018° |
| Remount01 | OFF2 | 190/370 (51.35%) | 180 | 0.5826° | 2.3265° | 2.2619° | 1.1632° | 0.7431° | 2.2357° |
| Remount02 | OFF1 | 193/370 (52.16%) | 177 | 0.5780° | 2.2999° | 2.2474° | 1.1500° | 0.7341° | 2.2083° |
| Remount02 | OFF2 | 211/370 (57.03%) | 159 | 0.5210° | 2.1655° | 2.0862° | 1.0828° | 0.6333° | 2.0764° |

Closure canonical vẫn nhỏ, khoảng 0.05-0.09°. Closure tốt không cứu được phép
đo: sai số dương và âm trên cả vòng có thể tự triệt tiêu tại point 360 trong
khi hàng trăm điểm trung gian vẫn ngoài deadband.

### 3.2. Timing và command response

- Cả 370 command mỗi sweep đều được phát và có telemetry timing.
- `CommandToStop` trung bình trên bốn run OFFICIAL khoảng 194-201 ms/điểm.
- Với các điểm đạt, median `TimeToDeadband` khoảng 182-214 ms.
- `NominalStepTrackingPermille` trung bình khoảng 999.8 permille: bước danh
  định 1° không bị mất.
- `CreepResponseEfficiencyPermille` chỉ khoảng 75-78% trên run OFFICIAL.

Diễn giải đúng: motor không bỏ qua gần một nửa command. Bước danh định được phát
đủ, nhưng trạng thái cân bằng rotor/load-angle lệch lớn; correction V5.8 hết
budget trước khi đưa rotor vào ±16 raw tại rất nhiều góc.

### 3.3. Mẫu lỗi theo góc

Trên bốn run OFFICIAL:

- 147 điểm fail 4/4 run;
- 159 điểm fail ít nhất 3/4 run;
- các dải lặp lại chính gồm khoảng 86-177°, 269-295° và 324-345°, cùng một số
  dải ngắn quanh 43-44°, 221-225° và 266-267°.

Tương quan dạng đường lỗi:

- trong remount01: khoảng 0.978;
- trong remount02: khoảng 0.992;
- trung bình remount01 so với remount02: khoảng 0.997, best circular shift = 0.

Vì vậy lỗi mang tính hệ thống và khóa theo góc. Remount có thể đổi biên độ nhưng
không loại được cơ chế chính.

### 3.4. Harmonic

Trong bốn run OFFICIAL:

- H42 dự kiến cho 7PP chỉ khoảng 0.0465-0.0593°;
- H2/H6 khoảng 0.326-0.473° và chiếm ưu thế;
- H36 khoảng 0.101-0.121°, cũng lớn hơn H42.

Kết quả chưa ủng hộ giả thuyết “ripple điện order 42 là nguyên nhân chính”. Dạng
lỗi hiện tại bị chi phối bởi thành phần thấp bậc của toàn hệ thống: commutation,
load-angle, trạng thái home, cơ khí/alignment hoặc tương tác giữa chúng. Chưa đủ
bằng chứng để ưu tiên đổi mapping 9363 sang direct-Q16 ngay.

### 3.5. Nhánh home/lock

Remount01 PRECONDITION bắt đầu tại `StartRaw=4687`; hai run sau ở
`StartRaw=13893/13834`. Chênh khoảng 9200 raw, gần một chu kỳ điện 7PP
`9363 raw`. Remount02 tiếp tục nằm ổn định quanh 13837-13871.

Đây là dấu hiệu motor có thể khóa vào hai nhánh cân bằng điện lân cận. Home phải
được instrument bằng `StartRaw mod 9363` và branch ID trước khi kết luận về
repeatability open-loop.

## 4. Audit định nghĩa NL: Gremsy so với V5.8

### 4.1. Gremsy open-loop NL

Chuỗi trong `datacty/gremsyTaskManager.c`:

```text
motorNL_Pos += MOTOR_NONLINEAR_POS_INCREASE
gremsyMotorMovePos(motorNL_Pos, 1.0)
wait
average encoder samples
Error = CommandAngle - (EncoderAngle - EncoderOffset)
NL = ErrorMax - ErrorMin
```

Trong lúc sweep, encoder không được dùng để thay đổi command. Sai lệch giữa
electrical command và vị trí cân bằng cơ khí chính là measurand.

Đại lượng tương đương trực tiếp với scalar Gremsy trong pipeline hiện tại là:

```text
RawP2P = max(Error[0..359]) - min(Error[0..359])
```

`Motor_System_INL_Deg = RawP2P / 2` và `RobustP2P` là các đại lượng bổ sung,
không phải scalar Gremsy gốc.

### 4.2. Phần dự án hiện tại làm tốt hơn Gremsy

- lưới 360 điểm đúng một vòng cơ khí;
- S-curve thay cho bước nhảy đột ngột;
- chờ stability thay cho fixed delay;
- 64 mẫu canonical tại mỗi điểm;
- SPI/unwrap/jump/timing gate;
- full error curve, DFT/harmonic, closure và repeatability;
- RawP2P, RobustP2P và System INL được báo riêng.

Những phần này cần được giữ lại cho V6.0.

### 4.3. Điểm V5.8 rời khỏi open-loop

Trong `CreepToUnwrappedTargetProfiled()`:

1. đọc vị trí thật từ MA600;
2. tính gap đến target cơ khí;
3. thay đổi `commandPos` theo bước 16/4 raw;
4. gọi `Motor_SetElectricalPos()`;
5. đọc lại MA600;
6. chỉ sau khi correction xong hoặc hết budget mới capture `DATA`.

Như vậy MA600 vừa là feedback device vừa là measured device. V5.8 phù hợp để
đánh giá position response, time-to-deadband và correction effort, nhưng không
thể được gọi là pure open-loop NL.

`AutoVerdict=DIAGNOSTIC PASS` của tool chỉ xác nhận capture/telemetry hợp lệ.
Nó không phải verdict chất lượng motor và cũng không xác nhận NL chính xác.

## 5. Quyết định kiến trúc

### 5.1. Tách hai firmware contract

| Contract | Mục đích | Vai trò MA600 | Statistical status |
|---|---|---|---|
| `GREMSY_COMPAT_OPEN_LOOP_NL_V1` | Đo whole-system open-loop NL | Chỉ quan sát settle và lấy mẫu | Candidate official sau qualification |
| `POSITION_RESPONSE_DIAGNOSTIC_V5X` | Đo khả năng bám target/correction | Feedback điều khiển creep | Diagnostic, `EligibleForStatistics=0` |

Không được trộn metric của hai contract trong cùng population hoặc so trực tiếp
như cùng một measurand.

### 5.2. Quyết định với V5.9

- Không triển khai/promote V5.9 terminal correction làm firmware đo NL chính
  thức.
- V5.9 có thể giữ trong backlog chẩn đoán position response cho các hồ sơ lỗi
  điểm cô lập.
- Không dùng V5.9 cho PG07 hiện tại: 159-180 failure/run là lỗi dải rộng, không
  phù hợp safety cap vài điểm terminal correction mỗi sweep.

## 6. Đề xuất V6.0 — `GREMSY_COMPAT_OPEN_LOOP_NL_V1`

### 6.1. Invariant bắt buộc

1. Electrical command tại mỗi point được tạo từ lưới danh định và giữ nguyên
   trong toàn bộ settle + capture.
2. Không dùng sweep-point creep, B0-B creep, feedforward hoặc terminal
   correction trong cửa sổ đo chính thức.
3. MA600 chỉ được dùng để:
   - kiểm tra rotor đã ổn định;
   - kiểm tra safety envelope;
   - lấy 64 mẫu canonical.
4. Không dùng độ gần target ±16 raw làm mục tiêu điều khiển; độ lệch ổn định
   chính là tín hiệu NL cần đo.
5. Nếu rotor không ổn định hoặc vượt safety envelope: invalidate point/run,
   không thay command để “cứu” số liệu.
6. Log phải chứng minh `CommandChangedDuringSettle=0` và
   `CommandChangedDuringCapture=0`.

### 6.2. Các phần giữ nguyên ban đầu

Để A/B có ý nghĩa, build đầu tiên giữ nguyên:

- S-curve 40 tick;
- power 1.0;
- lưới 1° và 360 analysis points;
- 371 captured points 0..370;
- current integer mapping `raw % 9363`;
- 64-sample canonical acquisition;
- settle stability 9 raw / 8 consecutive poll;
- config gate và toàn bộ safety/transport gate.

Chỉ thay một biến chính: **tắt feedback correction trước DATA capture**.

### 6.3. Telemetry tối thiểu

Đề xuất thêm:

```text
MeasurementDefinition=WHOLE_SYSTEM_OPEN_LOOP_TRACKING_V1
FeedbackCorrectionEnabled=0
CommandRawAtRampEnd
CommandRawAtSettleEnd
CommandRawAtCaptureStart
CommandRawAtCaptureEnd
CommandChangedDuringSettle
CommandChangedDuringCapture
StartRawModElectricalCycle
HomeElectricalBranch
```

V5.x diagnostic phải đổi definition rõ ràng, ví dụ:

```text
MeasurementDefinition=FEEDBACK_CORRECTED_POSITION_RESPONSE_DIAG_V1
```

### 6.4. Metric chính thức

- Gremsy-compatible primary scalar: `RawP2P`.
- Báo bổ sung nhưng không thay primary scalar:
  - ErrorMin/ErrorMax;
  - RobustP2P;
  - RMS_AC;
  - harmonic spectrum, đặc biệt H1/H2/H6/H42;
  - Closure và post-turn residual;
  - settle time và stability spread.

`Motor_System_INL_Deg` không được so với sensor INL trong datasheet MA600A.
Sensor-only INL/trueness vẫn không đo được nếu không có encoder tham chiếu độc
lập.

## 7. Trình tự thực nghiệm đề xuất

### V6.0-D0 — instrumentation-only home branch

- không đổi motion;
- log `StartRaw mod 9363`, branch ID, lock command và final state;
- chạy tối thiểu ba chu kỳ cùng mount;
- mục tiêu: xác định việc đổi nhánh 4687 -> 138xx có tái diễn hay không.

### V6.0-A/B/A — feedback-corrected vs observe-only

- A1: V5.8 diagnostic hiện tại;
- B: V6.0 open-loop observe-only;
- A2: quay lại đúng V5.8;
- cùng motor, jig, mount, HEX/checksum theo từng leg và cooldown đã khóa;
- không dùng scalar duy nhất để kết luận; so full curve, RawP2P, harmonic,
  stability và nhiệt/thời gian.

### V6.0-Pilot

Sau khi A/B/A xác nhận contract B đúng measurand:

- một PRECONDITION + ba OFFICIAL, cùng mount;
- acquisition/capture sạch 3/3;
- command bất biến 3/3;
- không run nào đổi home branch ngoài policy đã định;
- báo CV/range của RawP2P, RMS_AC, Closure và harmonic;
- chỉ khóa ngưỡng product sau khi có population/reference requirement, không
  suy ngưỡng chất lượng từ chính batch pilot.

### Mapping A/B chỉ khi được kích hoạt

Chỉ thử `raw % 9363` so với direct-Q16 `mechanicalRaw * 7` nếu open-loop trace
cho thấy lỗi tập trung ở biên chu kỳ điện hoặc harmonic/phase trajectory xác
nhận giả thuyết mapping. Không đổi mapping cùng lúc với việc tắt creep.

## 8. Checklist trạng thái cuối ngày

- [x] Xác nhận firmware nhận đúng PG07 7PP/order 42.
- [x] Xác nhận acquisition và timing V5.8 sạch.
- [x] Định lượng 4 run OFFICIAL qua hai remount.
- [x] Xác nhận motion feasibility V5.8 trên PG07 FAIL.
- [x] Xác nhận dạng lỗi lặp lại, không phải random transport noise.
- [x] Phát hiện filename `JIG1` nhưng nội dung/UID là JIG5.
- [x] Audit Gremsy NL và xác định scalar tương đương là RawP2P.
- [x] Xác nhận V5.8 creep không phải pure open-loop measurement.
- [x] Khóa mục tiêu V6.0 là Gremsy-compatible open-loop NL.
- [ ] Sửa/đối chiếu nhận dạng vật lý JIG1-vs-JIG5.
- [ ] Viết plan V6.0 chi tiết trước khi code.
- [ ] Implement compile profile open-loop riêng.
- [ ] Thêm telemetry chứng minh command bất biến.
- [ ] Build/test contract và package artifact.
- [ ] Chạy V6.0-D0 và A/B/A trên phần cứng.
- [ ] Qualification repeatability trước khi cấp official status.

## 9. Lưu ý cho AI/engineer tiếp theo

1. Không tiếp tục tối ưu V5.x correction rồi gọi kết quả là motor NL.
2. Không diễn giải `MeasurementValid=1`, `TrackingValid=1`, `Status=VALID` hoặc
   `DIAGNOSTIC PASS` thành product pass. Các gate hiện tại chủ yếu xác nhận
   structural/capture integrity.
3. Không dùng Closure nhỏ để che hàng trăm point failure.
4. Không dùng cùng MA600 vừa feedback-correct vừa tuyên bố đo được trueness/INL
   của MA600.
5. Không kết luận cross-jig từ hai file PG07 hôm nay vì chúng cùng JIG5/UID.
6. Không stage/commit các log, build artifact hoặc firmware đang dirty chỉ vì
   tài liệu này được commit; phạm vi commit của nhật ký phải độc lập.

## 10. File liên quan

- `Core/Src/nonlinear_test.c`
- `Core/Src/motor.c`
- `Core/Src/motor_pwm.c`
- `Core/Inc/motor_config.h`
- `datacty/gremsyTaskManager.c` (ở project chính)
- `docs/motor-7pp-engineering-test-plan.md`
- `docs/motor-7pp-stutter-diagnostic-plan.md`
- `docs/motor-7pp-a-b-evidence-derived-test-plan.md`
- `docs/phase3b0-closure-measurement-review.md` (ở project chính)
- `docs/motor-7pp-v5-8-response-timing-test-guide.md`
- `captured-logs/S2-PG07-JIG5-remount02-test-1-v5-8.txt`

## 11. Phạm vi commit của tài liệu này

Commit nhật ký chỉ chứa `docs/session-summary-2026-08-11.md`. Firmware, script,
graphify output, build và log đang có thay đổi riêng trong worktree không được
stage kèm, nhằm tránh trộn công việc chưa được audit vào một commit tài liệu.
