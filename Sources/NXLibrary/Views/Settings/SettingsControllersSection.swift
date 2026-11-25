import SwiftUI
import NXLibraryCore

struct SettingsControllersSection: View {
    @ObservedObject var settings: SettingsEditor
    let onActions: ([SettingsRowAction]) -> Void
    let onViewControls: () -> Void
    var onOpenPlayers: (() -> Void)?

    @ObservedObject var controller = GameControllerService.shared
    private var draftDeadzone: Double { settings.settings.launcherChoices.controllerDeadzone ?? controller.legacyDeadzone }
    private var layout: GamepadLayout { .init(settings.settings) }

    var body: some View {
        OortSettingsGroup {
            SettingsSubheading(L10n.text("Library controls"))
            SeleneRow("Gamepad",
                      subtitle: controller.isGamepadConnected
                        ? controller.activeControllerName
                        : "Connect a controller and press Detect.") {
                HStack(spacing: SeleneTokens.Space.gap) {
                    Text(controller.isGamepadConnected ? L10n.text("Connected") : L10n.text("Not connected"))
                        .seleneFont(.badge, .semibold)
                        .foregroundColor(controller.isGamepadConnected ? SeleneTheme.success : SeleneTheme.ink60)
                    Button(L10n.text("Detect")) { controller.refreshControllers() }
                        .buttonStyle(.plain)
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }

            SeleneCycleRow("Controller layout", value: layout.title, cycle: stepLayout)
            let pad = ConnectedPad(connected: controller.isGamepadConnected, brand: controller.activeBrand)
            SeleneRow("While browsing", subtitle: layout.guide(hasHome: controller.homeAccess.hasHome).filter {
                [.menu, .view, .y, .home].contains($0.prompt)
            }.map { $0.summary(style: settings.settings.buttonNames, pad: pad) }.joined(separator: "   |   "),
                      verbatimSubtitle: true) { EmptyView() }
            if controller.canOpenHomeSettings {
                SeleneButtonRow("Home Button Overrides", subtitle: controller.homeAccess.title,
                                buttonTitle: "Open System Settings", action: controller.openHomeSettings)
            } else {
                SeleneRow("Home Button Overrides", subtitle: controller.homeAccess.title) { EmptyView() }
            }
            SeleneButtonRow("Button layout",
                            subtitle: "Library & game",
                            buttonTitle: "View") {
                onViewControls()
            }

            SeleneRow("Stick navigation deadzone",
                      subtitle: "Library navigation",
                      info: "Adjusts minimum thumbstick deflection needed to trigger menu navigation. Increase if your analog stick has slight drift causing unintended scrolling.") {
                HStack(spacing: SeleneTokens.Space.gap) {
                    Slider(value: Binding(
                        get: { draftDeadzone },
                        set: setDeadzone
                    ), in: 0.10...0.80, step: 0.01)
                    .frame(width: 170)
                    Text(String(format: "%.2f", draftDeadzone))
                        .seleneFont(.badge, .semibold, design: .monospaced)
                        .foregroundColor(SeleneTheme.glyph)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            SettingsSubheading(L10n.text("In game"))
            if let onOpenPlayers {
                SeleneButtonRow("Players", buttonTitle: "Open", action: onOpenPlayers)
            }
            SeleneCycleRow("Home button in games", subtitle: "Auto follows the controller layout.",
                           value: settings.settings.inGameHomeButton.title, cycle: stepHomeButton)
        }
        .onAppear(perform: publishActions)
        .onChange(of: controller.deadzone) { publishActions() }
        .onChange(of: controller.homeAccess) { publishActions() }
    }

    private func publishActions() {
        onActions([
            .init(id: "detect", title: "Gamepad") {
                controller.refreshControllers()
            },
            .value("controllerLayout", "Controller layout", cycle: stepLayout),
            .init(id: "layout", title: "Button layout") {
                onViewControls()
            },
            .value("deadzone", "Stick navigation deadzone") { step in
                setDeadzone(min(0.80, max(0.10, (draftDeadzone * 100 + 5 * Double(step)).rounded() / 100)))
            },
        ] + (onOpenPlayers.map { action in [.init(id: "players", title: "Players", activate: action)] } ?? [])
          + [.value("inGameHomeButton", "Home button in games", cycle: stepHomeButton)]
          + (controller.canOpenHomeSettings
             ? [.init(id: "systemHome", title: "Home Button Overrides", activate: controller.openHomeSettings)] : []))
    }

    private func setDeadzone(_ value: Double) {
        let unset = settings.store.settings.launcherChoices.controllerDeadzone == nil
        settings.settings.launcherChoices.controllerDeadzone = unset && value == controller.legacyDeadzone ? nil : value
    }

    private func stepHomeButton(_ step: Int) {
        settings.settings.inGameHomeButton = settings.settings.inGameHomeButton.stepped(step)
    }

    private func stepLayout(_ step: Int) {
        let layouts = GamepadLayout.allCases
        let index = layouts.firstIndex(of: layout) ?? 0
        settings.settings.launcherChoices.gamepadLayout = layouts[(index + step % layouts.count + layouts.count) % layouts.count].rawValue
    }
}
