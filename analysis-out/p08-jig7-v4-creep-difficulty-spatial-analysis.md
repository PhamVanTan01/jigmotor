# P08/JIG7 v4 — phân tích không gian độ khó sweep-point-creep

## Kết luận điều hành

Phần kết luận tự động nằm ở cuối báo cáo sau khi trình bày đầy đủ data-integrity, overlap, correlation và đối chiếu NL. `|MOTION.PositionErrorRaw|` là proxy khe hở **trước creep**, không phải số iteration thật của từng điểm.

## Phương pháp

- Phạm vi phân tích: Point `0..359`.
- Chỉ dùng sweep có `RunRole=OFFICIAL`, `EligibleForStatistics=1`, `END.Status=VALID`.
- Primary: chỉ dùng official sweep đủ toàn bộ MOTION point.
- Sensitivity: dùng thêm official sweep không hoàn chỉnh tại từng point còn tồn tại.
- Difficulty(point): trung bình `abs(PositionErrorRaw)` qua các sweep được dùng.
- Pearson đo độ giống về biên độ; Spearman đo độ giống về thứ hạng điểm khó.

## Data integrity và sanity-check END

| Remount | File | Official khai báo | Official đầy đủ dùng primary | Sweep không đầy đủ |
|---|---|---:|---:|---|
| remount01 | `captured-logs/S2-P08-JIG7-remount01-test-6.txt` | 3 | 3 | Không |
| remount02 | `captured-logs/S2-P08-JIG7-remount02-test-6.txt` | 3 | 3 | Không |
| remount03 | `captured-logs/S2-P08-JIG7-remount03-test-6.txt` | 3 | 2 | TestID 6: thiếu 13 point (280°, 281°, 282°, 283°, 284°, 285°, 286°, 287°, 288°, 289°, 290°, 291°, 292°) |

| Remount | TestID | Complete | Corrected points | Iterations | Correction raw | Timeouts | BudgetExceeded |
|---|---:|---|---:|---:|---:|---:|---:|
| remount01 | 2 | YES | 343 | 2977 | 47632 | 0 | 63 |
| remount01 | 3 | YES | 346 | 2991 | 47856 | 0 | 68 |
| remount01 | 4 | YES | 343 | 2949 | 47184 | 0 | 61 |
| remount02 | 2 | YES | 345 | 2932 | 46912 | 0 | 56 |
| remount02 | 3 | YES | 347 | 2910 | 46560 | 0 | 60 |
| remount02 | 4 | YES | 345 | 2933 | 46928 | 0 | 58 |
| remount03 | 6 | NO | 340 | 2940 | 47040 | 0 | 65 |
| remount03 | 7 | YES | 338 | 2924 | 46784 | 0 | 60 |
| remount03 | 8 | YES | 346 | 2946 | 47136 | 0 | 59 |

Các counter END chỉ là tổng toàn sweep. Chúng được dùng sanity-check, không dùng gán BudgetExceeded cho một góc cụ thể.

## Top điểm khó của từng remount

### remount01

Top 15: 295° (312.7 raw/1.718°), 294° (312.3 raw/1.716°), 174° (293.3 raw/1.611°), 293° (285.3 raw/1.567°), 67° (281.7 raw/1.547°), 334° (279.7 raw/1.536°), 175° (278.7 raw/1.531°), 107° (269.0 raw/1.478°), 254° (268.7 raw/1.476°), 324° (267.0 raw/1.467°), 214° (262.3 raw/1.441°), 106° (261.0 raw/1.434°), 37° (258.0 raw/1.417°), 173° (258.0 raw/1.417°), 36° (257.0 raw/1.412°)

Số điểm `>150 raw`: 126; số điểm `>=220 raw`: 37.

### remount02

Top 15: 294° (318.3 raw/1.749°), 295° (301.7 raw/1.657°), 293° (291.7 raw/1.602°), 174° (286.7 raw/1.575°), 67° (278.7 raw/1.531°), 254° (274.3 raw/1.507°), 334° (272.7 raw/1.498°), 324° (268.7 raw/1.476°), 107° (265.0 raw/1.456°), 66° (262.0 raw/1.439°), 175° (258.3 raw/1.419°), 173° (256.3 raw/1.408°), 0° (256.0 raw/1.406°), 106° (254.0 raw/1.395°), 214° (252.7 raw/1.388°)

Số điểm `>150 raw`: 122; số điểm `>=220 raw`: 33.

### remount03

Top 15: 294° (320.0 raw/1.758°), 295° (305.0 raw/1.675°), 254° (291.5 raw/1.601°), 293° (289.0 raw/1.588°), 174° (286.0 raw/1.571°), 334° (277.0 raw/1.522°), 214° (268.0 raw/1.472°), 253° (266.0 raw/1.461°), 107° (264.5 raw/1.453°), 175° (263.5 raw/1.447°), 324° (261.0 raw/1.434°), 67° (256.5 raw/1.409°), 0° (254.5 raw/1.398°), 284° (254.5 raw/1.398°), 173° (253.5 raw/1.393°)

Số điểm `>150 raw`: 133; số điểm `>=220 raw`: 38.

## Overlap top 10% (36 điểm/remount)

| Cặp | Giao nhau | Jaccard | Trùng trên mỗi tập |
|---|---:|---:|---:|
| remount01 vs remount02 | 33 | 0.846 (84.6%) | 91.7% |
| remount01 vs remount03 | 30 | 0.714 (71.4%) | 83.3% |
| remount02 vs remount03 | 31 | 0.756 (75.6%) | 86.1% |

- Có trong top 10% của cả ba remount: 0°, 27°, 36°, 37°, 54°, 66°, 67°, 76°, 106°, 107°, 173°, 174°, 175°, 213°, 214°, 244°, 253°, 254°, 284°, 292°, 293°, 294°, 295°, 323°, 324°, 333°, 334°, 335°.
- Có trong top 10% của ít nhất 2/3 remount: 0°, 27°, 36°, 37°, 54°, 66°, 67°, 68°, 76°, 77°, 106°, 107°, 108°, 173°, 174°, 175°, 187°, 204°, 213°, 214°, 244°, 253°, 254°, 255°, 263°, 264°, 283°, 284°, 292°, 293°, 294°, 295°, 323°, 324°, 333°, 334°, 335°, 347°.

## Overlap top 15% (54 điểm/remount)

| Cặp | Giao nhau | Jaccard | Trùng trên mỗi tập |
|---|---:|---:|---:|
| remount01 vs remount02 | 51 | 0.895 (89.5%) | 94.4% |
| remount01 vs remount03 | 48 | 0.800 (80.0%) | 88.9% |
| remount02 vs remount03 | 50 | 0.862 (86.2%) | 92.6% |

- Có trong top 15% của cả ba remount: 0°, 4°, 27°, 36°, 37°, 54°, 55°, 66°, 67°, 68°, 76°, 77°, 106°, 107°, 108°, 134°, 172°, 173°, 174°, 175°, 187°, 204°, 213°, 214°, 215°, 243°, 244°, 252°, 253°, 254°, 255°, 263°, 264°, 283°, 284°, 292°, 293°, 294°, 295°, 323°, 324°, 325°, 332°, 333°, 334°, 335°, 347°.
- Có trong top 15% của ít nhất 2/3 remount: 0°, 4°, 27°, 28°, 36°, 37°, 38°, 54°, 55°, 66°, 67°, 68°, 76°, 77°, 94°, 106°, 107°, 108°, 134°, 147°, 157°, 172°, 173°, 174°, 175°, 187°, 204°, 212°, 213°, 214°, 215°, 227°, 243°, 244°, 252°, 253°, 254°, 255°, 263°, 264°, 283°, 284°, 292°, 293°, 294°, 295°, 303°, 323°, 324°, 325°, 332°, 333°, 334°, 335°, 347°.

## Overlap theo ngưỡng cố định >150 raw

| Cặp | Kích thước A/B | Giao nhau | Jaccard |
|---|---:|---:|---:|
| remount01 vs remount02 | 126/122 | 119 | 0.922 (92.2%) |
| remount01 vs remount03 | 126/133 | 120 | 0.863 (86.3%) |
| remount02 vs remount03 | 122/133 | 119 | 0.875 (87.5%) |

## Tương quan difficulty curve đầy đủ

| Cặp | Pearson primary | Spearman primary | Pearson sensitivity | Spearman sensitivity |
|---|---:|---:|---:|---:|
| remount01 vs remount02 | 0.9910 | 0.9903 | 0.9910 | 0.9903 |
| remount01 vs remount03 | 0.9790 | 0.9780 | 0.9779 | 0.9768 |
| remount02 vs remount03 | 0.9855 | 0.9854 | 0.9842 | 0.9837 |

## Đối chiếu với cực trị NL sau creep

Cực trị NL tham chiếu: 26°, 37°, 45°, 67°, 68°, 107°, 173°, 186°, 292°, 293°.

| Remount | Top-15 difficulty trùng chính xác | Trong ±1° | Trong ±2° |
|---|---|---|---|
| remount01 | 37°, 67°, 107°, 173°, 293° | 36°, 37°, 67°, 106°, 107°, 173°, 174°, 293°, 294° | 36°, 37°, 67°, 106°, 107°, 173°, 174°, 175°, 293°, 294°, 295° |
| remount02 | 67°, 107°, 173°, 293° | 66°, 67°, 106°, 107°, 173°, 174°, 293°, 294° | 66°, 67°, 106°, 107°, 173°, 174°, 175°, 293°, 294°, 295° |
| remount03 | 67°, 107°, 173°, 293° | 67°, 107°, 173°, 174°, 293°, 294° | 67°, 107°, 173°, 174°, 175°, 293°, 294°, 295° |

## Periodicity của difficulty curve

DFT dưới đây chạy trên `mean(abs(PositionErrorRaw))` sau khi loại mean. Đây là chẩn đoán bổ sung: một điểm cơ khí đơn thường tạo peak cục bộ/broadband, còn các order lặp lại qua remount gợi ý nguồn điện từ/controller hoặc cấu trúc tuần hoàn.

| Remount | 8 harmonic mạnh nhất (order: amplitude raw) |
|---|---|
| remount01 | H27: 45.62, H36: 40.99, H45: 40.65, H37: 29.05, H72: 27.14, H35: 24.69, H48: 16.48, H81: 14.86 |
| remount02 | H27: 47.54, H45: 40.72, H36: 39.77, H72: 28.21, H37: 27.86, H35: 25.16, H81: 15.68, H117: 14.55 |
| remount03 | H36: 45.86, H27: 45.17, H45: 40.68, H72: 27.70, H37: 27.32, H35: 24.18, H81: 16.64, H117: 14.85 |

- Harmonic nằm trong top-8 của cả ba remount: H27, H35, H36, H37, H45, H72, H81.
- Với motor 6 cặp cực, H36 tương ứng sáu ripple trên mỗi chu kỳ điện; H72 là harmonic bậc hai của pattern đó.

## Kết luận

- Pearson nhỏ nhất giữa các remount: **0.9790**.
- Spearman nhỏ nhất giữa các remount: **0.9780**.
- Độ lệch lớn nhất giữa primary và sensitivity correlation: **0.0017**.
- Điểm top-15 xuất hiện trong ít nhất 2/3 remount: **0°, 67°, 106°, 107°, 173°, 174°, 175°, 214°, 254°, 293°, 294°, 295°, 324°, 334°**.
- Trong nhóm ổn định đó, điểm trùng cực trị NL: **67°, 107°, 173°, 293°**.

**Kết luận nhị phân: CÓ — độ khó theo góc có cấu trúc lặp lại qua các remount, không phù hợp với giả thuyết nhiễu ngẫu nhiên độc lập.**

### Giới hạn diễn giải

Tương quan theo góc cao loại trừ phần lớn giả thuyết nhiễu thống kê độc lập, nhưng không tự chứng minh duy nhất một lỗi cơ khí cục bộ. DFT difficulty curve cho thấy một họ harmonic lặp lại qua các remount; pattern có thể đến từ cogging/điện từ, H36, controller hoặc tương tác motor–mounting được khóa theo sweep origin. Vì vậy kết quả này xác nhận **các vùng góc khó ổn định**, nhưng chưa xác nhận **một điểm hỏng cơ khí duy nhất**.

Sensitivity analysis không đổi kết luận đáng kể. Tuy vậy, để tuyên bố đúng thiết kế 3 official/remount, vẫn cần phục hồi hoặc đo lại 13 MOTION record bị mất của remount03 TestID 6.
