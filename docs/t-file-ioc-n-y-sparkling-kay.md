# B0-B: Same-direction local approach cho điểm 0 (equal-approach experiment) — REV 6

## Đã sửa theo audit vòng 5 (REV 5 vẫn bị "Request changes") — đã tự kiểm tra lại bằng code thật

Trước khi sửa, tự đọc lại đúng vùng code liên quan (không tin số liệu review một cách mù quáng):
- `nonlinear_test.c:1976-2021` (protocol A thật, chưa sửa) — xác nhận cấu trúc gốc: 1 lời gọi
  `MA600_AcquireSample()` đứng riêng (dòng 1977, KHÔNG bọc snapshot/accumulate, nghiễm nhiên tính
  vào "context") → rồi mới tới `WaitForPointSettle()` (dòng 1996, bọc snapshot/accumulate vào
  `out->settleAcquisition` chính). Lỗi acquisition ở acquire riêng (1979-1988) và ở settle
  (1999-2014, chỉ khi `== NL_SETTLE_ACQUISITION_ERROR`) đều **return trực tiếp** kèm tự tay tính
  `contextAcquisition`/trừ counter/set field chẩn đoán — KHÔNG dùng `goto capture_complete`.
  → Review đúng: REV 5 đã KHÔNG tự tay tính lại các field này ở nhánh lỗi B0-B, khiến
  `contextAcquisition`/`Acq*` bị bỏ trống ở early-return. Nhưng review đề xuất `goto
  capture_complete` là **sai chỗ**: nhãn đó (dòng 2261) nằm SAU các khai báo `pos`/`pointIndex`/
  `absoluteAngleAtMax`/... (dòng 2043-2052) — nhảy `goto` từ B0-B (chèn TRƯỚC các khai báo đó,
  đúng vị trí thay thế đoạn 1976-2021) tới nhãn đó sẽ đọc các biến CHƯA ĐƯỢC KHỞI TẠO (goto nhảy
  qua phần khởi tạo là hợp lệ về cú pháp C nhưng để lại giá trị rác) — một lỗi mới còn nặng hơn.
  → **Quyết định đúng**: giữ nguyên đúng pattern PRE-LOOP đã có sẵn ở protocol A (return trực
  tiếp + tự tay tính toán tại chỗ), áp dụng y hệt cho cả 5 nhánh lỗi B0-B — không phát minh
  `goto` mới, không cần dời khai báo biến.
- `nonlinear_test.c:1122-1125` — xác nhận `NL_SETTLE_OK = 0` (giá trị enum đầu tiên) → review
  đúng: struct `NlSweepCapture_t` zero-init khiến 1 field `ApproachXSettleResult` CHƯA TỪNG được
  gán sẽ đọc ra `NL_SETTLE_OK`/"OK" một cách sai lệch (trông như đã chạy và pass) nếu không có cờ
  "đã chạy giai đoạn này chưa" riêng.
- `nonlinear_test.c:41-48,1995,2080,2195,2247` — xác nhận có `SetEngineState()`/
  `NonlinearEngineState_t` (`NL_ENGINE_SETTLE`/`NL_ENGINE_RAMP`/`NL_ENGINE_ACQUIRE`...) được gọi
  trước MỌI settle/ramp/acquire trong sweep hiện tại → review đúng, B0-B phải gọi tương tự để
  không phá vỡ khả năng quan sát trạng thái engine khi đang chạy B0-B.
- `nonlinear_test.c:333-340,3449` — xác nhận `ENABLE_CCW_ENGINEERING_TEST` có thật (mặc định 0,
  kiến trúc-only), khi bật thì sweep có thể chạy CCW (`direction` truyền vào `CaptureSweep()`) →
  B0-B hard-code "lùi CCW/tiến CW" sẽ KHÔNG còn là "cùng chiều với sweep chính" nếu sweep đó là
  CCW. Review đúng là có lỗ hổng, nhưng **không tổng quát hóa theo `direction`** (thêm rủi ro/độ
  phức tạp không cần thiết cho giả thuyết đang kiểm định, vốn chỉ nhắm sweep CW mặc định) — thay
  vào đó **cấm kết hợp 2 flag** bằng `#error` (ít xâm lấn nhất, đúng tinh thần B0-B).
- `nonlinear_test.c:2542-2555` (`CLOSURE_PROBE_RESULT` thật) — xác nhận đúng field-identity
  pattern: `SchemaVersion,TestID,SweepID,JigID,MotorID,Direction,Official,Protocol,Enabled,
  Started,Complete,...,AcquisitionResult,Status` → dùng làm mẫu chính xác cho `APPROACH_RESULT`
  thay vì chỉ liệt kê field nghiệp vụ như REV 5 đã làm.
- `tools/plot_metric_trend.py:96-102` (đọc lại code thật) — xác nhận `load_runs()` chỉ đẩy vào
  `rec.fields` các field `META` nằm trong tuple whitelist cứng (`HomeDurationMs`,
  `HomeUpdateCount`, `MotorActiveDurationMs`, `CooldownActualMs`, `TimeSincePreviousRunMs`) —
  KHÔNG có `ApproachProtocol`/`ApproachStructuralValid` trong đó, và tool không có nhánh nào đọc
  dòng bắt đầu bằng `APPROACH_RESULT,`. → Khẳng định "không cần sửa gì" ở REV 5 (mục "Ngoài phạm
  vi lần này") là **sai**, cần sửa nhỏ tool này (xem mục 5b mới).

Các điểm sửa cụ thể (chi tiết ở mục 3 "Việc sẽ làm" bên dưới):
- **[P0] Lỗi `NL_SETTLE_ACQUISITION_ERROR` bị hạ cấp sai**: tách 2 nhánh cho mọi settle B0-B —
  `== NL_SETTLE_ACQUISITION_ERROR` (lỗi sensor thật) phải `out->acquisitionResult =
  settleObservation.acquisitionResult; return out->acquisitionResult;` (đúng pattern dòng
  1999-2014); các kết quả không-OK khác (`TIMEOUT`/`WRONG_POSITION`) mới là
  `out->measurementValid = false; return MA600_RESULT_OK;`. Hai lỗi ramp cũng phải gán
  `out->acquisitionResult = approachAcqResult;` trước khi return.
- **[P0] Mọi nhánh lỗi B0-B phải tự tay hoàn thiện counter/diagnostic**, đúng pattern PRE-LOOP có
  sẵn (không dùng `goto capture_complete`, lý do đã nêu ở trên): snapshot
  `out->contextAcquisition`, trừ đúng công thức `Acq*` mở rộng, gán `out->capturedCount = 0`,
  lưu lại MỌI diagnostic đã có tới thời điểm lỗi (không chỉ vài field) vào `NlSweepCapture_t`
  (không phải biến local sẽ mất khi hàm return).
- **[P1] Mỗi giai đoạn B0-B cần cờ `Attempted` riêng** (không dựa vào `NL_SETTLE_OK == 0` của
  zero-init) để `APPROACH_RESULT` in đúng `NA` cho giai đoạn chưa từng chạy tới, thay vì trông
  như "OK".
- **[P1] Sửa lại phân bổ counter theo đúng cấu trúc protocol A**: chỉ "standalone initial
  acquire" (mirror dòng 1977, không bọc) + "initial anchor settle" + "backoff settle" mới tính
  vào `approachSettleAcquisition` (trừ khỏi `Acq*`); **settle điểm 0 cuối cùng** (thay thế đúng
  vai trò settle điểm 0 của protocol A) phải tính vào `out->settleAcquisition` CHÍNH, giống hệt
  protocol A — không trừ 2 lần, giữ `SettlePoints`/`SettleReadAttempts` nhất quán giữa 2
  protocol.
- **[P1] `ApproachStructuralValid` cần thêm `ApproachAcquisitionClean`** (0 retry/transport-
  error/jump-reject/failed-sample trong toàn bộ hoạt động approach) làm thành phần gate, không
  chỉ direction/step-count. Firmware KHÔNG tự định nghĩa lại `MeasurementValid` chính thức —
  việc gộp `B0BEligible = MeasurementValid && ApproachStructuralValid &&
  ApproachAcquisitionClean && (cả 3 settle == OK)` để lại cho phân tích offline (script/Python),
  đúng nguyên tắc "không đổi ý nghĩa field chính thức trong cùng thay đổi" đã có từ đầu dự án.
- **[P1] Không được coi 9/10 đạt là "đạt yêu cầu ≥3 sweep"**: nếu bất kỳ run nào trong batch
  fail nhóm gate cấu trúc, CẢ LEG đó không đạt yêu cầu 10/10 — không loại run lỗi rồi kết luận
  từ các run còn lại. Cập nhật "Tiêu chí đánh giá" cho rõ.
- **[P1] Tách rõ batch pilot (protocol `_V1`) khỏi batch xác nhận**: SAU khi chốt ngưỡng từ dữ
  liệu pilot, phải đổi ID protocol thành `_V2` (không tái sử dụng `_V1` cho cả 2 mục đích) rồi
  chạy lại A→B→A ĐỘC LẬP với `_V2` — chỉ dữ liệu `_V2` mới được dùng để kết luận pass/falsify.
  Việc đổi `_V1`→`_V2` (thêm ngưỡng biên độ đã hiệu chỉnh vào gate) là 1 thay đổi code TÁCH BIỆT,
  SAU thay đổi này — ngoài phạm vi lần này, chỉ ghi nhận yêu cầu quy trình.
- **[P1] Khai báo biến dùng chung phải nằm TRƯỚC `#if`**: `sample`, `acquisitionResult`,
  `settleObservation`, `settleResult` (dùng lại xuyên suốt sweep loop phía sau, không riêng gì
  đoạn origin) phải khai báo unconditional trước `#if ENABLE_B0B_EQUAL_APPROACH`, cả 2 nhánh chỉ
  GÁN giá trị, không khai báo lại — nếu không nhánh B thiếu khai báo, không build được.
- **[P1] Gọi `SetEngineState(NL_ENGINE_SETTLE)`/`SetEngineState(NL_ENGINE_RAMP)`** trước mỗi
  settle/ramp mới của B0-B, đúng convention đã dùng cho mọi settle/ramp khác trong file.
- **[P1] Cấm kết hợp `ENABLE_B0B_EQUAL_APPROACH` với `ENABLE_CCW_ENGINEERING_TEST`** bằng
  `#error` biên dịch — B0-B hiện chỉ kiểm định đúng cho sweep CW (mặc định), chưa tổng quát hóa
  chiều tiếp cận theo `direction`.
- **[P1] `APPROACH_RESULT` cần đủ field định danh** theo đúng mẫu `CLOSURE_PROBE_RESULT` thật:
  `SchemaVersion,TestID,SweepID,JigID,MotorID,Direction,Official=0,Protocol,Started,Complete,
  Status`, KHÔNG chỉ có field nghiệp vụ.
- **[P2] Sửa nhỏ `tools/plot_metric_trend.py`**: thêm `ApproachProtocol`/`ApproachStructuralValid`
  vào whitelist field `META` (xem mục 5b) — không cần parse `APPROACH_RESULT` chi tiết (đủ dùng
  script scratch một lần như các phân tích trước đó trong dự án này).
- **[P2] Số liệu độ dài dòng `META`**: giữ nguyên kết luận "cần record riêng" (đúng), nhưng số đo
  1733 byte là số đo trên 1 log cụ thể, không phải worst-case — test mới (mục 6) phải tự đo độ
  dài dòng `META` thực tế lúc build đó chạy ra và assert `< 1900`, không hard-code số byte cụ
  thể.

Trước khi sửa, tự grep/đọc lại code để xác nhận (không tin theo số liệu review một cách mù
quáng, đúng nguyên tắc dự án này):
- `Core/Inc/ma600.h:27-39` — `MA600_Result_t` đúng là enum tầng sensor/acquisition, không nên
  nhét thêm ý nghĩa "settle thất bại" vào đó -- review đúng.
- `nonlinear_test.c:2448` — `out->measurementValid = structuralValid && out->trackingValid;`
  **có thật**, chạy ở cuối `CaptureSweep()` -- xác nhận nếu chỉ set `measurementValid=false` rồi
  để hàm chạy tiếp bình thường, giá trị đó SẼ bị ghi đè ở đây. Review đúng, bắt buộc phải là
  early-return thật, không phải set-cờ-rồi-tiếp-tục.
- `nonlinear_test.c:3438` — `if (captureResult == MA600_RESULT_OK && nlCaptures[...].
  measurementValid ...)` — caller **đã có sẵn** logic xử lý đúng tổ hợp "`MA600_RESULT_OK` +
  `measurementValid=false`" (coi là "chạy xong nhưng không dùng được"). → Không cần thêm enum
  mới vào `MA600_Result_t`: chỉ cần `return MA600_RESULT_OK;` sớm kèm `out->measurementValid =
  false` gán trực tiếp trước khi return (bỏ qua hoàn toàn đoạn code phía sau, kể cả dòng 2448) là
  đủ, dùng đúng pattern caller đã hỗ trợ sẵn — không phải phát minh cơ chế mới.
- `nonlinear_test.c:534` — `FormatI64()` **đã tồn tại sẵn**, dùng cho mọi field `int64_t` khác
  trong file (`nonlinear_test.c:2484-2992`). → Dùng hàm này cho diagnostic mới, không tự chế
  `%ld` (STM32 `long` là 32-bit, sai định dạng cho `int64_t`, review đúng).
- File log thật (`p03 jig 1 test 8.txt`) — dòng `META` hiện tại dài **1733 byte**, buffer
  `LogLineLarge()` chỉ 1900 byte (`nonlinear_test.c:454`) → **chỉ còn ~167 byte dư**, không đủ
  chỗ cho ~15+ field `Approach*` mới → sẽ bị `vsnprintf` cắt âm thầm nếu nhét hết vào META. Review
  đúng, cần record riêng.
- `docs/phase3b0-closure-measurement-review.md:434-449` — đọc lại kỹ: yêu cầu "acquisition and
  motion structural checks pass 3/3... Only after this gate passes may the 10-run repeatability
  batch be enabled" nằm trong **Stage B0-D (Freeze the measurement protocol)**, một giai đoạn
  SAU B0-B/B0-C, khi CHỐT protocol cuối cùng cho sản xuất — không phải yêu cầu của chính B0-B.
  Phần B0-B (`:409-422`, đã trích ở trên) chỉ yêu cầu "≥3 sweep không tháo-lắp", thỏa mãn bởi
  batch 10-run có sẵn (10≥3). → **Giữ nguyên quyết định dùng batch 10-run có sẵn cho B0-B**,
  không cần tạo protocol pilot 3-run riêng — nhưng ghi nhận rõ: đây là code MỚI, chưa chạy qua
  phần cứng thật lần nào, nên khuyến nghị vận hành (không phải yêu cầu firmware) là người dùng
  theo dõi sát vài run đầu của batch B đầu tiên, sẵn sàng dừng thủ công nếu có bất thường.

Các điểm sửa cụ thể:

- **[P1] Settle ban đầu (bước 1, lấy `initialAnchorUnwrapped`) cũng phải bắt buộc
  `== NL_SETTLE_OK`**, không chỉ loại trừ `ACQUISITION_ERROR` -- cùng lỗi đã sửa cho backoff/
  point0-settle ở REV 4 nhưng bỏ sót ở bước mới thêm này. Log riêng 3 kết quả:
  `ApproachInitialSettleResult`, `ApproachBackoffSettleResult`, `ApproachPoint0SettleResult`.
- **[P1] Chốt cách xử lý lỗi settle** (xem xác minh code ở trên): mọi lỗi settle B0-B (bước 1/3/5)
  đều `return MA600_RESULT_OK;` **ngay lập tức** kèm `out->measurementValid = false;
  out->capturedCount = 0; out->approachResult = NL_APPROACH_SETTLE_FAILED;` (enum LOCAL mới,
  chỉ để ghi log lý do -- không đụng `MA600_Result_t`) -- bỏ qua hoàn toàn phần capture/sweep
  phía sau, không để dòng 2448 ghi đè.
- **[P1] Đường thành công thiếu gán biến cho code cũ dùng lại**: sau `point0Settle` thành công,
  phải gán `sample = point0Settle.finalSample; settleObservation = point0Settle; settleResult =
  point0SettleResult;` -- nếu không, đoạn code cũ ngay sau đó (dựng `out->rawAtOffset`,
  `out->motorOffset`, v.v. từ các biến `sample`/`settleObservation` dùng chung) sẽ dùng nhầm dữ
  liệu cũ/rỗng.
- **[P1] Counter approach phải tách khỏi `Ramp*`/`Settle*`/`Acq*` đóng băng của sweep chính**:
  thêm bộ đếm riêng (`approachBackoffRampAcq`, `approachForwardRampAcq`, `approachSettleAcq` --
  gộp cả 3 lần settle B0-B), snapshot/cộng dồn quanh từng lời gọi đúng pattern có sẵn, rồi **trừ
  thêm** các bộ đếm này ra khỏi công thức `Acq* = context − ramp − settle` hiện có
  (`nonlinear_test.c:2274-2282`) để giữ nguyên đúng ý nghĩa `Acq*` đã đóng băng ở schema v5 --
  không được để các lần đọc của approach lẫn vào đó.
- **[P1] `RampCommandToTarget` cần trả thêm số bước thực tế đã chạy** (tham số out `uint32_t
  *stepsExecuted`, tách biệt khỏi việc đếm acquisition) để tính được `ApproachStepCountValid`
  (so với 32 bước kỳ vọng) -- REV 4 khai báo field này nhưng chưa có chỗ nào tính ra giá trị.
  `ApproachDirectionValid`/`ApproachStepCountValid`/cả 3 settle `OK` gộp thành 1 cờ
  `ApproachStructuralValid` -- cờ này MỚI thực sự gate được việc đưa run vào so sánh closure.
- **[P1 quan trọng] Direction check một mình chưa đủ chứng minh đã di chuyển ~256 raw**: rotor
  chỉ cần lệch `+1 raw` do nhiễu cũng qua được `approachObservedDeltaRaw > 0` dù chưa hề di
  chuyển đáng kể. → **Batch phần cứng B0-B đầu tiên phải được coi là calibration/pilot**, không
  phải kết luận cuối: mục đích chính là thu thập phân bố `ApproachObservedDeltaRaw`/
  `ApproachTargetErrorRaw`/`ApproachReturnErrorRaw` để CHỐT ngưỡng motion thật cho version sau
  (`_V2`), không phải để tuyên bố "B0-B đã pass" ngay cả khi closure 10/10 đẹp -- xem lại mục
  "Tiêu chí đánh giá" đã sửa bên dưới. Thêm diagnostic tương tự cho cả **đoạn chuẩn bị** (lùi):
  `BackoffObservedDeltaRaw`, `BackoffTargetErrorRaw`, `BackoffDirectionValid`.
- **[P1] Hợp nhất logging contract, tách record riêng cho diagnostic chi tiết**: `META` (và
  `SHADOW_RESULT`) LUÔN in `ApproachProtocol` (protocol A in `DITHER_V1`, không phải field vắng
  mặt) + `ApproachStructuralValid` (tóm tắt) -- KHÔNG nhét toàn bộ field chi tiết vào đó (đã xác
  nhận hết chỗ, xem mục kiểm tra ở trên). Mọi field diagnostic chi tiết
  (`Approach*ObservedDeltaRaw`, `Approach*TargetErrorRaw`, `ApproachReturnErrorRaw`, từng
  `Approach*SettleResult`, `ApproachMotionQualification`...) chuyển sang **record mới
  `APPROACH_RESULT,...`** (đúng pattern `CLOSURE_PROBE_RESULT` đã có -- record riêng, `Official=0`,
  không official-gating). Field `int64_t` dùng `FormatI64()` có sẵn, không dùng `%ld`.

## Đã sửa theo audit vòng 3 (REV 3 vẫn bị "Request changes")

- **[P0 NGHIÊM TRỌNG] Trộn tọa độ encoder (`unwrappedRaw`) với tọa độ lệnh motor.** REV 3 gán
  `approachPos = (int32_t)approachSample.unwrappedRaw` (giá trị encoder tuyệt đối/cộng dồn, có
  thể là số lớn bất kỳ tùy lịch sử quay) rồi truyền thẳng biến đó vào
  `Motor_SetElectricalPos((uint16_t)*pos, 1.0f)` -- trong khi **code hiện tại** (`pos` trong
  vòng ramp điểm-tới-điểm gốc) là tọa độ **lệnh motor tương đối, bắt đầu từ 0** ngay sau dither
  (`LockStartPosition()` kết thúc bằng `Motor_SetElectricalPos(0, 1.0f)`), hoàn toàn khác miền
  với `unwrappedRaw`. Nếu không sửa, lệnh đầu tiên sẽ nhảy tới gần giá trị encoder tuyệt đối
  (vd ~62500) thay vì `-8` -- có thể gây bước điện lớn/giật motor, phá hỏng thí nghiệm và có thể
  nguy hiểm. → **Tách hẳn 2 miền**: `commandPos` (int32_t, miền lệnh motor, luôn bắt đầu từ 0,
  CHỈ dùng để truyền vào `Motor_SetElectricalPos()`) và các biến `*Unwrapped` (int64_t, miền
  encoder, CHỈ dùng làm `expectedTargetUnwrapped` cho `WaitForPointSettle()` và tính diagnostic)
  -- không bao giờ gán chéo giữa 2 miền. Xem code sửa lại ở mục 3.
- **[P1] `NL_SETTLE_TIMEOUT`/`NL_SETTLE_WRONG_POSITION` bị bỏ qua, vẫn cho xác lập origin.** REV 3
  chỉ chặn khi `== NL_SETTLE_ACQUISITION_ERROR`, các kết quả settle khác (timeout, sai vị trí)
  vẫn rơi xuống dùng `finalSample` làm anchor/origin. Vì origin này là tham chiếu cho TOÀN BỘ
  256 điểm sau đó (không như 1 điểm lẻ trong sweep, nơi "capture nhưng đánh dấu invalid" là chấp
  nhận được), 1 origin sai sẽ làm hỏng cả sweep. → Với 2 lời gọi `WaitForPointSettle()` MỚI của
  B0-B (backoff-settle, point0-settle), bắt buộc `== NL_SETTLE_OK` mới được tiếp tục; bất kỳ kết
  quả nào khác đều coi là approach thất bại, không gán origin, không chạy tiếp sweep. **Không**
  đổi ngưỡng chặn của settle vô-mục-tiêu gốc (protocol A) -- giữ nguyên hành vi đã có.
- **[P1] Helper khai báo tham số counter nhưng không dùng, mô tả sai hành vi.** → Bỏ tham số
  counter khỏi helper, quay về đúng pattern **caller tự snapshot/cộng dồn** đã có sẵn trong code
  gốc (`SnapshotAcquisitionCounters` trước vòng ramp, `AccumulateCounterDelta` sau) -- áp dụng
  giống hệt cho cả lời gọi ramp cũ (điểm-tới-điểm) lẫn 2 lời gọi ramp mới của B0-B, không phát
  minh contract khác.
- **[P1] Cần tách rõ phần "gate được ngay" khỏi phần "chưa hiệu chỉnh".** Một số kiểm tra không
  cần số hiệu chỉnh vẫn gate được ngay (đúng chiều CW, đủ đúng 32 lệnh ramp, cả 2 settle đều OK,
  0 lỗi acquisition/jump/context) -- các điều kiện này PHẢI gate thật, không chờ hiệu chỉnh. Chỉ
  riêng ngưỡng biên độ tuyệt đối của `ApproachTargetErrorRaw` là chưa hiệu chỉnh. → Đổi
  `ApproachMotionValid=0` (ngụ ý "đã kiểm tra và fail") thành `ApproachMotionQualification=
  UNCALIBRATED`/`ApproachMotionValid=NA` (ngụ ý đúng "chưa đủ dữ liệu để kết luận"), tách bạch
  khỏi các gate cấu trúc đã liệt kê ở trên (những gate đó dùng field riêng, gate thật ngay từ
  đầu).
- **[Bổ sung theo góp ý]**: thêm 1 lần settle vô-mục-tiêu TRƯỚC khi bắt đầu backoff (để có
  `initialAnchorUnwrapped` ổn định làm mốc), và thêm field chẩn đoán
  `ApproachReturnErrorRaw = finalPoint0Unwrapped − initialAnchorUnwrapped` -- kiểm tra sau cả
  chu trình `0 → −256 → 0`, rotor có thực sự quay lại đúng vị trí cơ học ban đầu hay không.

## Đã sửa theo audit vòng 2 (REV 2 vẫn bị "Request changes")

REV 2 đã sửa đúng các điểm P0/P1/P2 của audit vòng 1 (giữ dither cho cả 2 protocol, backoff =
`NL_POS_INCREASE`, approach chạy trong `CaptureSweep()` dùng chung context, helper trả
`MA600_Result_t`, batch 10-run có sẵn...). Audit vòng 2 chỉ ra **3 điểm mới REV 2 chưa xử lý**,
đều là lỗi thuật toán thật, không phải lặp lại góp ý cũ:

- **[P0 MỚI] `WaitForPointSettle()` không đủ để chứng minh rotor đã di chuyển đúng 256 raw.**
  `NL_SETTLE_TARGET_TOLERANCE_RAW=910` (~5°) LỚN HƠN khoảng cách approach cần kiểm chứng (256
  raw ≈ 1.4°) — nghĩa là nếu rotor đứng yên hoàn toàn tại vị trí backoff (không ramp được, ví dụ
  do kẹt cơ khí), sai số so với target 0 vẫn chỉ 256 raw, **vẫn nằm trong dung sai 910 và settle
  check vẫn báo OK**. Không thể dùng riêng `WaitForPointSettle()` để khẳng định "đã tiếp cận từ
  đúng khoảng cách 256 raw". → Thêm kiểm tra chuyển vị riêng: `ApproachObservedDeltaRaw =
  finalUnwrapped − backoffAnchorUnwrapped`, so với `ApproachExpectedDeltaRaw =
  NL_B0B_APPROACH_BACKOFF_RAW`, tính `ApproachTargetErrorRaw` và `ApproachDirectionValid`
  (đúng chiều CW) — tách hẳn thành field/khái niệm **`ApproachMotionValid`**, KHÁC với
  `SettleValid` (chỉ nói "đứng yên") và `ClosureValid` (point 256 vs point 0). Ngưỡng chấp nhận
  cho `ApproachMotionValid` **chưa được hiệu chỉnh** — cần dữ liệu chuyển động point-to-point
  thật hoặc noise từ B0-A hold-probe để định nghĩa, không đoán số. Cho đến khi có ngưỡng đó,
  field này chỉ là **chẩn đoán quan sát**, KHÔNG được dùng để tuyên bố "mechanically equivalent"
  đã được chứng minh.
- **[P0 MỚI] Origin phải xác lập bằng settle CÓ mục tiêu tường minh sau approach, không dùng lại
  settle vô-mục-tiêu (`targetRequired=false`) của code hiện tại.** REV 2 để đoạn xác lập origin
  hiện có (dòng 1977-2021, vốn dùng `targetRequired=false` vì trước giờ không có mục tiêu cơ học
  cụ thể cho điểm 0) chạy nguyên xi sau bước approach — nhưng như vậy origin mới KHÔNG xác nhận
  được rotor có thực sự dừng đúng chỗ đã tính hay không. → Với protocol B, bước settle cuối
  (xác lập điểm 0) phải dùng `targetRequired=true` với mục tiêu tường minh
  `expectedPoint0Unwrapped = backoffAnchorUnwrapped + NL_B0B_APPROACH_BACKOFF_RAW`, và
  `sweepOriginUnwrapped` chỉ được gán từ kết quả settle CÓ mục tiêu này — không dùng lại lời gọi
  settle vô-mục-tiêu của protocol A.
- **[P1 MỚI] Ramp helper nên tự suy ra chiều từ `target − current`** thay vì cần tham số hướng
  riêng — vừa đơn giản hơn (dùng 1 vòng lặp thay vì 2 nhánh CW/CCW như code gốc), vừa tổng quát
  cho cả 2 đoạn ramp mới (lùi có thể CCW, tiến lại bắt buộc CW) mà không cần logic phân nhánh
  thêm. Vẫn giữ nguyên step size/delay/acquire-mỗi-bước, chỉ đổi cách xác định dấu bước.
- **[Ghi nhận, không bắt buộc sửa ngay]**: dwell/lịch sử tại vị trí backoff hiện chỉ có 1 lần
  settle ngắn, chưa mô phỏng đúng việc điểm 255 đã "ở yên" một khoảng thời gian xác định (settle
  + các cửa sổ acquisition) trước khi ramp sang 256. Đây là khác biệt còn sót lại, ghi nhận rõ
  trong tài liệu thay vì bỏ qua — chỉ cần xử lý ở vòng sau nếu local-ramp tối thiểu không đủ cải
  thiện closure (đúng như tài liệu B0-B tự đặt ra: thử phương án ít xâm lấn nhất trước).

## Đã sửa theo audit vòng 1 (giữ nguyên từ REV 2, không lặp lại chi tiết)

Bản draft đầu bị chỉ ra 4 lỗi P0/P1 nghiêm trọng + nhiều P1/P2 khác. Bám sát toàn bộ góp ý,
không giữ lại phần nào đã bị chỉ ra sai:

- **[P0] Backoff sai khoảng cách**: `6×8=48 raw` không tương đương đoạn tiếp cận điểm 256 thật
  (`256 raw = 32 bước`). → Đổi thành `NL_B0B_APPROACH_BACKOFF_RAW = NL_POS_INCREASE` (256 raw,
  đúng 32 bước `NL_RAMP_STEP`), có `#error` kiểm tra chia hết.
- **[P0] Sai acquisition context**: hàm tiếp cận mới không thể đứng ngoài `CaptureSweep()` vì
  `WaitForPointSettle()` bắt buộc dùng chung `sweepAcquisition` (context liên tục xuyên suốt
  ramp→settle→capture, đã xác nhận qua `nonlinear_test.c:1205-1209`). → Chuyển toàn bộ logic
  B0-B vào **bên trong** `CaptureSweep()`, ngay trước đoạn xác lập `sweepOriginUnwrapped`
  (`nonlinear_test.c:1974-2021`), dùng đúng context đó.
- **[P0] Bỏ qua lỗi acquisition/settle**: hàm cũ khai báo `void`, không xử lý kết quả. → Ramp
  helper trả `MA600_Result_t`; mọi lỗi (ramp hoặc settle) trả về sớm theo đúng pattern đã có sẵn
  ở đầu `CaptureSweep()` (`nonlinear_test.c:1979-1988`, `1999-2014`), không nuốt lỗi.
- **[P1] Confound 2 biến cùng lúc**: bản trước thay dither bằng approach mới — không cô lập được
  nguyên nhân nếu closure đổi. → **Giữ nguyên `LockStartPosition()` (dither) cho cả 2 protocol**,
  B0-B chỉ **thêm** đoạn tiếp cận CW cục bộ NGAY SAU dither, trước khi xác lập origin. Đổi tên
  protocol cho đúng bản chất: `DITHER_V1` (baseline, không đổi) vs
  `DITHER_PLUS_CW_LOCAL_APPROACH_V1` (thêm bước).
- **[P1] "Lùi thô 1 bước" tạo yếu tố cơ học không kiểm soát**: → Đoạn chuẩn bị lùi (`0→-256`)
  cũng phải ramp mượt (dùng cùng helper, có thể chiều CCW) + settle tại đó, KHÔNG nhảy 1 bước.
- **[P1] Batch 3-run không build được**: `NL_PRECONDITION_PROTOCOL_ID="ONE_FULL_SWEEP_120S_V1"`
  có `#error` khóa cứng `NL_BATCH_RUN_COUNT==10U` (`nonlinear_test.c:419-422`). → **Dùng nguyên
  batch 10-run có sẵn, không đổi gì ở guard này** — thỏa mãn "≥3 sweep" với dư, không cần
  protocol pilot riêng, không âm thầm bỏ gate.
- **[P1] Mô tả sai vai trò settle**: `WaitForPointSettle()` chỉ xác nhận ổn định + trong khoảng
  ~5° (910 raw) mục tiêu — không phải cơ chế đưa closure về 0.20°. → Sửa lại mô tả: B0-B chuẩn
  hóa hướng/lịch sử tiếp cận; closure được ĐO sau đó để kiểm định giả thuyết, không phải "đạt
  được" bởi bước settle.
- **[P1] Tiêu chí quyết định mơ hồ**: → Thêm rule định lượng cụ thể (mục "Tiêu chí đánh giá" bên
  dưới).
- **[P2] A→B bị confound thời gian/nhiệt**: → Đổi quy trình phần cứng thành **A→B→A** (không chỉ
  A→B), không tháo motor/đổi dây/đổi jig, ghi `ThermalState=UNMEASURED` (không có cảm biến nhiệt,
  không được ngụ ý đã kiểm soát nhiệt).
- **[P2] `ApproachProtocol` một mình chưa đủ audit**: → Thêm đủ field liệt kê bên dưới, xuất hiện
  ở cả `META` lẫn record liên quan.
- **[P2] Thiếu test/fixture/regression**: → Mở rộng phạm vi file bị ảnh hưởng, thêm contract
  test + fixture theo đúng pattern đã có (`scripts/test_phase3b0_closure_probe_contract.ps1` +
  `scripts/fixtures/schema-v5-phase3b0-closure-probe-p05-jig3.txt` dùng làm mẫu).

## Context

Theo đúng tài liệu đã có sẵn trong repo (`docs/phase3b0-closure-measurement-review.md`,
`docs/controller-state-synchronization-checklist.md`, `docs/ma600-canonical-pipeline-
improvement-plan.md`) — **không tự nghĩ ra thiết kế mới**, bám sát nguyên văn:

> "Stage B0-B — Equivalent approach experiment. Purpose: isolate friction/cogging/hysteresis
> caused by unequal point-0 and point-256 approach histories. Compare the existing dither-start
> protocol with an engineering protocol that approaches both reference states from the same
> direction and with the same ramp profile. Do not mix both protocols in one batch. Each
> protocol requires its own ID and at least three no-remount sweeps. Test the least invasive
> same-direction local approach first. If it does not produce a stable periodic state, evaluate
> a separately versioned full pre-roll/fly-in revolution."
> (`phase3b0-closure-measurement-review.md:409-422`)

Đã xác nhận qua code hiện tại đúng là bất đối xứng như tài liệu mô tả:
- **Điểm 0** hiện đến từ: PID home (`MoveToZeroAndCheckDirection`, hướng bất kỳ tùy vị trí trước
  đó) rồi `LockStartPosition()` — dither hở vòng đối xứng ±20→±1 quanh electrical-0
  (`nonlinear_test.c:1102-1114`), **không có hướng tiếp cận nhất quán**.
- **Điểm 256** (và mọi điểm khác trong sweep) đến từ: ramp hở vòng **chỉ 1 chiều** (CW), bước
  `NL_RAMP_STEP=8` mỗi lần, nằm trong vòng lặp chính của `CaptureSweep()`
  (`nonlinear_test.c:2186-2230`).

Đây chính là nguồn gốc "approach-history asymmetry" mà tài liệu chỉ ra là nguyên nhân khả dĩ của
closure bias hiện tại (~0.82°, gấp ~4 lần giới hạn pilot 0.20°).

**Ràng buộc bắt buộc phải giữ, theo đúng "pre-code decisions" đóng băng cho toàn bộ pha 3B0**
(`phase3b0-closure-measurement-review.md:289-308`, người dùng cũng nhắc lại trực tiếp — không
tiếp tục tuning PID):
1. Không đổi gain PID, không đổi `NL_RAMP_STEP`, không đổi filter/pole/closure-limit
   (`NL_SHADOW_CLOSURE_LIMIT_DEG=0.20f`) — chỉ đổi **cách tiếp cận cơ học** tới điểm 0, dùng lại
   nguyên xi ramp step/delay đã có.
2. Không đổi công thức RESULT/legacy math, không promote schema v6.
3. Không mix 2 protocol trong cùng 1 batch — mỗi protocol phải có ID riêng và ≥3 sweep không
   tháo–lắp — thỏa mãn tự nhiên vì đây là compile-time flag (đúng pattern `ENABLE_*` đã dùng
   xuyên suốt file này), và `NL_TEST_REPEAT_3_RUNS` (đã có sẵn) chính là cơ chế "≥3 sweep
   không tháo-lắp" — không cần state machine mới.
4. Không gán ý nghĩa official mới cho `ClosureValid`/`MeasurementValid`/`Motor OK` — số liệu vẫn
   tính bằng đúng công thức cũ, chỉ khác input cơ học, gắn thêm field chẩn đoán để phân biệt.
5. Chỉ làm "same-direction local approach" (ít xâm lấn nhất) lần này — **không** làm pre-roll/
   fly-in (đổi nhiệt/motor-on-time, tài liệu yêu cầu phải là thay đổi tách biệt, phiên bản
   riêng, chỉ làm nếu local-approach không đủ).

## Trình tự thực thi (REV 6, khớp code ở mục "Việc sẽ làm" bên dưới)

```text
CHUNG cho cả A và B:
  Home (MoveToZeroAndCheckDirection -- PID, không đổi)
  → LockStartPosition() dither cũ -- KHÔNG đổi, chạy cho cả 2 protocol
  → CaptureSweep() bắt đầu, MA600_AcquisitionInit(&sweepAcquisition)

PROTOCOL A -- DITHER_V1 (mặc định, KHÔNG đổi 1 dòng code nào so với hiện tại):
  → acquire mẫu, settle vô-mục-tiêu (targetRequired=false, dòng 1977-2021 hiện có)
  → sweepOriginUnwrapped = mẫu đã settle
  → capture point 0, sweep point 1..256 như hiện tại

PROTOCOL B -- DITHER_PLUS_CW_LOCAL_APPROACH_V1 (chỉ khi bật flag, KHÔNG đồng thời với
ENABLE_CCW_ENGINEERING_TEST; commandPos = miền lệnh motor bắt đầu từ 0, tách biệt hoàn toàn với
các biến *Unwrapped = miền encoder):
  0. Acquire riêng đứng đầu -- mirror đúng cấu trúc protocol A (không bọc snapshot, tính vào
     "context" giống A, giữ Acq* 2 protocol so sánh được).
  1. Settle vô-mục-tiêu (targetRequired=false, giống protocol A) → initialAnchorUnwrapped (chỉ
     để có mốc ổn định, KHÔNG phải origin cuối). BẮT BUỘC == NL_SETTLE_OK; tách 2 loại lỗi:
     `ACQUISITION_ERROR` (lỗi sensor thật) → propagate mã lỗi thật; lỗi khác (timeout) → thất
     bại mềm, return `MA600_RESULT_OK` kèm `measurementValid=false`. Cả 2 nhánh đều tự tính lại
     `contextAcquisition`/`Acq*` mở rộng qua `FinalizeApproachEarlyExit()` trước khi return
     (không dùng `goto capture_complete` -- nhãn đó nằm sau các khai báo `pos`/`pointIndex` chưa
     khởi tạo tại điểm này, xem "Đã sửa theo audit vòng 5").
  2. Ramp CHUẨN BỊ: commandPos 0 → −256 (miền lệnh, chiều tự suy CCW). Đếm bước thực tế.
  3. Settle CÓ mục tiêu tại initialAnchorUnwrapped−256 (targetRequired=true, BẮT BUỘC
     NL_SETTLE_OK, cùng cách tách lỗi ở bước 1) → backoffAnchorUnwrapped. Counter của bước 1+3
     tính vào `approachSettleAcquisition` (trừ khỏi `Acq*`).
  4. Ramp SO SÁNH: commandPos −256 → 0 (miền lệnh, CW bắt buộc vì target>current), đúng 32 bước
     NL_RAMP_STEP -- cùng chiều/bước/delay như đoạn point255→256 thật.
  5. Settle CÓ mục tiêu tường minh tại backoffAnchorUnwrapped+256 (targetRequired=true, BẮT BUỘC
     NL_SETTLE_OK, cùng cách tách lỗi). Đây CHÍNH LÀ settle điểm 0 -- counter tính vào
     `out->settleAcquisition` CHÍNH (giống protocol A), KHÔNG vào `approachSettleAcquisition`
     (giữ `SettlePoints`/`SettleReadAttempts` nhất quán giữa 2 protocol); có thêm 1 bản copy
     CHẨN ĐOÁN riêng (không trừ `Acq*`) để tính `ApproachAcquisitionClean`.
  6. sweepOriginUnwrapped = mẫu đã settle bước 5. Tính `ApproachDirectionValid`/
     `ApproachStepCountValid`/`ApproachAcquisitionClean` (GATE THẬT, gộp thành
     `ApproachStructuralValid`) + `ApproachTargetErrorRaw`/`ApproachReturnErrorRaw`/
     `ApproachMotionQualification=UNCALIBRATED` (CHỈ chẩn đoán -- xem "Tiêu chí đánh giá").
  → capture point 0, sweep point 1..256 KHÔNG đổi

  → point 256 (cả 2 protocol): ramp CW 256 raw/32 bước như hiện tại, KHÔNG đổi -- ĐÂY LÀ ĐOẠN
    B0-B ĐANG KIỂM ĐỊNH GIẢ THUYẾT (so với cách điểm 0 vừa được tiếp cận ở protocol B)
```

Chỉ 1 biến duy nhất thay đổi giữa 2 protocol: có/không có đoạn lùi-rồi-ramp-CW-vào-lại (với
settle có mục tiêu tường minh) trước khi điểm 0 được xác lập. Dither, PID home, sweep chính,
point 256, mọi công thức math đều giữ nguyên cho cả 2 protocol.

## Việc sẽ làm

### 1. `Core/Src/nonlinear_test.c` — tách ramp loop thành helper tự suy chiều, trả lỗi đúng cách

Vòng lặp ramp micro-step hiện tại (`nonlinear_test.c:2194-2239`, hiện có 2 nhánh CW/CCW riêng,
bước `NL_RAMP_STEP=8`, delay `NL_RAMP_STEP_DELAY_MS`, acquire mẫu mỗi bước, cộng dồn vào
`out->rampAcquisition`) tách thành 1 hàm dùng chung, tự xác định dấu bước từ `target − current`
(gộp 2 nhánh CW/CCW cũ thành 1 vòng lặp, theo đúng góp ý audit):

```c
/* pos: MIỀN LỆNH MOTOR (tương đối, truyền thẳng vào Motor_SetElectricalPos) -- KHÔNG phải
 * unwrappedRaw của encoder. Caller tự snapshot/cộng dồn counter quanh lời gọi này, đúng pattern
 * SnapshotAcquisitionCounters/AccumulateCounterDelta đã có sẵn (không nhận tham số counter).
 * stepsExecuted: out-param riêng biệt (đếm số lệnh ramp thực tế, KHÔNG phải acquisition
 * counter) -- cho phép caller B0-B kiểm chứng đúng 32 bước đã chạy; NULL nếu caller không cần
 * (call site sweep chính hiện tại truyền NULL, hành vi không đổi). */
static MA600_Result_t RampCommandToTarget(
    MA600_AcquisitionContext_t *sweepAcquisition, int32_t *pos, int32_t targetPos,
    uint32_t *stepsExecuted)
{
    int32_t step = (targetPos >= *pos) ? NL_RAMP_STEP : -NL_RAMP_STEP;
    uint32_t steps = 0;
    while (*pos != targetPos)
    {
        *pos += step;
        if ((step > 0 && *pos > targetPos) || (step < 0 && *pos < targetPos))
        {
            *pos = targetPos;   /* không overshoot -- kẹp đúng target ở bước cuối */
        }
        Motor_SetElectricalPos((uint16_t)*pos, 1.0f);   /* cast sang uint16_t CHỈ ở đây */
        osDelay(NL_RAMP_STEP_DELAY_MS);
        MA600_Sample_t rampSample;
        MA600_Result_t r = MA600_AcquireSample(sweepAcquisition,
            NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &rampSample);
        steps++;
        if (r != MA600_RESULT_OK)
        {
            if (stepsExecuted != NULL) { *stepsExecuted = steps; }
            return r;   /* lỗi trả về ngay, không nuốt */
        }
    }
    if (stepsExecuted != NULL) { *stepsExecuted = steps; }
    return MA600_RESULT_OK;
}
```

Giữ **nguyên xi** hằng số/hành vi bước (cùng `NL_RAMP_STEP`, cùng delay, cùng acquire/step) --
chỉ gộp 2 nhánh CW/CCW cũ thành 1 vòng lặp và đổi vị trí code. `CaptureSweep()`'s ramp
điểm-tới-điểm hiện tại (không đổi hành vi output) gọi hàm này thay vì code inline; caller ở mọi
vị trí gọi (kể cả code cũ) tự `SnapshotAcquisitionCounters` trước / `AccumulateCounterDelta` sau
quanh lời gọi -- đúng pattern đã có, không phát minh contract counter khác trong helper.

### 2. Flag + hằng số mới, mặc định TẮT

```c
#ifndef ENABLE_B0B_EQUAL_APPROACH
#define ENABLE_B0B_EQUAL_APPROACH   0
#endif
#if ENABLE_B0B_EQUAL_APPROACH
/* Khoảng lùi trước điểm 0 PHẢI bằng đúng NL_POS_INCREASE để đoạn ramp-vào-lại (mục 3) có đúng
 * 32 bước NL_RAMP_STEP -- tương đương chính xác đoạn tiếp cận điểm 256 thật (256 raw / 32 bước),
 * không phải một con số ước lượng riêng. */
#define NL_B0B_APPROACH_BACKOFF_RAW   NL_POS_INCREASE
#if (NL_POS_INCREASE % NL_RAMP_STEP) != 0
#error "B0-B requires an integer number of NL_RAMP_STEP micro-steps"
#endif
#define NL_B0B_APPROACH_PROTOCOL_ID   "DITHER_PLUS_CW_LOCAL_APPROACH_V1"
/* B0-B (mục 3) hard-code "lùi CCW / tiến CW" -- đúng "cùng chiều với sweep chính" CHỈ khi sweep
 * đó là CW. ENABLE_CCW_ENGINEERING_TEST (nonlinear_test.c:333-340) cho phép sweep chạy CCW --
 * kết hợp 2 flag sẽ âm thầm phá vỡ đúng giả thuyết "equal approach" mà B0-B định kiểm chứng.
 * Chưa tổng quát hóa chiều tiếp cận theo `direction` (thêm rủi ro không cần thiết cho phạm vi
 * lần này, giả thuyết đang kiểm định chỉ nhắm sweep CW mặc định) -- cấm kết hợp thay vì đoán. */
#if ENABLE_CCW_ENGINEERING_TEST
#error "B0-B equal-approach (CW-only) not yet validated against CCW engineering sweeps -- enable at most one of ENABLE_B0B_EQUAL_APPROACH / ENABLE_CCW_ENGINEERING_TEST"
#endif
#else
#define NL_B0B_APPROACH_PROTOCOL_ID   "DITHER_V1"
#endif
```

### 3. Đoạn tiếp cận B0-B bên TRONG `CaptureSweep()`, dùng đúng `sweepAcquisition`

Chèn ngay sau `MA600_AcquisitionInit(&sweepAcquisition)` (`nonlinear_test.c:1975`), **THAY CHỖ**
đoạn xác lập origin hiện có (`:1977-2021`) khi bật flag -- protocol A vẫn dùng nguyên code cũ đó
không đổi; protocol B dùng đường riêng, chỉ gán `sweepOriginUnwrapped` sau settle CÓ mục tiêu.

**Trước `#if`, khai báo UNCONDITIONAL** (đúng như code gốc đã khai báo `sample`/
`acquisitionResult` ở dòng 1976-1977 -- 2 nhánh chỉ GÁN giá trị, không khai báo lại, vì sweep
loop phía sau `#endif` dùng lại các biến này bất kể protocol nào):

```c
    MA600_AcquisitionContext_t sweepAcquisition;
    MA600_AcquisitionInit(&sweepAcquisition);
    MA600_Sample_t sample;
    MA600_Result_t acquisitionResult;
    NlSettleObservation_t settleObservation;
    NlSettleResult_t settleResult;
```

**Helper dùng chung cho MỌI nhánh lỗi B0-B** (tránh lặp lại 5 lần / quên 1 trong 5 chỗ -- đúng
lỗi REV 5 đã mắc; theo đúng phong cách hàm nhỏ đã có sẵn trong file như
`SnapshotAcquisitionCounters`/`AccumulateCounterDelta`):

```c
/* Gọi ở MỌI early-return lỗi B0-B, TRƯỚC khi return. Không tự set out->acquisitionResult (mỗi
 * call site tự quyết định giá trị đó tùy loại lỗi -- xem 2 nhánh ACQUISITION_ERROR/soft-fail
 * dưới đây), chỉ lo phần chung: measurementValid/capturedCount/Acq* mở rộng. */
static void FinalizeApproachEarlyExit(NlSweepCapture_t *out,
    MA600_AcquisitionContext_t *sweepAcquisition)
{
    out->measurementValid = false;
    out->capturedCount = 0;
    out->contextAcquisition = SnapshotAcquisitionCounters(sweepAcquisition);
    out->acquisitionReadAttempts = out->contextAcquisition.readAttempts
        - out->settleAcquisition.readAttempts - out->approachSettleAcquisition.readAttempts
        - out->approachBackoffRampAcquisition.readAttempts
        - out->approachForwardRampAcquisition.readAttempts;
    /* ...lặp lại tương tự cho retryCount/transportErrorCount/jumpRejectCount/failedSampleCount,
     * đúng công thức mở rộng đã nêu ở mục 4 (out->rampAcquisition luôn 0 ở giai đoạn approach,
     * chưa vào sweep loop chính -- vẫn trừ cho tổng quát/an toàn nếu code sau này đổi thứ tự). */
}
```

```c
#if ENABLE_B0B_EQUAL_APPROACH
    /* commandPos: MIỀN LỆNH MOTOR, bắt đầu từ 0. Mọi biến *Unwrapped là MIỀN ENCODER, không bao
     * giờ gán chéo 2 miền (lỗi P0 đã sửa ở REV 4). */
    int32_t commandPos = 0;

    /* 0. Acquire riêng đứng đầu -- mirror ĐÚNG cấu trúc protocol A (dòng 1977, không bọc
     * snapshot, nghiễm nhiên tính vào "context" giống hệt A) để Acq* của 2 protocol còn so
     * sánh được với nhau theo cùng 1 ý nghĩa. */
    SetEngineState(NL_ENGINE_ACQUIRE);
    acquisitionResult = MA600_AcquireSample(&sweepAcquisition,
        NL_SWEEP_MAX_JUMP_RAW, NL_ACQ_MAX_ATTEMPTS, &sample);
    if (acquisitionResult != MA600_RESULT_OK)
    {
        out->acquisitionResult = acquisitionResult;
        out->approachResult = NL_APPROACH_ACQUISITION_ERROR;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        return acquisitionResult;
    }

    /* 1. Settle vô-mục-tiêu TRƯỚC backoff -- lấy initialAnchorUnwrapped ổn định làm mốc. BẮT
     * BUỘC == NL_SETTLE_OK. Tách 2 loại lỗi (khác REV 5 -- REV 5 hạ mọi lỗi settle thành
     * MA600_RESULT_OK, kể cả ACQUISITION_ERROR là lỗi sensor thật, làm mất lỗi thật đó):
     *   - == NL_SETTLE_ACQUISITION_ERROR: lỗi sensor thật -- propagate nguyên trạng.
     *   - != NL_SETTLE_OK khác (TIMEOUT; WRONG_POSITION không nên xảy ra vì targetRequired=
     *     false): "thất bại mềm" -- return MA600_RESULT_OK, measurementValid=false. */
    out->approachInitialAttempted = true;
    SetEngineState(NL_ENGINE_SETTLE);
    NlAcquisitionCounters_t settleBefore0 = SnapshotAcquisitionCounters(&sweepAcquisition);
    NlSettleObservation_t initialSettle;
    out->approachInitialSettleResult = WaitForPointSettle(&sweepAcquisition,
        sample.unwrappedRaw, false, &initialSettle);
    AccumulateCounterDelta(&sweepAcquisition, &settleBefore0, &out->approachSettleAcquisition);
    if (out->approachInitialSettleResult != NL_SETTLE_OK)
    {
        bool isAcqError = (out->approachInitialSettleResult == NL_SETTLE_ACQUISITION_ERROR);
        out->approachResult = isAcqError ? NL_APPROACH_ACQUISITION_ERROR
                                          : NL_APPROACH_INITIAL_SETTLE_FAILED;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        if (isAcqError)
        {
            out->acquisitionResult = initialSettle.acquisitionResult;
            return out->acquisitionResult;
        }
        return MA600_RESULT_OK;
    }
    int64_t initialAnchorUnwrapped = initialSettle.finalSample.unwrappedRaw;

    /* 2. Ramp CHUẨN BỊ: lệnh motor 0 -> -256 (miền lệnh). Đếm số bước thực tế để kiểm chứng. */
    SetEngineState(NL_ENGINE_RAMP);
    int32_t backoffCommand = 0 - NL_B0B_APPROACH_BACKOFF_RAW;
    NlAcquisitionCounters_t rampBefore = SnapshotAcquisitionCounters(&sweepAcquisition);
    uint32_t backoffStepsExecuted = 0;
    MA600_Result_t approachAcqResult = RampCommandToTarget(&sweepAcquisition, &commandPos,
        backoffCommand, &backoffStepsExecuted);
    AccumulateCounterDelta(&sweepAcquisition, &rampBefore, &out->approachBackoffRampAcquisition);
    out->approachBackoffStepsExecuted = backoffStepsExecuted;
    if (approachAcqResult != MA600_RESULT_OK)
    {
        out->acquisitionResult = approachAcqResult;
        out->approachResult = NL_APPROACH_ACQUISITION_ERROR;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        return approachAcqResult;
    }

    /* 3. Settle CÓ mục tiêu tại vị trí lùi -- BẮT BUỘC == NL_SETTLE_OK, cùng cách tách lỗi ở
     * bước 1. */
    out->approachBackoffAttempted = true;
    SetEngineState(NL_ENGINE_SETTLE);
    int64_t expectedBackoffUnwrapped = initialAnchorUnwrapped - NL_B0B_APPROACH_BACKOFF_RAW;
    NlAcquisitionCounters_t settleBefore1 = SnapshotAcquisitionCounters(&sweepAcquisition);
    NlSettleObservation_t backoffSettle;
    out->approachBackoffSettleResult = WaitForPointSettle(&sweepAcquisition,
        expectedBackoffUnwrapped, true, &backoffSettle);
    AccumulateCounterDelta(&sweepAcquisition, &settleBefore1, &out->approachSettleAcquisition);
    if (out->approachBackoffSettleResult != NL_SETTLE_OK)
    {
        bool isAcqError = (out->approachBackoffSettleResult == NL_SETTLE_ACQUISITION_ERROR);
        out->approachResult = isAcqError ? NL_APPROACH_ACQUISITION_ERROR
                                          : NL_APPROACH_BACKOFF_SETTLE_FAILED;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        if (isAcqError)
        {
            out->acquisitionResult = backoffSettle.acquisitionResult;
            return out->acquisitionResult;
        }
        return MA600_RESULT_OK;
    }
    int64_t backoffAnchorUnwrapped = backoffSettle.finalSample.unwrappedRaw;
    /* Chẩn đoán riêng cho ĐOẠN CHUẨN BỊ (không phải đoạn đang so sánh, nhưng vẫn đáng ghi lại). */
    out->backoffObservedDeltaRaw = backoffAnchorUnwrapped - initialAnchorUnwrapped;
    out->backoffTargetErrorRaw = out->backoffObservedDeltaRaw - (-NL_B0B_APPROACH_BACKOFF_RAW);
    bool backoffDirectionValid = out->backoffObservedDeltaRaw < 0;

    /* 4. ĐOẠN SO SÁNH: lệnh motor -256 -> 0 (CW bắt buộc). */
    SetEngineState(NL_ENGINE_RAMP);
    NlAcquisitionCounters_t rampBefore2 = SnapshotAcquisitionCounters(&sweepAcquisition);
    uint32_t forwardStepsExecuted = 0;
    approachAcqResult = RampCommandToTarget(&sweepAcquisition, &commandPos, 0,
        &forwardStepsExecuted);
    AccumulateCounterDelta(&sweepAcquisition, &rampBefore2, &out->approachForwardRampAcquisition);
    out->approachForwardStepsExecuted = forwardStepsExecuted;
    if (approachAcqResult != MA600_RESULT_OK)
    {
        out->acquisitionResult = approachAcqResult;
        out->approachResult = NL_APPROACH_ACQUISITION_ERROR;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        return approachAcqResult;
    }

    /* 5. Settle CÓ mục tiêu tường minh tại điểm 0 -- BẮT BUỘC == NL_SETTLE_OK. Đây CHÍNH LÀ
     * settle điểm 0, thay thế đúng vai trò settle điểm 0 của protocol A (dòng 1996) -- do đó
     * tính vào out->settleAcquisition CHÍNH (KHÔNG phải approachSettleAcquisition), giữ
     * SettlePoints/SettleReadAttempts nhất quán giữa 2 protocol (đúng lỗi review vòng 5 chỉ ra:
     * REV 5 nhét cả 3 settle vào approachSettleAcquisition, làm protocol B "thiếu" 1 settle
     * trong out->settleAcquisition so với protocol A dù cùng có đúng 1 settle điểm 0). Đồng
     * thời copy riêng delta này vào 1 field CHẨN ĐOÁN (không tham gia trừ Acq*, chỉ để tính
     * ApproachAcquisitionClean ở bước 6). */
    out->approachPoint0Attempted = true;
    SetEngineState(NL_ENGINE_SETTLE);
    int64_t expectedPoint0Unwrapped = backoffAnchorUnwrapped + NL_B0B_APPROACH_BACKOFF_RAW;
    NlAcquisitionCounters_t settleBefore2 = SnapshotAcquisitionCounters(&sweepAcquisition);
    NlSettleObservation_t point0Settle;
    out->approachPoint0SettleResult = WaitForPointSettle(&sweepAcquisition,
        expectedPoint0Unwrapped, true, &point0Settle);
    AccumulateCounterDelta(&sweepAcquisition, &settleBefore2, &out->settleAcquisition);
    AccumulateCounterDelta(&sweepAcquisition, &settleBefore2,
        &out->approachPoint0SettleAcquisitionDiag);   /* copy CHỈ để chẩn đoán, không trừ Acq* */
    if (out->approachPoint0SettleResult != NL_SETTLE_OK)
    {
        bool isAcqError = (out->approachPoint0SettleResult == NL_SETTLE_ACQUISITION_ERROR);
        out->approachResult = isAcqError ? NL_APPROACH_ACQUISITION_ERROR
                                          : NL_APPROACH_POINT0_SETTLE_FAILED;
        FinalizeApproachEarlyExit(out, &sweepAcquisition);
        if (isAcqError)
        {
            out->acquisitionResult = point0Settle.acquisitionResult;
            return out->acquisitionResult;
        }
        return MA600_RESULT_OK;
    }
    const int64_t sweepOriginUnwrapped = point0Settle.finalSample.unwrappedRaw;
    /* QUAN TRỌNG (lỗi REV 4 đã sửa): gán lại cho code cũ phía sau (dòng ~2016+, dựng
     * out->rawAtOffset/out->motorOffset...) dùng đúng kết quả settle của protocol B, không phải
     * biến rỗng/cũ. */
    sample = point0Settle.finalSample;
    settleObservation = point0Settle;
    settleResult = out->approachPoint0SettleResult;
    out->approachResult = NL_APPROACH_OK;

    /* 6. Chẩn đoán đoạn so sánh -- tách "gate được ngay" khỏi "chưa hiệu chỉnh":
     *    - direction/step-count/acquisition-clean: GATE THẬT (cấu trúc, không cần số hiệu
     *      chỉnh) -- gộp thành out->approachStructuralValid.
     *    - approachTargetErrorRaw/approachReturnErrorRaw: CHỈ chẩn đoán. approachDirectionValid
     *      (dấu >0) KHÔNG tự chứng minh đã di chuyển đủ ~256 raw -- lệch +1 raw do nhiễu cũng
     *      qua được điều kiện này. Batch phần cứng ĐẦU TIÊN của B0-B vì vậy phải coi là
     *      calibration/pilot (xem "Tiêu chí đánh giá"), không phải kết luận cuối. */
    out->approachObservedDeltaRaw = sweepOriginUnwrapped - backoffAnchorUnwrapped;
    out->approachTargetErrorRaw = out->approachObservedDeltaRaw - NL_B0B_APPROACH_BACKOFF_RAW;
    bool approachDirectionValid = out->approachObservedDeltaRaw > 0;
    bool approachStepCountValid = (forwardStepsExecuted == NL_B0B_APPROACH_BACKOFF_RAW / NL_RAMP_STEP)
        && (backoffStepsExecuted == NL_B0B_APPROACH_BACKOFF_RAW / NL_RAMP_STEP);
    /* ApproachAcquisitionClean: 0 retry/transport-error/jump-reject/failed-sample trên TOÀN BỘ
     * hoạt động approach (2 settle chuẩn bị + 2 ramp + settle điểm 0 qua bản copy chẩn đoán) --
     * không chỉ direction/step-count như REV 5. */
    bool approachAcquisitionClean =
        (out->approachSettleAcquisition.retryCount == 0)
        && (out->approachSettleAcquisition.transportErrorCount == 0)
        && (out->approachSettleAcquisition.jumpRejectCount == 0)
        && (out->approachSettleAcquisition.failedSampleCount == 0)
        && (out->approachBackoffRampAcquisition.retryCount == 0)
        && (out->approachBackoffRampAcquisition.transportErrorCount == 0)
        && (out->approachBackoffRampAcquisition.jumpRejectCount == 0)
        && (out->approachBackoffRampAcquisition.failedSampleCount == 0)
        && (out->approachForwardRampAcquisition.retryCount == 0)
        && (out->approachForwardRampAcquisition.transportErrorCount == 0)
        && (out->approachForwardRampAcquisition.jumpRejectCount == 0)
        && (out->approachForwardRampAcquisition.failedSampleCount == 0)
        && (out->approachPoint0SettleAcquisitionDiag.retryCount == 0)
        && (out->approachPoint0SettleAcquisitionDiag.transportErrorCount == 0)
        && (out->approachPoint0SettleAcquisitionDiag.jumpRejectCount == 0)
        && (out->approachPoint0SettleAcquisitionDiag.failedSampleCount == 0);
    out->approachAcquisitionClean = approachAcquisitionClean;
    out->approachStructuralValid = approachDirectionValid && approachStepCountValid
        && backoffDirectionValid && approachAcquisitionClean;
        /* 3 settle == OK đã đảm bảo ở trên (mới đi tới được đây). */
    /* Kiểm tra vòng kín: sau 0 -> -256 -> 0, rotor có quay lại đúng chỗ ban đầu không. */
    out->approachReturnErrorRaw = sweepOriginUnwrapped - initialAnchorUnwrapped;
#else
    /* Protocol A -- nguyên xi code hiện có (dòng 1977-2021), không đổi 1 dòng.
     * out->approachResult = NL_APPROACH_NOT_APPLICABLE (giá trị mặc định qua zero-init struct
     * -- KHÁC NL_APPROACH_OK=0 về mặt thiết kế enum, xem mục 4). */
#endif
```

**Không đổi**: `LockStartPosition()` (dither), `MoveToZeroAndCheckDirection()` (PID home), toàn
bộ sweep point 0..256, `NL_RAMP_STEP`, gain PID, closure limit, công thức RESULT/SHADOW_RESULT.

### 4. Field mới -- `META`/`SHADOW_RESULT` chỉ giữ tóm tắt, chi tiết chuyển sang record riêng

**Đã xác nhận bằng số liệu thật** (2 lần đo trên 2 log khác nhau ra 1733 và 1741 byte -- chênh
lệch do độ dài số khác nhau giữa các run, không phải sai số đo): dòng `META` hiện tại dài
**~1730-1740 byte**, buffer `LogLineLarge()` chỉ 1900 byte (`nonlinear_test.c:454`) -- chỉ còn
~160-170 byte dư, không đủ chỗ cho >10 field `Approach*` chi tiết. Nhét hết vào `META` sẽ bị
`vsnprintf` cắt âm thầm. → Tách làm 2 tầng, đúng pattern `CLOSURE_PROBE_RESULT` đã có. Test mới
(mục 6) tự đo độ dài dòng `META` thực tế lúc chạy và assert `< 1900`, không hard-code 1 con số
byte cụ thể (số đo thay đổi theo giá trị từng run).

**`META` và `SHADOW_RESULT` (LUÔN in, không có khái niệm "field vắng mặt")**: chỉ 2 field tóm
tắt -- `ApproachProtocol=%s` (protocol A in `"DITHER_V1"`, protocol B in
`NL_B0B_APPROACH_PROTOCOL_ID`, không bao giờ vắng mặt) và `ApproachStructuralValid=%s` (`"1"`/
`"0"`/`"NA"` -- `NA` khi protocol A vì khái niệm này không áp dụng). Đủ để log bị cắt giữa chừng
vẫn giữ được danh tính thí nghiệm.

**Record mới `APPROACH_RESULT,...` (1 dòng/run, chỉ khi `ENABLE_B0B_EQUAL_APPROACH=1`, `Official=0`
giống `CLOSURE_PROBE_RESULT`)**. Field định danh đi trước, **đúng mẫu `CLOSURE_PROBE_RESULT`
thật** (`nonlinear_test.c:2542-2555`, không chỉ liệt kê field nghiệp vụ như REV 5 đã làm):
```text
APPROACH_RESULT,SchemaVersion=%d,TestID=%lu,SweepID=%lu,JigID=%s,MotorID=%s,Direction=%s,
Official=0,Protocol=%s,Started=%d,Complete=%d,Status=%s,...(field nghiệp vụ bên dưới)...
```
`Status` = tên `NlApproachResult_t` hiện tại của `out->approachResult` (`OK`/
`INITIAL_SETTLE_FAILED`/`BACKOFF_SETTLE_FAILED`/`POINT0_SETTLE_FAILED`/`ACQUISITION_ERROR`).
`Complete=1` chỉ khi `Status=OK` (đã qua hết 5 bước); `Started=1` luôn (record chỉ tồn tại khi
flag bật, và bước 0 -- acquire riêng -- luôn là hành động đầu tiên).

**Field nghiệp vụ, với NA-khi-chưa-chạy-tới thay vì trông như "OK"** (lỗi REV 5: struct
zero-init khiến `NL_SETTLE_OK==0` đọc nhầm là "đã pass" cho giai đoạn chưa từng chạy) --
`NlSweepCapture_t` cần thêm 3 cờ `bool approachInitialAttempted/approachBackoffAttempted/
approachPoint0Attempted` (mặc định `false` qua zero-init, đúng ý nghĩa "chưa chạy"), dùng để in
`NA` thay vì giá trị enum khi `!Attempted`:
`ApproachBackoffRaw=%ld`, `ApproachRampStepRaw=%d`, `ApproachRampDelayMs=%d`,
`ApproachExpectedSteps=%d` (luôn in, không phụ thuộc Attempted -- hằng số biết trước),
`ApproachInitialSettleResult=%s` (NA nếu `!approachInitialAttempted`),
`ApproachBackoffSettleResult=%s` (NA nếu `!approachBackoffAttempted`),
`ApproachPoint0SettleResult=%s` (NA nếu `!approachPoint0Attempted`),
`ApproachBackoffStepsExecuted=%lu`, `ApproachForwardStepsExecuted=%lu`,
`ApproachStepCountValid=%d`, `ApproachDirectionValid=%d`, `ApproachAcquisitionClean=%d` (gate
mới -- xem mục 3 bước 6),
`BackoffObservedDeltaRaw=%s`/`BackoffTargetErrorRaw=%s`/`BackoffDirectionValid=%d` (đoạn chuẩn
bị), `ApproachObservedDeltaRaw=%s`/`ApproachTargetErrorRaw=%s`/`ApproachReturnErrorRaw=%s` (đoạn
so sánh + vòng kín) -- **mọi field `int64_t` dùng `FormatI64()` có sẵn** (`nonlinear_test.c:534`),
không dùng `%ld` (STM32 `long` 32-bit, sai kiểu cho `int64_t`). Cuối cùng:
`ApproachMotionQualification=UNCALIBRATED` (hằng chuỗi cố định lần này, không phải field tính
toán) -- đánh dấu rõ ngưỡng biên độ chưa được định nghĩa, để phân biệt với
`ApproachStructuralValid` (gate thật, có giá trị 0/1 thật).

Bộ đếm acquisition mới (`approachSettleAcquisition` -- CHỈ initial-anchor-settle + backoff-settle,
KHÔNG gồm settle điểm 0; `approachBackoffRampAcquisition`; `approachForwardRampAcquisition`;
`approachPoint0SettleAcquisitionDiag` -- bản copy CHẨN ĐOÁN riêng của settle điểm 0, không tham
gia trừ Acq*) trong `NlSweepCapture_t` được **trừ thêm** vào công thức `Acq*` đóng băng hiện có
(`nonlinear_test.c:2274-2282`, hiện là `context − ramp − settle`, mở rộng thành
`context − ramp − settle − approachSettle − approachBackoffRamp − approachForwardRamp`) --
**settle điểm 0 vẫn tính vào `out->settleAcquisition` CHÍNH như protocol A** (đã sửa ở REV 6,
xem mục 3 bước 5 -- KHÔNG trừ thêm lần nữa, `approachPoint0SettleAcquisitionDiag` chỉ để tính
`ApproachAcquisitionClean`) để giữ `SettlePoints`/`SettleReadAttempts` nhất quán giữa 2 protocol.

### 5. `scripts/analyze_nonlinear_logs.ps1` -- nhận diện field mới

Thêm `ApproachProtocol` (và các field `Approach*` khác) vào danh sách field được parse/export
(theo đúng pattern các field `Closure*`/`Shadow*` đã có) -- không thay đổi logic tính toán nào,
chỉ thêm khả năng đọc/export field mới để không bị bỏ sót khi phân tích log B0-B.

### 5b. `tools/plot_metric_trend.py` -- thêm 2 field tóm tắt vào whitelist `META`

**Đã xác nhận bằng cách đọc lại code thật** (`tools/plot_metric_trend.py:96-102`): `load_runs()`
chỉ đẩy vào `rec.fields` các field `META` nằm trong 1 tuple whitelist cứng (`HomeDurationMs`,
`HomeUpdateCount`, `MotorActiveDurationMs`, `CooldownActualMs`, `TimeSincePreviousRunMs`) --
KHÔNG có `ApproachProtocol`/`ApproachStructuralValid`, và tool không có nhánh đọc dòng
`APPROACH_RESULT,...`. Khẳng định "không cần sửa gì" ở REV 5 (mục "Ngoài phạm vi lần này") là
**sai** cho 2 field tóm tắt này -- cần thêm `"ApproachStructuralValid"` vào tuple whitelist đó
(dòng ~97-98) để `--metric ApproachStructuralValid` vẽ được biểu đồ 0/1/NA qua các run, hỗ trợ
trực tiếp bước kiểm tra gate 10/10 ở "Tiêu chí đánh giá". `ApproachProtocol` là chuỗi (không phải
số) nên không cần thêm vào whitelist float -- người dùng đã tự tách theo file log riêng cho mỗi
protocol (xem "Xác minh" bước A→B→A, mỗi leg là 1 file log riêng). Parse chi tiết record
`APPROACH_RESULT` (dùng cho phân tích ngưỡng calibration ở batch pilot) **không** đưa vào tool
tổng quát này -- dùng script scratch một lần, đúng pattern đã dùng cho mọi phân tích ad-hoc khác
trong dự án này (xem "Ngoài phạm vi lần này").

### 6. Test + fixture mới (theo đúng pattern đã có, không tự sáng tác kiểu test khác)

- `scripts/test_phase3b0_equal_approach_contract.ps1` (mẫu:
  `scripts/test_phase3b0_closure_probe_contract.ps1`), kiểm tra:
  - Mặc định tắt (`ENABLE_B0B_EQUAL_APPROACH=0`) → `META`/`SHADOW_RESULT` có
    `ApproachProtocol=DITHER_V1,ApproachStructuralValid=NA`, không có record `APPROACH_RESULT`
    nào, mọi field/giá trị khác giống hệt baseline hiện tại (đảm bảo no-op khi tắt).
  - `ApproachExpectedSteps` luôn đúng bằng 32 (tính từ `NL_POS_INCREASE/NL_RAMP_STEP`).
  - Giả lập lỗi ACQUISITION_ERROR thật (không phải timeout/wrong-position) ở TỪNG trong 6 vị trí
    (acquire riêng bước 0, initial-settle, backoff-ramp, backoff-settle, forward-ramp,
    point0-settle) → mỗi trường hợp: hàm `CaptureSweep()` trả về đúng mã lỗi sensor thật (KHÔNG
    phải `MA600_RESULT_OK`), `APPROACH_RESULT.Status=ACQUISITION_ERROR`.
  - Giả lập lỗi "thất bại mềm" (timeout/wrong-position, KHÔNG phải acquisition-error) riêng ở
    initial-settle/backoff-settle/point0-settle → mỗi trường hợp: `CaptureSweep()` trả về
    `MA600_RESULT_OK`, `measurementValid=false`, `APPROACH_RESULT.Status` đúng tên lý do tương
    ứng (`INITIAL_SETTLE_FAILED`/`BACKOFF_SETTLE_FAILED`/`POINT0_SETTLE_FAILED`).
  - Với MỌI trường hợp lỗi ở trên: không có `RESULT`/`SHADOW_RESULT` với `ClosureValid` hợp lệ
    được sinh ra từ dữ liệu approach lỗi; `out->contextAcquisition`/`Acq*` vẫn được tính đầy đủ
    (không rỗng) qua `FinalizeApproachEarlyExit()`; giai đoạn CHƯA chạy tới in `NA` (không phải
    `OK`) cho `Approach*SettleResult` tương ứng (kiểm tra trực tiếp cờ `Attempted`, ví dụ lỗi ở
    backoff-settle thì `ApproachPoint0SettleResult=NA`).
  - Chuỗi lệnh `Motor_SetElectricalPos` thực tế đúng `0 → -256 → ... → 0` (miền lệnh), KHÔNG lẫn
    giá trị `unwrappedRaw` nào (test trực tiếp bắt lỗi P0 đã sửa ở REV 4).
  - Bộ đếm `approachSettleAcquisition`/`approachBackoffRampAcquisition`/
    `approachForwardRampAcquisition` (KHÔNG gồm settle điểm 0) không làm thay đổi giá trị
    `Ramp*` của sweep chính; **`SettlePoints`/`SettleReadAttempts` của protocol B phải bằng
    đúng protocol A** (1 settle điểm 0 duy nhất tính vào `out->settleAcquisition` ở cả 2 --
    test trực tiếp bắt lỗi phân bổ counter P1 đã sửa ở REV 6).
  - `ApproachAcquisitionClean=0` khi giả lập có retry/transport-error/jump-reject trong đoạn
    approach dù direction/step-count đều đạt -- xác nhận gate không chỉ dựa vào 2 điều kiện cũ.
  - `ApproachProtocol`/`ApproachStructuralValid` xuất hiện nhất quán ở cả `META` và
    `SHADOW_RESULT`; đo độ dài dòng `META` thực tế lúc test chạy và assert `< 1900` (không
    hard-code số byte cụ thể, xem mục 4).
  - Build với cả `ENABLE_B0B_EQUAL_APPROACH=1` và `ENABLE_CCW_ENGINEERING_TEST=1` → xác nhận
    `#error` chặn đúng lúc biên dịch (test build thất bại có kiểm soát, không chạy runtime).
- `scripts/fixtures/schema-v5-phase3b0-equal-approach-p0X-jigY.txt` (mẫu:
  `scripts/fixtures/schema-v5-phase3b0-closure-probe-p05-jig3.txt`) -- dữ liệu tổng hợp nhỏ minh
  họa đúng field mới (gồm cả field định danh `APPROACH_RESULT` theo mẫu `CLOSURE_PROBE_RESULT`),
  không phải log thật (chưa có phần cứng chạy B0-B).

## Tiêu chí đánh giá (định lượng, audit được -- không dùng "cải thiện rõ rệt" mơ hồ)

**Batch phần cứng B0-B ĐẦU TIÊN là calibration/pilot, không phải kết luận cuối** (lý do: xem
mục "Đã sửa theo audit vòng 4" -- direction-check một mình chưa chứng minh được đã di chuyển đủ
~256 raw, ngưỡng biên độ `Approach*ErrorRaw` chưa hiệu chỉnh). Quy trình đánh giá batch đầu tiên
tách làm 2 bước, đúng theo yêu cầu của audit vòng 4:

1. **Batch B đầu tiên (pilot, protocol `_V1`)** -- chỉ dùng để:
   1. Thu thập phân bố `ApproachObservedDeltaRaw`/`ApproachTargetErrorRaw`/
      `ApproachReturnErrorRaw`/`BackoffObservedDeltaRaw`/`BackoffTargetErrorRaw` trên cả 10 run
      (từ record `APPROACH_RESULT`).
   2. Dùng phân bố đó để CHỐT ngưỡng chấp nhận chính thức cho "đã di chuyển đủ ~256 raw" (hiện
      chưa có số -- xem "Ngoài phạm vi lần này").
   3. **BẮT BUỘC đổi protocol ID thành `_V2`** (thêm ngưỡng biên độ vừa chốt vào gate) --
      **KHÔNG được tái sử dụng dữ liệu pilot `_V1` làm dữ liệu xác nhận**, dù
      `ApproachStructuralValid=1` cả 10/10 run pilot. Đây là 1 thay đổi code TÁCH BIỆT, SAU thay
      đổi lần này (ngoài phạm vi ở đây -- xem "Ngoài phạm vi lần này").
   4. Chạy lại **A→B→A** ĐỘC LẬP với protocol `_V2` để kết luận xác nhận (bước 2 dưới đây).
   Ở bước pilot này, KHÔNG tuyên bố "B0-B đã pass/fail" chỉ từ closure đẹp hay xấu, kể cả khi
   `ApproachStructuralValid=1` cả 10/10 run -- dữ liệu pilot chỉ dùng để chốt ngưỡng, không lẫn
   vào kết luận cuối.
2. **Batch A→B→A xác nhận** (sau khi đã chốt ngưỡng và đổi protocol `_V2` ở bước 1) -- áp toàn
   bộ gate định lượng bên dưới, chạy trên dữ liệu `_V2`, để ra kết luận chính thức.

**Structural validity (gate thật, áp dụng cho cả batch pilot lẫn batch xác nhận -- không cần
hiệu chỉnh)**: mỗi run protocol B phải đạt cả 4 điều kiện sau (tổng hợp thành
`ApproachStructuralValid=1`, firmware tự tính): cả 3 settle
(`ApproachInitialSettleResult`/`ApproachBackoffSettleResult`/`ApproachPoint0SettleResult`) đều
`OK`; `ApproachDirectionValid=1`; `ApproachStepCountValid=1`; `BackoffDirectionValid=1`. **Thêm**
`ApproachAcquisitionClean=1` (0 retry/transport-error/jump-reject/failed-sample trong toàn bộ
đoạn approach -- xem mục 3 bước 6) làm điều kiện riêng, không gộp cứng vào firmware
`MeasurementValid` (giữ đúng ý nghĩa field chính thức đã đóng băng). Việc gộp cuối cùng để lại
cho phân tích offline: `B0BEligible = MeasurementValid && ApproachStructuralValid &&
ApproachAcquisitionClean` (script/Python, không đổi ý nghĩa field firmware nào).

**Yêu cầu 10/10, không cherry-pick**: nếu bất kỳ run nào trong 10 run của 1 batch KHÔNG đạt
`B0BEligible`, thì CẢ LEG đó không đạt yêu cầu "≥3 sweep không tháo-lắp" của B0-B theo đúng tinh
thần định lượng -- không được loại (các) run lỗi rồi kết luận từ số run còn lại. Ghi nhận run
lỗi, tìm nguyên nhân (cơ khí/nhiễu/timing), và coi cả leg là không kết luận được cho tới khi chạy
lại đạt đủ 10/10.

**`ApproachMotionQualification=UNCALIBRATED`/`ApproachTargetErrorRaw`/`ApproachReturnErrorRaw`/
`BackoffTargetErrorRaw` chỉ đọc để CHẨN ĐOÁN** ở batch pilot -- KHÔNG dùng làm gate pass/fail
cho tới khi ngưỡng được chốt ở bước 1.2 ở trên. Nếu các giá trị này lớn bất thường (vd hàng trăm
raw) dù đã qua hết gate cấu trúc, đó là dấu hiệu cần dừng lại xem xét cơ khí trước khi diễn giải
closure, không âm thầm bỏ qua.

Ở batch A→B→A xác nhận (bước 2), báo cáo:
- Báo cáo **từng `ClosureErrorDeg` riêng lẻ** (không chỉ mean) + mean/SD/range/số run đạt
  `ClosureValid=1` (ngưỡng 0.20°) cho cả A và B.
- **RMS_AC/A36 không được xấu đi** so với baseline quá phạm vi đã quan sát được ở nghiên cứu lặp
  lại trước đó (CV trong-session ~0.2-1.3%) -- nếu B làm RMS_AC/A36 lệch nhiều hơn khoảng đó so
  với A, cần dừng lại xem xét trước khi kết luận về closure.
- **Nếu chọn `PERIODIC_MAP_V1`**: B chỉ được coi là "đạt" nếu closure-valid 10/10 (không phải
  trung bình đẹp nhưng có run lẻ tẻ fail).
- **Nếu B cải thiện rõ nhưng chưa đạt 10/10 dưới 0.20°**: chưa "pass" B0-B, nhưng đủ bằng chứng
  để xem xét thử pre-roll/fly-in (thay đổi tách biệt, ngoài phạm vi lần này) -- không tự động
  chuyển sang pre-roll trong cùng thay đổi này.
- **Nếu B không cải thiện closure so với A** (trong biên độ nhiễu đã biết): approach-history
  không phải nguyên nhân chính -- quay lại xem xét các giả thuyết khác trong tài liệu (không mở
  rộng phạm vi ở đây).

## Ngoài phạm vi lần này (đúng theo tài liệu, không tự mở rộng)
- Pre-roll/fly-in revolution -- chỉ xem xét nếu same-direction local approach không đạt tiêu chí
  trên, và sẽ là 1 thay đổi tách biệt, versioned riêng (đổi nhiệt/motor-on-time).
- **Ghi nhận rõ, chưa xử lý**: dwell/lịch sử tại vị trí backoff (bước 3 ở trình tự trên) hiện chỉ
  có 1 lần settle, chưa mô phỏng đúng việc điểm 255 thật sự đã "ở yên" một khoảng thời gian xác
  định (settle + các cửa sổ acquisition) trước khi ramp sang 256 -- khác biệt còn sót lại giữa 2
  lịch sử tiếp cận, chỉ nên xử lý ở vòng thí nghiệm sau nếu local-ramp tối thiểu không đủ cải
  thiện closure (đúng tinh thần "thử phương án ít xâm lấn nhất trước" của tài liệu B0-B).
- Định nghĩa ngưỡng chấp nhận chính thức cho `ApproachTargetErrorRaw`/`ApproachReturnErrorRaw`/
  `BackoffTargetErrorRaw` (tức "đã hiệu chỉnh `ApproachMotionQualification`") -- cần dữ liệu
  chuyển động point-to-point thật từ batch pilot đầu tiên (xem "Tiêu chí đánh giá", bước 1) hoặc
  B0-A hold-probe noise, làm sau khi có log B0-B đầu tiên, không đoán số trong lần thay đổi này.
- **Đổi `NL_B0B_APPROACH_PROTOCOL_ID` từ `_V1` sang `_V2`** (thêm ngưỡng biên độ vừa chốt ở trên
  làm gate) -- 1 thay đổi code TÁCH BIỆT, làm SAU khi có dữ liệu pilot `_V1` (xem "Tiêu chí đánh
  giá", bước 1.3). Không làm trong thay đổi này vì ngưỡng chưa tồn tại để mã hóa.
- Không đổi `MoveToZeroAndCheckDirection()` (PID home) hay `LockStartPosition()` (dither) -- cả
  hai giữ nguyên cho cả 2 protocol, đúng yêu cầu cô lập 1 biến duy nhất.
- Không thêm phân tích/so sánh/xếp hạng tự động vào firmware -- so `Shadow_ClosureErrorDeg` giữa
  2 bộ log (`ApproachProtocol=DITHER_V1` vs `DITHER_PLUS_CW_LOCAL_APPROACH_V1`) làm offline bằng
  `tools/plot_metric_trend.py` (đã sửa nhỏ ở mục 5b -- thêm `ApproachStructuralValid` vào
  whitelist). Không mở rộng tool này để parse chi tiết record `APPROACH_RESULT` (dùng cho phân
  tích ngưỡng ở batch pilot) -- dùng script scratch một lần, đúng pattern đã dùng cho mọi phân
  tích ad-hoc khác trong dự án này.
- Không tạo protocol batch pilot riêng (3-run) -- dùng nguyên batch 10-run
  (`NL_TEST_REPEAT_10_RUNS`, `ONE_FULL_SWEEP_120S_V1`) đã có, không đổi gate `#error` tại
  `nonlinear_test.c:420-422`.
- Không tổng quát hóa chiều tiếp cận B0-B theo `direction` để tương thích
  `ENABLE_CCW_ENGINEERING_TEST` -- cấm kết hợp 2 flag bằng `#error` (mục 2) thay vì mở rộng thiết
  kế; chỉ xem xét nếu sau này thực sự cần kiểm định B0-B trên sweep CCW.

## File bị ảnh hưởng
- `Core/Src/nonlinear_test.c` -- thay đổi chính (mục 1-4).
- `scripts/analyze_nonlinear_logs.ps1` -- thêm parse field `Approach*` (mục 5).
- `tools/plot_metric_trend.py` -- thêm `ApproachStructuralValid` vào whitelist `META` (mục 5b).
- `scripts/test_phase3b0_equal_approach_contract.ps1` -- test mới (mục 6).
- `scripts/fixtures/schema-v5-phase3b0-equal-approach-p0X-jigY.txt` -- fixture mới (mục 6).

## Xác minh
1. `scripts\preflight.ps1` rồi `scripts\build_cubeide.ps1` **Debug và Release**, cả 2 config,
   0 lỗi/0 cảnh báo -- với `ENABLE_B0B_EQUAL_APPROACH=0` (mặc định): xác nhận hành vi/field log
   không đổi so với trước khi sửa (refactor mục 1 phải no-op hành vi).
2. Build với `ENABLE_B0B_EQUAL_APPROACH=1` -- build sạch, cả Debug và Release.
3. Build với cả `ENABLE_B0B_EQUAL_APPROACH=1` và `ENABLE_CCW_ENGINEERING_TEST=1` cùng lúc -- xác
   nhận `#error` chặn đúng lúc biên dịch (thất bại có kiểm soát), rồi trả `ENABLE_CCW_
   ENGINEERING_TEST` về giá trị mặc định trước khi tiếp tục.
4. Chạy toàn bộ test host hiện có (`scripts/test_*.ps1`) + test mới ở mục 6 -- pass hết, không
   phá vỡ contract test nào đã có (đặc biệt `test_preconditioned_10run_contract.ps1` vì batch
   10-run được dùng lại nguyên vẹn).
5. Trên phần cứng thật (người dùng tự nạp/chạy), quy trình **A→B→A** (không chỉ A→B), không tháo
   motor/đổi dây/jig giữa các lần, nghỉ đầy đủ giữa mỗi leg, ghi rõ `ThermalState=UNMEASURED`
   trong ghi chú vận hành (không có cảm biến nhiệt). **Lượt A→B→A ĐẦU TIÊN dùng protocol `_V1` và
   là batch pilot** theo đúng "Tiêu chí đánh giá" ở trên (bước 1) -- chỉ dùng để chốt ngưỡng
   `Approach*ErrorRaw`, chưa dùng để kết luận B0-B pass/fail:
   - Leg A1: flag tắt, batch 10-run (`ApproachProtocol=DITHER_V1`).
   - Leg B (pilot, `_V1`): flag bật, rebuild+nạp lại, batch 10-run
     (`DITHER_PLUS_CW_LOCAL_APPROACH_V1`). Theo dõi sát vài run đầu (code mới, chưa chạy qua phần
     cứng thật lần nào), sẵn sàng dừng thủ công nếu có bất thường.
   - Leg A2: rebuild+nạp lại flag tắt, batch 10-run -- xác nhận quay lại đúng mức của A1 (bằng
     chứng nhân quả mạnh nếu A2 ≈ A1 và khác B).
   - Ghi lại BuildID và SHA-256 của từng file `.hex` đã nạp cho mỗi leg.
   - Sau khi chốt ngưỡng từ dữ liệu pilot này (Tiêu chí đánh giá, bước 1.2-1.3), đổi
     `NL_B0B_APPROACH_PROTOCOL_ID` sang `_V2` (thay đổi code tách biệt, ngoài phạm vi lần này),
     rebuild, rồi lặp lại **ĐỘC LẬP** đúng quy trình A→B→A (Leg A1'→B'(`_V2`)→A2') để ra **batch
     xác nhận** (bước 2) -- đây mới là dữ liệu dùng để kết luận B0-B pass/fail. Không tái dùng
     log của lượt pilot `_V1` cho mục đích này.
6. So `Shadow_ClosureErrorDeg` (và RMS_AC/A36 để kiểm tra không suy giảm) giữa 3 file log của
   lượt A→B→A xác nhận (`_V2`) bằng `python tools/plot_metric_trend.py legA1.txt legB.txt
   legA2.txt --metric Shadow_ClosureErrorDeg`, và `--metric ApproachStructuralValid` trên riêng
   file leg B để xác nhận 10/10 -- áp dụng đúng "Tiêu chí đánh giá" ở trên để kết luận, không kết
   luận cảm tính. Dữ liệu từ lượt pilot chỉ dùng để chốt ngưỡng, không lẫn vào kết luận cuối.

---

# [ĐÃ XONG - xem lịch sử] Phân tích delta toàn bộ kết quả đo của test 8 (offline, không sửa firmware)

## Context

Sau khi phân tích A/B giữa `p03 jig 1 test 7.txt` (PID state tồn lưu) và `p03 jig 1 test 8.txt`
(policy `RESET_BEFORE_EACH_HOME_V1`), người dùng xác nhận: độ lệch (delta) giữa các lần đo trong
test 8 rất nhỏ — **đúng yêu cầu ổn định họ đề ra** — và yêu cầu tính delta cho TẤT CẢ kết quả đo
của test 8, để định lượng đầy đủ mức lặp lại của từng metric thay vì chỉ vài field chính đã nêu.

Đây là phân tích dữ liệu thuần túy trên log sẵn có — **không sửa firmware, không sửa file nào
trong repo**. Làm bằng script Python trong scratchpad (đúng pattern `qc_report.py` đã dùng cho
báo cáo QC trước đó).

## Việc sẽ làm

Script Python mới trong scratchpad (`test8_delta.py`):

1. **Parse `p03 jig 1 test 8.txt`** (BatchID=2, 11 run: 1 PRECONDITION + 10 OFFICIAL):
   - 11 dòng `RESULT,...` — toàn bộ field số: MeanDC, RMS_AC, A1..A108 (12 amplitude), 12 phase,
     A4/H4/A8/H8, Residual_RMS_*, Fitted_P2P/_Extended, FitExplainedRatio/_Extended,
     Motor_Error_P2P_Deg, Motor_System_INL_Deg, CrestFactor, P99_AbsDeviation,
     TrackingError_RMS_Deg, TrackingError_MaxAbs_Deg.
   - 11 dòng `SHADOW_RESULT,...` — ClosureErrorDeg (+ shadow RMS/A36/P2P nếu có).
   - 11 dòng `META,...` — HomeDurationMs, HomeUpdateCount, MotorActiveDurationMs, StartRaw
     (độ lặp vị trí home), CooldownActualMs.
   Gắn nhãn RunOrder/RunRole; precondition (RunOrder=0) hiển thị riêng, KHÔNG tính vào thống kê
   chính (theo đúng `EligibleForStatistics=0`).

2. **Tính delta cho từng metric** (trên 10 run OFFICIAL):
   - Delta liên tiếp: Δᵢ = xᵢ − xᵢ₋₁ (9 giá trị) + max|Δ| liên tiếp.
   - Delta so với trung bình: xᵢ − mean (max lệch tuyệt đối khỏi mean).
   - Spread = max − min; SD; CV% (bỏ CV cho các field phase/MeanDC có thể qua 0 — chỉ dùng
     spread/SD cho chúng, tránh CV vô nghĩa khi mean gần 0).
   - Riêng precondition: delta của nó so với mean 10 run chính (để xác nhận nhận định "precondition
     giờ gần khớp run chính").

3. **Xuất báo cáo bảng** (in ra console, tôi tổng hợp lại thành bảng markdown khi trả lời):
   nhóm theo loại — (a) metric chính (RMS_AC/A36/INL/P2P/Tracking/P99/Closure), (b) harmonic
   amplitudes, (c) phases, (d) model-fit, (e) vận hành (Home/StartRaw/duration). Đánh dấu metric
   nào có CV ≤ 1% (đạt mức lặp lại tốt theo tiêu chí đã bàn) và metric nào lệch lớn.

## File bị ảnh hưởng
- Chỉ tạo script mới trong scratchpad (`C:\Users\tanph\AppData\Local\Temp\claude\...\scratchpad\
  test8_delta.py`). Không đổi bất kỳ file nào trong `c:\learn\rd\jig`.

## Xác minh
1. Script chạy ra đủ 11 dòng dữ liệu × đủ field (đối chiếu vài giá trị đã trích tay ở phân tích
   trước: RMS_AC run1=0.7425, ClosureErrorDeg run1=0.81676, HomeDurationMs run1=5091...).
2. Kiểm tra chéo: mean/CV của RMS_AC 10 run chính phải khớp con số đã báo cáo trước (~0.742,
   CV≈0.35%).

---

# [ĐÃ XONG - xem lịch sử] Chế độ "1 run / lần bấm" cho remount study + TimeSincePreviousRunMs

---

# [ĐÃ XONG - xem lịch sử] Motor_System_INL_Deg / Motor_Error_P2P_Deg + harmonic H4/H8

---

# Tăng K (NL_SAMPLES_PER_POINT) từ 20 lên 64, giữ N=256

## Context

Sau khi thảo luận đề xuất chọn bộ N/K tối ưu (đề xuất gốc: ma trận 13 test case pairwise, tự
đổi filter-window MA600A qua SPI register-write, state machine tự động 45 run, tự resample/
RMSE/correlation/xếp hạng trong firmware), đã xác định đề xuất đó có 4 rào cản thực tế:
1. `ma600.c` **không có bất kỳ hàm ghi register nào** (chỉ có `MA600_ReadReg()` đọc) — đổi filter
   window (FW) động cần xây mới hoàn toàn năng lực ghi SPI-register, rủi ro thật (kẹt sai FW nếu
   abort giữa chừng).
2. N=512/1024 tái tạo đúng loại rủi ro RAM-overflow đã từng xảy ra với `NL_MAX_SWEEP_POINTS`.
3. 45 run/lần bấm ở N/K cao kéo dài thời gian motor-on đáng kể — đúng mối lo "motor heat" đã nêu
   nhiều lần trong dự án.
4. Phần so curve/resample/RMSE/correlation/auto-rank đi ngược nguyên tắc đã thống nhất từ đầu dự
   án: thống kê so sánh nhiều cấu hình làm offline bằng Python, không nhét vào firmware.

Người dùng đã chốt: **chỉ test đúng 1 cấu hình N=256 (giữ nguyên), K=64** (tăng từ 20) — không
làm ma trận, không đổi FW, không state machine tự động.

Đã xác nhận trong code (`nonlinear_test.c:1099-1118`, vòng lấy mẫu trong `CaptureSweep()`):
không có delay giữa các lần đọc mẫu (từng thử nghiệm trước đây và xác nhận không giúp ích gì,
xem comment sẵn có tại chỗ) — tăng K từ 20 lên 64 chỉ thêm 44 lần đọc SPI nhanh mỗi điểm × ~264
điểm, chi phí thời gian không đáng kể so với ~17s `MotorActiveDurationMs` hiện tại (phần lớn thời
gian đó là di chuyển+settle motor, không phải đọc mẫu).

## Việc sẽ làm (`Core/Src/nonlinear_test.c`)

Đổi trực tiếp hằng số:
```c
#define NL_SAMPLES_PER_POINT        64   /* was 20 -- see MA600A datasheet review: multi-sample
                                           * averaging per position should be as large as
                                           * practical since it's ~free (no inter-sample delay,
                                           * see CaptureSweep()'s sampling loop). Kept N=256
                                           * unchanged -- raising N reintroduces RAM/motor-time
                                           * risk this project has hit before; K=64 is the
                                           * low-risk half of that tradeoff. */
```
(dòng ~64, comment cũ về việc bỏ delay giữa các mẫu vẫn giữ nguyên bên dưới trong `CaptureSweep()`)

Không đổi gì khác — `NL_POS_INCREASE` (N=256), `NL_MAX_SWEEP_POINTS`, settle logic, harmonic sets
đều giữ nguyên.

## File bị ảnh hưởng
- `Core/Src/nonlinear_test.c` — đổi giá trị `NL_SAMPLES_PER_POINT` từ 20 thành 64, cập nhật
  comment tại chỗ định nghĩa.

## Xác minh
1. `scripts\preflight.ps1` rồi `scripts\build_cubeide.ps1` — build sạch, 0 lỗi/cảnh báo.
2. Nạp và chạy 1 test — so `MotorActiveDurationMs`/tổng thời gian sweep trước/sau để xác nhận
   chi phí thời gian thực tế đúng là nhỏ như dự đoán (không phải chỉ suy đoán từ code).
3. So `RMS_AC`/`A36`/`Motor_System_INL_Deg` giữa K=20 (log cũ đã có) và K=64 (log mới) trên cùng
   1 motor/jig — kỳ vọng: giá trị gần như không đổi (vì trước đó đã xác nhận averaging 20 mẫu vốn
   đã đủ mượt, xem comment "residual mechanical ringing" trong code), chỉ nhiễu run-to-run có thể
   giảm nhẹ.

## Context

Người dùng gửi một bản rà soát chi tiết theo MA600A Rev. 1.0, kết luận chính: giá trị nonlinear hiện tại
không nên gọi là "MA600A INL theo datasheet" vì hệ thống không có encoder reference độc lập — phải gọi
là `Motor_System_INL` (đo cả cụm motor+magnet+jig+MA600A, không tách riêng được sensor). Đề xuất có 13
mục, nhưng sau khi rà lại `Core/Src/nonlinear_test.c`/`Core/Src/ma600.c` bằng Explore agent, phần lớn đã
**đúng sẵn theo cách khác**, không cần sửa:

- **Circular average khi wrap 0°/360°**: đã đúng — `MA600_UpdateMultiTurn()` (`Core/Src/ma600.c:93-112`)
  unwrap từng delta raw *trước khi* cộng dồn thành `multiTurnCount`, nên trung bình cộng thường của
  `NL_SAMPLES_PER_POINT=20` giá trị `MA600_ReadMultiTurnDegrees()` (`nonlinear_test.c:1082-1099`) đã
  tương đương circular mean cho use-case này — không cần thêm `CircularMeanDeg()`.
- **Settle rồi mới lấy K mẫu**: đã đúng sẵn — `WaitForPointSettle()` (`nonlinear_test.c:852-886`, dựa
  trên dung sai 0.05°/8 lần đọc liên tiếp ổn định/timeout 100ms) chạy xong mới vào vòng lặp lấy 20 mẫu.
- **Không calibrate riêng từng motor**: tự động thỏa mãn — `ma600.c` không có bất kỳ lệnh ghi
  CORR0-31/LUT/NVM nào, "LUT BYPASSED" chỉ là log string tĩnh, mọi góc đọc đều là giá trị thô chưa hiệu
  chỉnh.
- **"Chế độ A — Jig Qualification"** (cần encoder reference độc lập, K≈1000 mẫu/vị trí, điều kiện từ
  trường/nhiệt độ kiểm soát): cần phần cứng encoder chuẩn mà jig này không có — ngoài phạm vi firmware,
  không làm ở đây (giống lý do MotorID/UART command parser đã bị deferred trước đó).
- **Tăng số điểm/vòng lên 512-1024**: sẽ tái tạo đúng loại rủi ro RAM-overflow đã từng xảy ra với
  `NL_MAX_SWEEP_POINTS`, và không có encoder chuẩn để làm cho độ phân giải cao hơn thực sự có ý nghĩa
  khoa học — không làm.

**Phần thực sự còn thiếu, đã xác nhận với người dùng giới hạn đúng phạm vi này**:
1. `legacyStats.rawPP` (= max−min của đường cong lỗi thô, tính sẵn trong `ComputeSweepStats()`,
   `nonlinear_test.c:675-740`) **chưa từng được xuất ra dòng `RESULT`** — chỉ có ở dòng text legacy
   (`"NL raw peak-to-peak..."`). Cần thêm 2 field mới vào `RESULT`: `Motor_Error_P2P_Deg` (=rawPP) và
   `Motor_System_INL_Deg` (=rawPP/2, đúng công thức INL trong datasheet áp cho đường cong đo thực tế).
   Không tính toán gì mới — chỉ format và in thêm.
2. Harmonic order 4 và 8 (bộ "datasheet-aligned H1/H2/H4/H8") chưa có trong
   `NL_HARMONIC_ORDERS`/`NL_LEGACY_HARMONIC_ORDERS`. Cần thêm `A4`/`H4_PhaseSweepDeg`/`A8`/
   `H8_PhaseSweepDeg` — tính bằng đúng hàm `ComputeHarmonicFull()` sẵn có, gọi trực tiếp cho order 4/8
   (hàm nhận 1 order mỗi lần gọi, `nonlinear_test.c:458-460`), **không** đưa vào mảng
   `NL_HARMONIC_ORDERS`/model "Extended" — vì làm vậy sẽ đổi ý nghĩa `Residual_RMS_Extended`/
   `Fitted_P2P_Extended`/`FitExplainedRatio_Extended` hiện có (đúng anti-pattern "redefine field" đã bị
   sửa trước đó trong dự án này). H1/H2 không cần tính lại — đã có sẵn `A1`/`A2`/`H1_PhaseSweepDeg`/
   `H2_PhaseSweepDeg` từ bộ Extended, ý nghĩa giống hệt.

Không đổi tên/xóa bất kỳ field nào đang có (`Fitted_P2P`, `RMS_AC`, dòng text
`"Nonlinear N Angle"`/`"NL raw peak-to-peak"` giữ nguyên byte-for-byte — vẫn cần cho
`scripts/analyze_nonlinear_logs.ps1` và để không phá dữ liệu lịch sử).

## Việc sẽ làm (`Core/Src/nonlinear_test.c`)

### 1. Thêm `Motor_Error_P2P_Deg`/`Motor_System_INL_Deg` vào RESULT

Trong `PrintSweepLog()`, thêm 2 buffer định dạng theo đúng pattern `FormatDeg2` đã dùng cho mọi field
khác:
```c
char motorP2PBuf[16], motorInlBuf[16];
FormatDeg2(c->legacyStats.rawPP, motorP2PBuf, sizeof(motorP2PBuf));
FormatDeg2(c->legacyStats.rawPP / 2.0f, motorInlBuf, sizeof(motorInlBuf));
```
Thêm `,Motor_Error_P2P_Deg=%s,Motor_System_INL_Deg=%s` vào format string RESULT (đặt sau
`FitExplainedRatio_Extended`, cùng nhóm các field P2P/chất lượng), và 2 tham số tương ứng.

Cần thêm `legacyStats` — đã có sẵn trong `NlSweepCapture_t` (`c->legacyStats`, đã gán ở
`nonlinear_test.c:1293`), không cần field struct mới.

### 2. Thêm H4/H8

Trong `NlSweepCapture_t`, thêm 2 field mới: `NlHarmonicResult_t harmonicH4; NlHarmonicResult_t
harmonicH8;` (không đụng mảng `harmonics[NL_HARMONIC_COUNT]` hiện có).

Ngay sau vòng lặp tính `out->harmonics[k]` hiện có (`nonlinear_test.c:1241-1244`), thêm:
```c
ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal, 4, &out->harmonicH4);
ComputeHarmonicFull(out->errorSamples, analysisCount, meanVal, 8, &out->harmonicH8);
```
(Nyquist an toàn tuyệt đối — order 4/8 << 128.)

Trong `PrintSweepLog()`, thêm `A4=%s,H4_PhaseSweepDeg=%s,A8=%s,H8_PhaseSweepDeg=%s` vào RESULT — đặt
ngay sau khối `A108=...,H108_PhaseSweepDeg=...` hiện có, trước `PhaseValidMask`.

**Mở rộng `PhaseValidMask`** thêm 2 bit (bit 12 = H4 phase-valid, bit 13 = H8 phase-valid) — 12 bit hiện
có (order 1..108) giữ nguyên ý nghĩa, chỉ nối thêm bit mới, không phải redefine.

### 3. Comment làm rõ khái niệm (đầu file, cạnh comment lịch sử schema)

Thêm đoạn comment ngắn giải thích: dự án này không có encoder reference độc lập, nên mọi giá trị
nonlinear đo được (kể cả `Motor_System_INL_Deg` mới) đo cả hệ thống (motor+magnet+mounting+jig+MA600A),
không được so trực tiếp với giới hạn INL 0.6°/0.1° trong datasheet MA600A (giới hạn đó chỉ áp dụng khi
có encoder chuẩn độc lập — "Jig Qualification mode" mà jig này không có phần cứng để làm). Đây là
comment thuần túy, không đổi hành vi.

## File bị ảnh hưởng
- `Core/Src/nonlinear_test.c` — thêm 2 field RESULT (`Motor_Error_P2P_Deg`/`Motor_System_INL_Deg`, dùng
  lại `legacyStats.rawPP` đã tính sẵn), thêm 2 harmonic field mới (`harmonicH4`/`harmonicH8` trong
  `NlSweepCapture_t`, tính bằng `ComputeHarmonicFull()` sẵn có), mở rộng `PhaseValidMask` thêm 2 bit,
  thêm comment giải thích Motor_System_INL vs MA600A INL. Không đổi `nonlinear_test.h`/`main.c`.

## Xác minh
1. `scripts\preflight.ps1` rồi `scripts\build_cubeide.ps1` với cấu hình mặc định hiện tại — build sạch,
   0 lỗi/cảnh báo.
2. Nạp và chạy 1 test — xác nhận dòng `RESULT` có thêm đúng `Motor_Error_P2P_Deg`, `Motor_System_INL_Deg`
   (= đúng nửa giá trị `Motor_Error_P2P_Deg`), `A4`, `H4_PhaseSweepDeg`, `A8`, `H8_PhaseSweepDeg`, và
   `PhaseValidMask` có thêm 2 bit cao nhất phản ánh đúng H4/H8. Đối chiếu `Motor_Error_P2P_Deg` khớp với
   dòng text legacy `"NL raw peak-to-peak..."` đã in trước đó (phải bằng nhau, cùng nguồn `rawPP`).
3. Xác nhận mọi field/dòng text cũ (`Fitted_P2P`, `RMS_AC`, `"Nonlinear N Angle"`, `LegacyOrders=1|2|3|6|
   12|18`, `ExtendedOrders=1|2|3|6|9|12|18|27|36|45|72|108`) giữ nguyên giá trị/định dạng như trước khi
   sửa — không có gì bị redefine.

## Context

Báo cáo remount vừa phân tích 3 run trong `jig1 test 3.txt` như thể chúng là 3 lần tháo–lắp
riêng biệt ("Run 1, Run 2 và Run 3 tương ứng với ba lần tháo motor ra rồi lắp lại"), nhưng tự
báo cáo cũng thừa nhận: "Log chưa có trường `MountCycle`, nên việc phân nhóm này đang dựa trên
mô tả của bạn." Thực tế, theo đúng thiết kế `ENABLE_AUTO_BATCH_TEST`/`NL_TEST_REPEAT_3_RUNS`
hiện tại, 3 run đó nằm trong **cùng một `BatchID=1`**, chạy tự động nối tiếp nhau với cooldown
120s do firmware tự kiểm soát — không có bước nào chờ operator thao tác. Nếu operator không
thực sự can thiệp tháo lắp motor giữa 3 lần đó (rất khó canh đúng lúc trong cửa sổ 120s tự
động), thì kết luận "remount variability" trong báo cáo đó thực chất chỉ đang đo lại đúng biến
động run-to-run/settling đã thấy ở bài 10-run cùng-mount, không phải biến động do tháo–lắp
thật.

Cách sửa đúng: thêm một **chế độ 3 (`1 run/lần bấm`)** vào đúng bộ macro loại-trừ-lẫn-nhau đã
có (`NL_TEST_REPEAT_3_RUNS`/`NL_TEST_REPEAT_10_RUNS`) sao cho **1 lần bấm nút = đúng 1 run,
rồi batch tự hoàn tất ngay** (không tự động cooldown/tiếp tục). Dưới chế độ này, "1 mount
cycle" và "1 batch" trở thành tương đương *theo đúng cấu trúc*, không còn phải suy đoán qua mô
tả ngoài log nữa — vì mọi lần bấm nút mới đều là một `BatchID` mới, và operator chỉ bấm nút sau
khi đã tháo–lắp lại xong. Do đó **không cần thêm field `MountCycle` mới** trùng ý nghĩa với
`BatchID` sẵn có — chỉ cần ghi rõ trong comment rằng dưới chế độ 1-run, `BatchID` chính là mã
mount cycle.

Đồng thời thêm `TimeSincePreviousRunMs`: khác với chế độ 3/10-run (cooldown do firmware tự
canh), chế độ 1-run có khoảng nghỉ giữa các lần bấm hoàn toàn do operator tự canh tay khi
tháo–lắp ngoài đời — field này cho biết chính xác đã trôi qua bao lâu kể từ khi motor lần
trước tắt torque đến khi lần chạy này bắt đầu, để xác minh operator có thực sự chờ đủ ~120s
giữa các lần mount hay không, thay vì chỉ tin theo lời kể.

**Đã xác nhận với người dùng**: bỏ qua hoàn toàn phần `MotorID`/`OrientationID`/
`ClampTorque_Nm`/`TemperatureBeforeTest_C` — không có sensor đo được các giá trị này, và hiện
tại project **chưa có bất kỳ cơ chế nhập liệu runtime nào** (đã xác minh: không UART RX
parser/callback nào tồn tại ngoài HAL library, không DIP switch, không bàn phím) — xây dựng
việc đó là một subsystem mới hoàn toàn, ngoài phạm vi lần này. Các giá trị đó tiếp tục ghi tay
ngoài log, đối chiếu qua `BatchID` + timestamp đã có sẵn trong log (đúng convention đang dùng
cho Jig/Product qua tên file).

## Việc sẽ làm (`Core/Src/nonlinear_test.c` trừ khi ghi chú khác)

### 1. Thêm chế độ thứ 3 vào bộ macro loại-trừ-lẫn-nhau (dòng ~245-263)

```c
#ifndef ENABLE_AUTO_BATCH_TEST
#define ENABLE_AUTO_BATCH_TEST      1
#endif

#if ENABLE_AUTO_BATCH_TEST
#ifndef NL_TEST_REPEAT_1_RUN
#define NL_TEST_REPEAT_1_RUN        0
#endif
#ifndef NL_TEST_REPEAT_3_RUNS
#define NL_TEST_REPEAT_3_RUNS       1
#endif
#ifndef NL_TEST_REPEAT_10_RUNS
#define NL_TEST_REPEAT_10_RUNS      0
#endif
#if ((NL_TEST_REPEAT_1_RUN + NL_TEST_REPEAT_3_RUNS + NL_TEST_REPEAT_10_RUNS) != 1)
#error "Enable exactly one test mode: NL_TEST_REPEAT_1_RUN, NL_TEST_REPEAT_3_RUNS, or NL_TEST_REPEAT_10_RUNS"
#endif
#if NL_TEST_REPEAT_1_RUN
#define NL_BATCH_RUN_COUNT          1U
#elif NL_TEST_REPEAT_3_RUNS
#define NL_BATCH_RUN_COUNT          3U
#else
#define NL_BATCH_RUN_COUNT          10U
#endif
```

Đặt tên `NL_TEST_REPEAT_1_RUN` (không phải `NL_TEST_MODE_PRODUCTION_1_RUN` như đề xuất gốc) để
khớp naming convention đã dùng cho 2 flag còn lại.

Không cần sửa gì trong `RunBatchSweep()`/state machine: với `NL_BATCH_RUN_COUNT=1U`, điều kiện
có sẵn `if (nlCurrentRun >= NL_BATCH_RUN_COUNT)` đã đúng ngay sau run đầu tiên — batch tự
chuyển `NL_BATCH_COMPLETE` (log `BATCH,...,Status=COMPLETE,RunCount=1`) mà không bao giờ vào
trạng thái `NL_BATCH_COOLDOWN`. Logic này dùng lại 100% state machine đã có, không thêm code
mới ở đó.

Thêm comment tại định nghĩa `nlBatchId`/`nlBatchIdCounter` (dòng ~1003) ghi rõ: dưới
`NL_TEST_REPEAT_1_RUN`, `BatchID` chính là mã định danh mount cycle (mỗi lần bấm nút mới = một
`BatchID` mới = một chu kỳ tháo–lắp mới, theo đúng giao thức thao tác); vẫn `CounterScope=BOOT`
như các counter khác trong file — reset về khi reset nguồn, không phải giới hạn mới.

### 2. Thêm `TimeSincePreviousRunMs`

Field mới trong `NlSweepCapture_t` (gần `motorActiveDurationMs`, dòng ~920), gated bởi
`#if ENABLE_AUTO_BATCH_TEST`:
```c
uint32_t timeSincePreviousRunMs; /* wall-clock kể từ khi motor lần chạy TRƯỚC tắt torque đến
                                   * khi lần chạy này bắt đầu -- 0/không hợp lệ nếu đây là lần
                                   * chạy đầu tiên kể từ khi boot. */
bool     hasPreviousRun;
```

Trong `NonlinearTest_Run()`, ngay tại chỗ đã có `runStartTick = HAL_GetTick();` (dòng ~1685),
đọc giá trị `nlLastMotorOffTick`/cờ "đã từng chạy chưa" TỪ TRƯỚC KHI nó bị ghi đè bởi chính lần
chạy này (việc ghi đè diễn ra sau, ở dòng ~1730-1731):
```c
static bool nlHasPreviousRun = false; /* static riêng, khác nlLastMotorOffTick -- 0 là giá trị
                                        * tick hợp lệ ở đầu quá trình boot nên không thể dùng
                                        * nlLastMotorOffTick==0 để suy ra "chưa từng chạy". */
uint32_t runStartTick = HAL_GetTick();
uint32_t timeSincePreviousRunMs = nlHasPreviousRun ? (runStartTick - nlLastMotorOffTick) : 0;
bool     hasPreviousRunSnapshot = nlHasPreviousRun;
```
rồi gán vào từng phần tử capture (cùng vòng lặp đang gán `motorActiveDurationMs`, dòng ~1742),
và set `nlHasPreviousRun = true;` cùng chỗ đang set `nlLastMotorOffTick = motorOffTick;` (dòng
~1731).

### 3. In vào dòng `META`

Theo đúng pattern `CooldownTargetMs=NA` đã có (dòng ~1330-1341): thêm buffer
`timeSincePreviousRunBuf`, in `"NA"` khi `!hasPreviousRun`, ngược lại in giá trị mili-giây.
Thêm `,TimeSincePreviousRunMs=%s` vào cuối chuỗi định dạng `#if ENABLE_AUTO_BATCH_TEST` (dòng
~1350) và buffer tương ứng vào danh sách tham số (dòng ~1363).

## Ngoài phạm vi lần này (đã xác nhận với người dùng)
- `MotorID` thật, `OrientationID`, `ClampTorque_Nm`, `TemperatureBeforeTest_C` — không có
  sensor đo được; cần cơ chế nhập liệu runtime (UART command parser) hoàn toàn chưa tồn tại
  trong project (đã xác minh: 0 dòng code RX nào ngoài HAL library, không ISR/callback, không
  `usart.c` riêng). Xây dựng subsystem đó là việc lớn hơn nhiều so với phạm vi lần này — người
  dùng đã đồng ý bỏ qua, tiếp tục ghi tay ngoài log.
- T-sweep study để chốt `NL_COOLDOWN_TIME_MS` chính thức — vẫn là việc vận hành/offline, không
  đổi gì trong phạm vi lần này.

## File bị ảnh hưởng
- `Core/Src/nonlinear_test.c` — thêm `NL_TEST_REPEAT_1_RUN` vào bộ macro loại trừ lẫn nhau,
  thêm field `timeSincePreviousRunMs`/`hasPreviousRun` vào `NlSweepCapture_t`, tính toán trong
  `NonlinearTest_Run()`, in thêm vào dòng `META`. Không đổi `Core/Inc/nonlinear_test.h` hay
  `Core/Src/main.c` — API và call site không đổi.

## Xác minh
1. `scripts\preflight.ps1` rồi `scripts\build_cubeide.ps1` với cấu hình mặc định hiện tại
   (`NL_TEST_REPEAT_3_RUNS=1`) — phải build sạch, hành vi không đổi so với hiện tại (field mới
   chỉ thêm, không sửa field cũ).
2. Build với `NL_TEST_REPEAT_1_RUN=1` (và 2 flag kia = 0) — build sạch.
3. Bật đồng thời 2 trong 3 flag (VD `NL_TEST_REPEAT_1_RUN=1` và `NL_TEST_REPEAT_3_RUNS=1`) —
   xác nhận `#error` chặn đúng, rồi trả về đúng 1 flag.
4. Nạp với `NL_TEST_REPEAT_1_RUN=1`, bấm nút — xác nhận log có đúng 1 dòng `DATA`/`RESULT`/
   `END` rồi `BATCH,...,Status=COMPLETE,RunCount=1` ngay, không có `COOLDOWN_START` nào. Lần
   bấm đầu tiên sau khi nạp: `TimeSincePreviousRunMs=NA`. Bấm nút lần 2 (mô phỏng remount):
   `TimeSincePreviousRunMs` phải khớp với thời gian thực đã chờ giữa 2 lần bấm (đối chiếu bằng
   đồng hồ tay).
5. Trả cấu hình về mặc định đang dùng thực tế (`NL_TEST_REPEAT_3_RUNS=1` hoặc theo ý người
   dùng) trước khi bàn giao — không tự đổi default nếu không được yêu cầu.
