# Plan MATLAB — phân tích offline A2/A2B/A2C power-envelope

## Mục tiêu

Dùng MATLAB R2025 để phân tích độc lập log alignment của firmware, tìm theo từng góc rotor ban đầu khoảng power có thể vừa đạt offset vừa không vượt safety guard. MATLAB không được gửi lệnh điều khiển motor, thay đổi firmware, hoặc tự tăng power trên hardware.

## Trạng thái ban đầu

- MATLAB executable: `E:\matlab\bin\matlab.exe`.
- Firmware/log canonical checker: `scripts/analyze_control_a2.ps1`.
- Profile hiện tại: `CONTROL_A2C_FIXED_PHASE_ALIGN_P06_H500_V1`.
- Motor: 12 poles, 6 pole-pairs; một electrical cycle = 60 mechanical degree = 10923 encoder raw (rounded firmware constant).

## Kiến trúc dữ liệu

```text
UART raw log
  -> scripts/analyze_control_a2.ps1
  -> summary CSV + evidence CSV (canonical input)
  -> MATLAB validation/load/analysis/plots
  -> MATLAB report CSV + PNG/PDF (decision support only)
  -> người vận hành chọn artifact P07/P08... hoặc dừng
```

Raw log là bằng chứng gốc. PowerShell là lớp kiểm tra schema, identity, timing, SPI và hard-gate. MATLAB chỉ phân tích file CSV đã vượt parsing.

## Phase M0 — xác nhận môi trường

1. Chạy MATLAB ở batch mode, không mở GUI:

   ```powershell
   & 'E:\matlab\bin\matlab.exe' -batch "disp(version); ver"
   ```

2. Ghi nhận version và các toolbox thực sự có. Bản đầu chỉ cần MATLAB cơ bản; Statistics and Machine Learning Toolbox hoặc Signal Processing Toolbox là tùy chọn, không được là dependency bắt buộc.
3. Tạo thư mục source `analysis/matlab/` và giữ output ở `analysis/output/`. Output, `.mat`, PNG/PDF, và raw log không commit mặc định.

**Gate M0:** batch command exit code 0, không yêu cầu kết nối board/motor.

## Phase M1 — contract CSV và units

1. MATLAB loader chỉ nhận hai loại input do PowerShell tạo:
   - `*-summary.csv`: một row cho một run;
   - evidence CSV: `Seq`, `Phase`, `TravelRaw`, `TravelMilliDeg`, `PowerPpm`, `DeltaRaw`, timing và SPI metrics.
2. `validateA2Schema.m` kiểm tra required fields, profile, sample count, units và sequence liên tục. Bất kỳ row `GatePass=false` phải được phân loại là hard fault, không được dùng để tính settled position.
3. Canonical conversion được khóa:
   - mechanical degree = `raw * 360 / 65536`;
   - electrical modulo = `mod(raw, 10923)`;
   - chỉ so sánh settled position trong miền modulo, không dùng encoder raw tuyệt đối.

**Gate M1:** MATLAB đọc đúng A2/A2B/A2C sample, phát hiện thiếu cột hoặc profile không biết, và tái tạo metric PowerShell với sai số không quá 1 raw / 0.006°.

## Phase M2 — MATLAB analysis package

Tạo các script/function nhỏ, không dùng Live Script làm source chính:

```text
analysis/matlab/
  run_a2_power_envelope.m
  load_a2_summary.m
  load_a2_evidence.m
  validate_a2_schema.m
  compute_a2_metrics.m
  plot_a2_run.m
  plot_a2_power_envelope.m
  export_a2_report.m
  tests/test_a2_analysis.m
```

`run_a2_power_envelope.m` nhận directory CSV và tạo:

- `run_metrics.csv`: gate, power, start phase, onset, max-step, max-travel, hold drift, settled modulo;
- `power_envelope.csv`: kết luận theo power và start phase;
- one plot/run: travel và power theo thời gian;
- one batch plot: settled modulo circular scatter và max-step vs power.

Không tạo C code, Simulink model hay serial-port control ở phase này.

## Phase M3 — thuật toán quyết định power-envelope

Với từng start phase, MATLAB tính:

- `P_safe`: power cao nhất có tất cả hard-gate pass;
- `P_move`: power thấp nhất có movement đạt tiêu chí đã định;
- `P_align`: power thấp nhất có settled modulo nằm trong tolerance của reference;
- `margin = P_safe - max(P_move, P_align)`.

Chỉ kết luận có power chung khi mọi start phase có `margin > 0` với dự phòng. Một lần `SAMPLE_STEP_LIMIT` hoặc `TRAVEL_LIMIT` tại một power là điểm dừng envelope cho phase đó; MATLAB không được suy diễn rằng power cao hơn an toàn.

Tiêu chí initial đề xuất để review, chưa phải acceptance chính thức:

- ít nhất 3 start phase khác nhau trong electrical cycle;
- zero hard-gate và zero acquisition/timing error;
- tail 20 ms không drift quá 0.05°;
- settled modulo giữa các run nằm trong tolerance do operator chốt.

## Phase M4 — cross-check và regression

1. Tạo fixture CSV nhỏ với run A2, A2B, A2C pass và một run step-fault.
2. MATLAB unit tests so sánh summary metrics với expected values.
3. Chạy cùng input bằng PowerShell và MATLAB; report phải chỉ rõ hai lớp có kết luận gate giống nhau.
4. Chỉ commit MATLAB source, fixture tổng hợp và test; không commit raw UART logs hay hardware report sinh ra.

## Phase M5 — quy trình hardware cho A2C

1. Chạy P06 tại ba start phase; giữa các run chỉ xoay rotor khi PWM đã disable.
2. Chạy PowerShell analyzer, rồi MATLAB report trên đúng output CSV.
3. Nếu P06 đều safe nhưng chưa đạt offset, tạo P07/H500 artifact riêng.
4. Lặp tăng 1% theo artifact riêng; không thử power cao hơn sau hard-gate.
5. Nếu không có common safe interval trên ba start phase, dừng fixed-phase power-envelope và chuyển sang thiết kế alignment có phase trajectory.

## Phase sau khi alignment đạt gate

Chỉ khi M5 chứng minh được equilibrium lặp lại mới mở phase mô hình hóa/PID:

- identification friction, inertia, cogging từ trace;
- mô phỏng ramp/trajectory ở 1 kHz;
- tune PID offline rồi port tay sang firmware;
- firmware guard vẫn là authority cuối cùng.
