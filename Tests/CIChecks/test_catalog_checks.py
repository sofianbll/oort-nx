"""The original probe glob is partitioned exactly once, and failures reach CI."""

from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import ci_catalog_checks as checks


class CatalogChecksTests(unittest.TestCase):
    def test_every_probe_runs_once_and_cold_builds_are_bounded(self):
        paths = sorted((ROOT / "Tests/CatalogAppChecks").glob("run_*.py"))
        debug, standalone = checks.partition(paths)
        self.assertCountEqual(debug + [path for group in standalone for path in group], paths)
        self.assertTrue(all(1 <= len(group) <= 2 for group in standalone))
        self.assertIn(ROOT / "Tests/CatalogAppChecks/run_catalog_removal.py", standalone[0])
        self.assertIn(ROOT / "Tests/CatalogAppChecks/run_achievement_scroll.py", debug)
        for name in ("cloud_assistant", "cloud_personal_update", "cloud_reference", "cloud_screens"):
            with self.subTest(probe=name):
                self.assertIn(ROOT / f"Tests/CatalogAppChecks/run_{name}.py", sum(standalone, []))

    def test_failing_probe_does_not_hide_the_next_result(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            failed = root / "run_fail.py"
            failed.write_text("raise SystemExit(7)\n")
            executed = root / "executed"
            passed = root / "run_pass.py"
            passed.write_text(f"from pathlib import Path\nPath({str(executed)!r}).touch()\n")
            # Exercise the same sequence runner without building the application.
            self.assertEqual(checks.run([failed, passed], root), 1)
            self.assertTrue(executed.exists())
