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
