"""The original probe glob is partitioned exactly once, and failures reach CI."""

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "Tests/CatalogAppChecks"))

import ci_catalog_checks as checks
from run_cloud_screens import build_probe


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

    def test_probe_build_does_not_mount_tools_in_its_fixture_home(self):
        fixture = {"HOME": "/fixture", "CFFIXED_USER_HOME": "/fixture", "OORT_PROBE_BUILD_HOME": "/runner"}
        with patch("run_cloud_screens.subprocess.run") as build, \
             patch("run_cloud_screens.subprocess.check_output", return_value="/products\n") as location:
            self.assertEqual(build_probe("/package", product="ProfileScreenProbe", jobs=2, environment=fixture),
                             Path("/products/ProfileScreenProbe"))
        for call in (build.call_args, location.call_args):
            self.assertEqual(call.kwargs["env"]["HOME"], "/runner")
            self.assertEqual(call.kwargs["env"]["CFFIXED_USER_HOME"], "/runner")
        self.assertEqual(fixture["HOME"], "/fixture")

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

    def test_probe_build_starts_from_the_sdk_modules_and_fills_an_empty_seed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            seed, package = root / "seed", root / "package"
            built = package / ".build/out/SDKExplicitPrecompiledModules"

            def compile_modules(*_, **__):
                built.mkdir(parents=True, exist_ok=True)
                (built / "SwiftUI.pcm").write_text("built")

            env = {"OORT_PROBE_MODULE_SEED": str(seed)}
            with patch("run_cloud_screens.subprocess.run", side_effect=compile_modules), \
                 patch("run_cloud_screens.subprocess.check_output", return_value="/products\n"):
                build_probe(package, environment=env)
            self.assertEqual((seed / "SDKExplicitPrecompiledModules/SwiftUI.pcm").read_text(), "built")

            (seed / "SDKExplicitPrecompiledModules/SwiftUI.pcm").write_text("cached")
            other = root / "other"
            seen = []
            with patch("run_cloud_screens.subprocess.run",
                       side_effect=lambda *_, **__: seen.append(
                           (other / ".build/out/SDKExplicitPrecompiledModules/SwiftUI.pcm").read_text())), \
                 patch("run_cloud_screens.subprocess.check_output", return_value="/products\n"):
                build_probe(other, environment=env)
            self.assertEqual(seen, ["cached"])

    def test_probe_build_without_a_seed_leaves_the_package_alone(self):
        with tempfile.TemporaryDirectory() as tmp:
            package = Path(tmp) / "package"
            with patch("run_cloud_screens.subprocess.run"), \
                 patch("run_cloud_screens.subprocess.check_output", return_value="/products\n"):
                build_probe(package, environment={})
            self.assertFalse(package.exists())
