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

    def test_nextendo_arrival_does_not_send_or_rotate_tokens(self):
        api = (VIEWS / "Settings/SettingsAPISection.swift").read_text()
        self.assertIn("!passiveArrival || nextendoRequested", api)
        self.assertRegex(api, r"if canContactNextendo && supportsNextendo && accountOnly \{ nextendo.check")
        self.assertRegex(api, r"\.onChange\(of: supportsNextendo\).*?\n\s*if canContactNextendo, accountOnly")
        self.assertRegex(api, r"\.task\(id: canContactNextendo \? friendsRefreshClient : nil\) \{\s*guard canContactNextendo")
        self.assertRegex(api, r"\.task\(id: passiveArrival \? nil : key\) \{\s*guard !passiveArrival, image == nil")
        self.assertIn('.init("Check status", action: checkNextendo)', api)
        self.assertRegex(api, r"func checkNextendo\(\) \{\s*nextendoRequested = true\s*nextendo.check\(clientID: clientID\)")

    def test_settings_consumes_confirmation_repeated_from_integrations(self):
        settings = (VIEWS / "Settings/SettingsView.swift").read_text()
        self.assertRegex(settings, r"case 36, 49, 76:\s*if typing \{ return event \}\s*"
                                  r"guard !event.isARepeat else \{ return nil \}\s*action = \.confirm")


if __name__ == "__main__":
    unittest.main()
