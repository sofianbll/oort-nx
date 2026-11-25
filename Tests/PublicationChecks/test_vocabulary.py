import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check_vocabulary.py"
SPEC = importlib.util.spec_from_file_location("check_vocabulary", SCRIPT)
check = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check)

WORDS = {
    "avoid": {"fr": [{"id": "gamepad", "pattern": r"\bgamepad\b", "use": "manette"}]},
    "states": [{"id": "installed", "en": "Installed", "fr": "Installé", "icon": "play", "action": "action.play"}],
    "terms": [{"id": "action.play", "en": "Play", "fr": "Jouer", "icon": "play",
               "keys": {"mac": ["Play"], "android": ["play"], "ios": ["Play"]}}],
}


def catalogue(**french):
    return json.dumps({"strings": {key: {"localizations": {"fr": {"stringUnit": {"value": value}}}}
                                   for key, value in french.items()}})


class VocabularyChecks(unittest.TestCase):
    def setUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = Path(folder.name)
        self.write("words.json", json.dumps(WORDS))

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def run_check(self, *more):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check.main(["--root", str(self.root), "--vocabulary", str(self.root / "words.json"),
                               "--debt", str(self.root / "debt.json"), *more])
        return code, out.getvalue()

    def test_the_repository_vocabulary_is_sound(self):
        self.assertEqual(check.invalid(json.loads(check.VOCABULARY.read_text(encoding="utf-8"))), [])

    def test_voice_spares_words_that_only_look_like_vous(self):
        self.assertTrue(check.VOUS.search("Choisissez un jeu"))
        self.assertTrue(check.VOUS.search("Vos jeux"))
        self.assertIsNone(check.VOUS.search("C’est assez : chez toi, au rez-de-chaussée, choisis."))

    def test_a_new_gap_fails_and_a_recorded_one_passes(self):
        self.write(check.MAC, catalogue(Play="Jouer"))
        self.assertEqual(self.run_check()[0], 0)
        self.write(check.MAC, catalogue(Play="Lancer", Hint="Votre gamepad"))
        code, out = self.run_check()
        self.assertEqual(code, 1)
        for gap in ("term|mac|Play", "voice|mac|Hint", "avoid:gamepad|mac|Hint"):
            self.assertIn(gap, out)
        self.assertEqual(self.run_check("--init")[0], 0)
        self.assertEqual(self.run_check()[0], 0)

    def test_the_record_only_shrinks(self):
        self.write(check.MAC, catalogue(Play="Lancer"))
        self.run_check("--init")
        self.assertEqual(self.run_check("--init")[0], 1, "a recorded system cannot be recorded again")
        self.write(check.MAC, catalogue(Play="Jouer"))
        self.assertEqual(self.run_check()[0], 1, "a repaired gap must be pruned")
        self.assertEqual(self.run_check("--prune")[0], 0)
        self.write(check.MAC, catalogue(Play="Lancer"))
        self.run_check("--prune")
        self.assertEqual(self.run_check()[0], 1, "pruning never records")

    def test_a_renamed_key_does_not_escape(self):
        self.write(check.MAC, catalogue(Start="Jouer"))
        self.assertIn("absent|mac|Play", self.run_check()[1])

    def test_platforms_are_held_to_the_terms_and_to_the_mac_words(self):
        self.write(check.MAC, catalogue(Play="Jouer", Sort="Trier"))
        self.write("mobile/Sources/App/Resources/Localizable.xcstrings", catalogue(Play="Jouer", Sort="Classer"))
        self.assertEqual(check.spaced(["Fermer\u00a0?"]), ["Fermer ?"])
        resources = f"{check.ANDROID}/values"
        self.write(f"{resources}/strings.xml", '<resources><string name="play">Start</string></resources>')
        self.write(f"{resources}-fr/strings.xml", '<resources><string name="play">Jouer</string></resources>')
        code, out = self.run_check()
        self.assertEqual(code, 1)
        self.assertIn("shared|ios|App:Sort", out)
        self.assertIn("term|android|play", out)
        self.assertNotIn("mac:", out, "the shared catalogue is only the reference on a platform branch")

    def test_a_mac_text_that_says_vous_is_no_model(self):
        self.write(check.MAC, catalogue(Pad="Votre manette", Sort="Trier"))
        self.write("mobile/Sources/App/Resources/Localizable.xcstrings", catalogue(Pad="Ta manette", Sort="Trier", Play="Jouer"))
        self.assertNotIn("shared|ios|App:Pad", self.run_check()[1])

    def test_the_site_is_read_on_request_and_only_in_french(self):
        self.write("fr.html", '<html lang="fr"><script>var vous</script><p>Vos jeux</p></html>')
        self.write("en.html", '<html lang="en"><p>Vos</p></html>')
        code, out = self.run_check("--system", "site")
        self.assertEqual(code, 1)
        self.assertIn("voice|site|fr.html:Vos jeux", out)
        self.assertNotIn("en.html", out)


if __name__ == "__main__":
    unittest.main()
