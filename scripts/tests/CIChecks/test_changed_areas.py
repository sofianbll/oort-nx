"""Tests for scripts/ci_changed_areas.py: which CI areas a change turns on."""

import io
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import ci_changed_areas as areas  # noqa: E402

ALL_FOLDERS = ("desktop", "mobile", "android")


def checkout(*folders):
    """A temporary checkout that contains the given area folders."""
    directory = tempfile.TemporaryDirectory()
    for folder in folders:
        (Path(directory.name) / folder).mkdir()
    return directory


class ChangedAreasTests(unittest.TestCase):
    def test_docs_only_turns_no_area_on(self):
        with checkout(*ALL_FOLDERS) as root:
            result = areas.decide(["docs/working-on-it/architecture-map.md", "CONTRIBUTING.md"], root)
        self.assertEqual(set(result.values()), {False})

    def test_core_change_turns_on_swift_and_both_ports_but_not_android(self):
        with checkout(*ALL_FOLDERS) as root:
            result = areas.decide(["core/OortCore/Catalog.swift"], root)
        self.assertEqual(result, {"swift": True, "desktop": True, "mobile": True, "android": False})

    def test_workflow_change_turns_every_area_on(self):
        with checkout(*ALL_FOLDERS) as root:
            result = areas.decide([".github/workflows/ci.yml"], root)
        self.assertEqual(set(result.values()), {True})

    def test_shared_design_sources_reach_the_ports_that_read_them(self):
        cases = {
            "design/oort.tokens.json": {"desktop", "android"},
            "design/Selene/palettes.json": {"swift", "desktop"},
            "scripts/generate_oort_tokens.py": {"swift", "desktop"},
            "design/Icons/AppIcon.icon/Assets/glyph.svg": {"swift", "android"},
            # Folders that came from Resources/ reach the Mac only, as they did there.
            "design/SoundPacks/oort.oortsound/back.wav": {"swift"},
            "design/Brands/Credits/arcane.png": {"swift"},
        }
        with checkout(*ALL_FOLDERS) as root:
            for path, expected in cases.items():
                with self.subTest(path=path):
                    result = areas.decide([path], root)
                    self.assertEqual({area for area, on in result.items() if on}, expected)

    def test_missing_folder_keeps_its_area_off_even_when_paths_match(self):
        # On main, desktop/ does not exist yet: a core change must not start the Windows jobs.
        with checkout("mobile") as root:
            result = areas.decide(["core/OortCore/Catalog.swift"], root)
        self.assertFalse(result["desktop"])
        self.assertTrue(result["mobile"])

    def test_all_flag_and_empty_input(self):
        with checkout("desktop") as root:
            # --all forces the areas whose folder exists; mobile and android have no folder here.
            self.assertEqual(
                areas.decide([], root, everything=True),
                {"swift": True, "desktop": True, "mobile": False, "android": False},
            )
            self.assertFalse(any(areas.decide([], root).values()))

    def test_main_entry_point_prints_one_line_per_area(self):
        output = io.StringIO()
        with checkout("android") as root:
            original = sys.stdout
            sys.stdout = output
            try:
                areas.main(["--root", root], stdin=io.StringIO("android/app/build.gradle.kts\n"))
            finally:
                sys.stdout = original
        self.assertEqual(
            output.getvalue().splitlines(),
            ["swift=false", "desktop=false", "mobile=false", "android=true"],
        )


if __name__ == "__main__":
    unittest.main()
