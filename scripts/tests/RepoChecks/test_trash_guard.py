"""Tests for scripts/trash_guard.py: a command that reaches the watched Trash fails the run."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

GUARD = Path(__file__).resolve().parents[2] / "trash_guard.py"


class TrashGuardTests(unittest.TestCase):
    def run_guard(self, trash, script):
        return subprocess.run([sys.executable, str(GUARD), "--trash", trash, "--", sys.executable, "-c", script],
                              capture_output=True, text=True)

    def test_a_new_entry_in_the_watched_trash_fails(self):
        with tempfile.TemporaryDirectory() as trash:
            Path(trash, "kept").write_text("already there")
            result = self.run_guard(trash, f"open({str(Path(trash, 'leak.app'))!r}, 'w').close()")
            self.assertEqual(result.returncode, 1)
            self.assertIn("gained 'leak.app'", result.stderr)
            self.assertTrue(Path(trash, "kept").exists(), "the guard never touches what was there")

    def test_the_command_gets_a_trash_of_its_own(self):
        with tempfile.TemporaryDirectory() as trash:
            script = "import os, pathlib; own = os.environ['OORT_TRASH']; pathlib.Path(own, 'x').write_text('x')"
            result = self.run_guard(trash, script)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(list(Path(trash).iterdir()), [])

    def test_the_command_status_is_kept(self):
        with tempfile.TemporaryDirectory() as trash:
            self.assertEqual(self.run_guard(trash, "raise SystemExit(3)").returncode, 3)


if __name__ == "__main__":
    unittest.main()
