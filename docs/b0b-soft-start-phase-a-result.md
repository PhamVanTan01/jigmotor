# B0-B soft-start — Phase A result (log mining) và thiết kế Phase B

## Bối cảnh

A5.6 kết luận nhiễu MA600 chỉ giải thích ~1/10 độ lệch Closure thực tế
(0.016-0.022°) — phần còn lại nằm ở tầng cơ khí/alignment. Ứng viên rõ nhất:
B0-B (`SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2`) — 2 đoạn lùi/tiến 182 raw
(~1° cơ), mỗi đoạn chỉ 40 tick @ 1ms, tại power=1.0 cố định, hụt quãng
đường 30-77% trong dữ liệu lịch sử.

## Phase A — mine log đã có, không chạy hardware mới

`scripts/analyze_b0b_transient.py` tái tạo lệnh quintic kỳ vọng
(`NlSmoothstepCommandRaw`) và so với vị trí thực đo từng tick (từ
`APPROACH_STEPS`, đã có sẵn trong log), trên **63 lần chạy** mined từ
`p03 jig 1 test 14/14 lần 2/15/16.txt` và `p03 jig 3 test 17/17 lần 2.txt`
— các file duy nhất có `APPROACH_STEPS` (từ khi Motion V2 được đưa vào).

Kết quả:

| Tick | BACKOFF %tracked | BACKOFF lag(raw) | FORWARD %tracked | FORWARD lag(raw) |
|---|---:|---:|---:|---:|
| 15 | 35.4% | 32.4 | 18.5% | 40.8 |
| 25 | 52.1% | 63.2 | 29.3% | 93.3 |
| 30 | 53.6% | 75.7 | 35.0% | 106.0 |
| 35 | 56.4% | 78.1 | 37.4% | 112.2 |
| 40 (cuối) | 57.4% | 77.4 | 38.5% | 111.9 |

**Phát hiện chính**: BACKOFF chững lại (lag raw phẳng) từ tick ~30 — đã bám
song song với lệnh, chỉ còn thiếu quãng đường tích lũy sớm. FORWARD vẫn
đang tăng lag đều tới tick 40 — chưa đạt trạng thái ổn định, và tệ hơn
BACKOFF rõ rệt. Đối chiếu hình dạng với A3/A4 (35% power, cả chu kỳ điện)
xác nhận: lag tự giảm sau khi qua giai đoạn giảm tốc của quintic, nhưng chỉ
sau khi đã đi được ~50% quãng đường — B0-B dừng lại rất xa trước điểm đó.

Đã loại trừ giả thuyết cogging/phụ thuộc vị trí: hình dạng đường lag nhất
quán qua 63 run ở các vị trí tuyệt đối khác nhau — nếu là cogging theo vị
trí, kỳ vọng sẽ thấy phân tán lớn hơn. → xác nhận nguyên nhân là động lực
học thời gian (chưa đủ tick để lag tích lũy), không phải hiệu ứng vị trí.

## Phase B — thiết kế đã triển khai

Một biến duy nhất: chậm cadence chung cho cả 2 đoạn (không đổi quãng đường
182 raw, không đổi power). `NL_B0B_APPROACH_SOFT_START_DELAY_MS = 4U`
(4x hiện tại) là ước lượng đầu có cơ sở — vì FORWARD vẫn chưa chững ở tick
40 với cadence hiện tại, cần margin lớn hơn BACKOFF.

Quyết định: **dùng chung 1 hằng số cho cả 2 đoạn ở lần thử đầu** (đúng
discipline một-biến-một-lần của A2B→A2F/`ENABLE_SWEEP_RAMP_SOFT_START`).
Nếu hardware cho thấy FORWARD vẫn chưa đủ sau khi có log thật, bước tiếp
theo mới tách 2 hằng số riêng (biến thứ hai, đổi độc lập).

Không thêm field mới vào `META` — chỉ còn ~39 byte dư trong buffer 1900
byte của `LogLineLarge` (đo từ log thật), không đủ cho 1 cặp field mới.
Field mới (`B0BSoftStartProtocol`) đặt trong `APPROACH_RESULT` (dư >1100
byte) — đúng chỗ về ngữ nghĩa vì đây là diagnostic riêng của B0-B.

## Build đã lưu (A→B→A trên jig thật)

```text
builds/b0b-soft-start-A-baseline/    (flag=0, hành vi không đổi)
builds/b0b-soft-start-B-delay4ms/    (flag=1, delay=4ms cả 2 đoạn)
```

Flash A → 1 batch → flash B → 1 batch → flash A lại → 1 batch. So sánh
`APPROACH_RESULT.BackoffObservedDeltaRaw`/`ApproachObservedDeltaRaw` (kỳ
vọng tăng rõ, gần 182 hơn) và chạy lại
`scripts/analyze_b0b_transient.py --b0b <log mới>` để xác nhận đúng cơ chế
dự đoán (BACKOFF chững sớm hơn, FORWARD có cải thiện nhưng cần theo dõi kỹ
hơn).

## Không làm trong lần này

- Không tách delay riêng cho từng đoạn (biến thứ hai — để dành nếu cần).
- Không đổi power (giữ 1.0).
- Không đổi quãng đường 182 raw hay ý nghĩa phép đo backoff/forward.
- Không đo J/ma sát tuyệt đối — không cần cho quyết định này.
