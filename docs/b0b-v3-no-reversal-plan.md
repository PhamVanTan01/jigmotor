# B0-B V3 — CW no-reversal approach plan

## 1. Mục tiêu

V3 kiểm tra một giả thuyết duy nhất: sai lệch Closure phụ thuộc product hiện
tại chủ yếu được tạo bởi sự kiện đảo chiều trong maneuver
`backoff -> forward`, không phải bởi nhiễu acquisition hoặc một correction
bias chung còn thiếu.

V3 phải:

- loại bỏ hoàn toàn đảo chiều trước khi capture point 0;
- giữ nguyên firmware đo, grid 360 điểm, 10 điểm hậu vòng, 64 sample/point,
  công thức NL/Closure và sweep CW chính;
- không dùng feedforward bias, creep hoặc soft-start trong approach V3;
- không dùng MA600 closed-loop trong sweep chính để tránh ép chính encoder
  DUT về target và che mất NL;
- tạo đủ log để chứng minh đường đi thực sự không đảo chiều và đánh giá
  endpoint độc lập với Closure.

Protocol ID đề xuất:

```text
SCURVE_CW_PREROLL_NO_REVERSAL_V1
```

Build label đề xuất:

```text
b0b-v3-cw-preroll-no-reversal-v1
```

## 2. Baseline đã có

Baseline thực dụng là V2 bias `79/126 raw`, cùng JIG1 và cùng firmware đo
(cùng `BuildID=Jul 22 2026 11:10:59`, xác nhận qua đối chiếu trực tiếp với
`build_info.txt` của build V2 và log thô của cả 5 product).

`Closure mean` dưới đây là **canonical** `SHADOW_RESULT.ClosureErrorDeg`
(quy ước `MEASURED_MINUS_TARGET`) — xem khóa quy ước dấu ở mục 4.
`Residual RMS` là `ClosureNormalizedDelta` RMS (10 điểm hậu vòng, 361-370)
tính trực tiếp từ `DATA.Error` (quy ước legacy `TARGET_MINUS_MEASURED`) —
xem công thức ở mục 4. Hai cột dùng hai nguồn dữ liệu khác nhau có chủ ý,
không được trộn.

| Product | Closure mean (canonical) | Closure pass | Endpoint both-valid | Residual RMS (legacy) | Residual SD | Repeatability 2.77×SD |
|---|---:|---:|---:|---:|---:|---:|
| P03 | +0.2588° | 0/10 | 6/10 | 0.36834° | 0.01554° | 0.04305° |
| P02 (n=20, 2 batch) | +0.0126° | 20/20 | 0/20 | 0.23288° | 0.00843° | 0.02335° |
| P04 | +0.0385° | 10/10 | 8/10 | 0.39664° | 0.02218° | 0.06144° |
| P05 | -0.0166° | 10/10 | 10/10 | 0.41908° | 0.02250° | 0.06232° |
| P06 (n=20, 2 batch) | -0.14021° | 20/20 | 14/20 | 0.27279° | 0.01258° | 0.03486° |

P03 và P06 là cặp pilot bắt buộc vì chúng nằm ở hai phía đối lập của
Closure, cách nhau khoảng **0.399°** (đã cập nhật theo baseline P06 n=20 ở
trên; số cũ 0.406° dùng baseline P06 n=10 đã lỗi thời). Nếu một approach
chung không làm hai product này hội tụ thì chưa có lý do test toàn bộ
product.

**Quan trọng — lý do residual phải là metric chính, không chỉ log phụ:**
P04 và P05 có Closure tốt nhất trong bảng (gần 0) nhưng lại có residual hậu
vòng **xấu nhất** (0.397° và 0.419°, cao hơn cả P03). Closure một mình
không đủ để đánh giá V3 — xem mục 7.2b.

## 3. Maneuver V3

### 3.1. Nguyên lý

Sau `MoveToZeroAndCheckDirection()` và `LockStartPosition()`, command đang ở
electrical phase 0. Không được lùi CCW rồi tiến CW như V2.

Với motor 12 pole/6 pole-pair hiện tại:

1. Acquire và settle initial anchor tại phase 0.
2. Pre-roll CW: **59 lệnh `RampCommandToTarget()` độc lập, mỗi lệnh 1 grid
   step (~1°), không phải một lệnh ramp duy nhất tới 59°** — xem cảnh báo
   bắt buộc ngay dưới.
3. Settle tại pre-roll target (point-59, ~10741 raw).
4. Ramp tiếp CW đúng một bước grid 1 deg (1 lệnh `RampCommandToTarget()`
   nữa) tới electrical zero kế tiếp, khoảng 60 deg cơ khí tính từ initial
   anchor.
5. Settle tại point-0 candidate.
6. Dùng final settled sample làm `sweepOriginUnwrapped`.
7. Chuẩn hóa command-domain về 0 tương đương modulo điện, không tạo chuyển
   động, rồi chạy sweep point 0..370 hiện tại không thay đổi.

**Cảnh báo bắt buộc — pre-roll KHÔNG được gọi `RampCommandToTarget()` một
lần với target 59°:** hàm này luôn chạy đúng `NL_SCURVE_SEGMENT_TICKS=40`
tick cho MỌI lệnh, bất kể khoảng cách target
(`Core/Src/nonlinear_test.c:1636-1637`, vòng lặp `for (commandIndex = 1;
commandIndex <= NL_SCURVE_SEGMENT_TICKS; ...)`). Gọi một lần với target
~10741 raw (59°) sẽ lệnh động cơ di chuyển ~10741 raw trong 40 tick (~40
ms, trung bình ~268 raw/tick) — nhanh gấp ~59 lần tốc độ 1 bước grid bình
thường (182 raw/40 tick ≈ 4.55 raw/tick), nguy cơ mất đồng bộ động cơ rất
cao. Pre-roll **bắt buộc** là vòng lặp 59 lệnh `RampCommandToTarget()`
riêng biệt, mỗi lệnh đi đúng 1 grid step, không settle giữa các segment
(chỉ settle tại point-59 và point-60):

```c
for (point = 1; point <= 59; point++)
{
    target = NlTargetRawMagnitudeForPoint(point);
    RampCommandToTarget(..., target, ...);   /* 40 tick/lệnh, không settle */
}
/* settle tại point-59 (pre-roll target) */

target = NlTargetRawMagnitudeForPoint(60);
RampCommandToTarget(..., target, ...);       /* final local leg, có log per-tick */
/* settle tại point-60 (point-0 candidate) */
```

```text
Pre-roll: 59 × 40 tick = 2360 lệnh (chỉ log start/end/duration/settle/acq counters)
Final:     1 × 40 tick =   40 lệnh (log per-tick đầy đủ, giống sweep hiện tại)
Tổng:                     2400 lệnh
```

Target từng segment lấy từ `NlTargetRawMagnitudeForPoint()` — đúng hàm
rounded-grid mà sweep chính đang dùng, không cộng lặp 182 bằng tay (tránh
lệch tích lũy do làm tròn từng bước).

Target phải sinh bằng cùng rounded-grid rule đang dùng cho sweep, không cộng
lặp literal 182:

```text
pre-roll target = rounded target tại (electrical-cycle mechanical angle - 1 deg)
final target    = rounded target tại một electrical-cycle mechanical angle
```

Đối với cấu hình 6 pole-pair hiện tại, giá trị dự kiến xấp xỉ:

```text
pre-roll command ~= 10741 raw
final command    ~= 10923 raw
final local leg  ~= 182 raw
```

Hai đoạn đều có delta command dương. `ReversalCount` phải bằng 0.

**Khóa định nghĩa `ReversalCount` (áp dụng cả B và A0):** chỉ đếm số lần
đổi dấu **delta giữa các motion segment thực sự gửi lệnh tới động cơ**
(tức mỗi lần gọi `RampCommandToTarget()`/tương đương, có `Motor_SetElectricalPos`
thật). Hai trường hợp KHÔNG được tính:

- **Rebase command-domain** ở bước 7 (mục 3.1: "Chuẩn hóa command-domain
  về 0 tương đương modulo điện, không tạo chuyển động") — đây là bookkeeping
  (commandPos đổi giá trị số học từ ~10923 về 0 do modulo điện), không phát
  lệnh động cơ, không có `Motor_SetElectricalPos` mới tương ứng. Nếu
  `ReversalCount` được tính bằng cách quét thô mọi thay đổi giá trị
  `commandPos`, bước rebase này có thể trông giống một lần đổi dấu giả và
  bị đếm nhầm.
- **Delta bằng 0 do lượng tử hóa S-curve** — `NlSmoothstepCommandRaw()` có
  thể cho hai tick liên tiếp cùng giá trị làm tròn gần đầu/cuối đoạn; delta
  0 không có dấu, phải bỏ qua, không tính là đổi dấu theo bất kỳ chiều nào.

Cách an toàn: tính `ReversalCount` từ chuỗi **target tuyệt đối của từng
motion segment đã gọi `RampCommandToTarget()`** (ví dụ dãy
`NlTargetRawMagnitudeForPoint()` đã dùng làm target cho mỗi lệnh), đếm số
lần dấu của `(target[k] − target[k-1])` đổi chiều so với lần trước đó có
delta khác 0 — không quét trực tiếp biến `commandPos` nội bộ (biến này bị
rebase và có thể gây nhiễu như trên).

**Khóa target settle tuyệt đối (bắt buộc, không dùng anchor chuỗi):** V2
hiện tại tính `expectedPoint0Unwrapped = backoffAnchorUnwrapped +
NL_B0B_APPROACH_BACKOFF_RAW` (`Core/Src/nonlinear_test.c:3117`) — tức
target settle của bước sau được tính **tương đối theo vị trí encoder quan
sát được ở bước trước** (`backoffAnchorUnwrapped`), không phải theo một
target tuyệt đối cố định. Nếu B/A0 tái dùng pattern này để nối tiếp
pre-roll→final, sai số settle của pre-roll sẽ cộng dồn vào target settle
của final — B và A0 khi đó có thể cùng lệnh command point-60 nhưng settle
tại hai vị trí encoder tuyệt đối khác nhau, làm sector confound (mục 3.1
"Lưu ý về sector cơ khí" dưới đây) quay lại dù đã sửa command target.

B **phải** dùng target tuyệt đối tính thẳng từ `initialAnchorUnwrapped`,
không nối chuỗi qua anchor trung gian:

```c
int64_t expectedPoint59 =
    initialAnchorUnwrapped + NlTargetRawMagnitudeForPoint(59);
int64_t expectedPoint60 =
    initialAnchorUnwrapped + NlTargetRawMagnitudeForPoint(60);
```

- Settle pre-roll (`WaitForPointSettle`) dùng `expectedPoint59`.
- Settle final dùng `expectedPoint60`.
- **Không** tính final settle target bằng `preRollAnchor + 182` (đây chính
  là pattern lỗi của V2 nêu trên, không được tái sử dụng cho V3).

Diagnostics tương ứng:

```c
PreRollTargetErrorRaw =
    preRollFinal - expectedPoint59;

FinalObservedDeltaRaw =
    finalSample - preRollFinal;

FinalTargetErrorRaw =
    FinalObservedDeltaRaw
    - (NlTargetRawMagnitudeForPoint(60) - NlTargetRawMagnitudeForPoint(59));

OriginShiftTargetErrorRaw =
    (finalSample - initialAnchorUnwrapped)
    - NlTargetRawMagnitudeForPoint(60);
```

**Lưu ý về sector cơ khí:** point-0 của V3-B nằm ở zero điện *kế tiếp*, lệch
khoảng +60° cơ khí so với zero điện ban đầu (nơi A0/V1/V2 hiện đang capture
point 0). Đây không phải chi tiết phụ — residual hậu vòng và harmonic có
thể phụ thuộc sector tuyệt đối trên encoder/magnet, nên B và bất kỳ baseline
reversal nào dùng để so sánh nhân quả (A0) đều phải capture point 0 tại
**cùng một zero điện**. Xem sửa đổi A0 ở mục 6.2 và giới hạn so sánh
harmonic/StartRaw ở mục 6.3.

### 3.2. Phần giữ nguyên tuyệt đối

- `RampCommandToTarget()` và quintic 40 tick/1 ms;
- power 1.0;
- sweep point 0..370;
- target grid rounded 182/183 raw;
- settle rule và acquisition context liên tục;
- legacy DATA và shadow canonical DATA;
- Closure point index 360;
- cách tính RMS_AC, A36, P2P, NL và harmonic;
- precondition 1 sweep, 10 official run, cooldown 120 s.

V3 V1 dùng cố định 59°/60° (suy từ 6 pole-pair hiện tại), nên bắt buộc
compile guard:

```c
#if MOTOR_POLE_PAIRS != 6
#error "V3 no-reversal V1 is validated only for 12-pole/6-pole-pair motors"
#endif
```

Nếu sau này hỗ trợ pole count khác, pre-roll/final target phải tính lại
theo `MOTOR_COUNT_PER_ELECTRICAL_CYCLE`/rounded-grid rule thực tế (ví dụ
tái dùng trực tiếp `NlTargetRawMagnitudeForPoint()` với index tương ứng
electrical-cycle-minus-one-grid-step và electrical-cycle), không giả định
chu kỳ điện là một số nguyên độ.

### 3.3. Feature isolation

Build V3-B phải cưỡng chế:

```text
ENABLE_B0B_APPROACH_FEEDFORWARD = 0
ENABLE_B0B_APPROACH_CREEP       = 0
ENABLE_B0B_APPROACH_SOFT_START  = 0
ENABLE_CCW_ENGINEERING_TEST     = 0
```

Thêm compile-time guard để V3 no-reversal không thể vô tình được build cùng
feedforward/creep/soft-start. Không thay tuning PID home hoặc sweep trong
cùng build.

Bổ sung 2 guard sau (dùng `NL_APPROACH_MODE` đề xuất ở mục 6.2; cả hai
macro vế phải đã tồn tại trong code: `NL_MOTION_PROFILE_SCURVE_V2` tại
`Core/Src/nonlinear_test.c:76`, `ENABLE_SWEEP_RAMP_SOFT_START` tại `:486`)
— nếu không, protocol vẫn mang
tên `SCURVE...V1` trong log nhưng số command/cadence hoặc sweep chính có
thể thực chạy khác với contract đã mô tả ở mục 3.1/3.2, mà không có gì báo
lỗi lúc build:

```c
#if NL_APPROACH_MODE >= NL_APPROACH_MODE_NO_REVERSAL_V3 && \
    (NL_MOTION_PROFILE != NL_MOTION_PROFILE_SCURVE_V2)
#error "V3 (no-reversal/shifted-reversal) requires NL_MOTION_PROFILE_SCURVE_V2 -- pre-roll/final math assumes the quintic profile"
#endif

#if NL_APPROACH_MODE >= NL_APPROACH_MODE_NO_REVERSAL_V3 && \
    ENABLE_SWEEP_RAMP_SOFT_START
#error "V3 (no-reversal/shifted-reversal) must not combine with sweep-ramp soft-start -- untested interaction with pre-roll cadence"
#endif
```

## 4. Khóa quy ước dấu Closure và nguồn dữ liệu residual

Codebase có hai quy ước dấu song song đã xác nhận trực tiếp trong firmware:

```text
DATA.ErrorDeg (mọi điểm, kể cả fallback ClosureErrorDeg schema v5 cũ):
    Target − Measured  =>  TARGET_MINUS_MEASURED

SHADOW_RESULT.ClosureErrorDeg (canonical):
    Measured − Target  =>  MEASURED_MINUS_TARGET
```

Ví dụ đối chiếu trên P03 (V2, cùng 10 run):

```text
Canonical (SHADOW_RESULT.ClosureErrorDeg):  +0.25882°
Legacy    (DATA[360] − DATA[0]):            -0.25522°
```

Cùng độ lớn, ngược dấu. Trộn hai nguồn trong cùng một gate hoặc cùng một
phép trừ (đặc biệt phép chuẩn hóa residual) sẽ cho kết quả sai — không phải
bản thân quy ước dấu là rủi ro (nếu mọi product đổi dấu nhất quán thì
range/so sánh chéo product vẫn đúng), mà rủi ro là **trộn lẫn hai pipeline
lấy mẫu khác nhau**.

Quy định cho V3:

```text
Primary Closure gate (mục 7.2, 7.2b so sánh chéo product):
    dùng SHADOW_RESULT.ClosureErrorDeg (canonical)

Residual hậu vòng (mục 7.2b):
    dùng DATA.Error (legacy), công thức:
        LegacyClosureForResidual = Error[360] − Error[0]
        PostTurnRepeatDelta[i]    = Error[360+i] − Error[i],       i=1..10
        ClosureNormalizedDelta[i] = PostTurnRepeatDelta[i] − LegacyClosureForResidual
    KHÔNG được chuẩn hóa DATA.Error bằng SHADOW_RESULT.ClosureErrorDeg —
    đó là hai pipeline lấy mẫu/reference khác nhau (canonical dùng
    POINT0_CANONICAL_MEAN, legacy dùng điểm 0 đơn lẻ của chính sweep đó).
```

## 4b. Logging bắt buộc

Không thêm field vào `META` vì line budget hạn chế. **Chốt: dùng chung
record `APPROACH_RESULT` cho cả B và A0, với formatter protocol-specific**
(không tạo record riêng theo protocol — giảm số format string cần
maintain/test, và giữ tương thích với parser hiện có vốn đã đọc
`APPROACH_RESULT` theo field optional):

- **Fixed-shape, không phải variable-shape:** `APPROACH_RESULT` của **cả B
  và A0 luôn in đủ toàn bộ field** trong danh sách dưới (kể cả
  `LocalBackoff*` và các field settle của protocol kia) — không có khái
  niệm "B không in field X" nữa. Khác biệt duy nhất giữa hai protocol là
  **giá trị**: field không áp dụng cho protocol đó mang `NA`, field áp
  dụng mang giá trị số/`OK` thật:
  ```text
  B:
    LocalBackoffCommandDeltaRaw=NA, LocalBackoffObservedDeltaRaw=NA,
    LocalBackoffTargetErrorRaw=NA, LocalBackoffDurationMs=NA
    PrePositionSettleResult=NA, LocalBackoffSettleResult=NA

  A0:
    PreRollSettleResult=NA
    (PreRollCommandDeltaRaw/ObservedDeltaRaw/TargetErrorRaw/DurationMs của
    A0 dùng lại đúng ý nghĩa "đoạn pre-position 60 lệnh", không phải NA —
    xem mục 6.2)
  ```
  Lý do chốt fixed-shape: giữ đúng yêu cầu "field không áp dụng luôn `NA`,
  không bỏ dòng" (đã khóa ở trên) — hai yêu cầu đó chỉ nhất quán khi record
  có cùng shape cho mọi protocol; không thể vừa "B không in field X" vừa
  "field không áp dụng luôn NA".
- `scripts/analyze_nonlinear_logs.ps1` tiếp tục đọc mọi field trên đây là
  optional (giống cách nó đã xử lý `ClosureProbe*`/`Shadow*` hiện nay) —
  optional ở đây nghĩa là parser không bắt buộc field phải tồn tại (tương
  thích log cũ trước khi có V3), không phải vì field bị lược theo protocol.

Các field tối thiểu (chung cho B; A0 thêm `LocalBackoff*` như trên):

```text
Protocol=SCURVE_CW_PREROLL_NO_REVERSAL_V1 | SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1
ApproachPath=CW_ONLY | CW_CCW_CW
ReversalCount=0 | 2
PreRollCommandDeltaRaw
PreRollObservedDeltaRaw
PreRollTargetErrorRaw
PreRollDurationMs
FinalCommandDeltaRaw
FinalObservedDeltaRaw
FinalTargetErrorRaw
FinalDurationMs
OriginShiftObservedRaw
OriginShiftTargetErrorRaw
InitialSettleResult
PreRollSettleResult          (B)   | PrePositionSettleResult, LocalBackoffSettleResult (A0)
FinalSettleResult
ApproachReadAttempts
ApproachRetries
ApproachTransportErrors
ApproachJumpRejects
ApproachFailedSamples
ApproachAcquisitionClean
ApproachStructuralValid
```

`Approach{ReadAttempts,Retries,TransportErrors,JumpRejects,FailedSamples}`
là aggregate của toàn bộ acquisition trong maneuver approach — bắt buộc
phải log, không chỉ suy ra một mình từ cờ `ApproachAcquisitionClean`, để
có thể audit nguyên nhân cụ thể khi một run không "clean" (ví dụ phân biệt
được retry nhiều do SPI nhiễu và transport error thật).

**Sửa lại nguồn final-settle cho aggregate (bản trước dùng sai nguồn):**
`settleAcquisition` (main) **không thể** dùng để đại diện riêng cho final
approach settle tại thời điểm log, vì sau khi approach kết thúc, sweep
loop chính tiếp tục cộng dồn settle của TẤT CẢ điểm 1..370 vào cùng
`out->settleAcquisition` (`Core/Src/nonlinear_test.c:3493-3497`,
`AccumulateCounterDelta(&sweepAcquisition, &settleBefore,
&out->settleAcquisition)` bên trong vòng lặp sweep chính, dùng chung biến
với dòng 3122 của final approach settle). `APPROACH_RESULT`/`RESULT` được
in sau khi sweep hoàn tất, nên lúc đó `settleAcquisition` đã lẫn ~370 settle
khác, không còn cô lập final approach settle nữa.

Vì vậy, nguồn đúng cho aggregate là ngược lại với bản trước:

```text
Approach aggregate (Approach{ReadAttempts,Retries,TransportErrors,
JumpRejects,FailedSamples}, ApproachAcquisitionClean) =
    approachInitialAcquisition                (mới — xem dưới)
  + approachSettleAcquisition                 (các settle chuẩn bị)
  + approachPreRollRampAcquisition/approachPrePositionRampAcquisition/
    approachLocalBackoffRampAcquisition/approachForwardRampAcquisition
  + FinalSettleAcquisitionDiag                (ĐÚNG MỘT LẦN — đây mới là
                                                delta độc lập, chụp ngay sau
                                                final settle, TRƯỚC khi
                                                sweep loop làm bẩn
                                                settleAcquisition)
```

`FinalSettleAcquisitionDiag` không "chỉ là bản copy chẩn đoán để bỏ qua"
như bản trước mô tả — nó là **nguồn duy nhất còn cô lập được** giá trị
final settle tại thời điểm log, và phải dùng cho aggregate.

`Acq*` legacy thì **giữ nguyên không đổi** so với V2 hiện tại — vẫn dùng
`settleAcquisition` (main, đã lẫn sweep) trừ khỏi `contextAcquisition`,
đúng như V2 đã làm (điều này đúng cho mục đích của `Acq*`: nó không cần cô
lập riêng approach, mà cần trừ hết mọi settle bất kể nguồn để giữ nghĩa
"chỉ còn 64 averaged reads/origin + 1 raw read/point"):

```text
Acq* legacy =
    contextAcquisition
  − rampAcquisition − settleAcquisition
  − approachSettleAcquisition
  − approachPreRollRampAcquisition/approachPrePositionRampAcquisition/
    approachLocalBackoffRampAcquisition/approachForwardRampAcquisition
```

- **Không trừ `FinalSettleAcquisitionDiag` khỏi `Acq*`** — final settle đã
  nằm trong `settleAcquisition` (bị trừ ở đó rồi), trừ thêm sẽ trừ hai lần.
- **Không trừ `approachInitialAcquisition` khỏi `Acq*`** — initial read vẫn
  mang nghĩa "origin" legacy, y hệt cách V2 hiện tại cố ý để initial acquire
  "không bọc snapshot" chảy thẳng vào `contextAcquisition`
  (`Core/Src/nonlinear_test.c:2949-2954`, comment: "để Acq* của 2 protocol
  so sánh được với nhau theo cùng một ý nghĩa").

**Thêm `approachInitialAcquisition` (counter mới, bắt buộc):** initial
acquire hiện tại (`:2952-2954`) không có snapshot before/after riêng — chỉ
gọi thẳng `MA600_AcquireSample()` rồi để counter chảy vào context. Muốn
aggregate thực sự đại diện "toàn bộ approach" (bao gồm initial read) mà
không đổi hành vi `Acq*` legacy, cần thêm một snapshot delta **chỉ để
log**, không tham gia bất kỳ phép trừ `Acq*` nào — tương tự vai trò
diagnostic-only của `FinalSettleAcquisitionDiag`.

Phương án thay thế đơn giản hơn nhưng chấp nhận được: tính và **đóng băng**
toàn bộ aggregate ngay sau final settle, trước khi vào sweep loop chính
(snapshot một lần `approachAggregateFrozen = approachInitialAcquisition +
approachSettleAcquisition + ramp counters + FinalSettleAcquisitionDiag`
ngay tại thời điểm đó) — tránh phụ thuộc thứ tự log sau này. Dù chọn cách
nào, `FinalSettleAcquisitionDiag` vẫn là nguồn dữ liệu final-settle, không
phải `settleAcquisition` chính.

`FinalTargetErrorRaw` và `OriginShiftTargetErrorRaw` đo hai đại lượng khác
nhau, không được coi là trùng:

```text
FinalTargetErrorRaw:      sai số riêng đoạn CW cuối 1° (final local leg)
OriginShiftTargetErrorRaw: sai số tích lũy từ initial anchor qua toàn bộ
                           khoảng ~60° (pre-roll + final gộp lại)
```

**Cập nhật:** `OriginShiftTargetErrorRaw` **không còn diagnostic-only** —
đây là gate bắt buộc ở mục 7.3 (`abs(OriginShiftTargetErrorRaw) <= 16 raw ở
>=9/10 run`), song song với `FinalTargetErrorRaw`. Lý do: dung sai
target-proximity hiện có của settle rất rộng
(`NL_SETTLE_TARGET_TOLERANCE_RAW = 910 raw`) — chỉ riêng gate settle không
đủ chặt để loại một run mà đoạn cuối đúng nhưng toàn bộ pre-roll đã lệch xa
target tuyệt đối. `OriginShiftObservedRaw` (giá trị quan sát, không phải
sai số) vẫn là diagnostic. Ngưỡng ±16 raw cho `OriginShiftTargetErrorRaw`
dùng tạm theo cùng chuẩn `FinalTargetErrorRaw`; hiệu chỉnh lại sau khi có
dữ liệu P03/P06 thật nếu cần, trước khi mở rộng V3.3.

**Quy tắc chống calibration-trên-chính-batch-dùng-để-PASS:** nếu ngưỡng
±16 raw của `OriginShiftTargetErrorRaw` được đổi sau khi xem dữ liệu pilot
V3.1 (P03/P06), batch V3.1 đó chỉ được coi là **batch hiệu chỉnh
(calibration)**, không được dùng luôn làm batch kết luận PASS/FAIL —
bắt buộc chạy một batch xác nhận độc lập (10 official run mới, cùng
protocol) với ngưỡng đã hiệu chỉnh trước khi ra quyết định ở mục 8. Dùng
chung một batch để vừa hiệu chỉnh ngưỡng vừa kết luận PASS là circular
reasoning — ngưỡng luôn "vừa đủ" để batch đó pass.

Chỉ log per-microstep cho final local 1-degree leg (40 tick). Không dành RAM
để log toàn bộ khoảng 2360 tick pre-roll; pre-roll chỉ cần start/end,
duration, settle và acquisition counters.

**Ownership acquisition counters (bắt buộc, để không phá contract `Acq*`
legacy):** `Core/Src/nonlinear_test.c:3517-3528` (normal completion) và
`:2858-2872` (`FinalizeApproachEarlyExit`, early-exit) đều tính
`Acq*` = `contextAcquisition` trừ đi một danh sách cố định các counter con
(`rampAcquisition`, `settleAcquisition`, `approachSettleAcquisition`,
`approachBackoffRampAcquisition`, `approachForwardRampAcquisition`) — đúng
2 chỗ, độc lập, phải khớp nhau. V3 pre-roll (~2360 acquisition) và final
leg (~40) là acquisition MỚI, không nằm trong danh sách trừ hiện có. Nếu
không bổ sung, `AcqReadAttempts`/`Acq*` legacy sẽ tăng thêm hàng nghìn read
mỗi run B/A0, phá vỡ ý nghĩa "Acq* chỉ tính origin + 64 averaged reads + 1
raw read/point" mà mọi baseline V1/V2 đang dựa vào để so sánh.

**Sửa lại theo đúng quy ước code hiện tại (quan trọng — final settle KHÔNG
thuộc `approachSettleAcquisition`):** `Core/Src/nonlinear_test.c:3108-3114`
ghi rõ bằng comment: final point-0 settle của V2 cố ý tính vào
`out->settleAcquisition` **chính** (không phải `approachSettleAcquisition`)
để giữ `SettlePoints`/`SettleReadAttempts` nhất quán giữa protocol A và B —
kèm một bản copy **chẩn đoán riêng** (`approachPoint0SettleAcquisitionDiag`)
không tham gia trừ `Acq*`, chỉ dùng để tính `ApproachAcquisitionClean`. V3
phải theo đúng pattern này, không phải nhóm final settle chung với các
settle chuẩn bị:

```text
B:
  approachSettleAcquisition = InitialSettle + PreRollSettle   (KHÔNG có Final)

A0:
  approachSettleAcquisition = InitialSettle + PrePositionSettle + LocalBackoffSettle
                                                                    (KHÔNG có Final)

B và A0 (giống hệt V2):
  FinalSettle → settleAcquisition CHÍNH (không phải approachSettleAcquisition)
  đồng thời copy sang FinalSettleAcquisitionDiag (chẩn đoán, KHÔNG trừ Acq*,
  chỉ dùng cho ApproachAcquisitionClean)
```

Không được trừ final settle hai lần khỏi `Acq*` (một lần qua
`settleAcquisition`, một lần nữa nếu nhầm gộp vào `approachSettleAcquisition`).

Counter cho các đoạn motion (ramp, không phải settle) — tái dùng tên đã có
cho đoạn cuối vì nó đóng đúng vai trò tương đương `approachForwardRampAcquisition`
của V2:

```text
B:
  approachPreRollRampAcquisition       (mới, 59×40 tick)
  approachForwardRampAcquisition       (tái dùng tên hiện có — final 1°, 40 tick)

A0:
  approachPrePositionRampAcquisition   (mới, 60×40 tick)
  approachLocalBackoffRampAcquisition  (mới, 40 tick, đoạn CCW)
  approachForwardRampAcquisition       (tái dùng tên hiện có — final 1°, 40 tick)
```

Yêu cầu:

- Trừ đúng các counter mới này (`approachPreRollRampAcquisition`,
  `approachPrePositionRampAcquisition`, `approachLocalBackoffRampAcquisition`,
  và `approachSettleAcquisition` đã redefine ở trên) khỏi `Acq*` ở **cả
  hai** chỗ (normal completion `:3517-3528` và `FinalizeApproachEarlyExit`
  `:2858-2872`), không chỉ một. `approachForwardRampAcquisition` đã có sẵn
  trong danh sách trừ hiện tại, không cần thêm lại.
- Contract test riêng: chạy B/A0 với acquisition giả lập, xác nhận
  `AcqReadAttempts` sau maneuver mới bằng đúng giá trị trước khi thêm V3
  (tức verify V3 không rò rỉ vào `Acq*`), tương tự cách baseline V1/V2 hiện
  đã tự chứng minh 3 counter B0-B của nó luôn trừ về 0 dưới protocol A.

`ApproachStructuralValid=1` — hai contract riêng theo protocol. **Cả B và
A0 đều có settle initial-anchor (bước 1 ở mục 3.1) cộng thêm vào các
settle của riêng maneuver — số settle bắt buộc là 3 (B) và 4 (A0), không
phải 2/3 như đếm thiếu initial-anchor:**

**B (`SCURVE_CW_PREROLL_NO_REVERSAL_V1`)** chỉ khi:
- pre-roll và final command delta đều dương;
- `ReversalCount=0`;
- đúng số command dự kiến (2360 pre-roll + 40 final);
- **cả 3 settle `OK`: `InitialSettle` + `PreRollSettle` + `FinalSettle`**;
- acquisition sạch;
- final local leg hoàn tất đủ 40 tick.

**A0 (`SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1`)** chỉ khi:
- pre-position command delta dương, local-backoff command delta **âm**
  (đúng vì đây là đoạn CCW có chủ ý — âm không phải lỗi), final command
  delta dương;
- `ReversalCount=2`;
- đúng số command dự kiến (2400 pre-position + 40 local-backoff + 40 final);
- **cả 4 settle `OK`: `InitialSettle` + `PrePositionSettle` +
  `LocalBackoffSettle` + `FinalSettle`**;
- acquisition sạch;
- final local leg hoàn tất đủ 40 tick.

Thêm field kết quả settle tương ứng vào `APPROACH_RESULT` (mục 4b) để có
thể audit từng thành phần của `ApproachStructuralValid` độc lập, thay vì
chỉ có một cờ tổng hợp:

```text
B:  InitialSettleResult, PreRollSettleResult, FinalSettleResult
A0: InitialSettleResult, PrePositionSettleResult, LocalBackoffSettleResult,
    FinalSettleResult
```

Endpoint amplitude vẫn là diagnostic riêng, không được nhập nhằng với gate
cấu trúc.

## 5. Contract test trước build

- [ ] Protocol ID V3 xuất hiện đúng trong source và log formatter.
- [ ] V3 và V2 reversal là hai nhánh loại trừ lẫn nhau (dùng
  `NL_APPROACH_MODE`, 4 giá trị 0-3 — xem mục 6.2).
- [ ] Mode 0 (`NL_APPROACH_MODE_LOCK_ONLY`, tương đương
  `ENABLE_B0B_EQUAL_APPROACH=0`/`SCURVE_LOCK_V2` hiện tại) vẫn còn lối vào
  và contract test cũ liên quan vẫn pass sau khi đổi sang enum mode.
- [ ] Compile guard cấm V3 + feedforward/creep/soft-start/CCW.
- [ ] Compile guard `#error` nếu `MOTOR_POLE_PAIRS != 6` (V3 V1 chỉ hợp lệ
  cho 6 pole-pair; xem mục 3.2).
- [ ] A0 (V3.2) capture point 0 tại cùng zero điện kế tiếp với B, không
  phải zero điện ban đầu (xem mục 6.2).
- [ ] Pre-roll target dùng rounded target rule (`NlTargetRawMagnitudeForPoint`),
  không cộng lặp 182 raw.
- [ ] **Pre-roll là vòng lặp 59 lệnh `RampCommandToTarget()` độc lập (point
  1..59), KHÔNG phải một lệnh ramp duy nhất tới target 59°** — xem cảnh báo
  bắt buộc ở mục 3.1. Test riêng: gọi `RampCommandToTarget()` với target xa
  (>1 grid step) phải bị coi là lỗi thiết kế/regression trong review, không
  chỉ dựa vào quan sát hành vi lúc chạy.
- [ ] Command delta của B (pre-roll, final) đều dương; command delta của A0
  (pre-position, final dương, local-backoff **âm**) đúng dấu theo mục 4b.
- [ ] `ReversalCount` tính từ command delta thực tế (đếm số lần đổi dấu),
  không hardcode kết quả — B kỳ vọng 0, A0 kỳ vọng 2.
- [ ] Gate `ApproachStructuralValid`/`ReversalCount` ở mục 7.1 áp dụng đúng
  contract theo protocol (B ≠ A0), không dùng một ngưỡng chung.
- [ ] Final local leg (cả B và A0) dùng đúng `RampCommandToTarget`, 40 tick,
  1 ms, có log per-tick.
- [ ] `APPROACH_RESULT` formatter đúng theo protocol (mục 4b): B không in
  field `LocalBackoff*`; field không áp dụng là `NA`, không phải `0` giả.
- [ ] Sweep loop và metric functions không thay đổi.
- [ ] Point 360 vẫn là closure index.
- [ ] Schema/parser chấp nhận protocol V3 (cả B và A0) và log cũ vẫn parse
  được.
- [ ] **Analyzer (`scripts/analyze_nonlinear_logs.ps1` hoặc tool tương ứng)
  xuất thêm, trên từng official run** (bắt buộc vì PASS/FAIL của V3 phụ
  thuộc residual — xem mục 7.2b, không chỉ "hỗ trợ parse protocol V3"):
  ```text
  PostTurnRepeatRMSDeg
  ClosureNormalizedDeltaRMSDeg
  ClosureNormalizedDeltaMaxAbsDeg
  PostTurnAnalysisValid
  ```
  Công thức dùng hoàn toàn `DATA.Error` (legacy, theo khóa ở mục 4).
  **Khóa rõ cả ba field xuất ra, không để analyzer/fixture tự chọn cách
  hiểu khác nhau:**
  ```text
  legacyClosure   = Error[360] − Error[0]
  post[i]         = Error[360+i] − Error[i]                  (i = 1..10)
  normalized[i]   = post[i] − legacyClosure

  PostTurnRepeatRMSDeg             = sqrt(mean(post[i]^2))              , i=1..10
  ClosureNormalizedDeltaRMSDeg     = sqrt(mean(normalized[i]^2))        , i=1..10
  ClosureNormalizedDeltaMaxAbsDeg  = max(abs(normalized[i]))            , i=1..10
  ```
  Mọi bảng/gate trong mục 2 và 7.2b dùng `ClosureNormalizedDeltaRMSDeg`
  (đã chuẩn hóa theo closure), không dùng `PostTurnRepeatRMSDeg` (chưa trừ
  closure) làm số liệu so sánh chính — `PostTurnRepeatRMSDeg` chỉ để đối
  chiếu/debug.
  `PostTurnAnalysisValid=1` chỉ khi: `AnalysisPoints=360`,
  `CapturedPoints>=371`, đủ `DATA` index 0..370, và
  `OfficialMeasurementValid=1`. Không tính residual trên STM32 — firmware
  chỉ phát `DATA`, phân tích residual hoàn toàn ở tool ngoài (tránh tăng
  RAM/flash và tránh trùng logic phân tích ở hai nơi).
- [ ] Contract test cho residual: fixture log có index 0..370 đã biết trước
  kết quả `ClosureNormalizedDelta`, xác nhận analyzer tính đúng (tương tự
  fixture `schema-v5-360grid-closure-p03-jig1.txt` đã có cho closure).
- [ ] Tất cả contract/regression test hiện có pass.
- [ ] Build hoàn tất không warning/error mới.

## 6. Kế hoạch hardware test

### V3.1 — screening nhanh, hai motor cực trị

Chỉ flash build V3-B no-reversal và test:

1. P03, JIG1: 1 precondition + 10 official.
2. Nghỉ/đổi motor theo quy trình hiện tại.
3. P06, JIG1: 1 precondition + 10 official.

Không đổi jig, nguồn, pole count, cooldown, firmware hoặc thao tác gá ngoài
việc thay motor. Ghi rõ có tháo/lắp lại hay không.

V3.1 dùng baseline V2 hiện có để đánh giá hiệu quả thực dụng. Nó chưa phải
phép chứng minh nhân quả tuyệt đối vì V2 còn bias còn V3 không bias.

### V3.2 — xác nhận nguyên nhân khi V3.1 có triển vọng

**Confound bắt buộc phải sửa trước khi build:** A0 (reversal hiện tại,
backoff -182 raw rồi forward về 0) capture point 0 tại **zero điện ban
đầu** (raw ≈ 0), trong khi B (V3 no-reversal) capture point 0 tại **zero
điện kế tiếp** (raw ≈ 10923, lệch ~+60° cơ khí — xem mục 3.1). Nếu chạy
A0-B-A0 với A0 giữ nguyên như mô tả cũ, một khác biệt residual giữa A0 và B
không thể phân biệt được là do loại bỏ reversal hay do đổi sang vùng cơ khí
khác của encoder/magnet/cogging. Plan cũ ở đây **chưa phải phép kiểm chứng
nhân quả**, chỉ là so sánh hai protocol khác nhau ở cả biến reversal lẫn
biến vị trí capture.

**A0 sửa lại — phải kết thúc tại cùng zero điện kế tiếp với B:**

```text
B (V3, không đảo chiều):
    0 → CW 59° → settle → CW 1° → settle → capture   (tại zero điện kế tiếp)

A0 (reversal, đã sửa):
    0 → CW 60° → settle
      → CCW 1° → settle
      → CW 1°  → settle → capture                     (tại cùng zero điện kế tiếp)
```

Cụ thể hóa thành lệnh (cùng cấu trúc segment-loop như B ở mục 3.1, để
tránh lặp lại lỗi gọi `RampCommandToTarget()` một lần với target xa):

```text
CW pre-position: 60 lệnh RampCommandToTarget(), point1..point60, 40 tick/lệnh
                 (không settle giữa các segment)
CCW local leg:   1 lệnh RampCommandToTarget() từ point60 về point59, 40 tick
CW final leg:    1 lệnh RampCommandToTarget() từ point59 về point60, 40 tick,
                 log per-tick đầy đủ (giống final leg của B)
```

`ReversalCount` của A0 = 2 (CW→CCW tại pre-position→local backoff, rồi
CCW→CW tại local backoff→final) — xem gate protocol-specific ở mục 7.1.
Protocol ID đề xuất cho A0: `SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1`
(phân biệt rõ với `SCURVE_CW_PREROLL_NO_REVERSAL_V1` của B và với
`SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2` cũ).

**Target settle tuyệt đối cho A0 — cùng nguyên tắc khóa ở mục 3.1, không
nối chuỗi qua anchor trung gian:**

```c
int64_t expectedPoint60 =
    initialAnchorUnwrapped + NlTargetRawMagnitudeForPoint(60);
int64_t expectedPoint59 =
    initialAnchorUnwrapped + NlTargetRawMagnitudeForPoint(59);
```

Thứ tự settle (cả ba đều so với target tuyệt đối tính từ
`initialAnchorUnwrapped`, không phải nối tiếp từ anchor bước trước):

```text
CW pre-position → settle theo expectedPoint60
CCW local backoff → settle theo expectedPoint59
CW final          → settle theo expectedPoint60
```

Nhờ vậy A0 và B cùng settle tại đúng một target encoder tuyệt đối
(`expectedPoint60`, tính từ cùng `initialAnchorUnwrapped`) ở bước capture
cuối cùng — không chỉ cùng lệnh command, mà cùng vị trí encoder kỳ vọng.

Cả hai (A0, B) kết thúc tại cùng vị trí cơ khí (~+60° từ initial anchor).
Khác biệt còn lại giữa A0 và B chỉ còn đúng một biến: **có/không có
maneuver đảo chiều** ngay trước capture. Nếu không sửa điểm này, V3.2
không tách được nguyên nhân, dù kết quả có vẻ hợp lý.

Tạo build A0 (đã sửa) tắt feedforward/creep/soft-start. Chạy A0-B-A0 trên
motor có thay đổi lớn nhất (định nghĩa "thay đổi lớn nhất" theo residual —
xem mục 7 cuối):

1. A0 (đã sửa): reversal, capture tại zero điện kế tiếp, bias 0/0.
2. B: no-reversal V3, capture tại cùng zero điện kế tiếp, bias 0/0.
3. A0 lần hai: reversal, capture tại cùng zero điện kế tiếp, bias 0/0.

Mỗi leg giữ 1 precondition + 10 official. Đây mới là phép tách riêng biến
`reversal` khỏi biến `bias`, biến `sector cơ khí`, và drift thời gian.

**Gate bắt buộc trước khi đọc kết quả nhân quả — xác nhận cả 3 leg thực sự
cùng sector tuyệt đối:** `expectedPoint60 = initialAnchorUnwrapped +
target60` đúng *trong từng run riêng lẻ*, nhưng `initialAnchorUnwrapped`
(từ `LockStartPosition()`/home) có thể trôi giữa A0-before, B và A0-after
(mỗi leg home lại từ đầu theo `RESET_BEFORE_EACH_HOME_V1`). Gate
`OriginShiftTargetErrorRaw` ở mục 7.3 chỉ xác nhận mỗi run đã đi đúng +60°
**tương đối** so với anchor của chính run đó — nó **không** xác nhận ba
leg kết thúc tại cùng raw encoder **tuyệt đối**. Quy tắc "không so sánh
`StartRaw`" ở mục 6.3 chỉ áp dụng khi so V2 baseline với V3 (nơi lệch
sector ~+60° là chủ đích); **trong nội bộ A0-B-A0 thì bắt buộc phải kiểm
tra `AnalysisStartRaw`** vì cả ba leg cùng nhắm một sector, một sai khác ở
đây là confound thật, không phải chủ đích:

Bracket "nằm trong khoảng [A0_before, A0_after]" theo giá trị raw thô
**không đủ**: raw có thể đi qua điểm wrap 65535→0 (khoảng bracket tính
thô sẽ sai), và nếu A0_before ≈ A0_after (không trôi giữa hai lần A0) thì
khoảng bracket rộng ~0, gate mất hết dung sai một cách giả tạo. Khóa công
thức circular + nội suy theo thời gian:

```text
CircularDelta(x, reference) =
    ((x - reference + 32768) mod 65536) - 32768
    /* đưa (x - reference) về miền [-32768, +32767], xử lý đúng wrap 65535→0 */
```

**Áp dụng theo từng B run, không phải theo mean batch** (mỗi leg A0-before/
B/A0-after đều có 10 official run — công thức dưới đây phải rõ dùng giá
trị nào ở từng bước, không để analyzer tự chọn mean hay per-run):

```text
1. A0_before_ref = circular mean của AnalysisStartRaw trên 10 run A0-before
   t_A0_before_ref = mean timestamp của 10 run đó

   A0_after_ref  = circular mean của AnalysisStartRaw trên 10 run A0-after
   t_A0_after_ref = mean timestamp của 10 run đó

2. A0_after_unwrapped =
       A0_before_ref + CircularDelta(A0_after_ref, A0_before_ref)
   /* "mở" A0_after_ref quanh A0_before_ref thành một trục liên tục */

3. Với TỪNG run B (10 run, k = 1..10):
       Expected_B[k] =
           A0_before_ref
           + (A0_after_unwrapped - A0_before_ref)
             × (timestamp_B[k] - t_A0_before_ref)
             / (t_A0_after_ref - t_A0_before_ref)
           /* nội suy tuyến tính theo timestamp của chính run B[k], cùng
              cách nl_report.txt đã nội suy Closure theo run-order ở
              Test 21 */

       SectorError_B[k] = CircularDelta(AnalysisStartRaw_B[k], Expected_B[k])

4. Gate: abs(SectorError_B[k]) <= SectorToleranceRaw ở >= 9/10 run B
   (không dùng mean SectorError_B trên cả batch — một run lệch sector
   không được che bằng cách lấy trung bình cả batch, nhất quán với cách
   các gate motion khác ở mục 7.3 đều tính theo tỉ lệ run đạt, không theo
   mean)
```

`SectorToleranceRaw` phải khóa **trước** khi xem dữ liệu P03/P06 dùng để
kết luận — nếu hiệu chỉnh bằng chính dữ liệu pilot, áp dụng cùng quy tắc
"calibration batch không được dùng để PASS" đã khóa ở mục 4b (chạy batch
xác nhận độc lập với ngưỡng đã hiệu chỉnh).

Nếu batch B không đạt `>=9/10` run trong gate này, **không được kết luận
reversal là nguyên nhân** từ cặp A0-B-A0 đó — sector không tương đương đủ
để tự nó giải thích chênh lệch residual, độc lập với reversal.

Kết luận reversal là nguyên nhân chỉ khi **cả gate sector trên đạt VÀ**:

```text
Residual_B <
    mean(Residual_A0_before, Residual_A0_after) − 2.77×pooled_SD
```

**Khóa công thức `pooled_SD`** (within-leg variance của 3 leg A0-before,
B, A0-after — mỗi leg n=10 official run, dùng `ClosureNormalizedDeltaRMSDeg`
của từng run làm mẫu, giống cách `nl_stability.csv`/`nl_report.txt` đã pool
SD giữa các leg A1/B/A2 ở Test 21):

```text
pooled_SD =
sqrt(
  ((n_A0before − 1)×s_A0before²
   + (n_B − 1)×s_B²
   + (n_A0after − 1)×s_A0after²)
  / (n_A0before + n_B + n_A0after − 3)
)
```

trong đó `s_leg` là sample SD của `ClosureNormalizedDeltaRMSDeg` trong
leg đó (n=10 mỗi leg, mẫu số n−1). Với 3 leg × 10 run, mẫu số =
10+10+10−3 = 27.

**Đề xuất implementation — một mode duy nhất thay vì nhiều boolean rời
rạc**, để tránh tổ hợp cấu hình không hợp lệ. **Bắt buộc gồm 4 mode, không
phải 3** — code hiện tại còn nhánh `SCURVE_LOCK_V2` khi
`ENABLE_B0B_EQUAL_APPROACH=0` (`Core/Src/nonlinear_test.c:456`, nhánh
`#else` của protocol ID); nếu enum chỉ có 3 mode (V2/V3-B/A0) và thay hẳn
macro cũ, đường code legacy `SCURVE_LOCK_V2` sẽ mất lối vào và các contract
test cũ dựa trên nó có thể bị phá:

```c
#define NL_APPROACH_MODE_LOCK_ONLY               0  /* SCURVE_LOCK_V2, ENABLE_B0B_EQUAL_APPROACH=0 hiện tại */
#define NL_APPROACH_MODE_REVERSAL_V2             1  /* SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2, giữ nguyên */
#define NL_APPROACH_MODE_NO_REVERSAL_V3          2  /* SCURVE_CW_PREROLL_NO_REVERSAL_V1 (B) */
#define NL_APPROACH_MODE_SHIFTED_REVERSAL_A0     3  /* SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1 (A0) */

#ifndef NL_APPROACH_MODE
#define NL_APPROACH_MODE NL_APPROACH_MODE_REVERSAL_V2
#endif

#if NL_APPROACH_MODE < NL_APPROACH_MODE_LOCK_ONLY || \
    NL_APPROACH_MODE > NL_APPROACH_MODE_SHIFTED_REVERSAL_A0
#error "Invalid NL_APPROACH_MODE"
#endif
```

Mặc định (`NL_APPROACH_MODE_REVERSAL_V2`) giữ đúng hành vi build hiện tại
nếu không ai set macro — không đổi behavior ngoài ý muốn cho các build cũ.
Build V3-B chọn mode 2; build A0 chọn mode 3. Guard bias/creep/soft-start
(mục 3.3) áp dụng cho cả mode 2 và mode 3.

### 6.3. Giới hạn so sánh do V3 dịch sector cơ khí ~+60°

Vì point-0 của V3-B (và A0 đã sửa) nằm ở sector cơ khí khác point-0 của
V1/V2/baseline hiện có (~+60°, xem mục 3.1/6.2):

- Chỉ so sánh **biên độ (amplitude)** và **energy ratio** của harmonic
  giữa V3 và baseline — đây là đại lượng không phụ thuộc pha tuyệt đối.
- **Không gate phase** của bất kỳ harmonic nào so với baseline — pha dịch
  theo sector là kỳ vọng, không phải bất thường.
- **Không so sánh trực tiếp `StartRaw`** giữa V3 và baseline — chúng khác
  nhau có chủ ý (~+60°/~10923 raw), không phải dấu hiệu lỗi.
- Phase thay đổi (do dịch sector) không được diễn giải là "NL thay đổi"
  trong mục 7.4.

### V3.3 — mở rộng product

Chỉ thực hiện nếu P03 và P06 cùng đạt tiêu chí pilot. Test tiếp P02, P04 và
P05, mỗi product một batch 10 official. Product nào sát giới hạn phải có
batch thứ hai sau ít nhất 15 phút.

## 7. Tiêu chí đánh giá

### 7.1. Gate dữ liệu

Mỗi batch phải có:

- 10/10 `OfficialMeasurementValid=1`;
- 10/10 acquisition sạch;
- 10/10 `ApproachStructuralValid=1` (theo đúng contract của protocol batch
  đó — xem dưới);
- `ReversalCount` đúng theo protocol, **không dùng một ngưỡng chung**:
  ```text
  SCURVE_CW_PREROLL_NO_REVERSAL_V1 (B):              ReversalCount = 0 ở 10/10
  SCURVE_CW_PREROLL_LOCAL_REVERSAL_CONTROL_V1 (A0):   ReversalCount = 2 ở 10/10
  ```
  A0 đảo chiều có chủ ý (CW pre-position → CCW local backoff → CW final),
  nên `ReversalCount=0` không áp dụng cho A0. Dùng chung ngưỡng 0 sẽ đánh
  dấu toàn bộ batch A0 invalid và làm hỏng phép so sánh A0-B-A0 ở V3.2.
  `ApproachStructuralValid` của A0 cũng cần contract riêng phản ánh đúng 3
  đoạn chuyển động (pre-position/local-backoff/final), không dùng chung
  điều kiện "command delta dương" của B (mục 4b, `ApproachStructuralValid`
  của B yêu cầu pre-roll/final delta dương — A0 có đoạn CCW nên delta local
  backoff âm là đúng, không phải lỗi);
- không E503, timeout hoặc failed settle.

Batch không đạt gate dữ liệu không được dùng kết luận Closure.

### 7.2. Primary success — Closure dùng chung

Trên từng product:

```text
abs(mean Closure) <= 0.10 deg
abs(mean Closure) + 3*SD <= 0.20 deg
ClosureValid >= 9/10
```

Trên cặp pilot P03/P06:

```text
range giữa hai product mean Closure <= 0.15 deg
```

### 7.2b. Primary success — Residual hậu vòng (bắt buộc, không phải log phụ)

Bằng chứng bảng mục 2: P04/P05 có Closure tốt nhất nhưng residual xấu
nhất — Closure một mình không đủ để đánh giá V3 có hiệu quả hay không. Dùng
`ClosureNormalizedDelta` RMS/MaxAbs tính theo công thức khóa ở mục 4.

Không xấu hơn baseline cùng product (điều kiện tối thiểu để không loại V3):

```text
Residual_V3 <= Residual_V2_cùng_product + 2.77×SD_V2_cùng_product
```

Để coi V3 thực sự có hiệu quả (không chỉ "không xấu hơn"), trên cặp pilot,
**khóa rõ `WorstResidual` là product có `Residual RMS` baseline (V2) lớn
hơn giữa P03/P06** (không phải P03 mặc định, cũng không phải trung bình
hai product) — theo bảng mục 2, đó là:

```text
WorstProduct = argmax(meanResidual_V2_P03, meanResidual_V2_P06)
             = P03   (0.36834° > 0.27279° của P06, theo baseline hiện có)

WorstResidual(P03, P06)_V3 =
    Residual_V3 của đúng WorstProduct (P03), không phải trung bình 2 product

repeatability limit đi kèm =
    2.77 × SD_V2 của cùng WorstProduct đó (P03: 2.77×0.01554° = 0.04305°,
    theo baseline mục 2 — không dùng SD của product kia)
```

Gate: `WorstResidual(P03, P06)_V3 <= meanResidual_V2_WorstProduct −
repeatability_limit_WorstProduct`. Nếu baseline V2 thay đổi (ví dụ chạy lại
P03/P06 trước V3.1), tính lại `WorstProduct` theo baseline mới nhất tại
thời điểm đó, không cố định P03 vĩnh viễn.

Nếu Residual_V3 không cải thiện dù Closure cải thiện — áp dụng ngay nhánh
"Endpoint tốt nhưng Closure không cải thiện" ở mục 8 (đổi tên áp dụng
tương tự cho residual): dừng nhánh reversal, chuyển hướng phân tích.

### 7.3. Motion success

```text
abs(FinalTargetErrorRaw) <= 16 raw ở >= 9/10 run
abs(OriginShiftTargetErrorRaw) <= 16 raw ở >= 9/10 run

ExpectedReversalCount theo protocol (không dùng ngưỡng chung — xem mục 7.1):
    B  = 0 ở 10/10 run
    A0 = 2 ở 10/10 run
```

**`OriginShiftTargetErrorRaw` không còn diagnostic-only — đây là gate bắt
buộc, song song và độc lập với `FinalTargetErrorRaw`.** Lý do: settle hiện
dùng dung sai target-proximity rất rộng (`NL_SETTLE_TARGET_TOLERANCE_RAW =
910 raw`). Một run có thể đạt `FinalTargetErrorRaw <= 16` (đoạn 1° cuối
đúng) trong khi toàn bộ pre-roll đã lệch hàng trăm raw so với target tuyệt
đối — `ApproachStructuralValid=1` vẫn có thể true, và Closure có thể "đẹp"
một cách tình cờ vì capture rơi đúng sector nhưng sai vị trí tuyệt đối bên
trong sector đó. `FinalTargetErrorRaw` kiểm tra đúng đoạn cuối;
`OriginShiftTargetErrorRaw` kiểm tra toàn bộ hành trình từ initial anchor —
hai gate bổ sung cho nhau, không thay thế nhau. Ngưỡng ±16 raw dùng tạm
theo cùng chuẩn `FinalTargetErrorRaw`; hiệu chỉnh lại sau khi có dữ liệu
P03/P06 thật nếu cần (không đoán trước — xem mục 4b).

Pre-roll target error được report riêng. Không cho phép Closure nhỏ do
pre-roll/final sai ngược chiều tự triệt tiêu.

### 7.4. Không làm sai phép đo NL

So với baseline cùng product:

- Robust NL không đổi quá repeatability limit `2.77 * SD` đã đo;
- H36 amplitude và các harmonic ratio chính không đổi quá 3%, trừ khi thay
  đổi được lặp lại trong V3.2 A-B-A và được chứng minh là do approach;
- acquisition và 12-order reconstruction không xấu đi;
- motor-active duration không tăng quá 15%;
- không thêm drift NL có slope CI95 loại trừ 0 theo chiều xấu.

### 7.5. Tiêu chí chọn motor cho V3.2

```text
Primary:    |Δ ClosureNormalizedDelta RMS| / repeatability_limit
Tie-break:  |Δ Closure canonical|
```

Residual được ưu tiên trước Closure vì đây là hiện tượng gốc cần kiểm
chứng nguyên nhân (mục 1, 7.2b) — Closure chỉ dùng để phá thế hòa.

## 8. Decision tree sau V3.1

PASS ở đây nghĩa là đạt **cả** gate Closure (7.2) **và** gate residual
(7.2b) — một trong hai không đạt thì coi là MIXED/FAIL, không PASS.

### Trường hợp PASS trên cả P03 và P06

- Chạy V3.2 A0-B-A0 (A0 đã sửa, cùng zero điện với B — mục 6.2) trên motor
  có `|Δ ClosureNormalizedDelta RMS| / repeatability_limit` lớn nhất giữa
  V3.1 và baseline V2 (xem tiêu chí chọn motor cuối mục 7) để xác nhận
  reversal là nguyên nhân.
- Sau đó mở rộng P02/P04/P05 theo V3.3.
- Chưa đặt V3 làm production default trước khi đủ năm product.

### Closure PASS nhưng residual không cải thiện (mục 7.2b)

- Không coi V3.1 là PASS toàn phần dù Closure đạt.
- Dừng nhánh reversal-là-nguyên-nhân-của-residual; residual cần được điều
  tra bằng cơ chế khác (không phải "không đủ dữ liệu để chạy V3.2" — vẫn
  nên chạy V3.2 để xác nhận reversal có/không ảnh hưởng Closure, nhưng
  không kỳ vọng nó giải thích residual).

### P03 cải thiện nhưng P06 xấu đi, hoặc ngược lại

- Dừng mở rộng product.
- Không tune thêm một bias tĩnh.
- Kiểm tra `FinalTargetErrorRaw`, origin shift và post-turn residual để xác
  định vấn đề nằm ở pre-roll hay final 1-degree leg.
- Chỉ tạo V3.1a với một thay đổi duy nhất sau khi xác định được leg lỗi.

### Closure tốt nhưng endpoint không đạt

- Kết luận FAIL. Đây là cùng dạng false confidence đã thấy ở P02 V2.
- Không chấp nhận triệt tiêu sai số làm thành công.

### Endpoint tốt nhưng Closure không cải thiện

- Dừng nhánh approach; reversal không phải đòn bẩy chính cho Closure.
- Chuyển phân tích sang point-0/point-360 state equivalence và sweep
  first-ramp dynamics, không dò thêm bias.

### Acquisition/settle lỗi hoặc thời gian tăng quá 15%

- Dừng hardware test, sửa tính đúng/độ an toàn trước khi đánh giá số đo.

## 9. Checklist trạng thái

### Firmware

- [ ] V3 feature flag (`NL_APPROACH_MODE_*`) và mutual-exclusion guards.
- [ ] CW pre-roll = 59 lệnh `RampCommandToTarget()` độc lập (point 1..59),
  không phải một lệnh ramp 59°.
- [ ] CW final 1-degree approach (point 59→60), log per-tick.
- [ ] A0: pre-position (60 lệnh) + local-backoff CCW (1 lệnh) + final CW
  (1 lệnh), `ReversalCount=2`.
- [ ] Command origin normalization không tạo chuyển động.
- [ ] V3 diagnostics và structural gate — **hai contract riêng B/A0**.
- [ ] `APPROACH_RESULT` formatter protocol-specific (B vs A0), field không
  áp dụng là `NA`.
- [ ] **Analyzer xuất `PostTurnRepeatRMSDeg`/`ClosureNormalizedDeltaRMSDeg`/
  `ClosureNormalizedDeltaMaxAbsDeg`/`PostTurnAnalysisValid`** trên từng
  official run — không chỉ "parse được protocol V3", vì PASS/FAIL phụ
  thuộc residual (mục 7.2b).
- [ ] Contract/regression tests pass (kể cả fixture residual mới).
- [ ] Build artifact và build manifest.

### Hardware

- [ ] P03 V3.1 log.
- [ ] P06 V3.1 log.
- [ ] Báo cáo so với V2 baseline.
- [ ] Quyết định PASS/MIXED/FAIL.
- [ ] A0-B-A0 confirmation nếu V3.1 PASS.
- [ ] P02/P04/P05 expansion nếu confirmation PASS.

## 10. Điều kiện hoàn thành V3

V3 chỉ hoàn thành khi một protocol không bias riêng theo product đạt đồng
thời Closure margin (7.2), **residual hậu vòng margin (7.2b)**, endpoint
(7.3), acquisition, repeatability và không làm thay đổi định nghĩa phép đo
NL (7.4, có tính đến giới hạn so sánh do dịch sector ở 6.3) trên toàn bộ
product đã test. Closure margin một mình, dù đạt trên mọi product, không
đủ để coi V3 hoàn thành nếu residual không cải thiện tương ứng.

