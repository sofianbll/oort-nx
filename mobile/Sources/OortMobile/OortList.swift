import ShellHost
import ShellModel
import SwiftUI

/// One line of a list: what it says and what it does. Every list of the app is made of these.
struct OortRow: Identifiable {
    enum Kind {
        case info
        case button(() -> Void)
        case open(OortRoute)
        case toggle(Bool, (Bool) -> Void)
        case choice([SettingOption], String, (String) -> Void)
        case range(ClosedRange<Double>, step: Double, unit: String, String, (String) -> Void)
    }
    var id: String
    var title: String
    var value = ""
    var note = ""
    var symbol: String?
    var tint: Color?
    var changed = false
    var enabled = true
    var kind: Kind = .info

    /// Left and right change a value; A does what the row does.
    @MainActor func step(_ direction: Int) -> Bool {
        switch kind {
        case .toggle(let on, let set):
            guard on != (direction > 0) else { return false }
            set(!on)
        case .choice(let options, let value, let set):
            guard !options.isEmpty else { return false }
            let index = options.firstIndex { $0.id == value } ?? 0
            let next = min(max(index + direction, 0), options.count - 1)
            guard next != index else { return false }
            set(options[next].id)
        case .range(let bounds, let step, _, let value, let set):
            let now = Double(value) ?? bounds.lowerBound
            let next = min(max(now + Double(direction) * step, bounds.lowerBound), bounds.upperBound)
            guard abs(next - now) > step / 1000 else { return false }
            set(Self.number(next, step: step))
        case .info, .button, .open: return false
        }
        return true
    }

    /// As many decimals as the step has, as the engine's launcher writes them.
    static func number(_ value: Double, step: Double) -> String {
        var digits = 0
        while digits < 4, abs((step * pow(10, Double(digits))).rounded() - step * pow(10, Double(digits))) > 1e-6 { digits += 1 }
        return String(format: "%.\(max(digits, 1))f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// The same number as the player writes it.
    static func shown(_ value: Double, step: Double) -> String {
        number(value, step: step).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
}

struct OortSection: Identifiable {
    var id: String
    var title = ""
    var footer = ""
    var rows: [OortRow]
}

extension OortRow {
    /// A setting of a game's own list.
    init(_ row: SettingRow, set: @escaping (String) -> Void) {
        self.init(id: row.id, title: row.label, note: row.note, changed: row.changed, enabled: row.enabled)
        switch row.kind {
        case .toggle(let on, let off): kind = .toggle(row.value == on) { set($0 ? on : off) }
        case .choice(let options): kind = .choice(options, row.value, set)
        case .range(let low, let high, let step, let unit): kind = .range(low...high, step: step, unit: unit, row.value, set)
        }
        if row.fromEnvFile { note += (note.isEmpty ? "" : "\n") + Oort.text("Set in env.txt") }
    }
}

/// The app's list: system controls on Oort's panels, and the same rows under the controller.
struct OortList<Header: View>: View {
    let model: ShellHostModel
    let nav: OortNav
    let title: String
    let sections: [OortSection]
    var backdrop = true
    @ViewBuilder var header: Header
    @State private var focus = FocusGrid<String>()

    private var rows: [OortRow] { sections.flatMap(\.rows) }

    var body: some View {
        ScrollViewReader { scroll in
            List {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                ForEach(sections) { section in
                    Section {
                        ForEach(section.rows) { row in
                            OortRowView(row: row, focused: nav.device != nil && focus.current == row.id, open: nav.open) { nav.sounds.play(.select) }
                                .id(row.id)
                                .listRowBackground(background(row))
                                .listRowInsets(EdgeInsets(top: SeleneTokens.Space.tight, leading: SeleneTokens.Space.medium,
                                                          bottom: SeleneTokens.Space.tight, trailing: SeleneTokens.Space.medium))
                                .listRowSeparatorTint(Oort.line)
                        }
                    } header: {
                        if !section.title.isEmpty { Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(Oort.ink2).textCase(nil) }
                    } footer: {
                        if !section.footer.isEmpty { Text(section.footer).foregroundStyle(Oort.ink2) }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            // On a wide screen the lines stay readable and the cloud keeps the right.
            .frame(maxWidth: Oort.Measure.list)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { if backdrop { OortBackdrop(strength: 0.5) } }
            .modifier(OortTitle(title: title))
            .tint(Oort.glyph)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OortHints(nav: nav, hints: [(.activate, Oort.text("Select")), (.back, Oort.text("Back"))])
                    .padding(.horizontal, SeleneTokens.Space.large)
                    .padding(.vertical, nav.device == nil ? 0 : SeleneTokens.Space.compact)
            }
            .oortInput(model, nav) { action in
                let moved: Bool
                switch action {
                case .up, .down: moved = focus.move(direction(action), in: rows.filter { $0.enabled && !$0.isInfo }.map { [$0.id] })
                case .left, .right:
                    guard let row = rows.first(where: { $0.id == focus.current }) else { return true }
                    nav.sounds.play(row.step(action == .right ? 1 : -1) ? .select : .deny)
                    return true
                case .activate:
                    guard let row = rows.first(where: { $0.id == focus.current }) else { return true }
                    activate(row)
                    return true
                default: return false
                }
                if moved {
                    nav.sounds.play(.move)
                    withAnimation(.snappy) { scroll.scrollTo(focus.current, anchor: .center) }
                }
                return true
            }
        }
    }

    private func background(_ row: OortRow) -> some View {
        let focused = nav.device != nil && focus.current == row.id
        return (focused ? Oort.panelRaised : Oort.panelHigh).overlay(alignment: .leading) {
            if focused { OortDots(rise: 1, color: Oort.glyph.opacity(0.10)) }
        }
    }

    private func activate(_ row: OortRow) {
        nav.sounds.play(.select)
        switch row.kind {
        case .info: break
        case .button(let run): run()
        case .open(let route): nav.open(route)
        case .toggle(let on, let set): set(!on)
        case .choice(let options, let value, let set):
            guard let index = options.firstIndex(where: { $0.id == value }) ?? options.indices.first else { return }
            set(options[(index + 1) % options.count].id)
        case .range: break
        }
    }
}

private struct OortTitle: ViewModifier {
    let title: String
    func body(content: Content) -> some View {
        if title.isEmpty { content } else { content.navigationTitle(title) }
    }
}

extension OortRow {
    var isInfo: Bool { if case .info = kind { true } else { false } }
}

private struct OortRowView: View {
    let row: OortRow
    let focused: Bool
    let open: (OortRoute) -> Void
    let pressed: () -> Void
    @Environment(\.dynamicTypeSize) private var type
    @ScaledMetric(relativeTo: .body) private var symbolWidth = 26

    var body: some View {
        control
            .disabled(!row.enabled)
            .padding(.vertical, SeleneTokens.Space.tight)
            .frame(minHeight: 44)
            .accessibilityAddTraits(focused ? .isSelected : [])
    }

    @ViewBuilder private var control: some View {
        switch row.kind {
        case .info:
            values
        case .button(let run):
            Button { pressed(); run() } label: { values.frame(minHeight: 44).contentShape(.rect) }
                .buttonStyle(.plain)
        case .open(let route):
            Button { pressed(); open(route) } label: {
                HStack {
                    values
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Oort.ink2).accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        case .toggle(let on, let set):
            Toggle(isOn: Binding(get: { on }, set: { pressed(); set($0) })) { label }.toggleStyle(OortToggleStyle())
        case .choice(let options, let value, let set):
            Picker(selection: Binding(get: { value }, set: { pressed(); set($0) })) {
                ForEach(options) { Text($0.label).tag($0.id) }
                // A saved value the list does not offer reads as itself, not as the first option.
                if !options.contains(where: { $0.id == value }) { Text("—").tag(value) }
            } label: { label }
            .pickerStyle(.menu)
        case .range(let bounds, let step, let unit, let value, let set):
            let number = Double(value) ?? bounds.lowerBound
            VStack(alignment: .leading, spacing: SeleneTokens.Space.tight) {
                HStack { label; Spacer(); Text(OortRow.shown(number, step: step) + unit).foregroundStyle(Oort.ink2).monospacedDigit() }
                    .accessibilityHidden(true)
                OortSlider(value: Binding(get: { number }, set: { set(OortRow.number($0, step: step)) }), bounds: bounds, step: step, title: row.title,
                           text: OortRow.shown(number, step: step) + unit)
            }
        }
    }

    private var values: some View {
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            label
            if !row.value.isEmpty {
                if !type.isAccessibilitySize { Spacer(minLength: SeleneTokens.Space.small) }
                Text(row.value).foregroundStyle(Oort.ink2).multilineTextAlignment(type.isAccessibilitySize ? .leading : .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: SeleneTokens.Space.small) {
            if let symbol = row.symbol {
                Image(systemName: symbol).foregroundStyle(row.tint ?? Oort.glyph).frame(width: symbolWidth).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: SeleneTokens.Space.seam) {
                HStack(spacing: SeleneTokens.Space.tight) {
                    Text(row.title).foregroundStyle(row.tint ?? Oort.ink)
                    if row.changed {
                        Circle().fill(Oort.glyph).frame(width: 7, height: 7).accessibilityLabel(Oort.text("Changed"))
                    }
                }
                if !row.note.isEmpty { Text(row.note).font(.footnote).foregroundStyle(Oort.ink2) }
            }
        }
    }
}
