---
type: "query"
date: "2026-08-11T06:00:49.296910+00:00"
question: "đây là lần mount bị lệnh tâm so với mount 1 hãy tìm ra data chứng mình là bị lệnh tâm"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Tổng kết phiên làm việc 2026-08-03: MOUNT_PRECHECK_V1 M0 + phát hiện root-cause \" cụm sensor+gá\\ Tổng", "kết", "phiên", "làm", "việc", "2026-08-04:", "xác", "nhận", "hiệu", "ứng"]
---

# Q: đây là lần mount bị lệnh tâm so với mount 1 hãy tìm ra data chứng mình là bị lệnh tâm

## Answer

Expanded via graph vocab: [mount, mounting, remount, alignment, sensor, harmonic, phase, nonlinear, curve, error, response, stability]. P08/JIG8 mount1 V5.5 versus current eccentric V5.8: precondition MOUNT_PRECHECK H1 0.00374->0.01355 deg (3.62x), H2 0.00797->0.04840 deg (6.07x), vector distances D1=0.01226 deg and D2=0.04900 deg. Official geometric family H1/H2/H4/H8 rises 3.1x/6.1x/11.1x/6.1x while H36 changes only -13%; phases are nearly perfectly coherent within the eccentric batch. Robust NL rises 0.22794->0.59288 deg and repeated hard-cap failures rise from 1 point/run to 16-17 points/run. Curve correlation is only 0.627 and circular shifting does not improve it, so this is shape deformation rather than simple zero-angle rotation. This strongly proves mounting-geometry misalignment, though logs alone cannot measure radial offset in mm or separate eccentricity from tilt/air-gap error.

## Outcome

- Signal: useful

## Source Nodes

- Tổng kết phiên làm việc 2026-08-03: MOUNT_PRECHECK_V1 M0 + phát hiện root-cause " cụm sensor+gá\ Tổng
- kết
- phiên
- làm
- việc
- 2026-08-04:
- xác
- nhận
- hiệu
- ứng
- "
- board
- mới\, tách bạch gá vs sensor, và đề xuất phương án đánh giá NL bền vững theo jig
- End-of-Shaft Mounting Verification Test Plan (MA600A)
- V5.8-TIME-DIAG — đo thời gian đáp ứng command theo từng điểm