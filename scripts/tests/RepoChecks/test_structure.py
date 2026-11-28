import unittest

from support import ROOT, Fixture
import check_structure


class StructureTests(unittest.TestCase):
    def test_the_repository_matches_its_model(self):
        self.assertEqual(check_structure.check(ROOT), [])

    def test_a_declared_tree_passes(self):
        self.assertEqual(check_structure.check(Fixture(self).root), [])

    def test_an_undeclared_folder_fails(self):
        fixture = Fixture(self)
        fixture.track("notes/plan.txt", "x")
        self.assertIn("notes/: folder not declared in architecture/structure.c4", check_structure.check(fixture.root))

    def test_an_undeclared_second_level_folder_fails(self):
        fixture = Fixture(self)
        fixture.track("Sources/Extra/Extra.swift", "x")
        self.assertIn("Sources/Extra/: folder not declared in architecture/structure.c4",
                      check_structure.check(fixture.root))

    def test_an_undeclared_root_file_fails(self):
        fixture = Fixture(self)
        fixture.track("TODO.txt", "x")
        self.assertIn("TODO.txt: root file not declared in architecture/structure.c4", check_structure.check(fixture.root))

    def test_a_declared_folder_that_is_gone_fails(self):
        fixture = Fixture(self)
        fixture.track("architecture/structure.c4", (fixture.root / "architecture/structure.c4").read_text().replace(
            'core = folder "Core/" { metadata { path "Sources/Core" } }',
            'core = folder "Core/" { metadata { path "Sources/Core" } }\n'
            '      ghost = folder "Ghost/" { metadata { path "Sources/Ghost" } }'))
        self.assertIn("Sources/Ghost/: declared in architecture/structure.c4 but holds no tracked file",
                      check_structure.check(fixture.root))

    def test_single_quotes_and_urls_in_strings_are_read(self):
        fixture = Fixture(self)
        fixture.track("notes/plan.txt", "x")
        model = fixture.root / "architecture/structure.c4"
        fixture.track("architecture/structure.c4", model.read_text().replace(
            'scripts = folder "scripts/" { metadata { path "scripts" } }',
            'scripts = folder "scripts/" { metadata { path "scripts" } }\n'
            "    notes = folder 'notes/' { link https://example.org/a//b; metadata { path 'notes' } }"))
        self.assertEqual(check_structure.check(fixture.root), [])

    def test_a_commented_declaration_does_not_count(self):
        fixture = Fixture(self)
        fixture.track("notes/plan.txt", "x")
        fixture.track("architecture/extra.c4", '// metadata { path "notes" }\n')
        model = fixture.root / "architecture/structure.c4"
        fixture.track("architecture/structure.c4", model.read_text() + '\n/* metadata { path "notes" } */\n')
        self.assertIn("notes/: folder not declared in architecture/structure.c4", check_structure.check(fixture.root))


if __name__ == "__main__":
    unittest.main()


class RetiredPathTests(unittest.TestCase):
    """The CI may not name a path under a root folder the layout retired, even in a job that sleeps."""

    def fixture(self, workflow):
        fixture = Fixture(self)
        fixture.track("architecture/names.json",
                      '{"former": [{"modules": {"app": {"path": "Old/App", "tests": {"path": "OldTests/AppTests"}}}}]}\n')
        fixture.track(".github/workflows/ci.yml", workflow)
        return check_structure.check(fixture.root)

    def test_a_retired_root_in_a_workflow_fails(self):
        issues = self.fixture("      - run: python3 -m unittest discover -s OldTests/AndroidChecks\n")
        self.assertIn(".github/workflows/ci.yml:1: OldTests/AndroidChecks is under a folder the layout retired"
                      " (architecture/names.json, former)", issues)

    def test_a_folder_of_the_same_name_deeper_down_passes(self):
        issues = self.fixture("      - run: cd apps/OldTests/ocr && python3 -m unittest discover -s scripts/tests/Old\n")
        self.assertEqual([issue for issue in issues if "retired" in issue], [])

    def test_a_former_root_that_still_exists_passes(self):
        # The fixture still declares Sources/: a former path there is not retired.
        fixture = Fixture(self)
        fixture.track("architecture/names.json", '{"former": [{"modules": {"core": {"path": "Sources/Core"}}}]}\n')
        fixture.track(".github/workflows/ci.yml", "      - run: ls Sources/Core\n")
        self.assertEqual([issue for issue in check_structure.check(fixture.root) if "retired" in issue], [])
