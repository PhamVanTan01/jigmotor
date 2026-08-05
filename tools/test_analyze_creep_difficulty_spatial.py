import tempfile
import unittest
from pathlib import Path

import analyze_creep_difficulty_spatial as spatial


def meta(test_id: int, role: str, eligible: int) -> str:
    return (
        f"META,TestID={test_id},SweepID={test_id},RunRole={role},"
        f"EligibleForStatistics={eligible},BuildID=TEST,JigID=JIGX\n")


def motion(test_id: int, point: int, error: int) -> str:
    return (
        f"MOTION,TestID={test_id},SweepID={test_id},Point={point},"
        f"PositionErrorRaw={error}\n")


def end(test_id: int) -> str:
    return f"END,TestID={test_id},SweepID={test_id},Status=VALID\n"


class SpatialCreepAnalysisTests(unittest.TestCase):
    def test_shadow_records_do_not_override_official_records(self):
        self.assertIsNone(spatial.extract_record(
            "SHADOW_META,TestID=1,SweepID=1", "META"))
        self.assertIsNone(spatial.extract_record(
            "SHADOW_END,TestID=1,SweepID=1", "END"))

    def test_concatenated_motion_record_is_recovered(self):
        record = spatial.extract_record(
            "DATA,5,6,6,JIG7,UNKNOWN,CW,280,10"
            "MOTION,TestID=6,SweepID=6,Point=293,PositionErrorRaw=-296",
            "MOTION",
        )
        self.assertIsNotNone(record)
        self.assertEqual(record["Point"], "293")
        self.assertEqual(record["PositionErrorRaw"], "-296")

    def test_primary_excludes_incomplete_official_sweep(self):
        content = meta(1, "PRECONDITION", 0)
        for point, error in enumerate((99, 99, 99)):
            content += motion(1, point, error)
        content += end(1)

        content += meta(2, "OFFICIAL", 1)
        for point, error in enumerate((10, -20, 30)):
            content += motion(2, point, error)
        content += end(2)

        content += meta(3, "OFFICIAL", 1)
        for point, error in enumerate((30, -40, 50)):
            content += motion(3, point, error)
        content += end(3)

        content += meta(4, "OFFICIAL", 1)
        content += motion(4, 0, 100)
        content += motion(4, 2, 100)
        content += end(4)

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "remount01.txt"
            path.write_text(content, encoding="utf-8")
            curve = spatial.build_curve(spatial.load_log(path, 3), 3)

        self.assertEqual([s.test_id for s in curve.complete_sweeps], [2, 3])
        self.assertEqual(curve.mean_abs_raw, [20.0, 30.0, 40.0])
        self.assertEqual(curve.sensitivity_mean_abs_raw,
                         [140.0 / 3.0, 30.0, 60.0])
        self.assertEqual(curve.sensitivity_counts, [3, 2, 3])


if __name__ == "__main__":
    unittest.main()
