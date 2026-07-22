# Thông số đo và kiểm tra (Measured & Checked Parameters)

> Tổng hợp từ firmware (`Core/Src/*.c`, `Core/Inc/*.h`), công cụ phân tích (`tools/*.py`, `scripts/*.ps1`), và bộ MATLAB (`analysis/matlab/**`).
> Tài liệu tham chiếu gốc: [nonlinear-metric-contract-v1.md](nonlinear-metric-contract-v1.md), [control-a5-checklist.md](control-a5-checklist.md).

Mỗi test "Part" (A2, A3, A4/A4B, A5, B0-B) dùng chung engine quét/giữ vị trí trong `Core/Src/nonlinear_test.c` và `control_engine.c`, nhưng có bộ tham số và ngưỡng pass/fail riêng.

---

## A2 — Quét xoay vòng (rotating-capture), phi tuyến & sóng hài

File: `Core/Src/nonlinear_test.c` (điểm chuẩn `NL_*`), `analysis/matlab/compute_a2_metrics.m`, `tools/analyze_motor_logs.py`.

Cấu hình quét: 370° (`NL_SWEEP_ANGLE_DEG`), bước 1°, 360 điểm/vòng (`NL_POINTS_PER_REV`), 65536 raw/vòng (`NL_FULL_TURN_RAW`), protocol `UNIFORM_1_DEG_ROUNDED_RAW_V1`.

### Thông số đo (per-point)
- Góc trục thô (encoder tuyệt đối MA600A, Q16 raw đã unwrap)
- Sai số so với target tại 360 điểm phân tích (0–359, đúng 1°/điểm — `NL_POINTS_PER_REV`)
- Sai số đóng vòng (closure error) tại điểm 360 (đúng một vòng cơ khí)
- Sai số 10 điểm hậu vòng (post-turn margin, điểm 361–370 — lặp lại vùng góc 1–10°, xem mục "Chỉ số hậu vòng" bên dưới)
- Sai số vị trí ổn định (settle error, raw) và số lần poll ổn định
- Tracking error (đo – target): RMS và max trên toàn bộ điểm
- Sức khỏe thu thập SPI: số giao dịch, số lỗi liên tiếp, thời gian, số lần bị loại do nhảy giá trị (jump reject)

> **Lưu ý về nguồn "256 điểm":** giao thức cũ (legacy schema v5, `STEP_RAW=256`) dùng lưới 256 điểm/vòng và vẫn còn là giá trị mặc định cứng trong `tools/analyze_motor_logs.py:49-51` (`ANALYSIS_POINT_COUNT=256`, `CLOSURE_INDEX=256`) — tool này **chưa cập nhật** theo giao thức hiện tại của firmware. Firmware hiện hành (`UNIFORM_1_DEG_ROUNDED_RAW_V1`) dùng lưới 360 điểm/vòng tròn độ, như mô tả ở `Core/Src/nonlinear_test.c:3565-3568`.

### Thông số tính toán (derived)
- MeanDC, RMS_AC (độ) trên điểm 0–359 (một chu kỳ cơ khí đầy đủ, đúng giả định của DFT bậc chọn lọc)
- Raw Peak-to-Peak (P2P) và `System_INL_Deg = RawP2P / 2`
- Robust P2P (trung bình 5 điểm cao nhất − 5 điểm thấp nhất, `NL_ROBUST_EXTREME_COUNT=5`)
- P99 độ lệch tuyệt đối (nearest-rank percentile)
- DFT bậc chọn lọc (biên độ, pha) tại các order: 1, 2, 3, 6, 9, 12, 18, 27, 36, 45, 72, 108
- Tái tạo họa ba theo họ: `LEGACY_6_V1` (1,2,3,6,12,18), `EXTENDED_12_V1` (đủ tập), `ELECTRICAL_FAMILY` (36,72,108)
- Thống kê vòng tròn (circular stats): mean/SD/range/resultant R
- Circular significance: Rayleigh test (z, p-value) + bootstrap CI trên R
- Fit sóng hài mô-men hồi phục (restoring torque) theo pha điện lúc bắt đầu: biên độ, pha, R², p-value F-test
- Theo dõi bao an toàn (safety envelope) theo ngân sách bước

### Ngưỡng pass/fail (limits)

| Thông số | Giới hạn | Đơn vị | Hằng số |
|---|---|---|---|
| Sai số ổn định tại điểm | 9 raw (0.04944°) | raw/deg | `NL_POINT_SETTLE_ERROR_RAW` |
| Số poll ổn định liên tiếp | 8 | count | `NL_POINT_SETTLE_CONSECUTIVE` |
| Timeout ổn định | 100 | ms | `NL_POINT_SETTLE_TIMEOUT_MS` |
| Dung sai gần target (bao chuyển động, rất lỏng) | 910 raw (4.99878°) | raw/deg | `NL_SETTLE_TARGET_TOLERANCE_RAW` |
| Sai số về 0 (home) | 0.05 | deg | `NL_MOVE_ZERO_ERROR_DEG` |
| Timeout về 0 | 20000 | ms | `NL_MOVE_ZERO_TIMEOUT_MS` |
| Giới hạn đóng vòng (shadow/canonical, thử nghiệm) | 0.20 (~2,386,093 Q16) | deg | `NL_SHADOW_CLOSURE_LIMIT_DEG` |
| Tracking RMS hợp lệ | ≤ 15.0 | deg | `NL_TRACKING_RMS_VALID_DEG` |
| Tracking max-abs hợp lệ | ≤ 30.0 | deg | `NL_TRACKING_MAX_VALID_DEG` |
| Góc kiểm tra hướng quay | 90 | deg | `NL_CHECK_DIR_ANGLE_DEG` |
| Bước nhảy tối đa khi thu thập (settle/sweep) | 1821 | raw | `NL_SETTLE_MAX_JUMP_RAW` / `NL_SWEEP_MAX_JUMP_RAW` |
| Số giao dịch SPI tối đa (shadow point) | 96 | count | `NL_SHADOW_POINT_MAX_TRANSACTIONS` |
| Số lỗi liên tiếp tối đa (shadow point) | 2 | count | `NL_SHADOW_POINT_MAX_CONSECUTIVE_FAILURES` |
| Thời gian tối đa (shadow point) | 20000 | µs | `NL_SHADOW_POINT_MAX_ELAPSED_US` |
| Biên độ tối thiểu để pha hợp lệ | 0.05 | deg | `NL_PHASE_MIN_AMPLITUDE_DEG` |
| Ngưỡng ổn định tiền điều kiện (adaptive precondition) | 0.03 | deg | `NL_PRECONDITION_STABILITY_THRESHOLD_DEG` |
| Số chu kỳ tiền điều kiện tối đa | 5 | count | `NL_PRECONDITION_MAX_COUNT` |
| Bao an toàn A2: bước mẫu tối đa | 45.0 | raw | `build_a2_safety_envelope.m` (`stepLimitRaw`) |
| Bao an toàn A2: hành trình tối đa | 910 (~5.0°) | raw/deg | `build_a2_safety_envelope.m` (`travelLimitDeg`) |
| Thời gian nghỉ giữa các test | 120000 (±300 dung sai) | ms | `NL_COOLDOWN_TIME_MS` / `NL_COOLDOWN_TOLERANCE_MS` |

### Chỉ số hậu vòng (post-turn repeat, điểm 361–370) — *đề xuất bổ sung, chưa có trong firmware*

360° sweep chỉ dùng điểm 0–359 cho MeanDC/RMS/DFT vì đó là đúng một chu kỳ cơ khí; đưa thêm điểm 361–370 vào cùng phép DFT sẽ **tính lặp** vùng góc 1–10° và làm méo biên độ/pha các bậc hài (vi phạm giả định lấy mẫu đúng một chu kỳ). Vì vậy các điểm này bị loại khỏi thống kê chính (`Core/Src/nonlinear_test.c:3565-3568`).

Tuy nhiên, vì điểm 361–370 đo lại **cùng vị trí góc cơ khí** với điểm 1–10 (sau khi motor đã đi trọn 360°), sai khác giữa hai lần đo là một phép kiểm tra tính toàn vẹn/lặp lại độc lập với NL/DFT — tương tự nguyên lý closure (điểm 360 vs điểm 0) nhưng mở rộng ra 10 điểm liên tiếp thay vì chỉ 1.

**Định nghĩa:**
```text
PostTurnRepeatDelta[i]     = Error[360 + i] - Error[i]                         , i = 1..10
ClosureNormalizedDelta[i]  = PostTurnRepeatDelta[i] - (Error[360] - Error[0])   , i = 1..10
```
`ClosureNormalizedDelta` tách phần lệch do riêng closure (offset cố định tại điểm 360) ra khỏi phần lệch còn lại theo từng góc — nếu hệ thống chỉ có sai số closure không đổi, `ClosureNormalizedDelta` phải xấp xỉ 0 ở cả 10 điểm.

**Kết quả đối chiếu thực nghiệm (30 run chính thức, Test 21):**

| Leg | Closure tại 360° | RMS `PostTurnRepeatDelta` (1–10°) | RMS `ClosureNormalizedDelta` | Max abs `ClosureNormalizedDelta` |
|---|---:|---:|---:|---:|
| A1 | −0.36789° | 0.58820° | 0.25249° | 0.48849° |
| B | −0.25490° | 0.59576° | 0.35292° | 0.60703° |
| A2 | −0.35388° | 0.54471° | 0.22170° | 0.47586° |
| Tổng | −0.32556° | 0.57666° | 0.28134° | 0.60703° |

`ClosureNormalizedDelta` trung bình theo từng góc lặp (không cố định, không giải thích được chỉ bằng offset closure):

| Góc lặp | `ClosureNormalizedDelta` trung bình |
|---:|---:|
| 1° | −0.219° |
| 2° | −0.447° |
| 3° | −0.054° |
| 4° | −0.414° |
| 5° | −0.302° |
| 10° | −0.063° |

**Diễn giải:**
- Một phần sai lệch 1–10° hậu vòng đến từ chính offset closure tại 360° (đã bị trừ ra trong `ClosureNormalizedDelta`).
- Sau khi loại closure, vẫn còn dư `0.22–0.35° RMS` — không tiến về 0, và không đều theo góc ⇒ có thêm ảnh hưởng khác ngoài closure offset (nhiều khả năng: ma sát/cogging, load-angle, hoặc trạng thái bộ điều khiển chưa hoàn toàn ổn định ngay sau khi khép vòng).
- Protocol B cải thiện closure tốt nhất (−0.25490° so với A1/A2 ~−0.35°) nhưng lại có `ClosureNormalizedDelta` RMS **lớn nhất** (0.35292°) — cho thấy closure tốt hơn không đồng nghĩa quỹ đạo đã quay lại trạng thái tuần hoàn tốt hơn.
- Chỉ nhìn NL/DFT trên 0–359 sẽ **không phát hiện** hiện tượng này vì phạm vi 0–359 vốn không lặp lại phép đo ở cùng một góc.

**Kết luận & khuyến nghị:**
- Dùng 0–359 cho NL/DFT vẫn đúng về mặt toán học — không nên gộp 360–370 vào cùng phép biến đổi đó.
- Không nên **bỏ qua** 361–370 hoàn toàn — nên báo cáo `PostTurnRepeatDelta`/`ClosureNormalizedDelta` (Mean, RMS, MaxAbs, và đường residual theo góc) như một nhóm chỉ số kiểm tra tính toàn vẹn riêng, song song với NL/DFT chứ không thay thế.
- **Trạng thái:** đây là phát hiện thực nghiệm từ đối chiếu dữ liệu Test 21, hai chỉ số trên **chưa được cài đặt** trong firmware/`analyze_motor_logs.py` — cần bổ sung nếu muốn đưa vào quy trình kiểm tra thường quy.

#### Phân tích tương quan (n=30, Test 21) — đã hiệu chỉnh sau phản biện

Bản đầu của mục này (tương quan gộp r=±0.90 giữa residual và `BackoffObservedDeltaRaw`/`ApproachObservedDeltaRaw`, kết luận "maneuver giải thích 81% phương sai") **đã bị phản biện và xác minh là kết luận quá mạnh so với bằng chứng** — giữ lại phần dưới đây làm bản đã hiệu chỉnh, kèm nguyên nhân cụ thể.

**1. Tương quan gộp ±0.90 chủ yếu là artefact của phân nhóm A1/B/A2 (ecological correlation / Simpson's paradox), không phải quan hệ nhân quả trong cùng cơ chế:**

| Thông số | r toàn cục (30 run) | r trong-leg (đã demean theo leg) |
|---|---:|---:|
| `BackoffObservedDeltaRaw` | −0.902 | **+0.022** |
| `ApproachObservedDeltaRaw` | +0.897 | **−0.183** |

Tương quan gần như biến mất khi kiểm soát leg. Theo từng leg riêng, dấu tương quan cũng đảo chiều không nhất quán (A1: −0.76/+0.47; B: +0.08/−0.31; A2: +0.57/−0.63) — nếu backoff/forward có quan hệ nhân quả đơn điệu thật sự, dấu phải ổn định giữa các leg. Kết luận đúng mức bằng chứng hiện có chỉ là: **cấu hình leg B (feedforward bias 100/136) làm residual tăng**, chưa chứng minh được backoff hay forward là biến quyết định.

**2. `BackoffObservedDeltaRaw` và `ApproachObservedDeltaRaw` gần như cùng một biến ẩn, không phải hai bằng chứng độc lập:** r(Backoff, Approach) = **−0.998** trên toàn bộ 30 run — vì bias 100/136 luôn được bật/tắt cùng nhau theo leg. Không thể tách ai trong hai biến "giải thích 81%" — cả hai chỉ đang đại diện cho biến nhị phân "feedforward ON/OFF".

**3. Trình tự chuyển động: B0-B backoff/forward chạy *trước khi xác lập điểm 0*, không phải ngay trước điểm 360+i** (`Core/Src/nonlinear_test.c:3083` cho maneuver, `:3163` cho xác lập origin). Diễn giải đúng hơn: feedforward B tạo ra trạng thái ban đầu/load-angle/hysteresis khác tại điểm 0, khiến lần đi qua đầu (điểm 1–10) và lần đi qua sau một vòng (điểm 361–370) không tương đương — chứ không phải "maneuver B0-B trực tiếp tạo ra điểm 361–370".

**4. "Approach quality" không phải tên đúng cho cơ chế:** leg B có endpoint chính xác hơn (Return error MAE 13.4 raw so với ~32 raw của A-bracket; closure tốt hơn 0.257° so với ~0.362°) nhưng residual lại **tệ hơn** (~0.35° so với ~0.24° RMS). Vậy không phải "endpoint càng chính xác thì residual càng nhỏ" — nhiều khả năng liên quan hành trình/năng lượng maneuver, trạng thái tải rotor sau reversal, hoặc hysteresis, không phải độ chính xác điểm dừng.

**5. Về sóng hài điện/cogging (H36):** tương quan yếu (−0.21) với biên độ H36 chỉ loại được giả thuyết hẹp "residual tăng trực tiếp theo biên độ H36". Chưa loại được ảnh hưởng pha H36, cogging phụ thuộc load-angle, hay tương tác cogging×reversal/backlash. Biên độ H36 cũng biến thiên rất ít giữa các run (restricted range) nên hệ số tương quan thấp không đủ để kết luận "không liên quan".

**6. Closure-probe (`ClosureProbeDelta50/100/200InitialDeg`, r≈0) chỉ loại được giả thuyết hẹp "trôi chậm khi đứng yên"**, không loại được ma sát phụ thuộc vận tốc, hysteresis khi đảo chiều, hay sai lệch sinh ra trong ramp 360→361 (closure-probe đo trạng thái đứng yên; residual hậu vòng được quan sát khi motor chuyển động trở lại — hai điều kiện động học khác nhau).

**7. Phát hiện thêm — bug thật trong tooling, không phải trong dữ liệu (đã sửa):** giá trị `ClosureErrorDeg` lấy từ `analysis-out/test21-nl-stability/official_analyzer.csv` **không phải** `Error[360]-Error[0]`. Trong `scripts/analyze_nonlinear_logs.ps1` (schema v5, đúng trường hợp Test 21), script rơi vào nhánh fallback hardcode `256`:
```powershell
} elseif ($null -ne $dataErrors[0] -and $null -ne $dataErrors[256]) {
    $closureErrorDeg = [double]$dataErrors[256] - [double]$dataErrors[0]   # index 256, di sản giao thức cũ
    $closureMeaning = 'DIAGNOSTIC_SCHEMA_V5_PILOT'
}
```
Đây là **cùng một lỗi di sản index-256** đã ghi nhận ở `tools/analyze_motor_logs.py` (mục ghi chú "256 điểm" phía trên), nhưng ảnh hưởng nghiêm trọng hơn: nó âm thầm gán sai giá trị cho cột `ClosureErrorDeg` thay vì chỉ dùng sai số điểm phân tích. Đã xác minh trực tiếp: `Error[256]-Error[0]` khớp tuyệt đối (diff ≈ 0.00000) với cột CSV trên cả 30 run.

**Đã sửa** (`scripts/analyze_nonlinear_logs.ps1:810-822`): index đóng vòng giờ lấy động từ `META.AnalysisPoints` (giống cách script đã làm cho `CLOSURE_PROBE` từ trước), thay vì hardcode 256. Fixture cũ (256-điểm, `v6-p03-jig1/2.txt`, `AnalysisPoints=256`) không đổi hành vi; log 360-điểm (Test 21, `AnalysisPoints=360`) giờ tính đúng closure tại điểm 360. Đã thêm fixture regression `scripts/fixtures/schema-v5-360grid-closure-p03-jig1.txt` (khai báo `AnalysisPoints=360`, cố ý đặt giá trị rất khác tại điểm 256 để lộ ngay nếu ai đó hardcode lại 256) và assertion tương ứng trong `scripts/test_analyze_nonlinear_logs.ps1` — đã xác minh test fail đúng như kỳ vọng khi tạm revert fix, và pass sau khi khôi phục. Toàn bộ 8 test suite liên quan (`test_phase1_baseline_integrity`, `test_analyze_nonlinear_logs`, `test_adaptive_precondition_contract`, `test_phase2b_shadow_contract`, `test_phase3b0_equal_approach_contract`, `test_preconditioned_10run_contract`, `test_phase3a_motion_contract`, `test_phase3b0_closure_probe_contract`) pass sau khi sửa.

Giá trị `ClosureErrorDeg` trên Test 21 sau khi sửa (leg A1/B/A2): −0.368°/−0.255°/−0.354° — khớp với số độc lập trong `b0b_test21_assessment.md` (0.3701/0.2568/0.3547, vốn đã tính đúng qua pipeline Python riêng). Tương quan với residual RMS tăng từ +0.662 (bug) lên **+0.898** (đã sửa).

**Quy ước dấu — nguồn nhầm lẫn ban đầu giữa hai hệ số +0.898 và −0.887:** hai bên đã tính đúng, chỉ khác quy ước dấu của closure:

| Field | Định nghĩa | Quy ước dấu |
|---|---|---|
| `DATA.ErrorDeg` (mọi điểm, kể cả fallback `ClosureErrorDeg` schema v5) | `Target − Measured` | `TARGET_MINUS_MEASURED` (`Core/Src/nonlinear_test.c:3343`) |
| `ShadowClosureErrorDeg` (canonical, `SHADOW_RESULT`) | `Measured − Target` | `MEASURED_MINUS_TARGET` (`NL_SHADOW_SIGN_CONVENTION`, `Core/Src/nonlinear_test.c:169`) |
| Schema v6 canonical closure | `Measured − Target` | `MEASURED_MINUS_TARGET` |

Do đó `r(legacy ClosureErrorDeg, residual RMS) ≈ +0.898` và `r(ShadowClosureErrorDeg, residual RMS) ≈ −0.887` **đều đúng** và gần đối dấu như kỳ vọng; chênh lệch nhỏ về độ lớn (0.898 so với 0.887) đến từ việc legacy DATA và shadow canonical dùng pipeline lấy mẫu/reference khác nhau (canonical dùng `POINT0_CANONICAL_MEAN` làm reference, không phải điểm 0 đơn lẻ của legacy). Khi trích dẫn hệ số tương quan liên quan đến closure, cần nêu rõ đang dùng field nào (`ClosureErrorDeg` legacy hay `ShadowClosureErrorDeg` canonical) vì dấu sẽ ngược nhau.

**Kết luận có thể khẳng định với bằng chứng hiện có:**
- Cấu hình feedforward B (100/136 raw) làm residual hậu vòng tăng rõ rệt so với baseline A.
- H36 amplitude toàn cục và stationary relaxation (đứng yên sau khi dừng) không giải thích được sự phân nhóm A–B–A.
- Nhiều khả năng nguyên nhân nằm ở trạng thái động lực học ban đầu do feedforward/maneuver tạo ra tại điểm 0, ảnh hưởng lan tới cả lần đi qua đầu và lần đi qua sau một vòng — nhưng đây vẫn là kết luận ở mức hệ thống (whole-system).

**Chưa thể khẳng định:**
- Backoff hay forward là nguyên nhân riêng lẻ (r=−0.998 giữa hai biến khiến không thể tách).
- Chúng "giải thích 81% phương sai" theo nghĩa nhân quả (số này chỉ phản ánh phân nhóm leg).
- Cogging pha/load-angle và toàn bộ các dạng relaxation (ma sát phụ thuộc vận tốc, hysteresis đảo chiều) đã bị loại.
- Endpoint tracking tốt hơn sẽ làm residual tốt hơn (bằng chứng leg B cho thấy điều ngược lại).

**Thiết kế thực nghiệm xác nhận đề xuất tiếp theo** (chưa thực hiện):
1. Giữ forward cố định, chỉ đổi backoff bias: 0 → 79 → 100 raw.
2. Giữ backoff cố định, chỉ đổi forward bias: 0 → 126 → 136 raw.
3. Ngẫu nhiên hóa/xen kẽ thứ tự chạy để tránh nhiễu do trôi theo thời gian.
4. Đo cả endpoint error lẫn `PostTurnRepeatDelta`/`ClosureNormalizedDelta`.
5. Phân tích bằng tương quan trong-từng-cấu-hình hoặc hồi quy có biến leg — không dùng Pearson gộp đơn thuần trên dữ liệu đã phân nhóm theo thiết kế thí nghiệm (A-B-A).

Bias 79/126 raw (ước tính từ `b0b_test21_assessment.md`) vẫn là ứng viên hợp lý cho lần thử tiếp theo, nhưng mục tiêu thí nghiệm phải là kiểm tra residual có giảm *theo mức* bias hay chỉ thay đổi *theo trạng thái* protocol (ON/OFF).

### Cổng hợp lệ chính thức (Official validity gate)
```
OfficialMeasurementValid = ConfigValid && AcquisitionComplete && AllRequiredPointsValid
  && SettleValid && TrackingValid && ClosureValid
  && ContextReacquireCount==0 && MotorFaultCount==0
```
Firmware thực tế dùng `measurementValid = structuralValid && trackingValid` (yêu cầu đủ 360 điểm phân tích, tất cả settle-valid). `ClosureValid` **chưa** được đưa vào cổng chính thức (chỉ tương quan 0.99633 với sai số điểm 256, giao thức trạng thái vật lý chưa chốt).

---

## A3 — Căn chỉnh quỹ đạo pha (rotating-capture)

File: `Core/Src/control_engine.c`, `analysis/matlab/a3/analyze_a3_batch.m`.

### Thông số đo
- ElectricalOffsetRaw (vị trí ổn định cuối, mod chu kỳ điện = 10923 raw)
- Drag lag (mean/max, raw)
- Ramp creep (raw)
- Hành trình/bước tối đa (milli-deg)
- Cờ phát hiện capture

### Ngưỡng pass/fail
- Circular range của `FinalOffsetRaw` ≤ 182.0 raw
- Circular resultant R ≥ 0.99
- Không có run lỗi (zero fault runs)
- Tỷ lệ phát hiện capture = 100% trong các run OK
- Số run OK ≥ 5

Tham chiếu lịch sử đã kiểm chứng: mean 6742.1 raw, SD 81.3 raw, range 210 raw, R≈0.999 trên 8 run OK (2/10 lỗi `SAMPLE_STEP_LIMIT`).

---

## A4 / A4B — Kéo lệch có mồi từ encoder (encoder-seeded drag-alignment)

File: `Core/Src/control_engine.c` (profile `CONTROL_A4B_ENCODER_SEEDED_DRAG_P35_OFFSET7971_V1`), `analysis/matlab/a4/`.

### Hằng số cấu hình

| Thông số | Giá trị | Đơn vị |
|---|---|---|
| Offset điện | 7971 | raw |
| Công suất target | 350000 (350‰) | ppm |
| Số tick ramp công suất | 300 | ticks |
| Số tick quét đầy đủ | 2400 | ticks |
| Số tick giữ (hold) | 500 | ticks |
| Thời gian hoạt động tối đa | 4000 | ms |
| Số tick quét tối thiểu | 240 | ticks |
| Ngưỡng span đã căn (already-aligned) | 210 | raw |
| Span tối thiểu để yêu cầu capture | 1000 | raw |
| Hệ số decimation evidence | 3× | — |
| Bước nhảy tối đa khi thu thập | 1821 | raw |
| **Hành trình tối đa (hard gate)** | **12000** | raw |
| **Bước mẫu-tới-mẫu tối đa (hard gate)** | **150** | raw |
| Số mẫu bị bỏ lỡ liên tiếp tối đa | 3 | count |
| Cửa sổ capture | 100 | ticks |
| Field tối thiểu để capture | 60 | raw |
| Drag-loss lag | 2731 | raw |

Lỗi báo cáo: `TRAVEL_LIMIT`, `SAMPLE_STEP_LIMIT`.

### Thông số tính toán
- SeedPhaseRaw so với kỳ vọng
- SweepSpanRaw so với kỳ vọng
- SweepTicks / EvidenceCount so với kỳ vọng (khớp chính xác, dung sai `<1e-6`)
- FinalOffsetRaw
- RampMaxStepRawEvidence, SweepMaxStepRawEvidence
- HoldTail20P2PRaw (P2P của 20 mẫu cuối trong pha giữ)
- DragLagMean / DragLagMax (raw)

### Ngưỡng pass/fail
- ≥ 5 run, tất cả `Valid` (khớp profile + Result=OK + capture nhất quán + khớp mọi giá trị kỳ vọng), tất cả Result=OK
- Bao phủ ≥ 4/4 góc phần tư điện (electrical quadrants)
- Circular range của FinalOffsetRaw ≤ 182.0 raw

---

## A5 — Ổn định góc thô tĩnh (MA600 static RawAngle stability)

File: `Core/Inc/control_a5_math.h`, `Core/Src/control_a5_capture.c`, `analysis/matlab/a5/`.

### Hằng số cấu hình

| Thông số | Giá trị | Đơn vị |
|---|---|---|
| Số mẫu | 2048 | samples |
| Tần số lấy mẫu | 1000 | Hz |
| Chu kỳ | 1 | ms |
| Cửa sổ capture | 2048 | ms |
| Số lần đọc thử | 1 | — |
| Offset điện (từ A4B) | 7971 | raw |
| Pha lệnh | 0 | raw |
| Công suất lệnh | 350000 | ppm |
| Bước nhảy unwrap tối đa | 1821 | raw |
| **Bước mẫu tối đa (hard gate)** | **150** | raw |
| **Hành trình tĩnh tối đa (hard gate)** | **210** | raw |
| Thời gian capture tối đa | 2300 | ms |
| Heap trống tối thiểu sau cấp buffer | 64 | KB |
| Số bin pha PWM | 32 | bins |

Lỗi: `CONTROL_A5_SAMPLE_STEP_LIMIT`, `CONTROL_A5_STATIC_TRAVEL_LIMIT`.

### Thông số tính toán
- P2P (raw)
- Drift (đầu-đến-cuối, raw)
- Độ lệch chuẩn quần thể (population SD)
- RMS tương đối
- Median, MAD → robust sigma (= 1.4826 × MAD)
- Độ dốc trôi tuyến tính (raw/mẫu và raw/s)
- SD sau khi loại xu hướng (detrended SD)
- Bước nhảy tuyệt đối tối đa
- Tự tương quan & Allan deviation (overlapping) tại τ ∈ {1, 2, 4, 8, 16, 32, 64, 128} mẫu
- Kiểm tra toàn vẹn RawCRC32

### Dải pass đã chốt (`docs/control-a5-checklist.md`, profile `CONTROL_A5_MA600_RAW_HOLD_P35_OFFSET7971_N2048_1KHZ_V1`, trạng thái A5.6 COMPLETE)

| Chỉ số | Dải quan sát | Giới hạn dải |
|---|---|---|
| P2P (raw / deg) | 11–16 (0.060–0.088°) | ≤ 32 raw |
| SD quần thể (raw / deg) | 1.63–2.16 (0.009–0.012°) | ≤ 5 raw |
| Drift đầu-cuối (raw / deg) | −4..+6 (−0.022..+0.033°) | ≤ 16 raw |
| PwmFirstHarmonicP2PRaw | 0.075–0.16 raw | < 1.5% ngân sách P2P |

---

## B0-B — Tiếp cận điểm đóng (backoff/forward), creep, feedforward, soft-start

File: `Core/Src/nonlinear_test.c` (`NL_B0B_*`), `analysis/matlab/b0b/`.

### Hằng số cấu hình

| Thông số | Giá trị | Đơn vị |
|---|---|---|
| Target backoff/forward tiếp cận | 182 | raw |
| Trễ soft-start tiếp cận | 4 | ms |
| Deadband target | 16 | raw |
| Bước creep | 8 | raw |
| Deadband creep (= deadband target) | 16 | raw |
| **Tổng hiệu chỉnh creep tối đa (safety cap)** | **150** | raw |
| **Số lần lặp creep tối đa** | **30** | count |
| Bias feedforward backoff | 100 | raw |
| Bias feedforward forward | 136 | raw |
| Độ lệch lệnh tối đa | 500 | raw |

Protocol: `SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`.

### Thông số đo/tính toán
- BackoffObservedDeltaRaw / ApproachObservedDeltaRaw (biểu diễn theo % của target = 182 raw)
- Số lần lặp creep và tổng hiệu chỉnh creep (raw), theo từng nhánh (leg)
- Dạng lag bám theo từng tick so với đường cong S bậc 5 (quintic) tái tạo phân tích (40 tick, 1 ms/tick) — % đã bám và lag (raw) tại các mốc {1,5,10,15,20,25,30,35,40}
- Thống kê batch tiền điều kiện: số chu kỳ khai báo vs quan sát, `PreconditionRunsUsed`, `PreconditionValid`, `PreconditionStabilityDeltaDeg`

Tham chiếu lịch sử Phase-A (đã kiểm chứng qua MATLAB): tick 15 BACKOFF 35.4%/32.4 raw, FORWARD 18.5%/40.8 raw; tick 40 BACKOFF 57.4%/77.4 raw, FORWARD 38.5%/111.9 raw.

---

## Phân tích độ lặp lại / xu hướng NL (`tools/analyze_nl_stability.py`)

Tính theo từng run và gộp qua các leg (A1→B→A2):
- Mean, SD mẫu, CV%, median, MAD → robust sigma
- Min/max/range
- **Giới hạn lặp lại = 2.77 × SD** (chẩn đoán kiểu ISO 5725, **không** phải tuyên bố pass theo chuẩn ISO)
- Độ dốc trôi tuyến tính (deg/run) với khoảng tin cậy 95% (phân phối t), R²
- Đối chiếu chéo NL/RMS_AC/A36 tính lại so với giá trị firmware báo cáo (chỉ báo cáo `max |tính lại − firmware|`, không có ngưỡng pass cố định)

### Self-test
`run_self_test()` trong `tools/analyze_motor_logs.py` tái tạo lại toán DFT của firmware để chứng minh bản Python khớp hành vi bit-for-bit với `ComputeHarmonicFull`/`ComputeSweepStats` trong `nonlinear_test.c`, dung sai `tol=0.01`.

---

## Chỉ mục file/dòng tham chiếu

- `Core/Src/nonlinear_test.c` — toàn bộ hằng số firmware A2/B0-B và logic hợp lệ (dòng 55–215, 428–750, 2415–2520, 3540–3710)
- `Core/Src/control_engine.c` — hằng số A3/A4/A4B và mã lỗi (dòng 24–102, 126–127, 310–311, 601–607)
- `Core/Inc/control_a5_math.h` / `Core/Src/control_a5_capture.c` — hằng số và mã lỗi A5
- [nonlinear-metric-contract-v1.md](nonlinear-metric-contract-v1.md) — hợp đồng công thức/hợp lệ chuẩn (làm tròn Q16, closure, settle, DFT, công thức hợp lệ chính thức)
- [control-a5-checklist.md](control-a5-checklist.md) — dải pass A5 đã chốt và lịch sử cổng kiểm tra
- `tools/analyze_motor_logs.py`, `tools/analyze_nl_stability.py`, `tools/analyze_one_turn_pattern.py` — phân tích lại bằng Python, độ lặp lại, tái tạo họ sóng hài
- `scripts/analyze_control_a4.ps1`, `scripts/analyze_control_a5.ps1`, `scripts/analyze_nonlinear_logs.ps1` — triển khai tham chiếu PowerShell (ngưỡng chuẩn: `$FinalOffsetRangeLimitRaw=182.0`; closure `-le 0.20`)
- `analysis/matlab/*.m`, `analysis/matlab/{a3,a4,a5,b0b}/*.m` — bộ MATLAB kiểm tra chéo độc lập, thống kê vòng tròn, kiểm định significance, bao an toàn, fit mô-men hồi phục
