---
type: "query"
date: "2026-08-12T06:53:12.033751+00:00"
question: "What percentage of the current code is ready to measure pure Gremsy-style open-loop NL?"
contributor: "graphify"
outcome: "useful"
---

# Q: What percentage of the current code is ready to measure pure Gremsy-style open-loop NL?

## Answer

Engineering-readiness estimate: checked-in default source about 72/100, production-qualified trustworthy open-loop NL about 55/100, while the latest V5.8/V5.9a diagnostic artifact is only about 35/100 aligned with pure open-loop because sweep-point creep/terminal correction is enabled and the artifact explicitly sets EligibleForStatistics=0. Default source has ENABLE_SWEEP_POINT_CREEP=0, fixed S-curve observation-only ramp, 64-sample mean, Gremsy-compatible Error and RawP2P, clean acquisition, 360-point metrics, and corrected analyzer gating. Remaining critical gaps are no explicit official-profile compile isolation, canonical Q16 still shadow, separate 65th raw read, schema v5/OfficialResultSource=LEGACY, and no dedicated V6 open-loop hardware qualification.

## Outcome

- Signal: useful