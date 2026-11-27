import tempfile
import unittest
from pathlib import Path

from support import ROOT
import check_probes


class ProbeTests(unittest.TestCase):
    def folder(self):
        temp = tempfile.TemporaryDirectory(prefix="oort-probes-")
        self.addCleanup(temp.cleanup)
        probes = Path(temp.name) / "Tests/CatalogAppChecks"
        probes.mkdir(parents=True)
        (probes / "ProbeRenderedText.swift").write_text("func readProbeText() {}\nfunc assertVisible() {}\n")
        return Path(temp.name), probes

    def test_the_repository_probes_prove_visibility(self):
        self.assertEqual(check_probes.check(ROOT), [])

    def test_reading_pdf_text_alone_fails(self):
        root, probes = self.folder()
        (probes / "run_example.py").write_text('SCENARIO = "let text = try readProbeText(output, name: n)"\n')
        self.assertEqual(check_probes.check(root),
                         ["Tests/CatalogAppChecks/run_example.py: reads rendered text without using assertVisible"])

    def test_an_ignored_empty_or_commented_proof_fails(self):
        root, probes = self.folder()
        for body in ('_ = readProbeText(o, name: n)\nassertVisible(o, name: n, ["x"])\n',
                     'let t = readProbeText(o, name: n)\nlet p = assertVisible(o, name: n, [])\n',
                     'let t = readProbeText(o, name: n)\n// let p = assertVisible(o, name: n, ["x"])\n'):
            with self.subTest(body=body):
                (probes / "Example.swift").write_text(body)
                self.assertEqual(len(check_probes.check(root)), 1)

    def test_reading_and_proving_passes(self):
        root, probes = self.folder()
        (probes / "Example.swift").write_text('let t = try readProbeText(o, name: n)\nfailures += assertVisible(o, name: n, '
                                              '["x"])\n')
        self.assertEqual(check_probes.check(root), [])


if __name__ == "__main__":
    unittest.main()
