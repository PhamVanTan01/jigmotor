# Sector-response calibration — kế hoạch thử nghiệm phần cứng

Tài liệu này mô tả cách chạy thí nghiệm **trung hạn** đề xuất trong
`docs/nl-factors-jig-comparison-and-algorithm-review-2026-07-27.md` mục 4.5:
giữ cố định 1 motor, quét sector chủ động qua nhiều vị trí biết trước, để đo
đúng đường cong phi tuyến thật của MỘT motor cụ thể — thay vì suy từ 14 phiên
gộp từ nhiều motor/jig khác nhau (R²=0.22, không đủ tin cậy).

**Trạng thái: firmware đã viết, build sạch, self-test PASS trong software.
CHƯA chạy trên phần cứng thật — cần bạn thực hiện phần dưới đây.**

## 1. Cơ chế firmware (đã implement, mặc định TẮT)

File: `Core/Src/nonlinear_test.c`, flag `ENABLE_NL_SECTOR_CALIBRATION_SWEEP`
(mặc định `0`, không ảnh hưởng gì tới hành vi A0 sản xuất hiện tại).

Khi bật (`=1`):
- Trước khi bắt đầu mỗi batch (mỗi lần nhấn nút), firmware chọn 1 trong 8 vị
  trí sector đã định sẵn theo thứ tự vòng (round-robin), cách đều nhau 1/8
  chu kỳ điện (10923 raw / 8 ≈ 1365 raw ≈ 45° điện mỗi bước):
  `{0, 1365, 2731, 4096, 5462, 6827, 8192, 9558}` raw.
- Chủ động lệnh motor tới vị trí đó **trước** bước "settle vô-mục-tiêu" hiện
  có (không đổi bất kỳ dòng code nào của approach/measurement đã validate —
  chỉ thêm 1 bước di chuyển TRƯỚC nó).
- Toàn bộ 10 run chính thức trong batch đó dùng CHUNG 1 sector (đóng vai trò
  lặp lại để lấy trung bình khử nhiễu — đúng cấu trúc dữ liệu mà
  `analyze_nl_factors.m`/`fit_sector_response.m` đã dùng).
- Ghi 1 dòng log riêng mỗi batch để đối chiếu: `SECTOR_CALIBRATION,BatchID=X,TargetIndex=Y,TargetRaw=Z`.

**An toàn thiết kế**: cờ mặc định TẮT — không build/flash nào trong lịch sử
dự án bị ảnh hưởng trừ khi bạn chủ động bật cờ này và build lại. Đã build
kiểm tra cả 2 trạng thái (bật/tắt) và test kết hợp (bật cả 2 cờ cùng lúc bị
chặn bởi `#error` build-time) — không có warning mới nào ngoài 2 warning
đã tồn tại từ trước (không liên quan).

## 2. Việc bạn cần làm trên phần cứng

### Bước 1 — Build firmware với cờ bật

```powershell
# Trong Measurement/subdir.mk hoặc qua override define khi build:
# đổi Core/Src/nonlinear_test.c dòng "#define ENABLE_NL_SECTOR_CALIBRATION_SWEEP 0"
# thành "... 1", rồi:
powershell -File scripts/build_dual_image.ps1 -Mode Measurement
```

Sau khi thử nghiệm xong, **nhớ đổi lại về `0`** trước khi build bản production
tiếp theo (hoặc dùng nhánh git riêng cho lần build này).

### Bước 2 — Chọn 1 motor cố định, KHÔNG tháo lắp giữa các batch

Chọn 1 sản phẩm/motor bất kỳ đã dùng trong các test trước (ví dụ P03) — gắn
cố định trên jig, **không tháo ra lắp lại** trong suốt phiên thử nghiệm (loại
bỏ hoàn toàn biến "motor-to-motor" và biến "remount", chỉ còn lại biến
sector).

### Bước 3 — Chạy đủ 8 batch liên tiếp (nhấn nút 8 lần)

Mỗi lần nhấn nút = 1 batch = 1 sector mới trong danh sách (tự động cycle theo
thứ tự cố định). Sau lần nhấn thứ 8, sector quay vòng lại vị trí đầu — nếu
muốn thêm độ tin cậy, có thể chạy thêm 1 vòng nữa (8 batch nữa, tổng 16) để
có 2 lần lặp độc lập mỗi sector, nhưng 8 batch là đủ tối thiểu để fit mô hình
harmonic bậc 1 (2 tham số tự do, dư 6 bậc tự do).

Mỗi batch mất khoảng thời gian tương đương 1 batch B0-B thông thường (1
precondition + 10 run chính thức + cooldown 120s giữa các run — như các test
B0-B trước đây).

### Bước 4 — Lưu log

Đặt tên file theo quy ước có sẵn của dự án, ví dụ:
`sector-calibration-p03-batch01.txt` ... `sector-calibration-p03-batch08.txt`
(hoặc gộp cả 8 batch vào 1 file log liên tục nếu không tắt nguồn giữa các
lần nhấn nút — cả hai cách đều phân tích được bằng tool bên dưới).

## 3. Phân tích kết quả (đã chuẩn bị sẵn, chạy được ngay khi có log)

### 3.1. Kiểm tra độ chính xác pre-position

```matlab
addpath('analysis/matlab'); addpath('analysis/matlab/nl');
result = parse_sector_calibration_log("sector-calibration-p03-batch01.txt");
% (gộp nhiều file nếu tách riêng mỗi batch — xem Comparison table của từng file)
```

Cho biết lệnh vs vị trí thực đo lệch bao nhiêu (raw) — nếu lệch lớn bất
thường (>50-100 raw), có thể do ma sát/backlash cần điều tra thêm trước khi
tin tưởng mô hình fit ở bước sau.

### 3.2. Fit mô hình sector-response cho ĐÚNG 1 motor này

```matlab
files = "sector-calibration-p03-batch0" + (1:8) + ".txt";
products = repmat("p03", 1, 8);  % cùng 1 motor -- centering theo product gần như không đổi gì, nhưng giữ API nhất quán
fitNL = fit_sector_response(files, products, "NL_RobustP2P_Deg", 10923.0);
fitA36 = fit_sector_response(files, products, "A36_Deg", 10923.0);
```

R² kỳ vọng sẽ **cao hơn đáng kể** so với 0.22 hiện tại (vì loại bỏ hoàn toàn
nhiễu motor-to-motor và jig-to-jig, chỉ còn đúng 8 điểm sạch trên 1 motor) —
nếu R² vẫn thấp dù đã kiểm soát sector, đó sẽ là bằng chứng mạnh cho thấy
sector KHÔNG phải yếu tố chi phối chính, ngay cả trong điều kiện lý tưởng
nhất.

## 4. Đề xuất dài hạn (chưa bật, cần bạn quyết định thời điểm)

Flag `ENABLE_NL_A0_FIXED_SECTOR` (cùng file, mặc định `0`) sẵn sàng để bật
sau khi có kết quả từ thí nghiệm trên — nếu sector-response được xác nhận là
yếu tố chi phối đủ mạnh, có thể cân nhắc khóa A0 luôn về 1 sector cố định
(`NL_A0_FIXED_SECTOR_TARGET_RAW`, hiện đặt placeholder = 0, tức trùng vị trí
`LockStartPosition()`) làm mặc định sản xuất mới. **Đây là thay đổi hành vi
đo production, cần một vòng validate hardware riêng** (lặp lại qua nhiều lần
power-cycle, so sánh với tập dữ liệu shifted-sector hiện tại) trước khi cân
nhắc thay thế A0 hiện hành (đã khóa theo commit `8c90514`).
