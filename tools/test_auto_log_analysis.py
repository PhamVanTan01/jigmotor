#!/usr/bin/env python3
"""Hardware-free tests for automatic UART capture and analysis."""

from __future__ import annotations

import math
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from auto_log_analysis import (  # noqa: E402
    BatchLogRecorder,
    analyze_saved_log,
    save_capture,
    suggested_capture_filename,
)


def make_sweep(test_id: int, run_order: int, role: str, eligible: int) -> list[str]:
    lines = [
        "META,SchemaVersion=5,Firmware=test,BuildID=unit-test,JigID=JIG1,"
        f"MotorID=p03,TestID={test_id},SweepID={test_id},Direction=CW,"
        "MeasurementValid=1,TrackingValid=1,AnalysisPoints=360,StepRaw=0,"
        "ShadowContractVersion=CANONICAL_Q16_1DEG360_V2,"
        f"RunOrder={run_order},RunRole={role},EligibleForStatistics={eligible}"
    ]
    for index in range(361):
        target = round(index * 65536 / 360)
        wrapped_target = target & 0xFFFF
        error = 0.6 * math.sin(math.radians(36 * index)) + 0.1 * math.sin(
            math.radians(index)
        )
        angle_raw = int(round(wrapped_target - error * 65536 / 360)) & 0xFFFF
        lines.append(
            f"DATA,5,{test_id},{test_id},JIG1,p03,CW,{index},{target},"
            f"{angle_raw},{angle_raw * 360.0 / 65536.0:.5f},{error:.5f}"
        )
    lines.append(
        f"END,SchemaVersion=5,TestID={test_id},SweepID={test_id},Direction=CW,"
        "CapturedPoints=361,AnalysisPoints=360,Status=VALID"
    )
    return lines


def make_complete_batch() -> bytes:
    lines = [
        "BUILD_MANIFEST,AppMode=MEASUREMENT,AppProfile=UNIT_TEST",
        "BATCH,BatchID=7,Status=START,PreconditionCount=1,RunCount=2,TotalCycleCount=3",
        "CONFIG,ConfigContext=PRECONDITION_PRE_MOTOR,ConfigValid=1,"
        "PolicyAGatePassed=1,JigID=JIG1,BuildID=unit-test",
    ]
    lines.extend(make_sweep(1, 0, "PRECONDITION", 0))
    lines.extend(make_sweep(2, 1, "OFFICIAL", 1))
    lines.extend(make_sweep(3, 2, "OFFICIAL", 1))
    lines.append(
        "BATCH,BatchID=7,Status=COMPLETE,PreconditionCount=1,RunCount=2,TotalCycleCount=3"
    )
    return ("\r\n".join(lines) + "\r\n").encode("utf-8")


class BatchLogRecorderTests(unittest.TestCase):
    def test_chunked_batch_is_completed_once(self) -> None:
        payload = make_complete_batch()
        recorder = BatchLogRecorder()
        captures = []
        chunk_sizes = (1, 7, 31, 3, 128, 19)
        offset = 0
        chunk_index = 0
        while offset < len(payload):
            size = chunk_sizes[chunk_index % len(chunk_sizes)]
            captures.extend(recorder.feed(payload[offset : offset + size]))
            offset += size
            chunk_index += 1

        self.assertEqual(len(captures), 1)
        capture = captures[0]
        self.assertEqual(capture.batch_id, 7)
        self.assertEqual(capture.expected_official_runs, 2)
        self.assertEqual(capture.motor_id, "p03")
        self.assertEqual(capture.jig_id, "JIG1")
        self.assertEqual(capture.terminal_status, "COMPLETE")
        self.assertIn("BUILD_MANIFEST", capture.text)
        self.assertIn("BATCH,BatchID=7,Status=COMPLETE", capture.text)

    def test_interrupted_batch_is_preserved(self) -> None:
        recorder = BatchLogRecorder()
        recorder.feed(
            b"BATCH,BatchID=9,Status=START,RunCount=3\r\n"
            b"META,TestID=1,SweepID=1,JigID=JIG1,MotorID=p05\r\n"
        )
        captures = recorder.flush_incomplete()
        self.assertEqual(len(captures), 1)
        self.assertEqual(captures[0].terminal_status, "INCOMPLETE")
        self.assertIn("MotorID=p05", captures[0].text)

    def test_complete_batch_saves_and_analyzes(self) -> None:
        recorder = BatchLogRecorder()
        captures = recorder.feed(make_complete_batch())
        self.assertEqual(len(captures), 1)

        with tempfile.TemporaryDirectory() as temporary_dir:
            log_path = save_capture(captures[0], Path(temporary_dir))
            outcome = analyze_saved_log(
                log_path,
                expected_official_runs=captures[0].expected_official_runs,
                terminal_status=captures[0].terminal_status,
            )
            self.assertTrue(outcome.passed, outcome.summary)
            self.assertEqual(outcome.official_valid, 2)
            self.assertIn("p03/JIG1", outcome.summary)
            self.assertIn("NL=", outcome.summary)
            self.assertTrue(outcome.csv_path.exists())
            self.assertTrue(outcome.json_path.exists())
            self.assertTrue(outcome.report_path.exists())

    def test_operator_filename_is_sanitized_and_never_overwrites(self) -> None:
        capture = BatchLogRecorder().feed(make_complete_batch())[0]
        self.assertTrue(suggested_capture_filename(capture).endswith("_p03_JIG1_batch007_complete.txt"))

        with tempfile.TemporaryDirectory() as temporary_dir:
            output_dir = Path(temporary_dir)
            first = save_capture(capture, output_dir, "P03:JIG1 lần 01.txt")
            second = save_capture(capture, output_dir, "P03:JIG1 lần 01.txt")
            self.assertEqual(first.name, "P03-JIG1 lần 01.txt")
            self.assertEqual(second.name, "P03-JIG1 lần 01_02.txt")


if __name__ == "__main__":
    unittest.main()
