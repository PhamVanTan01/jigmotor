---
type: "query"
date: "2026-08-12T07:15:50.610968+00:00"
question: "Predict NL results from the new GREMSY_COMPAT_OPEN_LOOP_NL_V1 firmware"
contributor: "graphify"
outcome: "useful"
---

# Q: Predict NL results from the new GREMSY_COMPAT_OPEN_LOOP_NL_V1 firmware

## Answer

Using V5.9 MOTION.PositionErrorRaw captured after ramp/settle but before creep, reconstructing Error_i approximately as (gap_i-gap_0)*360/65536 predicts: P03/JIG8 remount01 RawP2P 3.21-3.26 deg, RobustP2P 2.76-2.81, RMS 0.742-0.745, A36 0.914-0.919; P03 remount02 RawP2P 3.75-3.86, Robust 2.89-2.91, RMS 0.748-0.753, A36 0.917-0.925; P08/JIG8 RawP2P about 3.05-3.33, Robust 2.88-2.98, RMS 0.739-0.755, A36 0.850-0.856; P09/JIG8 RawP2P 2.73-2.75, Robust 2.60-2.65, RMS 0.680-0.684, A36 0.839-0.844. This agrees in scale with historical creep-off P03/JIG1 RawP2P 2.735-2.759, RMS 0.690-0.694, A36 0.903-0.908. Prediction is approximate because MOTION is a settle final sample, not canonical mean, and prior points in those logs were still creep-corrected. Expect valid open-loop metrics to rise sharply versus V5.9, more pronounced extrema/H36, shorter test time, possibly more invalid sweeps, and no automatic cross-jig convergence.

## Outcome

- Signal: useful