import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("generate_oort_tokens", ROOT / "scripts/generate_oort_tokens.py")
GEN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GEN)


class OortTokenTests(unittest.TestCase):
    def copy(self, root):
        for relative in (GEN.SOURCE, GEN.SWIFT, GEN.CSS, GEN.PALETTES):
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    def test_generated_outputs_are_deterministic_and_stale_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy(root)
            GEN.generate(root, check=False)
            for relative in (GEN.SWIFT, GEN.CSS, GEN.PALETTES):
                path = root / relative
                self.assertEqual(path.read_bytes(), (ROOT / relative).read_bytes())
                original = path.read_text()
                path.write_text(original.replace('"focus": 16777215', '"focus": 2') if relative == GEN.PALETTES else "stale")
                with self.assertRaisesRegex(ValueError, "Stale output"):
                    GEN.generate(root, check=True)
                self.assertNotEqual(path.read_text(), original)
                path.write_text(original)

    def test_low_contrast_is_refused_before_either_output_is_written(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy(root)
            path = root / GEN.SOURCE
            data = json.loads(path.read_text())
            data["color"]["ink"]["$value"] = "{color.glass}"
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "Contrast ink / glass: 1.00:1 < 4.5:1"):
                GEN.generate(root, check=False)
            for output in (GEN.SWIFT, GEN.CSS, GEN.PALETTES):
                self.assertEqual((root / output).read_bytes(), (ROOT / output).read_bytes())

    def test_the_css_holds_the_same_values(self):
        resolved = GEN.tokens(json.loads((ROOT / GEN.SOURCE).read_text()))
        text = GEN.css(resolved)
        for line in ("--space-medium: calc(16 * var(--u));", "--radius-card: calc(16 * var(--u));", "--text-text: calc(19 * var(--u));",
                     "--motion-move: 280ms;", "--alpha-muted: 0.6;", "--art-sun: #F4CE8E;", "--effect-panel-blur-points: 10px;"):
            self.assertIn(line, text)

    def test_legacy_palettes_remain_untouched(self):
        source = json.loads((ROOT / GEN.SOURCE).read_text())
        actual = (ROOT / GEN.PALETTES).read_text()
        replacement = GEN.palettes(GEN.tokens(source), actual)
        self.assertEqual(json.loads(actual)[1:], json.loads(replacement)[1:])


if __name__ == "__main__":
    unittest.main()
