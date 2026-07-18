# MATLAB result — A2 đến A2E power-envelope

## Dataset và integrity

- MATLAB: R2025b (`25.2.0.2998904`).
- Input: canonical summary/evidence CSV từ `scripts/analyze_control_a2.ps1`.
- 31 log blocks được đọc; 30 run vật lý được đưa vào thống kê.
- `A2 lần 9 #1` trùng SHA-256 với `A2 lần 8` và bị loại tự động.
- MATLAB recompute khớp PowerShell 31/31 run cho final travel, max step,
  hold drift và settled modulo.

## Kết quả theo profile

| Profile | Power | Run pass | Run moved >0.1° | Max step | Max travel | Settled circular range | R |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| A2C P06/H500 | 6% | 5/5 | 3/5 | 10 raw | 0.286° | 40.374° | 0.183 |
| A2D P07/H500 | 7% | 5/5 | 5/5 | 10 raw | 1.121° | 38.270° | 0.210 |
| A2E P08/H500 | 8% | 5/5 | 5/5 | 10 raw | 0.906° | 31.247° | 0.336 |
| A2B P10/H500 | 10% | 1/2 | 1/2 | 50 raw | 2.296° | không đủ run pass | — |
| A2 P10/H100 | 10% | 11/13 | 8/13 | 52 raw | 5.026° | 48.335° | 0.233 |

`R` gần 1 nghĩa là vị trí dừng tạo một cụm; `R` gần 0 nghĩa là phân tán trên
electrical cycle. Circular range được biểu diễn bằng mechanical degree trong
một electrical cycle 60°.

## Settle sau chuyển động

P06/P07/P08 đều sạch SPI/timing và có max step chỉ 10 raw. Sau khi rotor dừng:

| Power | Max absolute hold drift | Max tail-20 P2P |
| ---: | ---: | ---: |
| 6% | 0.0275° | 0.0439° |
| 7% | 0.0385° | 0.0439° |
| 8% | 0.0604° | 0.0439° |

Như vậy dữ liệu cuối hold khá ổn định; vấn đề không phải SPI noise hay thiếu
thời gian settle. Vấn đề là mỗi start phase dừng tại một vị trí khác nhau.

## Kết luận thuật toán

Tăng 6% -> 7% -> 8% làm tăng khả năng rotor có chuyển động, nhưng không kéo
rotor về một equilibrium chung. P08 cải thiện circular range so với P06, nhưng
31.247° vẫn quá lớn so với diagnostic tolerance 1°. Các điểm trên plot settled
modulo gần như giữ thứ tự và vị trí theo start modulo, cho thấy command fixed
phase chưa tạo đủ authority để xóa điều kiện ban đầu.

Power-envelope an toàn hiện chỉ được bracket:

```text
P08: 5/5 safe
P09: chưa có dữ liệu
P10: đã có SAMPLE_STEP_LIMIT
```

Nếu mục tiêu chỉ là hoàn tất bản đồ ngưỡng power, bước duy nhất còn thiếu là
artifact P09/H500, chạy một run đầu rồi tối đa năm start phase. Gặp một hard
gate thì dừng. Nếu P09 safe nhưng circular range vẫn lớn hơn tolerance, phải
dừng fixed-phase power search và chuyển sang alignment có phase trajectory;
không tiếp tục P10/P11.

Không được gọi P07/P08 là alignment thành công chỉ vì 5/5 run có chuyển động và
hard-gate pass.

## Output

Generated report nằm trong `analysis/output/a2-a2e/matlab/`:

- `matlab-run-metrics.csv`;
- `matlab-profile-summary.csv`;
- `matlab-crosscheck.csv`;
- `matlab-decision.txt`;
- `power-vs-final-travel.png`;
- `power-vs-settled-modulo.png`;
- `runs/*.png`.

Chạy lại bằng:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\run_matlab_a2_analysis.ps1 -RunTests
```
