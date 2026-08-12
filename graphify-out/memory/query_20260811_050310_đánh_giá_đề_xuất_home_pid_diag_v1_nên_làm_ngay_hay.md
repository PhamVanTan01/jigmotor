---
type: "query"
date: "2026-08-11T05:03:10.469151+00:00"
question: "Đánh giá đề xuất HOME_PID_DIAG_V1 nên làm ngay hay xếp sau V5.8"
contributor: "graphify"
outcome: "corrected"
correction: "Home gate is not identical to sweep settle, and LockStartPosition changes/re-zeros the reference after home."
source_nodes: ["MoveToZeroAndCheckDirection", "WaitForPointSettle", "LockStartPosition", "V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm"]
---

# Q: Đánh giá đề xuất HOME_PID_DIAG_V1 nên làm ngay hay xếp sau V5.8

## Answer

Expanded query: [home, controller, settle, creep, response, timing, thermal, measurement, nonlinear, zero]. Most of the proposal is sound, but one important claim is false: home and sweep-point settle do not use the same gate. Home requires abs(error)<0.05 deg for 501 updates at about 2 ms; WaitForPointSettle requires inter-sample motion <=9 raw for 8 polls and target proximity only within 910 raw (~5 deg), after which creep may target +/-16 raw. Also LockStartPosition runs after home, moves to the nearest electrical zero and then re-zeros, so the final home encoder position is not directly the NL point-0 reference. Recommendation: finish the active V5.8 hardware gate without changing the flashed build, then run HOME_PID_DIAG_V1; plan/code may be prepared behind a default-off compile flag now. Avoid naming collision: current implemented V5.8 is TIME-DIAG, while session-summary also called an unimplemented cap-400 terminal correction V5.8; rename the latter V5.9 or similar.

## Outcome

- Signal: corrected
- Correction: Home gate is not identical to sweep settle, and LockStartPosition changes/re-zeros the reference after home.

## Source Nodes

- MoveToZeroAndCheckDirection
- WaitForPointSettle
- LockStartPosition
- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm