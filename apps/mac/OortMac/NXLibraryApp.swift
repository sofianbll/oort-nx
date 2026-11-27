import OortLibrary
import SwiftUI

extension Notification.Name {
    static let nxLibraryPlayFocused = Notification.Name("NXLibraryPlayFocused")
    static let nxLibraryCheckAppUpdates = Notification.Name("NXLibraryCheckAppUpdates")
    /// The object is the words already typed elsewhere, if any.
    static let nxLibraryOpenPalette = Notification.Name("NXLibraryOpenPalette")
    static let nxLibraryOpenMenu = Notification.Name("NXLibraryOpenMenu")
    static let nxSettingsGamepadAction = Notification.Name("NXSettingsGamepadAction")
    static let nxSettingsDecisionInput = Notification.Name("NXSettingsDecisionInput")
    static let nxLocalePickerGamepadAction = Notification.Name("NXLocalePickerGamepadAction")
    static let nxAddGameGamepadAction = Notification.Name("NXAddGameGamepadAction")
    static let nxConsoleGamepadAction = Notification.Name("NXConsoleGamepadAction")
    static let nxLaunchScreenExit = Notification.Name("NXLaunchScreenExit")
    static let nxDetailGamepadAction = Notification.Name("NXDetailGamepadAction")
    static let nxSpotlightGamepadAction = Notification.Name("NXSpotlightGamepadAction")
    static let nxCollectionGamepadAction = Notification.Name("NXCollectionGamepadAction")
    static let nxInterfaceZoom = Notification.Name("NXInterfaceZoom")
    static let nxGameOptionsGamepadAction = Notification.Name("NXGameOptionsGamepadAction")
    static let nxSetupCheckGamepadAction = Notification.Name("NXSetupCheckGamepadAction")
    static let nxArcaneWelcomeGamepadAction = Notification.Name("NXArcaneWelcomeGamepadAction")
    static let nxThemePickerGamepadAction = Notification.Name("NXThemePickerGamepadAction")
    static let nxLibraryOpenSettings = Notification.Name("NXLibraryOpenSettings")
    static let nxLibraryRetryCatalogSave = Notification.Name("NXLibraryRetryCatalogSave")
    static let nxLibraryOpenConsole = Notification.Name("NXLibraryOpenConsole")
    static let nxLibraryOpenLibrary = Notification.Name("NXLibraryOpenLibrary")
    static let nxLibraryOpenAddGame = Notification.Name("NXLibraryOpenAddGame")
    static let nxLibraryAddMacApp = Notification.Name("NXLibraryAddMacApp")
    static let nxGameSettingsRestored = Notification.Name("NXGameSettingsRestored")
    static let nxLibraryUndoChange = Notification.Name("NXLibraryUndoChange")
    static let nxLibraryOpenDetails = Notification.Name("NXLibraryOpenDetails")
    static let nxLibraryOpenGameOptions = Notification.Name("NXLibraryOpenGameOptions")
}

@main
struct NXLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @FocusedValue(\.nxMenuAvailability) private var availability
    @ObservedObject private var localization = AppLocalization.shared

    #if DEBUG
    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--render-file-picker") {
            precondition(args.indices.contains(index + 1), "Pass a directory for the file picker PNGs")
            try! OortFilePickerProbe.capture(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            exit(EXIT_SUCCESS)
        }
        if let index = args.firstIndex(of: "--render-command-palette") {
            precondition(args.indices.contains(index + 1), "Pass a directory for the palette PNGs")
            try! CommandPaletteProbe.capture(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            exit(0)
        }
        if let index = args.firstIndex(of: "--render-keyboard") {
            precondition(args.indices.contains(index + 1), "Pass a directory for the keyboard PNGs")
            try! OortKeyboardProbe.run(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            exit(EXIT_SUCCESS)
        }
        if let index = args.firstIndex(of: "--render-oort-ui-gallery") {
            precondition(args.indices.contains(index + 1), "Pass a directory for the gallery PNGs")
            try! OortUIGallery.capture(to: URL(fileURLWithPath: args[index + 1], isDirectory: true))
            exit(EXIT_SUCCESS)
        }
        if let index = args.firstIndex(where: { ["--render-integration-fixture", "--render-sound-fixture", "--render-onboarding-fixture"].contains($0) }) {
            precondition(index + 1 < CommandLine.arguments.count, "Pass a directory for the fixture PNGs")
            try! IntegrationFixtureView.capture(to: URL(fileURLWithPath: args[index + 1], isDirectory: true),
                                                soundOnly: args[index] == "--render-sound-fixture",
                                                onboardingOnly: args[index] == "--render-onboarding-fixture")
            exit(EXIT_SUCCESS)
        }
    }
    #endif

    var body: some Scene {
        Window(windowTitle, id: windowID) {
            startup
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("Add Game…")) { NativeMenuCommands.shared.post(.nxLibraryOpenAddGame) }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(availability?.general != true)
            }
            CommandGroup(after: .newItem) {
                if availability?.catalogRecovery == true {
                    Button(L10n.text("Retry saving library")) { NativeMenuCommands.shared.post(.nxLibraryRetryCatalogSave) }
                        .keyboardShortcut("s", modifiers: [.command])
                }
            }
            CommandGroup(after: .undoRedo) {
                Button(L10n.text("Undo Last Change")) { NativeMenuCommands.shared.post(.nxLibraryUndoChange) }
                    .disabled(availability?.undo != true)
            }
            CommandGroup(after: .appInfo) {
                Button(L10n.text("Check for Updates…")) { NativeMenuCommands.shared.post(.nxLibraryCheckAppUpdates) }
                    .disabled(availability?.general != true)
            }
            CommandGroup(replacing: .appSettings) {
                Button(L10n.text("Settings…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenSettings)
                }
                .keyboardShortcut(",", modifiers: [.command])
                .disabled(availability?.general != true)
            }
            CommandMenu("Game") {
                Button(L10n.text("Add Game…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenAddGame)
                }
                .disabled(availability?.general != true)
                Button(L10n.text("Add an app…")) { NativeMenuCommands.shared.post(.nxLibraryAddMacApp) }
                    .disabled(availability?.addMacApp != true)
                Divider()
                Button(L10n.text("Play Selected Game")) {
                    NativeMenuCommands.shared.post(.nxLibraryPlayFocused)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(availability?.play != true)
                Divider()
                Button(L10n.text("Game Details")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenDetails)
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(availability?.details != true)
                Button(L10n.text("Game Options…")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenGameOptions)
                }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(availability?.options != true)
            }
            CommandGroup(after: .sidebar) {
                ForEach([("Larger interface", 1, "+"), ("Smaller interface", -1, "-"), ("Actual size", 0, "0")], id: \.1) { title, steps, key in
                    Button(L10n.text(title)) {
                        NotificationCenter.default.post(name: .nxInterfaceZoom, object: steps)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(key)), modifiers: [.command])
                }
                Button(L10n.text("Search everywhere")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenPalette)
                }
                .keyboardShortcut("k", modifiers: [.command])
                .disabled(availability?.palette != true)
                Button(L10n.text("Menu")) {
                    NativeMenuCommands.shared.post(.nxLibraryOpenMenu)
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(availability?.general != true)
            }
        }
    }

    private var windowTitle: String {
        #if DEBUG
        if AppData.integrationFixtureHome != nil { return "Oort NX · Fixture" }
        #endif
        return AppIdentity.displayName
    }

    private var windowID: String {
        #if DEBUG
        if AppData.integrationFixtureHome != nil { return "integration-fixture" }
        #endif
        return "main"
    }

    @ViewBuilder private var startup: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--oort-ui-gallery") { OortUIGallery() }
        else if AppData.integrationFixtureHome != nil { IntegrationFixtureView() }
        else { DevelopmentStartupView() }
        #else
        DevelopmentStartupView()
        #endif
    }
}
