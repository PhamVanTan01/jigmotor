# B0-B — kết quả closure và approach (test 18–23), tính độc lập bằng MATLAB

Toàn bộ số liệu trong doc này được tính bằng bộ công cụ MATLAB mới
(`analysis/matlab/b0b/`, `analysis/matlab/nl/`) — **độc lập** với
`tools/analyze_nl_stability.py`/`analyze_b0b_transient.py` (không đọc lại
report đã có), cross-check khớp tới ~1e-15 trên `nl_runs.csv`/
`nl_stability.csv` đã tồn tại cho test21/test22. Đây là lần đầu tiên toàn
bộ log B0-B từ test18 tới test23 (kể cả các file A2/lần-2 xác nhận trước
đây bị bỏ sót) được chạy qua cùng một pipeline.

## 1. Soft-start (test 18) — delay=4ms tệ hơn baseline, không nên dùng

`B0BSoftStartProtocol`: A=NONE (1ms/tick), B=SOFT_START_V1 (4ms/tick).
11 run mỗi nhánh (`test 18 A.txt`/`test 18 B.txt`); `test 18.txt` gốc (2
run hợp lệ, protocol=NONE) cho kết quả trùng khớp nhánh A, không phải một
điều kiện thứ ba.

| | BACKOFF tick-40 %tracked | FORWARD tick-40 %tracked |
| --- | ---: | ---: |
| A (1ms/tick) | 51.6% | 34.5% |
| B (4ms/tick) | 47.6% | 31.5% |

Đã xác nhận qua source (`NL_B0B_APPROACH_ACTIVE_DELAY_MS` truyền thẳng vào
`RampCommandToTarget()`, `Core/Src/nonlinear_test.c:2876,2944`) — không
phải hiểu sai tham số. **Kết luận: không adopt delay=4ms.**

## 2. Creep correction (test 19, A→B→A2) — hiệu quả rõ rệt

`B0BCreepProtocol`: NONE (A + A2, n=22) vs ENCODER_CREEP_V1 (B, n=11).

| | NONE (n=22) | ENCODER_CREEP_V1 (n=11) |
| --- | ---: | ---: |
| BACKOFF %-of-target | 53.4% | **93.0%** |
| FORWARD %-of-target | 35.7% | **91.8%** |
| Iterations (mean/max) | 0 | 12.5 / 17.0 (mean), 14 / 19 (max) |

`BackoffObservedDeltaRaw`/`ApproachObservedDeltaRaw` (đã bao gồm hiệu
chỉnh creep) đóng gần hết khoảng trống còn thiếu so với target ±182 raw,
đúng cả 2 leg, nhất quán qua A/B/A2. **Kết luận: giữ/triển khai creep.**

## 3. Adaptive precondition (test 20, A/A2/B) — đúng thiết kế, có bug log

`PreconditionProtocol`: A/A2=ONE_FULL_SWEEP_120S_V1 (1 sweep, xác nhận 2
lần độc lập), B=ADAPTIVE_2CONSECUTIVE_STABLE_V1 (tự động chạy 2 sweep
trước khi coi là ổn định — đúng logic "2 consecutive stable" tối thiểu).

Cả 3 file (A, A2, B) đều gặp cùng một lỗi: dòng `BATCH...Status=COMPLETE`
bị cắt đúng 198 ký tự, mất giá trị `PreconditionStabilityDeltaDeg`. Đã
được fix ở commit `7326373` ("use LogLineLarge for BATCH lines extended
by adaptive precondition") — xác nhận đúng nguyên nhân đã báo.

## 4. NL closure (test 21/22, sản phẩm P03) — KHÔNG đạt 0.20°

Build V2 (`SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`, feedforward bias
79/126 raw). `ClosureErrorDeg` đọc thẳng từ `SHADOW_RESULT` (không phải
suy ra lại), theo đúng định nghĩa canonical trong
`docs/nonlinear-metric-contract-v1.md`.

| Leg | n | Closure mean | Min | Max | Đạt ≤0.20°? |
| --- | ---: | ---: | ---: | ---: | --- |
| test21 A1 | 10 | 0.370° | 0.327° | 0.413° | 0/10 |
| test21 B | 10 | 0.257° | 0.226° | 0.296° | 0/10 |
| test21 A2 | 10 | 0.355° | 0.326° | 0.373° | 0/10 |
| test22 (P03) | 10 | 0.259° | 0.236° | 0.277° | 0/10 |

Không run nào trong 4 batch này đạt ≤0.20°, kể cả batch tốt nhất
(test21 B, min 0.226°).

## 5. NL closure (test 23, đa sản phẩm) — P02/P04/P05/P06 đạt, **P07 không đạt**

Cùng build V2. Mỗi run 10 sweep official (loại 1 sweep precondition).

| Sản phẩm | n | Closure mean | Min | Max | Đạt ≤0.20°? |
| --- | ---: | ---: | ---: | ---: | --- |
| P02 (lần 1) | 10 | +0.0108° | −0.022° | +0.036° | ✅ 10/10 |
| P02 (lần 2) | 10 | +0.0143° | +0.001° | +0.040° | ✅ 10/10 |
| P04 | 10 | +0.0385° | −0.017° | +0.065° | ✅ 10/10 |
| P05 | 10 | −0.0166° | −0.083° | +0.023° | ✅ 10/10 |
| P06 (lần 1) | 10 | −0.1473° | −0.176° | −0.111° | ✅ 10/10 |
| P06 (lần 2) | 10 | −0.1332° | −0.148° | −0.108° | ✅ 10/10 |
| **P07** | 10 | **−0.2465°** | **−0.275°** | **−0.222°** | **❌ 0/10** |

**P07 không đạt mục tiêu pilot 0.20°** — tệ hơn cả P03 (mục 4). P07 trùng
tên với motor 7 pole-pair đang được chuẩn bị gate riêng trong
`docs/motor-7pp-engineering-test-plan.md` (§P7.4: pipeline NL/closure
hiện hardcode cho 6 pole-pair — order-36 folding, 360 điểm — chưa chắc áp
dụng đúng cho 7pp). Cần xác nhận P07 có đúng là motor 7pp trước khi kết
luận đây là lỗi hiệu năng thật hay là artefact của pipeline chưa tương
thích.

## 6. Tổng kết claim "toàn bộ đều dưới 0,20"

**Không chính xác.** 6/8 batch (P02×2, P04, P05, P06×2) đạt; **2/8 batch
không đạt (P03, P07)**, cả hai đều lệch đáng kể (P03 +0.259°, P07 −0.247°,
không phải sai số biên).

## Công cụ

`analysis/matlab/b0b/analyze_b0b_transient.m` (soft-start),
`analyze_b0b_creep.m` (creep), `analyze_b0b_precondition.m`
(precondition), `analysis/matlab/nl/analyze_nl_stability_batch.m`
(closure/NL). Test hồi quy: `analysis/matlab/tests/test_b0b_analysis.m`,
`test_nl_stability_analysis.m`.
