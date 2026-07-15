#!/usr/bin/env python3
"""Plot the run-to-run trend of a nonlinear-sweep metric, with a linear
regression trend line, from one or more jigmotor test log .txt files.

Reads the same META/RESULT/SHADOW_RESULT key=value record lines the
firmware emits (schema v4 and v5 both supported -- v4 logs simply lack
RunRole/EligibleForStatistics/ControllerState fields, which this tool
treats as "no precondition concept, include every run").

Each RESULT record is paired with the META record immediately preceding
it (same TestID/SweepID) for run-ordering context, and with the
SHADOW_RESULT record immediately following it (if present) for
Shadow_ClosureErrorDeg. Precondition runs (RunRole=PRECONDITION /
EligibleForStatistics=0) are plotted with a distinct marker and excluded
from the linear fit by default -- see --include-precondition.

Usage:
    python tools/plot_metric_trend.py LOGFILE [LOGFILE ...] --metric RMS_AC
    python tools/plot_metric_trend.py LOGFILE --metric Motor_System_INL_Deg --out trend.png
    python tools/plot_metric_trend.py LOGFILE --list-metrics
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional

import matplotlib
matplotlib.use("Agg")  # headless-safe default; savefig always works regardless of backend
import matplotlib.pyplot as plt


def parse_kv(line: str) -> Dict[str, str]:
    """Parse a 'KEY=VALUE,KEY=VALUE,...' record line into a dict of strings."""
    out: Dict[str, str] = {}
    for part in line.rstrip("\r\n").split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = v.strip()
    return out


@dataclass
class RunRecord:
    file: str
    test_id: Optional[int]
    run_order: Optional[int]
    run_role: str  # "OFFICIAL" if unknown (v4 logs have no concept of precondition)
    eligible: bool  # True if unknown (v4 logs: every run counts)
    fields: Dict[str, float] = field(default_factory=dict)

    @property
    def label(self) -> str:
        if self.run_order is not None:
            return f"run{self.run_order}"
        if self.test_id is not None:
            return f"TestID{self.test_id}"
        return "?"


def to_float(v: str) -> Optional[float]:
    try:
        return float(v)
    except ValueError:
        return None


def load_runs(path: Path) -> List[RunRecord]:
    """Walk a log file in order, pairing each RESULT with the most recent META
    and the next SHADOW_RESULT (if it arrives before the next META)."""
    runs: List[RunRecord] = []
    pending_meta: Optional[Dict[str, str]] = None
    last_run: Optional[RunRecord] = None

    with path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("META,"):
                pending_meta = parse_kv(line)
                last_run = None  # a new META closes off shadow-attachment to the previous run
            elif line.startswith("RESULT,"):
                r = parse_kv(line)
                m = pending_meta or {}
                run_order = int(m["RunOrder"]) if "RunOrder" in m else None
                test_id = int(m["TestID"]) if "TestID" in m else (
                    int(r["TestID"]) if "TestID" in r else None)
                run_role = m.get("RunRole", "OFFICIAL")
                eligible = m.get("EligibleForStatistics", "1") == "1"
                rec = RunRecord(file=path.name, test_id=test_id, run_order=run_order,
                                 run_role=run_role, eligible=eligible)
                for k, v in r.items():
                    fv = to_float(v)
                    if fv is not None:
                        rec.fields[k] = fv
                for k in ("HomeDurationMs", "HomeUpdateCount", "MotorActiveDurationMs",
                          "CooldownActualMs", "TimeSincePreviousRunMs"):
                    if k in m:
                        fv = to_float(m[k])
                        if fv is not None:
                            rec.fields[k] = fv
                runs.append(rec)
                last_run = rec
            elif line.startswith("SHADOW_RESULT,") and last_run is not None:
                s = parse_kv(line)
                if "ClosureErrorDeg" in s:
                    fv = to_float(s["ClosureErrorDeg"])
                    if fv is not None:
                        last_run.fields["Shadow_ClosureErrorDeg"] = fv
    return runs


def linear_fit(x: List[float], y: List[float]):
    """Least-squares slope/intercept/R^2 -- no numpy.polyfit dependency needed
    beyond what's already used for plotting, kept explicit for clarity."""
    n = len(x)
    mean_x = sum(x) / n
    mean_y = sum(y) / n
    sxy = sum((xi - mean_x) * (yi - mean_y) for xi, yi in zip(x, y))
    sxx = sum((xi - mean_x) ** 2 for xi in x)
    if sxx == 0:
        return 0.0, mean_y, 0.0
    slope = sxy / sxx
    intercept = mean_y - slope * mean_x
    ss_tot = sum((yi - mean_y) ** 2 for yi in y)
    ss_res = sum((yi - (slope * xi + intercept)) ** 2 for xi, yi in zip(x, y))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 1.0
    return slope, intercept, r2


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logfiles", nargs="+", type=Path, help="Log file(s), in run order")
    parser.add_argument("--metric", help="RESULT/META field name to plot, e.g. RMS_AC, A36, "
                         "Motor_System_INL_Deg, TrackingError_RMS_Deg, Shadow_ClosureErrorDeg")
    parser.add_argument("--list-metrics", action="store_true",
                         help="List numeric fields found in the file(s) and exit")
    parser.add_argument("--out", type=Path, default=None,
                         help="PNG output path (default: <metric>_trend.png next to the first logfile)")
    parser.add_argument("--include-precondition", action="store_true",
                         help="Include PRECONDITION/EligibleForStatistics=0 runs in the linear fit "
                              "(default: shown on the plot but excluded from the fit)")
    parser.add_argument("--show", action="store_true", help="Open an interactive window too")
    args = parser.parse_args(argv)

    all_runs: List[RunRecord] = []
    for p in args.logfiles:
        if not p.exists():
            print(f"error: file not found: {p}", file=sys.stderr)
            return 1
        all_runs.extend(load_runs(p))

    if not all_runs:
        print("error: no RESULT records found in the given file(s)", file=sys.stderr)
        return 1

    if args.list_metrics:
        keys = sorted(set().union(*(r.fields.keys() for r in all_runs)))
        print(f"{len(all_runs)} runs parsed from {len(args.logfiles)} file(s).")
        print("Available numeric metrics:")
        for k in keys:
            print(f"  {k}")
        return 0

    if not args.metric:
        parser.error("--metric is required (use --list-metrics to see available names)")

    metric = args.metric
    missing = [r for r in all_runs if metric not in r.fields]
    present = [r for r in all_runs if metric in r.fields]
    if not present:
        print(f"error: metric '{metric}' not found in any run. Try --list-metrics.", file=sys.stderr)
        return 1
    if missing:
        print(f"warning: {len(missing)}/{len(all_runs)} runs have no '{metric}' field, skipping those.",
              file=sys.stderr)

    # X axis: sequential run index across the given file(s), in the order encountered.
    xs_all = list(range(len(present)))
    ys_all = [r.fields[metric] for r in present]
    included = [i for i, r in enumerate(present) if args.include_precondition or r.eligible]
    excluded = [i for i in xs_all if i not in included]

    fit_x = [xs_all[i] for i in included]
    fit_y = [ys_all[i] for i in included]
    slope, intercept, r2 = linear_fit(fit_x, fit_y)

    fig, ax = plt.subplots(figsize=(10, 5.5))

    if included:
        ax.plot([xs_all[i] for i in included], [ys_all[i] for i in included],
                "o-", color="#1f77b4", label=f"{metric} (included in fit)")
    if excluded:
        ax.plot([xs_all[i] for i in excluded], [ys_all[i] for i in excluded],
                "x", color="#d62728", markersize=10, markeredgewidth=2,
                label="excluded (precondition)")

    if len(fit_x) >= 2:
        line_x = [min(xs_all), max(xs_all)]
        line_y = [slope * xi + intercept for xi in line_x]
        ax.plot(line_x, line_y, "--", color="#555555",
                label=f"linear fit: y={slope:.5g}x+{intercept:.5g}  (R2={r2:.3f})")

    ax.set_xlabel("Run index (sequential order across input file(s))")
    ax.set_ylabel(metric)
    ax.set_title(f"{metric} trend across {len(present)} run(s)"
                 + (f" ({len(args.logfiles)} file(s))" if len(args.logfiles) > 1 else ""))
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best", fontsize=9)

    for i, r in enumerate(present):
        ax.annotate(r.label, (xs_all[i], ys_all[i]), textcoords="offset points",
                    xytext=(0, 8), fontsize=7, ha="center", alpha=0.7)

    fig.tight_layout()

    out_path = args.out or (args.logfiles[0].parent / f"{metric}_trend.png")
    fig.savefig(out_path, dpi=150)
    print(f"Saved: {out_path}")
    print(f"n={len(present)} (fit n={len(fit_x)}, excluded={len(excluded)})  "
          f"mean={sum(fit_y)/len(fit_y):.5g}  slope={slope:.6g}/run  R2={r2:.4f}")

    if args.show:
        try:
            plt.show()
        except Exception as exc:  # no display available, e.g. headless CI/SSH session
            print(f"warning: --show failed ({exc}); the PNG was still saved above.", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
