# Chốt phương thức đo B0-B bằng MATLAB

## Kết luận

**Chọn `A0` làm phương thức đo hiện tại. Không chọn V3 no-reversal.**

Hai thí nghiệm trả lời hai câu hỏi tách biệt:

1. **Test 29 — sector:** V2 cũ và A0 đều có reversal; A0 chỉ đổi sang sector mới. A0 giảm residual ở 5/5 motor và giảm |closure| ở 5/5 motor.
2. **Test 28 — reversal:** A0 và V3 dùng cùng sector; V3 bỏ reversal. Residual V3 cao hơn A0 bracket `+0.02304°`, bootstrap 95% `[+0.00965°, +0.03619°]`, nên không có lợi ích từ bỏ reversal.

## Các gate quan trọng

- Test 28: 30/30 official runs hợp lệ, đúng protocol/reversal count.
- Residual gate đã khóa: V3 phải nhỏ hơn A0 bracket trừ `2.77 × pooled SD`; ngưỡng là `0.03959°`, V3 là `0.11021°` — fail.
- V3 không cải thiện |canonical closure|: chênh V3-bracket `+0.01542°`.
- NL A0/V3 nằm trong repeatability envelope; không có bằng chứng rằng chọn A0 làm sai khác NL có ý nghĩa.
- Sector Test 28 khớp 10/10 trong ±91 raw, max `9.56 raw`, nhưng đây là gate mô tả vì ba file không có wall-clock chung.

## Phạm vi kết luận

Dữ liệu đủ để **giữ A0 và dừng nhánh V3**: sector mới có lợi trên nhiều motor, còn bỏ reversal không cải thiện phép đo và làm residual xấu hơn trên bracket P03. Không tuyên bố causal proof tuyệt đối cho sector per-run của Test 28 cho đến khi firmware/log có timestamp chung xuyên A0–V3–A0.
