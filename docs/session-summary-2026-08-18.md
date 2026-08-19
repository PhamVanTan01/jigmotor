# Session summary — 2026-08-18

## S5.3 mở rộng — đánh giá lại độ ổn định và khả năng đồng bộ Open-loop NL giữa JIG7/JIG8

**Classification:** `OPEN_LOOP_MEASUREMENT` — chỉ đánh giá dữ liệu đã thu; không đổi command,
profile, sampler, công thức, schema hoặc measurand. Primary measurand vẫn là
`OpenLoopNL = max(ErrorRawQ16) - min(ErrorRawQ16)` trên 360 điểm. Không suy ra ngưỡng pass/fail
sản phẩm vì project chưa calibrate ngưỡng đó.

### Phạm vi dữ liệu

Tính lại trực tiếp từ `ErrorRawQ16` official của các batch schema-v6
`GREMSY_COMPAT_OPEN_LOOP_NL_V1`, chọn batch đầy đủ mới nhất/đại diện tốt nhất cho từng cặp:

- P03: JIG8 remount02 và JIG7 run01.
- P08: JIG8 run01 và JIG7 run01; vế JIG7 chỉ có 9/10 official hợp lệ do một sweep thiếu
  DATA index 14, nên cặp này chỉ là bằng chứng exploratory, chưa phải qualification hoàn chỉnh.
- P010: JIG8 run02 và JIG7 run02, loại hai mounting run01 đã chứng minh là atypical.
- P011: run01 trên mỗi jig; chưa có remount để tách mount effect.
- P013: JIG8 run02 và JIG7 run03; đây là hai batch remount mới nhất, đều 10/10 valid.

Không dùng `S4-P08-JIG7-openloop-v1-run02` (0/10, capture dở), `S4-P012-JIG8...`
(2/10, capture dở và không có vế JIG7), hay legacy `flags-off` vào cross-jig statistics.

### Repeatability trong từng batch

| Product | Jig | Official | OpenLoopNL mean | SD | CV | Full-curve r mean |
|---|---|---:|---:|---:|---:|---:|
| P03 | JIG8 | 10 | 2.9319° | 0.0416° | 1.42% | 0.99787 |
| P03 | JIG7 | 10 | 2.8430° | 0.0302° | 1.06% | 0.99800 |
| P08 | JIG8 | 10 | 3.1523° | 0.0322° | 1.02% | 0.99891 |
| P08 | JIG7 | 9 | 3.0863° | 0.0355° | 1.15% | 0.99874 |
| P010 | JIG8 | 10 | 3.4475° | 0.0512° | 1.49% | 0.99818 |
| P010 | JIG7 | 10 | 3.1780° | 0.0129° | 0.41% | 0.99952 |
| P011 | JIG8 | 10 | 3.2124° | 0.0392° | 1.22% | 0.99919 |
| P011 | JIG7 | 10 | 2.6794° | 0.0431° | 1.61% | 0.99757 |
| P013 | JIG8 | 10 | 3.0403° | 0.0173° | 0.57% | 0.99862 |
| P013 | JIG7 | 10 | 2.7281° | 0.0301° | 1.10% | 0.99932 |

Kết luận: **within-batch repeatability tốt trên cả hai jig**. CV scalar nằm 0.41–1.61%; đường
360 điểm lặp lại với r trung bình 0.9976–0.9995. Sai khác cross-jig không thể giải thích bằng
noise sweep-to-sweep.

### Cross-jig — cùng motor, batch mới nhất

| Product | NL JIG8 | NL JIG7 | JIG7−JIG8 | Curve r | Centered RMSE | A36 delta |
|---|---:|---:|---:|---:|---:|---:|
| P03 | 2.9319° | 2.8430° | -3.03% | 0.9683 | 0.1780° | +0.52% |
| P08 | 3.1523° | 3.0863° | -2.09% | 0.9851 | 0.1293° | +0.06% |
| P010 | 3.4475° | 3.1780° | -7.82% | 0.9708 | 0.1892° | +0.76% |
| P011† | 3.2124° | 2.6794° | -16.59% | 0.9511 | 0.2232° | +0.64% |
| P013 | 3.0403° | 2.7281° | -10.27% | 0.9430 | 0.2431° | +0.17% |

† P011 mới có một mounting trên mỗi jig. Delta của P011 là quan sát thật trong hai batch đó,
nhưng có mức bằng chứng thấp hơn P03/P010/P013 vì chưa tách được mounting-instance artifact.

- JIG7 cho RawP2P thấp hơn JIG8 ở cả 5/5 cặp, trung bình **-7.96%**, median **-7.82%**,
  nhưng product-dependent (-2.09% đến -16.59%), nên không thể sửa bằng một scalar offset chung.
- Mean paired scalar gap là -0.254°, cùng thang hoặc lớn hơn độ phân tán product trong từng jig
  (SD giữa 5 product: JIG8 0.195°, JIG7 0.220°). Vì vậy jig effect hiện đủ lớn để làm nhiễu
  đánh giá/ranking product.
- Cross-jig full-curve r = 0.9430–0.9851 (mean 0.9637), thấp rõ so với within-batch r >= 0.9976.
  Search circular shift ±180° vẫn cho optimum shift=0 ở cả 5 product; mismatch không phải chỉ do
  lệch zero/index đơn giản.
- Top/bottom-5 extrema overlap thấp và extrema tuyệt đối thay đổi theo product/jig. Full curve
  giữ phần periodic chính nhưng không đồng nhất ở các vùng cực trị quyết định RawP2P.
- **A36 là thành phần đồng bộ tốt nhất:** JIG7/JIG8 chỉ lệch +0.06% đến +0.76% trên cả 5 product.
  Ngược lại A1/A2 và DC/low-order content đổi mạnh, phù hợp với tổng hợp của mounting,
  sensor eccentricity/alignment và motor–fixture interaction.
- Xếp hạng RawP2P của 5 product giữa hai jig chỉ có Spearman rho exploratory khoảng **0.30**;
  chưa đủ tin cậy để dùng hai jig thay thế nhau trong production screening.

### Verdict đối với hai mục tiêu bắt buộc

1. **Đo pure open-loop NL:** đạt ở mức firmware/capture và within-batch repeatability. Dữ liệu
   official dùng canonical 64-sample mean, feedback actuation bằng 0, acquisition sạch và đường
   360 điểm lặp lại cao. Đây là whole-system command-to-rotor NL, chưa phải motor-only INL.
2. **Đồng bộ NL giữa JIG7/JIG8:** **CHƯA ĐẠT / vẫn mở**. A36 đồng bộ tốt, nhưng primary RawP2P,
   low-order harmonics, extrema và một phần full-curve amplitude chưa comparable đủ để tin cậy
   production. Không dùng offset scalar để che mismatch.

### Bước tiếp theo được dữ liệu hỗ trợ

Đóng băng firmware/schema/analyzer hiện tại. Không retune motor command vì sẽ đổi measurand.
Chuyển sang designed Gage R&R/variance-components: cùng một nhóm motor reference, randomize thứ tự
JIG7/JIG8, tối thiểu nhiều remount có torque/orientation kiểm soát trên mỗi jig. Từ đó tách
motor, jig, mount và interaction. Song song, characterization/correction jig-side chỉ được phép
nếu dùng calibration độc lập và được version hóa; không được học correction từ chính motor-under-test
rồi gọi kết quả đó là official open-loop NL.

## Phân rã nguyên nhân cross-jig — cùng motor/cùng firmware nhưng NL khác

**Classification:** `OPEN_LOOP_MEASUREMENT`, analysis-only. Phép loại harmonic bên dưới chỉ dùng
để định vị nguồn sai khác; không định nghĩa lại hoặc sửa official OpenLoopNL.

### Đã loại được firmware, config và acquisition là biến khác nhau

Kiểm tra 100 official-intent sweep thuộc 10 batch đại diện P03/P08/P010/P011/P013 × JIG7/JIG8:

- cùng `BuildID=Aug 12 2026 16:45:25`;
- cùng `GREMSY_COMPAT_OPEN_LOOP_NL_V1`, canonical Q16, 360 điểm, 64 mẫu/điểm;
- cùng `SCURVE40_ABSOLUTE_TICK_V2`, tick 1 ms, 40 commands/degree, power 1.000;
- cùng MA600 Zero/Dir/Filt/Status/Prt/Rmap/CorrCRC =
  `0000/00/05/00/00/00/190A55AD`;
- `FeedbackActuationEnabled=0`, `FinalTargetMode=OPEN_LOOP_UNCHANGED`;
- acquisition OK, zero retry/transport error/jump reject/failed sample/context reacquire;
- settle stability valid, zero ramp timing overrun/lateness.

Khác biệt có chủ đích chỉ là MCU/jig identity (`JIG7 UID=0046...`, `JIG8 UID=003E...`) và cụm
phần cứng đi kèm jig. P08/JIG7 mất một DATA line ở một sweep nên chỉ 9/10 usable; không có dấu
hiệu acquisition firmware tương ứng.

### Cross-jig scalar khác lớn hơn repeatability noise

| Product | |Delta NL| | Pooled within-batch SD | Delta / pooled SD |
|---|---:|---:|---:|
| P03 | 0.0890° | 0.0364° | 2.45× |
| P08 | 0.0659° | 0.0339° | 1.95× |
| P010 | 0.2695° | 0.0373° | 7.22× |
| P011 | 0.5329° | 0.0412° | 12.93× |
| P013 | 0.3122° | 0.0245° | 12.73× |

Do đó mismatch là hiệu ứng có cấu trúc; đặc biệt P010/P011/P013 lớn hơn noise nội batch 7–13 lần.

### DFT của chính đường sai khác `JIG7 - JIG8`

| Product | Centered delta RMS | Delta A1 | Delta A2 | H1+H2 share | Delta A36 | H36 share |
|---|---:|---:|---:|---:|---:|---:|
| P03 | 0.1780° | 0.0719° | 0.1628° | 50.0% | 0.0057° | 0.1% |
| P08 | 0.1293° | 0.0941° | 0.0386° | 30.9% | 0.0062° | 0.1% |
| P010 | 0.1892° | 0.0950° | 0.2000° | 68.5% | 0.0069° | 0.1% |
| P011 | 0.2232° | 0.2623° | 0.0734° | 74.5% | 0.0067° | <0.1% |
| P013 | 0.2431° | 0.2873° | 0.0655° | 73.5% | 0.0079° | 0.1% |

H1+H2 một mình giải thích 31–75% variance cross-jig. H36 gần như không giải thích mismatch,
đồng thời biên độ A36 gốc chỉ lệch 0.06–0.76% giữa jig. Các thành phần residual nổi bật tiếp
theo thường là H3/H4/H12; vì vậy không được kết luận toàn bộ sai khác chỉ là A1/A2.
Trên 5 cặp hiện có, độ lớn NL gap tương quan exploratory `r=0.821` với độ lớn vector delta
H1/H2. Với `n=5`, kiểm định Pearson hai phía cho `p≈0.088`; kết quả này chưa đạt mức ý nghĩa
thống kê 0.05 và không được dùng như bằng chứng xác nhận nguyên nhân. Nó chỉ là giả thuyết để
kiểm tra trên thiết kế Gage R&R lớn hơn.

Counterfactual analysis (không sửa official result):

- bỏ H1+H2 khỏi cả hai mean curve thì correlation tăng lên 0.9822–0.9900;
- bỏ H1–H8 thì correlation tăng lên 0.9895–0.9952, centered RMSE còn 0.067–0.096°;
- control bỏ H3+H4+H12 cũng làm mean correlation tăng từ 0.9637 lên 0.9733; vì vậy bản thân
  hiện tượng "lọc rồi correlation tăng" là một phần hệ quả toán học, không phải bằng chứng
  nhân quả riêng cho H1/H2. H1+H2 cho cải thiện trung bình lớn hơn (mean r=0.9862), nhưng chỉ
  được diễn giải là định vị spectral mismatch;
- H36-only peak-to-peak (`2*A36`) gần như giống nhau giữa jig;
- circular shift ±180° vẫn optimum ở 0 trước khi lọc, nên đây không phải lỗi zero/index đơn giản.

Cơ chế giải thích RawP2P: H36 tạo 36 peak/trough lặp lại ổn định; low-order H1/H2/H3/H4 tạo
envelope chậm nâng một số peak và hạ một số trough. Khi envelope khác giữa jig, peak/trough nào
trở thành global max/min cũng đổi, nên `max(Error)-min(Error)` đổi dù A36 gần như giữ nguyên.

### Remount là bằng chứng độc lập cho thành phần cơ khí/interaction

| Same motor, same jig | NL trước -> sau | Delta | Curve r |
|---|---:|---:|---:|
| P03/JIG8 | 2.8611° -> 2.9319° | +2.47% | 0.9993 |
| P010/JIG8 | 4.1773° -> 3.4475° | -17.47% | 0.9277 |
| P010/JIG7 | 3.5718° -> 3.1780° | -11.03% | 0.9749 |
| P013/JIG8 | 3.0241° -> 3.0403° | +0.54% | 0.9946 |
| P013/JIG7 run1->run2 | 3.1123° -> 2.6928° | -13.48% | 0.9743 |
| P013/JIG7 run2->run3 | 2.6928° -> 2.7281° | +1.31% | 0.9916 |

Mount effect có thể nhỏ với P03/P013 tốt, nhưng đạt 11–17% với P010/P013 ở mounting khác — cùng
thang hoặc lớn hơn cross-jig delta. Nó phụ thuộc motor×jig×mount, không phải một offset cố định.

### Causal conclusion có thể bảo vệ bằng dữ liệu

Mô hình phù hợp nhất hiện tại:

`Error_observed = motor/electrical + jig/sensor geometry + mount + motor×jig×mount interaction + noise`.

- `noise` nhỏ: within-batch r >= 0.9976, scalar CV <= 1.61%;
- `motor/electrical periodic component` được tái tạo tốt: A36 cross-jig lệch <= 0.76%;
- `low-order geometry + motor×jig×mount interaction` chi phối mismatch: H1/H2 variance share
  31–75%, remount có thể làm NL đổi tới 17.5%, extrema và low-order envelope đổi theo jig/mount.
  Không được gọi H1/H2 là thuần jig-side: phase A2 của P013 lặp gần như cùng góc vật lý trên
  JIG7/JIG8, chứng minh ít nhất một motor có thành phần low-order motor-locked mạnh;
- driver gain/current, supply, magnet-sensor gap/tilt/eccentricity, clamping/bearing load là các
  cơ chế vật lý còn khả dĩ. Log hiện không đo phase current, supply hay field magnitude nên chưa
  được phép chọn duy nhất một trong số đó làm root cause cuối cùng;
- không có reference encoder/stage nên cũng chưa tách được MA600 silicon INL khỏi magnetic/mechanical
  alignment. Kết luận chắc chắn hiện chỉ tới cấp **whole-system low-order contribution**; các phần
  motor-side, jig-side, mount-side và interaction chưa thể tách duy nhất bằng log hiện có.

## Audit phản biện phương pháp luận — hạ mức kết luận H1/H2 và phân hạng bằng chứng

**Classification:** `OPEN_LOOP_MEASUREMENT`, analysis-only. Không đổi firmware, command, sampler,
schema, measurand hoặc official NL. Mục này audit lại kết luận S5.3 bằng DATA official đã có.

### 1. Ranking cross-jig và giới hạn mẫu nhỏ

Tính lại từ năm cặp RawP2P trong bảng trên:

- Spearman `rho=0.30`; exact two-sided permutation `p=0.683` với `n=5`;
- nếu tạm loại P011 chưa remount, rho đổi thành `0.80`, nhưng chỉ còn `n=4` nên vẫn không đủ
  để kết luận ranking population;
- vì vậy `rho=0.30` là bằng chứng thực dụng rằng **ranking quan sát được hiện chưa đồng bộ**, không
  phải ước lượng đáng tin của correlation sản phẩm trong production population.

P011 phải được giữ trong bảng để không che dữ liệu, nhưng gắn cờ `single-mount evidence`. Delta
`-16.59%` và `12.93× pooled SD` không được đặt ngang mức xác nhận với các product đã remount.

### 2. Control cho phép loại harmonic

Đã dùng cùng hai batch-mean curve của từng product và cùng phép chiếu DFT, chỉ thay tập harmonic
bị loại. Đây là counterfactual diagnostic, tuyệt đối không thay official OpenLoopNL.

| Product | r gốc | r sau bỏ H1+H2 | r sau bỏ H3+H4+H12 | Delta variance H1+H2 | Delta variance control |
|---|---:|---:|---:|---:|---:|
| P03 | 0.9683 | 0.9831 | 0.9806 | 50.0% | 39.6% |
| P08 | 0.9851 | 0.9892 | 0.9931 | 30.9% | 54.0% |
| P010 | 0.9708 | 0.9900 | 0.9771 | 68.5% | 21.6% |
| P011† | 0.9511 | 0.9863 | 0.9605 | 74.5% | 20.4% |
| P013 | 0.9430 | 0.9822 | 0.9550 | 73.5% | 21.8% |
| **Mean** | **0.9637** | **0.9862** | **0.9733** | — | — |

Control xác nhận hai điều cùng lúc:

1. H1+H2 chứa phần mismatch lớn hơn nhóm control trên P010/P011/P013 và trên trung bình năm cặp.
2. P03 và đặc biệt P08 cho thấy một dải khác cũng có thể cải thiện correlation tương đương hoặc
   mạnh hơn. Vì vậy không được suy từ filtering sang root cause; kết luận hợp lệ chỉ là mismatch
   tập trung ở **low-order spectral content, product-dependent**.

### 3. A2 phase-vector: P013 là phản ví dụ cho mô hình thuần jig-side

Tính lại từ `ErrorRawQ16` của các sweep official, hiệu chỉnh bằng `AnalysisStartRaw`, rồi chia phase
order-2 về góc cơ khí axial (hai hướng tương đương cách nhau 180°):

| Product | A2 physical JIG7 | A2 physical JIG8 | Axial gap |
|---|---:|---:|---:|
| P03 | 19.09° | 157.96° | 41.13° |
| P08 | 26.34° | 19.67° | 6.67° |
| P010 | 18.36° | 165.19° | 33.17° |
| P011† | 12.38° | 177.09° | 15.29° |
| **P013** | **148.79°** | **148.46°** | **0.33°** |

P013 không chỉ là caveat: phase A2 gần như giữ nguyên trên hai jig sau remount. P08 cũng không theo
mẫu jig-shift của P03/P010. Dữ liệu hiện tại vì vậy ủng hộ mô hình vector hỗn hợp:

`H_low_observed = H_motor + H_jig + H_mount + interaction`.

Motor nào có vector motor-side mạnh có thể giữ phase qua jig; motor khác có thể bị vector jig/mount
kéo phase. Hướng khắc phục không được mặc định là một bảng correction jig-side duy nhất, và không
được học correction từ chính DUT.

### 4. Verdict sau audit

- Kết luận cốt lõi không đổi: objective 2 (JIG7/JIG8 interchangeable cho official open-loop NL)
  chưa đạt; firmware/acquisition không giải thích được mismatch đã quan sát.
- Mức kết luận nguyên nhân được hạ đúng: đã khoanh vùng **low-order + mounting/interaction**, chưa
  định danh duy nhất sensor, jig hay motor là root cause.
- Gage R&R tiếp theo phải randomize jig/order, dùng nhiều remount có torque/orientation kiểm soát,
  và phân tích complex harmonic vector (amplitude + phase), full curve, extrema và scalar NL.
- P011 cần remount trước khi dùng như bằng chứng qualification; không có product pass/fail threshold
  nào được suy ra từ audit này.

## Điểm quyết định sau một tháng đồng bộ jig — dừng tuning firmware, chuyển sang calibration/qualification

**Classification:** `OPEN_LOOP_MEASUREMENT`, decision-only. Không đổi firmware hoặc measurand.

### Giới hạn nhận dạng đã chạm tới

Official S4 chỉ có một nguồn quan sát vật lý là MA600 của chính jig. Tại mỗi góc, phép đo chứa đồng
thời motor, nam châm đọc, sensor, gá, lần mount và interaction:

`Error_observed = Error_motor + Error_jig + Error_mount + interaction`.

Không có reference encoder/stage thì đây là một phương trình với nhiều thành phần chưa biết. Test
thêm hoặc retune open-loop command không thể tách duy nhất các thành phần đó. Dữ liệu đã chứng minh:

- firmware/acquisition lặp lại tốt trong batch;
- gá quyết định mạnh vị trí extrema và sensor/die ảnh hưởng biên độ;
- remount có thể đổi NL cùng thang với cross-jig gap;
- P013/P08 cho thấy low-order còn có thành phần motor-side, nên một correction jig-side học từ một
  DUT không tổng quát.

### Ba đại lượng phải phân biệt

1. `Raw whole-system open-loop NL`: official measurand hiện tại. Hai jig phần cứng khác nhau không
   được kỳ vọng tự nhiên cho giá trị giống hệt nếu chưa characterization/calibration.
2. `Calibrated motor-estimate NL`: chỉ hợp lệ khi trừ một curve jig được suy ra từ reference độc
   lập, có CalibrationID/version/traceability; raw curve vẫn phải được giữ nguyên.
3. `Motor supporting features` như A36/harmonic family: hữu ích cho nhận dạng, nhưng không được đổi
   tên thành primary OpenLoopNL.

### Đường triển khai có thể đóng objective 2

1. **Freeze S4 firmware/schema/analyzer**; không chỉnh power/ramp/dwell để ép scalar hội tụ.
2. **Ưu tiên chuẩn tuyệt đối:** dùng rotary stage/reference encoder để quay cùng một reference
   magnet/shaft qua 360°, characterization riêng curve của từng sensor-head+jig.
3. **Nếu chưa có chuẩn tuyệt đối:** dùng transfer-standard assembly cố định, đo randomized trên
   JIG7/JIG8 ở nhiều orientation đã đánh dấu. Đây chỉ cho relative calibration, không chứng minh
   absolute motor NL.
4. Lưu song song `RawErrorCurve` và `JigCalibrationCurve`; correction chỉ thực hiện sau khi official
   DATA đã freeze, không feedback vào command và không học từ DUT đang đánh giá.
5. Qualification bằng Gage R&R randomized: nhiều reference motor, nhiều remount có torque/gap/
   orientation kiểm soát; phân tích variance components, full curve, extrema, complex H1/H2,
   A36 và RawP2P. Chỉ sau đó mới đặt measurement-system comparability limits có version.

Nếu không thể bổ sung reference hoặc transfer standard độc lập, kết luận kỹ thuật phải là: chỉ
được so sánh motor trong cùng một gauge đã khóa; chưa thể tuyên bố JIG7/JIG8 interchangeable cho
primary Raw OpenLoopNL.

## Điểm chốt ưu tiên — mục tiêu cốt lõi vẫn là độ lặp lại giữa nhiều jig, không phải các nhánh phụ

**Classification:** decision-only, không đổi measurand. Ghi lại để mọi việc tiếp theo (kể cả nhánh
closed-loop/response-capability đã khảo sát bằng dữ liệu S2) không làm lệch trọng tâm khỏi objective 2
đã khóa trong AGENTS.md: cùng một motor đo trên các jig khác nhau phải cho kết quả lặp lại được.

### Hiện trạng so với đúng tiêu chí này

| Thước đo | Trong một jig | Giữa JIG7/JIG8 |
|---|---:|---:|
| CV của NL scalar | 0.41-1.61% | - |
| Curve correlation r | 0.9976-0.9995 | 0.9430-0.9851 |
| Spearman rho xếp hạng 5 sản phẩm | - | 0.30 |
| NL scalar lệch | - | 2.1%-16.6%, product-dependent |

**Chưa đạt.** Trong-jig lặp lại tốt (loại trừ firmware/acquisition khỏi nguyên nhân); giữa-jig thì
không, đặc biệt chỉ số quyết định thực dụng nhất (xếp hạng sản phẩm cross-jig, rho=0.30) gần như
không tương quan.

### Nguyên nhân đã xác định, không còn là câu hỏi mở

Motor x jig interaction có thật ở low-order harmonics (P013/P08 gần như không đổi phase A2 cross-jig,
P03/P010/P011 đổi mạnh) -- nên một offset hiệu chỉnh chung cho hai jig không giải quyết được (đã tính:
chỉ giảm 44% sai số, và làm sai hướng với P03/P08).

### Đường đã đồng thuận để đóng objective 2

Freeze firmware hiện tại; Gage R&R randomized (nhiều motor x nhiều remount có ghi torque/orientation x
random hóa thứ tự jig) để tách variance components; nếu cần trị tuyệt đối thì bổ sung reference/transfer
standard độc lập. Các nhánh khác (response-capability closed-loop qua dữ liệu S2, tracking dynamic) là
thông tin bổ trợ hữu ích, không thay thế được yêu cầu lặp lại cross-jig này. Đây là giới hạn nhận dạng của hệ đo, không phải thiếu thêm một vòng tune.
