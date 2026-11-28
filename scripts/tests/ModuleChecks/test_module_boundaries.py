"""Tests for scripts/check_module_boundaries.py, on synthetic fixtures and on the repository."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import check_module_boundaries as boundaries  # noqa: E402
import names  # noqa: E402

CORE, LIBRARY, NXNATIVE, APP = names.CORE, names.LIBRARY, names.NXNATIVE, names.APP


def source(role, file):
    return f"{names.path(role)}/{file}"


def write(root, relative, text):
    path = Path(root) / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class ModuleBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name
        self.names = (ROOT / names.SOURCE).read_text(encoding="utf-8")
        write(self.root, names.SOURCE, self.names)
        write(self.root, "Package.swift", (ROOT / "Package.swift").read_text(encoding="utf-8"))
        write(self.root, source("core", "Core.swift"), "import Foundation\n")
        write(self.root, source("library", "Library.swift"), f"import Foundation\nimport {CORE}\n")
        write(self.root, source("nxnative", "Adapter.swift"), f"import AppKit\nimport {LIBRARY}\n")
        # The app's entry point may import the engine (ADR 0002).
        self.entry = names.MODULES["mac"]["entry"]
        write(self.root, self.entry, f"import SwiftUI\nimport {NXNATIVE}\n")

    def declare(self, change):
        data = json.loads(self.names)
        change(data["modules"])
        write(self.root, names.SOURCE, json.dumps(data))

    def tearDown(self):
        self.directory.cleanup()

    def test_layered_fixture_has_no_violation(self):
        self.assertEqual(boundaries.check(self.root), [])

    def test_swift_module_missing_from_the_names_fails(self):
        self.declare(lambda modules: modules.pop("mac"))
        self.assertIn(f"{names.SOURCE}: missing Swift module {APP}", boundaries.check(self.root))

    def test_swift_module_only_in_the_names_fails(self):
        self.declare(lambda modules: modules.update(ghost={"name": "Ghost", "kind": "core", "layer": 0, "path": "ghost"}))
        self.assertIn(f"{names.SOURCE}: Ghost is not a Swift module in Package.swift", boundaries.check(self.root))

    def test_swift_imports_follow_the_layer_in_the_names(self):
        self.declare(lambda modules: modules["core"].update(layer=1))
        self.assertIn(f"{source('library', 'Library.swift')}: {LIBRARY} imports {CORE}, which is not below it",
                      boundaries.check(self.root))

    def test_oort_core_may_not_import_an_interface_framework(self):
        write(self.root, source("core", "Core.swift"), "import Foundation\nimport AppKit\n")
        violations = boundaries.check(self.root)
        self.assertTrue(any(f"{CORE} imports AppKit" in line for line in violations), violations)

    def test_a_lower_module_may_not_import_a_higher_one(self):
        write(self.root, source("library", "Library.swift"), f"import {APP}\n")
        violations = boundaries.check(self.root)
        self.assertTrue(any(f"{LIBRARY} imports {APP}" in line for line in violations), violations)

    def test_repository_respects_its_boundaries(self):
        self.assertEqual(boundaries.check(ROOT), [])

    def test_only_the_system_folder_reaches_the_trash(self):
        write(self.root, source("nxnative", "Cleanup.swift"),
              "import Foundation\nfunc f(_ u: URL) throws { try FileManager.default.trashItem(at: u, resultingItemURL: nil) }\n")
        violations = boundaries.check(self.root)
        self.assertIn(f"{source('nxnative', 'Cleanup.swift')}:2: reach the Trash through OortSystem.trash", violations)
        write(self.root, source("nxnative", "Cleanup.swift"), "import Foundation\nfunc f(_ u: URL) throws { try OortSystem.trash(u) }\n")
        write(self.root, source("library", "System/OortSystem.swift"), "let a = FileManager.SearchPathDirectory.trashDirectory\n")
        self.assertEqual(boundaries.check(self.root), [])

    def test_view_cannot_read_engine_storage(self):
        write(self.root, source("mac", "App.swift"), 'git(["rev-parse", "HEAD"])\ngit(["status",\n"--porcelain"])\n')
        self.assertEqual(len(boundaries.check(self.root)), 2)

    def test_view_cannot_restore_an_old_play_route_or_open_a_native_app(self):
        write(self.root, source("mac", "Views/Tile.swift"),
              "playRouter.play(game)\nrunningGames.resume(game)\nNSWorkspace.shared.openApplication(at: url)\n")
        self.assertEqual(len(boundaries.check(self.root)), 3)

    def test_only_the_engine_can_admit_an_adapter(self):
        write(self.root, source("mac", "App.swift"), "adapter.admit(target, profile: profile, gesture: gesture)\n")
        self.assertEqual(len(boundaries.check(self.root)), 1)


    def debt(self, *files):
        write(self.root, boundaries.ENGINE_DEBT, json.dumps({"files": list(files)}))

    def test_only_the_entry_point_imports_an_engine(self):
        write(self.root, source("mac", "Views/Screen.swift"), f"import SwiftUI\nimport {NXNATIVE}\n")
        violations = boundaries.check(self.root)
        self.assertIn(f"{source('mac', 'Views/Screen.swift')}: {APP} imports the engine {NXNATIVE}; "
                      "only the app's entry point may (ADR 0002)", violations)
        self.debt(source("mac", "Views/Screen.swift"))
        self.assertEqual(boundaries.check(self.root), [])

    def test_importing_one_declaration_of_the_engine_counts_as_importing_it(self):
        write(self.root, source("mac", "Views/Screen.swift"), f"import struct {NXNATIVE}.Thing\n")
        self.assertTrue(any("only the app's entry point may" in line for line in boundaries.check(self.root)))

    def test_a_debt_entry_that_no_longer_imports_the_engine_is_reported(self):
        self.debt(source("mac", "Views/Screen.swift"))
        write(self.root, source("mac", "Views/Screen.swift"), "import SwiftUI\n")
        self.assertIn(f"{boundaries.ENGINE_DEBT}: {source('mac', 'Views/Screen.swift')} no longer imports an engine; "
                      "remove the entry", boundaries.check(self.root))

    def test_the_engine_debt_only_shrinks_against_a_base(self):
        subprocess.run(["git", "init", "-q", self.root], check=True)
        self.debt()
        git = ["git", "-C", self.root, "-c", "user.name=Fixture", "-c", "user.email=fixture@users.noreply.github.com",
               "-c", "commit.gpgsign=false"]
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-qm", "base"], check=True)
        write(self.root, source("mac", "Views/Screen.swift"), f"import {NXNATIVE}\n")
        self.debt(source("mac", "Views/Screen.swift"))
        self.assertEqual(boundaries.check(self.root), [])
        self.assertIn(f"{boundaries.ENGINE_DEBT}: new entry {source('mac', 'Views/Screen.swift')}; the list only shrinks "
                      "(ADR 0002)", boundaries.check(self.root, "HEAD"))


if __name__ == "__main__":
    unittest.main()
