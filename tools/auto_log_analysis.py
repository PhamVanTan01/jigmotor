#!/usr/bin/env python3
"""Automatic UART batch capture and nonlinear-log analysis.

This module is deliberately independent from Tkinter so the serial framing,
file boundaries, and analysis contract can be unit-tested without hardware.
The GUI feeds arbitrary UART byte chunks into :class:`BatchLogRecorder`.
Completed captures are saved as plain UTF-8 text and analyzed directly with
``analyze_motor_logs``; no external Python process is required by the EXE.
"""

from __future__ import annotations

import codecs
import io
import re
import threading
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

import analyze_motor_logs as motor_analyzer


TERMINAL_BATCH_STATUSES = frozenset({"COMPLETE", "FAILED", "ABORTED"})
MAX_PREAMBLE_LINES = 1000


def parse_kv_record(line: str) -> tuple[str, Dict[str, str]]:
    """Parse a firmware CSV record without interpreting positional DATA rows."""
    parts = [part.strip() for part in line.strip().split(",")]
    if not parts:
        return "", {}
    fields: Dict[str, str] = {}
    for token in parts[1:]:
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key.strip()] = value.strip()
    return parts[0], fields


def _safe_int(value: Optional[str]) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(value, 0)
    except ValueError:
        return None


def _safe_name(value: Optional[str], fallback: str) -> str:
    candidate = (value or fallback).strip() or fallback
    candidate = re.sub(r"[^A-Za-z0-9._-]+", "-", candidate)
    return candidate.strip("-._") or fallback


def _safe_requested_stem(value: str, fallback: str) -> str:
    """Return a Windows-safe leaf stem while preserving readable Unicode."""
    candidate = Path(value.strip()).name
    if candidate.lower().endswith(".txt"):
        candidate = candidate[:-4]
    candidate = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "-", candidate)
    candidate = candidate.rstrip(" .")
    if not candidate:
        return fallback
    reserved = {"CON", "PRN", "AUX", "NUL"}
    reserved.update(f"COM{index}" for index in range(1, 10))
    reserved.update(f"LPT{index}" for index in range(1, 10))
    if candidate.split(".", 1)[0].upper() in reserved:
        candidate = "_" + candidate
    return candidate


@dataclass(frozen=True)
class CompletedCapture:
    text: str
    started_at: datetime
    completed_at: datetime
    terminal_status: str
    batch_id: Optional[int]
    expected_official_runs: Optional[int]
    motor_id: str
    jig_id: str
    build_id: str
    implicit_start: bool = False


@dataclass(frozen=True)
class AnalysisOutcome:
    passed: bool
    summary: str
    log_path: Path
    csv_path: Path
    json_path: Path
    report_path: Path
    official_valid: int
    official_expected: Optional[int]


class BatchLogRecorder:
    """Turn arbitrary UART chunks into one capture per firmware batch.

    Normal operation starts on ``BATCH,Status=START`` and finishes on a
    terminal BATCH status. If the monitor is opened after START was emitted,
    a META record creates an implicit capture which still finishes on the
    later BATCH terminal record. Legacy non-batch sweeps finish at END.
    """

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self.reset_session()

    def reset_session(self) -> None:
        with self._lock:
            self._decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
            self._pending_text = ""
            self._idle_lines: List[str] = []
            self._active_lines: Optional[List[str]] = None
            self._started_at: Optional[datetime] = None
            self._batch_id: Optional[int] = None
            self._expected_runs: Optional[int] = None
            self._motor_id = "UNKNOWN_MOTOR"
            self._jig_id = "UNKNOWN_JIG"
            self._build_id = "UNKNOWN_BUILD"
            self._implicit_start = False
            self._declared_role_seen = False

    @property
    def capture_active(self) -> bool:
        return self._active_lines is not None

    def feed(self, data: bytes) -> List[CompletedCapture]:
        if not data:
            return []
        with self._lock:
            self._pending_text += self._decoder.decode(data, final=False)
            completed: List[CompletedCapture] = []
            while "\n" in self._pending_text:
                raw_line, self._pending_text = self._pending_text.split("\n", 1)
                completed.extend(self._process_line(raw_line.rstrip("\r")))
            return completed

    def flush_incomplete(self) -> List[CompletedCapture]:
        """Flush a partial UART line and preserve an interrupted active batch."""
        with self._lock:
            completed: List[CompletedCapture] = []
            self._pending_text += self._decoder.decode(b"", final=True)
            if self._pending_text:
                completed.extend(self._process_line(self._pending_text.rstrip("\r")))
                self._pending_text = ""
            if self.capture_active:
                completed.append(self._finalize("INCOMPLETE"))
            return completed

    def _remember_idle(self, line: str) -> None:
        self._idle_lines.append(line)
        if len(self._idle_lines) > MAX_PREAMBLE_LINES:
            del self._idle_lines[: len(self._idle_lines) - MAX_PREAMBLE_LINES]

    def _start_capture(self, line: str, implicit: bool) -> None:
        self._active_lines = [*self._idle_lines, line]
        self._idle_lines = []
        self._started_at = datetime.now()
        self._batch_id = None
        self._expected_runs = None
        self._motor_id = "UNKNOWN_MOTOR"
        self._jig_id = "UNKNOWN_JIG"
        self._build_id = "UNKNOWN_BUILD"
        self._implicit_start = implicit
        self._declared_role_seen = False
        self._update_identity(line)

    def _update_identity(self, line: str) -> None:
        record, fields = parse_kv_record(line)
        if record == "BATCH":
            batch_id = _safe_int(fields.get("BatchID"))
            expected_runs = _safe_int(fields.get("RunCount"))
            if batch_id is not None:
                self._batch_id = batch_id
            if expected_runs is not None:
                self._expected_runs = expected_runs
        if record in {"CONFIG", "META"}:
            if fields.get("JigID"):
                self._jig_id = fields["JigID"]
            if fields.get("BuildID"):
                self._build_id = fields["BuildID"]
        if record == "META":
            if fields.get("MotorID"):
                self._motor_id = fields["MotorID"]
            if "RunRole" in fields or "EligibleForStatistics" in fields:
                self._declared_role_seen = True

    def _process_line(self, line: str) -> List[CompletedCapture]:
        completed: List[CompletedCapture] = []
        record, fields = parse_kv_record(line)
        status = fields.get("Status", "").upper() if record == "BATCH" else ""

        if record == "BATCH" and status == "START":
            if self.capture_active:
                completed.append(self._finalize("INCOMPLETE"))
            self._start_capture(line, implicit=False)
            return completed

        if not self.capture_active and record == "META":
            # The monitor may have been connected after BATCH START. Keep the
            # sweep instead of silently losing the entire test.
            self._start_capture(line, implicit=True)
        elif self.capture_active:
            assert self._active_lines is not None
            self._active_lines.append(line)
            self._update_identity(line)
        else:
            self._remember_idle(line)

        if record == "BATCH" and status in TERMINAL_BATCH_STATUSES:
            if not self.capture_active:
                # The terminal line was just retained as idle preamble above.
                # Remove it before starting so it appears exactly once.
                if self._idle_lines and self._idle_lines[-1] == line:
                    self._idle_lines.pop()
                self._start_capture(line, implicit=True)
            completed.append(self._finalize(status))
        elif record == "END" and self.capture_active and self._implicit_start:
            # Legacy logs have no batch role. New batch logs must wait for the
            # BATCH terminal record because END appears after every sweep.
            if not self._declared_role_seen:
                completed.append(self._finalize(fields.get("Status", "END")))
        return completed

    def _finalize(self, status: str) -> CompletedCapture:
        lines = self._active_lines or []
        capture = CompletedCapture(
            text="\n".join(lines).rstrip("\n") + "\n",
            started_at=self._started_at or datetime.now(),
            completed_at=datetime.now(),
            terminal_status=status,
            batch_id=self._batch_id,
            expected_official_runs=self._expected_runs,
            motor_id=self._motor_id,
            jig_id=self._jig_id,
            build_id=self._build_id,
            implicit_start=self._implicit_start,
        )
        self._active_lines = None
        self._started_at = None
        self._batch_id = None
        self._expected_runs = None
        self._motor_id = "UNKNOWN_MOTOR"
        self._jig_id = "UNKNOWN_JIG"
        self._build_id = "UNKNOWN_BUILD"
        self._implicit_start = False
        self._declared_role_seen = False
        self._idle_lines = []
        return capture


def suggested_capture_filename(capture: CompletedCapture) -> str:
    """Build the editable default filename shown to the operator."""
    stamp = capture.started_at.strftime("%Y%m%d-%H%M%S")
    motor = _safe_name(capture.motor_id, "UNKNOWN_MOTOR")
    jig = _safe_name(capture.jig_id, "UNKNOWN_JIG")
    batch = f"batch{capture.batch_id:03d}" if capture.batch_id is not None else "batchNA"
    status = _safe_name(capture.terminal_status.lower(), "unknown")
    return f"{stamp}_{motor}_{jig}_{batch}_{status}.txt"


def save_capture(
    capture: CompletedCapture,
    output_dir: Path,
    requested_filename: Optional[str] = None,
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    suggested_name = suggested_capture_filename(capture)
    fallback_stem = Path(suggested_name).stem
    base = _safe_requested_stem(requested_filename or suggested_name, fallback_stem)
    path = output_dir / f"{base}.txt"
    suffix = 2
    while path.exists():
        path = output_dir / f"{base}_{suffix:02d}.txt"
        suffix += 1
    path.write_text(capture.text, encoding="utf-8", newline="\n")
    return path


def _configuration_health(log_path: Path) -> tuple[int, int, int]:
    gated_total = 0
    gated_invalid = 0
    boot_invalid = 0
    for raw_line in log_path.read_text(encoding="utf-8", errors="replace").splitlines():
        record, fields = parse_kv_record(raw_line)
        if record != "CONFIG":
            continue
        invalid = fields.get("ConfigValid") == "0" or fields.get("PolicyAGatePassed") == "0"
        if fields.get("ConfigContext") == "BOOT_SMOKE":
            boot_invalid += int(invalid)
        else:
            gated_total += 1
            gated_invalid += int(invalid)
    return gated_total, gated_invalid, boot_invalid


def analyze_saved_log(
    log_path: Path,
    expected_official_runs: Optional[int] = None,
    terminal_status: str = "COMPLETE",
) -> AnalysisOutcome:
    """Recompute metrics, write machine-readable artifacts, and return a GUI summary."""
    sweeps, warnings = motor_analyzer.load_sweeps(log_path)
    reports = [motor_analyzer.build_report(sweep) for sweep in sweeps]
    motor_analyzer.infer_run_order(reports)

    by_group: Dict[tuple[str, str], List[motor_analyzer.SweepReport]] = {}
    for report in reports:
        by_group.setdefault(motor_analyzer.group_key(report.sweep), []).append(report)
    summaries = [
        motor_analyzer.summarize_group(motor_id, jig_id, group_reports)
        for (motor_id, jig_id), group_reports in sorted(by_group.items())
    ]

    csv_path = log_path.with_name(log_path.stem + ".metrics.csv")
    json_path = log_path.with_name(log_path.stem + ".analysis.json")
    report_path = log_path.with_name(log_path.stem + ".analysis.txt")
    motor_analyzer.write_csv(reports, csv_path)
    motor_analyzer.write_json(reports, summaries, json_path)

    gated_configs, invalid_configs, boot_invalid = _configuration_health(log_path)
    official_reports = [r for r in reports if r.sweep.run_role == "OFFICIAL"]
    if not official_reports:
        official_reports = [r for r in reports if not r.sweep.uses_declared_role_contract]
    valid_official = [r for r in official_reports if r.officially_valid]
    expected = expected_official_runs
    if expected is None and official_reports:
        expected = len(official_reports)

    passed = (
        terminal_status.upper() == "COMPLETE"
        and bool(reports)
        and invalid_configs == 0
        and len(valid_official) == len(official_reports)
        and (expected is None or len(valid_official) == expected)
    )

    report_buffer = io.StringIO()
    report_buffer.write("AUTO-CAPTURE ANALYSIS\n")
    report_buffer.write(f"Source={log_path}\n")
    report_buffer.write(f"TerminalStatus={terminal_status}\n")
    report_buffer.write(
        f"OfficialValid={len(valid_official)}/{expected if expected is not None else 'NA'}\n"
    )
    report_buffer.write(
        f"GatedConfigInvalid={invalid_configs}/{gated_configs},BootSmokeInvalid={boot_invalid}\n"
    )
    report_buffer.write(f"AutoVerdict={'PASS' if passed else 'FAIL'}\n\n")
    motor_analyzer.print_text_report(reports, summaries, warnings, out=report_buffer)
    report_path.write_text(report_buffer.getvalue(), encoding="utf-8", newline="\n")

    summary_parts: List[str] = [
        "PASS" if passed else "FAIL",
        f"OFFICIAL {len(valid_official)}/{expected if expected is not None else 'NA'}",
    ]
    if summaries:
        summary = summaries[0]
        nl = summary.fields.get("robust_p2p", {}).get("mean")
        nl_sd = summary.fields.get("robust_p2p", {}).get("sd")
        rms = summary.fields.get("rms_ac", {}).get("mean")
        closure_values = [
            abs(r.metrics.closure_error_deg)
            for r in valid_official
            if r.metrics is not None and r.metrics.closure_error_deg is not None
        ]
        summary_parts.insert(1, f"{summary.motor_id}/{summary.jig_id}")
        if nl is not None:
            summary_parts.append(f"NL={nl:.4f} deg")
        if nl_sd is not None:
            summary_parts.append(f"SD={nl_sd:.4f} deg")
        if rms is not None:
            summary_parts.append(f"RMS_AC={rms:.4f} deg")
        if closure_values:
            summary_parts.append(f"ClosureMax={max(closure_values):.4f} deg")
    if invalid_configs:
        summary_parts.append(f"CONFIG_INVALID={invalid_configs}")
    if warnings:
        summary_parts.append(f"WARN={len(warnings)}")

    return AnalysisOutcome(
        passed=passed,
        summary=" | ".join(summary_parts),
        log_path=log_path,
        csv_path=csv_path,
        json_path=json_path,
        report_path=report_path,
        official_valid=len(valid_official),
        official_expected=expected,
    )
