#!/usr/bin/env python3
"""Check the real integration wiring without mounting Settings or using local accounts."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
VIEWS = ROOT / "Sources/NXLibrary/Views"


class IntegrationContract(unittest.TestCase):
    def test_switch_arrival_does_not_prepare_or_import_keys(self):
        settings = (VIEWS / "Settings/SettingsView.swift").read_text()
        engine = (VIEWS / "Settings/SettingsEngineSection.swift").read_text()
        self.assertRegex(settings, r"openedFromIntegrations = State\(initialValue: router.previousRoute == \.integrations\)")
        self.assertRegex(settings, r"\.environment\(\\\.passiveSettingsArrival, openedFromIntegrations && section == initialSection\)")
        self.assertRegex(engine, r"\.onAppear \{\s*if !passiveArrival \{ setup.prepareBuildEnvironmentIfNeeded\(\) \}\s*publishActions\(\)")
        self.assertRegex(engine, r"if passiveArrival \{ setup.refreshCompatibility\(\) \}\s*else \{ setup.detectEnvironment\(\) \}")
        self.assertEqual(engine.count("setup.detectEnvironment()"), 1, "Both click and controller use the same re-check")


if __name__ == "__main__":
    unittest.main()
