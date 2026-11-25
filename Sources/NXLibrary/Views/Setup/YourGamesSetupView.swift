import SwiftUI
import AppKit
import NXLibraryCore
import ArcanePorting

/// The library half of first launch. It uses the same backdrop, rows, pills and input channel as Get ready.
struct YourGamesSetupView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    let onChooseFiles: () -> Void
    let onChooseFolder: () -> Void
    let onFinish: () -> Void

    @State private var focus: FirstRunSetup.Focus = .file
    @State private var focusPlaced = false

    private var libraryState: FirstRunSetup.LibraryState {
        FirstRunSetup.libraryState(isScanning: viewModel.isScanningLibrary, gameCount: viewModel.libraryGames.count)
    }
    private var folderProblem: String? { GameAppDestination.folderProblem(at: viewModel.gameAppsFolder) }
    private var title: String { libraryState == .empty ? L10n.text("Add your first game") : L10n.text("Your games") }
    private var subtitle: String {
        switch libraryState {
        case .scanning: return L10n.text("Looking for existing game apps…")
        case .empty: return L10n.text("Choose a game file, or add one later.")
        case .ready:
            let count = viewModel.libraryGames.count
            return L10n.count("%lld games found.", count, arguments: [])
        }
    }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                SetupStepIndicator(page: .games).padding(.bottom, canvas.u(SeleneTokens.Space.control))
                Text(title).seleneFont(.screen, .semibold).foregroundColor(SeleneTheme.ink)
                Text(subtitle).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))

                row(.apps, title: GameFoldersCopy.appsTitle,
                    detail: GameFoldersCopy.appsContents + "\n" + (viewModel.gameAppsFolder.path as NSString).abbreviatingWithTildeInPath,
                    icon: .folder, trailing: "Change") {
                    viewModel.selectLibraryFolder()
                }
                .help(viewModel.gameAppsFolder.path)
                .padding(.top, canvas.u(SeleneTokens.Space.section))

                if !viewModel.isScanningLibrary, let warning = viewModel.libraryScanWarnings.first {
                    Text(warning).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, canvas.u(SeleneTokens.Space.small))
                }

                row(.file, title: "Choose game file", detail: "NSP · XCI · NSZ · XCZ", icon: .add,
                    enabled: folderProblem == nil, action: onChooseFiles)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))

                SelenePillButton(title: L10n.text("Choose a folder instead"), icon: .folder, iconSize: 19,
                                 minWidth: 0, height: 44, horizontalPadding: 24,
                                 focused: focus == .folder, enabled: folderProblem == nil) {
                    activate(.folder)
                }
                .onHover { if $0 { move(to: .folder) } }
                .padding(.top, canvas.u(SeleneTokens.Space.control))

                if let folderProblem {
                    Text(folderProblem).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, canvas.u(SeleneTokens.Space.small))
                }

                HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                    SelenePillButton(title: L10n.text("Back"), focused: focus == .back) { activate(.back) }
                        .onHover { if $0 { move(to: .back) } }
                    SelenePillButton(title: libraryState == .ready ? L10n.text("Open library") : L10n.text("Skip for now"),
                                     minWidth: 220, focused: focus == .finish) { activate(.finish) }
                        .onHover { if $0 { move(to: .finish) } }
                }
                .padding(.top, canvas.u(SeleneTokens.Space.section))
            }
            .frame(width: canvas.u(960))
            .offset(y: canvas.u(-20))

            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(left: [HintItem(.b, L10n.text("Back"))], right: [HintItem(.a, L10n.text("Select"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear(perform: placeInitialFocus)
        .onChange(of: viewModel.isScanningLibrary) { placeInitialFocus() }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            guard let action = note.object as? GamepadAction,
                  viewModel.showSetupCheck, viewModel.firstRunSetup.page == .games,
                  NSApp.modalWindow == nil, viewModel.alertMessage == nil else { return }
            switch action {
            case .navigateLeft: move(to: focus.moved(.left))
            case .navigateRight: move(to: focus.moved(.right))
            case .navigateUp: move(to: focus.moved(.up))
            case .navigateDown: move(to: focus.moved(.down))
            case .confirm: activate(focus)
            case .cancel: activate(.back)
            default: break
            }
        }
    }

    private func row(_ target: FirstRunSetup.Focus, title: String, detail: String, icon: MaterialIcon,
                     trailing: String? = nil, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        SetupCardRow(title: title, detail: detail, icon: icon,
                     trailing: trailing.map { .text($0) } ?? .chevron,
                     focused: focus == target, enabled: enabled,
                     onHover: { move(to: target) }) {
            move(to: target)
            guard enabled else { return }
            SoundEffectService.shared.play(.click)
            action()
        }
    }

    private func move(to next: FirstRunSetup.Focus) {
        focusPlaced = true
        guard focus != next else { return }
        focus = next
        SoundEffectService.shared.play(.focus)
    }

    private func placeInitialFocus() {
        guard !focusPlaced, !viewModel.isScanningLibrary else { return }
        focus = libraryState == .ready ? .finish : .file
        focusPlaced = true
    }

    private func activate(_ target: FirstRunSetup.Focus) {
        guard viewModel.showSetupCheck, viewModel.firstRunSetup.page == .games, NSApp.modalWindow == nil else { return }
        move(to: target)
        if (target == .file || target == .folder), folderProblem != nil {
            move(to: .apps)
            SoundEffectService.shared.play(.error)
            return
        }
        SoundEffectService.shared.play(.click)
        switch target {
        case .apps: viewModel.selectLibraryFolder()
        case .file: onChooseFiles()
        case .folder: onChooseFolder()
        case .back: viewModel.returnToSetupRequirements()
        case .finish: onFinish()
        case .steamToggle, .portingCard, .openLibrary: break
        }
    }
}

struct SetupStepIndicator: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let page: FirstRunSetup.Page

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            step(1, L10n.text("Get ready", context: localization), active: page == .requirements)
            Capsule().fill(SeleneTheme.ink15).frame(width: canvas.u(38), height: canvas.u(1))
            step(2, L10n.text("Your games", context: localization), active: page == .games)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text(page == .requirements ? "Step 1 of 2: Get ready" : "Step 2 of 2: Your games",
                                       context: localization))
    }

    private func step(_ number: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(String(number)).seleneFont(.badge, .semibold)
                .foregroundColor(active ? SeleneTheme.onFocus : SeleneTheme.ink60)
                .frame(width: canvas.u(24), height: canvas.u(24))
                .background(Circle().fill(active ? SeleneTheme.focus : SeleneTheme.glass))
            Text(title).seleneFont(.text, .semibold).foregroundColor(active ? SeleneTheme.ink : SeleneTheme.ink60)
        }
    }
}

/// A first-launch card row: icon, title, detail and what sits on the right. Focus draws the outline and glow.
struct SetupCardRow: View {
    enum Trailing { case chevron, text(String), toggle(Bool), none }

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let title: String
    let detail: String
    var note: String? = nil
    let icon: MaterialIcon
    var badges: [String] = []
    var platform: PlatformKind? = nil
    var trailing: Trailing = .chevron
    var height: CGFloat = 112
    let focused: Bool
    var enabled: Bool = true
    var onHover: () -> Void = {}
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: canvas.u(SeleneTokens.Space.large)) {
                if platform == nil { MaterialIconView(icon, size: 30).frame(width: canvas.u(40)) }
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.hairline)) {
                    if let platform {
                        PlatformLabel(platform, title: title, preset: .setup)
                    } else {
                        Text(title).seleneFont(.row, .semibold)
                    }
                    if !detail.isEmpty {
                        Text(detail).seleneFont(.text).foregroundColor(SeleneTheme.ink75)
                            .lineLimit(badges.isEmpty ? 2 : nil).truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OortFormatBadges(labels: badges)
                    if let note {
                        Text(note).seleneFont(.badge).foregroundColor(SeleneTheme.ink60).padding(.top, canvas.u(1))
                    }
                }
                Spacer(minLength: canvas.u(12))
                switch trailing {
                case .chevron: MaterialIconView(.chevron, size: 22)
                case .text(let text): Text(text).seleneFont(.text, .semibold)
                case .toggle(let isOn): SeleneSwitch(isOn: .constant(isOn)).allowsHitTesting(false)
                case .none: EmptyView()
                }
            }
            .foregroundColor(SeleneTheme.ink)
            .padding(.horizontal, canvas.u(SeleneTokens.Space.large))
            .frame(width: canvas.u(960))
            .frame(minHeight: canvas.u(height))
            .padding(.vertical, badges.isEmpty ? 0 : canvas.u(SeleneTokens.Space.compact))
            .oortPanel(radius: canvas.u(SeleneTheme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
                .strokeBorder(focused ? SeleneTheme.focus : .clear, lineWidth: canvas.u(SeleneTokens.Space.focusStroke)))
            .shadow(color: focused ? SeleneTheme.focusGlow : .clear, radius: canvas.u(16))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(OortPressStyle())
        .oortPadPress(focused)
        .disabled(!enabled)
        .onHover { if $0 { onHover() } }
        .animation(reduceMotion ? nil : SeleneTheme.focusIn, value: focused)
    }
}
