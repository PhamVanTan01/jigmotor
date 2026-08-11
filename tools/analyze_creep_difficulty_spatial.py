#!/usr/bin/env python3
"""Analyze the spatial repeatability of pre-creep point difficulty.

The firmware logs MOTION.PositionErrorRaw before ENABLE_SWEEP_POINT_CREEP
calls CreepToUnwrappedTarget().  This tool uses abs(PositionErrorRaw) as the
per-point difficulty proxy, averages it over declared OFFICIAL/eligible
sweeps, and compares independent remounts.

The primary analysis uses only complete official sweeps (all analysis-point
MOTION records present).  A sensitivity analysis also includes incomplete
official sweeps point-by-point, so a damaged UART/log segment is visible and
cannot silently bias the primary conclusion.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import statistics
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


RAW_PER_REV = 65536.0


def parse_kv_record(record: str) -> Dict[str, str]:
    fields = record.strip().split(",")
    parsed: Dict[str, str] = {"_record": fields[0]}
    for field_value in fields[1:]:
        if "=" not in field_value:
            continue
        key, value = field_value.split("=", 1)
        parsed[key.strip()] = value.strip()
    return parsed


def extract_record(line: str, prefix: str) -> Optional[Dict[str, str]]:
    """Return PREFIX record even when a damaged log concatenated it to text."""
    marker = prefix + ","
    search_from = 0
    while True:
        start = line.find(marker, search_from)
        if start < 0:
            return None
        # `META,` and `END,` are also substrings of SHADOW_META/SHADOW_END.
        # Those records have different contracts and must never overwrite the
        # official META role or END counters.  A genuine concatenated record
        # such as `DATA,...MOTION,...` remains recoverable.
        if not line[:start].endswith("SHADOW_"):
            return parse_kv_record(line[start:])
        search_from = start + len(marker)


def as_int(record: Dict[str, str], key: str) -> int:
    try:
        return int(record[key])
    except (KeyError, ValueError) as exc:
        raise ValueError(f"invalid or missing {key} in {record}") from exc


@dataclass
class Sweep:
    test_id: int
    sweep_id: int
    role: str = "UNKNOWN"
    eligible: bool = False
    build_id: str = "UNKNOWN"
    jig_id: str = "UNKNOWN"
    points: Dict[int, int] = field(default_factory=dict)
    duplicates: Set[int] = field(default_factory=set)
    end: Dict[str, str] = field(default_factory=dict)

    def missing_points(self, analysis_points: int) -> List[int]:
        return [point for point in range(analysis_points)
                if point not in self.points]

    def complete(self, analysis_points: int) -> bool:
        return not self.missing_points(analysis_points) and not self.duplicates


@dataclass
class LogData:
    path: Path
    label: str
    sweeps: Dict[Tuple[int, int], Sweep]

    def official(self) -> List[Sweep]:
        return sorted(
            (sweep for sweep in self.sweeps.values()
             if sweep.role == "OFFICIAL" and sweep.eligible),
            key=lambda sweep: (sweep.test_id, sweep.sweep_id),
        )


@dataclass
class RemountCurve:
    log: LogData
    complete_sweeps: List[Sweep]
    all_official_sweeps: List[Sweep]
    mean_abs_raw: List[float]
    sensitivity_mean_abs_raw: List[float]
    sensitivity_counts: List[int]


def infer_label(path: Path) -> str:
    match = re.search(r"remount[-_ ]?(\d+)", path.stem, flags=re.IGNORECASE)
    return f"remount{match.group(1)}" if match else path.stem


def load_log(path: Path, analysis_points: int) -> LogData:
    sweeps: Dict[Tuple[int, int], Sweep] = {}

    def get_sweep(test_id: int, sweep_id: int) -> Sweep:
        key = (test_id, sweep_id)
        if key not in sweeps:
            sweeps[key] = Sweep(test_id=test_id, sweep_id=sweep_id)
        return sweeps[key]

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, start=1):
            meta = extract_record(line, "META")
            if meta is not None and "TestID" in meta and "SweepID" in meta:
                sweep = get_sweep(as_int(meta, "TestID"), as_int(meta, "SweepID"))
                sweep.role = meta.get("RunRole", "UNKNOWN").upper()
                sweep.eligible = meta.get("EligibleForStatistics", "0") == "1"
                sweep.build_id = meta.get("BuildID", "UNKNOWN")
                sweep.jig_id = meta.get("JigID", "UNKNOWN")

            motion = extract_record(line, "MOTION")
            if motion is not None and all(
                    key in motion for key in
                    ("TestID", "SweepID", "Point", "PositionErrorRaw")):
                sweep = get_sweep(
                    as_int(motion, "TestID"), as_int(motion, "SweepID"))
                point = as_int(motion, "Point")
                if point < 0:
                    raise ValueError(f"{path}:{line_number}: negative Point={point}")
                if point in sweep.points:
                    sweep.duplicates.add(point)
                sweep.points[point] = as_int(motion, "PositionErrorRaw")

            end = extract_record(line, "END")
            if end is not None and "TestID" in end and "SweepID" in end:
                sweep = get_sweep(as_int(end, "TestID"), as_int(end, "SweepID"))
                sweep.end = end

    official = [sweep for sweep in sweeps.values()
                if sweep.role == "OFFICIAL" and sweep.eligible]
    if not official:
        raise ValueError(f"{path}: no declared OFFICIAL eligible sweeps")
    for sweep in official:
        if not sweep.end:
            raise ValueError(
                f"{path}: TestID={sweep.test_id} has no END record")
        if sweep.end.get("Status") != "VALID":
            raise ValueError(
                f"{path}: TestID={sweep.test_id} END is not VALID")
        # Values beyond the analysis window are intentionally retained in
        # Sweep.points for audit, but never enter a 0..analysis_points-1 curve.
        if not any(point < analysis_points for point in sweep.points):
            raise ValueError(
                f"{path}: TestID={sweep.test_id} has no analysis MOTION points")
    return LogData(path=path, label=infer_label(path), sweeps=sweeps)


def build_curve(log: LogData, analysis_points: int) -> RemountCurve:
    official = log.official()
    complete = [sweep for sweep in official if sweep.complete(analysis_points)]
    if not complete:
        raise ValueError(f"{log.path}: no complete official sweeps")

    mean_abs_raw = [
        statistics.fmean(abs(sweep.points[point]) for sweep in complete)
        for point in range(analysis_points)
    ]
    sensitivity_mean: List[float] = []
    sensitivity_counts: List[int] = []
    for point in range(analysis_points):
        available = [abs(sweep.points[point]) for sweep in official
                     if point in sweep.points]
        if not available:
            raise ValueError(
                f"{log.path}: Point={point} absent from all official sweeps")
        sensitivity_mean.append(statistics.fmean(available))
        sensitivity_counts.append(len(available))
    return RemountCurve(
        log=log,
        complete_sweeps=complete,
        all_official_sweeps=official,
        mean_abs_raw=mean_abs_raw,
        sensitivity_mean_abs_raw=sensitivity_mean,
        sensitivity_counts=sensitivity_counts,
    )


def pearson(a: Sequence[float], b: Sequence[float]) -> float:
    if len(a) != len(b) or len(a) < 2:
        return float("nan")
    mean_a = statistics.fmean(a)
    mean_b = statistics.fmean(b)
    da = [value - mean_a for value in a]
    db = [value - mean_b for value in b]
    denominator = math.sqrt(sum(value * value for value in da)
                            * sum(value * value for value in db))
    if denominator == 0.0:
        return float("nan")
    return sum(x * y for x, y in zip(da, db)) / denominator


def ranks(values: Sequence[float]) -> List[float]:
    ordered = sorted(enumerate(values), key=lambda item: item[1])
    result = [0.0] * len(values)
    index = 0
    while index < len(ordered):
        end = index + 1
        while end < len(ordered) and ordered[end][1] == ordered[index][1]:
            end += 1
        average_rank = (index + 1 + end) / 2.0
        for ordered_index in range(index, end):
            result[ordered[ordered_index][0]] = average_rank
        index = end
    return result


def spearman(a: Sequence[float], b: Sequence[float]) -> float:
    return pearson(ranks(a), ranks(b))


def top_set(values: Sequence[float], count: int) -> Set[int]:
    return set(sorted(range(len(values)),
                      key=lambda point: (-values[point], point))[:count])


def top_list(values: Sequence[float], count: int) -> List[int]:
    return sorted(range(len(values)),
                  key=lambda point: (-values[point], point))[:count]


def threshold_set(values: Sequence[float], threshold: float) -> Set[int]:
    return {point for point, value in enumerate(values) if value > threshold}


def jaccard(a: Set[int], b: Set[int]) -> float:
    union = a | b
    return len(a & b) / len(union) if union else 1.0


def circular_distance(a: int, b: int, count: int) -> int:
    distance = abs(a - b) % count
    return min(distance, count - distance)


def harmonic_amplitude(values: Sequence[float], order: int) -> float:
    """DFT amplitude after removing the curve mean."""
    count = len(values)
    mean_value = statistics.fmean(values)
    cosine = 0.0
    sine = 0.0
    for point, value in enumerate(values):
        phase = 2.0 * math.pi * order * point / count
        centered = value - mean_value
        cosine += centered * math.cos(phase)
        sine += centered * math.sin(phase)
    scale = 2.0 / count
    return math.hypot(scale * cosine, scale * sine)


def dominant_harmonics(values: Sequence[float], count: int = 8
                       ) -> List[Tuple[int, float]]:
    # The Nyquist order is included for an even-length curve.  Reporting the
    # dominant orders of |PositionErrorRaw| helps distinguish one localized
    # mechanical event from a repeated electrical/control pattern.
    amplitudes = [
        (order, harmonic_amplitude(values, order))
        for order in range(1, len(values) // 2 + 1)
    ]
    return sorted(amplitudes, key=lambda item: (-item[1], item[0]))[:count]


def format_points(points: Iterable[int]) -> str:
    ordered = sorted(points)
    return ", ".join(f"{point}°" for point in ordered) if ordered else "—"


def format_top(values: Sequence[float], count: int) -> str:
    return ", ".join(
        f"{point}° ({values[point]:.1f} raw/{values[point] * 360.0 / RAW_PER_REV:.3f}°)"
        for point in top_list(values, count)
    )


def end_counter(sweep: Sweep, key: str) -> str:
    return sweep.end.get(key, "NA")


def pairwise(curves: Sequence[RemountCurve]):
    for index, curve_a in enumerate(curves):
        for curve_b in curves[index + 1:]:
            yield curve_a, curve_b


def proximity_matches(points: Set[int], references: Set[int],
                      tolerance: int, analysis_points: int) -> Set[int]:
    return {point for point in points
            if any(circular_distance(point, reference, analysis_points)
                   <= tolerance for reference in references)}


def render_report(curves: Sequence[RemountCurve], analysis_points: int,
                  top_percentages: Sequence[float], top_count: int,
                  threshold_raw: float, budget_raw: float,
                  nl_extremes: Sequence[int]) -> str:
    if len(curves) < 2:
        raise ValueError("at least two remount logs are required")

    percent_counts = {
        percentage: max(1, math.ceil(analysis_points * percentage / 100.0))
        for percentage in top_percentages
    }
    lines: List[str] = [
        "# P08/JIG7 v4 — phân tích không gian độ khó sweep-point-creep",
        "",
        "## Kết luận điều hành",
        "",
        "Phần kết luận tự động nằm ở cuối báo cáo sau khi trình bày đầy đủ data-integrity, "
        "overlap, correlation và đối chiếu NL. `|MOTION.PositionErrorRaw|` là proxy khe hở "
        "**trước creep**, không phải số iteration thật của từng điểm.",
        "",
        "## Phương pháp",
        "",
        f"- Phạm vi phân tích: Point `0..{analysis_points - 1}`.",
        "- Chỉ dùng sweep có `RunRole=OFFICIAL`, `EligibleForStatistics=1`, "
        "`END.Status=VALID`.",
        "- Primary: chỉ dùng official sweep đủ toàn bộ MOTION point.",
        "- Sensitivity: dùng thêm official sweep không hoàn chỉnh tại từng point còn tồn tại.",
        "- Difficulty(point): trung bình `abs(PositionErrorRaw)` qua các sweep được dùng.",
        "- Pearson đo độ giống về biên độ; Spearman đo độ giống về thứ hạng điểm khó.",
        "",
        "## Data integrity và sanity-check END",
        "",
        "| Remount | File | Official khai báo | Official đầy đủ dùng primary | Sweep không đầy đủ |",
        "|---|---|---:|---:|---|",
    ]
    for curve in curves:
        incomplete = []
        for sweep in curve.all_official_sweeps:
            missing = sweep.missing_points(analysis_points)
            if missing:
                incomplete.append(
                    f"TestID {sweep.test_id}: thiếu {len(missing)} point "
                    f"({format_points(missing)})")
        lines.append(
            f"| {curve.log.label} | `{curve.log.path.as_posix()}` | "
            f"{len(curve.all_official_sweeps)} | {len(curve.complete_sweeps)} | "
            f"{'<br>'.join(incomplete) if incomplete else 'Không'} |")

    lines.extend([
        "",
        "| Remount | TestID | Complete | Corrected points | Iterations | Correction raw | Timeouts | BudgetExceeded |",
        "|---|---:|---|---:|---:|---:|---:|---:|",
    ])
    for curve in curves:
        for sweep in curve.all_official_sweeps:
            lines.append(
                f"| {curve.log.label} | {sweep.test_id} | "
                f"{'YES' if sweep.complete(analysis_points) else 'NO'} | "
                f"{end_counter(sweep, 'SweepPointCreepPointsCorrected')} | "
                f"{end_counter(sweep, 'SweepPointCreepTotalIterations')} | "
                f"{end_counter(sweep, 'SweepPointCreepTotalCorrectionRaw')} | "
                f"{end_counter(sweep, 'SweepPointCreepTimeouts')} | "
                f"{end_counter(sweep, 'SweepPointCreepBudgetExceeded')} |")

    lines.extend([
        "",
        "Các counter END chỉ là tổng toàn sweep. Chúng được dùng sanity-check, không dùng "
        "gán BudgetExceeded cho một góc cụ thể.",
        "",
        "## Top điểm khó của từng remount",
        "",
    ])
    for curve in curves:
        lines.extend([
            f"### {curve.log.label}",
            "",
            f"Top {top_count}: {format_top(curve.mean_abs_raw, top_count)}",
            "",
            f"Số điểm `>{threshold_raw:g} raw`: "
            f"{len(threshold_set(curve.mean_abs_raw, threshold_raw))}; "
            f"số điểm `>={budget_raw:g} raw`: "
            f"{sum(value >= budget_raw for value in curve.mean_abs_raw)}.",
            "",
        ])

    for percentage, count in percent_counts.items():
        lines.extend([
            f"## Overlap top {percentage:g}% ({count} điểm/remount)",
            "",
            "| Cặp | Giao nhau | Jaccard | Trùng trên mỗi tập |",
            "|---|---:|---:|---:|",
        ])
        sets = {curve.log.label: top_set(curve.mean_abs_raw, count)
                for curve in curves}
        for curve_a, curve_b in pairwise(curves):
            set_a = sets[curve_a.log.label]
            set_b = sets[curve_b.log.label]
            intersection = set_a & set_b
            lines.append(
                f"| {curve_a.log.label} vs {curve_b.log.label} | "
                f"{len(intersection)} | {jaccard(set_a, set_b):.3f} "
                f"({100.0 * jaccard(set_a, set_b):.1f}%) | "
                f"{100.0 * len(intersection) / count:.1f}% |")
        all_intersection = set.intersection(*sets.values())
        membership = Counter(point for points in sets.values() for point in points)
        at_least_two = {point for point, frequency in membership.items()
                        if frequency >= 2}
        lines.extend([
            "",
            f"- Có trong top {percentage:g}% của cả ba remount: "
            f"{format_points(all_intersection)}.",
            f"- Có trong top {percentage:g}% của ít nhất 2/3 remount: "
            f"{format_points(at_least_two)}.",
            "",
        ])

    lines.extend([
        f"## Overlap theo ngưỡng cố định >{threshold_raw:g} raw",
        "",
        "| Cặp | Kích thước A/B | Giao nhau | Jaccard |",
        "|---|---:|---:|---:|",
    ])
    threshold_sets = {
        curve.log.label: threshold_set(curve.mean_abs_raw, threshold_raw)
        for curve in curves
    }
    for curve_a, curve_b in pairwise(curves):
        set_a = threshold_sets[curve_a.log.label]
        set_b = threshold_sets[curve_b.log.label]
        lines.append(
            f"| {curve_a.log.label} vs {curve_b.log.label} | "
            f"{len(set_a)}/{len(set_b)} | {len(set_a & set_b)} | "
            f"{jaccard(set_a, set_b):.3f} ({100.0 * jaccard(set_a, set_b):.1f}%) |")

    lines.extend([
        "",
        "## Tương quan difficulty curve đầy đủ",
        "",
        "| Cặp | Pearson primary | Spearman primary | Pearson sensitivity | Spearman sensitivity |",
        "|---|---:|---:|---:|---:|",
    ])
    primary_pearsons: List[float] = []
    primary_spearmans: List[float] = []
    sensitivity_deltas: List[float] = []
    for curve_a, curve_b in pairwise(curves):
        p_primary = pearson(curve_a.mean_abs_raw, curve_b.mean_abs_raw)
        s_primary = spearman(curve_a.mean_abs_raw, curve_b.mean_abs_raw)
        p_sensitivity = pearson(curve_a.sensitivity_mean_abs_raw,
                                curve_b.sensitivity_mean_abs_raw)
        s_sensitivity = spearman(curve_a.sensitivity_mean_abs_raw,
                                 curve_b.sensitivity_mean_abs_raw)
        primary_pearsons.append(p_primary)
        primary_spearmans.append(s_primary)
        sensitivity_deltas.append(max(abs(p_primary - p_sensitivity),
                                      abs(s_primary - s_sensitivity)))
        lines.append(
            f"| {curve_a.log.label} vs {curve_b.log.label} | "
            f"{p_primary:.4f} | {s_primary:.4f} | "
            f"{p_sensitivity:.4f} | {s_sensitivity:.4f} |")

    nl_set = set(nl_extremes)
    lines.extend([
        "",
        "## Đối chiếu với cực trị NL sau creep",
        "",
        f"Cực trị NL tham chiếu: {format_points(nl_set)}.",
        "",
        f"| Remount | Top-{top_count} difficulty trùng chính xác | Trong ±1° | Trong ±2° |",
        "|---|---|---|---|",
    ])
    exact_match_counts: List[int] = []
    for curve in curves:
        difficult = top_set(curve.mean_abs_raw, top_count)
        exact = difficult & nl_set
        near_one = proximity_matches(difficult, nl_set, 1, analysis_points)
        near_two = proximity_matches(difficult, nl_set, 2, analysis_points)
        exact_match_counts.append(len(exact))
        lines.append(
            f"| {curve.log.label} | {format_points(exact)} | "
            f"{format_points(near_one)} | {format_points(near_two)} |")

    lines.extend([
        "",
        "## Periodicity của difficulty curve",
        "",
        "DFT dưới đây chạy trên `mean(abs(PositionErrorRaw))` sau khi loại mean. "
        "Đây là chẩn đoán bổ sung: một điểm cơ khí đơn thường tạo peak cục bộ/broadband, "
        "còn các order lặp lại qua remount gợi ý nguồn điện từ/controller hoặc cấu trúc tuần hoàn.",
        "",
        "| Remount | 8 harmonic mạnh nhất (order: amplitude raw) |",
        "|---|---|",
    ])
    dominant_orders: List[List[int]] = []
    for curve in curves:
        harmonics = dominant_harmonics(curve.mean_abs_raw)
        dominant_orders.append([order for order, _ in harmonics])
        description = ", ".join(
            f"H{order}: {amplitude:.2f}" for order, amplitude in harmonics)
        lines.append(f"| {curve.log.label} | {description} |")
    shared_dominant_orders = set(dominant_orders[0]).intersection(
        *(set(orders) for orders in dominant_orders[1:]))
    lines.extend([
        "",
        "- Harmonic nằm trong top-8 của cả ba remount: "
        f"{', '.join(f'H{order}' for order in sorted(shared_dominant_orders)) or '—'}.",
        "- Với motor 6 cặp cực, H36 tương ứng sáu ripple trên mỗi chu kỳ điện; "
        "H72 là harmonic bậc hai của pattern đó.",
    ])

    top15_sets = [top_set(curve.mean_abs_raw, top_count) for curve in curves]
    top15_membership = Counter(point for points in top15_sets for point in points)
    stable_top15 = {point for point, frequency in top15_membership.items()
                    if frequency >= 2}
    stable_exact = stable_top15 & nl_set

    # Classification is deliberately conservative. All three pairwise curves
    # must remain positively correlated and at least moderately ranked alike;
    # overlap is reported separately rather than hidden in one score.
    min_pearson = min(primary_pearsons)
    min_spearman = min(primary_spearmans)
    repeatable = min_pearson >= 0.50 and min_spearman >= 0.50
    sensitivity_consistent = max(sensitivity_deltas, default=0.0) < 0.10

    lines.extend([
        "",
        "## Kết luận",
        "",
        f"- Pearson nhỏ nhất giữa các remount: **{min_pearson:.4f}**.",
        f"- Spearman nhỏ nhất giữa các remount: **{min_spearman:.4f}**.",
        f"- Độ lệch lớn nhất giữa primary và sensitivity correlation: "
        f"**{max(sensitivity_deltas, default=0.0):.4f}**.",
        f"- Điểm top-{top_count} xuất hiện trong ít nhất 2/3 remount: "
        f"**{format_points(stable_top15)}**.",
        f"- Trong nhóm ổn định đó, điểm trùng cực trị NL: "
        f"**{format_points(stable_exact)}**.",
        "",
    ])
    if repeatable:
        lines.append(
            "**Kết luận nhị phân: CÓ — độ khó theo góc có cấu trúc lặp lại qua "
            "các remount, không phù hợp với giả thuyết nhiễu ngẫu nhiên độc lập.**")
    else:
        lines.append(
            "**Kết luận nhị phân: KHÔNG — dữ liệu không cho thấy difficulty curve "
            "lặp lại đủ mạnh qua mọi remount; chưa có cơ sở gán cho một điểm cơ khí cố định.**")
    lines.extend([
        "",
        "### Giới hạn diễn giải",
        "",
        "Tương quan theo góc cao loại trừ phần lớn giả thuyết nhiễu thống kê độc lập, nhưng "
        "không tự chứng minh duy nhất một lỗi cơ khí cục bộ. DFT difficulty curve cho thấy một "
        "họ harmonic lặp lại qua các remount; pattern có thể đến từ cogging/điện từ, H36, "
        "controller hoặc tương tác motor–mounting được khóa theo sweep origin. Vì vậy kết quả "
        "này xác nhận **các vùng góc khó ổn định**, nhưng chưa xác nhận **một điểm hỏng cơ khí "
        "duy nhất**.",
        "",
    ])
    if not sensitivity_consistent:
        lines.append(
            "Cảnh báo: sensitivity analysis thay đổi correlation đáng kể; cần phục hồi hoặc "
            "đo lại phần log thiếu trước khi dùng kết luận cho quyết định firmware.")
    else:
        lines.append(
            "Sensitivity analysis không đổi kết luận đáng kể. Tuy vậy, để tuyên bố đúng thiết "
            "kế 3 official/remount, vẫn cần phục hồi hoặc đo lại 13 MOTION record bị mất của "
            "remount03 TestID 6.")

    return "\n".join(lines) + "\n"


def write_csv(path: Path, curves: Sequence[RemountCurve],
              analysis_points: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle)
        header = ["Point"]
        for curve in curves:
            header.extend([
                f"{curve.log.label}_MeanAbsPositionErrorRaw_Primary",
                f"{curve.log.label}_MeanAbsPositionErrorDeg_Primary",
                f"{curve.log.label}_MeanAbsPositionErrorRaw_Sensitivity",
                f"{curve.log.label}_SensitivitySweepCount",
            ])
        writer.writerow(header)
        for point in range(analysis_points):
            row: List[object] = [point]
            for curve in curves:
                primary = curve.mean_abs_raw[point]
                row.extend([
                    f"{primary:.6f}",
                    f"{primary * 360.0 / RAW_PER_REV:.9f}",
                    f"{curve.sensitivity_mean_abs_raw[point]:.6f}",
                    curve.sensitivity_counts[point],
                ])
            writer.writerow(row)


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Analyze spatial repeatability of pre-creep MOTION error")
    parser.add_argument("logfiles", nargs="+", type=Path)
    parser.add_argument("--analysis-points", type=int, default=360)
    parser.add_argument("--top-percent", type=float, nargs="+",
                        default=[10.0, 15.0])
    parser.add_argument("--top-count", type=int, default=15)
    parser.add_argument("--threshold-raw", type=float, default=150.0)
    parser.add_argument("--budget-raw", type=float, default=220.0)
    parser.add_argument("--nl-extremes", type=int, nargs="*",
                        default=[293, 173, 292, 26, 186,
                                 107, 67, 68, 45, 37])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--csv", type=Path)
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    if args.analysis_points <= 1:
        raise SystemExit("--analysis-points must be > 1")
    for percentage in args.top_percent:
        if not 0.0 < percentage <= 100.0:
            raise SystemExit("--top-percent values must be in (0, 100]")
    logs = [load_log(path, args.analysis_points) for path in args.logfiles]
    labels = [log.label for log in logs]
    if len(labels) != len(set(labels)):
        raise SystemExit(f"remount labels are not unique: {labels}")
    curves = [build_curve(log, args.analysis_points) for log in logs]
    report = render_report(
        curves=curves,
        analysis_points=args.analysis_points,
        top_percentages=args.top_percent,
        top_count=args.top_count,
        threshold_raw=args.threshold_raw,
        budget_raw=args.budget_raw,
        nl_extremes=args.nl_extremes,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report, encoding="utf-8")
    if args.csv is not None:
        write_csv(args.csv, curves, args.analysis_points)
    print(f"Report: {args.out}")
    if args.csv is not None:
        print(f"CSV: {args.csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
