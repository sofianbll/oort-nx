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
    @StateObject private var controller = ControllerInput()
    @State private var index = 0
    @FocusState private var acceptsKeys: Bool

    private var failed: Bool { notice == .failed }
    private var choices: [Choice] { failed ? [.retry, .proceed, .quit] : [.proceed, .folder, .quit] }
    private var omissions: [DowngradeCheckpoint.Omission] {
        if case let .copy(omissions) = notice { return omissions }
        return []
    }

    var body: some View {
        VStack(spacing: SeleneTokens.Space.panel) {
            Text(title)
                .font(.system(size: SeleneTokens.Text.title.rawValue, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .font(.system(size: SeleneTokens.Text.body.rawValue))
            Text(failed ? text("Going back to Oort NX 0.3.0 without a copy may lose play time.")
                 : text("If you go back to Oort NX 0.3.0, it won’t show play time recorded by the new version. Finish cloud transfers before going back."))
                .font(.system(size: SeleneTokens.Text.compactCaption.rawValue))
            HStack(spacing: SeleneTokens.Space.large) {
                ForEach(choices.indices, id: \.self) { position in
                    let choice = choices[position]
                    if index == position {
                        Button(label(choice)) { perform(choice) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityAddTraits(.isSelected)
                    } else {
                        Button(label(choice)) { perform(choice) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .foregroundColor(.white)
        .padding(SeleneTokens.Space.group)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SeleneTheme.scrim)
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
        if failed { return text("Try again, or open the app without a copy just this once.") }
        if !omissions.isEmpty {
            return L10n.format("The copy reached its 128 MiB limit. Not fully copied: %@.", [
                omissions.map(omissionLabel).joined(separator: ", "),
            ], context: context)
        }
        return text("A copy of your launcher data is ready. It doesn’t include games or saves.")
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
        case .retry: text("Retry")
        case .proceed: failed ? text("Continue without a copy") : text("Continue")
        case .folder: text("Open library folder")
        case .quit: text("Quit")
        }
    }

    private func text(_ key: String) -> String { L10n.text(key, context: context) }

    private func perform(_ choice: Choice) {
        switch choice {
        case .retry: retry()
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
