# Tổng kết phiên làm việc 2026-08-04: xác nhận hiệu ứng "board mới", tách bạch gá vs sensor, và đề xuất phương án đánh giá NL bền vững theo jig

Tài liệu này tiếp nối `docs/session-summary-2026-08-03-mount-precheck-and-assembly-swap.md` và
`docs/session-summary-2026-08-03-peak-signature-classification.md` (phiên trước, cùng chủ đề gốc
sensor+gá). Ghi lại đúng những gì đã làm/tìm được trong phiên hội thoại ngày 2026-08-04.

## 1. Đăng ký thêm 2 board mới: JIG7 (đã có UID từ trước) và JIG8 (mới đăng ký hôm nay)

`Core/Src/nonlinear_test.c`, `NL_KNOWN_JIGS[]`:

| Jig | MCU_UID | Ghi chú |
|---|---|---|
| JIG6 | 005100323235511835383831 | Đăng ký 2026-07-28 (phiên trước) |
| JIG7 | 004600323235511835383831 | Đăng ký 2026-07-28 (phiên trước) |
| **JIG8** | **003E00323235511835383831** | **Đăng ký hôm nay 2026-08-04**, cùng lô wafer với JIG6/JIG7 (UID_WORD1/WORD2 giống hệt, chỉ khác WORD0) — lần thứ 3 liên tiếp. Đăng ký chỉ từ 2 lần đọc `BOOT_SMOKE` (không gate) — profile vẫn là placeholder, đã xác nhận đúng qua lần đọc `PRECONDITION_PRE_MOTOR` thật đầu tiên (Zero=0x0000, khớp JIG1-7). |

Build: `builds/jig8-registration-fast3-20260804/` (1 pre + 3 official). Build sạch, 28/29 script pass
(1 ngoại lệ `test_preconditioned_10run_contract.ps1`, đúng mẫu mọi build FAST3 trong dự án).
HexSHA256=307BEC65EE35F5CFBEE9AEF281B9C5ED4FD578A9D2FCE9C34D5A9E957B237767.

## 2. Phát hiện chính #1: "hiệu ứng board mới" làm giảm biên độ NL, không đổi vị trí lỗi

Gắn đúng 1 cụm (gá+sensor gốc của JIG4, cụm "tốt" đã biết từ phiên trước, remount-range 0.02°) lần
lượt lên 3 board khác nhau, mỗi board 3x remount (FAST3):

| Board | NL trung bình | Range 3x | Chênh vs lịch sử JIG4 (3.310°) | Vị trí đáy (bottom-5) |
|---|---:|---:|---:|---|
| JIG4 (board gốc) | 3.310° | 0.0195° | — | {76,77,36,37,78}° |
| JIG6 | 2.997° | 0.0485° | -0.313° | {36,37,76,77,38}° (8.0° tới gốc) |
| JIG7 | 3.053° | 0.0191° | -0.258° | {36,37,76,77,38}° (8.0° tới gốc) |
| JIG8 | 3.113° (2 remount, chưa đủ 3x) | 0.015° (2 điểm) | -0.198° | {36,37,76,77,38}° (8.0° tới gốc) |

Cả 3 board mới đều: (a) vị trí đáy khớp gá gốc gần như tuyệt đối (8.0°, ổn định), (b) biên độ tụt
cùng hướng so với lịch sử board JIG4 gốc, độ lớn khác nhau chút ít (0.20-0.31°) nhưng không cố
định — 3 board độc lập (khác die, dù JIG6/7/8 cùng lô wafer) cho cùng kết luận, loại trừ giả thuyết
"lỗi cơ khí riêng của 1 board". Xem `analysis-out/p05-jig7-3remount-final-20260804/`,
`analysis-out/p05-jig8-newboard-crosscheck-20260804/`.

## 3. Phát hiện chính #2: chữ ký "lai" khi gắn cụm yếu hơn lên board mới — tái lập trên 2 board độc lập

Cụm còn lại (gá gốc JIG1, hiện gắn ở board JIG5, tín hiệu yếu hơn: H1≈0.3° so với 0.52° của cụm
JIG4-gốc) khi gắn lên JIG6 và JIG7 đều cho ra **đúng cùng 1 chữ ký lai**, không thuần theo bên nào:

- Bottom-5 (cả JIG6 và JIG7, gộp 18 run): **{196,197,76,77,36}°** — 2 điểm thuộc chữ ký JIG5-gốc
  (196,197), 3 điểm thuộc chữ ký JIG4-gốc (76,77,36).
- JIG6/cụm-này ↔ JIG7/cụm-này: khoảng cách đáy = **0.0°**, r=0.996 — trùng khít, xác nhận đây là
  hiện tượng thật, không phải lỗi riêng của 1 board.

**Mô hình giải thích khớp nhất**: board mới (JIG6/7/8) có thể mang một lệch tâm cơ khí nhỏ của
riêng nó, cộng vector với lệch tâm riêng của cụm gắn lên. Với cụm mạnh (JIG4-gốc), tín hiệu cụm áp
đảo → vị trí giữ nguyên, chỉ biên độ bị triệt tiêu một phần (mục 2). Với cụm yếu hơn (JIG1-gốc/JIG5),
2 tín hiệu cỡ tương đương → vector tổng lệch hướng trung gian → chữ ký lai. Biên độ NL của cụm yếu
này cũng nhạy với board hơn cụm mạnh (JIG6=3.008° vs JIG7=3.155°, chênh 0.147°, so với chỉ 0.056°
ở cụm mạnh) — khớp với mô hình vector cộng dồn. Xem
`analysis-out/p05-full-crossboard-final-20260804/`.

Một lần thử trên board JIG8 (cùng ý định) cho kết quả **không ổn định** (range NL 2 remount =
0.124°, vượt xa gate 0.05°, cv nội bộ 4.28% — cao bất thường) — nghi ngờ lắp chưa chuẩn, **chưa
đóng được kết luận**, cần xác minh lại lực siết/quy trình lắp trước khi test tiếp.

## 4. Phát hiện chính #3 (quan trọng nhất): thí nghiệm tách sensor khỏi gá — lần đầu tách bạch được vai trò của từng thành phần

Người vận hành xác nhận đã tháo sensor MA600 ra khỏi gá JIG4-gốc, thay bằng 1 module sensor **hoàn
toàn mới, chưa từng dùng**, giữ nguyên gá — test trên board JIG7, 3x remount FAST3.

| Remount | NL | H2 |
|---|---:|---:|
| 01 | 2.642° | 0.059° |
| 02 | 2.674° | 0.064° |
| 03 | 2.640° | 0.063° |
| **Trung bình** | **2.652°** | **≈0.062°** |
| Range 3x | 0.034° (đạt gate) | — |

Bottom-5 = **{36,37,76,156,77}°** — **4/5 điểm vẫn khớp đúng gá JIG4-gốc** ({76,77,36,37,78}°),
chỉ 1 điểm khác (156° thay vì 78°), ổn định qua cả 3 remount. Top-5 = {264,263,294,304,224}° — pha
trộn, điểm 224° là điểm mới, không thuộc gá nào đã biết.

**Kết luận (lần đầu tách bạch được trong toàn bộ quá trình điều tra)**:
- **Gá (mounting/lệch tâm cơ khí) quyết định phần lớn VỊ TRÍ lỗi** — 4/5 điểm đáy giữ nguyên dù đổi
  hẳn sang 1 sensor mới.
- **Sensor die quyết định BIÊN ĐỘ lỗi** — NL tụt còn 2.65° (thấp nhất toàn bộ dữ liệu từ trước đến
  giờ, thấp hơn cả hiệu ứng board mới ở mục 2), H2 giảm mạnh và rất ổn định (~0.062° so với
  0.215-0.265° của sensor gốc) — đặc tính riêng của từng con chip sensor, không phải lỗi ngẫu nhiên.

Xem `analysis-out/p05-jig7-sensoronly-3remount-final-20260804/`.

**Xác nhận quan trọng (người vận hành, cuối phiên)**: xuyên suốt TOÀN BỘ thí nghiệm đổi board hôm
nay (JIG6/JIG7/JIG8, mục 2/3, cả thí nghiệm tách gá-sensor ở mục này) đều dùng **đúng 1 motor vật
lý, đúng 1 item 8** (xem mục 4.3) — không đổi motor giữa các lần đo. Điều này loại trừ hoàn toàn khả
năng "hiệu ứng board mới"/"cụm yếu nhạy board hơn"/"gá quyết định vị trí, sensor quyết định biên độ"
là do khác biệt giữa các con motor — 100% biến động quan sát được đến từ phía jig (gá + đầu đọc
MA600 + board), không phải từ motor đang đo.

## 4.3. Đối chiếu bản vẽ thiết kế motor (ASM1807, `1807AS001A2`) — item 8 là nam châm cảm biến riêng

Người vận hành cung cấp bản vẽ lắp ráp + BOM chính thức của motor test (`1807AS001A2`, "ASM1807",
Gremsy J.S.C, checked 4/2/2026). Phát hiện:

- **Item 8 "N48H RING MAGNET"** (Neodymium N48H, QTY 1) là **1 nam châm riêng biệt**, tách khỏi cụm
  rotor chính (items 6+7 "N42H NS"/"N42H SN", QTY 7 mỗi loại = 14 miếng, khớp ghi chú bản vẽ "Motor
  configuration: 14N12P"). Item 8 gắn cùng trục với rotor chính (item 9, "ROTOR HOLO SHAFT", không
  khớp nối trung gian) — góc quay của item 8 = góc quay thật của trục.
- **MA600 trong toàn bộ dự án luôn đọc item 8**, không bao giờ đọc trực tiếp rotor chính — người vận
  hành xác nhận điều này đúng cho **mọi loại motor đang test**, không riêng ASM1807.
- Truy lại công thức cũ (`gremsyTaskManager.c`, `ST_STATE_NON_LINEAR_PROCESS`): biến `motorNL_PosAngle`
  (comment "goc theo rotor") thực chất **không đọc từ cảm biến nào** — chỉ là quy đổi biến đếm phần
  mềm `motorNL_Pos` (tự cộng dồn theo `MOTOR_NONLINEAR_POS_INCREASE`, dùng để RA LỆNH PWM) sang độ.
  Công thức cũ (`ErrorMax − ErrorMin`, không chia 2, không harmonic) và công thức mới đều chỉ có
  **đúng 1 nguồn đo vật lý** (qua item 8), so với 1 target hở vòng — không phải 2 phép đo độc lập từ
  "encoder" và "rotor" như tên biến gợi ý. Cả 2 thế hệ jig đều chung giới hạn này (không có encoder
  chuẩn độc lập), không phải khác biệt giữa jig cũ/mới.

**Mâu thuẫn số cặp cực — ĐÃ ĐÓNG**: người vận hành xác nhận mẫu motor thực tế đang test có **6 cặp
cực** (khớp đúng `MOTOR_POLE_PAIRS=6` trong firmware); bản vẽ ASM1807 "14N12P"/7 cặp cực là 1 revision
thiết kế khác, không phải mẫu đang chạy trên jig. Không còn mâu thuẫn — `ElectricalRippleOrder=36`
(=6×6) khớp đúng số cặp cực thật của motor test.

**Vì sao dùng bậc 36 dù item 8 (cảm biến) chỉ 1 cặp cực — câu hỏi đã được trả lời gọn**: item 8 chỉ
đóng vai trò truyền tải trung thực góc trục thật (gắn cứng cùng trục, không khớp nối trung gian), tự
nó không sinh ra dao động bậc cao. Bậc 36 đến từ phía ROTOR CHÍNH đang lái (6 cặp cực) — gợn mô-men
bậc 6 so với tần số điện cơ bản (6×6=36), hiện tượng kinh điển ở PMSM sin-commutation, làm trục thật
dao động 36 lần/vòng; item 8 chỉ báo cáo lại đúng dao động đó. Ngược lại, lỗi riêng của chính item 8
(không đồng đều từ hóa, lệch tâm với đầu đọc MA600) tự nhiên rơi vào bậc thấp (1 cặp cực → bậc 1, 2)
— đúng khớp nhóm "geometric" đã xác lập. Hai nguồn (item 8 bậc thấp, rotor chính bậc cao bội số 6)
nằm tách biệt hẳn nhau trên phổ tần — đây là lý do thiết kế cơ khí thật khiến chiến lược phân nhóm
harmonic "geometric" vs "motor" (mục 5) hoạt động sạch, không phải trùng hợp.

## 4.4. Vì sao 2 sensor cùng loại lại cho đỉnh lỗi khác nhau — đối chiếu datasheet MA600A

Datasheet MA600A (`MA600A.md`, mục "User Output Calibration", dòng ~2268-2276) tự tách rõ 2 nguồn
lỗi mà bảng hiệu chuẩn 32 điểm của chip nhắm tới xoá bỏ — khớp chính xác với 2 vai trò vừa tách bạch
được ở mục 4:

> *"This enables the removal of errors induced by the magnetic configuration (misalignments and
> magnet defaults) **as well as the intrinsic MA600A error**."*

- "Errors induced by magnetic configuration (misalignments and magnet defaults)" = lỗi do gá/lệch
  tâm/nam châm → khớp phát hiện "gá quyết định VỊ TRÍ lỗi".
- **"Intrinsic MA600A error"** = lỗi nội tại của chính con chip → khớp phát hiện "sensor die quyết
  định BIÊN ĐỘ lỗi".

**Vì sao lỗi nội tại khác nhau giữa 2 con chip cùng part number**: mọi chip MA600A đều qua cùng 1
quy trình hiệu chuẩn nhà máy (factory calibration), nhưng hiệu chuẩn đó chỉ đảm bảo lỗi còn lại nằm
**dưới ngưỡng** ≤0.6° (chưa hiệu chuẩn user), không đảm bảo mọi chip giống hệt nhau — mỗi die silicon
vẫn giữ sai số dư riêng của nó trong ngưỡng đó, là hiện tượng bình thường của mọi IC sản xuất hàng
loạt. Đã xác nhận qua data: **`CorrNonZeroCount=0`** trên MỌI file log cả phiên (sensor cũ lẫn sensor
mới, mọi jig) — tức là bảng hiệu chuẩn 32 điểm on-chip (CORR0-31) **chưa từng được nạp cho bất kỳ
sensor nào** trong toàn bộ quá trình điều tra. Vậy khác biệt không phải do "1 bên đã hiệu chuẩn user,
1 bên chưa" — cả 2 đều chạy factory-cal thuần, khác biệt là sai số nội tại (silicon) thật sự giữa 2
die.

**Cơ chế cụ thể khả dĩ cho riêng H2** (dòng ~3081-3087 datasheet, mục layout PCB): tụ decoupling đặt
quá gần tâm chip (khoảng 3mm) có thể tạo ra **nhiễu loạn bậc-2 (2nd harmonic) lên tới 0.2°** do nhiễu
từ trường. Vì H2 là thông số lệch nhiều nhất giữa 2 sensor hôm nay (0.24° sensor cũ → 0.06° sensor
mới, gấp 4 lần), đây là ứng viên vật lý cụ thể đáng kiểm tra: nếu 2 module sensor là 2 board nhỏ
riêng biệt, chỉ cần lệch vị trí linh kiện xung quanh chip (đặc biệt tụ decoupling) vài mm giữa 2
lần lắp ráp cũng đủ giải thích phần lớn chênh lệch H2 quan sát được — độc lập hoàn toàn với gá/nam
châm. **Chưa xác minh được** (không có sơ đồ mạch của module sensor để đối chiếu) — đề xuất kiểm tra
vật lý layout của 2 module nếu muốn xác nhận dứt điểm.

## 5. Đề xuất phương án đánh giá chất lượng motor bền vững với jig/sensor/board

**Câu hỏi đặt ra**: nếu cùng 1 motor nhưng đo bằng sensor/board/gá khác nhau lại ra NL khác biệt lớn
(mục 2-4), thì dùng chỉ số NL hiện tại (RobustP2P, top5-bottom5) để đánh giá chất lượng motor là
không đáng tin cậy — chênh lệch do jig có thể lớn hơn hoặc ngang chênh lệch thật giữa các motor.

**Bằng chứng số liệu hôm nay** (harmonic spectrum, 3 cấu hình phần cứng hoàn toàn khác nhau: gá
JIG4-gốc+sensor gốc+board JIG4; gá JIG1-gốc (khác hẳn)+board JIG5; gá JIG4-gốc+sensor MỚI+board
JIG7):

| Harmonic | Family (đã có sẵn trong tool) | JIG4 (gá+sensor gốc) | JIG5 (gá khác) | JIG7 (gá JIG4+sensor mới) | Độ dao động |
|---|---|---:|---:|---:|---:|
| H1 | geometric (gá/mounting) | 0.530° | 0.298° | 0.221° | **~140-360%** |
| H2 | geometric (gá/mounting) | 0.241° | 0.300° | 0.065° | |
| H36 | **motor** (6×số cặp cực) | 0.864° | 0.846° | 0.859° | **chỉ ~2.1%** |
| H9/H18/H27/H45/H72/H108 | motor | (xem CSV) | | | đều ~1-5% |

`tools/analyze_nl_extreme_angles.py` (dòng 354) đã sẵn có khái niệm 2 nhóm harmonic:
**"geometric"** (H1,H2,H4,H8 — do lệch tâm gá/sensor quyết định, đã chứng minh hôm nay dao động
140-360% giữa các cấu hình phần cứng khác nhau đo cùng 1 motor) và **"motor"** (H3,H6,H9,H12,H18,
H27,H36,H45,H72,H108 — do chính cấu trúc điện/cơ của motor quyết định, dao động chỉ 1-5% dù đổi
hẳn gá/sensor/board).

**Phương án đề xuất (ưu tiên theo thứ tự)**:

1. **Dùng nhóm harmonic "motor" (đặc biệt H36) làm chỉ số chính để đánh giá/so sánh chất lượng
   motor**, thay vì RobustP2P/NL hiện tại (vốn là top5-bottom5 của đường cong thô, bị chi phối nặng
   bởi nhóm "geometric" nhạy jig). Đây là thay đổi ít tốn kém nhất — không cần phần cứng mới, chỉ
   cần đổi chỉ số báo cáo/gate, và đã có sẵn hạ tầng tính toán (cả trong firmware lẫn
   `analyze_nl_extreme_angles.py`).
2. **Giữ 1 gauge "vàng" (golden gauge) cố định cho mọi so sánh cross-motor bắt buộc dùng RobustP2P
   theo spec cũ** — không trộn dữ liệu đo từ nhiều board/sensor khác nhau khi so sánh trực tiếp
   giữa các motor. Ứng viên tốt nhất hiện tại: gá+sensor gốc JIG4 trên chính board JIG4 (range 3x
   0.0195°, tốt nhất từng ghi nhận).
3. **Xây bảng hiệu chuẩn offset theo từng gauge** (tiếp nối đúng mục đích `MOUNT_PRECHECK_V1`/
   `analyze_mount_precheck_batch.m` đã có) — đo 1 "motor chuẩn" trên nhiều gauge (dữ liệu hôm nay đã
   là 1 phần của việc này), suy ra hệ số bù riêng từng gauge, áp dụng trước khi so sánh cross-gauge
   nếu vẫn cần dùng RobustP2P.
4. **Nâng cấp `MountValid` trong `MOUNT_PRECHECK_V1`** dùng đúng fingerprint H1/H2 để làm gate xác
   minh gauge (không chỉ gate "lắp tốt hay xấu" như hiện tại) — phát hiện ngay nếu 1 board/sensor
   lệch khỏi profile gauge đã hiệu chuẩn, trước khi dữ liệu motor thật bị đo sai.

**Khuyến nghị làm ngay, chi phí thấp nhất**: mục 1 — đổi chỉ số báo cáo chính sang nhóm harmonic
"motor"/H36, verify lại trên toàn bộ dữ liệu lịch sử của dự án (không chỉ hôm nay) để xác nhận độ ổn
định tổng quát trước khi chính thức thay thế RobustP2P trong quy trình QA.

### 5.1. Đối chiếu RobustP2P với công thức spec (MA600A Appendix B, Equation B1)

`RobustP2P`/`legacyStats.robustPP` (dùng xuyên suốt phân tích hôm nay) = avg(5 điểm cao nhất) −
avg(5 điểm thấp nhất) — **không khớp** Equation B1 (`INL = (max−min)/2`): thiếu phép chia 2, và
dùng trung bình 5 điểm thay vì đúng 1 điểm max/min. Firmware đã có sẵn field đúng công thức B1,
chưa từng dùng trong phân tích: `Motor_System_INL_Deg = legacyStats.rawPP / 2.0f`
(`nonlinear_test.c:5356-5362`) — đo cả hệ thống (motor+nam châm+gá+jig+sensor), không phải riêng
sensor, nên vẫn không so trực tiếp được với ngưỡng ≤0.6°/≤0.1° của datasheet, nhưng dùng đúng công
thức để so sánh nội bộ giữa các cấu hình.

Tính lại toàn bộ bảng so sánh hôm nay theo `Motor_System_INL_Deg`:

| Cấu hình | RobustP2P (cũ) | Motor_System_INL_Deg (đúng B1) | Chênh % |
|---|---:|---:|---:|
| JIG4-gốc (board gốc) | 3.310° | 1.7408° | — |
| JIG6 + cụm JIG4-gốc | 2.997° (-9.5%) | 1.6127° (-7.4%) | cùng hướng |
| JIG7 + cụm JIG4-gốc | 3.053° (-7.8%) | 1.6415° (-5.7%) | cùng hướng |
| JIG8 + cụm JIG4-gốc | 3.113° (-6.0%) | 1.6227° (-6.8%) | cùng hướng |
| JIG5-gốc (cụm yếu) | ~3.03-3.08° | 1.5965° | — |
| JIG6 + cụm yếu (test-2) | 3.008° (thấp hơn nhẹ) | 1.5766° (-1.2%) | cùng hướng |
| JIG7 + cụm yếu (test-2) | 3.155° (cao hơn) | 1.6834° (+5.4%) | cùng hướng |
| JIG7 + gá JIG4 + sensor mới | 2.652° | 1.4004° | -14.7% so với JIG7+cụm gốc (1.6415°) |

**Kết luận**: tỷ lệ INL/RobustP2P ổn định quanh **~0.53** trên mọi cấu hình (không phải đúng 0.5 vì
robustPP làm mượt 5 điểm còn rawPP lấy đúng 1 điểm) — mọi kết luận định tính ở mục 2-4 (hiệu ứng
board mới, cụm yếu nhạy board hơn cụm mạnh, gá quyết định vị trí/sensor quyết định biên độ) **giữ
nguyên** khi đổi sang chỉ số đúng công thức spec. Chỉ số tuyệt đối và ngưỡng gate (hiện ≤0.05° theo
RobustP2P) cần quy đổi lại theo tỷ lệ ~0.53 nếu chính thức chuyển sang dùng `Motor_System_INL_Deg`.

## 6. Việc chưa hoàn thành / đề xuất cho phiên sau

1. JIG8/cụm-yếu (mục 3, thử nghiệm chưa đóng) — cần xác minh lại lực siết/quy trình lắp, test lại
   3x để xem hiện tượng bất ổn định (range 0.124°) có phải do lắp sai hay là phát hiện thật.
2. Đóng nốt 3x remount cho JIG8/cụm-mạnh (mới có 2/3, xem mục 2) và test cụm yếu trên JIG8 lần nữa
   sau khi khắc phục mục 1 — để có đủ 3 board xác nhận cả 2 hiện tượng (mục 2 và mục 3).
3. Verify đề xuất mục 5.1 (chỉ số harmonic "motor"/H36) trên toàn bộ dữ liệu lịch sử dự án, không
   chỉ dữ liệu hôm nay, trước khi đổi chính thức trong quy trình QA.
4. Tìm hiểu vật lý: vì sao sensor mới lại cho H2 thấp hơn hẳn (0.062° so với 0.215-0.265°) — dung
   sai sản xuất riêng từng die, hay lỗi/khác biệt lô sensor.
5. Đánh nhãn vật lý A/B/C độc lập cho từng cụm gá và từng module sensor (khuyến nghị từ phiên trước,
   càng quan trọng hơn sau khi xác nhận gá và sensor tách rời được).

## 7. Build/dữ liệu

- Build: `builds/jig8-registration-fast3-20260804/`.
- Dữ liệu thô: `captured-logs/S2-P05-JIG{6,7,8}-remount*-test-*.txt` (kèm `.analysis.*` tự sinh).
- Phân tích: `analysis-out/p05-jig{6,7,8}-*-20260804/`, `analysis-out/p05-full-crossboard-final-20260804/`,
  `analysis-out/p05-jig7-sensoronly-3remount-final-20260804/`.
