---
type: "query"
date: "2026-08-11T01:37:27.572350+00:00"
question: "thuật toán hiện tại và cách tính NL trong thư mục khác nhau những gì; code hiện tại có đang thực hiện nhiệm vụ là tính giá trị NL như code của gremsy hay không?"
contributor: "graphify"
outcome: "useful"
source_nodes: ["gremsyMotor.c", "nonlinear_test.c", "recompute_metrics()", "Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)"]
---

# Q: thuật toán hiện tại và cách tính NL trong thư mục khác nhau những gì; code hiện tại có đang thực hiện nhiệm vụ là tính giá trị NL như code của gremsy hay không?

## Answer

Expanded from original query via vocab: [gremsy, nonlinear, encoder, motor, sweep, error, angle, calibration, correction, tracking, position, robust]. Kết luận: hai code cùng đo whole-system command tracking bằng góc lệnh so với MA600, nhưng không cùng measurement contract. Gremsy dùng bước 256 raw, 5 giá trị góc đã qua IIR nền, fixed delay, error=target-(encoder-offset), và Nonlinear Angle=max(error)-min(error) trên gần 370 độ. Firmware hiện tại dùng lưới 360 điểm một độ, 64 đọc SPI trực tiếp sau settle, tách closure/post-turn, và Nonlinear chính=mean(top 5)-mean(bottom 5). Trường Motor_Error_P2P_Deg của firmware hiện tại có cùng dạng toán max-min với Gremsy; Motor_System_INL_Deg=P2P/2 và không có tương đương trong Gremsy. Vì chuyển động, lưới và lọc khác nhau, ngay cả hai P2P cũng không tương đương số học 1:1. Cả hai không đo sensor-only INL vì không có encoder tham chiếu độc lập.

## Outcome

- Signal: useful

## Source Nodes

- gremsyMotor.c
- nonlinear_test.c
- recompute_metrics()
- Đánh giá cách đọc dữ liệu MA600A trong firmware Gremsy cũ (gremsyEncoder.c / gremsyMotor.c / gremsyTaskManager.c / gremsyAnalog.c)