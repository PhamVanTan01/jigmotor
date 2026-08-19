# Session summary — 2026-08-19

## System architecture review (NL + Power split, MISRA C target)

Full review, two rounds of independent counter-review (accepted 13/14 findings across both
rounds, pushed back on 3 with verified technical grounds), final sign-off with 2 closing
acceptance criteria and a locked 7-step implementation order. Full detail:
`docs/system-architecture-nl-power-review-2026-08-18.md` (file dated 08-18, review concluded
and approved on 08-19).

## QuickScreen3Run firmware build

Built an isolated Measurement image (`Build/QuickScreen3Run/`) using the project's existing
`NL_TEST_REPEAT_3_RUNS` mode (1 precondition + 3 official sweeps per button press, protocol ID
`ONE_FULL_SWEEP_120S_V1_FAST3`) instead of the standard 10-run batch — for fast A/B screening
of mechanical changes (sensor gap, mount path) where the effect being looked for is expected to
be large relative to noise. New script: `scripts/build_quick_screen_3run.ps1`, mirrors
`build_dual_image.ps1`'s isolated-directory technique; does not touch the standard Release
build. Verified: correct protocol string compiled in, CCM headroom ~48.4KB free (well above the
8KB minimum). Explicit warning baked into `build_info.txt` and the analysis discipline: results
from this image screen for "did anything change," not a qualified measurement — confirm on the
standard 10-run build before trusting a finding from it.

## P013/JIG7 sensor-gap and mechanical-path investigation (run01-run09)

Extensive sequence of remounts/gap adjustments on JIG7, tracked as "mechanical path 1" / "path
2" with sensor-gap values (2282mm baseline, then 2300mm, then a 3000mm variant). Findings
across the sequence (see chat log for full detail, not reproduced here):

- run01-03: established a tight, repeatable P013/JIG7 baseline (A2 physical angle 137-151 deg,
  RawP2P 2.68-3.11 deg, A36 0.860-0.862 deg).
- run04 onward: sensor gap changed; A2 phase and RawP2P wandered substantially across
  run04-08 before a path1-vs-path2 A/B comparison at matched gap (2300mm) isolated the
  instability specifically to "path 2," not the gap value itself (path1/run08: CV 0.54%;
  path2/run06+07: CV 3.9-4.5%, same gap).
- Curve overlay (path1 vs path2, matched gap): zero-shift r=0.9667, near-perfect top-5 peak
  overlap (motor-dominant region, A36) but weak bottom-5 overlap (1/5 -- low-order/path-side
  region), consistent with the session's established A36-stable/A1-A2-mount-sensitive model.

## Critical correction: run05-run08 were mislabeled P013, actually P010

User identified a labeling mistake: partway through the gap/path sequence (intended to switch
test subjects from P013 to P010 per an earlier suggestion), the physical motor was swapped to
P010 but the log filenames were left saying P013.

**Verified independently against data, not taken on the user's recollection alone** (per this
project's standing rule to check peak-signature data before accepting a verbal
mount/identity claim): A36 is an established, highly stable per-motor fingerprint
(motor-locked, ~0.29% CV even across different jigs/mounts for the same unit).

- P013's own confirmed A36: 0.860-0.862 deg (from unambiguous run01-03).
- P010's own confirmed A36 (from this project's original, unambiguous P010 testing on
  JIG7/JIG8 earlier in the week): 0.9078-0.9180 deg.
- Checked every "P013"-labeled file from run04 onward against these two fingerprints:

| File (as labeled before correction) | A36 | Matches |
|---|---:|---|
| run04 | 0.862 | P013 (correct as labeled) |
| run05 | 0.918 | **P010** |
| run06 (2281mm) | 0.9125 | **P010** |
| run06-2300mm-path-2 | 0.9182 | **P010** |
| run06-3000mm | 0.9181 | **P010** |
| run07-2300mm-path-2 | 0.9179 | **P010** |
| run08-2300mm-path-1 | 0.9159 | **P010** |
| run09-2300mm-path-2 | 0.868 | P013 (motor was swapped back) |

**Action taken**: renamed all 22 affected files (`run05`, `run06-2281-mm`,
`run06-2300mm-path-2`, `run06-3000mm`, `run07-2300mm-path-2`, `run08-2300mm-path-1` -- every
extension: `.txt`, `.analysis.txt`, `.analysis.json`, `.metrics.csv`, `.nl.png`, `.polar.png`
where present) from `S4-P013-...` to `S4-P010-...` in `tools/dist/captured-logs/`. `run04` and
`run09-2300mm-path-2` were left as `P013` (fingerprint-confirmed correct). No file contents
were edited -- the firmware's own `MotorID` field is always `UNKNOWN`/`UNSET` internally (no
independent motor-ID sensing exists), so the filename was the only place the label lived.

**Why this matters going forward**: the "RawP2P climbed to ~3.5-3.7 deg after the gap change"
and the dramatic A2-phase wandering seen across the old run05-08 were not purely a P013 mount/
gap effect -- P010 has a naturally higher baseline RawP2P (3.18-4.18 deg, established from its
own original testing) independent of any of this gap/path work. The path1-vs-path2 CV
comparison (§ above) remains valid on its own terms, since run06/07/08 were consistently the
same (P010) motor throughout that specific comparison -- only the framing of "P013's response
to gap/path changes" was wrong for that middle stretch. Do not reuse any "P013 gap-sensitivity"
conclusion drawn from run05-08 without re-checking which motor it actually describes.

## Full path-2 evaluation across motors (2300mm, old sensor) -- reverses the "path 2 is bad" read

With P010's mislabeling corrected, the earlier "path 2 has a repeatability problem" conclusion
(drawn only from P010's run06/07, RawP2P CV 3.88-4.52%) was re-tested against 4 independently-
run09-labeled motors on path 2 (correct labels): P03, P08, P011 (after 1 capture failure and
1 successful retest -- `_02` suffix, Closure=-0.203 deg on the first attempt), P013.

| Motor | RawP2P | CV | A2 physical angle | Own JIG7 baseline (angle) |
|---|---:|---:|---:|---|
| P03 | 2.804 deg | 0.47% | 11.66 deg | 19.9 deg |
| P08 | 3.540 deg | 0.60% | 49.24 deg | 26.3-30.9 deg |
| P011 | 2.775 deg | 0.32% | 13.53 deg | 12.38 deg (closest match seen all day) |
| P013 | 2.939 deg | 0.44% | 141.76 deg | 137-151 deg |

All four land in the 0.32-0.60% CV range -- excellent. **Revised conclusion**: the elevated CV
seen earlier was specific to P010 (or to those first two path-2 attempts specifically, before
path 2 had been exercised), not a general path-2 mechanical defect. P010 should be re-tested on
path 2 again to settle which explanation is correct, but path 2 itself is not disqualified.

## Path 1 data added for P08 and P011; direct path1-vs-path2 curve comparison

New path-1 tests (`run011-2300mm-path-1`) for P08 and P011, correlated against each motor's own
path-2 data:

| Motor | RawP2P path1 | RawP2P path2 | r (zero-shift) | r (best shift) |
|---|---:|---:|---:|---:|
| P08 | 3.140 deg | 3.528 deg (+12.3%) | 0.855 | 0.934 (shift=-80) |
| P011 | 3.520 deg | 2.765 deg (-21.5%) | **0.936** | 0.936 (shift=0, no shift needed) |

P011's shape is essentially identical between path1 and path2 (no shift needed) despite a real
21.5% amplitude difference -- another case of "shape preserved, amplitude moved," consistent
with the low-order-harmonic-carries-the-amplitude-difference model established earlier today.
P08 needed an 80-index shift to align, similar in character to earlier gap-change cases.

## Sensor swap (mid-session): re-tested P08, P011, P013 on path 2 with a new physical MA600 unit

User replaced the physical sensor (not a gap/path change) partway through, then had the results
evaluated blind before revealing what changed -- results were interpreted first, motor identity
confirmed via A36 fingerprint as usual, then the change was disclosed for interpretation.

| Motor | RawP2P old sensor | RawP2P new sensor | Delta | r (zero-shift) |
|---|---:|---:|---:|---:|
| P08 | 3.528 deg | 3.113 deg | -11.8% | **0.920 (shift=0)** |
| P013 | 2.939 deg | 2.851 deg | -3.0% | **0.978 (shift=0)** |
| P011 | 2.765 deg | 2.972 deg | +7.3% | **0.987 (shift=0)** |

(P011's first sensor-swap retest attempt failed capture entirely -- `run011`, Closure=-0.508 deg,
0/3 official; second attempt `run012` succeeded, PASS 3/3. P011 has now failed capture twice on
path 2 across the session, both times on precondition closure -- worth a physical-mount check
if it recurs a third time.)

**Signature identified**: every sensor-swap comparison needed **zero index shift** to reach peak
correlation, unlike every gap/path mechanical change tested earlier (which needed 20-90 index
shifts). This gives an empirical way to distinguish the two kinds of change from data alone
going forward: a geometry/mount change perturbs phase (needs a shift to correlate well); a
sensor-chip swap leaves phase alone and only perturbs amplitude modestly and non-uniformly
across motors (consistent with ordinary chip-to-chip manufacturing variance, not a mount effect).

## Three-way path comparison (path1 / path2-old-sensor / path2-new-sensor), P08 and P011

| Motor | path1 vs path2-old | path1 vs path2-new | path2-old vs path2-new |
|---|---:|---:|---:|
| P08 | 0.855 | **0.977** | 0.920 |
| P011 | 0.936 | 0.960 | **0.987** |

Cross-motor consistency of each path-pair (mean and spread across the two motors that have all
three configurations tested):

| Path pair | Mean r | Spread (max-min) |
|---|---:|---:|
| path1 vs path2-old | 0.896 | 0.081 |
| **path1 vs path2-new** | **0.969** | **0.017 (tightest)** |
| path2-old vs path2-new | 0.962 (n=3 incl. P013: 0.978) | 0.067 |

`path1 vs path2-new` is both the highest-average and most motor-consistent pairing measured so
far -- notably, for P08 specifically, path1-vs-path2-old was the *worst* pairing in the whole
table (0.855, needed an 80-index shift), while path1-vs-path2-new became the *best* (0.977, no
shift) for the same motor. This suggests the sensor swap may have resolved whatever was causing
P08's path1/path2 misalignment under the old sensor, rather than path1/path2 being intrinsically
incompatible. Only 2 motors confirm this so far -- same caveat as everywhere else this session,
more motors needed before treating "path1~path2-new is motor-independent" as established.

## Conceptual note: why a path-pair can look consistent across motors while motors still differ

Recorded because it came up as a direct question and is easy to get backwards: "how similar is
path A to path B for a given motor" (a property of the measurement system) and "how similar is
motor X to motor Y on a given path" (a property of the physical motors) are independent axes.
A path-pair's relationship can be stable across different motors (as path1-vs-path2-new appears
to be) while the motors themselves remain visibly different from each other on any single path
-- these are not in tension; the first is about whether the measurement configuration distorts
consistently, the second is about real physical differences between units, which the whole
point of NL measurement is to be able to see. This also contrasts with the original JIG7-vs-
JIG8 finding from 2026-08-18, where the *cross-jig* relationship was motor-dependent (a real
motor x jig interaction, evidenced by P013/P08 barely shifting cross-jig while P03/P010/P011
shifted heavily) -- here, within-JIG7 path1-vs-path2-new looks close to motor-independent by
contrast, which would be the more favorable condition for building a transferable correction,
if confirmed with more motors.

## Consolidated NL value table (RawP2P, CV, A36) for this session's path/sensor work

| Motor | Config | RawP2P | CV | A36 |
|---|---|---:|---:|---:|
| P08 | path1 | 3.140 deg | 0.40% | 0.887 deg |
| P08 | path2-old-sensor | 3.540 deg | 0.60% | 0.894 deg |
| P08 | path2-new-sensor | 3.113 deg | 0.84% | 0.894 deg |
| P011 | path1 | 3.520 deg | 0.59% | 0.873 deg |
| P011 | path2-old-sensor | 2.775 deg | 0.32% | 0.878 deg |
| P011 | path2-new-sensor | 2.972 deg | 1.08% | 0.877 deg |
| P013 | path2-old-sensor | 2.939 deg | 0.44% | 0.868 deg |
| P013 | path2-new-sensor | 2.853 deg | 0.46% | 0.866 deg |
| P010 (reference) | path1 | 3.583 deg | 0.54% | 0.916 deg |
| P010 (reference) | path2 (first 2 attempts) | 3.57-3.61 deg | 3.88-4.52% | 0.918 deg |

A36 stayed within each motor's own established fingerprint band throughout all of today's
path/sensor changes (P08 ~0.887-0.894, P011 ~0.873-0.878, P013 ~0.866-0.868, P010 ~0.916-0.918)
-- confirms none of today's mechanical/sensor changes silently swapped motors again, and
continues to validate A36 as a reliable per-motor identity check.

## Open items for next session

1. Re-test P010 on path 2 (new sensor) -- only motor not yet re-confirmed after the mislabeling
   correction; needed to know if its earlier elevated CV was motor-specific or a first-exposure
   transient.
2. Get P013 (and ideally P03) onto path 1 -- path1 data currently only exists for P08, P011,
   and P010, so the "path1 vs path2-new is motor-independent" read has an n=2 sample size.
3. Investigate P011's repeated precondition-closure capture failures on path 2 (twice now) if a
   third occurrence happens -- possible physical-mount issue specific to that motor/path
   combination, not yet root-caused.
4. `run06-3000mm` on P010 has full analysis on disk but was not reviewed in detail this
   session -- available if a third gap data point is wanted.
