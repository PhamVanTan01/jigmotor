#!/usr/bin/env python3
"""Plot the run-to-run trend of a nonlinear-sweep metric, with a linear
regression trend line, from one or more jigmotor test log .txt files.

Reads the same META/RESULT/SHADOW_RESULT/APPROACH_RESULT key=value record lines the
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
    python tools/plot_metric_trend.py  # open the desktop application
    python tools/plot_metric_trend.py LOGFILE [LOGFILE ...] --metric RMS_AC
    python tools/plot_metric_trend.py LOGFILE --metric Motor_System_INL_Deg --out trend.png
    python tools/plot_metric_trend.py LOGFILE --list-metrics
    python tools/plot_metric_trend.py LOGFILE [LOGFILE ...] --export-csv runs.csv
    python tools/plot_metric_trend.py LOG_DIRECTORY --export-csv runs.csv
"""

from __future__ import annotations

import argparse
import csv
import glob
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
    source_path: str
    file_index: int
    run_index_in_file: int
    test_id: Optional[int]
    sweep_id: Optional[int]
    run_order: Optional[int]
    run_role: str  # "OFFICIAL" if unknown (v4 logs have no concept of precondition)
    eligible: bool  # True if unknown (v4 logs: every run counts)
    fields: Dict[str, float] = field(default_factory=dict)
    records: Dict[str, Dict[str, str]] = field(default_factory=dict)

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


def load_runs(path: Path, file_index: int = 0) -> List[RunRecord]:
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
                sweep_id = int(m["SweepID"]) if "SweepID" in m else (
                    int(r["SweepID"]) if "SweepID" in r else None)
                run_role = m.get("RunRole", "OFFICIAL")
                eligible = m.get("EligibleForStatistics", "1") == "1"
                rec = RunRecord(file=path.name, source_path=str(path.resolve()),
                                 file_index=file_index, run_index_in_file=len(runs),
                                 test_id=test_id, sweep_id=sweep_id, run_order=run_order,
                                 run_role=run_role, eligible=eligible,
                                 records={"META": dict(m), "RESULT": dict(r)})
                for k, v in r.items():
                    fv = to_float(v)
                    if fv is not None:
                        rec.fields[k] = fv
                for k in ("HomeDurationMs", "HomeUpdateCount", "MotorActiveDurationMs",
                          "CooldownActualMs", "TimeSincePreviousRunMs",
                          # B0-B summary gate: "1"/"0" plot as 1.0/0.0; protocol A's
                          # "NA" is skipped by to_float() below, same as any other
                          # non-numeric META value. ApproachProtocol is a string and
                          # deliberately NOT whitelisted into this float field map.
                          "ApproachStructuralValid"):
                    if k in m:
                        fv = to_float(m[k])
                        if fv is not None:
                            rec.fields[k] = fv
                runs.append(rec)
                last_run = rec
            elif line.startswith("SHADOW_RESULT,") and last_run is not None:
                s = parse_kv(line)
                last_run.records["SHADOW_RESULT"] = dict(s)
                if "ClosureErrorDeg" in s:
                    fv = to_float(s["ClosureErrorDeg"])
                    if fv is not None:
                        last_run.fields["Shadow_ClosureErrorDeg"] = fv
                for k, v in s.items():
                    fv = to_float(v)
                    if fv is not None:
                        last_run.fields.setdefault(f"Shadow_{k}", fv)
            elif line.startswith("APPROACH_RESULT,") and last_run is not None:
                a = parse_kv(line)
                last_run.records["APPROACH_RESULT"] = dict(a)
                for k, v in a.items():
                    fv = to_float(v)
                    if fv is not None:
                        last_run.fields.setdefault(k, fv)
    return runs


def expand_logfiles(inputs: List[Path]) -> List[Path]:
    """Expand directories and wildcard arguments while preserving input order.

    PowerShell does not consistently expand wildcards passed to native Python
    programs, so the application handles them itself. A directory means all
    .txt files immediately inside that directory.
    """
    expanded: List[Path] = []
    seen = set()
    for item in inputs:
        candidates: List[Path]
        item_text = str(item)
        if any(ch in item_text for ch in "*?["):
            candidates = [Path(p) for p in sorted(glob.glob(item_text), key=str.casefold)]
        elif item.is_dir():
            candidates = sorted(item.glob("*.txt"), key=lambda p: p.name.casefold())
        else:
            candidates = [item]

        for candidate in candidates:
            key = str(candidate.resolve()).casefold()
            if key not in seen:
                seen.add(key)
                expanded.append(candidate)
    return expanded


def export_runs_csv(runs: List[RunRecord], path: Path,
                    include_precondition: bool = False) -> None:
    """Export one wide CSV row per run without losing string-valued fields.

    Field names are namespaced by source record so duplicate names such as
    RMS_AC, Valid, or Protocol remain unambiguous. UTF-8 with BOM keeps JigID,
    MotorID, and Vietnamese file names readable when opened directly in Excel.
    """
    sections = ("META", "RESULT", "SHADOW_RESULT", "APPROACH_RESULT")
    section_fields: Dict[str, List[str]] = {section: [] for section in sections}
    section_seen = {section: set() for section in sections}
    for run in runs:
        for section in sections:
            for key in run.records.get(section, {}):
                if key not in section_seen[section]:
                    section_seen[section].add(key)
                    section_fields[section].append(key)

    identity_fields = [
        "FileIndex", "RunIndexInFile", "SequentialRunIndex", "SourceFile", "SourcePath",
        "TestID", "SweepID", "RunOrder", "RunRole", "EligibleForStatistics",
        "IncludedInStatistics",
    ]
    record_fields = [
        f"{section}.{key}"
        for section in sections
        for key in section_fields[section]
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=identity_fields + record_fields,
                                extrasaction="ignore")
        writer.writeheader()
        for sequential_index, run in enumerate(runs):
            row = {
                "FileIndex": run.file_index,
                "RunIndexInFile": run.run_index_in_file,
                "SequentialRunIndex": sequential_index,
                "SourceFile": run.file,
                "SourcePath": run.source_path,
                "TestID": run.test_id,
                "SweepID": run.sweep_id,
                "RunOrder": run.run_order,
                "RunRole": run.run_role,
                "EligibleForStatistics": 1 if run.eligible else 0,
                "IncludedInStatistics": 1 if include_precondition or run.eligible else 0,
            }
            for section in sections:
                for key, value in run.records.get(section, {}).items():
                    row[f"{section}.{key}"] = value
            writer.writerow(row)


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


def launch_gui() -> int:
    """Launch the desktop file-picker workflow when no CLI arguments are given."""
    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, ttk
    except ImportError as exc:
        print(f"error: Tkinter is not available ({exc})", file=sys.stderr)
        print("Run with --help for command-line usage.", file=sys.stderr)
        return 2

    root = tk.Tk()
    root.title("Jigmotor TXT Log Export & Metric Trend")
    root.geometry("900x560")
    root.minsize(720, 460)

    selected_paths: List[Path] = []
    metric_var = tk.StringVar()
    include_precondition_var = tk.BooleanVar(value=False)
    status_var = tk.StringVar(value="Chọn một hoặc nhiều file log .txt theo đúng thứ tự test.")

    main_frame = ttk.Frame(root, padding=12)
    main_frame.pack(fill="both", expand=True)
    main_frame.columnconfigure(0, weight=1)
    main_frame.rowconfigure(1, weight=1)

    ttk.Label(main_frame, text="File log đầu vào (thứ tự này được giữ trong CSV và biểu đồ):") \
        .grid(row=0, column=0, columnspan=2, sticky="w", pady=(0, 6))

    list_frame = ttk.Frame(main_frame)
    list_frame.grid(row=1, column=0, sticky="nsew")
    list_frame.columnconfigure(0, weight=1)
    list_frame.rowconfigure(0, weight=1)
    file_list = tk.Listbox(list_frame, selectmode=tk.EXTENDED)
    file_list.grid(row=0, column=0, sticky="nsew")
    scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=file_list.yview)
    scrollbar.grid(row=0, column=1, sticky="ns")
    file_list.configure(yscrollcommand=scrollbar.set)

    button_frame = ttk.Frame(main_frame, padding=(10, 0, 0, 0))
    button_frame.grid(row=1, column=1, sticky="ns")

    def redraw_file_list() -> None:
        file_list.delete(0, tk.END)
        for index, path in enumerate(selected_paths, start=1):
            file_list.insert(tk.END, f"{index:02d}. {path}")

    def parse_selected(show_error: bool = True) -> Optional[List[RunRecord]]:
        if not selected_paths:
            if show_error:
                messagebox.showwarning("Chưa có file", "Hãy chọn ít nhất một file log .txt.")
            return None
        runs: List[RunRecord] = []
        try:
            for file_index, path in enumerate(selected_paths):
                runs.extend(load_runs(path, file_index=file_index))
        except (OSError, ValueError) as exc:
            if show_error:
                messagebox.showerror("Không đọc được log", str(exc))
            return None
        if not runs:
            if show_error:
                messagebox.showerror(
                    "Không có dữ liệu",
                    "Không tìm thấy record RESULT trong các file đã chọn.",
                )
            return None
        return runs

    def refresh_metrics() -> None:
        runs = parse_selected(show_error=False)
        if not runs:
            metric_box["values"] = ()
            metric_var.set("")
            status_var.set(f"Đã chọn {len(selected_paths)} file; chưa tìm thấy RESULT hợp lệ.")
            return
        metrics = sorted(set().union(*(run.fields.keys() for run in runs)))
        metric_box["values"] = metrics
        preferred = ("Shadow_ClosureErrorDeg", "RMS_AC", "Motor_System_INL_Deg")
        if metric_var.get() not in metrics:
            metric_var.set(next((name for name in preferred if name in metrics), metrics[0]))
        status_var.set(
            f"Đã đọc {len(runs)} run từ {len(selected_paths)} file; có {len(metrics)} metric số."
        )

    def add_paths(paths) -> None:
        known = {str(path.resolve()).casefold() for path in selected_paths}
        for raw_path in paths:
            path = Path(raw_path)
            key = str(path.resolve()).casefold()
            if key not in known:
                known.add(key)
                selected_paths.append(path)
        redraw_file_list()
        refresh_metrics()

    def add_files() -> None:
        paths = filedialog.askopenfilenames(
            parent=root,
            title="Chọn file log jigmotor",
            filetypes=(("Text logs", "*.txt"), ("All files", "*.*")),
        )
        if paths:
            add_paths(paths)

    def add_folder() -> None:
        folder = filedialog.askdirectory(parent=root, title="Chọn thư mục chứa log .txt")
        if folder:
            add_paths(sorted(Path(folder).glob("*.txt"), key=lambda p: p.name.casefold()))

    def remove_selected() -> None:
        for index in reversed(file_list.curselection()):
            del selected_paths[index]
        redraw_file_list()
        refresh_metrics()

    def clear_files() -> None:
        selected_paths.clear()
        redraw_file_list()
        refresh_metrics()

    def export_csv_from_gui() -> None:
        runs = parse_selected()
        if not runs:
            return
        default_dir = str(selected_paths[0].parent)
        output = filedialog.asksaveasfilename(
            parent=root,
            title="Xuất dữ liệu từng run",
            initialdir=default_dir,
            initialfile="jigmotor_runs.csv",
            defaultextension=".csv",
            filetypes=(("CSV data", "*.csv"),),
        )
        if not output:
            return
        try:
            export_runs_csv(runs, Path(output), include_precondition_var.get())
        except OSError as exc:
            messagebox.showerror("Không xuất được CSV", str(exc))
            return
        status_var.set(f"Đã xuất {len(runs)} run: {output}")
        messagebox.showinfo("Xuất CSV thành công", f"Đã xuất {len(runs)} run vào:\n{output}")

    def plot_from_gui() -> None:
        runs = parse_selected()
        metric = metric_var.get()
        if not runs or not metric:
            messagebox.showwarning("Chưa chọn metric", "Hãy chọn metric cần tạo biểu đồ.")
            return
        default_dir = str(selected_paths[0].parent)
        output = filedialog.asksaveasfilename(
            parent=root,
            title="Lưu biểu đồ metric",
            initialdir=default_dir,
            initialfile=f"{metric}_trend.png",
            defaultextension=".png",
            filetypes=(("PNG image", "*.png"),),
        )
        if not output:
            return
        cli_args = [str(path) for path in selected_paths]
        cli_args.extend(("--metric", metric, "--out", output))
        if include_precondition_var.get():
            cli_args.append("--include-precondition")
        try:
            result = main(cli_args)
        except Exception as exc:  # keep the desktop app alive and show a useful error
            messagebox.showerror("Không tạo được biểu đồ", str(exc))
            return
        if result != 0:
            messagebox.showerror("Không tạo được biểu đồ", f"Lệnh kết thúc với mã lỗi {result}.")
            return
        status_var.set(f"Đã tạo biểu đồ: {output}")
        messagebox.showinfo("Tạo biểu đồ thành công", f"Đã lưu biểu đồ vào:\n{output}")

    ttk.Button(button_frame, text="Thêm file...", command=add_files, width=18) \
        .pack(fill="x", pady=(0, 6))
    ttk.Button(button_frame, text="Thêm thư mục...", command=add_folder, width=18) \
        .pack(fill="x", pady=6)
    ttk.Button(button_frame, text="Xóa file đã chọn", command=remove_selected, width=18) \
        .pack(fill="x", pady=6)
    ttk.Button(button_frame, text="Xóa tất cả", command=clear_files, width=18) \
        .pack(fill="x", pady=6)

    options_frame = ttk.LabelFrame(main_frame, text="Xuất dữ liệu / biểu đồ", padding=10)
    options_frame.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(12, 0))
    options_frame.columnconfigure(1, weight=1)
    ttk.Label(options_frame, text="Metric:").grid(row=0, column=0, sticky="w", padx=(0, 8))
    metric_box = ttk.Combobox(options_frame, textvariable=metric_var, state="readonly")
    metric_box.grid(row=0, column=1, columnspan=2, sticky="ew")
    ttk.Checkbutton(
        options_frame,
        text="Đưa PRECONDITION vào thống kê/đường hồi quy",
        variable=include_precondition_var,
    ).grid(row=1, column=0, columnspan=3, sticky="w", pady=(8, 8))
    ttk.Button(options_frame, text="Xuất CSV...", command=export_csv_from_gui) \
        .grid(row=2, column=1, sticky="e", padx=(0, 6))
    ttk.Button(options_frame, text="Tạo biểu đồ PNG...", command=plot_from_gui) \
        .grid(row=2, column=2, sticky="e")

    ttk.Label(main_frame, textvariable=status_var, relief="sunken", anchor="w", padding=6) \
        .grid(row=3, column=0, columnspan=2, sticky="ew", pady=(10, 0))

    root.mainloop()
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
        if not argv:
            return launch_gui()

    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logfiles", nargs="+", type=Path,
                         help="Log file(s), wildcard(s), or directories containing .txt logs, "
                              "in run order")
    parser.add_argument("--metric", help="RESULT/META field name to plot, e.g. RMS_AC, A36, "
                         "Motor_System_INL_Deg, TrackingError_RMS_Deg, Shadow_ClosureErrorDeg")
    parser.add_argument("--list-metrics", action="store_true",
                         help="List numeric fields found in the file(s) and exit")
    parser.add_argument("--out", type=Path, default=None,
                         help="PNG output path (default: <metric>_trend.png next to the first logfile)")
    parser.add_argument("--export-csv", type=Path, default=None,
                         help="Export one wide CSV row per run, including META, RESULT, "
                              "SHADOW_RESULT and APPROACH_RESULT fields")
    parser.add_argument("--include-precondition", action="store_true",
                         help="Include PRECONDITION/EligibleForStatistics=0 runs in the linear fit "
                              "(default: shown on the plot but excluded from the fit)")
    parser.add_argument("--show", action="store_true", help="Open an interactive window too")
    args = parser.parse_args(argv)

    logfiles = expand_logfiles(args.logfiles)
    if not logfiles:
        print("error: no .txt log files matched the given input(s)", file=sys.stderr)
        return 1

    all_runs: List[RunRecord] = []
    for file_index, p in enumerate(logfiles):
        if not p.exists():
            print(f"error: file not found: {p}", file=sys.stderr)
            return 1
        if not p.is_file():
            print(f"error: not a file: {p}", file=sys.stderr)
            return 1
        all_runs.extend(load_runs(p, file_index=file_index))

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

    if args.export_csv:
        export_runs_csv(all_runs, args.export_csv, args.include_precondition)
        print(f"Exported {len(all_runs)} run(s) from {len(logfiles)} file(s): {args.export_csv}")

    if not args.metric:
        if args.export_csv:
            return 0
        parser.error("--metric is required unless --export-csv or --list-metrics is used")

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
    if fit_x:
        slope, intercept, r2 = linear_fit(fit_x, fit_y)
    else:
        slope, intercept, r2 = 0.0, 0.0, 0.0

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

    out_path = args.out or (logfiles[0].parent / f"{metric}_trend.png")
    fig.savefig(out_path, dpi=150)
    print(f"Saved: {out_path}")
    fit_mean = f"{sum(fit_y)/len(fit_y):.5g}" if fit_y else "N/A"
    print(f"n={len(present)} (fit n={len(fit_x)}, excluded={len(excluded)})  "
          f"mean={fit_mean}  slope={slope:.6g}/run  R2={r2:.4f}")

    if args.show:
        try:
            plt.show()
        except Exception as exc:  # no display available, e.g. headless CI/SSH session
            print(f"warning: --show failed ({exc}); the PNG was still saved above.", file=sys.stderr)

    plt.close(fig)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
