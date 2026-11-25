import Observation
import ShellHost
import ShellModel
import SwiftUI

enum OortTab: String, CaseIterable, Hashable { case home, library, controllers, settings }

enum OortRoute: Hashable {
    case game(String), options(String), cheats(String), mapping(String?), padTest, activity, credits, notices
}

/// Which screen is open, which one the controller drives, and whether the player is on it now.
@MainActor @Observable final class OortNav {
    var tab: OortTab
    var paths: [OortTab: [OortRoute]] = [:]
    var selected: String?
    var device: InputDevice?
    var importing = false
    /// The photo picker of a game's page.
    var picking = false
    /// A screen's own question, shown over the app.
    var question: OortQuestion?
    /// What the library searches, in the system's field (`typing`) or with Oort NX's letters for a controller.
    var query = ""
    var typing = false
    var letters = false
    /// The question or sheet that reads in place of every screen.
    @ObservationIgnored var asking: UUID?
    /// This press brought the ring back: on a list it does nothing else.
    @ObservationIgnored private(set) var revealing = false
    /// What the system laid over the app, as the way to close it. nil: nothing is over the app.
    @ObservationIgnored var cover: () -> (() -> Void)? = { nil }
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

    /// Only the screen on top reads the controller, or the question over it. What it does not use opens a tab or goes back.
    func read(_ log: ShellInputLog, as id: UUID, _ handle: (ShellInput.Action) -> Bool) {
        guard (asking ?? screens.last) == id else { return }
        let events = log.since(seen)
        seen = log.last
        for event in events where !event.released {
            revealing = device == nil
            device = event.device
            if asking == nil, let close = cover() {
                if event.action == .back { close(); sounds.play(.back) }
                continue
            }
            if handle(event.action) { continue }
            switch event.action {
            case .back:
                if back() { sounds.play(.back) } else if tab != .home { tab = .home; sounds.play(.back) } else { sounds.play(.deny) }
            case .controllers: show(.controllers)
            case .search: search()
            case .shellSettings: show(.settings)
            case .previousTab, .nextTab:
                let all = OortTab.allCases, step = event.action == .nextTab ? 1 : all.count - 1
                show(all[(all.firstIndex(of: tab)! + step) % all.count])
            default: break
            }
        }
    }

    /// The library, ready to be typed in: with the keyboard in hand, its own field.
    func search() {
        tab = .library
        paths[.library] = []
        if device == .keyboard { typing = true } else { letters = true }
        sounds.play(.open)
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

    /// The presses of a question or a sheet: while it is shown, no screen reads.
    func oortModalInput(_ model: ShellHostModel, _ nav: OortNav, _ handle: @escaping (ShellInput.Action) -> Bool) -> some View {
        modifier(OortInput(model: model, nav: nav, modal: true, handle: handle))
    }
}

private struct OortInput: ViewModifier {
    let model: ShellHostModel
    let nav: OortNav
    var modal = false
    let handle: (ShellInput.Action) -> Bool
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content
            .onAppear { if modal { nav.asking = id } else { nav.appeared(id) } }
            .onDisappear { if !modal { nav.left(id) } else if nav.asking == id { nav.asking = nil } }
            .onChange(of: model.input.last) { nav.read(model.input, as: id, handle) }
    }
}

/// The controller's keys for what can be done here, drawn for the controller in hand. Touch hides them.
struct OortHints: View {
    let nav: OortNav
    let hints: [(action: ShellInput.Action, label: String)]
    var body: some View {
        if let device = nav.device {
            // A keyboard has no key for L and R.
            let hints = device == .keyboard ? self.hints.filter { $0.action != .nextTab && $0.action != .previousTab } : self.hints
            let half = (hints.count + 1) / 2
            ViewThatFits(in: .horizontal) {
                row(device, hints)
                VStack(alignment: .trailing, spacing: SeleneTokens.Space.tight) {
                    row(device, Array(hints.prefix(half)))
                    row(device, Array(hints.dropFirst(half)))
                }
                VStack(alignment: .trailing, spacing: SeleneTokens.Space.tight) {
                    ForEach(hints, id: \.label) { row(device, [$0]) }
                }
            }
            .padding(.horizontal, SeleneTokens.Space.compact)
            .padding(.vertical, SeleneTokens.Space.tight)
            .background(Oort.night.opacity(0.9), in: RoundedRectangle(cornerRadius: Oort.key, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityHidden(true)
        }
    }

    private func row(_ device: InputDevice, _ hints: [(action: ShellInput.Action, label: String)]) -> some View {
        HStack(spacing: SeleneTokens.Space.panel) {
            ForEach(hints, id: \.label) { hint in
                HStack(spacing: SeleneTokens.Space.tight) {
                    // Both shoulders change the tab: both are shown.
                    if hint.action == .nextTab { Image(systemName: Self.symbol(.previousTab, device)).foregroundStyle(Oort.ink) }
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
            return switch action { case .activate: "return"; case .back: "escape"; case .settings: "o.square"; case .search: "y.square"; default: "keyboard" }
        }
        let playStation = device == .controller(.playStation)
        // The options are on + (Menu, Options): the button that opens them on every system.
        let menu = playStation || device == .controller(.xbox) ? "line.3.horizontal.circle.fill" : "plus.circle.fill"
        return switch action {
        case .activate: playStation ? "xmark.circle.fill" : "a.circle.fill"
        case .back: playStation ? "circle.circle.fill" : "b.circle.fill"
        case .settings: menu
        case .search: playStation ? "triangle.circle.fill" : "y.circle.fill"
        case .previousTab: "l.rectangle.roundedbottom.fill"
        case .nextTab: "r.rectangle.roundedbottom.fill"
        default: "dpad.fill"
        }
    }
}
