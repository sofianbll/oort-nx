import Observation
import ShellHost
import ShellModel
import SwiftUI

enum OortTab: String, CaseIterable, Hashable { case home, library, controllers, settings }

enum OortRoute: Hashable {
    case game(String), options(String), cheats(String), mapping(String?), padTest, activity, credits
}

/// Which screen is open, which one the controller drives, and whether the player is on it now.
@MainActor @Observable final class OortNav {
    var tab: OortTab
    var paths: [OortTab: [OortRoute]] = [:]
    var selected: String?
    var device: InputDevice?
    var importing = false
    private var screens: [UUID] = []
    @ObservationIgnored private var seen = 0
    @ObservationIgnored let sounds: OortSounds

    init(tab: OortTab = .home, route: [OortRoute] = [], selected: String? = nil, sounds: OortSounds) {
        (self.tab, self.selected, self.sounds) = (tab, selected, sounds)
        paths[tab] = route
    }

    func open(_ route: OortRoute) { paths[tab, default: []].append(route) }
    func back() -> Bool {
        guard paths[tab]?.isEmpty == false else { return false }
        paths[tab]?.removeLast()
        return true
    }

    func appeared(_ id: UUID) { screens.removeAll { $0 == id }; screens.append(id) }
    func left(_ id: UUID) { screens.removeAll { $0 == id } }

    /// Only the screen on top reads the controller. What it does not use opens a tab or goes back.
    func read(_ log: ShellInputLog, as id: UUID, _ handle: (ShellInput.Action) -> Bool) {
        guard screens.last == id else { return }
        let events = log.since(seen)
        seen = log.last
        for event in events where !event.released {
            device = event.device
            if handle(event.action) { continue }
            switch event.action {
            case .back:
                if back() { sounds.play(.back) } else if tab != .home { tab = .home; sounds.play(.back) } else { sounds.play(.deny) }
            case .controllers: show(.controllers)
            case .shellSettings: show(.settings)
            case .previousTab, .nextTab:
                let all = OortTab.allCases, step = event.action == .nextTab ? 1 : all.count - 1
                show(all[(all.firstIndex(of: tab)! + step) % all.count])
            default: break
            }
        }
    }

    private func show(_ next: OortTab) {
        tab = next
        sounds.play(.open)
    }
}

func direction(_ action: ShellInput.Action) -> MoveDirection {
    switch action { case .left: .left; case .right: .right; case .up: .up; default: .down }
}

extension View {
    /// The controller's presses on this screen, while it is the one on top. True: used.
    func oortInput(_ model: ShellHostModel, _ nav: OortNav, _ handle: @escaping (ShellInput.Action) -> Bool) -> some View {
        modifier(OortInput(model: model, nav: nav, handle: handle))
    }
}

private struct OortInput: ViewModifier {
    let model: ShellHostModel
    let nav: OortNav
    let handle: (ShellInput.Action) -> Bool
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { nav.appeared(id) }
            .onDisappear { nav.left(id) }
            .onChange(of: model.input.last) { nav.read(model.input, as: id, handle) }
    }
}

/// The controller's keys for what can be done here, drawn for the controller in hand. Touch hides them.
struct OortHints: View {
    let nav: OortNav
    let hints: [(action: ShellInput.Action, label: String)]
    var body: some View {
        if let device = nav.device {
            ViewThatFits(in: .horizontal) {
                row(device, hints)
                row(device, Array(hints.prefix(2)))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
    }

    private func row(_ device: InputDevice, _ hints: [(action: ShellInput.Action, label: String)]) -> some View {
        HStack(spacing: SeleneTokens.Space.panel) {
            ForEach(hints, id: \.label) { hint in
                HStack(spacing: SeleneTokens.Space.tight) {
                    Image(systemName: Self.symbol(hint.action, device)).foregroundStyle(Oort.ink)
                    Text(hint.label).foregroundStyle(Oort.ink2)
                }
            }
        }
        .font(.footnote.weight(.medium))
        .lineLimit(1)
        .fixedSize()
    }

    static func symbol(_ action: ShellInput.Action, _ device: InputDevice) -> String {
        if case .keyboard = device {
            return switch action { case .activate: "return"; case .back: "escape"; default: "keyboard" }
        }
        let playStation = device == .controller(.playStation)
        return switch action {
        case .activate: playStation ? "xmark.circle.fill" : "a.circle.fill"
        case .back: playStation ? "circle.circle.fill" : "b.circle.fill"
        case .settings: playStation ? "square.circle.fill" : "x.circle.fill"
        case .controllers: playStation ? "triangle.circle.fill" : "y.circle.fill"
        case .previousTab: "l.rectangle.roundedbottom.fill"
        case .nextTab: "r.rectangle.roundedbottom.fill"
        default: "dpad.fill"
        }
    }
}
