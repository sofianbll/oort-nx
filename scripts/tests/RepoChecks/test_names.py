"""Red examples of scripts/check_names.py: a name written by hand, a frozen value that changed."""
import json
import unittest

from support import Fixture

import check_names

NAMES = {
    "package": "Pkg",
    "modules": {
        "core": {"name": "CoreMod", "path": "core/CoreMod", "tests": {"name": "CoreModTests", "path": "core/Tests/CoreModTests"}},
        "library": {"name": "LibMod", "path": "core/LibMod"},
    },
    "frozen": {"values": {"identifier = \"com.example.app\"": ["core/CoreMod/App.swift"]}},
}


class NamesTests(unittest.TestCase):
    def setUp(self):
        self.fixture = Fixture(self)
        self.fixture.track("architecture/names.json", json.dumps(NAMES))
        self.fixture.track("core/CoreMod/App.swift", 'let identifier = "com.example.app"\n')

    def findings(self):
        return check_names.check(self.fixture.root)

    def test_the_repository_passes(self):
        self.assertEqual(check_names.check(check_names.ROOT), [])

    def test_a_name_written_by_hand_in_a_script_fails(self):
        self.fixture.track("scripts/build.sh", "swift build --product LibMod\n")
        self.assertEqual(self.findings(), ["scripts/build.sh:1: LibMod is written by hand; read scripts/names.py or "
                                           "generate it from architecture/names.json"])

    def test_the_resource_bundle_name_counts_as_a_name(self):
        self.fixture.track("scripts/copy.py", 'BUNDLE = "Pkg_LibMod.bundle"\n')
        self.assertEqual(len(self.findings()), 1)

    def test_imports_folders_and_generated_blocks_are_allowed(self):
        self.fixture.track("scripts/probe.py", 'HOST = "import CoreMod\\n@testable import LibMod"\n'
                                               'SOURCE = "core/CoreMod/App.swift"\nTITLE = "LibMod/"\n')
        self.fixture.track("Package.swift", "// BEGIN GENERATED NAMES (x)\nlet core = \"CoreMod\"\n// END GENERATED NAMES\n")
        self.assertEqual(self.findings(), [])

    def test_docs_and_sources_may_name_a_module(self):
        self.fixture.track("docs/modules.md", "LibMod holds the library.\n")
        self.assertEqual(self.findings(), [])

    def test_a_frozen_value_that_changed_fails(self):
        self.fixture.track("core/CoreMod/App.swift", 'let identifier = "com.example.other"\n')
        self.assertEqual(self.findings(), ["core/CoreMod/App.swift: frozen value 'identifier = \"com.example.app\"' is "
                                           "missing; players' data depend on it, never change it"])


if __name__ == "__main__":
    unittest.main()
