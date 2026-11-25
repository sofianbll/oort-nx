import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_guides", ROOT / "scripts/check_guides.py")
guides = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guides)


class CheckGuidesTests(unittest.TestCase):
    """The published guides pass, and each rule refuses what it must."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "docs/guides", self.root / "docs/guides")
        shutil.copyfile(ROOT / "docs/features.json", self.root / "docs/features.json")
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        self.page = self.root / "docs/guides/fr/windows/play.md"

    def tearDown(self):
        self.temp.cleanup()

    def errors(self):
        return guides.check(self.root)[0].errors

    def refuses(self, words):
        found = self.errors()
        self.assertTrue(any(words in line for line in found), found)

    def edit(self, old, new, page=None):
        page = page or self.page
        text = page.read_text()
        self.assertIn(old, text)
        page.write_text(text.replace(old, new, 1))

    def test_published_guides_pass(self):
        self.assertEqual(self.errors(), [])

    def test_a_language_is_missing(self):
        self.page.unlink()
        self.refuses("exists in one language only")

    def test_a_system_is_forgotten(self):
        for lang in guides.LANGS:
            (self.root / f"docs/guides/{lang}/linux/saves.md").unlink()
        self.refuses("linux has no saves guide")

    def test_a_picture_is_missing_or_heavy_or_not_webp(self):
        picture = next((self.root / "docs/guides/media/windows").glob("*.webp"))
        picture.write_bytes(b"x" * 200_001)
        self.refuses("not a WebP file")
        self.refuses("over 200000")
        picture.unlink()
        self.refuses("does not exist")

    def test_an_old_version(self):
        self.edit("version: 0.1.0-alpha.1", "version: 0.0.9")
        self.refuses("check the guide again")

    def test_a_promise(self):
        self.edit("Choisis **Jouer**.", "Bientôt, choisis **Jouer**.")
        self.refuses("a promise")

    def test_vous(self):
        self.edit("Choisis **Jouer**.", "Choisissez votre jeu.")
        self.refuses("says “tu”")

    def test_a_dead_link_and_plain_http(self):
        self.edit("Choisis **Jouer**.", "Voir [ici](absent.md) et [là](http://example.com).")
        self.refuses("leads nowhere")
        self.refuses("https only")

    def test_a_step_without_proof(self):
        self.edit("<!-- step play played", "<!-- step play tested")
        self.refuses("is not one of")

    def test_a_feature_forgets_a_system_or_its_proof(self):
        path = self.root / "docs/features.json"
        matrix = json.loads(path.read_text())
        del matrix["features"][0]["systems"]["ios"]
        matrix["features"][0]["systems"]["mac"]["proof"] = []
        path.write_text(json.dumps(matrix))
        self.refuses("a system is forgotten: ios")
        self.refuses("no proof")


if __name__ == "__main__":
    unittest.main()
