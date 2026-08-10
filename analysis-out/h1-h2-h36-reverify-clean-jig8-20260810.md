# Re-verify H1/H2/H36 trên dữ liệu "sạch" (JIG8, V5.5) — 2026-08-10

Việc treo từ 04/8: H1/H2/H36 đo được trước đây (mọi log trong dự án tới 05/8) nhiễm artifact
settle-creep chưa đóng hết khe hở (H1 -57%, H2 -34% giữa fw cũ và creep-fixed, theo phân tích MATLAB
05/8). Hôm nay lần đầu có dữ liệu đủ sạch (JIG8, creep hội tụ 88.8-100%) để đo lại.

## Dữ liệu nguồn

3 official run/motor, cùng build V5.5 (`Aug 6 2026 13:40:02`), cùng board JIG8, 3 motor khác nhau:

| | A1 (H1) | A2 (H2) | A9 | A36 (H36) | H36 phase |
|---|---:|---:|---:|---:|---:|
| P03/JIG8 | 0.0123 (cv 4.95%) | 0.0134 (cv 16.38%) | 0.0127 (cv 9.52%) | 0.0942 (cv 1.15%) | 81.14° (cv 2.03%) |
| P08/JIG8 | 0.0044 (cv 28.63%) | 0.0081 (cv 12.62%) | 0.0222 (cv 2.06%) | 0.0978 (cv 1.54%) | 87.47° (cv 1.49%) |
| P09/JIG8 | 0.0108 (cv 14.55%) | 0.0099 (cv 35.05%) | 0.0163 (cv 8.35%) | 0.0962 (cv 0.79%) | 92.25° (cv 0.66%) |

(cv trong ngoặc = trong-cùng-motor, qua 3 official run)

## Kết quả — so sánh CROSS-MOTOR (3 motor khác nhau, cùng board JIG8)

| Harmonic | Mean 3 motor | cv cross-motor | Relative range |
|---|---:|---:|---:|
| **A36 (motor family)** | 0.0961 | **1.88%** | **3.7%** |
| A1 (geometric family) | 0.0092 | 46.01% | 86.6% |
| A2 (geometric family) | 0.0105 | 25.73% | 50.5% |

## Kết luận

1. **Khung "họ harmonic hình học vs motor" (04/8) được xác nhận LẦN ĐẦU trên dữ liệu sạch, và rõ ràng
   hơn dự kiến**: A36 (họ motor) chỉ dao động 1.88% cv **ngay cả khi đổi sang 3 MOTOR VẬT LÝ KHÁC NHAU**
   (không chỉ đổi mount của cùng 1 motor) — trong khi A1/A2 (họ hình học) dao động 26-46% cv cùng điều
   kiện. Đây là bằng chứng mạnh hơn nhiều so với trước 04/8 (lúc đó chỉ so sánh cùng 1 motor qua các
   board, chưa so được cross-motor vì dữ liệu còn nhiễm artifact).
2. **A1 giờ chỉ ~0.004-0.012°** — nhỏ hơn 10-100 lần so với mọi giá trị H1 từng đo trong dự án trước
   05/8 (0.12-0.55°, đều nhiễm artifact). Xác nhận phát hiện sơ bộ hôm 06/8: phần lớn "tín hiệu H1/H2"
   trước đây thực chất là chính artifact settle-creep, không phải độ lệch tâm cơ khí thật.
3. **A36 phase cũng khá ổn định trong từng motor** (cv 0.66-2.03%, range 1.2-3.2° qua 3 run) — nhưng
   khác nhau rõ giữa 3 motor (81°/87°/92°) — hợp lý vì đây là đặc tính pha riêng của từng motor
   (không phải artifact), không mâu thuẫn với kết luận "A36 amplitude ổn định".

## Giới hạn — chưa đóng được hoàn toàn vòng lặp gốc

Yêu cầu gốc (04/8) là xác nhận **cùng 1 motor, H36 ổn định qua các BOARD khác nhau** (không phải qua
các motor khác nhau như bảng trên). Việc đó **chưa làm được** vì JIG7 chưa đạt độ sạch tương đương
(escalation success 75-88%, chưa qua V5.8) — không có board thứ 2 nào đủ sạch để đối chiếu ngang hàng
với JIG8 cho cùng 1 motor (P03 có cả JIG7 và JIG8, nhưng JIG7 chưa đủ sạch).

**Việc cần làm tiếp**: sau khi V5.8 (hoặc hướng thay thế) đưa JIG7 lên độ sạch tương đương, đo lại P03
trên JIG7 và so trực tiếp A36/H36-phase với P03/JIG8 (bảng trên) để đóng vòng lặp gốc thật sự.

## Chưa làm trong lần này

- Thiết kế lại gate `MountValid` theo vector H1/H2 — biên độ hiện quá nhỏ và nhiễu pha còn cao (đặc
  biệt P08's A1 cv=28.6%, P09's A2 cv=35%) để dựng ngưỡng tin cậy ngay; cần thêm dữ liệu hoặc cách đo
  giảm nhiễu pha trước khi thiết kế gate.
- So sánh JIG1/JIG4 (mục tiêu gốc dự án) — cần đợi có ít nhất 1 cặp board đều sạch để so sánh có ý
  nghĩa.
