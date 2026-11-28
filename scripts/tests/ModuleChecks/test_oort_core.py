"""Tests for scripts/check_oort_core.py (R3), on synthetic fixtures and on the repository."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import check_oort_core as core  # noqa: E402
import names  # noqa: E402

LIBRARY = names.path("library")
LIBRARY_TESTS = names.test_path("library")


def write(root, relative, text):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class PortableCoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        write(self.root, core.CORE_DEBT, json.dumps({"files": []}))
        write(self.root, f"{names.path('core')}/Core.swift", "import Foundation\n")

    def tearDown(self):
        self.directory.cleanup()

    def problems(self, relative, text):
        write(self.root, relative, text)
        return core.scan(self.root)[relative]

    def test_portable_file_passes(self):
        text = "import Foundation\nimport Synchronization\nimport Observation\nimport Crypto\n#if DEBUG\nlet a = 1\n#endif\n"
        self.assertEqual(self.problems(f"{LIBRARY}/Clean.swift", text), [])

    def test_an_apple_import_behind_if_is_still_seen(self):
        found = self.problems(f"{LIBRARY}/Hidden.swift", "import Foundation\n#if os(macOS)\nimport AppKit\n#endif\n")
        self.assertIn("imports AppKit", found)
        self.assertIn("branches on the system (os(macOS))", found)

    def test_the_c_library_belongs_to_the_system_folder(self):
        self.assertIn("imports Glibc", self.problems(f"{LIBRARY}/Files.swift", "import Glibc\n"))
        text = "#if canImport(Darwin)\nimport Darwin\n#elseif canImport(Glibc)\nimport Glibc\n#endif\nlet x = renamex_np\n"
        self.assertEqual(self.problems(f"{LIBRARY}/System/Rename.swift", text), [])

    def test_an_apple_only_name_is_refused_outside_the_system_folder(self):
        found = self.problems(f"{LIBRARY}/Store.swift", "import Foundation\nfinal class S: ObservableObject {}\n")
        self.assertIn("uses ObservableObject", found)
        found = self.problems(f"{LIBRARY}/Trash.swift", "import Foundation\nfunc f(_ u: URL) throws {\n"
                                                          "    try FileManager.default.trashItem(at: u, resultingItemURL: nil)\n}\n")
        self.assertIn("uses trashItem", found)
        found = self.problems(f"{LIBRARY}/Open.swift", "import Foundation\nlet fd = Darwin.open(\"/\", 0)\n")
        self.assertIn("uses Darwin.open", found)

    def test_an_apple_name_in_a_string_is_text_unless_interpolated(self):
        text = ('import Foundation\nlet a = "NSWorkspace.shared.open(" + "Published"\n'
                'let b = """\n    NSImage\n    """\nlet c = "\\"NSImage\\""\n')
        self.assertEqual(self.problems(f"{LIBRARY}/Message.swift", text), [])
        found = self.problems(f"{LIBRARY}/Hidden.swift", 'import Foundation\nlet a = "\\(NSImage())"\n')
        self.assertIn("uses NSImage", found)
        self.assertIn("uses NSImage", self.problems(f"{LIBRARY}/Call.swift", 'import Foundation\nlet a = NSImage("x")\n'))

    def test_the_core_is_a_folder_except_a_resource_it_copies_as_written(self):
        library = names.MODULES["library"]
        def targets(**library_target):
            return [{"name": names.CORE, "type": "regular", "path": names.path("core"), "dependencies": [],
                     "settings": [{"kind": {"swiftLanguageMode": {"_0": "6"}}}]},
                    {"name": library["name"], "type": "regular", "path": library["path"],
                     "dependencies": [{"byName": [names.CORE, None]}],
                     "settings": [{"kind": {"swiftLanguageMode": {"_0": "6"}}}], **library_target}]
        copy = [{"path": "Resources/Strings.xcstrings", "rule": {"copy": {}}}, {"path": "Resources", "rule": {"process": {}}}]
        self.assertEqual(core.check_targets(targets(exclude=["Resources/Strings.xcstrings"], resources=copy)), [])
        refused = f"Package.swift: {library['name']} lists files; the core is a folder"
        self.assertEqual(core.check_targets(targets(exclude=["Legacy/Old.swift"], resources=copy)), [refused])
        self.assertEqual(core.check_targets(targets(sources=["A.swift"])), [refused])

    def test_foundation_networking_is_the_only_conditional_import(self):
        text = "import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n"
        self.assertEqual(self.problems(f"{LIBRARY}/Net.swift", text), [])
        found = self.problems(f"{LIBRARY}/Other.swift", "#if canImport(UIKit)\nimport UIKit\n#endif\n")
        self.assertIn("imports UIKit", found)

    def test_a_core_test_may_use_xctest_but_not_appkit(self):
        self.assertEqual(self.problems(f"{LIBRARY_TESTS}/ATests.swift", "import XCTest\n@testable import OortLibrary\n"), [])
        self.assertIn("imports AppKit", self.problems(f"{LIBRARY_TESTS}/BTests.swift", "import XCTest\nimport AppKit\n"))

    def test_debt_holds_a_file_and_reports_a_stale_entry(self):
        relative = f"{LIBRARY}/Old.swift"
        write(self.root, relative, "import Combine\n")
        self.assertTrue(any("imports Combine" in line for line in core.check(self.root)))
        write(self.root, core.CORE_DEBT, json.dumps({"files": [relative]}))
        self.assertEqual(core.check(self.root), [])
        write(self.root, relative, "import Foundation\n")
        self.assertIn(f"{core.CORE_DEBT}: {relative} breaks no rule now; remove the entry", core.check(self.root))

    def test_debt_only_shrinks_against_a_base(self):
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "add", "-A"], cwd=self.root, check=True)
        subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "base"], cwd=self.root,
                       check=True)
        relative = f"{LIBRARY}/New.swift"
        write(self.root, relative, "import AppKit\n")
        write(self.root, core.CORE_DEBT, json.dumps({"files": [relative]}))
        self.assertIn(f"{core.CORE_DEBT}: new entry {relative}; the list only shrinks", core.check(self.root, "HEAD"))

    def test_repository_holds_its_core(self):
        self.assertEqual(core.check_manifest(ROOT) + core.check(ROOT), [])


if __name__ == "__main__":
    unittest.main()
