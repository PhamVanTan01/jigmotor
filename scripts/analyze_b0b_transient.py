#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""B0-B per-tick tracking-lag analysis (Phase A, host-side reference tool).

Why this exists: B0-B's backoff/forward legs (nonlinear_test.c,
SCURVE_LOCK_PLUS_CW_LOCAL_APPROACH_V2) command a 182-raw quintic move over
exactly 40 ticks at 1 ms/tick, full power. APPROACH_RESULT already reports the
*final* observed displacement (BackoffObservedDeltaRaw/ApproachObservedDeltaRaw),
showing severe under-travel (historically ~30-77% of 182 raw). What it does not
show is the *shape* of that under-travel tick-by-tick -- whether tracking is
catching up by tick 40 (just needs a few more ticks / a mildly slower cadence)
or still far off (needs a much slower cadence, or a different mechanism
entirely). This tool reconstructs that shape from APPROACH_STEPS, which already
logs one raw position per tick for both legs of every run.

Method: re-derive the commanded quintic curve analytically (NlSmoothstepCommandRaw:
blend(u) = u^3*(10-15u+6u^2), u = commandIndex/40, commandIndex = 1..40, last
index clamped exactly to target) and compare to the actual logged position at
each tick, both referenced to the leg's own first logged sample (tick 1) so no
external anchor is needed. This is a *relative* shape comparison, not the
official displacement metric -- APPROACH_RESULT remains the source of truth for
final displacement.

Also extracts CONTROL_A4_DATA per-tick dragLagRaw/commandPhaseProgressRaw from
A3/A4/A4B Control-image logs (35% power, full electrical cycle) purely for
shape cross-reference -- power and geometry differ from B0-B (100% power, 6 deg
electrical), so absolute values are not comparable, only the qualitative
catch-up curve shape.

Usage:
    python scripts/analyze_b0b_transient.py --b0b "log1.txt" ["log2.txt" ...]
    python scripts/analyze_b0b_transient.py --a4 "log1.txt" ["log2.txt" ...]

Reads only; writes nothing. Use PYTHONIOENCODING=utf-8 for Vietnamese filenames.
"""

import re
import sys

B0B_TARGET_RAW = 182
B0B_TICKS = 40


def blend(u):
    return u * u * u * (10.0 - 15.0 * u + 6.0 * u * u)


def expected_cum(command_index, target_signed):
    """Commanded cumulative displacement from the pre-leg start, at 1-indexed
    commandIndex 1..40 (40 clamps exactly to target_signed)."""
    if command_index >= B0B_TICKS:
        return float(target_signed)
    u = command_index / float(B0B_TICKS)
    return target_signed * blend(u)


def parse_b0b_log(path):
    """Return list of {'sweepId', 'leg', 'raw': [40 ints]} plus matching
    APPROACH_RESULT rows keyed by sweepId for cross-check."""
    text = open(path, encoding='utf-8', errors='replace').read()
    legs = []
    results = {}
    corrupt = 0
    for line in text.splitlines():
        if line.startswith('APPROACH_STEPS,'):
            kv = dict(x.split('=', 1) for x in line.split(',')[1:] if '=' in x)
            if 'UnwrappedRaw' not in kv or 'SweepID' not in kv or 'Leg' not in kv:
                corrupt += 1
                print(f"  !! {path}: skipping a corrupted APPROACH_STEPS line "
                      f"(UART glitch, missing field) -- {line[:80]!r}...")
                continue
            try:
                raw = [int(v) for v in kv['UnwrappedRaw'].split('|')]
            except ValueError:
                corrupt += 1
                print(f"  !! {path}: skipping a corrupted APPROACH_STEPS line "
                      f"(non-integer UnwrappedRaw value)")
                continue
            legs.append({'sweepId': int(kv['SweepID']), 'leg': kv['Leg'], 'raw': raw})
        elif line.startswith('APPROACH_RESULT,'):
            kv = dict(x.split('=', 1) for x in line.split(',')[1:] if '=' in x)
            results[int(kv['SweepID'])] = kv
    return legs, results


def analyze_b0b(paths):
    all_legs = {'BACKOFF': [], 'FORWARD': []}
    mismatches = 0
    for path in paths:
        legs, results = parse_b0b_log(path)
        for leg in legs:
            if len(leg['raw']) != B0B_TICKS:
                print(f"  !! {path} sweep {leg['sweepId']} {leg['leg']}: "
                      f"expected {B0B_TICKS} ticks, got {len(leg['raw'])} -- skipped")
                continue
            r = results.get(leg['sweepId'])
            if r is None or r.get('Status') != 'OK' or r.get('ApproachStructuralValid') != '1':
                print(f"  !! {path} sweep {leg['sweepId']} {leg['leg']}: no matching "
                      f"valid APPROACH_RESULT (orphan/incomplete capture) -- skipped")
                continue
            target_signed = -B0B_TARGET_RAW if leg['leg'] == 'BACKOFF' else B0B_TARGET_RAW
            raw0 = leg['raw'][0]
            actual_cum = [leg['raw'][i] - raw0 for i in range(B0B_TICKS)]
            expected = [expected_cum(i + 1, target_signed) for i in range(B0B_TICKS)]
            lag = [expected[i] - actual_cum[i] for i in range(B0B_TICKS)]
            pct_tracked = [
                (actual_cum[i] / expected[i] * 100.0) if expected[i] != 0 else 0.0
                for i in range(B0B_TICKS)
            ]
            all_legs[leg['leg']].append({
                'path': path, 'sweepId': leg['sweepId'],
                'actual_cum': actual_cum, 'expected': expected,
                'lag': lag, 'pct_tracked': pct_tracked,
            })
            r = results.get(leg['sweepId'])
            if r:
                field = ('BackoffObservedDeltaRaw' if leg['leg'] == 'BACKOFF'
                         else 'ApproachObservedDeltaRaw')
                reported = r.get(field)
                if reported is not None:
                    recomputed_final = actual_cum[-1] + raw0 - leg['raw'][0]
                    # sanity-only cross-check against the array's own net delta
                    net = leg['raw'][-1] - leg['raw'][0]
                    if abs(int(reported) - net) > 60:
                        mismatches += 1
                        print(f"  !! {path} sweep {leg['sweepId']} {leg['leg']}: "
                              f"APPROACH_RESULT {field}={reported} vs "
                              f"STEPS array net delta={net} (uses a different "
                              f"external anchor -- expected to differ somewhat, "
                              f"flagging only if >60 raw)")

    checkpoints = [1, 5, 10, 15, 20, 25, 30, 35, 40]
    for leg_name in ('BACKOFF', 'FORWARD'):
        runs = all_legs[leg_name]
        if not runs:
            continue
        n = len(runs)
        print(f"\n=== B0-B {leg_name} leg -- {n} run(s), target {B0B_TICKS} ticks / "
              f"{B0B_TARGET_RAW} raw ===")
        print(f"{'tick':>4} {'%tracked mean':>14} {'%tracked min':>13} "
              f"{'%tracked max':>13} {'lag mean(raw)':>14} {'lag max(raw)':>13}")
        for tick in checkpoints:
            idx = tick - 1
            pcts = [r['pct_tracked'][idx] for r in runs]
            lags = [abs(r['lag'][idx]) for r in runs]
            print(f"{tick:>4} {sum(pcts)/n:>14.1f} {min(pcts):>13.1f} "
                  f"{max(pcts):>13.1f} {sum(lags)/n:>14.1f} {max(lags):>13.1f}")
        final_pcts = [r['pct_tracked'][-1] for r in runs]
        print(f"  final tick-40 %tracked: mean={sum(final_pcts)/n:.1f}  "
              f"min={min(final_pcts):.1f}  max={max(final_pcts):.1f}")
    if mismatches:
        print(f"\n  ({mismatches} sanity-check flags above -- see note on external "
              f"anchor; does not affect the shape analysis itself)")


def parse_a4_log(path):
    """Return list of per-tick dicts from CONTROL_A4_DATA (decimated 3:1, plus
    final tick), grouped by nearest preceding CONTROL_A4_SUMMARY (one run)."""
    text = open(path, encoding='utf-8', errors='replace').read()
    runs = []
    current = None
    for line in text.splitlines():
        if line.startswith('CONTROL_A4_SUMMARY,'):
            current = {'ticks': []}
            runs.append(current)
        elif line.startswith('CONTROL_A4_DATA,') and current is not None:
            kv = dict(x.split('=', 1) for x in line.split(',')[1:] if '=' in x)
            if kv.get('Phase') == 'PHASE_SWEEP':
                current['ticks'].append({
                    'seq': int(kv['Seq']),
                    'dragLag': int(kv['DragLagRaw']),
                    'phaseProgress': int(kv['PhaseProgressRaw']),
                })
    return [r for r in runs if r['ticks']]


def analyze_a4(paths):
    all_runs = []
    for path in paths:
        all_runs.extend(parse_a4_log(path))
    if not all_runs:
        print("No CONTROL_A4_DATA PHASE_SWEEP ticks found in the given files.")
        return
    print(f"\n=== A3/A4 sweep-phase drag lag shape (35% power, full electrical "
          f"cycle, {len(all_runs)} run(s), decimated 3:1 -- shape reference only, "
          f"NOT comparable in absolute raw to B0-B's 100% power / 6 deg move) ===")
    # Bucket by fraction of sweep progress (0-100%) since tick counts vary
    # slightly per run (sweepTicksUsed).
    buckets = {p: [] for p in (5, 10, 20, 30, 50, 70, 100)}
    for run in all_runs:
        max_seq = max(t['seq'] for t in run['ticks'])
        if max_seq == 0:
            continue
        for t in run['ticks']:
            frac = t['seq'] / max_seq * 100.0
            for p in buckets:
                lo = 0 if p == 5 else p - 10
                if lo < frac <= p:
                    buckets[p].append(t['dragLag'])
                    break
    print(f"{'sweep %':>8} {'n':>5} {'dragLag mean':>13} {'dragLag max':>12}")
    for p in sorted(buckets):
        vals = buckets[p]
        if not vals:
            continue
        absvals = [abs(v) for v in vals]
        print(f"{p:>8} {len(vals):>5} {sum(vals)/len(vals):>13.1f} {max(absvals):>12}")


def main(argv):
    if len(argv) < 3 or argv[1] not in ('--b0b', '--a4'):
        print(__doc__)
        return 2
    mode = argv[1]
    paths = argv[2:]
    if mode == '--b0b':
        analyze_b0b(paths)
    else:
        analyze_a4(paths)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
