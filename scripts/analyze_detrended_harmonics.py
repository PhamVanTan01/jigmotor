#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Detrended-harmonic analysis of jig NL logs (host-side reference tool).

Why this exists: the firmware's per-sweep DFT (ComputeHarmonicFull) assumes the
360-point error curve is periodic, but the real curve fails to close by exactly
the per-revolution drift (= closure error, 0.3..0.5 deg on real hardware). A
sampled linear ramp of height d leaks into every DFT bin with amplitude about
|d|/(k*pi), which biases the low-order "mechanical signature" amplitudes
(A1/A2/A3) and their phases. This tool recomputes all 12 logged orders from the
per-point DATA rows both as-is and after removing the linear drift, so the true
jig mounting signature (H1/H2) can be separated from the leakage artifact and
compared across jigs.

It is also the cross-check reference for the firmware DETREND_RESULT record
(LeakModel=RAMP_ANALYTIC_V1): firmware values must match this tool's detrended
values to within 1e-3 deg on the same log.

Usage:
    python scripts/analyze_detrended_harmonics.py "log1.txt" ["log2.txt" ...]

Reads only; writes nothing. Use PYTHONIOENCODING=utf-8 when log filenames or
content contain Vietnamese text.
"""

import math
import sys

ORDERS = (1, 2, 3, 6, 9, 12, 18, 27, 36, 45, 72, 108)
ANALYSIS_POINTS = 360          # one mechanical revolution, matches firmware
CLOSURE_POINT = 360            # drift = error[360] - error[0]
FIRMWARE_MATCH_TOL = 0.002     # deg, pre-detrend amplitudes vs RESULT record


def parse_log(path):
    """Return {sweepId: {'err': {pointIndex: errDeg}, 'res': {k: v}, 'closure': f}}."""
    runs = {}

    def run(sid):
        return runs.setdefault(sid, {'err': {}, 'res': {}, 'closure': None})

    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if line.startswith('DATA,'):
                p = line.split(',')
                # DATA,schema,TestID,SweepID,Jig,Motor,Dir,idx,target,measured,absDeg,errDeg
                run(int(p[3]))['err'][int(p[7])] = float(p[11])
            elif line.startswith('RESULT,'):
                kv = dict(x.split('=', 1) for x in line.split(',')[1:] if '=' in x)
                run(int(kv['SweepID']))['res'] = kv
            elif line.startswith('SHADOW_RESULT,'):
                kv = dict(x.split('=', 1) for x in line.split(',')[1:] if '=' in x)
                run(int(kv['SweepID']))['closure'] = float(kv['ClosureErrorDeg'])
    return runs


def dft(errs, k):
    """Single-bin DFT identical to firmware ComputeHarmonicFull (mean-removed)."""
    n = len(errs)
    mean = sum(errs) / n
    sum_cos = 0.0
    sum_sin = 0.0
    for i, e in enumerate(errs):
        rad = math.radians(k * i)          # 1 deg grid: angleDeg == index
        sum_cos += (e - mean) * math.cos(rad)
        sum_sin += (e - mean) * math.sin(rad)
    a = 2.0 / n * sum_cos
    b = 2.0 / n * sum_sin
    return a, b


def amp_phase(a, b):
    return math.hypot(a, b), math.degrees(math.atan2(b, a))


def analytic_detrend(a, b, drift, k, n=ANALYSIS_POINTS):
    """Apply the closed-form ramp-leak correction (RAMP_ANALYTIC_V1).

    For r_i = drift*i/n the mean-removed single-bin DFT is
    a_leak = -drift/n, b_leak = -(drift/n)*cot(pi*k/n); subtracting the ramp
    from the curve therefore adds +drift/n and +(drift/n)*cot(pi*k/n).
    """
    a_d = a + drift / n
    b_d = b + (drift / n) / math.tan(math.pi * k / n)
    return a_d, b_d


def rms_ac(errs):
    n = len(errs)
    mean = sum(errs) / n
    return math.sqrt(sum((e - mean) ** 2 for e in errs) / n)


def rms_ac_detrended(errs, drift):
    """rmsd^2 = rms^2 - 2*cov(e, ramp) + var(ramp), all mean-removed."""
    n = len(errs)
    mean = sum(errs) / n
    s1 = sum((e - mean) * i for i, e in enumerate(errs))
    cross = drift / (n * n) * s1
    var_ramp = drift * drift * (n * n - 1) / (12.0 * n * n)
    val = rms_ac(errs) ** 2 - 2.0 * cross + var_ramp
    return math.sqrt(max(val, 0.0))


def analyze_file(path):
    runs = parse_log(path)
    print(f"\n=== {path} ===")
    header = (f"{'sw':>3} {'closure':>8} {'drift':>8} {'RMSAC':>7} {'RMSACd':>7} |"
              f" {'A1':>7} {'A1d':>7} {'ph1d':>7} | {'A2':>7} {'A2d':>7} |"
              f" {'A3':>7} {'A3d':>7} | {'A36':>7} {'A36d':>7}")
    print(header)

    agg = {}
    mismatches = 0
    for sid in sorted(runs):
        r = runs[sid]
        if CLOSURE_POINT not in r['err'] or len(r['err']) < CLOSURE_POINT + 1:
            print(f"{sid:>3} (incomplete sweep, skipped)")
            continue
        errs = [r['err'][i] for i in range(ANALYSIS_POINTS)]
        drift = r['err'][CLOSURE_POINT] - r['err'][0]

        row = {'closure': r['closure'] if r['closure'] is not None else float('nan'),
               'drift': drift,
               'rms': rms_ac(errs),
               'rmsd': rms_ac_detrended(errs, drift)}
        for k in ORDERS:
            a, b = dft(errs, k)
            amp, _ = amp_phase(a, b)
            a_d, b_d = analytic_detrend(a, b, drift, k)
            amp_d, ph_d = amp_phase(a_d, b_d)
            row[f'A{k}'] = amp
            row[f'A{k}d'] = amp_d
            row[f'P{k}d'] = ph_d
            # Cross-check pre-detrend amplitude against the firmware RESULT field.
            fw = r['res'].get(f'A{k}')
            if fw is not None and abs(float(fw) - amp) > FIRMWARE_MATCH_TOL:
                mismatches += 1
                print(f"    !! sweep {sid}: firmware A{k}={fw} vs recomputed {amp:.4f}")

        print(f"{sid:>3} {row['closure']:>8.4f} {row['drift']:>8.4f} "
              f"{row['rms']:>7.4f} {row['rmsd']:>7.4f} |"
              f" {row['A1']:>7.4f} {row['A1d']:>7.4f} {row['P1d']:>7.1f} |"
              f" {row['A2']:>7.4f} {row['A2d']:>7.4f} |"
              f" {row['A3']:>7.4f} {row['A3d']:>7.4f} |"
              f" {row['A36']:>7.4f} {row['A36d']:>7.4f}")
        for key, val in row.items():
            agg.setdefault(key, []).append(val)

    if agg:
        print("  --- mean +/- sd (all complete sweeps incl. precondition) ---")
        for key in (['closure', 'drift', 'rms', 'rmsd']
                    + [f'A{k}' for k in ORDERS] + [f'A{k}d' for k in ORDERS]
                    + ['P1d', 'P2d']):
            vals = [v for v in agg.get(key, []) if not math.isnan(v)]
            if not vals:
                continue
            mu = sum(vals) / len(vals)
            sd = (math.sqrt(sum((x - mu) ** 2 for x in vals) / (len(vals) - 1))
                  if len(vals) > 1 else 0.0)
            print(f"    {key:>8}: {mu:>9.4f} +/- {sd:.4f}")
    if mismatches:
        print(f"  !! {mismatches} firmware-vs-recomputed mismatches above "
              f"{FIRMWARE_MATCH_TOL} deg -- investigate before trusting this log.")
    return mismatches


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    total_mismatch = 0
    for path in argv[1:]:
        total_mismatch += analyze_file(path)
    return 1 if total_mismatch else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
