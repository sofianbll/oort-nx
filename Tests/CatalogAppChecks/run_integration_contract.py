#!/usr/bin/env python3
"""Check the real integration wiring without mounting Settings or using local accounts."""

import json
from pathlib import Path
import re
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

    def test_drive_arrival_does_not_run_rclone_or_replay_pending_recovery(self):
        settings = (VIEWS / "Settings/SettingsView.swift").read_text()
        cloud = (VIEWS / "Settings/SettingsCloudLibrarySection.swift").read_text()
        self.assertIn("$recovery.dropFirst(openedFromIntegrations ? 1 : 0)", settings)
        self.assertRegex(cloud, r"\.task\(id: Inspection\(enabled: !passiveArrival \|\| advanced,")
        self.assertRegex(cloud, r"guard !passiveArrival \|\| advanced else \{ inspecting = false; return \}")

    def test_settings_consumes_confirmation_repeated_from_integrations(self):
        settings = (VIEWS / "Settings/SettingsView.swift").read_text()
        self.assertRegex(settings, r"case 36, 49, 76:\s*if typing \{ return event \}\s*"
                                  r"guard !event.isARepeat else \{ return nil \}\s*action = \.confirm")

    def test_spotlight_leaves_header_focus_when_wheel_enters_content(self):
        input_view = (VIEWS / "Spotlight/SpotlightView+Input.swift").read_text()
        selection = (VIEWS / "Spotlight/SpotlightView+Selection.swift").read_text()
        header = (VIEWS / "Shell/IntegrationsView+Input.swift").read_text()
        self.assertRegex(input_view, r"func scrollPage[\s\S]*?mutate \{ \$0.focus = \.pills; \$0.pillIndex = 0 \}")
        self.assertRegex(selection, r"if viewModel.spotlight.focus == \.row, state.focus != \.row \{\s*"
                                    r"router.integrationBarFocused = false\s*profileFocused = false")
        self.assertRegex(header, r"if integrationBarFocused, \[\.secondaryAction, \.contextAction, \.jumpToStart, \.jumpToEnd\]"
                                 r"\.contains\(action\) \{ return true \}")

    def test_navigating_up_can_scroll_back_to_the_first_integration(self):
        page = (VIEWS / "Shell/IntegrationsView.swift").read_text()
        self.assertRegex(page, r"scrollFocus: router.integrationFocus,\s*initialFocus:")
        shared = (VIEWS / "OortUI/OortPage.swift").read_text()
        self.assertRegex(shared, r"guard let id, old != id \|\| id != initialFocus \|\| restoreScroll")

    def test_access_copy_names_actual_destinations_and_local_writes_in_english_and_french(self):
        source = (ROOT / "Sources/ArcanePorting/Settings/IntegrationOverview.swift").read_text()
        catalog = json.loads((ROOT / "Sources/NXLibraryCore/Resources/Localizable.xcstrings").read_text())["strings"]
        sections = re.split(r"^        case \.(\w+):$", source, flags=re.MULTILINE)
        for row, body in zip(sections[1::2], sections[2::2]):
            rights = dict(re.findall(r'(reads|writes|sends): "([^"]+)"', body))
            self.assertEqual(set(rights), {"reads", "writes", "sends"}, row)
            for language in ["en", "fr"]:
                with self.subTest(row=row, language=language):
                    rendered = {right: catalog[key]["localizations"][language]["stringUnit"]["value"]
                                for right, key in rights.items()}
                    self.assertTrue(all(value.strip() for value in rendered.values()))
                    for term in {"switchGames": ["GitHub", "Apple"], "steam": ["Steam", "App ID", "CDN"], "macApps": [],
                                 "drive": ["rclone", "OAuth", "Google"], "nextendo": ["Nextendo", "OAuth"],
                                 "images": ["SteamGridDB", "IGDB", "Twitch", "Wikidata", "Nlib", "Switch Icon Showdown"],
                                 "saves": ["iCloud Drive", "Apple"]}[row]:
                        self.assertIn(term, rendered["sends"])
                    if row == "switchGames":
                        self.assertIn("private copy" if language == "en" else "copie privée", rendered["writes"])
                    if row == "saves":
                        self.assertIn("preference" if language == "en" else "préférence", rendered["writes"])


if __name__ == "__main__":
    unittest.main()
