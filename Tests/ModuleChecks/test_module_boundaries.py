"""Tests for scripts/check_module_boundaries.py, on synthetic fixtures and on the repository."""

from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import check_module_boundaries as boundaries  # noqa: E402


def write(root, relative, text):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ModuleBoundaryTests(unittest.TestCase):
    def setUp(self):
        # Synthetic fixtures use an empty baseline: the real one lists files that the fixture lacks.
        self.saved_baseline = dict(boundaries.UI_BASELINE)
        boundaries.UI_BASELINE.clear()
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name
        write(self.root, "Sources/OortCore/Core.swift", "import Foundation\n")
        write(self.root, "Sources/NXLibraryCore/Library.swift", "import Foundation\nimport OortCore\n")
        write(self.root, "Sources/ArcanePorting/Adapter.swift", "import AppKit\nimport NXLibraryCore\n")
        write(self.root, "Sources/NXLibrary/App.swift", "import SwiftUI\nimport ArcanePorting\n")

    def tearDown(self):
        self.directory.cleanup()
        boundaries.UI_BASELINE.clear()
        boundaries.UI_BASELINE.update(self.saved_baseline)

    def test_layered_fixture_has_no_violation(self):
        self.assertEqual(boundaries.check(self.root), [])

    def test_oort_core_may_not_import_an_interface_framework(self):
        write(self.root, "Sources/OortCore/Core.swift", "import Foundation\nimport AppKit\n")
        violations = boundaries.check(self.root)
        self.assertTrue(any("OortCore imports AppKit" in line for line in violations), violations)

    def test_a_lower_module_may_not_import_a_higher_one(self):
        write(self.root, "Sources/NXLibraryCore/Library.swift", "import NXLibrary\n")
        violations = boundaries.check(self.root)
        self.assertTrue(any("NXLibraryCore imports NXLibrary" in line for line in violations), violations)

    def test_core_interface_import_needs_a_baseline_entry(self):
        write(self.root, "Sources/NXLibraryCore/Views/Panel.swift", "import SwiftUI\n")
        violations = boundaries.check(self.root)
        self.assertTrue(any("NXLibraryCore imports the interface framework SwiftUI" in line for line in violations))

    def test_baseline_entry_passes_and_stale_entry_is_reported(self):
        boundaries.UI_BASELINE["Sources/NXLibraryCore/Library.swift"] = {"AppKit"}
        violations = boundaries.check(self.root)
        self.assertTrue(any("baseline lists AppKit" in line for line in violations), violations)
        write(self.root, "Sources/NXLibraryCore/Library.swift", "import AppKit\n")
        self.assertEqual(boundaries.check(self.root), [])

    def test_repository_respects_its_boundaries(self):
        boundaries.UI_BASELINE.update(self.saved_baseline)
        self.assertEqual(boundaries.check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
