import json
import subprocess
import unittest

from support import ROOT, Fixture
import check_docs


class DocsTests(unittest.TestCase):
    def test_the_repository_docs_pass(self):
        self.assertEqual(check_docs.check(ROOT), [])

    def test_a_clean_fixture_passes(self):
        fixture = Fixture(self)
        fixture.track("docs/guide.md", "See [start](guides/start.md#top) and [the site](https://example.org).\n")
        self.assertEqual(check_docs.check(fixture.root), [])

    def test_documentation_outside_its_folders_fails(self):
        fixture = Fixture(self)
        fixture.track("Sources/Core/NOTES.md", "Notes.\n")
        self.assertIn('Sources/Core/NOTES.md: documentation outside the folders architecture/structure.c4 '
                      'marks markdown "yes"', check_docs.check(fixture.root))

    def test_a_dead_relative_link_fails(self):
        fixture = Fixture(self)
        fixture.track("docs/guide.md", "See [gone](../scripts/gone.py) and `[code](not/a/link.md)`.\n")
        issues = check_docs.check(fixture.root)
        self.assertIn("docs/guide.md: link to ../scripts/gone.py does not resolve to a tracked path", issues)
        self.assertEqual(len(issues), 1, "links inside code spans are not links")

    def test_a_link_above_the_repository_fails(self):
        fixture = Fixture(self)
        fixture.track("README.md", "[outside](../../etc/passwd)\n")
        self.assertIn("README.md: link to ../../etc/passwd does not resolve to a tracked path",
                      check_docs.check(fixture.root))

    def test_a_private_marker_fails(self):
        fixture = Fixture(self)
        fixture.track("docs/guide.md", "Built in /Users/someone/project.\n")
        self.assertIn("docs/guide.md: private marker '/Users/'; remove it (scripts/private-markers.json records only "
                      "old ones)", check_docs.check(fixture.root))

    def test_a_recorded_marker_passes_and_a_stale_record_fails(self):
        fixture = Fixture(self)
        fixture.track("docs/guide.md", "Built in /Users/someone/project.\n")
        fixture.track("scripts/private-markers.json",
                      json.dumps({"markers": ["/Users/"], "allowed": {"docs/guide.md": ["/Users/"]}}))
        self.assertEqual(check_docs.check(fixture.root), [])
        fixture.track("docs/guide.md", "Built in a project.\n")
        self.assertIn("scripts/private-markers.json: docs/guide.md no longer holds '/Users/'; remove the allowance",
                      check_docs.check(fixture.root))

    def test_a_base_without_the_list_starts_it(self):
        fixture = Fixture(self)
        (fixture.root / "scripts/private-markers.json").unlink()
        subprocess.run(["git", "rm", "-q", "--cached", "scripts/private-markers.json"], cwd=fixture.root, check=True)
        base = fixture.commit()
        fixture.track("docs/guide.md", "Built in /Users/someone/project.\n")
        fixture.track("scripts/private-markers.json",
                      json.dumps({"markers": ["/Users/"], "allowed": {"docs/guide.md": ["/Users/"]}}))
        self.assertEqual(check_docs.check(fixture.root, base), [])

    def test_an_unknown_base_is_an_error(self):
        with self.assertRaises(ValueError):
            check_docs.check(Fixture(self).root, "no-such-ref")

    def test_links_inside_long_fences_are_not_links(self):
        fixture = Fixture(self)
        fixture.track("docs/guide.md", "````md\n[example](missing.md)\n````\n")
        self.assertEqual(check_docs.check(fixture.root), [])

    def test_the_allowances_only_shrink(self):
        fixture = Fixture(self)
        base = fixture.commit()
        fixture.track("docs/guide.md", "Built in /Users/someone/project.\n")
        fixture.track("scripts/private-markers.json",
                      json.dumps({"markers": ["/Users/"], "allowed": {"docs/guide.md": ["/Users/"]}}))
        self.assertIn("scripts/private-markers.json: new allowance docs/guide.md '/Users/'; the list only shrinks",
                      check_docs.check(fixture.root, base))


if __name__ == "__main__":
    unittest.main()
