"""A Release binary that still holds a probe hook is refused; one without passes."""

from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "scripts"))

import check_probe_hooks


class ProbeHookTests(unittest.TestCase):
    def binary(self, content):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        path = Path(folder.name) / "app"
        path.write_bytes(content)
        return path

    def test_a_binary_with_a_hook_fails_and_names_it(self):
        binary = self.binary(b"\x00$s4Demo17CloudLibraryModelC24oortProbeInstallArchives_7sourcesyF\x00oortProbeRendersFlat\x00")
        self.assertEqual(check_probe_hooks.hooks(binary), ["oortProbeInstallArchives_7sourcesyF", "oortProbeRendersFlat"])
        self.assertEqual(check_probe_hooks.main([str(binary)]), 1)

    def test_a_binary_without_a_hook_passes(self):
        binary = self.binary(b"\x00$s4Demo17CloudLibraryModelC6updateyy\x00rendersFlat\x00probe\x00")
        self.assertEqual(check_probe_hooks.hooks(binary), [])
        self.assertEqual(check_probe_hooks.main([str(binary)]), 0)


if __name__ == "__main__":
    unittest.main()
