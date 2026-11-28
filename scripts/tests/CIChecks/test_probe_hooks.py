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


class SourceTests(unittest.TestCase):
    def test_a_hook_inside_if_debug_passes(self):
        self.assertEqual(check_probe_hooks.outside_debug(
            "#if DEBUG\nextension M {\n    func oortProbeSet() {}\n}\n#endif\n"), [])

    def test_a_hook_without_if_debug_fails(self):
        self.assertEqual(check_probe_hooks.outside_debug("extension M {\n    func oortProbeSet() {}\n}\n"), [2])

    def test_the_else_branch_of_debug_is_outside(self):
        text = "#if DEBUG\nstatic var oortProbeFlat = false\n#else\nlet flat = oortProbeFlat\n#endif\n"
        self.assertEqual(check_probe_hooks.outside_debug(text), [4])

    def test_a_nested_condition_inside_debug_stays_inside(self):
        text = "#if DEBUG\n#if os(macOS)\nfunc oortProbeA() {}\n#endif\n#endif\nfunc oortProbeB() {}\n"
        self.assertEqual(check_probe_hooks.outside_debug(text), [6])

    def test_a_comment_naming_a_hook_is_not_a_hook(self):
        self.assertEqual(check_probe_hooks.outside_debug("// until they render through oortProbeRendersFlat\n"), [])

    def test_the_repository_keeps_its_hooks_inside_debug(self):
        self.assertEqual(check_probe_hooks.sources(ROOT), [])


class CapitalTests(unittest.TestCase):
    def test_a_type_named_oort_probe_counts_too(self):
        self.assertEqual(check_probe_hooks.outside_debug("@MainActor enum OortProbeObserver {}\n"), [1])
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        binary = Path(folder.name) / "app"
        binary.write_bytes(b"\x00$s4Demo17OortProbeObserverO\x00")
        self.assertEqual(check_probe_hooks.hooks(binary), ["OortProbeObserverO"])
