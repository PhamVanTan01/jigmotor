# Plan test 7PP suy ra từ chuỗi thử nghiệm A→B

Updated: 2026-07-24

Status: **READY FOR IMPLEMENTATION — engineering qualification**

## 1. Mục tiêu và phạm vi

Tài liệu này tổng hợp những gì chuỗi A2→A5, Motion V2 và B0-B đã chứng minh
trên hệ motor/JIG trước đây, sau đó chuyển thành một trình tự test phù hợp cho
motor 1807 7 cặp cực.

Mục tiêu trước mắt:

1. điều khiển motor 7PP đi đủ vòng, không khựng hoặc dừng dài bất thường;
2. phân biệt lỗi ramp, settle, ma sát/cogging, sector cơ khí và mapping pha;
3. tạo baseline 7PP riêng trước khi chạy batch 10 lần;
4. không tái sử dụng mù các offset, bias và ngưỡng đã tune trên motor 6PP.

Plan này không biến JIG thành thiết bị đo INL độc lập. Kết quả vẫn mô tả toàn
hệ motor + gá + nam châm + MA600.

## 2. Trạng thái 7PP hiện tại

Firmware hiện hành:

```text
Profile:          7PP_ENGINEERING_V32_SHIFTED_REVERSAL_1RUN_V1
Pole count:       14
Pole pairs:       7
Electrical cycle: 9363 raw
Electrical order: 42
Motion:           SCURVE40_ABSOLUTE_TICK_V2
Approach:         SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2
Power:            1.000
Runs/button:      1
Auto batch:       OFF
```

`1807-test 6.txt` có bốn run:

| Run | END | Wrong-position | Max settle error | Closure |
| ---: | --- | --- | ---: | ---: |
| 1 | VALID | 0 point | 898 raw / 4.933° | 0.279° |
| 2 | INVALID | point 143–147 | 1003 raw / 5.510° | 0.663° |
| 3 | VALID | 0 point | 877 raw / 4.818° | 0.115° |
| 4 | INVALID | point 143–148 | 1026 raw / 5.636° | 0.719° |

Approach của cả bốn run đều sạch và lặp lại:

- `ApproachStatus=OK`;
- `ApproachStructuralValid=1`;
- pre-roll target error 381–408 raw;
- final target error −63..−67 raw;
- không có SPI error, jump reject hoặc timing overrun.

Vì vậy ưu tiên hiện tại là **sweep tại point 135–160**, không phải thay tiếp
approach hoặc home.

## 3. Bằng chứng từ các plan A→B

### 3.1. Bảng tổng hợp

| Phase | Biến đã thử | Kết quả đã chứng minh | Bài học cho 7PP |
| --- | --- | --- | --- |
| A2C–A2F | fixed phase, power 6–10% | 6–9% safe nhưng không hội tụ; 10% có snap/step-limit | Không tìm alignment bằng cách tăng power fixed-phase |
| A3 | rotating capture + forward drag | following/drag hoạt động; random-start power ramp có snap | Phase trajectory có giá trị, nhưng phải seed torque gần zero |
| A4/A4B | encoder-seeded, forward-only drag | alignment ổn định hơn; khung safety đã được kiểm chứng | Kiến trúc có thể chuyển, offset và cycle không thể chuyển |
| A5 | hold tĩnh 2048 mẫu @1 kHz | MA600 tĩnh sạch; noise nhỏ hơn biến thiên Closure khoảng 10× | Không ưu tiên sửa SPI/filter; dùng hold tĩnh để phân loại sector |
| Motion V2 | S-curve 40 tick, cadence tuyệt đối | chuyển động mượt và có telemetry; giữ grid/capture contract | Giữ làm baseline A; instrument trước khi tune |
| B0-B soft-start | 1 ms so với 4 ms/tick | 4 ms làm tracking backoff/forward tệ hơn | “Chậm hơn” không mặc nhiên tốt; mọi đổi tốc độ phải A/B/A |
| B0-B creep | correction 8 raw có cap | endpoint tiến gần target rõ rệt trên 6PP | Cơ chế đáng tham khảo, nhưng không dùng hệ số 6PP cho 7PP |
| B0-B feedforward | bias 79/126 và 100/136 | endpoint có thể tốt hơn nhưng residual/Closure có thể xấu | Không dùng endpoint đẹp làm bằng chứng phép đo tốt |
| Adaptive precondition | đến khi hai sweep liên tiếp ổn định | logic hữu ích; run đầu có thể khác do warm-up | Chỉ bật sau khi single-run structural pass |
| V3/V3.2 | no-reversal và shifted-reversal | sector là confound thật; phải so A/B/A cùng sector | Giữ shifted-reversal hiện tại; không đổi sector khi test stutter |
| Closure review | point 0/360 và post-turn residual | `Motor OK` không đồng nghĩa Closure <0.2° | Structural motion và Closure là hai gate độc lập |

### 3.2. Những cơ chế được phép tái sử dụng

- S-curve quintic và cadence tuyệt đối;
- một biến cho mỗi firmware;
- A/B/A trên cùng motor, JIG và lần gá;
- prime output ở power 0 trước khi enable;
- forward-only phase trajectory khi cần alignment;
- safety gate step/travel/timing/acquisition;
- static/global evidence buffer, không UART trong cửa sổ chuyển động;
- giữ từng run riêng, không che run lỗi bằng trung bình;
- calibration batch không được dùng lại làm confirmation PASS.

### 3.3. Những giá trị không được chuyển trực tiếp

Các giá trị dưới đây thuộc motor/cấu hình 6PP:

```text
Electrical cycle 10923 raw
A3 offset 6742 raw
A4B/A5 offset 7971 raw
A4B power 35%
B0-B bias 79/126 raw
B0-B bias 100/136 raw
B0-B creep response và cap đã tune
H36 / family 36,72,108
Tracking max baseline khoảng 2.16°
```

Đối với 7PP:

```text
Electrical cycle = 9363 raw
Electrical order = 42
Electrical family = 42,84,126
Mechanical grid step vẫn = 182/183 raw
```

Mọi offset điện, power envelope, lag, step/travel limit dùng để quyết định
hiệu năng phải được đo lại. Các hard safety limit hiện có chỉ được giữ như
fail-safe ban đầu, không được gọi là acceptance 7PP đã xác nhận.

## 4. Nhận định kỹ thuật cho lỗi hiện tại

### 4.1. Điều đã loại trừ tương đối mạnh

- Không phải lỗi config MA600: gate 4/4 run pass.
- Không phải mất dữ liệu SPI: counters đều sạch.
- Không phải scheduler trễ: timing overrun bằng 0.
- Không phải approach thất bại: shifted-reversal 4/4 run complete.
- Không phải rotor đứng yên toàn vòng: motor đi đủ 371 điểm.

### 4.2. Cơ chế có xác suất cao

Đỉnh position error tại cùng point 143–148 nằm ngay quanh tolerance 910 raw.
Khi error vượt 910, settle chờ đến `PollCount=101`; 5–6 pause liên tiếp tạo
cảm giác motor khựng.

Hai nguyên nhân vật lý còn cần tách:

1. rotor đã chậm/plateau ngay trong ramp 40 tick;
2. ramp đã tiến bình thường nhưng rotor dừng ở equilibrium tĩnh lệch target.

Kết quả A2–A5 cho thấy stick-slip và equilibrium phụ thuộc vị trí là khả năng
thật; kết quả B0-B cho thấy chỉ tăng thời gian ramp có thể làm xấu hơn. Vì vậy
không được tune trước khi có trace từng tick tại vùng lỗi.

## 5. Kiến trúc test đề xuất

Toàn bộ chương trình được chia thành ba tầng:

```text
Tầng 1 — structural/motion
  config, direction, step, travel, ramp, settle, acquisition

Tầng 2 — repeatability
  cold/warm, cooldown, run-to-run, sector stability

Tầng 3 — measurement
  Closure, post-turn residual, RMS_AC, P2P, order 42
```

Không đọc kết quả tầng 3 để PASS khi tầng 1 chưa đạt.

## 6. P7-AB0 — Đóng băng baseline

Artifact baseline:

```text
Source commit: d24ca7c
Archive commit: 6600ddd
HEX SHA-256:
2F1995EDD5525EB89B8398A095DF2C0DE72536A367DDE92D9A72832CF23E3A8E
```

Việc cần làm:

- giữ artifact trong `builds/1807/`;
- xuất bảng một hàng/run từ `1807-test 6.txt`;
- ghi rõ run 1/3 VALID, run 2/4 INVALID;
- dùng baseline này làm leg A cho mọi A/B/A tiếp theo;
- không thay settle tolerance 910 raw.

`1807-test 6.txt` là evidence screening. Do bốn run được chạy trong một phiên
ngắn mà không có cooldown được firmware khóa, nó chưa phải batch repeatability.

## 7. P7-AB1 — Instrumentation-only tại vùng khựng

Profile:

```text
7PP_STUTTER_DIAG_P135_160_1RUN_V1
```

Giữ byte-equivalent:

- power 1.0;
- 40 tick/degree, 1 ms/tick;
- target grid 182/183 raw;
- settle 9 raw, target tolerance 910 raw, timeout 100 ms;
- approach V3.2 hiện tại;
- sampling và phép tính kết quả.

Chỉ bổ sung record sau khi motor disable:

```text
STUTTER_RAMP_STEP:
  Point, Tick, CommandRaw, ObservedRaw, ObservedDeltaRaw,
  LagRaw, AcquisitionResult, LatenessTicks

STUTTER_SETTLE_SAMPLE:
  Point, Poll, ElapsedMs, ObservedRaw, TargetErrorRaw,
  WindowP2PRaw, FinalSettleResult
```

Giới hạn:

- point 135..160;
- 26 × 40 ramp samples;
- buffer static/global;
- không truyền UART trong ramp/settle;
- buffer thiếu/overflow làm diagnostic invalid.

Gate software:

- Debug/Release: 0 error, 0 warning;
- tất cả contract hiện tại pass;
- test chứng minh motion constants giống baseline;
- build mới có profile ID và artifact riêng.

## 8. P7-AB2 — Tái hiện có kiểm soát

Cùng motor, JIG3 và lần gá:

```text
Power off >=10 phút -> Run 1
Motor off 120 giây  -> Run 2
Motor off 120 giây  -> Run 3
```

Không xoay tay và không remount.

Mỗi run phải báo:

- max settle error và point;
- wrong-position count;
- ramp progress 40 tick tại point 135..160;
- longest near-zero-progress sequence;
- backtrack count/max;
- ramp-end lag;
- settle correction;
- settle elapsed/poll count;
- approach errors;
- Closure và post-turn residual;
- video timestamp vùng khựng.

Gate:

- 3/3 config/acquisition/approach sạch;
- trace đầy đủ;
- ít nhất một run tái hiện `>910 raw` hoặc pause quan sát được.

Nếu chưa tái hiện, chạy thêm tối đa hai run cùng protocol. Không tune và không
chạy 10-run.

## 9. P7-AB3 — Phân loại nguyên nhân

### Class S — settle-induced pause

Chọn Class S khi:

- observed position vẫn tiến trong 40 tick;
- không có plateau/backtrack lớn trong ramp;
- ramp-end hoặc settled error ngoài ±910 raw;
- pause bắt đầu sau ramp và kết thúc tại poll 101.

### Class R — ramp stall/dynamic lag

Chọn Class R khi:

- nhiều tick liên tiếp gần như không có observed progress;
- lag tăng rõ trong ramp;
- rotor chỉ nhảy/đuổi kịp sau đoạn plateau.

### Class E — static equilibrium/load

Chọn Class E khi:

- ramp hoàn thành;
- settle window P2P nhỏ;
- vị trí ổn định nhưng lệch target 5° hoặc hơn;
- cùng vùng góc cơ khí tái hiện qua các run.

Có thể gắn `MIXED` nếu cả R và E cùng xuất hiện.

## 10. P7-AB4 — Static hold theo phương pháp A5

Chỉ mở khi Class E hoặc MIXED.

Tạo ba build diagnostic chỉ khác `HoldPoint`:

```text
7PP_STATIC_HOLD_P140_N2048_V1
7PP_STATIC_HOLD_P145_N2048_V1
7PP_STATIC_HOLD_P150_N2048_V1
```

Mỗi build:

- đi tới point bằng motion baseline;
- giữ nguyên command/power;
- lấy 2048 mẫu @1 kHz;
- không có UART trong cửa sổ hold;
- báo P2P, SD, drift, max step và mean target error.

Các dải A5 6PP chỉ là tham chiếu điều tra, không phải gate 7PP. Nếu P2P/drift
nhỏ nhưng mean target error lớn, xác nhận đây là equilibrium cơ–điện lệch,
không phải sensor noise.

## 11. P7-AB5 — A/B/A theo class

Chỉ chạy một nhánh, không chạy tất cả theo thói quen.

### Nhánh S: cadence A/B/A

| Leg | Cấu hình |
| --- | --- |
| A0 | settle baseline |
| B | fixed-cadence diagnostic, vẫn log wrong-position nhưng không giữ đến 100 ms |
| A1 | settle baseline |

Mục tiêu chỉ là xác nhận pause nhìn thấy do state machine. Leg B là
`DIAGNOSTIC_ONLY`, không dùng NL/Closure làm official.

### Nhánh R: ramp 40/80/40

| Leg | Commands/degree | Tick |
| --- | ---: | ---: |
| A0 | 40 | 1 ms |
| B | 80 | 1 ms |
| A1 | 40 | 1 ms |

Chỉ thay sweep ramp. Approach vẫn giữ 40 tick và shifted-reversal hiện tại.
Không dùng 4 ms/tick vì B0-B đã chứng minh thay đổi đó có thể xấu hơn.

B có triển vọng khi:

- max error vùng 135..160 giảm ít nhất 20% so với mean A0/A1;
- không có wrong-position;
- tracking ngoài vùng không xấu;
- A1 quay lại gần A0.

### Nhánh E: correction có feedback

Nếu rotor ổn định sai target, không thêm bias 6PP. Thiết kế một correction
7PP mới dựa trên encoder, có:

- deadband đo từ noise 7PP;
- step/cap fail-safe;
- log từng correction;
- A/B/A baseline/correction/baseline.

Build correction chỉ dùng cho **motion qualification**. Nếu correction được
áp trước capture, phép đo không còn hoàn toàn open-loop và phải có measurement
contract/profile mới; không được so NL trực tiếp với baseline như không có gì
thay đổi.

## 12. P7-AB6 — Alignment/phase trajectory, chỉ khi được kích hoạt

A2–A4 cho thấy encoder-seeded forward drag là kiến trúc alignment tốt hơn
fixed-phase. Tuy nhiên current 7PP approach đã 4/4 structural-valid, nên chưa
có lý do thay nó ngay.

Chỉ mở phase này nếu:

- start/approach error tương quan mạnh với stutter hoặc Closure;
- random start làm approach fail;
- shifted-reversal không lặp lại sector.

Khi mở:

1. đo offset 7PP mới, modulo 9363 raw;
2. không dùng 6742 hoặc 7971;
3. prime phase từ encoder ở power 0;
4. ramp power và kéo forward-only;
5. test ít nhất năm random start phủ bốn quadrant điện;
6. giữ step/travel/deadline/safe-stop;
7. artifact/profile hoàn toàn riêng.

Power 35% và các limit 6PP chỉ là điểm tham khảo thiết kế, không phải giá trị
được phép bật trực tiếp trên 7PP.

## 13. P7-AB7 — Kiểm tra sector và mapping

Trước tiên phân tích mỗi run theo:

- góc cơ khí;
- electrical phase hiện tại `raw % 9363`;
- electrical phase lý tưởng `(raw * 7) % 65536`;
- harmonic order 1, 2, 7, 14 và 42.

Chỉ mở A/B/A mapping `9363` so với direct-Q16 nếu lỗi lặp tại biên chu kỳ điện.
Nếu lỗi chỉ nằm ở một vùng cơ khí, ưu tiên gá, dây, tải và ma sát.

Không đổi mapping cùng lúc với ramp, settle hoặc approach.

## 14. P7-AB8 — Candidate confirmation

Sau khi một nhánh A/B/A xác nhận nguyên nhân, tạo candidate 1-run và chạy ba
run cùng lần gá, cooldown 120 giây.

Gate structural:

- 3/3 `END.Status=VALID`;
- 0 wrong-position;
- không có `PollCount=101`;
- max settle error `<820 raw`, tạo margin 90 raw so với gate;
- acquisition/timing sạch;
- approach 3/3 complete và structural-valid;
- không xuất hiện vùng lỗi mới;
- motor không rung, snap, quá nhiệt hoặc chạm current limit.

Gate measurement báo cáo riêng:

- Closure từng run và pass count tại 0.2°;
- post-turn residual;
- RMS_AC, robust P2P và tracking;
- `AElectrical6` tại order 42;
- không gộp Closure fail vào một average pass.

Candidate structural pass nhưng Closure fail được ghi:

```text
MOTION_PASS / MEASUREMENT_NOT_QUALIFIED
```

Không đổi code để làm Closure đẹp trước khi motion đã khóa.

## 15. P7-AB9 — Batch repeatability

Chỉ mở sau P7-AB8 pass:

```text
1 precondition, EligibleForStatistics=0
10 official runs
120 s motor-off cooldown
same mount, no reset/remount
```

Không bật adaptive precondition trong batch đầu tiên; giữ một precondition để
có baseline so sánh. Nếu official run 1 lệch có hệ thống, tạo A/B/A riêng cho
fixed-one so với adaptive-two-consecutive. Không loại run 1 hậu nghiệm.

Batch đạt khi:

- precondition structural-valid;
- 10/10 official structural-valid;
- không cherry-pick;
- cooldown hợp lệ;
- không có drift motion/thermal theo run;
- Closure và order-42 report đúng pipeline 7PP.

Batch đầu dùng để thiết lập envelope 7PP. Ngưỡng suy ra từ batch này phải được
khóa rồi xác nhận bằng batch độc lập; không dùng chính calibration batch để
tuyên bố PASS.

## 16. Tooling 7PP bắt buộc

Analyzer phải:

- group theo `MotorPolePairs=7`;
- lấy closure index từ `AnalysisPoints=360`, không hardcode 256;
- tính electrical order động bằng `6 * polePairs = 42`;
- hỗ trợ family 42/84/126;
- không dùng `folded_10deg` hoặc H36 làm signature 7PP;
- fold theo circular electrical phase/interpolation vì 360 không chia hết 42;
- xuất một hàng cho mọi run, kể cả INVALID;
- tách `StructuralValid`, `ClosureValid` và `ResultClass`.

Synthetic contract:

- sine order 42 phục hồi đúng amplitude/phase;
- metadata 6PP/7PP mismatch phải reject;
- run wrong-position không được lọt vào official-valid;
- closure point 360 phải khác được point 256 trong negative fixture.

## 17. Thứ tự implementation

```text
I0  Freeze baseline + analyzer table
I1  Instrument point 135..160
I2  Build/test P7-AB1
I3  Hardware P7-AB2
I4  Classify S/R/E
I5  Implement đúng một A/B/A branch
I6  Candidate 3-run confirmation
I7  Generalize order-42 tooling
I8  Precondition + 10 official
```

Không implement I5 trước khi có trace I3.

## 18. Decision tree

```text
Config/acquisition/timing lỗi
  -> sửa structural layer, không tune motor

Ramp tiến đều nhưng poll 101
  -> Class S, cadence A/B/A

Ramp plateau/backtrack
  -> Class R, 40/80/40 A/B/A

Rotor tĩnh sạch nhưng lệch target
  -> Class E, static hold rồi feedback-correction A/B/A

Lỗi lặp theo góc cơ khí
  -> kiểm tra gá/dây/tải

Lỗi lặp theo biên pha điện
  -> mapping 9363/direct-Q16 A/B/A

Motion 3/3 pass, Closure fail
  -> khóa motion; mở measurement investigation riêng

Motion + measurement pilot pass
  -> batch 1+10, sau đó confirmation độc lập
```

## 19. Quan hệ với các plan khác

Tài liệu này là plan điều phối dựa trên evidence A→B. Chi tiết implementation
trace/stutter nằm tại:

- `docs/motor-7pp-stutter-diagnostic-plan.md`

Geometry, safety và qualification tổng thể nằm tại:

- `docs/motor-7pp-engineering-test-plan.md`
- `docs/motor-7pp-code-implementation-plan.md`

Khi có khác biệt, trạng thái firmware thực tế và plan mới hơn này được ưu tiên;
không dùng các guard cũ từng cấm V3-7PP sau khi mode 3 đã được tổng quát hóa và
contract hiện tại đã build thành công.
