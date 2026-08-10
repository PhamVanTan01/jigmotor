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
    analyze_motor_response_timing,
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
    def test_v58_response_timing_separates_reached_from_stop_latency(self) -> None:
        prefix = (
            "SchemaVersion=1,TestID=11,SweepID=12,JigID=JIG8,MotorID=p08,"
            "Direction=CW,Official=0,ClockHz=168000000,TimingValid=1,"
        )
        lines = [
            "SWEEP_POINT_TIMING," + prefix
            + "Point=0,HasCommand=0,NominalTargetRaw=0,NominalStepCommandRaw=NA,"
            "InitialGapRaw=NA,FinalGapRaw=NA,CreepIterations=0,"
            "CreepCorrectionCommandRaw=0,SettlePollCount=8,RampCycles=NA,"
            "InitialSettleCycles=NA,CreepCycles=NA,CommandToStopCycles=NA,"
            "ReachedDeadband=0,TimeToDeadbandCycles=NA,LegacyCaptureCycles=168000,"
            "ShadowCaptureCycles=168000,CommandToDataFrozenCycles=NA,"
            "CommandToAllCaptureDoneCycles=NA,CreepResult=NOT_RUN",
            "SWEEP_POINT_TIMING," + prefix
            + "Point=1,HasCommand=1,NominalTargetRaw=182,NominalStepCommandRaw=182,"
            "InitialGapRaw=100,FinalGapRaw=2,CreepIterations=10,"
            "CreepCorrectionCommandRaw=160,SettlePollCount=8,RampCycles=6552000,"
            "InitialSettleCycles=1512000,CreepCycles=13440000,"
            "CommandToStopCycles=21504000,ReachedDeadband=1,"
            "TimeToDeadbandCycles=21504000,LegacyCaptureCycles=168000,"
            "ShadowCaptureCycles=168000,CommandToDataFrozenCycles=21672000,"
            "CommandToAllCaptureDoneCycles=21840000,CreepResult=OK",
            "SWEEP_POINT_TIMING," + prefix
            + "Point=2,HasCommand=1,NominalTargetRaw=364,NominalStepCommandRaw=182,"
            "InitialGapRaw=180,FinalGapRaw=40,CreepIterations=20,"
            "CreepCorrectionCommandRaw=320,SettlePollCount=9,RampCycles=6552000,"
            "InitialSettleCycles=1680000,CreepCycles=26880000,"
            "CommandToStopCycles=35112000,ReachedDeadband=0,"
            "TimeToDeadbandCycles=NA,LegacyCaptureCycles=168000,"
            "ShadowCaptureCycles=168000,CommandToDataFrozenCycles=35280000,"
            "CommandToAllCaptureDoneCycles=35448000,CreepResult=BUDGET_EXCEEDED",
            "SWEEP_POINT_TIMING_END,SchemaVersion=1,TestID=11,SweepID=12,"
            "JigID=JIG8,MotorID=p08,Direction=CW,Official=0,ExpectedPoints=3,"
            "EmittedPoints=3,ValidPoints=3,CommandPoints=2,ReachedDeadbandPoints=1,Complete=1",
        ]
        analysis = analyze_motor_response_timing("\n".join(lines))
        self.assertTrue(analysis.complete)
        self.assertEqual(len(analysis.rows), 3)
        self.assertIn("Response=1/2", analysis.summary_fragment or "")
        reached = analysis.rows[1]
        stopped = analysis.rows[2]
        self.assertAlmostEqual(reached["TimeToDeadbandMs"], 128.0)
        self.assertAlmostEqual(reached["CreepResponseEfficiencyPermille"], 612.5)
        self.assertAlmostEqual(reached["NominalStepTrackingPermille"], 1000.0 * 180 / 182)
        self.assertIsNone(stopped["TimeToDeadbandMs"])
        self.assertAlmostEqual(stopped["CommandToStopMs"], 209.0)
        self.assertTrue(any("StopLatency(not-reached)" in line for line in analysis.report_lines))

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

    def test_high_volume_capture_is_byte_complete_across_small_chunks(self) -> None:
        payload = make_complete_batch()
        terminal = (
            b"BATCH,BatchID=7,Status=COMPLETE,PreconditionCount=1,"
            b"RunCount=2,TotalCycleCount=3\r\n"
        )
        telemetry = b"".join(
            (
                f"SWEEP_CREEP_STEP,SchemaVersion=3,TestID=2,SweepID=2,"
                f"Point=308,StepOrder={index},GapBeforeRaw=32,GapAfterRaw=31\r\n"
            ).encode("ascii")
            for index in range(1, 12001)
        )
        payload = payload.replace(terminal, telemetry + terminal)
        recorder = BatchLogRecorder()
        captures = []
        chunk_sizes = (1, 2, 3, 5, 7, 11, 127, 4096, 17)
        offset = 0
        chunk_index = 0
        while offset < len(payload):
            size = chunk_sizes[chunk_index % len(chunk_sizes)]
            captures.extend(recorder.feed(payload[offset : offset + size]))
            offset += size
            chunk_index += 1

        self.assertGreater(len(payload), 1_000_000)
        self.assertEqual(len(captures), 1)
        self.assertEqual(captures[0].text, payload.decode("utf-8").replace("\r\n", "\n"))

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

    def test_saved_v58_batch_exports_response_csv_and_report(self) -> None:
        payload = make_complete_batch().decode("utf-8")
        for test_id in (1, 2, 3):
            timing = [
                "SWEEP_POINT_TIMING,SchemaVersion=1,"
                f"TestID={test_id},SweepID={test_id},JigID=JIG1,MotorID=p03,"
                "Direction=CW,Point=0,Official=0,ClockHz=168000000,HasCommand=0,"
                "TimingValid=1,NominalTargetRaw=0,NominalStepCommandRaw=NA,"
                "InitialGapRaw=NA,FinalGapRaw=NA,CreepIterations=0,"
                "CreepCorrectionCommandRaw=0,SettlePollCount=8,RampCycles=NA,"
                "InitialSettleCycles=NA,CreepCycles=NA,CommandToStopCycles=NA,"
                "ReachedDeadband=0,TimeToDeadbandCycles=NA,LegacyCaptureCycles=168000,"
                "ShadowCaptureCycles=168000,CommandToDataFrozenCycles=NA,"
                "CommandToAllCaptureDoneCycles=NA,CreepResult=NOT_RUN",
                "SWEEP_POINT_TIMING,SchemaVersion=1,"
                f"TestID={test_id},SweepID={test_id},JigID=JIG1,MotorID=p03,"
                "Direction=CW,Point=1,Official=0,ClockHz=168000000,HasCommand=1,"
                "TimingValid=1,NominalTargetRaw=182,NominalStepCommandRaw=182,"
                "InitialGapRaw=100,FinalGapRaw=2,CreepIterations=10,"
                "CreepCorrectionCommandRaw=160,SettlePollCount=8,RampCycles=6552000,"
                "InitialSettleCycles=1512000,CreepCycles=13440000,"
                "CommandToStopCycles=21504000,ReachedDeadband=1,"
                "TimeToDeadbandCycles=21504000,LegacyCaptureCycles=168000,"
                "ShadowCaptureCycles=168000,CommandToDataFrozenCycles=21672000,"
                "CommandToAllCaptureDoneCycles=21840000,CreepResult=OK",
                "SWEEP_POINT_TIMING_END,SchemaVersion=1,"
                f"TestID={test_id},SweepID={test_id},JigID=JIG1,MotorID=p03,"
                "Direction=CW,Official=0,ExpectedPoints=2,EmittedPoints=2,"
                "ValidPoints=2,CommandPoints=1,ReachedDeadbandPoints=1,Complete=1",
            ]
            marker = f"END,SchemaVersion=5,TestID={test_id},SweepID={test_id},"
            payload = payload.replace(marker, "\r\n".join(timing) + "\r\n" + marker, 1)

        capture = BatchLogRecorder().feed(payload.encode("utf-8"))[0]
        with tempfile.TemporaryDirectory() as temporary_dir:
            log_path = save_capture(capture, Path(temporary_dir))
            outcome = analyze_saved_log(
                log_path,
                expected_official_runs=capture.expected_official_runs,
                terminal_status=capture.terminal_status,
            )
            self.assertTrue(outcome.passed, outcome.summary)
            self.assertTrue(outcome.capture_integrity_valid, outcome.summary)
            self.assertEqual(outcome.response_timing_rows, 6)
            self.assertIsNotNone(outcome.response_csv_path)
            assert outcome.response_csv_path is not None
            self.assertTrue(outcome.response_csv_path.exists())
            self.assertIn("Response=3/3", outcome.summary)
            self.assertTrue(outcome.summary.startswith("DIAGNOSTIC PASS"))
            report_text = outcome.report_path.read_text(encoding="utf-8")
            self.assertIn("AnalysisMode=RESPONSE_TIMING_DIAGNOSTIC", report_text)
            self.assertIn("MOTOR RESPONSE TIMING (V5.8)", report_text)
            self.assertIn("TimeToDeadband(reached-only)", report_text)

    def test_missing_data_is_reported_as_capture_invalid(self) -> None:
        payload = make_complete_batch().decode("utf-8")
        dropped_line = next(
            line for line in payload.splitlines()
            if line.startswith("DATA,") and line.split(",")[7] == "120"
        )
        payload = payload.replace(dropped_line + "\r\n", "", 1)
        capture = BatchLogRecorder().feed(payload.encode("utf-8"))[0]

        with tempfile.TemporaryDirectory() as temporary_dir:
            log_path = save_capture(capture, Path(temporary_dir))
            outcome = analyze_saved_log(
                log_path,
                expected_official_runs=capture.expected_official_runs,
                terminal_status=capture.terminal_status,
            )
            self.assertFalse(outcome.passed)
            self.assertFalse(outcome.capture_integrity_valid)
            self.assertTrue(outcome.summary.startswith("CAPTURE INVALID"))
            self.assertIn("AutoVerdict=CAPTURE INVALID", outcome.report_path.read_text())

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
