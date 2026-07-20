# Plan A3 — Alignment bằng phase trajectory (rotating capture + drag)

## Bối cảnh

Chuỗi A2..A2F (35 run vật lý) đã đóng sổ hướng fixed-phase với đầy đủ bằng
chứng (`docs/control-a2f-p09-result.md`): không tồn tại mức power tĩnh nào
vừa an toàn vừa tạo hội tụ — ma sát tĩnh ~9-10% torque max, ma sát động ~4%,
và hướng di chuyển thực tế vô tương quan với hướng kéo của field. Quyết định
đã chốt: alignment phải dùng **quỹ đạo phase chuyển động**.

Cơ sở tin cậy: measurement image chứng minh rotor bám quỹ đạo phase S-curve
với lag chỉ 60-130 raw ở full power (Motion V2), và `LockStartPosition`
chính là một phase-trajectory alignment đang chạy ổn định.

## Nguyên lý A3 và vì sao nó né được bế tắc stick-slip

Fixed-phase bắt rotor nhảy một lần qua toàn bộ khoảng cách (snap lớn, không
kiểm soát). Phase trajectory làm ngược lại: **field tự đi đến chỗ rotor** rồi
kéo đi. Khi field quét qua equilibrium của rotor, độ lệch lúc "break" chỉ là
`asin(mu_s/P)` và cú giật giải phóng chỉ còn:

```text
jolt_elec ~ asin(mu_s/P) - asin(mu_k/P)     (mu_s~0.10, mu_k~0.04)

P=20%:  30.0 - 11.5 = 18.5 deg elec ~ 3.1 deg mech (~560 raw)
P=35%:  16.6 -  6.6 = 10.0 deg elec ~ 1.7 deg mech (~305 raw)
P=50%:  11.5 -  4.6 =  6.9 deg elec ~ 1.2 deg mech (~210 raw)
```

Ngược với fixed-phase: **power càng cao, cú giật capture càng NHỎ**. Sau
capture, rotor bám field với lag động ~`asin(mu_k/P)` (P35: ~6.6° điện) —
đúng chế độ mà sweep measurement đã chạy hàng nghìn segment không lỗi.

## Profile đề xuất

`CONTROL_A3_ROTATING_CAPTURE_P35_V1` — một biến duy nhất so với A2F:
phase không đứng yên mà quét đúng **một chu kỳ điện** bằng S-curve.

| Thuộc tính | Giá trị | Ghi chú |
| --- | ---: | --- |
| Power | 35% | tiền lệ home C0; jolt capture ~305 raw; không dùng vùng 6-9% đã chứng minh vô hiệu |
| Pha 1: power ramp | 0→35% trong 300 ms, phase giữ 0 | mini-A2, creep ≤~1° đã biết trước, gate phủ được |
| Pha 2: phase sweep | 0 → 10923 raw (1 chu kỳ điện = 60° cơ) bằng quintic smoothstep, 40 ms/độ-cơ → 2400 ms | cùng cadence Motion V2 đã được chứng minh; kết thúc tại 10923 ≡ phase 0 |
| Pha 3: hold | 500 ms @ 35%, phase ≡ 0 | đo settle + equilibrium |
| Kết thúc | disable → dump UART | giữ nguyên khung A2F |
| Loop | 1 ms, encoder mỗi tick | giữ nguyên |

Capture được **bảo đảm trong một chu kỳ**: field quét qua mọi góc điện đúng
một lần, nên bắt buộc đi qua equilibrium của rotor dù rotor ở bất kỳ đâu —
không cần biết electrical offset trước.

## Guard — phải nới có chủ đích so với A2F (ghi rõ lý do, không im lặng)

| Guard | A2F | A3 đề xuất | Lý do |
| --- | ---: | ---: | --- |
| MAX_TRAVEL | 910 raw (5°) | 12000 raw (~66°) | kéo tối đa 1 chu kỳ = 60° cơ + creep/margin |
| MAX_SAMPLE_STEP | 45 raw/ms | 150 raw/ms | jolt capture ~305 raw giải phóng trong ~10-30 ms → đỉnh ước 30-100 raw/ms; 150 là trần an toàn có suy luận |
| MAX_ACTIVE | 1200 ms | 4000 ms | 300+2400+500 ms + margin |
| Deadline 3-miss, abort nút lần 2, prime-audit-enable, disable-trước-UART | giữ nguyên | giữ nguyên | khung đã chạy hoàn hảo 35/35 run |

## Evidence budget (ràng buộc CCM 64 KB)

~3200 tick active > 1001 slot kiểu A2F. Giữ loop + guard full-rate 1 ms,
**decimate evidence ×3** (ghi mỗi 3 tick) → ~1067 record ≈ 51 KB CCM, ngang
A2F. Ghi thêm vào mỗi record: `CommandElectricalRaw` hiện hành (field đang ở
đâu) — bắt buộc để phân tích capture/lag. Log thêm summary:
`CaptureSeq`, `DragLagMeanRaw`, `DragLagMaxRaw`, `SettledModuloRaw`,
`ElectricalOffsetRaw` (xem dưới).

## Sản phẩm phụ quan trọng: electrical offset

Sau khi hold ổn định, rotor nằm tại equilibrium của phase 0 →
`ElectricalOffsetRaw = (encoder raw lúc settle) mod 10923`. Đây là hằng số
hiệu chuẩn encoder↔điện của cặp motor+gá, mở đường cho A4 (alignment êm
seed từ encoder, khởi phát zero-torque) và xa hơn là sensored commutation.
In ra summary mỗi run; 5 run phải cho cùng giá trị trong ±1 noise band.

## Trình tự test trên jig

1. Build Control image, flash, lưu manifest (`AppProfile=CONTROL_A3_...`).
2. Run 1: quan sát an toàn (motor 60° xoay trơn? có kẹt cáp/tải không?).
3. Nếu run 1 sạch: thêm ≥4 run, **xoay rotor bằng tay sang vị trí ngẫu
   nhiên giữa các run** (như A2F) để phủ start phase.
4. Nhấn nút lần hai để abort nếu thấy giật bất thường.
5. Lưu đủ log + commit SHA + hex SHA-256, phân tích rồi mới bàn tiếp.

## Phân tích & acceptance

Tool: mở rộng `analyze_control_a2.ps1` hoặc `analyze_control_a3.ps1` mới:

- `CaptureSeq`: seq đầu tiên rotor-velocity ≥ 50% field-velocity giữ ≥100 ms;
- Drag lag = field phase − rotor điện (sau capture), mean/max;
- Settled modulo + circular stats (tái dùng máy móc A2 sẵn có);
- So `ElectricalOffsetRaw` giữa các run.

**Acceptance A3 (mục tiêu alignment):** trên ≥5 run start phase ngẫu nhiên —
capture 5/5; settled modulo circular range ≤ 182 raw (1° cơ) và R ≥ 0.99;
`ElectricalOffsetRaw` trùng nhau trong noise band; 0 hard gate.

## Decision tree

- **Capture fail** (rotor không bám field ở P35) → một escalation duy nhất:
  P50, profile ID mới. Không dò từng 1%.
- **Slip giữa chừng** (bám rồi tuột) → giảm tốc độ sweep (40→80 ms/độ) trước
  khi tăng power — slip là vấn đề tốc độ/lag, không phải thiếu lực break.
- **Pass** → A4 (encoder-seeded gentle alignment dùng offset vừa đo) và/hoặc
  chuyển sang thiết kế tracking closed-loop; đồng thời phản hồi insight sang
  measurement line (B0-B warm approach cùng bản chất "kéo khi đang ấm").

## Ngoài phạm vi (giữ kỷ luật một-biến)

- Không đụng measurement image, không đụng PID/home controller.
- Không tuning P/I/D, không thêm chế độ tracking trong cùng firmware này.
- Không đổi đồng thời power và tốc độ sweep trong một lần đổi profile.
- MATLAB pipeline mở rộng cho A3 là việc riêng sau khi có log thật.
