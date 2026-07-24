# Plan chẩn đoán hiện tượng khựng motor 1807 7PP

Updated: 2026-07-24

Status: **READY FOR IMPLEMENTATION — engineering diagnostic only**

## 1. Mục tiêu

Xác định nguyên nhân motor 1807 7 cặp cực có lúc khựng và làm phép đo
`INVALID` tại một số điểm, sau khi lần chạy trước đã hoàn thành.

Plan phải trả lời riêng ba câu hỏi:

1. rotor thực sự ngừng tiến trong ramp hay chỉ dừng lâu vì firmware chờ settle;
2. sai lệch có gắn với một vùng góc cơ khí, một pha điện, hay lịch sử
   nhiệt/ma sát giữa các lần chạy;
3. thay đổi nhỏ nhất nào loại bỏ `WRONG_POSITION` mà không che lỗi bằng cách
   nới ngưỡng.

Không dùng plan này để kết luận chất lượng MA600 hoặc PASS/FAIL sản phẩm.

## 2. Bằng chứng kích hoạt plan

Nguồn: `1807-test 6.txt`, cùng firmware và cùng lần gá.

| Run | END | Điểm `WRONG_POSITION` | Max position error | Closure |
| ---: | --- | --- | ---: | ---: |
| 1 | VALID | không | 898 raw / 4.933° | 0.279° |
| 2 | INVALID | 143–147 | 1003 raw / 5.510° | 0.663° |
| 3 | VALID | không | 877 raw / 4.818° | 0.115° |
| 4 | INVALID | 143–148 | 1026 raw / 5.636° | 0.719° |

Các điểm lỗi nằm trong cùng một vùng:

- command khoảng 197–202° cơ khí;
- measured khoảng 202–207° cơ khí;
- rotor ổn định nhưng lệch target quá `910 raw` xấp xỉ 5°;
- mỗi điểm lỗi có `PollCount=101`, nên firmware giữ khoảng 100 ms thay vì
  khoảng 9 poll như điểm bình thường;
- SPI error, jump reject và timing overrun đều bằng 0;
- approach 7PP có `Status=OK`, `ApproachStructuralValid=1`.

Giả thuyết ban đầu mạnh nhất là đỉnh sai lệch cơ–điện nằm sát ngưỡng 5°.
Khi vượt ngưỡng, settle chờ hết timeout tại 5–6 điểm liên tiếp, tạo cảm giác
khựng. Chưa đủ bằng chứng để kết luận nguồn gốc của sai lệch là cogging,
ma sát tải, tốc độ ramp hay ánh xạ pha.

## 3. Baseline và nguyên tắc khóa biến

Baseline bắt buộc:

```text
Source commit:       d24ca7c
Archive commit:      6600ddd
Profile:             7PP_ENGINEERING_V32_SHIFTED_REVERSAL_1RUN_V1
Protocol:            SCURVE_ECYCLE_PREROLL_LOCAL_REVERSAL_V2
HEX SHA-256:         2F1995EDD5525EB89B8398A095DF2C0DE72536A367DDE92D9A72832CF23E3A8E
Runs per button:     1
Auto batch:          OFF
Sweep:               CW, 40 tick/degree, 1 ms/tick
Power:               1.000
Settle tolerance:    910 raw
Settle timeout:      100 ms
```

Trong mỗi phép A/B/A:

- giữ nguyên motor, JIG3, nguồn, current limit, dây, gá và chiều quay;
- không tháo/lắp hoặc xoay tay giữa A–B–A;
- nghỉ motor-off đúng 120 giây giữa các run và ghi thời gian thực;
- không thay approach, PID home, power, grid, sampling và motion cùng lúc;
- mỗi HEX có profile ID, git commit, manifest và SHA-256 riêng;
- chỉ thay đúng biến được nêu trong phase đó.

Không chạy tự động 10 lần khi phase chẩn đoán chưa pass.

## 4. Các giả thuyết cần phân biệt

| ID | Giả thuyết | Dấu hiệu xác nhận |
| --- | --- | --- |
| H1 | Khựng nhìn thấy chủ yếu do settle chờ đủ 100 ms | ramp vẫn tiến; pause chỉ xuất hiện sau ramp và trùng `PollCount=101` |
| H2 | Rotor thiếu tiến triển ngay trong ramp | nhiều tick liên tiếp có observed delta gần 0 hoặc lag tăng ngay trong 40 tick |
| H3 | Lỗi gắn với vùng góc cơ khí/tải | cực đại luôn nằm quanh raw/góc cơ khí giống nhau qua các run |
| H4 | Lỗi gắn với pha điện/cogging | mẫu lặp theo chu kỳ điện khoảng 9363 raw hoặc harmonic liên quan 7/14/42 |
| H5 | Tốc độ ramp quá nhanh cho vùng mô-men yếu | ramp 80 tick giảm rõ lag và số wrong-position so với 40 tick |
| H6 | Lịch sử nhiệt/ma sát giữa các run | kết quả thay theo cooldown hoặc thứ tự run, không chỉ theo góc |
| H7 | Mapping nguyên 9363 raw gây lỗi biên pha | lỗi tập trung gần biên chu kỳ điện và giảm với direct-Q16 mapping |

H7 chỉ được mở sau khi D1–D4 cho thấy tương quan với biên pha. Point 143–148
hiện chưa đủ bằng chứng để ưu tiên thay mapping.

## 5. D0 — Kiểm tra phần cứng và điều kiện dừng

Trước mỗi nhóm test:

- [ ] trục quay tự do khi motor off, không cạ cơ khí hoặc kéo căng dây;
- [ ] gá, nam châm và sensor không dịch chuyển;
- [ ] nguồn/current limit đúng cấu hình baseline;
- [ ] log idle MA600 sạch trước khi nhấn nút;
- [ ] ghi thời điểm kết thúc cooldown;
- [ ] camera quay được chuyển động và âm thanh tại vùng khựng;
- [ ] có thể cắt nguồn motor ngay lập tức.

Dừng ngay nếu có rung mạnh, sai chiều, kẹt thật, tiếng va chạm, driver/current
limit tác động, nhiệt tăng bất thường, reset hoặc HardFault. Không lặp lại để
“lấy thêm dữ liệu” sau một dấu hiệu an toàn.

## 6. D1 — Build instrumentation-only

Tạo build:

```text
Profile: 7PP_STUTTER_DIAG_P135_160_1RUN_V1
Behavior: byte-equivalent baseline motion
Instrumented points: 135..160
Official/result policy: ENGINEERING_ONLY
```

Không thay đổi command, delay, settle, timeout hoặc ngưỡng. Chỉ bổ sung log:

### 6.1. Ramp trace

Với mỗi point 135..160 và từng tick 1..40, lưu:

- command unwrapped raw;
- observed unwrapped raw;
- observed delta so với tick trước;
- target lag `observed - command`;
- acquisition result và tick lateness.

Record đề xuất:

```text
STUTTER_RAMP_STEP,TestID=...,Point=...,Tick=...,CommandRaw=...,
ObservedRaw=...,ObservedDeltaRaw=...,LagRaw=...,Acq=...,LatenessTicks=...
```

### 6.2. Settle trace

Với point 135..160, lưu từng poll cho đến khi OK hoặc hết timeout:

- elapsed time;
- observed raw;
- target error raw;
- window P2P/stability;
- kết quả cuối `OK`, `TIMEOUT` hoặc `WRONG_POSITION`.

Record đề xuất:

```text
STUTTER_SETTLE_SAMPLE,TestID=...,Point=...,Poll=...,ElapsedMs=...,
ObservedRaw=...,TargetErrorRaw=...,WindowP2PRaw=...
```

### 6.3. Ràng buộc implementation

- buffer phải là static/global có kích thước compile-time, không đặt thêm mảng
  lớn trên task stack;
- không truyền UART trong lúc ramp/settle;
- chỉ phát trace sau khi motor đã disable;
- instrument đúng 26 point × 40 ramp tick, không log toàn bộ 371 point;
- nếu buffer overflow hoặc thiếu record, run phải mang cờ diagnostic invalid;
- Debug và Release phải có 0 error, 0 warning;
- contract test phải xác nhận motion constants giống baseline.

## 7. D2 — Tái hiện có kiểm soát

Với HEX D1, chạy ba run độc lập, cùng lần gá:

```text
Cold/rest >= 10 phút -> Run 1
Motor off 120 giây  -> Run 2
Motor off 120 giây  -> Run 3
```

Mỗi run ghi:

- max absolute position error và point tương ứng;
- số `WRONG_POSITION` trong toàn vòng và trong point 135..160;
- `PollCount` từng point 135..160;
- Closure initial và hold-200;
- tracking RMS/max;
- approach target errors;
- video timestamp của khựng;
- thời gian nghỉ thực tế.

Gate đủ dữ liệu:

- 3/3 acquisition sạch;
- 3/3 approach structural-valid;
- trace đủ 26 × 40 ramp sample;
- ít nhất một run tái hiện max error trên 910 raw hoặc video khựng.

Nếu không tái hiện sau ba run, không tune. Chạy thêm tối đa hai run cùng
protocol để phân loại intermittent; không chuyển sang batch 10 run.

## 8. D3 — Phân loại ramp hay settle

Tính riêng tại point 135..160:

- ramp start/end observed raw;
- tổng observed progress trong 40 tick;
- final ramp lag;
- số tick có `abs(ObservedDeltaRaw) <= 1`;
- chuỗi dài nhất của các tick gần như không tiến;
- số backtrack và backtrack lớn nhất;
- settle correction từ ramp-end đến settled position;
- thời gian settle thực tế.

Kết luận:

- **H1/settle-induced pause:** ramp progress liên tục, không có plateau dài,
  nhưng sau ramp error vẫn ngoài ±910 raw và settle giữ đến poll 101;
- **H2/ramp stall:** observed progress bị plateau/backtrack ngay trong ramp,
  lag tăng trước khi settle bắt đầu;
- **mixed:** cả ramp plateau và settle timeout xuất hiện.

Không gọi `WRONG_POSITION` là motor kẹt nếu trace cho thấy rotor ổn định và vẫn
tiến qua vùng đó.

## 9. D4 — A/B/A cadence, chỉ khi H1 chiếm ưu thế

Mục tiêu là xác nhận pause nhìn thấy có phải do nhánh chờ 100 ms hay không.

| Leg | Cấu hình |
| --- | --- |
| A0 | baseline settle hiện tại |
| B | fixed-cadence diagnostic: không kéo dài quá cadence bình thường; vẫn log wrong-position, không đổi tolerance |
| A1 | trở lại baseline settle |

Thứ tự A0–B–A1, mỗi leg một run, cooldown 120 giây. B phải mang profile/result
`DIAGNOSTIC_ONLY`; dữ liệu của B không được gộp vào NL/Closure baseline.

Xác nhận H1 nếu:

- pause 100 ms biến mất ở B và quay lại ở A1;
- vùng position error vẫn tồn tại ở cả ba leg;
- không có SPI/timing fault mới.

Nếu B chỉ làm tracking xấu dần hoặc xuất hiện mất đồng bộ rõ rệt, loại phương án
fixed cadence; không dùng nó làm fix.

## 10. D5 — A/B/A tốc độ ramp, chỉ khi H2 hoặc mixed

Giữ nguyên power và settle:

| Leg | Commands/degree | Tick |
| --- | ---: | ---: |
| A0 | 40 | 1 ms |
| B | 80 | 1 ms |
| A1 | 40 | 1 ms |

B chỉ giảm tốc độ chuyển target; không tăng power và không thêm feedforward.
Approach phải giữ baseline, chỉ sweep point-to-point đổi sang 80 tick.

Tốc độ được coi là nguyên nhân đáng kể nếu B đồng thời:

- giảm max error vùng 135..160 ít nhất 20% so với trung bình hai leg A;
- không còn `WRONG_POSITION`;
- không tạo lỗi mới ngoài vùng;
- A1 quay lại gần A0.

Nếu error cuối settle gần như không đổi dù ramp chậm hơn, ưu tiên static
cogging/load equilibrium thay vì quán tính.

## 11. D6 — Phân biệt góc cơ khí và pha điện

Chỉ thực hiện bằng phân tích trước, chưa remount:

1. lập curve `PositionErrorRaw` theo góc cơ khí cho từng run;
2. chuyển cùng dữ liệu sang electrical phase bằng cả:
   - mapping hiện tại `raw % 9363`;
   - phase lý tưởng `(raw * 7) % 65536`;
3. kiểm tra cực đại tại order 1, 2, 7, 14 và 42;
4. kiểm tra lỗi có lặp quanh bảy biên chu kỳ điện hay chỉ một vùng cơ khí.

Decision:

- chỉ một vùng cơ khí cố định: kiểm tra tải, dây, gá và ma sát trước;
- lặp theo bảy chu kỳ: mở thử nghiệm commutation/cogging riêng;
- tập trung tại biên integer-cycle: mới mở A/B/A mapping 9363 so với direct-Q16;
- không có coherence: ưu tiên lịch sử ma sát/nhiệt và tăng số run có cooldown.

Không remount hoặc đổi hướng CCW trong cùng dataset D1–D6.

## 12. Candidate fix và thứ tự ưu tiên

Chỉ chọn fix sau khi có kết luận D3–D6:

1. sửa cadence/settle state machine nếu pause là artifact của timeout;
2. giảm tốc ramp toàn vòng nếu D5 xác nhận thiếu tiến triển động;
3. thiết kế correction/closed-loop settle riêng nếu rotor ổn định sai target;
4. compensation theo góc chỉ khi mẫu lặp lại qua đủ run và lần gá;
5. direct-Q16 mapping chỉ khi D6 xác nhận lỗi biên pha.

Mỗi candidate phải dùng A/B/A và một biến duy nhất. Không được coi việc tăng
`SettleTargetToleranceRaw` trên 910 là fix; đó chỉ là thay gate.

## 13. Tiêu chí chấp nhận candidate

Sau A/B/A causal pass, tạo candidate build 1-run và chạy ba run cùng lần gá,
cooldown 120 giây.

Candidate đạt mức engineering khi:

- 3/3 `END.Status=VALID`;
- 0 point `WRONG_POSITION`;
- max absolute settle position error dưới 820 raw, tạo tối thiểu 90 raw margin
  so với gate 910 raw;
- không có pause bất thường trên video và không có `PollCount=101`;
- 0 timing overrun, transport error, jump reject và failed sample;
- approach vẫn `Status=OK`, `ApproachStructuralValid=1`;
- tracking RMS/max không xấu hơn baseline;
- không phát sinh vùng lỗi mới;
- Closure được báo cáo riêng; mục tiêu `< 0.2°` chỉ đánh giá sau khi motion
  structural đã pass.

Ngưỡng 820 raw là gate engineering của candidate trong plan này, không phải
giới hạn chất lượng sản phẩm.

## 14. File bằng chứng phải lưu

Mỗi build/run phải có:

- HEX/ELF/MAP, manifest, source commit và SHA-256;
- log UART nguyên bản từ boot;
- CSV analyzer;
- bảng point 135..160;
- ramp/settle trace;
- video có tên khớp TestID/run;
- cooldown thực tế và ghi chú nguồn/current limit;
- quyết định theo H1–H7;
- bảng A/B/A trước khi chọn fix.

Lưu firmware dưới:

```text
builds/1807/<profile>-<commit>/
```

Không ghi đè firmware baseline hoặc artifact đã lưu.

## 15. Decision tree

```text
D1 không giữ motion byte-equivalent / log làm timing đổi
  -> sửa instrumentation, chưa chạy hardware

D2 không tái hiện trong tối đa 5 run có cooldown
  -> kết luận intermittent chưa đủ dữ liệu, không tune

D3 cho thấy ramp tiến đều + poll 101
  -> D4 cadence A/B/A

D3 cho thấy plateau/backtrack trong ramp
  -> D5 tốc độ A/B/A

D6 cho thấy một vùng góc cơ khí
  -> kiểm tra tải/gá/dây trước khi sửa commutation

D6 cho thấy lặp theo pha điện hoặc biên 9363
  -> mở thử nghiệm mapping/commutation riêng

Candidate đạt 3/3 structural với margin
  -> mới xem xét batch repeatability
```
