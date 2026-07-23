# Kết quả A2F — P09 hoàn tất power envelope, đóng sổ fixed-phase

## Dataset và integrity

- Firmware: `CONTROL_A2F_FIXED_PHASE_ALIGN_P09_H500_V1` (commit `1eead32`),
  Control image, phase điện cố định = 0, power ramp 0→9%/500 ms + hold 9%/500 ms.
- Log: `A2F test 1.txt` … `A2F test 5.txt` (5 run vật lý, 5 start phase khác
  nhau do xoay rotor bằng tay giữa các run), mỗi log 1001 evidence @ 1 kHz.
- Phân tích bằng tool chuẩn `scripts/analyze_control_a2.ps1` (5/5 parse OK)
  + tổng hợp chéo run (onset power, hướng di chuyển vs hướng kéo của field).
- Health cả 5 run: `DeadlineMisses=0`, `Retries=0`, `TransportErrors=0`,
  `JumpRejects=0`, `FailedSamples=0`; loop 17.28 µs, SPI 7.95 µs.
- `Result=OK`, `HardGatePass=True` cả 5 run; `MaxAbsStepRaw` ≤ 12
  (gate 45) — **không có run nào chạm bất kỳ gate nào**.

## Kết quả theo run

| Run | BaselineRaw | Start modulo (raw) | Góc điện vs phase 0 | sin (torque khả dụng) | Di chuyển cuối | Onset chuyển động |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 35203 | 2434 | 80.2° | **0.99** | **0 raw** | không có |
| 2 | 5924 | 5924 | 195.2° | −0.26 | +144 raw (0.79°) | ~4.1% power |
| 3 | 60708 | 6093 | 200.8° | −0.36 | +145 raw (0.80°) | ~4.1% |
| 4 | 47961 | 4269 | 140.7° | +0.63 | +148 raw (0.81°) | ~4.2% |
| 5 | 37041 | 4272 | 140.8° | +0.63 | +236 raw (1.30°) | ~3.8% |

Circular stats (tool chuẩn): mean = 4813.82 raw, **range = 3803.83 raw
= 20.9° cơ**, R = 0.7184 (n = 5). R cao hơn P06-P08 chủ yếu vì start phase
của run 4/5 và 2/3 trùng cụm nhau, không phải vì lực kéo hội tụ.

## Ba sự thật quyết định

1. **Hướng di chuyển không tuân theo hướng kéo của từ trường.** Cả 4 run có
   chuyển động đều đi cùng chiều dương, dù run 2/3 xuất phát ở 195-201° điện
   và run 4/5 ở 141° điện — hai phía ngược nhau của equilibrium. Không có quy
   ước dấu encoder↔điện nào khớp được cả 4 run (một quy ước khớp run 2/3,
   quy ước ngược lại khớp run 4/5). Chuyển động ~0.8° là creep do địa hình
   ma sát/detent cục bộ, không phải hành vi tìm equilibrium.

2. **Run có torque tốt nhất đứng im tuyệt đối.** Run 1 ở 80.2° điện (99%
   torque khả dụng, gần đúng góc 90° tối ưu) không nhúc nhích
   (Baseline = Final = 35203, mọi dao động ±14 raw có mặt từ lúc power = 0
   → noise band); trong khi run 2 chỉ có 26% torque lại đi 0.79°. Đáp ứng
   do vị trí quyết định, không do độ lớn lệnh.

3. **Onset ~4% power ở cả 4 run có chuyển động** — khớp ước lượng ma sát
   động 3.5-7.5% suy độc lập từ lag ổn định 60-130 raw của sweep S-curve
   100% power bên measurement image. Hai dataset độc lập cùng chỉ một bộ
   hằng số vật lý:

   | Đại lượng | Ước lượng | Nguồn |
   | --- | ---: | --- |
   | Ma sát động | ~4% torque max | onset A2F + lag sweep measurement |
   | Ma sát tĩnh | ~9-10% torque max | run 1 không break ở 8.9%; P10 snap ở 10% |

   Static >> kinetic → cấu trúc stick-slip: dưới ~9% không break được; vừa
   break (10%) thì torque thừa ~5-6% → snap (đúng `SAMPLE_STEP_LIMIT` của
   P10). **Cửa sổ "hội tụ êm" cho fixed-phase không tồn tại.**

## Bản đồ power envelope cuối cùng

```text
P06: 3/5 run có chuyển động, không hội tụ (range 40.4°)
P07: 5/5 di chuyển, không hội tụ (range 38.3°)
P08: 5/5 safe, không hội tụ (range 31.2°)
P09: 5/5 safe, không hội tụ (range 20.9°), hướng đi vô tương quan với lệnh   <- A2F
P10: SAMPLE_STEP_LIMIT (snap >50 raw/ms)
```

## Quyết định

Điều kiện đặt trước trong `docs/matlab-a2-a2e-analysis-result.md` đã kích
hoạt đầy đủ: *P09 safe nhưng circular range >> tolerance 1°* →

- **DỪNG fixed-phase power search. Không chạy P10/P11.**
- **Chuyển sang alignment có phase trajectory** (profile A3).

Không được diễn giải "5/5 HardGatePass" của A2F là alignment thành công —
gate chỉ chứng minh an toàn, không chứng minh authority.

## Định hướng thiết kế A3 (phase trajectory)

Bằng chứng phía measurement image đã chỉ sẵn: rotor bám quỹ đạo phase
**chuyển động** rất tốt (S-curve sweep lag chỉ 60-130 raw ở full power), và
`LockStartPosition` của measurement image thực chất là một phase-trajectory
alignment đang chạy ổn định (S-curve về phase-zero gần nhất, 100% power).
Khuyến nghị cho A3:

- Quét phase bằng S-curve (quintic như Motion V2) thay vì đứng yên chờ rotor
  tự rơi vào equilibrium;
- Power ở mức đã chứng minh bám được quỹ đạo (tham chiếu measurement image
  dùng 100%; mức thấp hơn cần bracket riêng), không dùng vùng 6-9% đã chứng
  minh vô hiệu;
- Giữ nguyên khung an toàn + evidence 1 kHz của A2F (guard travel/step/
  deadline/duration, prime-audit-enable, một đường thoát disable-trước-UART,
  nhấn nút lần hai để abort) — khung này đã chạy hoàn hảo 5/5 run;
- Đổi profile ID mới theo đúng quy tắc một-biến-một-firmware.

## Tái lập phân tích

```powershell
$logs = Get-ChildItem -Filter 'A2F test *.txt' | Sort-Object Name |
    ForEach-Object { $_.FullName }
& .\scripts\analyze_control_a2.ps1 -LogPath $logs
```

(Onset power và kiểm tra hướng di chuyển vs hướng kéo là phân tích bổ sung
trên các dòng `CONTROL_A2_DATA`; số liệu gốc nằm nguyên trong log.)
