#!/usr/bin/env python3
"""Hardware-free regression for schema-v6 NL and polar plotting."""

from __future__ import annotations

import math
import tempfile
import unittest
from pathlib import Path

from analyze_motor_logs import load_sweeps
from motor_quality_polar import generate_nl_curve_chart, generate_polar_quality_chart
from stm32_uart_flasher import FlasherApp


Q16 = 65536
FULL_TURN_RAW = 65536


def _schema6_sweep(test_id: int, run_order: int) -> list[str]:
    lines = [
        "META,SchemaVersion=6,Firmware=test,BuildID=unit-test,JigID=JIG8,"
        f"MotorID=p03,TestID={test_id},SweepID={test_id},Direction=CW,"
        "OfficialMeasurementValid=1,TrackingValid=1,CapturedPoints=361,"
        "AnalysisPoints=360,StepRaw=0,RunRole=OFFICIAL,EligibleForStatistics=1"
    ]
    for index in range(361):
        target_relative = round(index * FULL_TURN_RAW / 360)
        target_abs = target_relative & 0xFFFF
        error_deg = 0.55 * math.sin(math.radians(2 * index))
        error_raw_q16 = round(error_deg * FULL_TURN_RAW * Q16 / 360.0)
        command_raw_q16 = target_relative * Q16
        mean_raw_q16 = command_raw_q16 - error_raw_q16
        angle_raw = round(mean_raw_q16 / Q16) & 0xFFFF
        angle_deg = angle_raw * 360.0 / FULL_TURN_RAW
        # Positional ErrorDeg is intentionally wrong: schema-v6 consumers
        # must use canonical ErrorRawQ16.
        lines.append(
            f"DATA,6,{test_id},{test_id},JIG8,p03,CW,{index},{target_abs},"
            f"{angle_raw},{angle_deg:.5f},99.00000,"
            f"CommandRawQ16={command_raw_q16},"
            f"MeanUnwrappedRawQ16={mean_raw_q16},ErrorRawQ16={error_raw_q16}"
        )
    lines.append(
        f"END,SchemaVersion=6,TestID={test_id},SweepID={test_id},Direction=CW,"
        "CapturedPoints=361,AnalysisPoints=360,Status=VALID"
    )
    return lines


class Schema6PlottingTests(unittest.TestCase):
    def test_schema6_without_role_is_not_treated_as_legacy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "truncated-meta.txt"
            lines = _schema6_sweep(1, 0)
            lines[0] = lines[0].replace(
                ",RunRole=OFFICIAL,EligibleForStatistics=1", ""
            )
            log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            self.assertIsNone(generate_nl_curve_chart(log_path))
            self.assertIsNone(generate_polar_quality_chart(log_path))

    def test_schema6_drives_live_nl_and_saved_charts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log_path = Path(directory) / "schema6-pilot.txt"
            log_path.write_text(
                "\n".join(_schema6_sweep(1, 1) + _schema6_sweep(2, 2)) + "\n",
                encoding="utf-8",
            )
            sweeps, warnings = load_sweeps(log_path)
            self.assertFalse(warnings)
            self.assertEqual(len(sweeps), 2)
            self.assertTrue(all(sweep.is_official_valid for sweep in sweeps))
            self.assertEqual(len(sweeps[0].points), 361)
            self.assertNotEqual(sweeps[0].points[90].error_deg, 99.0)
            live = FlasherApp._parse_plot_line(
                _schema6_sweep(3, 3)[1 + 45]
            )
            self.assertIsNotNone(live)
            self.assertEqual(live[0], 45)
            self.assertAlmostEqual(live[1], 0.55, places=4)

            nl_path = generate_nl_curve_chart(log_path)
            polar_path = generate_polar_quality_chart(log_path)
            self.assertIsNotNone(nl_path)
            self.assertIsNotNone(polar_path)
            self.assertGreater(nl_path.stat().st_size, 1000)
            self.assertGreater(polar_path.stat().st_size, 1000)


if __name__ == "__main__":
    unittest.main()
