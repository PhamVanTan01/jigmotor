# NL pointwise-curve analysis tool

## Purpose

`tools/analyze_nl_curve.py` extends the nonlinear-log pipeline from a single
robust-NL number to the complete sweep-relative error curve. It is designed
for an explicit A1-B-A2 experiment:

- A1: baseline jig before moving the motor;
- B: comparison jig;
- A2: return to the baseline jig.

The tool separates three questions that a single NL value cannot answer:

1. Is the run-level robust NL repeatable?
2. At which sweep-relative angles are its top and bottom tails produced?
3. Does jig B change the curve shape, or only its DC level/phase?

## Measurement contract

- `DATA.Error` at indices `0..AnalysisPoints-1` is the **pointwise error
  curve**.
- Robust NL is still computed independently for every run as
  `mean(top 5) - mean(bottom 5)`.
- Index `AnalysisPoints` is the closure sample. For a 360-point protocol this
  is index 360. It is validated separately and is not included in the curve,
  robust NL, or spectrum.
- Raw and centered curves are both exported. A centered run has its own
  360-point mean removed before pointwise mean/SD is calculated.
- Zero-shift A-vs-B comparison is the primary interchangeability result.
  Best circular alignment is also reported, but only as an explicit
  diagnostic. The tool never silently rotates one jig's curve.
- A PASS establishes repeatability/interchangeability for
  `WHOLE_SYSTEM_COMMAND_TRACKING`. It does not establish absolute encoder or
  motor nonlinearity without an independent angle reference.

## Command

```powershell
python tools/analyze_nl_curve.py `
  --a1 "S2-P03-JIG1-A1.txt" `
  --b "S2-P03-JIG4-B.txt" `
  --a2 "S2-P03-JIG1-A2.txt" `
  --out-dir "analysis-out/s2-nl-curve-p03"
```

Each leg accepts more than one log:

```powershell
python tools/analyze_nl_curve.py `
  --a1 A1-run1.txt A1-run2.txt `
  --b B-run1.txt B-run2.txt `
  --a2 A2-run1.txt A2-run2.txt `
  --out-dir analysis-out/my-study
```

Only sweeps accepted by `analyze_motor_logs.py` as complete, declared
`OFFICIAL`, and `EligibleForStatistics=1` are used. Legacy logs without
declared role fields remain labeled by the shared parser's legacy policy.
Mixed motors, mixed grids, or different A1/A2 jig IDs are rejected.

## Outputs

| File | Meaning |
|---|---|
| `run_metrics.csv` | Robust NL, tails, closure, RMS, P2P, and selected harmonics per OFFICIAL run |
| `leg_summary.csv` | Mean/SD for A1, B, and A2 |
| `pointwise_curves.csv` | Raw and centered mean/SD, tail-selection rate, zero-shift and aligned A-B-A differences |
| `extreme_points.csv` | Top/bottom five locations and their repeat frequency |
| `harmonic_spectrum.csv` | Mechanical harmonic orders 1 through Nyquist, including mean-curve amplitude and phase |
| `gate_results.csv` | Frozen pilot-gate result |
| `analysis_manifest.json` | Inputs, contract, thresholds, results, and warnings |
| `nl_curve_report.md` | Human-readable assessment |
| `raw_error_curve.png` | Raw mean ± pointwise SD |
| `centered_error_curve.png` | Shape-only comparison |
| `aba_differential_curve.png` | `B - mean(A1,A2)`, raw and centered |
| `harmonic_spectrum.png` | Spectrum of each leg's mean curve |

## Default pilot gates

The defaults match
`docs/CODEX_HANDOFF_NL_JIG_SYNC_2026-07-30.md`:

```text
Within-batch NL SD:             <= 0.03 deg
Remount/A1-to-A2 mean shift:    <= 0.05 deg
Cross-jig |Delta NL|:           <= max(0.05 deg, 2.77 * pooled SD)
|Delta top-tail mean|:          <= 0.10 deg
|Delta bottom-tail mean|:       <= 0.10 deg
Zero-shift curve correlation:   >= 0.98
Zero-shift centered curve RMSE: <= 0.10 deg
Closure:                        abs <= 0.20 deg for every run
```

`pooled SD` is calculated only from variance inside A1, B, and A2. The
A1-to-A2 mean drift is reported separately and is deliberately excluded from
the repeatability SD; otherwise a drifting baseline would make the cross-jig
gate less strict.

The A1-to-A2 return must also pass the same correlation and centered-RMSE
limits. If it does not, the cross-jig estimate is labeled confounded because
the baseline jig did not reproduce itself after remount.

All limits can be overridden from the CLI, but confirmation limits must be
frozen before inspecting a confirmation batch.

## Regression

```powershell
python tools/analyze_nl_curve.py --self-test
powershell -ExecutionPolicy Bypass -File scripts/test_nl_curve_analysis.ps1
```
