# Session summary — 2026-08-21

## P011 remount repeatability, path-1, 2 more independent remounts (Today1/Today2)

- Classification: `OPEN_LOOP_MEASUREMENT`, `QuickScreen3Run` (`DIAGNOSTIC_ONLY`), same path-1 slot, cross-day
  from the 2026-08-20 R1/R2/R3 series (see `session-summary-2026-08-20.md`).
- Logs: `S4-P011-JIG7-openloop-v1-test-2remountR3-path-1.txt`, `...test-2remountR2-path-1.txt`.
- A36 0.875-0.884 deg, matches P011 band; correct motor confirmed.
- Both new remounts fall in the same cluster as R1/R2/R3: r0=0.994-0.997 vs each of R1/R2/R3, best_shift=0,
  RMSE 0.075-0.096 deg — comparable to the internal R1/R2/R3 spread (0.058-0.084 deg).
- Full 5-remount set (R1,R2,R3,Today1,Today2), path-1, 2 calendar days:
  - RawP2P: 3.48/3.41/3.39/3.42/3.36 deg, mean=3.413 deg, cv=1.17% (n=5).
  - H36 cv=0.32% (fingerprint stable); H1 cv=5.04%; H2 cv=11.25% (still the least stable harmonic).
  - All 5 vs `run011` (2026-08-19 path-1 baseline): r0=0.915-0.939, best_shift=40 deg every time,
    RMSE 0.568-0.661 deg — 5-10x the intra-cluster RMSE, confirming `run011` is a systematic outlier, not
    path-1 drifting.
  - Retracted a premature claim from the n=3 pass: the pointwise-sd peak location moved from idx=85 (n=3)
    to idx=15 (n=5), so "variance concentrates near the N-S zone" is not supported at this sample size;
    only the aggregate finding (intra-cluster noise << gap to `run011`) stands.

## P011, path-2, 2 independent remounts today (R1/R2) — mislabel check, then a jig-level finding

- Classification: `OPEN_LOOP_MEASUREMENT`, `QuickScreen3Run`, `DIAGNOSTIC_ONLY`.
- Logs: `S4-P011-JIG7-openloop-v1-remountR1-path-2.txt`, `...remountR2-path-2.txt`.
- First pass flagged a possible path mislabel: `remountR1-path-2`'s idxMax/idxMin (354/97) matched the
  path-1 cluster exactly, not path2_old/path2_new (17-274 range), and it correlated with `path1_mean` at
  shift=0 (r0=0.977) better than with path2_old/path2_new (shift=40 required both times). User confirmed
  the physical mount was genuinely path-2 (not a repeat of the earlier P013/P010 mislabel pattern).
- With that confirmed, R2 was captured for a second independent check: R1 vs R2 r0=0.997, best_shift=0,
  RMSE=0.077 deg — internally as tight as the path-1 remount cluster, i.e. today's path-2 mounting is itself
  repeatable, it has just moved.
- Both R1 and R2 remain far closer to `path1_mean` (RMSE 0.180-0.236 deg, no shift) than to `path2_old`/
  `path2_new` (RMSE 0.307-0.443 deg, shift=40 both times); R2 is if anything closer to path1_mean than R1.
- Verdict: path-2 as physically realized today has moved substantially from where it was on 2026-08-19
  (`path2_old`/`path2_new`), landing close to today's path-1. Not a mislabel — a real drift in the path-2
  setup between the two sessions. Overlay chart (`path1 vs path2, today, P011`) confirms visually: all 4
  curves (path1 Today1/Today2, path2 R1/R2) overlap almost everywhere; the one visible split is around
  index ~85-100 deg, where `path1_Today2` dips to -2.1 deg vs -1.55/-1.6 deg for the other three — the same
  angular zone flagged earlier for harmonic instability (H2 cv=11%).

## Cross-motor check: does path1~path2 convergence generalize? (P08, P010, P013, P03)

- Classification: `OPEN_LOOP_MEASUREMENT`, `QuickScreen3Run`/single-remount spot checks, `DIAGNOSTIC_ONLY`.
- Purpose: determine whether the path1~path2 convergence seen for P011 today is jig-level (all motors) or
  motor-specific, before drawing any conclusion.
- **P08**: `remountR2-path1.txt` vs `remountR1-path-2.txt`. A36 0.889-0.890 (correct motor). r0=0.980,
  best_shift=0, RMSE=0.160 deg. Historical (2026-08-19) `path1_run011` vs `path2_old_run09` needed
  shift=-80 deg, RMSE=0.516 deg — today's gap is much smaller than the historical path1/path2_old gap
  (though `path1_run011` vs `path2_new_run012` was already close then, RMSE=0.178 deg).
- **P010**: `remountR1-path1.txt` vs `remountR1-path2.txt`. A36 0.913-0.914 (correct motor). r0=0.938,
  best_shift=0, RMSE=0.394 deg — the loosest of the 5 motors. Historical `path1_run08` vs `path2_run07`
  (2026-08-19) was actually tighter (r0=0.958, RMSE=0.246 deg). `path1_today` also diverges more from its
  own history (`path1_run08`: r0=0.941, RMSE=0.469 deg) than `path2_today` does from its history
  (`path2_run07`: r0=0.968, RMSE=0.203 deg) — i.e. for this motor, path-1 is the one that moved, not path-2.
- **P013**: `remountR1-path1.txt` vs `remountR1-path2.txt`. A36 0.861 (correct motor). r0=0.961,
  best_shift=0, RMSE=0.304 deg — moderate. Historical path1 vs path2_new (`run011`) RMSE=0.342 deg
  (already close); vs path2_old (`run09`) needed shift=-80, RMSE=0.42 deg. `path1_today`/`path2_today`
  both need an 80 deg shift to match their own very first (`run01`) baseline, echoing the P011 finding that
  the earliest measurement of a motor tends to be the outlier, not later remounts.
- **P03**: `remountR1-path1.txt` vs `remountR1-path2.txt`. A36 0.899-0.901 (correct motor). r0=0.970,
  best_shift=-40 deg, r_best=0.975, RMSE=0.239 deg.

### Consolidated table — path1 vs path2, today, all 5 motors tested

| Motor | A36 p1/p2 | RawP2P p1/p2 (deg) | r0 | shift | RMSE (deg) |
|---|---|---|---:|---:|---:|
| P08  | 0.890/0.889 | 2.976/3.159 | 0.980 | 0   | 0.160 |
| P011 | 0.880/0.880 | 3.389/3.038 | 0.981 | 0   | 0.187 |
| P03  | 0.901/0.900 | 2.807/2.913 | 0.975 | -40 | 0.239 |
| P013 | 0.861/0.861 | 2.870/2.637 | 0.961 | 0   | 0.304 |
| P010 | 0.914/0.913 | 3.721/3.292 | 0.938 | 0   | 0.394 |

A36 confirms correct motor identity for every pair (no mislabeling in this batch).

### Verdict

- 4 of 5 motors (P08, P011, P03, P013) show path1/path2 noticeably closer today (r0 >= 0.96, RMSE
  0.16-0.30 deg, mostly no shift needed) than the 2026-08-19 path1-vs-path2_old baseline was for the motors
  where that historical pair is known (P08, P013: needed 80 deg shift, RMSE 0.42-0.52 deg). This is
  consistent across 4 independently-tested motors, so it reads as a jig-level change between 2026-08-19 and
  today, not an artifact of one motor's mount.
- **P010 breaks the pattern**: it is the loosest pair today (RMSE=0.394 deg) and, unusually, its own
  historical path1-path2 gap (2026-08-19) was tighter than today's. For P010 specifically, path-1 (not
  path-2) is the side that has moved relative to its own history. Flagged as an open item — recommend
  checking P010's path-1 setup today for anything done differently (gap, clamp order, position) versus the
  other 4 motors.
- No product pass/fail conclusion drawn; this remains a measurement-system/traceability finding per RULE 0.
  Feeds directly into Q1/Q2 of `docs/open-loop-nl-jig-calibration-gage-rr-plan-2026-08-20.md` (mounting DOE
  and SOP lock) — it is now empirical evidence, from 5 motors, that the current path1/path2 labels do not
  yet correspond to a fixed, day-to-day-repeatable mechanical datum.

## How many physical MA600 units were actually used across S4 (indirect inference, then field-confirmed)

MA600 exposes no per-unit serial number over SPI -- `Core/Inc/ma600.h`'s register map (ZERO/DIR/FILT/
STATUS/PRT/RMAPID/CORR0-31) has no unique-ID field; `RMAPID` is a register-map/part-revision ID shared
by every unit of that part, not a serial number. Sensor identity can currently only be inferred
indirectly.

Built `analysis/matlab/nl/build_s4_sensor_timeline.m`: parses every `S4-*.txt` log (58 files found, 53
with usable OFFICIAL open-loop data), extracts `JigID`/`MCU_UID` (authoritative identity) and `BuildID`
(firmware compile timestamp, the only chronological proxy available -- no capture wall-clock field
exists) alongside RawP2P/A36/H2 amplitude+phase per file.

Findings:
- JIG7 (44 files): exactly two `BuildID` values -- `12-Aug-2026 16:45:25` (run01-run06, the earliest S4
  batch) and `19-Aug-2026 12:21:06` (every `path1`/`path2` file, including all of today 2026-08-21's data
  -- confirms the firmware has not been rebuilt/reflashed since 2026-08-19, consistent with today's
  path1/path2 convergence being explained by the documented 2026-08-19 mid-session sensor swap, not a
  code change).
- JIG8 (9 files): a single `BuildID` throughout, never touched by the 08-19+ build -- outside the whole
  path1/path2 investigation.
- Documented-certain: at least 2 distinct MA600 units on JIG7 (the blind-tested old/new sensor swap from
  2026-08-19, see that day's summary).
- Could not detect further undocumented swaps from data alone: the shift-vs-amplitude-only signature
  used to distinguish "sensor changed" from "mount changed" only works when comparing two captures on
  the *same* mount -- every cross-day file pair is already confounded by an ordinary remount (which
  itself requires a shift regardless of sensor), so the signal is not separable across days.
- Reported minimum to the user: >=3 distinct physical MA600 units (2 on JIG7 over time + 1 on JIG8),
  explicitly caveated as a floor, not an exact count.

**User confirmed from direct hardware knowledge: exactly 3 sensors were actually used.** The indirect
inference (BuildID grouping + the one documented swap + JIG8 being untouched by that swap) landed on the
correct count. This validates the method as a reasonable stand-in until real serialization exists, but
it should not be over-trusted for cases with more undocumented swaps than this one -- the same
mount-change confound would silently hide them. Reinforces the open recommendation (not yet
implemented): add an operator-entered `SensorHeadSerial` field to the log schema so this becomes exactly
answerable rather than inferred.

## Open items for next session

- P010: repeat path-1 today's setup and re-check against `run08`/`remountR1-path1` to see if today's result
  was a one-off setup variation or a real, repeatable new state.
- Extend the 5-motor path1/path2-today table with more remounts per motor (currently 1-2 each, except P011
  which has 5 on path-1 and 2 on path-2) before treating the jig-level-change hypothesis as confirmed.
- Still open from 2026-08-20: trace the source run for the "remount up to 17.47%" figure cited in the Gage
  R&R plan baseline table; begin Q0 (freeze S4 artifact + approve `MSR_V1`) before further ad hoc path
  testing, per the plan's own critical-path note (Q1->Q3 is the gating step).
