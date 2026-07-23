# Kết quả A5 — MA600 RawAngle static stability: đã khóa

## Đã chứng minh

Trên nền alignment A4B đã đóng băng (offset 7971 raw, forward-only drag),
đo trực tiếp **duy nhất một đại lượng**: giá trị góc thô 16-bit trả về từ
`MA600_ReadRawChecked()`, trong cửa sổ tĩnh 2048 mẫu @ 1kHz (2.048s), phase
điện = 0, power = 35%, không có bất kỳ lệnh động cơ nào trong lúc đo.

**20/20 run vật lý hợp lệ về mặt cấu trúc** (2 batch × 10 run, phủ đủ 4
góc phần tư điện, có 1 cold-start thật ≥15 phút tắt nguồn hoàn toàn, không
tháo gá suốt cả 2 batch):

| Chỉ số | Giá trị quan sát (20 run) | Band ban đầu |
|---|---:|---:|
| P2P trong cửa sổ | 11–16 raw (0.060–0.088°) | ≤32 raw |
| SD (population) | 1.63–2.16 raw (0.009–0.012°) | ≤5 raw |
| Drift đầu-cuối | −4..+6 raw (−0.022..+0.033°) | ≤16 raw |
| SPI latency | cố định 1338 cycles mọi run | — |
| Schedule error tối đa | 74 cycles (~0.44 µs) | — |

Không có retry/transport error/jump-reject/failed-sample/timing-overrun nào
trong toàn bộ 20×2048 = 40.960 mẫu.

## Giới hạn quan sát được (không phải ngưỡng pass/fail sản phẩm)

Theo đúng non-goal đã ghi trong plan ("No product or ISO pass/fail limit
inferred from one pilot batch"), các số trên được khóa lại như **envelope
kỹ thuật quan sát được**, không nâng thành spec chính thức. Dùng để so sánh
cho các phase sau, không dùng để pass/fail sản phẩm.

## PWM-phase, phân bố, drift dài hạn — sạch

- Mọi run phủ đủ 32/32 PWM phase bin → diagnostic có đủ độ phân giải để
  phát hiện tương quan nếu có. `PwmFirstHarmonicP2PRaw` chỉ 0.075–0.16 raw
  (<1.5% tổng P2P) → **không có tương quan PWM-phase đáng kể**.
- Histogram delta mọi run đơn-mode, đối xứng — không có dấu hiệu
  cogging-slip hay xê dịch gá.
- Allan deviation giảm đơn điệu từ 1ms→128ms ở mọi run (ví dụ test10 run1:
  1.84→1.33→0.94→0.68→0.47→0.39→0.23→0.19 raw) — đúng hành vi nhiễu trắng
  khi trung bình hóa, không có sàn flicker/1-per-f hay trôi chạy trốn.

## Cold vs warm — quan sát nhẹ, không phải kết luận cứng

Run cold thật duy nhất (`test7 run1`) có SD=2.16 raw, cao hơn **16.6%** so
với chính run warm ngay sau nó (`test7 run2`, SD=1.85 raw) — và là SD cao
nhất trong toàn bộ 20 run. Đây là dấu hiệu hợp lý của warm-up nhẹ, nhưng
**n=1** và bị confound với việc `test7 run1` cũng là 1 trong 2 mẫu Q2 hiếm
— không đủ để tách bạch "do cold" hay "do quadrant/nhiễu tự nhiên". Không
khóa thành derating, chỉ ghi nhận làm quan sát.

## Kết luận quyết định: sensor không còn là nút thắt

Ghép error budget: SD 1 mẫu thô (~1.92 raw) → sau trung bình 64 mẫu/điểm
(như phép đo NL thật) → nhiễu mỗi điểm ~0.24 raw ≈ 0.0013°. Lan truyền vào
Closure (hiệu 2 điểm) → ~0.0018° lý thuyết.

So với Closure SD thực tế đo trên jig (test16/test17, phiên trước):
**0.016–0.022°** — lớn hơn số lý thuyết từ nhiễu sensor tới **~10 lần**.

→ **MA600 RawAngle đã được đo chính xác và rất sạch; nó không phải nguồn
gây biến thiên Closure còn tồn đọng trong phép đo production.** Phần biến
thiên còn lại (~90%) đến từ nguồn cơ khí/alignment, không phải cảm biến.

## Gate cho tham số MA600 tiếp theo (A5B)

Theo đúng điều kiện đã đặt trong plan ("if the 1kHz result reveals aliasing
or a PWM-phase dependency, a separately versioned A5B... experiment will be
designed"): **điều kiện đó không xảy ra** — không có PWM-phase dependency,
không có dấu hiệu alias. **A5B (đổi sample rate/tham số MA600) không có cơ
sở triệu chứng để triển khai lúc này.** Có thể để đó, không cần làm tiếp trừ
khi có lý do mới.

## Ẩn số còn lại

- Độ ổn định RawAngle tại **các vị trí cơ khí khác** (A5 chỉ đo tại phase-0)
  chưa được xác nhận đồng nhất quanh 360°.
- Độ ổn định trong lúc **đang chuyển động** (không chỉ tĩnh) chưa được đo —
  A5 chỉ đặc trưng hóa trạng thái giữ yên.
- Cold-vs-warm mới có n=1 — chưa đủ để kết luận thống kê.

## Hướng đi tiếp theo (không phải quyết định của tôi — cần bạn chọn)

Với kết luận "sensor không phải nút thắt", hướng có lợi suất cao nhất là
**đưa cơ chế encoder-seeded drag (A4B) sang B0-B protocol của Measurement
image** — nơi vẫn còn open-loop, under-travel 30-77%, và là nguồn khả dĩ
nhất giải thích 90% biến thiên Closure còn lại. Đây là ý tưởng đã đề xuất
một lần và bị từ chối trước đó trong phiên; giờ có bằng chứng ma sát định
lượng mạnh hơn nhiều (từ A2–A5) để làm lại đúng cách.

## Trạng thái

**A5.0 → A5.6: HOÀN TẤT.** RawAngle stability đã khóa. Các phase sau chỉ
cần giữ nguyên gate cấu trúc hiện có (retry/transport/step/travel/safe-stop)
làm health-check, không cần lặp lại đặc trưng hóa thống kê đầy đủ này.
