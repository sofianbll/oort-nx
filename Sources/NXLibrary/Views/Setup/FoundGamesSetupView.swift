import SwiftUI
import AppKit
import NXLibraryCore

/// The first launch's first page: what is already on the Mac (Steam, ported apps), the Porting card and
/// Open library. It reads without changing anything; the switches apply only on Open library.
struct FoundGamesSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    let steamRoot: URL
    let steamEnabled: Bool
    /// The Steam switch lives in `FirstRunSetup`, so it survives the Porting path; the shell applies it.
    let onOpenLibrary: (_ importPorted: Bool) -> Void

    @StateObject var reader = FirstRunFindingsReader()
    @State var focus: FirstRunSetup.Focus = .initialOnFound

    var findings: FirstRunFindings? { reader.findings }
    var steamCount: Int? { findings?.steamGameCount }
    var hasSteam: Bool { steamCount != nil || findings?.steamReadFailed == true }
    var portedCount: Int { findings?.portedAppCount ?? 0 }
    var isReading: Bool { findings == nil }
    var steamOn: Bool { viewModel.firstRunSetup.steamChoice ?? steamEnabled }

    var body: some View {
        FoundGamesSetupContent(findings: findings, steamOn: steamOn, focus: focus,
                               move: move, activate: activate)
        .onAppear {
            reader.start(steamRoot: steamRoot, appsFolder: viewModel.gameAppsFolder)
        }
        .onDisappear { reader.cancel() }
        .onChange(of: findings) { _, found in
            if found != nil, !hasSteam, focus == .steamToggle { move(to: .openLibrary) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            guard let action = note.object as? GamepadAction else { return }
            handle(action)
        }
    }
}

/// The Selene screen shared by the live reader and the offline Debug preview.
struct FoundGamesSetupContent: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let findings: FirstRunFindings?
    let steamOn: Bool
    let focus: FirstRunSetup.Focus
    let move: (FirstRunSetup.Focus) -> Void
    let activate: (FirstRunSetup.Focus) -> Void

    private var isReading: Bool { findings == nil }

    private var title: String {
        if isReading { return L10n.text("Looking at your Mac…") }
        return findings?.isEmpty == true ? L10n.text("No games found") : L10n.text("Here's what's on your Mac")
    }

    private var subtitle: String {
        if isReading { return L10n.text("Arcane reads Steam and your Game apps folder without changing anything. You can open the library now and add sources later in Settings.") }
        return findings?.isEmpty == true
            ? L10n.text("Steam and ported apps aren't here yet. Add them later from Settings → Sources or with Porting.")
            : L10n.text("Arcane looked without changing anything. Choose what goes in your library.")
    }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                Text(title).seleneFont(.screen, .semibold).foregroundColor(SeleneTheme.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))

                VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    if let steamCount = findings?.steamGameCount {
                        SetupCardRow(title: "Steam",
                                     detail: L10n.count("%lld installed Mac games", steamCount),
                                     icon: .store, platform: .steam, trailing: .toggle(steamOn),
                                     focused: focus == .steamToggle,
                                     onHover: { move(.steamToggle) }) { activate(.steamToggle) }
                    } else if findings?.steamReadFailed == true {
                        SetupCardRow(title: "Steam",
                                     detail: L10n.text("Steam couldn't be read completely. Try again or continue and check Settings → Sources later."),
                                     icon: .store, platform: .steam, trailing: .text(L10n.text("Retry")),
                                     focused: focus == .steamToggle,
                                     onHover: { move(.steamToggle) }) { activate(.steamToggle) }
                    }
                    if let portedCount = findings?.portedAppCount, portedCount > 0 {
                        SetupCardRow(title: L10n.format("Already ported: %@", [String(portedCount)]),
                                     detail: L10n.text("They're in your library."),
                                     icon: .check, trailing: .none, height: 84, focused: false) {}
                            .allowsHitTesting(false)
                    }
                    SetupCardRow(title: AppIdentity.portingName,
                                 detail: L10n.text("Bring the Nintendo Switch games you own to the Mac."),
                                 note: L10n.text("Arcane is not affiliated with Nintendo."),
                                 icon: .build, focused: focus == .portingCard,
                                 onHover: { move(.portingCard) }) { activate(.portingCard) }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.section))

                SelenePillButton(title: L10n.text("Open library"), minWidth: 220,
                                 focused: focus == .openLibrary) {
                    activate(.openLibrary)
                }
                .seleneHover { move(.openLibrary) }
                .padding(.top, canvas.u(SeleneTokens.Space.section))
            }
            .frame(width: canvas.u(960))
            .offset(y: canvas.u(-20))
            .animation(reduceMotion ? nil : SeleneTheme.standard, value: findings)

            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: [HintItem(.a, L10n.text("Select"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
    }
}
