---
type: "query"
date: "2026-08-11T05:32:44.232189+00:00"
question: "phân tích S2-P03-JIG8-remount01-test-2-v5-8 và remount02 trước P08"
contributor: "graphify"
outcome: "useful"
source_nodes: ["MotorResponseTimingAnalysis", "analyze_nl_stability.py", "V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm"]
---

# Q: phân tích S2-P03-JIG8-remount01-test-2-v5-8 và remount02 trước P08

## Answer

Expanded query: [response, timing, creep, measurement, nonlinear, remount, motor, point, error, stability]. Both logs reanalyzed with current tool: DIAGNOSTIC PASS, 1484 timing rows, TelemetryComplete=1, 3/3 official diagnostic sweeps, acquisition clean. Official-only reached rates are 98.47% and 98.11%; mean CommandToStop is virtually identical 190.993 vs 190.961 ms. Repeated failure families are highly stable: common points 107/108, 187/188, 347/348; remount02 additionally has point28 repeated. Mean 360-point error curves correlate r=0.9858 at zero circular shift, RMSE=0.01393 deg. Robust NL means 0.273873 vs 0.277121 deg (delta 0.003249 deg, 1.19%); RMS_AC 0.082303 vs 0.082926; A2 0.008834 vs 0.008807; A36 0.099579 vs 0.101047 with H36 phase delta 0.30 deg. Home duration changes 6.831s to 5.312s while NL remains stable, suggesting home affects time/heat more than measured NL for this pair. Phase timing sums close within 0.005 ms. These P03 data strongly validate V5.8 instrumentation/remount repeatability but do not replace the planned matched P08/JIG8 point308 gate.

## Outcome

- Signal: useful

## Source Nodes

- MotorResponseTimingAnalysis
- analyze_nl_stability.py
- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm