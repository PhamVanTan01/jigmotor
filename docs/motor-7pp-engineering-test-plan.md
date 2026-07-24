# Plan thử nghiệm motor 7 cặp cực

Updated: 2026-07-24

Status: **ACTIVE ENGINEERING DIAGNOSTIC — P7.8 implemented; P7.9/P7.10 active;
chưa phải tiêu chuẩn PASS/FAIL sản phẩm**

## 1. Mục tiêu

Xác định motor **7 cặp cực** có thể được điều khiển và đo lặp lại bằng JIG hiện
tại hay không, đồng thời thu một bộ dữ liệu đủ sạch để nhận dạng đặc trưng motor.

Thứ tự ưu tiên:

1. đúng hình học điện và an toàn chuyển động;
2. acquisition/settle/motion hợp lệ;
3. độ lặp lại trên cùng một lần gá;
4. nhận dạng phổ/harmonic của motor;
5. chỉ sau các bước trên mới xem xét tối ưu Closure hoặc mở rộng V3.

Kết quả thử nghiệm này **không** được dùng để kết luận MA600A đạt datasheet/ISO.
JIG không có encoder chuẩn độc lập nên các đại lượng NL/INL vẫn là sai số của
toàn hệ thống motor + gá + nam châm + MA600A.

## 2. Hình học bắt buộc

Trong project, `MOTOR_NUM_POLSE` là **số cực vật lý**, không phải số cặp cực.
Motor 7 cặp cực phải có cấu hình:

| Đại lượng | Giá trị |
| --- | ---: |
| Số cực vật lý | 14 |
| `MOTOR_NUM_POLSE` | `14U` |
| `MOTOR_POLE_PAIRS` | `7U` |
| Số đếm cơ khí/vòng | 65,536 raw |
| Chu kỳ điện lý tưởng | 65,536 / 7 = 9,362.285714 raw |
| Chu kỳ điện đang dùng trong firmware | `ceil(65,536 / 7)` = 9,363 raw |
| Một chu kỳ điện theo góc cơ khí | 51.428571° |
| Ripple order dự kiến `6 × pole-pairs` | 42 |

Không được cấu hình `MOTOR_NUM_POLSE=7`: build hiện tại sẽ chặn số cực lẻ, và
ý nghĩa vật lý cũng sai.

### 2.1. Giới hạn đã biết của bộ đổi pha PWM hiện tại

`motor_pwm.c` dùng chu kỳ điện nguyên 9,363 raw. Bảy chu kỳ như vậy bằng
65,541 raw, lớn hơn một vòng encoder 5 raw. Vì lệnh được chứa trong `uint16_t`,
điểm 360° vẫn wrap về 0, nhưng chu kỳ điện cuối bị ngắn 5 raw và ánh xạ pha có
sai khác tối đa xấp xỉ:

- 5 raw cơ khí tương đương 0.02747° cơ khí;
- tương đương khoảng 0.1923° điện với 7 cặp cực.

Đây chưa phải lý do cấm chạy thử, nhưng mọi kết quả ban đầu phải mang nhãn
`ENGINEERING_ONLY`. Không được quy trực tiếp 5 raw này thành Closure; nó là
sai khác ánh xạ pha điều khiển cần được kiểm tra riêng nếu dữ liệu cho thấy dấu
hiệu bất thường tại biên chu kỳ.

## 3. Cấu hình build thử nghiệm

Tạo build riêng, không đổi default 12-pole đang dùng cho P02–P06:

```text
Build label:       motor-7pp-lock-only-1run-v1
App mode:          MEASUREMENT
Profile identity:  7PP_ENGINEERING_LOCK_ONLY_V1
MOTOR_NUM_POLSE:   14U
NL_APPROACH_MODE:  NL_APPROACH_MODE_LOCK_ONLY
Motion profile:    SCURVE40_ABSOLUTE_TICK_V2
Auto batch:        OFF ở giai đoạn bring-up
CCW engineering:   OFF
B0-B soft-start:   OFF
B0-B creep:        OFF
B0-B feedforward:  OFF
Sweep soft-start:  OFF
Ramp diagnostics:  ON
Closure hold probe: ON, diagnostic-only
```

Các ràng buộc:

- Không dùng `NL_APPROACH_MODE_NO_REVERSAL_V3` mode 2: implementation này
  vẫn cố định pre-roll 59°→60° cho motor 6 cặp cực.
- V3.2 shifted-reversal mode 3 chỉ được dùng sau khi target đã tổng quát hóa
  theo raw electrical-cycle; không được thay 59/60 bằng 50/51 một cách xấp xỉ.
- Không dùng bias B0-B 79/126 raw. Đây là hệ số thực nghiệm của motor/jig 6
  cặp cực, không phải hằng số ma sát phổ quát.
- Không dùng Control A5 offset 7971 như phép bring-up; offset đó được hiệu
  chỉnh cho cấu hình trước, không phải cho motor 7 cặp cực.
- Không thay PID gain, power, S-curve, settle hoặc công thức NL trong cùng
  build này. Biến duy nhất về điều khiển là hình học motor 14 pole/7 pole-pair.

### 3.1. Contract build cần bổ sung trước khi flash

Tạo script/build profile độc lập để inject các define trên và lưu:

- HEX/ELF/MAP;
- git commit và dirty state;
- SHA-256 của HEX;
- toàn bộ define 7PP và profile ID;
- kết quả Debug + Release, 0 compiler error và 0 warning;
- kiểm tra negative build: chọn V3 cùng `MOTOR_NUM_POLSE=14U` phải fail.

`save_build.ps1` hiện chỉ cố đọc boolean B0-B cũ; không dùng sidecar hiện tại
làm bằng chứng đầy đủ cho build 7PP cho đến khi manifest ghi được
`MOTOR_NUM_POLSE`, `NL_APPROACH_MODE` và các flag thử nghiệm.

## 4. Trình tự thử nghiệm

### P7.0 — Xác nhận phần cứng trước cấp lực

- [ ] Xác nhận bằng datasheet/đếm vật lý rằng motor có 14 pole = 7 pole-pair.
- [ ] Xác nhận thứ tự ba pha và chiều quay mong đợi.
- [ ] Trục quay tự do, không chạm hard-stop, gá/nam châm/MA600A chắc chắn.
- [ ] MA600 idle angle đọc được và không có lỗi SPI/status trước khi nhấn nút.
- [ ] Nguồn có current limit theo định mức thật của motor/driver; không tự đặt
  một ngưỡng dòng mới khi chưa có datasheet.
- [ ] Có phương tiện cắt nguồn motor ngay khi rung mạnh, sai chiều, kẹt hoặc
  dòng/nhiệt tăng bất thường. Nút hiện tại chỉ tạo cạnh START, không phải nút
  emergency-stop trong lúc test.
- [ ] Motor bắt đầu ở trạng thái nguội đã ghi nhận; nếu không có cảm biến nhiệt,
  chỉ được gọi đây là kiểm soát thời gian nghỉ, không phải kiểm soát nhiệt độ.

Nếu bất kỳ mục nào chưa đạt: **không flash/chạy motor**.

### P7.1 — Smoke test một lần, cùng một lần gá

Dùng build `motor-7pp-lock-only-1run-v1`, start logging trước khi nhấn nút và
chỉ nhấn một lần.

Gate bắt buộc trong log:

- `BUILD_MANIFEST` đúng Measurement/profile 7PP và đúng checksum đã lưu;
- `CONFIG` hợp lệ, `PolicyAGatePassed=1`;
- `MotorPoleCount=14`, `MotorPolePairs=7`, `ElectricalRippleOrder=42`;
- `ApproachProtocol=SCURVE_LOCK_V2`;
- không có `APPROACH_RESULT` B0-B/V2/V3;
- không E502/E503/E504/E505/E506, reset, HardFault hoặc stack overflow;
- `MeasurementValid=1`, `TrackingValid=1`, `AcquisitionResult=OK`;
- 371 điểm được capture cho 0..370°, trong đó `AnalysisPoints=360` và closure
  dùng point 360;
- toàn bộ 371 settle point hợp lệ, không timeout/wrong-position;
- với S-curve 40 tick và 370 đoạn, kỳ vọng 14,800 ramp-feedback sample nếu
  không retry/fault;
- transport error, failed sample, jump reject và context reacquire đều bằng 0.

Quan sát vật lý bắt buộc: chiều quay đúng, không mất bước rõ rệt, không rung/
tiếng bất thường, current limit không tác động và motor không tăng nhiệt nhanh.

Chỉ cần một lỗi an toàn hoặc một lỗi structural: dừng tại P7.1, không chạy lại
để “lấy trung bình cho đẹp”.

### P7.2 — Ba lần xác nhận feasibility

Chỉ chạy khi P7.1 sạch. Giữ nguyên HEX, JIG và lần gá; chạy thêm hai lần để có
tổng cộng ba run. Nghỉ motor-off 120 giây giữa các lần và ghi thời gian thực.

Gate để sang P7.3:

- 3/3 run đạt toàn bộ gate structural của P7.1;
- không có xu hướng tracking error, motor-active time, dòng/nhiệt hoặc settle
  xấu dần;
- báo cáo riêng từng run, không loại run đầu sau khi xem kết quả;
- `RMS_AC` có CV ≤ 5%; Closure canonical có range ≤ 0.15°;
- `Motor_Error_P2P_Deg` và `Motor_System_INL_Deg` có CV ≤ 5%.

Các ngưỡng trên là gate repeatability engineering tạm thời, không phải giới
hạn chất lượng/datasheet. Nếu chỉ metric điện `AElectrical6` chưa ổn định nhưng
motion/acquisition sạch, giữ P7.2 để phân tích phổ trước; không tune controller
ngay.

### P7.3 — Batch repeatability

Sau khi P7.2 pass, tạo build thứ hai chỉ thay chế độ batch:

```text
Build label: motor-7pp-lock-only-pre1-plus-10-v1
Precondition: 1 full sweep, EligibleForStatistics=0
Official:     10 run
Cooldown:     120,000 ms motor-off
```

Không đổi motion/PWM/PID/approach giữa build 1-run và build batch. Batch phải
có đúng một precondition + mười official run, không remount và không reset.

Gate repeatability:

- 10/10 official run hợp lệ; precondition không lọt vào thống kê;
- cooldown từng chu kỳ nằm trong contract firmware;
- Closure canonical: SD ≤ 0.05° và range ≤ 0.15°;
- `RMS_AC`, P2P hệ thống và INL hệ thống: CV ≤ 5%;
- `AElectrical6` tại order 42: CV ≤ 10%;
- official run 1 không tách khỏi run 2..10 vượt các giới hạn trên.

Nếu official run 1 lệch hệ thống so với 2..10, kết luận **một precondition chưa
đủ cho motor 7PP**. Không được loại run 1 hậu nghiệm; tạo thí nghiệm warm-up
riêng trước khi tiếp tục.

### P7.4 — Nhận dạng signature motor 7PP

Chỉ dùng các run structural-valid và giữ precondition thành nhóm audit riêng.

**Tooling gate trước khi chạy:** `tools/analyze_one_turn_pattern.py` hiện tính
được phổ tổng quát order 1..179, nhưng phần reconstruction/folding vẫn hardcode
H36, family 36/72/108 và file `folded_10deg`. Các output reconstruction/fold đó
**không hợp lệ cho 7PP**. Trước P7.4 phải mở rộng tool để nhận:

```text
--pole-pairs 7
--electrical-ripple-multiple 6
electrical order = 42
electrical family = 42, 84, 126
```

Vì 360 không chia hết cho 42, không được thay số 36 bằng 42 trong
`fold_by_order()` hiện tại. Phải fold theo electrical phase bằng circular bin/
interpolation, hoặc báo rõ `fold unavailable`; không ép 360 điểm thành 42 sector
có độ rộng nguyên.

Sau khi contract/tool test cho 7PP pass, chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\analyze_nonlinear_logs.ps1 `
  -Summary -OutCsv .\analysis-output\motor-7pp-summary.csv <logfiles>

python .\tools\analyze_one_turn_pattern.py `
  <logfiles> --pole-pairs 7 --electrical-ripple-multiple 6 `
  --out-dir .\analysis-output\motor-7pp-one-turn
```

Các đặc trưng cần báo cáo:

- `RMS_AC`, robust/raw P2P, `Motor_System_INL_Deg`;
- canonical Closure và residual hậu vòng;
- phổ harmonic đầy đủ 1..179;
- amplitude và energy ratio tại order 7, 14, 21, 28, 35, **42**, 49;
- `AElectrical6` động của firmware, phải tương ứng `ElectricalRippleOrder=42`;
- dominant order, top harmonic, phase coherence trong cùng một lần gá;
- tracking RMS/max, settle time/timeout và motion diagnostics.

Order 42 là **giả thuyết vật lý cần kiểm chứng**, không phải bằng chứng độc lập
rằng motor có 7 cặp cực. Pole count vẫn phải đến từ thông tin motor/kiểm tra
phần cứng. Khi so sánh qua lần tháo-lắp, ưu tiên amplitude/energy ratio; phase
có thể đổi theo góc gá và không được dùng đơn độc làm signature.

Không gộp thống kê motor 7PP với P02–P06 6PP. Có thể đặt cạnh nhau để mô tả,
nhưng phải group theo `MotorPolePairs` trước mọi mean/SD/threshold.

### P7.5 — Kiểm tra giới hạn ánh xạ pha, chỉ khi cần

Kích hoạt phase này nếu P7.1/P7.2 có một trong các dấu hiệu:

- sai số tracking lặp lại ở biên mỗi chu kỳ điện hoặc gần raw wrap 65,536;
- phổ xuất hiện thành phần liên quan đến bảy biên chu kỳ;
- Closure/endpoint sạch về acquisition nhưng không lặp lại;
- dữ liệu tốt hơn giới hạn cỡ 5 raw khiến sai khác ánh xạ hiện tại không còn
  bỏ qua được.

Khi đó tạo A/B riêng:

- A: mapping hiện tại `pos % 9363`;
- B: direct Q16 electrical phase, tính từ `mechanicalRaw × 7` rồi wrap;
- giữ nguyên mọi biến khác và chạy A–B–A trên cùng motor/JIG.

Không đưa direct-Q16 vào cùng build bring-up đầu tiên; nếu thay geometry và
thuật toán ánh xạ cùng lúc sẽ không biết biến nào gây khác biệt.

### P7.6 — Mở rộng V3, yêu cầu lịch sử trước implementation P7.8

Phần này ghi lại yêu cầu thiết kế trước khi P7.8 được implement. V3 cho 7PP
phải thiết kế target theo raw/electrical phase; không thể thay 60 thành một số
độ nguyên vì 51.428571° không nằm trên lưới 1°.

Yêu cầu tối thiểu của V3-7PP tương lai:

- pre-roll target và final target tính từ `MOTOR_COUNT_PER_ELECTRICAL_CYCLE`
  hoặc direct Q16 phase, không hardcode point 51/52;
- endpoint target biểu diễn chính xác trong raw, tách khỏi analysis grid 1°;
- contract/log riêng, compile guard riêng cho 7PP;
- test causal A–B–A riêng; không tái sử dụng bias của 6PP.

## 5. Decision tree

```text
P7.0 chưa đủ điều kiện
  -> KHÔNG chạy

P7.1 có lỗi an toàn / direction / home / acquisition / settle
  -> dừng, chẩn đoán hình học pha và wiring

P7.1 sạch nhưng P7.2 không lặp lại
  -> giữ build 1-run; phân tích motion/thermal/mapping, chưa chạy 10-run

P7.2 pass
  -> P7.3 precondition + 10 official

P7.3 pass và không có dấu hiệu phase-boundary
  -> chấp nhận 7PP ở mức engineering baseline, lập signature P7.4

P7.3 structural pass nhưng endpoint/spectrum cho thấy phase-boundary
  -> P7.5 integer-cycle vs direct-Q16 A-B-A

Chỉ sau khi mapping + repeatability pass
  -> cân nhắc V3-7PP hoặc tối ưu Closure
```

## 6. File và bằng chứng phải lưu

- [ ] build manifest và SHA-256 cho từng HEX;
- [ ] log UART nguyên bản, bắt đầu từ boot manifest;
- [ ] tên motor do operator điền; Motor ID không phải gate phần mềm nhưng pole
  count là gate bắt buộc;
- [ ] JIG ID/UID và ảnh/cách gá;
- [ ] thời gian nghỉ trước test và cooldown thực tế;
- [ ] nguồn/current-limit và quan sát nhiệt/dòng;
- [ ] CSV official analyzer;
- [ ] spectrum/one-turn report;
- [ ] bảng từng run trước mean/SD/CV;
- [ ] quyết định PASS/MIXED/FAIL cho từng phase, không chỉ kết luận chung.

## 7. Trạng thái hiện tại

- [x] Code dùng một nguồn hình học chung cho PWM và diagnostics.
- [x] `MOTOR_NUM_POLSE=14U` suy ra đúng 7 pole-pair.
- [x] Firmware có log pole count/pole pairs/ripple order động.
- [x] `AElectrical6` có thể tính động tại order 42.
- [x] Mode 2 no-reversal 59°→60° vẫn bị chặn cho 7PP; mode 3
  shifted-reversal đã được tổng quát hóa theo chu kỳ điện 9363 raw tại P7.8.
- [x] Đã nhận diện giới hạn integer-cycle 9,363 raw.
- [ ] Tạo build profile/script 7PP độc lập và manifest đầy đủ.
- [ ] Chạy build/negative-build contract.
- [ ] P7.0 hardware checklist.
- [ ] P7.1 one-run smoke test.
- [ ] P7.2 ba-run feasibility.
- [ ] P7.3 repeatability batch.
- [ ] Tổng quát hóa one-turn tool cho electrical order 42 và fold không chia
  hết 360.
- [ ] P7.4 motor signature.
- [ ] P7.5 mapping A/B nếu gate kích hoạt.

## 8. Điều kiện hoàn thành

Lần thử motor 7PP hoàn thành ở mức engineering khi:

1. geometry trong build/log đúng 14 pole/7 pole-pair;
2. không có lỗi an toàn, direction, acquisition, settle hoặc motion;
3. P7.2 và P7.3 đạt gate repeatability đã khóa trước;
4. signature được tính riêng cho 7PP và order 42 được báo cáo đúng;
5. giới hạn mapping 9,363 raw đã được chấp nhận bằng dữ liệu hoặc đã được xử
   lý qua P7.5;
6. không có số liệu 7PP nào bị gộp vào baseline 6PP.

## 9. P7.7 — B0-B V2 one-run pilot

Sau khi smoke test và repeatability cho thấy motor 7PP di chuyển ổn định, build
thử tiếp theo chỉ bật một biến: equal approach theo reversal V2.

- `Profile=7PP_ENGINEERING_B0B_REVERSAL_V2_1RUN_V1`
- `ApproachProtocol=SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`
- `NL_APPROACH_MODE=1`, `ENABLE_B0B_EQUAL_APPROACH=1`
- một lần nhấn nút chỉ chạy một run; `AutoBatch=0`
- feedforward 79/126, creep, B0-B soft-start, sweep soft-start và CCW đều tắt

Không dùng V3 no-reversal vì guard hiện tại chỉ được xác nhận cho 6PP. Cũng
không dùng bias 79/126 của 6PP để tránh trộn ảnh hưởng equal approach với một
hệ số chưa được hiệu chỉnh cho 7PP.

Gate log của mỗi run:

1. boot manifest đúng profile/protocol ở trên;
2. có đúng một `APPROACH_RESULT`;
3. `ApproachStructuralValid=1`, không có acquisition/motion error;
4. dùng trường canonical `SHADOW_RESULT.ClosureErrorDeg` để so với mục tiêu
   `<0.2 deg`; `WindowP2P` không được thay thế closure;
5. thử A-B-A với cooldown cố định trước khi kết luận B0-B có cải thiện closure.

## 10. P7.8 — V3.2 shifted-reversal theo raw electrical cycle

Log P7.7 cho thấy V2 có thể đạt Closure `<0.2 deg`, nhưng hai run sau rơi
vào nhánh lock khác: `StartRaw` đổi từ khoảng 600 sang khoảng 65500,
`LockCommands` đổi từ 160 sang 40, settle target fail và Closure tăng lên
khoảng 3.4 deg. P7.8 dùng shifted-reversal tại zero điện kế tiếp để loại
bỏ phụ thuộc vào giả định point-59/point-60.

Geometry đã khóa cho 7PP:

```text
ElectricalCycleRaw = ceil(65536 / 7) = 9363
FinalTargetRaw     = 9363
LocalStepRaw       = 182
BackoffTargetRaw   = 9363 - 182 = 9181
```

Pre-position CW dùng các target rounded-grid 1 độ độc lập. Vì 9363 raw
tương ứng 51.428571 độ, sau target grid 51 độ (`9284 raw`) có thêm một
segment cuối `79 raw` tới đúng `9363`; không gộp toàn bộ pre-position vào
một ramp 40 tick. Sau settle tuyệt đối tại `initialAnchor + 9363`, protocol
lùi CCW đúng 182 raw về `9181`, settle tuyệt đối, rồi tiến CW đúng 182 raw
trong 40 tick về `9363` và settle lần cuối.

Build pilot:

- `Profile=7PP_ENGINEERING_V32_SHIFTED_REVERSAL_1RUN_V1`
- `ApproachProtocol=SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2`
- `NL_APPROACH_MODE=3`, một run mỗi lần nhấn nút
- `ReversalCount=2`
- feedforward, creep, mọi soft-start và CCW engineering đều tắt

Gate tối thiểu:

1. `PreRollCommandDeltaRaw=9363`;
2. `LocalBackoffCommandDeltaRaw=-182`;
3. `FinalCommandDeltaRaw=182`;
4. `ReversalCount=2`, `ApproachStructuralValid=1`;
5. `OriginShiftTargetErrorRaw` trong settle tolerance và acquisition sạch;
6. `MeasurementValid=1`, sau đó mới đánh giá
   `abs(SHADOW_RESULT.ClosureErrorDeg) < 0.2`.

## 11. P7.9 — Chẩn đoán hiện tượng khựng tại point 143–148

Log `1807-test 6.txt` đã tái hiện các run luân phiên VALID/INVALID, trong đó
run lỗi có `WRONG_POSITION`, `PollCount=101` và position error vượt 910 raw tại
point 143–148. Không nới settle tolerance hoặc chuyển sang batch trước khi
phân loại được ramp stall và settle-induced pause.

Plan thực thi độc lập:

- `docs/motor-7pp-stutter-diagnostic-plan.md`

## 12. P7.10 — Plan tích hợp từ chuỗi A→B

Chuỗi thử nghiệm A2→A5, Motion V2 và B0-B chứa các bằng chứng về fixed-phase
power, stick-slip, phase trajectory, encoder-seeded drag, noise MA600,
soft-start, creep, feedforward và precondition. Việc chuyển các bài học này
sang 7PP phải tách rõ cơ chế tái sử dụng được khỏi hằng số riêng của motor 6PP.

Plan điều phối và ma trận chuyển giao:

- `docs/motor-7pp-a-b-evidence-derived-test-plan.md`
