"""repo_model.renamed: debt lists read from a base follow files that moved since."""
import subprocess
import unittest

from support import Fixture

import repo_model


class RenamedTests(unittest.TestCase):
    def test_a_moved_file_maps_to_its_new_path_and_nothing_else_does(self):
        fixture = Fixture(self)
        base = fixture.commit()
        (fixture.root / "core").mkdir()
        subprocess.run(["git", "mv", "Sources/Core/Core.swift", "core/Core.swift"], cwd=fixture.root, check=True)
        fixture.track("README.md", "# Changed\n")
        self.assertEqual(repo_model.renamed(fixture.root, base), {"Sources/Core/Core.swift": "core/Core.swift"})


if __name__ == "__main__":
    unittest.main()
