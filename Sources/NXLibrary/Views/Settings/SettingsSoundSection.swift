import SwiftUI
import AppKit
import NXLibraryCore
import UniformTypeIdentifiers

struct SettingsSoundSection: View {
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    @State private var importNote: String?
    @State private var packNote: String?
    @State private var packChoices: [(key: String, name: String)] = [("selene", "Selene")]
    @State private var removalKey = ""
    @State private var event = SoundPackEvent.move
    @State private var providedEvents: Set<String> = []
    @State private var importingPack = false
    @State private var importTicket = UUID()
    let soundPackLibrary: SoundPackLibrary

    init(settings: SettingsEditor, onActions: @escaping ([SettingsRowAction]) -> Void,
         soundPackLibrary: SoundPackLibrary = SoundPackLibrary()) {
        self.settings = settings
        self.onActions = onActions
        self.soundPackLibrary = soundPackLibrary
    }

    private func stepVolume(_ step: Int) {
        let next = (settings.settings.soundVolume * 10).rounded() + Double(step)
        settings.settings.soundVolume = min(10, max(0, next)) / 10
    }

    var body: some View {
        OortSettingsGroup {
            SeleneToggleRow("Interface sounds",
                            subtitle: "Plays a short sound when you move, select, go back or launch a game.",
                            isOn: $settings.settings.interfaceSounds)

            OortSliderRow(title: "Sound volume", subtitle: "How loud the interface sounds are.",
                          value: $settings.settings.soundVolume, range: 0...1, step: 0.05,
                          displayValue: "\(Int((settings.settings.soundVolume * 100).rounded()))%")

            SeleneToggleRow("Quiet launch screen",
                            subtitle: "Game cues only",
                            info: "Movement and selection sounds stay quiet during launch. Game starting and Game ready still play.",
                            isOn: $settings.settings.quietLaunch)

            SettingsSubheading(L10n.text("Sound packs", context: localization))
            SeleneCycleRow("Sound pack", subtitle: packNote ?? "Choose the interface sound pack.",
                           value: packChoices.first(where: { $0.key == settings.settings.soundPackID })?.name ?? "Selene",
                           verbatimValue: true, cycle: stepPack)

            SeleneCycleRow("Sound to preview", value: Self.eventTitle(event), cycle: stepEvent)
            SeleneButtonRow("Preview sound", subtitle: hasSample ? nil : "No sound for this event.", buttonTitle: "Listen") { previewSound() }
                .disabled(!canPreview)

            SeleneButtonRow("Import sound pack", subtitle: "Choose a folder or .oortsound file.",
                            buttonTitle: "Choose", action: importPack)
                .disabled(importingPack)
            if !customPacks.isEmpty {
                SeleneCycleRow("Installed pack", subtitle: "Choose an imported pack to remove.",
                               value: customPacks.first(where: { $0.key == removalKey })?.name ?? customPacks[0].name,
                               verbatimValue: true, cycle: stepRemoval)
                SeleneButtonRow("Remove sound pack",
                                subtitle: "Moves only the installed copy to the Trash.",
                                buttonTitle: "Remove", action: removePack)
            }

            SettingsSubheading(L10n.text("Theme assets"))

            SeleneButtonRow("Import sounds and wallpapers from Selene",
                            subtitle: importNote
                                ?? "Copies optional sounds and wallpapers from a local Selene folder you own.",
                            buttonTitle: "Choose folder") { importFromSelene() }
        }
        .onAppear {
            refreshPacks()
            publishActions()
        }
        .onChange(of: settings.settings.soundPackID) {
            refreshSelection()
            publishActions()
        }
        .onChange(of: settings.settings.soundVolume) { publishActions() }
        .onChange(of: importingPack) { publishActions() }
        .onDisappear {
            importTicket = UUID()
            importingPack = false
        }
        .onChange(of: settings.settings.interfaceSounds) { _, enabled in
            if enabled { SoundEffectService.shared.play(.key) }
            publishActions()
        }
    }

    private func publishActions() {
        var actions: [SettingsRowAction] = [
            .init(id: "sounds", title: "Interface sounds") {
                settings.settings.interfaceSounds.toggle()
            },
            .value("volume", "Sound volume") { stepVolume($0) },
            .init(id: "quietLaunch", title: "Quiet launch screen") {
                settings.settings.quietLaunch.toggle()
            }
        ]
        actions.append(.value("soundPack", "Sound pack", cycle: stepPack))
        actions.append(.value("soundPreviewEvent", "Sound to preview", cycle: stepEvent))
        actions.append(.init(id: "soundPreview", title: "Preview sound", isEnabled: canPreview, activate: previewSound))
        actions.append(.init(id: "importSoundPack", title: "Import sound pack", isEnabled: !importingPack,
                             activate: importPack))
        if !customPacks.isEmpty {
            actions.append(.value("soundPackToRemove", "Installed pack", cycle: stepRemoval))
            actions.append(.init(id: "removeSoundPack", title: "Remove sound pack", activate: removePack))
        }
        actions.append(.init(id: "importSelene", title: "Import sounds and wallpapers from Selene") {
            importFromSelene()
        })
        onActions(actions)
    }

    private static func eventTitle(_ event: SoundPackEvent) -> String {
        switch event {
        case .move: return "Move"
        case .select: return "Select"
        case .confirm: return "Confirm"
        case .back: return "Back"
        case .deny: return "Deny"
        case .open: return "Open"
        case .close: return "Close"
        case .play: return "Play"
        case .resume: return "Return from game"
        case .success: return "Success"
        case .notification: return "Notification"
        case .boot: return "Boot"
        case .ambience: return "Ambience"
        }
    }

    private var hasSample: Bool {
        let id = settings.settings.soundPackID
        if id == "selene" { return event.legacyCue != nil }
        if providedEvents.contains(event.rawValue) { return true }
        if event == .boot || (id == "oort" && event == .move) { return false }
        return event.legacyCue != nil
    }

    private var canPreview: Bool { hasSample && settings.settings.interfaceSounds && settings.settings.soundVolume > 0 }

    private func stepEvent(_ step: Int) {
        event = event.stepped(step)
        publishActions()
    }

    private func previewSound() {
        SoundEffectService.shared.preview(event)
    }

    private func refreshPacks() {
        packChoices = soundPackLibrary.choices()
        if !customPacks.contains(where: { $0.key == removalKey }) {
            removalKey = customPacks.first?.key ?? ""
        }
        refreshSelection()
    }

    private func refreshSelection() {
        providedEvents = []
        let key = settings.settings.soundPackID
        guard key != "selene" else { return }
        do {
            guard packChoices.contains(where: { $0.key == key }),
                  let pack = try soundPackLibrary.load(key) else {
                throw CocoaError(.fileNoSuchFile)
            }
            providedEvents = Set(pack.manifest.events.keys)
        } catch {
            settings.settings.soundPackID = "selene"
            packNote = L10n.text("The selected sound pack is unavailable. Selene is in use.", context: localization)
        }
    }

    private var customPacks: [(key: String, name: String)] {
        packChoices.filter { $0.key.hasPrefix("custom.") }
    }

    private func stepRemoval(_ step: Int) {
        removalKey = customPacks.map(\.key).stepped(from: removalKey, step) ?? ""
    }

    private func stepPack(_ step: Int) {
        let keys = packChoices.map(\.key)
        guard let next = keys.stepped(from: settings.settings.soundPackID, step) else { return }
        do {
            if next != "selene", try soundPackLibrary.load(next) == nil {
                throw CocoaError(.fileNoSuchFile)
            }
            settings.settings.soundPackID = next
            packNote = nil
        } catch {
            packNote = L10n.text("Could not select this sound pack.", context: localization) + " " + error.localizedDescription
        }
    }

    private func importPack() {
        guard !importingPack else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder, UTType(filenameExtension: "oortsound") ?? .data]
        panel.prompt = L10n.text("Choose", context: localization)
        panel.message = L10n.text("Choose a folder or .oortsound file.", context: localization)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ticket = UUID()
        importTicket = ticket
        importingPack = true
        Task {
            do {
                let pack = try await Task.detached(priority: .userInitiated) { try SoundPack.read(url) }.value
                guard importTicket == ticket else { return }
                let manifest = pack.manifest
                let alert = Self.importAlert(manifest, locale: localization)
                if alert.runModal() == .alertFirstButtonReturn {
                    try soundPackLibrary.install(pack)
                    packChoices = soundPackLibrary.choices()
                    removalKey = customPacks.first(where: { $0.key == "custom.\(manifest.id)" })?.key
                        ?? customPacks.first?.key ?? ""
                    packNote = L10n.text("Sound pack imported. Choose it to use it.", context: localization)
                }
            } catch {
                guard importTicket == ticket else { return }
                packNote = L10n.text("Could not import the sound pack.", context: localization) + " " + error.localizedDescription
            }
            importingPack = false
        }
    }

    @MainActor static func importAlert(_ manifest: SoundPackManifest, locale: AppLocale) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.text("Import sound pack?", context: locale)
        let events = SoundPackEvent.allCases.filter { manifest.events[$0.rawValue] != nil }
            .map { L10n.text(eventTitle($0), context: locale) }.joined(separator: ", ")
        alert.informativeText = [
            L10n.format("Name: %@", [manifest.name], context: locale),
            L10n.format("Author: %@", [manifest.author], context: locale),
            L10n.format("Licence: %@", [manifest.license], context: locale),
            L10n.format("Version: %@", [manifest.version], context: locale),
            L10n.format("Events: %@", [events], context: locale),
            L10n.text("Import only sounds you have the right to use.", context: locale),
            L10n.text("The pack will not be selected automatically.", context: locale)
        ].joined(separator: "\n")
        alert.addButton(withTitle: L10n.text("Import", context: locale)).keyEquivalent = ""
        alert.addButton(withTitle: L10n.text("Cancel", context: locale)).keyEquivalent = "\r"
        return alert
    }

    private func removePack() {
        let key = removalKey
        guard key.hasPrefix("custom.") else { return }
        let name = customPacks.first(where: { $0.key == key })?.name ?? key
        let alert = Self.removalAlert(name, locale: localization)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try soundPackLibrary.remove(key)
            if settings.settings.soundPackID == key { settings.settings.soundPackID = "selene" }
            packChoices = soundPackLibrary.choices()
            removalKey = customPacks.first?.key ?? ""
            packNote = nil
            publishActions()
        } catch {
            packNote = L10n.text("Could not remove the sound pack.", context: localization) + " " + error.localizedDescription
        }
    }

    @MainActor static func removalAlert(_ name: String, locale: AppLocale) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.text("Remove sound pack?", context: locale)
        alert.informativeText = L10n.format("Only the installed copy of %@ moves to the Trash. If active, Selene will be selected.", [name], context: locale)
        let remove = alert.addButton(withTitle: L10n.text("Remove", context: locale))
        remove.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: L10n.text("Cancel", context: locale))
        cancel.keyEquivalent = "\r"
        return alert
    }

    private func importFromSelene() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.text("Import")
        panel.message = L10n.text("Choose your Selene folder (the one that contains theme/theme.yaml).")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = try SeleneImporter().importFrom(seleneRoot: url)
            SoundEffectService.shared.reloadSounds()
            NotificationCenter.default.post(name: .nxSeleneImportFinished, object: nil)
            importNote = L10n.format("Imported %@ files", [String(describing: report.copied.count)])
                + (report.missing.isEmpty ? "." : L10n.format("; %@ not found in that folder.", [String(describing: report.missing.count)]))
            SoundEffectService.shared.play(.success)
        } catch {
            importNote = error.localizedDescription
            SoundEffectService.shared.play(.alert)
        }
    }
}

extension Notification.Name {
    /// Posted after a Selene import so wallpaper lists reload.
    static let nxSeleneImportFinished = Notification.Name("nxSeleneImportFinished")
}
