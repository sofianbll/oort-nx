import AppKit
import NXLibraryCore
import SwiftUI

struct DowngradeWarningView: View {
    enum Choice: Hashable {
        case retry, proceed, folder, quit
    }

    private final class ControllerInput: ObservableObject {
        var handle: ((GamepadAction) -> Void)?
    }

    let notice: DevelopmentStartup.Notice
    let retry: () -> Void
    let proceed: () -> Void
    var context = AppLocale(language: .automatic, region: nil)
    @Environment(\.seleneCanvas) private var canvas
    @ObservedObject private var theme = ThemeStore.shared
    @StateObject private var controller = ControllerInput()
    @State private var index = 2
    @FocusState private var acceptsKeys: Bool

    private var failed: Bool { notice.canContinueWithoutCopy }
    private var choices: [Choice] { failed ? [.quit, .proceed, .retry] : [.quit, .folder, .proceed] }
    private var omissions: [DowngradeCheckpoint.Omission] {
        if case let .copy(omissions) = notice { return omissions }
        return []
    }

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.panel)) {
            Text(title)
                .seleneFont(.screen, .semibold)
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .seleneFont(.text)
                .foregroundStyle(SeleneTheme.ink90)
            Text(risk)
                .seleneFont(.text)
                .foregroundStyle(SeleneTheme.ink75)
            OortActionBar(actions: choices.enumerated().map { position, choice in
                .init(id: position, title: label(choice),
                      role: choice == .quit ? .back : position == choices.count - 1 ? .primary : .secondary) { perform(choice) }
            }, focused: index, preset: .card) { id in
                if let position = id.base as? Int { index = position }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: canvas.u(880))
        .foregroundStyle(SeleneTheme.ink)
        .padding(canvas.u(SeleneTokens.Space.group))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            SeleneHintsBar(left: [HintItem(.b, "Quit") { perform(.quit) }],
                           right: [HintItem(.a, "Select") { perform(choices[index]) }])
        }
        .background(SeleneTheme.baseGradient(for: theme.palette))
        .environment(\.nxAppLocale, context)
        .focusable()
        .focused($acceptsKeys)
        .defaultFocus($acceptsKeys, true)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .tab, .return, .space, .escape]) { key in
            switch key.key {
            case .leftArrow: input(.navigateLeft)
            case .rightArrow: input(.navigateRight)
            case .tab: input(key.modifiers.contains(.shift) ? .navigateLeft : .navigateRight)
            case .escape: input(.cancel)
            default: input(.confirm)
            }
            return .handled
        }
        .onAppear {
            acceptsKeys = true
            let receiver = controller
            receiver.handle = input
            GameControllerService.shared.onAction = { [weak receiver] in receiver?.handle?($0) }
            LaunchReveal.show()
        }
        // Do not clear the shared router: the shell can already have installed its own handler.
        .onDisappear { controller.handle = nil }
    }

    private var title: String {
        if failed { return text("Couldn’t make a copy") }
        if !omissions.isEmpty { return text("Only part of your library was copied") }
        return text("Before updating your library")
    }

    private var summary: String {
        if notice == .diskFull { return text("There’s not enough space for the copy. Free some space, then try again.") }
        if failed { return text("Try again, or open the app without a copy just this once.") }
        if !omissions.isEmpty {
            return L10n.format("The copy reached its 128 MiB limit. Not fully copied: %@.", [
                omissions.map(omissionLabel).joined(separator: ", "),
            ], context: context)
        }
        return text("A copy of your launcher data is ready. It doesn’t include games or saves.")
    }

    var risk: String {
        let key = failed ? "Going back to Oort NX 0.3.0 without a copy may lose play time."
            : "If you go back to Oort NX 0.3.0, it won’t show play time recorded by the new version. Finish cloud transfers before going back."
        return text(key).replacingOccurrences(of: "Oort NX 0.3.0", with: "Oort\u{00a0}NX\u{00a0}0.3.0")
    }

    private func omissionLabel(_ item: DowngradeCheckpoint.Omission) -> String {
        switch item {
        case .sessions: return text("play history")
        case .catalog: return text("game list")
        case .settings: return text("settings")
        case .profiles: return text("profiles")
        case .queue: return text("transfer and build queues")
        case .preferences: return text("cloud status and connection settings")
        case .artwork: return text("artwork and metadata choices")
        case .sound: return text("sound packs")
        }
    }

    private func label(_ choice: Choice) -> String {
        switch choice {
        case .retry: "Retry"
        case .proceed: failed ? "Continue without a copy" : "Continue"
        case .folder: "Open library folder"
        case .quit: "Quit"
        }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: context) }

    private func perform(_ choice: Choice) {
        switch choice {
        case .retry: index = choices.count - 1; retry()
        case .proceed: proceed()
        case .folder: NSWorkspace.shared.open(AppData.supportRoot)
        case .quit: NSApplication.shared.terminate(nil)
        }
    }

    private func input(_ action: GamepadAction) {
        switch action {
        case .navigateLeft: index = max(0, index - 1)
        case .navigateRight: index = min(choices.count - 1, index + 1)
        case .confirm: perform(choices[index])
        case .cancel: perform(.quit)
        default: break
        }
    }
}

struct DowngradeCopyProgress: View {
    let context: AppLocale
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SeleneTokens.Space.compact) {
            WaveDots()
            Text(L10n.text("Checking the library copy…", context: context))
                .seleneFont(.text)
        }
        .foregroundStyle(SeleneTheme.ink75)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeleneTheme.baseGradient(for: theme.palette))
        .environment(\.seleneReduceMotion, reduceMotion)
        .onAppear { LaunchReveal.show() }
    }
}
