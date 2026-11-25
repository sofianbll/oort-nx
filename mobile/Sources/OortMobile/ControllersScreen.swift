import OortCore
import ShellHost
import ShellModel
import SwiftUI

/// The controllers in hand, what their buttons send, and the touch controls for when there is none.
struct ControllersScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    @State private var changes = 0

    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Controllers"), sections: sections) { EmptyView() }
    }

    private var sections: [OortSection] {
        _ = changes
        let a = model.actions, store = model.shellSettings
        func choice(_ id: String, _ title: String, _ values: [(String, String)], _ value: String, _ set: @escaping (String) -> Void) -> OortRow {
            OortRow(id: id, title: title, kind: .choice(values.map { SettingOption($0.0, $0.1) }, value) { set($0); changes += 1; model.refreshAll() })
        }
        var connected = model.controllers.map { pad in
            OortRow(id: pad.id, title: pad.name,
                    value: [pad.player, pad.batteryPercent.map { "\($0) %" }].compactMap { $0 }.joined(separator: "  ·  "),
                    symbol: pad.charging ? "bolt.fill" : "gamecontroller.fill")
        }
        if connected.isEmpty {
            connected = [OortRow(id: "none", title: Oort.text("No controller connected"),
                                 note: Oort.text("Pair one in Settings, Bluetooth. Touch works everywhere meanwhile."), symbol: "gamecontroller")]
        }
        return [
            OortSection(id: "pads", title: Oort.text("Connected"), rows: connected + [
                OortRow(id: "test", title: Oort.text("Try the buttons"), symbol: "circle.grid.cross", enabled: !model.controllers.isEmpty, kind: .open(.padTest)),
            ]),
            OortSection(id: "map", title: Oort.text("Buttons"), footer: Oort.text("For every game. A game can have its own on its page."), rows: [
                OortRow(id: "mapping", title: Oort.text("What each button sends"),
                        value: model.globalPadMap.entries.isEmpty ? Oort.text("As printed") : Oort.text("Changed"), symbol: "arrow.left.arrow.right", kind: .open(.mapping(nil))),
                OortRow(id: "merge", title: Oort.text("All controllers are player 1"), symbol: "person.2",
                        kind: .toggle(model.padMerge) { a.onPadMergeChange($0) }),
                OortRow(id: "homebutton", title: Oort.text("Home button, in iOS Settings"), symbol: "house", kind: .button { a.onOpenHomeButtonSettings() }),
            ]),
            OortSection(id: "touch", title: Oort.text("Touch controls"), footer: Oort.text("Shown over a game when no controller is connected."), rows: [
                choice("size", Oort.text("Size"), [("small", Oort.text("Small")), ("medium", Oort.text("Medium")), ("large", Oort.text("Large"))], store.touchSize, store.storeTouchSize),
                choice("stick", Oort.text("Left stick"), [("corner", Oort.text("In the corner")), ("higher", Oort.text("Higher")), ("inward", Oort.text("Further in"))], store.touchStick, store.storeTouchStick),
                choice("mode", Oort.text("Made for"), [("3d", Oort.text("3D games")), ("2d", Oort.text("2D games"))], store.touchMode, store.storeTouchMode),
            ]),
        ]
    }
}

/// What each button sends, for every game or for one.
struct MappingScreen: View {
    let id: String?
    let model: ShellHostModel
    let nav: OortNav

    var body: some View {
        OortList(model: model, nav: nav, title: Oort.text("Buttons"), sections: sections) {
            Text(Oort.text("Buttons are named as on a Switch controller, by where they are.")).font(.footnote).foregroundStyle(Oort.ink2)
                .padding(.vertical, SeleneTokens.Space.compact)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var sections: [OortSection] {
        let a = model.actions
        let rows: [SettingRow], set: (String, String) -> Void, reset: () -> Void
        if let id {
            rows = model.details.first { $0.id == id }?.sections.first { $0.id == PadMappingRows.sectionID }?.rows ?? []
            set = { a.onChange(id, $0, $1) }
            reset = { a.onChange(id, PadMappingRows.resetID, "") }
        } else {
            rows = PadMappingRows.global(model.globalPadMap)
            set = a.onGlobalPadMapChange
            reset = a.onGlobalPadMapReset
        }
        func line(_ row: SettingRow, _ button: String?) -> OortRow {
            var line = OortRow(row) { set(row.id, $0) }
            if let button {
                line.title = button == "Plus" ? "+" : button == "Minus" ? "−" : PadMap.buttons.prefix(4).contains(button) ? button : PadMap.label(button)
                let place = PadMap.placeName(button)
                line.note = place == line.title ? "" : place
            }
            line.changed = !row.fromShell
            return line
        }
        var result: [OortSection] = []
        if let swap = rows.first { result.append(OortSection(id: "swap", rows: [line(swap, nil)])) }
        for group in PadMap.buttonGroups {
            let members = group.buttons.compactMap { button in rows.dropFirst().first { $0.id == button || $0.id == "pad.\(button)" }.map { line($0, button) } }
            if !members.isEmpty { result.append(OortSection(id: group.title, title: group.title, rows: members)) }
        }
        result.append(OortSection(id: "reset", rows: [OortRow(id: "reset", title: Oort.text("Back to the buttons as printed"), symbol: "arrow.counterclockwise", kind: .button(reset))]))
        return result
    }
}

/// Each button lights where it is on the controller. Holding B closes, so every button can be tried.
struct PadTestScreen: View {
    let model: ShellHostModel
    let nav: OortNav
    @State private var held: Task<Void, Never>?
    private var pad: PadSnapshot { model.padSnapshot ?? PadSnapshot() }

    var body: some View {
        VStack(spacing: SeleneTokens.Space.section) {
            Spacer(minLength: 0)
            Text(pad.name.isEmpty ? Oort.text("Press a button") : pad.name).font(.title2.bold()).foregroundStyle(Oort.ink)
            OortPadView(press: { pad.pressed.contains(Self.element($0)) ? 1 : 0 }, left: pad.leftStick, right: pad.rightStick,
                        shoulders: [pad.pressed.contains(.leftBumper) ? 1 : 0, pad.leftTrigger, pad.pressed.contains(.rightBumper) ? 1 : 0, pad.rightTrigger])
                .padding(SeleneTokens.Space.large)
                .oortPanel(radius: SeleneTokens.Radius.dialog)
                .frame(maxWidth: 560)
            Text(Oort.text("Hold the bottom or right button to close.")).font(.footnote).foregroundStyle(Oort.ink2)
            Spacer(minLength: 0)
        }
        .padding(SeleneTokens.Space.panel)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { OortBackdrop(strength: 0.35) }
        .navigationTitle(Oort.text("Try the buttons"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { model.actions.onButtonTest(true) }
        .onDisappear { model.actions.onButtonTest(false); held?.cancel() }
        .onChange(of: pad.pressed.contains(.b) || pad.pressed.contains(.a)) { _, down in
            held?.cancel()
            guard down else { return }
            held = Task {
                try? await Task.sleep(for: .seconds(1.2))
                if !Task.isCancelled { nav.sounds.play(.back); _ = nav.back() }
            }
        }
        .oortInput(model, nav) { _ in true }
    }

    /// The buttons by where they are: the host names them as on an Xbox controller.
    private static func element(_ place: OortPadShape.Place) -> PadElement {
        switch place {
        case .leftStick: .leftStick
        case .rightStick: .rightStick
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .top: .y
        case .west: .x
        case .east: .b
        case .bottom: .a
        case .view: .view
        case .menu: .menu
        case .home: .home
        }
    }
}
