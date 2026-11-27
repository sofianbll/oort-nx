import SwiftUI
import AppKit
import OortLibrary
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
    /// The pack last chosen under Other, given back when the row returns there.
    @State private var otherKey = "selene"
    @State private var event = SoundPackEvent.move
    @State private var providedEvents: Set<String> = []
    @State private var importingPack = false
    @State private var importTicket = UUID()
    @State private var playing: Int?
    /// nil: everywhere.
    @State private var place: OortSynth.Place?
    @State private var playTicket = UUID()
    let soundPackLibrary: SoundPackLibrary
    /// The app's own question, on Cancel.
    let ask: (Question, @escaping () -> Void) -> Void

    struct Question {
        let title: String
        let message: String
        let action: String
    }

    init(settings: SettingsEditor, onActions: @escaping ([SettingsRowAction]) -> Void,
         soundPackLibrary: SoundPackLibrary = SoundPackLibrary(),
         ask: @escaping (Question, @escaping () -> Void) -> Void = { _, _ in }) {
        self.settings = settings
        self.onActions = onActions
        self.soundPackLibrary = soundPackLibrary
        self.ask = ask
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
                           value: isOtherPack ? L10n.text("Other", context: localization) : packName,
                           verbatimValue: true, cycle: stepPack)
            if isOtherPack {
                SeleneCycleRow("Other pack", subtitle: packNote ?? "The earlier packs and those you imported.",
                               value: packName, verbatimValue: true, cycle: stepOtherPack)
            }

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
                SeleneButtonRow("Delete sound pack",
                                subtitle: "Moves only the installed copy to the Trash.",
                                buttonTitle: "Delete", action: removePack)
            }

            if OortSynth(pack: settings.settings.soundPackID) != nil {
                SettingsSubheading(L10n.text("Compose", context: localization))
                SeleneCycleRow("Place", subtitle: "Where this sequence is heard. A place without its own follows Everywhere.",
                               value: place?.title ?? "Everywhere", cycle: stepPlace)
                SeleneCycleRow("Note sequence", subtitle: "The notes you hear as you move. The Oort voices play it from start to end.",
                               value: melody.figure.title, cycle: stepFigure)
                SeleneCycleRow("Octave", subtitle: "Plays the note sequence lower or higher.",
                               value: melody.octave > 0 ? "+\(melody.octave)" : "\(melody.octave)",
                               verbatimValue: true, cycle: stepOctave)
                SeleneButtonRow("Listen to the sequence", buttonTitle: "Listen", action: playNotes)
                if ownMelody {
                    SeleneButtonRow("Follow Everywhere", subtitle: "Removes this place’s own sequence.", buttonTitle: "Follow", action: followEverywhere)
                }
                OortNotes(notes: melody.notes, playing: playing, change: setNote)
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
        if isOtherPack { actions.append(.value("soundPackOther", "Other pack", cycle: stepOtherPack)) }
        actions.append(.value("soundPreviewEvent", "Sound to preview", cycle: stepEvent))
        actions.append(.init(id: "soundPreview", title: "Preview sound", isEnabled: canPreview, activate: previewSound))
        if OortSynth(pack: settings.settings.soundPackID) != nil {
            actions.append(.value("placeNotes", "Place", cycle: stepPlace))
            actions.append(.value("noteFigure", "Note sequence", cycle: stepFigure))
            actions.append(.value("noteOctave", "Octave", cycle: stepOctave))
            actions.append(.init(id: "noteListen", title: "Listen to the sequence", activate: playNotes))
            if ownMelody { actions.append(.init(id: "noteFollow", title: "Follow Everywhere", activate: followEverywhere)) }
        }
        actions.append(.init(id: "importSoundPack", title: "Import sound pack", isEnabled: !importingPack,
                             activate: importPack))
        if !customPacks.isEmpty {
            actions.append(.value("soundPackToRemove", "Installed pack", cycle: stepRemoval))
            actions.append(.init(id: "removeSoundPack", title: "Delete sound pack", activate: removePack))
        }
        actions.append(.init(id: "importSelene", title: "Import sounds and wallpapers from Selene") {
            importFromSelene()
        })
        onActions(actions)
    }

    private var melody: OortSynth.Melody { settings.settings.melody(place) }
    private var ownMelody: Bool { place.map { settings.settings.placeNotes[$0.rawValue] != nil } ?? false }

    private func change(_ edit: (inout OortSynth.Melody) -> Void) {
        var next = melody
        edit(&next)
        guard next != melody else { return }
        settings.settings.setMelody(next, for: place)
        publishActions()
    }

    private func stepPlace(_ step: Int) {
        let all: [OortSynth.Place?] = [nil] + OortSynth.Place.allCases
        guard let index = all.firstIndex(of: place) else { return }
        place = all[(index + step + all.count) % all.count]
        publishActions()
        playNotes()
    }

    private func followEverywhere() {
        guard let place else { return }
        settings.settings.placeNotes[place.rawValue] = nil
        publishActions()
        playNotes()
    }

    private func stepFigure(_ step: Int) {
        let all = OortSynth.Figure.allCases
        change { melody in
            guard let index = all.firstIndex(of: melody.figure) else { return }
            melody.figure = all[(index + step + all.count) % all.count]
        }
        playNotes()
    }

    private func stepOctave(_ step: Int) {
        change { $0.octave = min(OortSynth.octaves.upperBound, max(OortSynth.octaves.lowerBound, $0.octave + step)) }
        playNotes()
    }

    /// Pulling a note makes the sequence the player's own, starting from the one on screen.
    private func setNote(_ index: Int, _ value: Double) {
        let value = min(OortSynth.range.upperBound, max(OortSynth.range.lowerBound, value))
        var next = melody.notes.map { $0.rounded() }
        guard next[index] != value || melody.figure != .custom else { return }
        next[index] = value
        change { $0.custom = next; $0.figure = .custom }
        SoundEffectService.shared.previewNotes([value], octave: melody.octave, pack: settings.settings.soundPackID)
    }

    private func playNotes() {
        let ticket = UUID()
        playTicket = ticket
        SoundEffectService.shared.previewNotes(melody.notes, octave: melody.octave, pack: settings.settings.soundPackID)
        Task { @MainActor in
            for index in 0..<melody.notes.count {
                guard playTicket == ticket else { return }
                playing = index
                try? await Task.sleep(for: .milliseconds(135))
            }
            if playTicket == ticket { playing = nil }
        }
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
        if OortSynth(pack: id) != nil { return event != .ambience }
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
        if isOtherPack { otherKey = key }
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

    private var isOtherPack: Bool { SoundPackRow.value(for: settings.settings.soundPackID) == SoundPackRow.other }
    private var packName: String { packChoices.first(where: { $0.key == settings.settings.soundPackID })?.name ?? "Selene" }

    private var customPacks: [(key: String, name: String)] {
        packChoices.filter { $0.key.hasPrefix("custom.") }
    }

    private func stepRemoval(_ step: Int) {
        removalKey = customPacks.map(\.key).stepped(from: removalKey, step) ?? ""
    }

    private func stepPack(_ step: Int) {
        let remembered = packChoices.contains(where: { $0.key == otherKey }) ? otherKey : "selene"
        selectPack(SoundPackRow.step(from: settings.settings.soundPackID, step, other: remembered))
    }

    private func stepOtherPack(_ step: Int) {
        let keys = SoundPackRow.others(packChoices).map(\.key)
        if let next = keys.stepped(from: settings.settings.soundPackID, step) { selectPack(next) }
    }

    private func selectPack(_ next: String) {
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
        OortFilePickerPresentation.open(.files(["oortsound"], folder: true), title: L10n.text("Import sound pack", context: localization),
                                        message: L10n.text("Choose a folder or .oortsound file.", context: localization)) { urls in
            if let url = urls.first { importPack(url) }
        }
    }

    private func importPack(_ url: URL) {
        guard !importingPack else { return }
        let ticket = UUID()
        importTicket = ticket
        importingPack = true
        Task {
            do {
                let pack = try await Task.detached(priority: .userInitiated) { try SoundPack.read(url) }.value
                guard importTicket == ticket else { return }
                ask(Self.importQuestion(pack.manifest, locale: localization)) { install(pack) }
            } catch {
                guard importTicket == ticket else { return }
                packNote = L10n.text("Could not import the sound pack.", context: localization) + " " + error.localizedDescription
            }
            importingPack = false
        }
    }

    private func install(_ pack: SoundPack) {
        do {
            try soundPackLibrary.install(pack)
            packChoices = soundPackLibrary.choices()
            removalKey = customPacks.first(where: { $0.key == "custom.\(pack.manifest.id)" })?.key
                ?? customPacks.first?.key ?? ""
            packNote = L10n.text("Sound pack imported. Choose it to use it.", context: localization)
        } catch {
            packNote = L10n.text("Could not import the sound pack.", context: localization) + " " + error.localizedDescription
        }
    }

    static func importQuestion(_ manifest: SoundPackManifest, locale: AppLocale) -> Question {
        let events = SoundPackEvent.allCases.filter { manifest.events[$0.rawValue] != nil }
            .map { L10n.text(eventTitle($0), context: locale) }.joined(separator: ", ")
        let facts = [
            L10n.format("Name: %@", [manifest.name], context: locale),
            L10n.format("Author: %@", [manifest.author], context: locale),
            L10n.format("Licence: %@", [manifest.license], context: locale),
            L10n.format("Version: %@", [manifest.version], context: locale),
            L10n.format("Events: %@", [events], context: locale),
            L10n.text("Import only sounds you have the right to use.", context: locale),
            L10n.text("The pack will not be selected automatically.", context: locale)
        ].joined(separator: "\n")
        return Question(title: L10n.text("Import sound pack?", context: locale), message: facts, action: "Import")
    }

    private func removePack() {
        let key = removalKey
        guard key.hasPrefix("custom.") else { return }
        let name = customPacks.first(where: { $0.key == key })?.name ?? key
        ask(Self.removalQuestion(name, locale: localization)) { remove(key) }
    }

    private func remove(_ key: String) {
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

    static func removalQuestion(_ name: String, locale: AppLocale) -> Question {
        Question(title: L10n.text("Delete sound pack?", context: locale),
                 message: L10n.format("Only the installed copy of %@ moves to the Trash. If active, Selene will be selected.", [name], context: locale),
                 action: "Delete")
    }

    private func importFromSelene() {
        OortFilePickerPresentation.open(.folder, title: L10n.text("Selene folder"),
                                        message: L10n.text("Choose your Selene folder (the one that contains theme/theme.yaml).")) { urls in
            if let url = urls.first { importSelene(url) }
        }
    }

    private func importSelene(_ url: URL) {
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
