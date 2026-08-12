---
type: "query"
date: "2026-08-11T06:23:38.617330+00:00"
question: "S2-P038-JIG8-remount03-test-1-v5-8 remount 03 tôi sẽ test thêm remount 04"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Tổng kết phiên làm việc 2026-08-03: MOUNT_PRECHECK_V1 M0 + phát hiện root-cause \" cụm sensor+gá\\ Tổng", "kết", "phiên", "làm", "việc", "2026-08-04:", "xác", "nhận", "hiệu", "ứng"]
---

# Q: S2-P038-JIG8-remount03-test-1-v5-8 remount 03 tôi sẽ test thêm remount 04

## Answer

Expanded via graph vocab: [mount, remount, sensor, harmonic, phase, nonlinear, curve, error, response, stability, tracking, motor]. Assuming P038 is the same physical P08, remount03 returns close to the centered family and independently confirms remount02 was geometrically abnormal: official H2 falls 0.05203->0.01307 deg, Robust NL 0.59288->0.26184 deg, RMS 0.09707->0.08087 deg, A36 recovers 0.08345->0.09508 deg, and response rises 95.59%->99.10%. Failures collapse from 49 official failures over 16 recurring points to 10 failures concentrated mainly at points 148/158. Remount04 should be kept same motor/jig/firmware/clamp protocol and used as independent confirmation; current thresholds are provisional, not production gates.

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