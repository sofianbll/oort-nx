import ShellHost
import ShellModel
import SwiftUI

struct SettingsScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    @State private var changes = 0

    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Settings"), sections: sections) { EmptyView() }
    }

    private var sections: [OortSection] {
        _ = changes
        let a = model.actions, store = model.shellSettings, sounds = nav.sounds
        func toggle(_ id: String, _ title: String, _ symbol: String, _ on: Bool, note: String = "", _ set: @escaping (Bool) -> Void) -> OortRow {
            OortRow(id: id, title: title, note: note, symbol: symbol, kind: .toggle(on) { set($0); changes += 1; model.refreshAll() })
        }
        var signing: [OortSection] = []
        if let warning = model.signingWarning {
            let title = switch warning {
            case .expired: Oort.text("The app's signature has expired")
            case .expiringHours(let hours): Oort.text("The app's signature ends in \(hours) h")
            case .expiringSoon: Oort.text("The app's signature ends soon")
            }
            signing = [OortSection(id: "signing", footer: Oort.text("Install it again from your Mac with the same account. Your games and saves stay."), rows: [
                OortRow(id: "signing", title: title, symbol: "signature", tint: Oort.warning, kind: .button { model.dismissSigningWarning() })])]
        }
        var folders = [OortRow(id: "data", title: Oort.text("Folder for every game's data"), value: store.dataFolderName ?? Oort.text("The app's own"),
                               symbol: "internaldrive", kind: .button { a.onPickShellData() })]
        if store.dataBookmark != nil {
            folders.append(OortRow(id: "dataoff", title: Oort.text("Use the app's own folder"), symbol: "arrow.uturn.backward", kind: .button {
                nav.question = .confirm(Oort.text("Use the app's own folder?"), Oort.text("Oort NX stops reading the folder you chose for every game. Nothing is deleted."),
                                        Oort.text("Use the app's own folder")) { a.onClearShellData(); changes += 1 }
            }))
        }
        folders.append(OortRow(id: "cloud", title: Oort.text("Folder the saves follow"), value: store.cloudSavesFolderName ?? Oort.text("None"),
                               symbol: "folder.badge.gearshape", kind: .button { a.onPickShellCloud() }))
        if store.cloudSavesBookmark != nil {
            folders.append(OortRow(id: "cloudoff", title: Oort.text("Stop following the folder"), symbol: "xmark.circle", kind: .button {
                nav.question = .confirm(Oort.text("Stop following the folder?"), Oort.text("Your saves stay on this device and in the folder. They no longer follow each other."),
                                        Oort.text("Stop following the folder")) { a.onClearShellCloud(); changes += 1 }
            }))
        }
        return signing + [
            OortSection(id: "games", title: Oort.text("Games"), rows: [
                OortRow(id: "add", title: Oort.text("Add a game"), note: Oort.text("A folder that ends in .framework, made by Oort NX on your Mac."), symbol: "plus", kind: .button { nav.importing = true }),
                OortRow(id: "activity", title: Oort.text("Play time"), value: model.activityLog.totalSeconds > 0 ? model.activityLog.totalTime : "", symbol: "chart.bar.xaxis", kind: .open(.activity)),
            ]),
            OortSection(id: "folders", title: Oort.text("Data and saves"), footer: Oort.text("Oort NX sends nothing and has no account. Saves leave this device only if you choose a folder."), rows: folders),
            OortSection(id: "ingame", title: Oort.text("In every game"), footer: Oort.text("A game's own options win."), rows: [
                toggle("fps", Oort.text("Show the frame rate"), "gauge.with.dots.needle.67percent", store.showFPS ?? false, store.storeShowFPS),
                toggle("hud", Oort.text("Show the graphics details"), "chart.xyaxis.line", store.performanceHUD ?? false, store.storePerformanceHUD),
                toggle("mix", Oort.text("Keep my music playing"), "music.note", store.audioMix, store.storeAudioMix),
            ]),
            OortSection(id: "sounds", title: Oort.text("Sounds and touch"), rows: [
                toggle("sounds", Oort.text("Sounds"), "speaker.wave.2", sounds.isOn) { sounds.isOn = $0; sounds.play(.confirm) },
                toggle("haptics", Oort.text("Vibrations"), "iphone.radiowaves.left.and.right", sounds.haptics) { sounds.haptics = $0; sounds.play(.confirm) },
                OortRow(id: "pack", title: Oort.text("Voice"), symbol: "waveform", enabled: sounds.isOn,
                        kind: .choice(OortSounds.packs.map { SettingOption($0, $0.capitalized) }, sounds.pack) { sounds.pack = $0; sounds.play(.success) }),
            ]),
            OortSection(id: "about", title: "Oort NX", rows: [
                OortRow(id: "version", title: Oort.text("Version"), value: Oort.version, symbol: "info.circle"),
                OortRow(id: "credits", title: Oort.text("Thanks and licences"), symbol: "heart", kind: .open(.credits)),
            ]),
        ]
    }
}

struct ActivityScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    var body: some View {
        let log = model.activityLog
        OortList(model: model, nav: nav, title: Oort.text("Play time"), sections: [
            OortSection(id: "total", rows: [
                OortRow(id: "total", title: Oort.text("All games"), value: log.totalSeconds > 0 ? log.totalTime : Oort.text("Never played")),
                OortRow(id: "sessions", title: Oort.text("Times played"), value: "\(log.totalSessions)"),
                OortRow(id: "days", title: Oort.text("Days played"), value: "\(log.activeDaysCount)"),
            ]),
            OortSection(id: "games", title: Oort.text("Games"), footer: Oort.text("Counted on this device only."), rows: log.entries.map {
                OortRow(id: $0.id, title: $0.title, value: $0.totalTime, note: $0.lastPlayed)
            }),
        ].filter { !$0.rows.isEmpty }, readAll: true) { EmptyView() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct CreditsScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Thanks and licences"), sections: [
            OortSection(id: "oort", rows: [OortRow(id: "oort", title: "Oort NX", note: Oort.text("Free software under the MIT licence. Built on Arcane by Bium23."))]),
            OortSection(id: "thanks", title: Oort.text("With the work of"), rows: [
                OortRow(id: "nx2apple", title: "NX2Apple", note: Oort.text("LNPANDY and contributors, MIT. The library of installed games, their settings, saves, cheats and controllers, and the way a game starts.")),
                OortRow(id: "nxnative", title: "nxnative", note: Oort.text("seedds, MIT. The engine inside each game.")),
                OortRow(id: "d2r", title: "d2r-mobile", note: Oort.text("jhaizhou, MIT. Where nxnative began.")),
                OortRow(id: "selene", title: "Selene", note: Oort.text("Matthew Silva, MIT. The theme Oort NX's look and sounds grew from.")),
            ]),
            OortSection(id: "notice", title: Oort.text("Licence"), rows: [
                OortRow(id: "notices", title: Oort.text("Every notice, in full"), symbol: "doc.text", kind: .open(.notices)),
                OortRow(id: "mit", title: "MIT", note: Self.licence),
            ]),
        ], readAll: true) { EmptyView() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    static let licence = """
    Copyright (c) 2026 seedds
    Copyright (c) 2026 jhaizhou
    Copyright (c) 2026 LNPANDY and NX2Apple contributors
    Copyright (c) 2026 bium
    Copyright (c) 2026 Matthew Silva

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}

/// The repository's LICENSE and NOTICE files, as shipped in the app.
struct NoticesScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    @State private var texts: [String] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SeleneTokens.Space.medium) {
                ForEach(Array(texts.enumerated()), id: \.offset) { Text($1).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .font(.footnote)
            .foregroundStyle(Oort.ink)
            .textSelection(.enabled)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SeleneTokens.Space.panel)
        }
        .modifier(OortReading(model: model, nav: nav))
        .background(Oort.page)
        .navigationTitle(Oort.text("Every notice, in full"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { texts = Self.read(from: .main) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OortHints(nav: nav, hints: [(.back, Oort.text("Back"))]).padding(SeleneTokens.Space.compact)
        }
    }

    /// One paragraph at a time, so a screen reader and the list do not take the whole file at once.
    static func read(from bundle: Bundle) -> [String] {
        ["LICENSE", "NOTICE", "NOTICE.txt"].compactMap { bundle.url(forResource: $0, withExtension: nil) }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.components(separatedBy: "\n\n") }
            .map { flow($0).trimmingCharacters(in: CharacterSet(charactersIn: "-=").union(.whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    /// The files cut their lines for a terminal: a full line runs into the next, unless that one starts a list or an address.
    static func flow(_ paragraph: String) -> String {
        paragraph.components(separatedBy: "\n").reduce(into: "") { text, line in
            let next = line.trimmingCharacters(in: .whitespaces), last = text.components(separatedBy: "\n").last ?? ""
            if text.isEmpty { text = next }
            else if last.count > 55, !next.hasPrefix("- "), !next.hasPrefix("http") { text += " " + next }
            else { text += "\n" + next }
        }
    }
}
