import contextlib
import copy
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import generate_credits as credits  # noqa: E402


def run(data, *arguments):
    """The check's answer with another credits.json."""
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "credits.json"
        source.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        errors = io.StringIO()
        with mock.patch.object(credits, "SOURCE", source), contextlib.redirect_stderr(errors), contextlib.redirect_stdout(io.StringIO()):
            try:
                code = credits.main(["--check", *arguments])
            except SystemExit as stop:
                return 1, str(stop)
        return code, errors.getvalue()


class CreditsTests(unittest.TestCase):
    def setUp(self):
        self.data = credits.load()

    def without(self, name):
        data = copy.deepcopy(self.data)
        data["credits"] = [c for c in data["credits"] if c["id"] != name]
        data["roles"] = {k: v for k, v in data["roles"].items() if any(c["role"] == k for c in data["credits"])}
        return data

    def test_the_repository_passes(self):
        self.assertEqual(run(self.data), (0, ""))

    def test_a_dependency_without_a_credit_fails(self):
        for name, key in (("capstone", "wheel:capstone"), ("gametdb", "host:art.gametdb.com"), ("material-icons", "font:MaterialIcons-Regular.ttf"),
                          ("omarchy", "dir:ThirdPartyLicenses/omarchy"), ("nx2apple", "source:NX2Apple"), ("glslang", "brew:glslang")):
            code, text = run(self.without(name))
            self.assertEqual(code, 1)
            self.assertIn(f"no credit for {key}", text)

    def test_a_notice_or_a_copy_that_differs_fails(self):
        data = copy.deepcopy(self.data)
        data["credits"][0]["author"] = "Somebody else"
        code, text = run(data)
        self.assertEqual(code, 1)
        self.assertIn("NOTICE is not what design/credits.json says", text)
        for name in credits.copies(data):
            self.assertTrue("credit" in name and name.endswith(".png") or f"{name} is not what" in text, name)

    def test_a_legal_text_taken_out_of_the_notice_fails(self):
        notice = credits.read(ROOT / "NOTICE")
        with mock.patch.object(credits, "read", lambda p: notice.replace("LNPANDY/NX2Apple\nhttps", "x\nhttps").replace("LNPANDY/NX2Apple", "x", 2)
                               if p == ROOT / "NOTICE" else (p.read_text(encoding="utf-8") if p.is_file() else "")):
            code, text = run(self.data)
        self.assertEqual(code, 1)
        self.assertIn("NOTICE does not speak of nx2apple", text)

    def test_a_site_without_its_pages_fails(self):
        with tempfile.TemporaryDirectory() as folder:
            code, text = run(self.data, "--site", folder)
        self.assertEqual(code, 1)
        self.assertIn("site: credits/index.html is missing", text)

    def test_the_source_is_held_to_its_shape(self):
        for change, message in ((lambda c: c.update(license="Free"), "unknown licence"), (lambda c: c.update(url="nowhere"), "bad link"),
                                (lambda c: c.update(systems=["amiga"]), "unknown system"), (lambda c: c.update(role="none"), "unknown role"),
                                (lambda c: c.update(icon={"allowed": True, "asset": "x"}), "why it may be shown"),
                                (lambda c: c.update(license=None), "code needs a licence")):
            data = copy.deepcopy(self.data)
            change(data["credits"][0])
            self.assertIn(message, run(data)[1])

    def test_the_block_replaces_itself_and_keeps_the_rest(self):
        once = credits.with_block("Legal text.\n", "one")
        twice = credits.with_block(once, "two")
        self.assertTrue(twice.startswith("Legal text.\n"))
        self.assertIn("two", twice)
        self.assertNotIn("one\n", twice)
        self.assertEqual(credits.with_block(twice, "two"), twice)


if __name__ == "__main__":
    unittest.main()
