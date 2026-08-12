---
type: "query"
date: "2026-08-11T06:42:41.038975+00:00"
question: "S2-P08-JIG8-remount04-test-1-v5-8 remount 4"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Tổng kết phiên làm việc 2026-08-03: MOUNT_PRECHECK_V1 M0 + phát hiện root-cause \" cụm sensor+gá\\ Tổng", "kết", "phiên", "làm", "việc", "2026-08-04:", "xác", "nhận", "hiệu", "ứng"]
---

# Q: S2-P08-JIG8-remount04-test-1-v5-8 remount 4

## Answer

Expanded via graph vocab: [mount, remount, sensor, harmonic, phase, nonlinear, curve, error, response, stability, tracking, motor]. Remount04 confirms remount03 forms a stable near-centered mounting family, distinct from eccentric remount02. R3/R4 official NL=0.26184/0.23984 deg, H2=0.01307/0.01267 deg, A36=0.09508/0.09366 deg, official response=99.10/99.19%, and 360-degree curve correlation is 0.9812 at zero shift. MOUNT_PRECHECK vector distances R3-R4 are D1=0.00237 deg, D2=0.00107 deg; eccentric R2 to R4 is D2=0.03974 deg while D1 only 0.00262 deg. Therefore H2, not H1 alone, is the strongest discriminator for this eccentric mounting event. Both good remounts share hard regions P148/P158. V5.8 remains diagnostic-only (EligibleForStatistics=0), so this is a mounting/mechanism classification rather than production NL approval.

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
- analyze_nl_stability.py