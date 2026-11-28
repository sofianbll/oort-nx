import SwiftUI
import OortLibrary

extension EnvironmentValues {
    @Entry var settingsRowChanges: [String: AppSettingsDraft.Change] = [:]
}

/// The one help open on a screen, so a key opens the focused row's help as a click does.
extension EnvironmentValues {
    @Entry var seleneOpenHelp: Binding<String?>? = nil
}

/// The row whose help the key opens: the focused one, when it has a help.
struct SeleneFocusedHelpKey: PreferenceKey {
    static let defaultValue: String? = nil
    static func reduce(value: inout String?, nextValue: () -> String?) { value = value ?? nextValue() }
}

/// An info button: a click shows `text` beside it. Pass `isShowing` for a screen that also opens it from the
/// keyboard or a controller.
struct SeleneInfoTip: View {
    @Environment(\.nxAppLocale) private var localization
    let text: String
    private let shown: Binding<Bool>?
    /// The row this help belongs to, when the screen's help key can open it.
    private let row: String?
    private let focused: Bool
    @State private var shownHere = false
    @Environment(\.seleneOpenHelp) private var openHelp

    init(_ text: String, isShowing: Binding<Bool>? = nil, row: String? = nil, focused: Bool = false) {
        self.text = text
        self.shown = isShowing
        self.row = row
        self.focused = focused
    }

    private var isShowing: Binding<Bool> {
        if let shown { return shown }
        guard let row, let openHelp else { return $shownHere }
        return Binding(get: { openHelp.wrappedValue == row }, set: { openHelp.wrappedValue = $0 ? row : nil })
    }

    var body: some View {
        Button {
            isShowing.wrappedValue.toggle()
        } label: {
            Image(systemName: "info.circle")
                .seleneFont(.text, .semibold)
                .foregroundColor(isShowing.wrappedValue ? SeleneTheme.glyph : SeleneTheme.ink60.opacity(SeleneTokens.Alpha.heavy))
                .padding(SeleneTokens.Space.seam)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isShowing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: SeleneTokens.Space.tight) {
            Text(L10n.text(text, context: localization))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink.opacity(SeleneTokens.Alpha.near))
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(SeleneTokens.Space.line)
            .frame(width: 290, alignment: .leading)
            .background(SeleneTheme.glassSolid)
        }
        .help(L10n.text(text, context: localization))
        .accessibilityLabel(L10n.text("Information", context: localization))
        .accessibilityHint(L10n.text(text, context: localization))
        .preference(key: SeleneFocusedHelpKey.self, value: focused ? row : nil)
    }
}

struct SeleneRow<Trailing: View>: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.settingsRowChanges) private var pending
    let rowID: String
    let title: String
    let subtitle: String?
    let info: String?
    let verbatimTitle: Bool
    let verbatimSubtitle: Bool
    private let truncateSubtitleInMiddle: Bool
    private let platform: PlatformKind?
    private let formatBadges: [String]
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.seleneFocusedRowID) private var focusedRowID

    init(_ title: String, id: String? = nil, subtitle: String? = nil, info: String? = nil,
         verbatimTitle: Bool = false, verbatimSubtitle: Bool = false,
         truncateSubtitleInMiddle: Bool = false, platform: PlatformKind? = nil, formatBadges: [String] = [],
                @ViewBuilder trailing: @escaping () -> Trailing) {
        self.rowID = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.verbatimTitle = verbatimTitle
        self.verbatimSubtitle = verbatimSubtitle
        self.truncateSubtitleInMiddle = truncateSubtitleInMiddle
        self.platform = platform
        self.formatBadges = formatBadges
        self.trailing = trailing
    }

    private var isFocused: Bool { focusedRowID == rowID }

    var body: some View {
        let change = pending[rowID]
        let previous = change.map { L10n.format("Was: %@", [$0.before], context: localization) }
        let original = verbatimSubtitle ? subtitle : subtitle.map { L10n.text($0, context: localization) }
        let about = [original, previous].compactMap { $0 }.joined(separator: " · ")
        SeleneOptionRow(icon: nil, title: verbatimTitle ? title : L10n.text(title, context: localization),
                        about: about.isEmpty ? nil : about, focused: isFocused,
                        titleAccessory: change.map { _ in AnyView(SeleneStatusMark(color: SeleneTheme.glyph, pulses: false)) },
                        truncateAboutInMiddle: truncateSubtitleInMiddle && change == nil, platform: platform,
                        aboutIsHelp: !verbatimSubtitle, formatBadges: formatBadges) {
            HStack(spacing: SeleneTokens.Space.gap) {
                if let info {
                    SeleneInfoTip(info, row: rowID, focused: isFocused)
                }
                trailing()
            }
        }
        .id("selene-row-\(rowID)")
    }
}

struct SeleneToggleStyle: ToggleStyle {
    init() {}
    func makeBody(configuration: Configuration) -> some View {
        SeleneSwitch(isOn: configuration.$isOn)
    }
}

struct SeleneToggleRow: View {
    let title: String
    let subtitle: String?
    let info: String?
    let platform: PlatformKind?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, info: String? = nil, platform: PlatformKind? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.platform = platform
        self._isOn = isOn
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info, platform: platform) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(SeleneToggleStyle())
        }
    }
}

struct SeleneValueRow: View {
    let title: String
    let subtitle: String?
    let info: String?
    let value: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ title: String, subtitle: String? = nil, info: String? = nil, value: String,
                actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.value = value
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info) {
            HStack(spacing: SeleneTokens.Space.gap) {
                SeleneValueChip(text: value)
                if let actionTitle, let action {
                    Button(L10n.text(actionTitle), action: action)
                        .buttonStyle(.plain)
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph)
                }
            }
        }
    }
}

struct SeleneButtonRow: View {
    @Environment(\.nxAppLocale) private var localization
    let rowID: String
    let title: String
    let subtitle: String?
    let info: String?
    let buttonTitle: String
    let verbatimTitle: Bool
    let verbatimSubtitle: Bool
    private let truncateSubtitleInMiddle: Bool
    private let platform: PlatformKind?
    let action: () -> Void

    init(_ title: String, id: String? = nil, subtitle: String? = nil, info: String? = nil,
         verbatimTitle: Bool = false, verbatimSubtitle: Bool = false,
         truncateSubtitleInMiddle: Bool = false, platform: PlatformKind? = nil,
                buttonTitle: String, action: @escaping () -> Void) {
        self.rowID = id ?? title
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.verbatimTitle = verbatimTitle
        self.verbatimSubtitle = verbatimSubtitle
        self.truncateSubtitleInMiddle = truncateSubtitleInMiddle
        self.platform = platform
        self.buttonTitle = buttonTitle
        self.action = action
    }

    var body: some View {
        SeleneRow(title, id: rowID, subtitle: subtitle, info: info, verbatimTitle: verbatimTitle, verbatimSubtitle: verbatimSubtitle,
                  truncateSubtitleInMiddle: truncateSubtitleInMiddle, platform: platform) {
            Button(L10n.text(buttonTitle, context: localization), action: action)
                .buttonStyle(.plain)
                .seleneFont(.text, .semibold)
                .foregroundColor(SeleneTheme.glyph)
        }
    }
}

struct OortSegmented<Value: Hashable>: View {
    enum Preset { case compact, modeBar }
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Namespace private var pill
    @State private var hover = SeleneHoverFocus()
    @Binding var selection: Value
    let options: [(Value, String)]
    var preset: Preset = .compact
    var focused: Value? = nil
    var hint: (Value) -> String = { _ in "" }
    var onFocus: (Value) -> Void = { _ in }

    var body: some View {
        HStack(spacing: SeleneTokens.Space.segmentInset) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = selection == option.0
                let active = focused == option.0
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .seleneFont(preset == .compact ? .text : .row, .semibold)
                        .foregroundColor(selected ? (preset == .compact ? SeleneTheme.scrim : SeleneTheme.onFocus)
                                         : (preset == .compact ? SeleneTheme.ink.opacity(SeleneTokens.Alpha.half) : SeleneTheme.ink75))
                        .padding(.horizontal, SeleneTokens.Space.small)
                        .padding(.vertical, SeleneTokens.Space.tight)
                        .background {
                            if selected {
                                Capsule().fill(SeleneTheme.focus).matchedGeometryEffect(id: "selection", in: pill)
                            }
                        }
                }
                .buttonStyle(OortPressStyle())
                .padding(preset == .compact ? 0 : SeleneTokens.Space.seam)
                .overlay(PillOutline(width: SeleneTokens.Space.focusStroke)
                    .fill(active ? SeleneTheme.focus : .clear, style: FillStyle(eoFill: true))
                    .allowsHitTesting(false))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(hint(option.0))
                .help(hint(option.0))
                .onHover { if hover.moved($0) { onFocus(option.0) } }
            }
        }
        .padding(SeleneTokens.Space.segmentInset)
        .background(Capsule().fill(SeleneTheme.panelRaised))
        .overlay(PillOutline(width: SeleneTokens.Space.thinStroke).fill(SeleneTheme.lineStrong, style: FillStyle(eoFill: true)))
        .clipShape(Capsule())
        .animation(Motion.focus(reduceMotion), value: selection)
    }
}

typealias SeleneSegmented = OortSegmented

struct OortCard<Content: View>: View {
    @Environment(\.nxAppLocale) private var localization
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneFocusedRowID) private var focusedRowID
    @Environment(\.screenTrace) private var trace
    let title: String?
    let info: String?
    /// The row whose focus lets the help key open `info`: the one named like the card, unless told otherwise.
    let infoRow: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String? = nil, info: String? = nil, infoRow: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.info = info
        self.infoRow = infoRow
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
            if let title {
                HStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                    Text(L10n.text(title, context: localization))
                        .seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.ink75)
                        .accessibilityAddTraits(.isHeader)
                        .screenTrace(trace, [.init(kind: .text, text: L10n.text(title, context: localization), role: .card)])
                    if let info {
                        SeleneInfoTip(info, row: infoRow ?? title, focused: focusedRowID != nil && focusedRowID == infoRow ?? title)
                    }
                }
            }
            content()
        }
        .padding(canvas.u(SeleneTokens.Space.large))
        .frame(maxWidth: .infinity, alignment: .leading)
        .oortPanel(radius: canvas.u(SeleneTheme.cardRadius))
    }
}

typealias SelenePanel = OortCard

/// A value row that steps through its choices: Left/Right on a controller, the arrows with a pointer.
struct SeleneCycleRow: View {
    @Environment(\.nxAppLocale) private var localization
    let title: String
    let subtitle: String?
    let info: String?
    let value: String
    let verbatimValue: Bool
    let cycle: (Int) -> Void

    init(_ title: String, subtitle: String? = nil, info: String? = nil, value: String, verbatimValue: Bool = false,
                cycle: @escaping (Int) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.value = value
        self.verbatimValue = verbatimValue
        self.cycle = cycle
    }

    var body: some View {
        SeleneRow(title, subtitle: subtitle, info: info) {
            SeleneCycleValue(title: L10n.text(title, context: localization),
                             value: verbatimValue ? value : L10n.text(value, context: localization), cycle: cycle)
        }
    }
}

struct SeleneCycleValue: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var localization
    let title: String
    let value: String
    let cycle: (Int) -> Void

    var body: some View {
        HStack(spacing: canvas.u(SeleneTokens.Space.tight)) {
            arrow(.chevronLeft, -1)
            SeleneValueChip(text: value)
            arrow(.chevron, 1)
        }
    }

    private func arrow(_ icon: MaterialIcon, _ delta: Int) -> some View {
        Button { cycle(delta) } label: {
            MaterialIconView(icon, size: 20)
                .foregroundColor(SeleneTheme.ink60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format(delta < 0 ? "Previous %@" : "Next %@",
                                       [title], context: localization))
    }
}

extension CaseIterable where Self: Equatable {
    /// The case `delta` steps away, wrapping at both ends.
    func stepped(_ delta: Int) -> Self {
        let all = Array(Self.allCases)
        let index = all.firstIndex(of: self) ?? 0
        let count = all.count
        return all[((index + delta) % count + count) % count]
    }
}

extension Array where Element: Equatable {
    /// The element `delta` steps from `current`, wrapping; the first element when `current` is absent.
    func stepped(from current: Element, _ delta: Int) -> Element? {
        guard !isEmpty else { return nil }
        guard let index = firstIndex(of: current) else { return first }
        return self[((index + delta) % count + count) % count]
    }
}
