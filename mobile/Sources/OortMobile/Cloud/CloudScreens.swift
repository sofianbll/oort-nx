import AuthenticationServices
import OortCore
import ShellHost
import SwiftUI

/// What Oort NX can be joined to. Every line is off until the player turns it on.
struct IntegrationsScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Integrations"), sections: [
            OortSection(id: "all", footer: Oort.text("Optional. Oort NX works without any of them, and nothing is contacted while they are off."), rows: [
                OortRow(id: "cloud", title: Oort.text("Cloud library"), value: nav.cloud?.isOn == true ? Oort.text("On") : Oort.text("Off"),
                        note: Oort.text("The games your Mac prepared, from your own Google Drive."), symbol: "cloud", kind: .open(.cloud)),
            ]),
        ]) { EmptyView() }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The cloud library's own page: what it does before it is on, the steps that are left, then its settings.
struct CloudScreen: View {
    let cloud: CloudModel
    let model: ShellHostModel
    let nav: OortNav
    @State private var scanning = false
    @State private var typing = false
    @State private var refusal: String?
    @Environment(\.webAuthenticationSession) private var browser

    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Cloud library"), sections: sections) {
            if cloud.stage == .off {
                Text(Oort.text("The games your Mac prepared for this device, read from your own Google Drive."))
                    .foregroundStyle(Oort.ink).padding(.vertical, SeleneTokens.Space.compact)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) { CodeScannerSheet { text in take(text) } }
        #endif
        .sheet(isPresented: $typing) { CodeEntrySheet { text in take(text) } }
        .task(id: cloud.stage) { if cloud.stage == .ready, cloud.listing == nil { await cloud.look() } }
    }

    private func take(_ text: String) {
        refusal = cloud.take(text)
        nav.sounds.play(refusal == nil ? .success : .deny)
    }

    private func signIn() {
        Task {
            await cloud.signIn { page, scheme in try await browser.authenticate(using: page, callbackURLScheme: scheme, preferredBrowserSession: .ephemeral) }
            nav.sounds.play(cloud.stage == .ready ? .success : .deny)
        }
    }

    private var sections: [OortSection] {
        switch cloud.stage {
        case .off: offSections
        case .code, .signIn: [steps]
        case .ready: [steps, choices]
        }
    }

    private var offSections: [OortSection] {
        [OortSection(id: "what", rows: [
            OortRow(id: "reads", title: Oort.text("It reads"), note: Oort.text("The folder your Mac keeps on your Google Drive. Google's permission covers your whole Drive; Oort NX opens only this folder."), symbol: "eye"),
            OortRow(id: "writes", title: Oort.text("It writes"), note: Oort.text("Nothing on Google Drive. On this device, the games you download."), symbol: "square.and.pencil"),
            OortRow(id: "sends", title: Oort.text("It sends"), note: Oort.text("Requests to Google, with your account. Nothing to Oort NX: no account, no statistics.") + "\n" + cloud.hosts.joined(separator: "\n"), symbol: "paperplane"),
            OortRow(id: "asks", title: Oort.text("It asks for"), note: Oort.text("The camera, to scan your Mac's code, and notifications, to say a game is ready. Each one when it is needed, and you can refuse."), symbol: "hand.raised"),
        ]), OortSection(id: "on", footer: Oort.text("You can turn it off at any time."), rows: [
            OortRow(id: "on", title: Oort.text("Turn on"), symbol: "power", kind: .button { cloud.turnOn() }),
        ])]
    }

    private var steps: OortSection {
        let hasCode = cloud.stage != .code, hasAccess = cloud.stage == .ready
        var rows: [OortRow] = []
        if hasCode {
            rows.append(OortRow(id: "code", title: Oort.text("Your Mac's code"), value: Oort.text("Done"), symbol: "checkmark.circle.fill", tint: nil))
        } else {
            #if os(iOS)
            rows.append(OortRow(id: "scan", title: Oort.text("Scan your Mac's code"), note: Oort.text("On your Mac: Settings, Integrations, Code for a phone."), symbol: "qrcode.viewfinder", kind: .button { refusal = nil; scanning = true }))
            #endif
            rows.append(OortRow(id: "paste", title: Oort.text("Paste the code"), note: refusal ?? "", symbol: "doc.on.clipboard", kind: .button { refusal = nil; typing = true }))
        }
        if hasAccess {
            rows.append(OortRow(id: "access", title: Oort.text("Signed in with Google"), value: Oort.text("Done"), symbol: "checkmark.circle.fill"))
        } else {
            let refused = cloud.problem.map { $0 == .accessDenied ? Oort.text("Google did not give access. Nothing was changed.") : CloudWords.why($0) }
            rows.append(OortRow(id: "signin", title: Oort.text("Sign in with Google"), note: hasCode ? refused ?? Oort.text("In the system's browser. Oort NX never sees your password.") : "",
                                symbol: "person.badge.key", enabled: hasCode, kind: .button(signIn)))
        }
        rows.append(folder)
        return OortSection(id: "steps", rows: rows)
    }

    private var folder: OortRow {
        if cloud.looking { return OortRow(id: "folder", title: Oort.text("Looking for your games…"), symbol: "folder") }
        if let listing = cloud.listing {
            return OortRow(id: "folder", title: Oort.text("Folder found"), value: Oort.text("\(listing.games.count) games for this device"), symbol: "checkmark.circle.fill")
        }
        if cloud.stage == .ready, let problem = cloud.problem {
            return OortRow(id: "folder", title: Oort.text("Folder not found"), note: CloudWords.why(problem), symbol: "exclamationmark.triangle", tint: Oort.warning)
        }
        return OortRow(id: "folder", title: Oort.text("Folder on Google Drive"), symbol: "folder", enabled: false)
    }

    private var choices: OortSection {
        OortSection(id: "choices", footer: Oort.text("\(cloud.freeSpace.map(CloudWords.size) ?? "—") free on this device."), rows: [
            OortRow(id: "open", title: Oort.text("See the games"), symbol: "square.grid.2x2", kind: .button { nav.showCloud() }),
            OortRow(id: "again", title: Oort.text("Look again"), symbol: "arrow.clockwise", enabled: !cloud.looking, kind: .button { Task { await cloud.look() } }),
            OortRow(id: "wifi", title: Oort.text("Wi-Fi only"), note: Oort.text("Mobile data is never used while this is on."), symbol: "wifi", kind: .toggle(cloud.wifiOnly) { cloud.wifiOnly = $0 }),
            OortRow(id: "used", title: Oort.text("Downloads not installed yet"), value: CloudWords.size(cloud.used), symbol: "internaldrive"),
            OortRow(id: "change", title: Oort.text("Change the code"), note: Oort.text("Erases the sign-in of this one first."), symbol: "qrcode", kind: .button { Task { await cloud.changeCode() } }),
            OortRow(id: "off", title: Oort.text("Turn off"), symbol: "power", kind: .open(.cloudOff)),
        ])
    }
}

/// Turning off is a page, not a dialog, so that a controller chooses as a finger does.
struct CloudOffScreen: View {
    let cloud: CloudModel
    let model: ShellHostModel
    let nav: OortNav
    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Turn off"), sections: [
            OortSection(id: "off", footer: Oort.text("Games already installed stay. Your saves are never touched."), rows: [
                OortRow(id: "keep", title: Oort.text("Keep the downloads"), symbol: "power", kind: .button { off(false) }),
                OortRow(id: "delete", title: Oort.text("Delete the downloads"), symbol: "trash", tint: Oort.danger, kind: .button { off(true) }),
                OortRow(id: "cancel", title: Oort.text("Cancel"), symbol: "xmark", kind: .button { _ = nav.back() }),
            ]),
        ]) {
            VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
                Text(Oort.text("Turn the cloud library off?")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(Oort.text("The sign-in is erased from this device. Your Google Drive and your saves stay as they are. To withdraw Google's permission too, remove Oort from your Google account's connections."))
                    .foregroundStyle(Oort.ink2)
            }
            .foregroundStyle(Oort.ink)
            .padding(.vertical, SeleneTokens.Space.compact)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func off(_ deleting: Bool) {
        nav.cloudShown = false
        Task {
            await cloud.turnOff(deleting: deleting)
            _ = nav.back()
        }
    }
}

/// One game of the cloud: what it is, what it needs, and the one thing to do now.
struct CloudGameScreen: View {
    let id: String
    let cloud: CloudModel
    let model: ShellHostModel
    let nav: OortNav
    @Environment(\.horizontalSizeClass) private var across
    @Environment(\.verticalSizeClass) private var down
    private var beside: Bool { across == .regular || down == .compact }

    var body: some View {
        if let game = cloud.game(id) {
            layout(game)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .sensoryFeedback(.success, trigger: game.job?.state == .ready)
        } else {
            ContentUnavailableView(Oort.text("This game is no longer here"), systemImage: "square.dashed")
        }
    }

    @ViewBuilder private func layout(_ game: CloudModel.Game) -> some View {
        if beside {
            HStack(spacing: 0) {
                ScrollView { header(game).padding(.horizontal, SeleneTokens.Space.panel) }
                    .scrollBounceBehavior(.basedOnSize)
                    .safeAreaInset(edge: .bottom, spacing: 0) { key(game).padding(.horizontal, SeleneTokens.Space.panel).padding(.vertical, SeleneTokens.Space.compact) }
                    .containerRelativeFrame(.horizontal) { width, _ in min(width * Oort.Measure.sideShare, Oort.Measure.side) }
                OortList(model: model, nav: nav, title: "", sections: sections(game), backdrop: false) { EmptyView() }
            }
            .background { OortBackdrop(strength: Oort.Measure.backdrop) }
            .navigationTitle(game.build.name)
        } else {
            OortList(model: model, nav: nav, title: game.build.name, sections: sections(game)) { header(game) }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    key(game)
                        .padding(.horizontal, SeleneTokens.Space.panel)
                        .padding(.top, SeleneTokens.Space.large)
                        .padding(.bottom, SeleneTokens.Space.compact)
                        .background { LinearGradient(colors: [.clear, Oort.night.opacity(Oort.Measure.foot)], startPoint: .top, endPoint: .center).ignoresSafeArea() }
                }
        }
    }

    private func header(_ game: CloudModel.Game) -> some View {
        VStack(alignment: .leading, spacing: SeleneTokens.Space.medium) {
            CloudTile(game: game, cloud: cloud, artwork: CloudArt.of(id, model), side: down == .compact ? Oort.Measure.coverShort : Oort.Measure.cover)
            Text(game.build.name).font(.title.bold()).foregroundStyle(Oort.ink).accessibilityAddTraits(.isHeader)
            Text(CloudWords.state(game, cloud)).font(.subheadline).monospacedDigit().foregroundStyle(Oort.ink2)
                .accessibilityAddTraits(game.job?.state == .running ? .updatesFrequently : [])
            if let message = cloud.message { Text(message).font(.subheadline).foregroundStyle(Oort.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, SeleneTokens.Space.compact)
        .padding(.horizontal, SeleneTokens.Space.seam)
    }

    private func key(_ game: CloudModel.Game) -> some View {
        let action = CloudAction(game, cloud: cloud, model: model, nav: nav)
        return Button(action: action.run) { Label(action.label, systemImage: action.symbol).frame(maxWidth: .infinity) }
            .buttonStyle(OortKeyStyle(solid: true))
            .disabled(!action.enabled)
    }

    private func sections(_ game: CloudModel.Game) -> [OortSection] {
        var facts = [OortRow(id: "version", title: Oort.text("Version"), value: game.build.gameVersion, symbol: "number"),
                     OortRow(id: "size", title: Oort.text("Size"), value: CloudWords.size(game.build.bytes), symbol: "shippingbox"),
                     OortRow(id: "free", title: Oort.text("Free on this device"), value: cloud.freeSpace.map(CloudWords.size) ?? "—", symbol: "internaldrive"),
                     OortRow(id: "system", title: Oort.text("System needed"), value: "iOS \(game.build.minimumSystem)", symbol: "iphone")]
        if let here = game.installedVersion { facts.insert(OortRow(id: "here", title: Oort.text("On this device"), value: here, symbol: "checkmark.circle"), at: 1) }
        var rows: [OortRow] = []
        let action = CloudAction(game, cloud: cloud, model: model, nav: nav)
        if nav.device != nil { rows.append(OortRow(id: "start", title: action.label, symbol: action.symbol, enabled: action.enabled, kind: .button(action.run))) }
        if game.job != nil, cloud.installing != id {
            rows.append(OortRow(id: "cancel", title: Oort.text("Cancel the download"), note: Oort.text("Erases only what this download received."), symbol: "xmark.circle",
                                tint: Oort.danger, kind: .button { Task { await cloud.cancel(id) } }))
        }
        if game.installedVersion != nil {
            rows.append(OortRow(id: "page", title: Oort.text("Game page"), note: Oort.text("Remove it from this device there. Its saves and Google Drive stay."), symbol: "info.circle", kind: .open(.game(id))))
        }
        return [OortSection(id: "facts", footer: Oort.text("Signed by your Mac. Each file is checked before it is installed."), rows: facts),
                OortSection(id: "do", rows: rows)].filter { !$0.rows.isEmpty }
    }
}

/// The one thing a game of the cloud waits for.
struct CloudAction {
    var label: String
    var symbol: String
    var enabled = true
    var run: @MainActor () -> Void = {}

    @MainActor init(_ game: CloudModel.Game, cloud: CloudModel, model: ShellHostModel, nav: OortNav) {
        let id = game.id, sounds = nav.sounds
        if cloud.installing == id {
            (label, symbol, enabled) = (Oort.text("Installing…"), "hourglass", false)
            return
        }
        switch game.job?.state {
        case .running, .waiting:
            (label, symbol) = (Oort.text("Pause"), "pause.fill")
            run = { sounds.play(.select); cloud.pause(id) }
        case .paused:
            (label, symbol) = (Oort.text("Resume"), "arrow.down")
            run = { sounds.play(.confirm); cloud.resume(id) }
        case .failed:
            (label, symbol) = (Oort.text("Try again"), "arrow.clockwise")
            run = { sounds.play(.confirm); cloud.resume(id) }
        case .ready:
            (label, symbol) = (Oort.text("Install"), "square.and.arrow.down")
            run = { Task { await cloud.install(id); sounds.play(cloud.game(id)?.isInstalled == true ? .success : .deny) } }
        case nil where game.isInstalled:
            if let detail = model.details.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) {
                let action = OortGameAction(detail, model: model, nav: nav)
                (label, symbol, enabled, run) = (action.label, action.symbol, action.enabled, action.run)
            } else { (label, symbol, enabled) = (Oort.text("Installed"), "checkmark", false) }
        case nil:
            (label, symbol) = game.installedVersion == nil ? (Oort.text("Download"), "arrow.down") : (Oort.text("Update"), "arrow.up")
            run = { sounds.play(.confirm); cloud.download(game.build) }
        }
    }
}

enum CloudArt {
    /// The picture the library already has of it, if any. Nothing is downloaded to draw a list.
    @MainActor static func of(_ id: String, _ model: ShellHostModel) -> CloudTile.GameArt? {
        guard let tile = model.details.first(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame })?.game, let art = tile.icon ?? tile.banner else { return nil }
        return .init(view: AnyView(OortPicture(artwork: art)))
    }
}

/// The code as text, typed or pasted.
private struct CodeEntrySheet: View {
    let take: (String) -> Void
    @State private var text = ""
    @FocusState private var typing: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SeleneTokens.Space.medium) {
                    Text(Oort.text("On your Mac: Settings, Integrations, Code for a phone, Copy the code.")).foregroundStyle(Oort.ink2)
                    TextField(Oort.text("Code from your Mac"), text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        #endif
                        .focused($typing)
                        .padding(SeleneTokens.Space.medium)
                        .oortPanel(radius: Oort.key)
                        .accessibilityIdentifier("oort.code")
                    PasteButton(payloadType: String.self) { items in text = items.first ?? text }
                    Button { take(text); dismiss() } label: { Label(Oort.text("Use this code"), systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(OortKeyStyle(solid: true))
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(SeleneTokens.Space.panel)
            }
            .background(Oort.page)
            .navigationTitle(Oort.text("Paste the code"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(Oort.text("Close")) { dismiss() } } }
            .onAppear { typing = true }
        }
        .preferredColorScheme(.dark)
    }
}
