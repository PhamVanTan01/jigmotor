# Từ điển thông số đo của JIG motor

> Phiên bản tổng hợp: 2026-08-05
> Phạm vi: firmware đo nonlinear hiện tại của dự án `jigmotor`
> Nguồn chuẩn: `Core/Src/nonlinear_test.c`, contract nonlinear và log schema hiện hành

## 1. Mục đích tài liệu

Tài liệu này định nghĩa các đại lượng đang được JIG ghi nhận, công thức tính, ý nghĩa vật lý, ảnh hưởng đối với kết quả motor và giới hạn diễn giải. Đây là tài liệu tra cứu khi:

- đọc một file log mới;
- so sánh hai motor hoặc hai JIG;
- xác định một thay đổi đến từ motor, mounting, sensor, controller hay acquisition;
- quyết định một run có đủ tin cậy để đưa vào thống kê hay không.

## 2. Ranh giới phép đo bắt buộc phải nhớ

JIG hiện tại không có encoder tham chiếu độc lập. Vì vậy JIG không đo được sai số riêng của MA600 hoặc riêng của motor. Đại lượng quan sát là:

\[
\boxed{\text{Motor + nam châm + mounting + MA600 + JIG + PWM/controller}}
\]

Policy hiện tại thể hiện đúng ranh giới này:

- `MeasurementDefinition=WHOLE_SYSTEM_COMMAND_TRACKING`
- `AcceptanceMode=REPORT_ONLY`
- `WHOLE_SYSTEM_REPORT_ONLY_V1`

Do đó:

- `NL`, `INL`, `H1`, `H2`, `H36` là đặc trưng của **toàn hệ thống đo**;
- chỉ được quy một khác biệt cho motor sau khi sensor, khoảng cách, lực siết, góc lắp, firmware, nhiệt và JIG đã được kiểm soát;
- dòng `Motor OK!` hiện có nghĩa giao thức/thu thập đã hoàn thành hợp lệ, không phải motor đã đạt một specification NL của sản phẩm.

## 3. Ba lớp thông số

| Lớp | Nội dung | Có dùng trực tiếp để kết luận motor không? |
|---|---|---|
| Đáp ứng motor–hệ thống | NL, RMS, P2P, harmonic, closure, tracking | Có, nhưng chỉ sau khi validity và mounting đạt |
| Tính hợp lệ phép đo | Acquisition, settle, config gate, run role, cooldown | Không; dùng quyết định dữ liệu có đáng tin không |
| Identity/audit | Firmware, BuildID, JigID, UID, contract, CRC | Không; dùng bảo đảm hai phép đo có thể so sánh |

## 4. Hình học của một sweep

Thiết kế hiện tại:

| Thành phần | Giá trị |
|---|---:|
| Khoảng capture | `0°..370°` |
| Số điểm capture | 371, index `0..370` |
| Khoảng dùng tính NL chính | `0°..359°` |
| Số điểm phân tích | 360 |
| Điểm closure | index 360 |
| Vùng post-turn | index `361..370` |
| Bước góc danh nghĩa | 1° |
| Bước raw | xen kẽ 182/183 raw |
| Số mẫu MA600 mỗi điểm | 64 |

Mười điểm `361..370` không thuộc phép tính NL 360 điểm. Chúng được giữ lại để so sánh vùng sau một vòng với các điểm `1..10`, qua đó kiểm tra tính tuần hoàn, hysteresis và độ lặp của chuyển động.

## 5. Công thức sai số theo từng điểm

Với điểm `i`:

\[
TargetMagnitudeRaw_i=\operatorname{round}\left(\frac{i\times65536}{360}\right)
\]

\[
MeasuredRelativeRawQ16_i=PointMeanRawQ16_i-PointMeanRawQ16_0
\]

\[
TargetRelativeRawQ16_i=Direction\times TargetMagnitudeRaw_i\times65536
\]

\[
ErrorRawQ16_i=MeasuredRelativeRawQ16_i-TargetRelativeRawQ16_i
\]

\[
ErrorDeg_i=ErrorRawQ16_i\frac{360}{65536^2}
\]

### Quy ước dấu

- Canonical/shadow: `MEASURED_MINUS_TARGET`.
- Record `DATA` legacy: `TARGET_MINUS_MEASURED`.

Hai nguồn có dấu ngược nhau. Tool phân tích phải đọc contract/schema, không được ghép trực tiếp hai cột error mà không chuẩn hóa dấu.

## 6. Các đại lượng NL chính

Cho đường sai số 360 điểm là \(e_i\), với \(i=0..359\).

| Thông số trong log/tool | Định nghĩa | Ý nghĩa | Cách diễn giải khi tăng |
|---|---|---|---|
| `MeanDC` | \(\bar e=\frac{1}{360}\sum e_i\) | Offset trung bình của toàn đường | Điểm gốc, load angle hoặc bias điều khiển có thể đã dịch |
| `RMS_AC` | \(\sqrt{\frac{1}{360}\sum(e_i-\bar e)^2}\) | Mức dao động phi tuyến sau khi bỏ DC | Ripple/biến dạng toàn vòng lớn hơn |
| `RawP2P`, `Motor_Error_P2P_Deg` | \(\max(e)-\min(e)\) | Khoảng sai số cực đại | Nhạy với đỉnh đơn, breakaway và outlier |
| `Motor_System_INL_Deg` | `RawP2P / 2` | Biên độ INL đối xứng tương đương của hệ thống | Biên sai số hệ thống tăng; không phải sensor INL riêng |
| `RobustP2P`, `Nonlinear N Angle` | mean 5 điểm lớn nhất − mean 5 điểm nhỏ nhất | NL chống một outlier đơn tốt hơn RawP2P | Có vùng sai số lặp lại rộng hơn |
| `Nonlinear Final Average` | Trung bình RobustP2P của các official run hợp lệ | Giá trị NL tổng kết hiện tại | Chỉ đáng tin nếu validity và mounting đạt |
| `P5`, `P95` | Phân vị 5% và 95% | Biên robust của phần lớn đường sai số | Cho biết phân bố, không phụ thuộc đúng một cực trị |
| `P95-P5` | Khoảng phân vị 90% | Độ rộng robust của sai số | Toàn đường sai số đang mở rộng |
| `RMS`/`NL TC rms` | \(\sqrt{mean(e_i^2)}\) | Gồm cả DC và AC | Có thể tăng chỉ vì offset MeanDC |
| `P99AbsDeviation` | P99 của \(|e_i-\bar e|\) | Sai lệch gần cực trị nhưng ít nhạy hơn max | Các vùng lỗi xấu nhất tăng |
| `CrestFactor` | \(\max|e_i-\bar e|/RMS_{AC}\) | Độ tập trung/độ nhọn của đỉnh lỗi | Lỗi tập trung tại ít góc thay vì trải đều |

### Quy tắc đọc kết hợp

| Hiện tượng | Nhận định ưu tiên |
|---|---|
| RawP2P tăng, RobustP2P không tăng | Có thể là điểm lỗi đơn hoặc acquisition outlier |
| RawP2P và RobustP2P cùng tăng | Có biến dạng thật trên một vùng góc |
| RMS_AC thấp, P2P cao | Phần lớn vòng tốt nhưng có đỉnh lỗi cục bộ |
| RMS_AC và RobustP2P cùng cao | Sai số phân bố trên nhiều góc |
| MeanDC đổi, RMS_AC gần như không đổi | Đường bị dịch offset, hình dạng ít đổi |
| CrestFactor tăng mạnh | Cần tìm vị trí breakaway, mounting snap hoặc lỗi cục bộ |

## 7. Phân tích harmonic

Mô hình DFT:

\[
e(\theta)=Mean+\sum_k[a_k\cos(k\theta)+b_k\sin(k\theta)]
\]

\[
A_k=\sqrt{a_k^2+b_k^2},\qquad Phase_k=\operatorname{atan2}(b_k,a_k)
\]

| Harmonic | Chu kỳ/vòng cơ | Ý nghĩa chẩn đoán có thể có |
|---|---:|---|
| `H1/A1` | 1 | Lệch tâm, sai đồng tâm motor–nam châm–sensor, gradient từ một vòng |
| `H2/A2` | 2 | Nghiêng, ellipticity, biến dạng hai thùy, bất đối xứng sensor/mounting |
| `H3/A3` | 3 | Bất đối xứng ba thùy hoặc họ hình học/điện bậc ba |
| `H4/A4` | 4 | Thành phần thường xuất hiện trong mô hình hiệu chỉnh sensor; ở đây vẫn là whole-system |
| `H6/A6` | 6 | Một chu kỳ trên mỗi chu kỳ điện của motor 6 cặp cực |
| `H8/A8` | 8 | Thành phần hiệu chỉnh bậc cao thường gặp trong mô hình sensor |
| `H9/A9` | 9 | Họ coupling điện/cơ lân cận, dùng chẩn đoán |
| `H12/A12` | 12 | Hai chu kỳ trên mỗi chu kỳ điện; cũng có thể trùng nguồn hình học |
| `H18/A18` | 18 | Ba chu kỳ trên mỗi chu kỳ điện |
| `H27/A27` | 27 | Ripple điện/chuyển mạch bậc cao hơn |
| `H36/A36` | 36 | Sáu ripple mỗi chu kỳ điện; thường liên quan hỗn hợp PWM, commutation, cogging, back-EMF |
| `H45/A45` | 45 | Họ ripple bậc cao lân cận |
| `H72/A72` | 72 | Harmonic bậc hai của H36; phản ánh dạng sóng H36 nhọn/không sin |
| `H108/A108` | 108 | Harmonic bậc ba của H36; chi tiết ripple tần số cao hơn |

### H1 và H2

- H1/H2 rất nhạy với khoảng cách sensor–nam châm, độ nghiêng, độ đồng tâm, góc lắp và lực siết.
- Chúng phù hợp để tạo `mounting fingerprint`.
- Chúng chưa phải đặc tính riêng của motor.
- A2 thay đổi sau remount hoặc xoay motor không tự động chứng minh motor thay đổi.
- Amplitude cho biết độ mạnh; phase cho biết vị trí góc tương đối của thành phần.

### Phase và `PhaseValidMask`

- Phase chỉ có ý nghĩa khi amplitude đủ lớn.
- Ngưỡng hợp lệ hiện tại: amplitude tối thiểu khoảng `0.05°`.
- `PhaseValidMask` đánh dấu harmonic nào có phase đủ tin cậy.
- Phase tham chiếu theo điểm gốc sweep, chưa phải datum cơ khí tuyệt đối dùng chung giữa nhiều JIG/remount.

### Các trường harmonic tổng hợp

| Thông số | Định nghĩa/ý nghĩa |
|---|---|
| `DominantSelectedOrder` | Bậc harmonic lớn nhất trong tập được chọn |
| `DominantSelectedAmplitudeDeg` | Biên độ của harmonic trội |
| `DominantSelectedEnergyRatio` | Tỷ lệ năng lượng AC do harmonic trội giải thích |
| `Residual_RMS_H6` | RMS còn lại sau khi trừ Mean và H6 |
| `Residual_RMS_H36` | RMS còn lại sau khi trừ Mean và H36 |
| `Residual_RMS_Full` | Phần RMS mô hình harmonic legacy chưa giải thích |
| `Residual_RMS_Extended` | Phần RMS mô hình harmonic mở rộng chưa giải thích |
| `Fitted_P2P` | P2P của đường dựng lại từ mô hình harmonic legacy |
| `Fitted_P2P_Extended` | P2P của đường dựng lại từ mô hình mở rộng |
| `FitExplainedRatio` | Tỷ lệ năng lượng sai số được mô hình giải thích |
| `LegacyModelValid` | Mô hình legacy tính được hợp lệ về số học/dữ liệu |
| `ExtendedModelValid` | Mô hình mở rộng tính được hợp lệ về số học/dữ liệu |

`FitExplainedRatio` cao không có nghĩa motor tốt. Nó chỉ cho biết sai số có cấu trúc harmonic đều và dễ mô hình hóa.

`AElectrical6` hiện là alias của A36 khi motor có 6 cặp cực:

\[
ElectricalRippleOrder=6\times PolePairs=36
\]

## 8. Closure và vùng post-turn

### `ClosureErrorDeg`

\[
Closure=Measured(360^\circ)-Measured(0^\circ)-360^\circ
\]

Closure kiểm tra hệ thống có trở về cùng vị trí tương đối sau một vòng hay không. Nó nhạy với:

- approach và reversal;
- hysteresis/load angle;
- stiction và breakaway;
- controller và settle;
- trượt/mất đồng bộ chuyển động.

Nó không phải NL toàn vòng.

`ClosureValid` hiện dùng ngưỡng pilot:

\[
|Closure|\leq0.20^\circ
\]

Đây là gate integrity thử nghiệm, không phải specification chất lượng cuối của sản phẩm.

### `CLOSURE_PROBE`

Các record `INITIAL`, `HOLD_50`, `HOLD_100`, `HOLD_200` đo lại endpoint sau thời gian giữ:

| Trường | Ý nghĩa |
|---|---|
| `ClosureErrorDeg` | Sai số tại endpoint ở từng thời điểm |
| `ClosureProbeDelta...` | Thay đổi so với thời điểm initial |
| `WindowP2P` | Rung/noise trong cửa sổ đo ngắn |
| `WindowDrift` | Dịch chuyển từ đầu đến cuối cửa sổ |

- Closure thay đổi theo thời gian: có relaxation/settling.
- Closure gần như đứng yên: sai lệch đã đóng băng, nghiêng về endpoint/hysteresis hơn là thiếu dwell.

### Điểm `361..370`

So sánh \(Error_{360+i}\) với \(Error_i\), `i=1..10`:

- sai khác nhỏ: đường sai số có tính tuần hoàn tốt;
- sai khác lớn: cần xét hysteresis, nhiệt, approach hoặc điều khiển không lặp.

## 9. Chất lượng bám chuyển động

| Thông số | Ý nghĩa | Ảnh hưởng/diễn giải |
|---|---|---|
| `TrackingError_RMS_Deg` | RMS giữa vị trí thực và target trong sweep | Cao có thể do mất đồng bộ, thiếu torque, ma sát hoặc controller |
| `TrackingError_MaxAbs_Deg` | Sai số bám lớn nhất | Phát hiện stall, pull-out hoặc breakaway lớn |
| `PositionErrorRaw/Deg` | Sai số sau settle tại từng điểm | Rotor có thực sự tới gần target hay không |
| `PollCount` | Số poll trước khi kết luận settle | Cao: hội tụ chậm, stiction hoặc controller yếu |
| `StabilityValid` | Biến thiên giữa poll nằm trong ngưỡng đủ số lần liên tiếp | Không đạt: rotor vẫn rung hoặc trôi |
| `TargetProximityValid` | Vị trí nằm trong cửa sổ target | Không đạt: rotor ổn định nhưng ổn định sai vị trí |
| `SettleValid` | `StabilityValid && TargetProximityValid` | Điều kiện một điểm chuyển động hợp lệ |
| `SettleResult` | `OK`, `TIMEOUT`, `WRONG_POSITION`, `ACQUISITION_ERROR` | Phân loại lỗi settle |
| `ObservedBacktrackCount` | Số lần rotor đi ngược hướng dự kiến | Có thể do dynamics, hysteresis, cogging hoặc controller |
| `ObservedBacktrackMaxRaw` | Backtrack lớn nhất | Độ nghiêm trọng của reversal ngoài ý muốn |

Ngưỡng integrity hiện tại gồm tracking RMS khoảng `15°`, tracking max khoảng `30°`, ổn định khoảng `9 raw` và target proximity khoảng `910 raw` (xấp xỉ `5°`). Đây là ngưỡng bắt lỗi chuyển động lớn, không chứng minh phép đo NL chính xác ở mức nhỏ.

### Record `MOTION_RESULT`

Record này tổng hợp:

- số lần đọc context/ramp/settle;
- accepted samples và retries;
- transport errors, jump rejects và failed samples;
- số điểm stable, target-valid, settle-valid;
- timeout, wrong-position;
- settle error lớn nhất.

Nó là bằng chứng phép sweep được thực thi đúng, không phải metric chất lượng motor.

## 10. Controller state và home

| Trường `CONTROL_STATE` | Ý nghĩa |
|---|---|
| `ResetApplied`, `ResetValid` | State controller đã được reset đúng trước run |
| `IntegralBefore/After` | Tích phân PID trước/sau reset |
| `LastErrorBefore/After` | Sai số controller còn lưu |
| `CommandBefore/After` | Lệnh cũ còn lưu |
| `DerivativeBefore/After` | Trạng thái đạo hàm |
| `OutputStep`, `Power`, `Enabled` | Trạng thái output điều khiển |
| `HomeResult` | Kết quả đưa rotor về điểm bắt đầu |
| `HomeDurationMs` | Thời gian home |
| `HomeUpdateCount` | Số update controller trong home |
| `InitialError`, `FinalError` | Sai số trước/sau home |

State không được đồng bộ có thể làm run hiện tại phụ thuộc run trước. Integral còn dư có thể tạo load-angle offset. Home khác nhau có thể thay đổi điểm 0, closure và hình dạng đường NL quan sát được.

## 11. Motion profile

Record `MOTION_PROFILE` mô tả điều kiện tạo phép đo:

| Trường | Ý nghĩa |
|---|---|
| `ProfileID` | ID thuật toán chuyển động |
| `HomeController` | Controller dùng cho home |
| `TickMs` | Chu kỳ cập nhật lệnh |
| `CommandsPerDegree` | Mật độ lệnh trên mỗi độ |
| `Power` | Mức kích motor |
| `LockDuration/Commands` | Thời gian và số lệnh lock |
| `SegmentCount/CommandCount` | Số segment và tổng lệnh |
| `TimingOverruns` | Số lần không đạt cadence |
| `ObservedBacktrack...` | Chuyển động ngược quan sát được |

Khác `ProfileID`, power, tick hoặc lệnh trên mỗi độ có thể thay đổi load angle và đường NL. Không so trực tiếp hai log có motion profile khác nhau như cùng một measurand.

## 12. Approach, pre-roll và điểm bắt đầu

`APPROACH_RESULT` ghi cách rotor đi tới point 0:

| Trường | Ý nghĩa |
|---|---|
| `ApproachPath` | Chuỗi hướng di chuyển, ví dụ `CW_CCW_CW` |
| `ReversalCount` | Số lần đổi chiều |
| `CommandDeltaRaw` | Quãng đường đã ra lệnh |
| `ObservedDeltaRaw` | Quãng đường thực tế encoder quan sát |
| `TargetErrorRaw` | `Observed - Commanded` |
| `OriginShiftObservedRaw` | Điểm gốc thực tế đã dịch bao nhiêu |
| `OriginShiftTargetErrorRaw` | Sai số shift so với mục tiêu |
| `PreRoll...`, `Final...` | Kết quả từng leg pre-roll/final |
| `ApproachStructuralValid` | Chuỗi approach hợp lệ về cấu trúc và acquisition |

`ApproachStructuralValid=1` không tự chứng minh endpoint chính xác. Approach tác động đến closure và có thể tác động NL qua reversal, hysteresis, load angle hoặc sector cơ khí được chọn.

Các field này hiện là diagnostic (`Official=0`), không phải chỉ số product.

## 13. Acquisition và SPI MA600

| Thông số | Ý nghĩa |
|---|---|
| `AcqReadAttempts` | Tổng số lần thử đọc |
| `AcceptedSamples` | Số mẫu được chấp nhận |
| `Retries` | Số lần phải đọc lại |
| `TransportErrors`, `SPIFailures` | Lỗi truyền SPI |
| `JumpRejects` | Mẫu bị loại vì nhảy góc bất hợp lý |
| `FailedSamples` | Không lấy được mẫu hợp lệ |
| `SkippedSlots` | Mất slot acquisition |
| `TimingOverruns` | Không hoàn thành đúng cadence |
| `MaxConsecutiveFailures` | Chuỗi lỗi liên tục dài nhất |
| `ContextReacquireCount` | Số lần unwrap context bị mất và tạo lại |
| `AcquisitionResult` | Kết quả tổng thể acquisition |
| `RawCRC32` | Dấu vân tay kiểm tra dữ liệu không bị thay đổi |

Đây là thông số độ tin cậy dữ liệu, không phải chất lượng motor. Một run có transport error, failed sample hoặc context reacquire không nên dùng để kết luận khác biệt NL nhỏ.

Record `ACQ` theo điểm còn có CS cycle, PWM counter, số attempt và flags để xác định lỗi xảy ra ở thời điểm nào.

## 14. Noise tĩnh MA600

Dòng `MA600 noise (last 5s)` chứa:

| Trường | Ý nghĩa |
|---|---|
| `P2P` | Biên độ noise cực đại trong cửa sổ |
| `StdDev` | Độ lệch chuẩn noise |
| `Drift` | Dịch chuyển đầu–cuối cửa sổ |
| `MaxStep` | Bước nhảy lớn nhất giữa hai mẫu |
| `N` | Số mẫu |
| `valid` | Cửa sổ đo có hợp lệ không |

Đây là noise floor của sensor/JIG khi đứng yên. Harmonic có amplitude gần noise floor sẽ có phase và độ khác biệt kém tin cậy. Noise tĩnh không phải NL của motor.

## 15. Mounting precheck

`MOUNT_PRECHECK_RESULT` hiện có:

- RobustP2P;
- H1 amplitude/phase;
- H2 amplitude/phase;
- closure;
- tracking;
- acquisition status;
- `MountValid`, `RejectReason`, `GateEnabled`.

Trạng thái hiện tại:

- H1/H2 được ghi để quan sát nhưng chưa có envelope calibrated theo product/JIG;
- `MountValid` chủ yếu dựa trên tracking, closure và acquisition;
- `ENABLE_MOUNT_PRECHECK_GATE=0`, vì vậy precheck chưa chặn batch.

Dữ liệu thực nghiệm đã cho thấy sensor, lực siết và remount làm thay đổi H1/H2 và đỉnh NL. Vì vậy H1/H2 nên được dùng làm mounting fingerprint sau khi xây dựng ngưỡng riêng bằng dữ liệu Gage R&R.

## 16. Cấu hình MA600

| Field | Chức năng | Ảnh hưởng đến kết quả |
|---|---|---|
| `Zero` | Offset điểm 0 | Dịch datum góc |
| `Dir` | Chiều tăng góc | Sai sẽ đảo chiều/dấu |
| `Filt` | Bộ lọc nội MA600 | Thay đổi noise, bandwidth và delay |
| `Status` | Trạng thái sensor/NVM | Báo lỗi cấu hình hoặc phần cứng |
| `Prt` | Chế độ giao tiếp/output | Sai mode có thể làm đọc không đúng |
| `RmapId` | Nhận dạng register map/profile | Xác nhận sensor dùng đúng map |
| `CorrNonZeroCount` | Số entry correction khác zero | Cho biết LUT correction đang hoạt động |
| `CorrCRC32` | CRC bảng correction | Phát hiện bảng khác nhau giữa JIG |
| `ConfigReadValid` | Đọc config thành công | Điều kiện kỹ thuật ban đầu |
| `ConfigValid` | Config thực tế khớp expected profile | Không khớp thì measurand đã thay đổi |
| `PolicyAGatePassed` | Được phép chạy theo policy | Gate bảo vệ phép đo |
| `ExpectedProfileFound` | UID/Jig có profile khai báo | Không có thì không biết cấu hình chuẩn |
| `RejectReason` | Lý do từ chối | Ví dụ `FILT_MISMATCH` |

Project yêu cầu `ExpectedCalibrationState=ZERO_TABLE`: bảng correction phải bằng zero. Mục tiêu là không để một bảng bù riêng của sensor che hoặc làm thay đổi đáp ứng thực của cụm đo.

## 17. Batch, precondition và lịch sử nhiệt

| Field | Ý nghĩa |
|---|---|
| `BatchID` | ID của batch |
| `CycleOrder` | Thứ tự cycle |
| `RunOrder` | Thứ tự run |
| `RunRole` | `PRECONDITION` hoặc `OFFICIAL` |
| `EligibleForStatistics` | Run có được đưa vào thống kê |
| `PreconditionCount` | Số run ổn định/làm nóng |
| `CooldownTargetMs` | Thời gian nghỉ mục tiêu |
| `CooldownActualMs` | Thời gian nghỉ thực tế |
| `CooldownValid` | Cooldown có đúng cửa sổ cho phép |
| `MotorActiveDurationMs` | Thời gian motor hoạt động |
| `TimeSincePreviousRunMs` | Thời gian từ run trước |
| `PreconditionValid` | Precondition hoàn thành hợp lệ |

Cấu hình batch hiện tại là một precondition và mười official run, cooldown khoảng 120 giây. Precondition không được đưa vào thống kê official.

Các field này chỉ kiểm soát lịch sử theo thời gian. Chưa có cảm biến nhiệt motor nên không chứng minh hai run ở cùng nhiệt độ thực.

## 18. Identity, schema và audit

| Nhóm field | Mục đích |
|---|---|
| `Firmware`, `BuildID`, `SourceId` | Xác định code đã tạo log |
| `ProfileFingerprint`, `AppProfile` | Xác định đúng build/profile |
| `MCU_UID`, `JigID`, `JigKnown` | Xác định phần cứng JIG |
| `MotorID` | Xác định product/motor; có thể nhập thủ công |
| `MotorPolePairs` | Số cặp cực dùng cho kích từ và quy đổi harmonic điện |
| `TestID`, `SweepID`, `BatchID` | Liên kết record cùng phép đo |
| `ContractVersion`, `SchemaVersion` | Xác định công thức và field semantics |
| `CapturedPoints`, `AnalysisPoints` | Xác định số điểm capture/phân tích |
| `FeatureComputeTime` | Thời gian MCU tính feature |
| `FreeHeap`, `MinEverFreeHeap`, stack high-water | An toàn tài nguyên MCU |
| `UARTWriteFailureCount/Status` | Log có bị mất do UART không |

Các field trên không đánh giá motor nhưng bắt buộc để hai kết quả có thể so sánh.

Sai số cặp cực đặc biệt nguy hiểm: nó làm sai pha điện, có thể tăng tracking error/ripple hoặc làm motor mất đồng bộ. Cấu hình hiện tại của product đã xác nhận sử dụng 6 cặp cực, trừ khi có build/test riêng được kiểm chứng.

## 19. `RESULT`, `SHADOW_RESULT`, `END` và official validity

### `RESULT`

Đây là summary theo schema legacy đang được firmware dùng làm nguồn kết quả official.

### `SHADOW_RESULT`

Đây là phép tính canonical Q16 để đối chiếu và phát triển contract. Nó có thể chứa NL, RMS, harmonic, closure và model-fit đầy đủ hơn nhưng hiện được đánh dấu `Official=0`.

### `END`/`SHADOW_END`

Xác nhận sweep đã hoàn thành, đủ point và trạng thái measurement/acquisition.

Một run chỉ nên vào thống kê khi đồng thời thỏa:

1. `RunRole=OFFICIAL`;
2. `EligibleForStatistics=1`;
3. `MeasurementValid=1`;
4. có record kết thúc hợp lệ;
5. đủ toàn bộ AnalysisPoints;
6. acquisition/config/identity phù hợp contract.

Không được suy official validity chỉ từ vị trí dòng hoặc `RunOrder`.

## 20. Control A5 — profile riêng, không phải sweep NL

Firmware dùng kiến trúc dual-image compile-time. Control A5 là profile riêng, không chạy đồng thời với measurement sweep.

Control A5 lấy khoảng 2048 mẫu ở 1 kHz khi giữ tĩnh và tính:

- P2P raw;
- drift raw;
- standard deviation và RMS;
- median, MAD, robust sigma;
- linear slope;
- detrended standard deviation;
- max step;
- autocorrelation/Allan deviation;
- PWM-phase harmonic;
- `RawCRC32`.

Các trường này đánh giá độ ổn định sensor/hold và noise tương quan PWM tại một vị trí. Chúng không đo NL trên toàn vòng 360° và không được trộn với `Nonlinear N Angle`.

## 21. Quan hệ với thuật toán Gremsy legacy

Trong code Gremsy cũ:

\[
NLLow=\min(e_i)
\]

\[
NLHigh=\max(e_i)
\]

\[
NLAngle=NLHigh-NLLow
\]

`NLAngle` legacy gần nhất với `Motor_Error_P2P_Deg` hiện tại.

Nó không giống hoàn toàn `Nonlinear N Angle` hiện tại vì metric mới là:

\[
mean(Top5)-mean(Bottom5)
\]

Metric mới giảm tác động của một mẫu lỗi đơn. Khi đối chiếu log/code cũ và mới phải ghi rõ đang dùng raw P2P hay robust top-5/bottom-5.

## 22. Thứ tự chuẩn để đọc một log

1. Kiểm tra firmware, BuildID, contract/schema và số cặp cực.
2. Kiểm tra JigID/UID và MA600 config gate.
3. Kiểm tra acquisition: SPI, failed sample, jump reject, timing, context reacquire.
4. Kiểm tra `RunRole`, `EligibleForStatistics`, END và đủ 360 analysis points.
5. Kiểm tra tracking, motion, settle và backtrack.
6. Kiểm tra closure và overlap `361..370`.
7. Kiểm tra H1/H2/mounting fingerprint.
8. Sau đó mới đọc đường error 360 điểm.
9. Đánh giá độ lớn bằng RobustP2P, RMS_AC, P99 và CrestFactor.
10. Đánh giá hình dạng/nguồn lỗi bằng H1, H2, H36 và residual.
11. So sánh với baseline cùng product, JIG, sensor, motion profile, lực siết và điều kiện nhiệt.

Bộ metric tối thiểu nên giữ khi đánh giá motor:

\[
\boxed{RobustP2P,\ RMS_{AC},\ P99,\ CrestFactor,\ H1,\ H2,\ H36,\ Residual,\ Closure}
\]

kèm toàn bộ đường sai số 360 điểm và các cờ validity.

## 23. Những kết luận không được phép rút ra từ một field đơn

| Quan sát | Không được kết luận ngay | Cần kiểm tra thêm |
|---|---|---|
| NL cao | Motor chắc chắn xấu | Mounting, H1/H2, sensor, tracking, top/bottom angle |
| H1 cao | Motor lệch tâm | Sensor/nam châm/JIG/remount cùng đóng góp |
| H2 cao | Nam châm nghiêng chính xác bao nhiêu | H2 là fingerprint, chưa phải phép đo tilt đã hiệu chuẩn |
| H36 cao | Chắc chắn do cogging | PWM, commutation, back-EMF và control cũng có thể đóng góp |
| Closure tốt | NL chính xác | Có thể có triệt tiêu endpoint trong khi curve vẫn sai |
| TrackingValid | Bám chính xác | Ngưỡng hiện tại chỉ loại lỗi gross motion |
| FitExplainedRatio cao | Motor tốt | Chỉ chứng minh lỗi có cấu trúc đều |
| `Motor OK!` | Product đạt spec NL | Chỉ chứng minh phép chạy hợp lệ theo protocol hiện tại |

## 24. Nguồn đối chiếu khi tài liệu và log không khớp

Ưu tiên theo thứ tự:

1. Source firmware của đúng `BuildID` đã tạo log.
2. Contract/schema ID được ghi trong chính log.
3. Test contract tự động của cùng build.
4. Tài liệu contract hiện hành.
5. Tài liệu phase/plan lịch sử.

Các file tham chiếu chính:

- `Core/Src/nonlinear_test.c`
- `Core/Src/main.c`
- `Core/Inc/app_mode.h`
- `docs/nonlinear-metric-contract-v2.md`
- `docs/measured-and-checked-parameters.md`
- `docs/nonlinear-log-schema-v6.md`
- `tools/analyze_motor_logs.py`
- `scripts/analyze_nonlinear_logs.ps1`

Tài liệu này cần được cập nhật khi một trong các nội dung sau thay đổi: contract ID, AnalysisPoints, closure index, sign convention, official source, harmonic order, motion profile, validity gate hoặc MA600 expected profile.
