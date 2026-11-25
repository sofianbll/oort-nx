import SwiftUI
import AppKit
import NXLibraryCore

enum LocalePickerMode { case language, region }

/// Direct language selection and searchable regional formats share the same input behavior.
struct LocalePicker: View {
    let mode: LocalePickerMode
    @ObservedObject var settings: SettingsEditor
    let canHandleInput: () -> Bool
    let onClose: () -> Void
    @ObservedObject private var localization = AppLocalization.shared
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var focus = 0
    @State private var keyMonitor: Any?
    @FocusState private var searchFocused: Bool

    private struct Choice { let id: String; let name: String }
    private var choices: [Choice] {
        if mode == .language {
            return AppLanguage.allCases.map { Choice(id: $0.rawValue, name: $0.nativeName) }
        }
        return (query.isEmpty ? [Choice(id: "auto", name: L10n.text("Automatic (Mac)"))] : [])
            + AppRegionOption.matching(query, context: localization.context).map { Choice(id: $0.id, name: $0.name) }
    }
    private var selectedID: String {
        mode == .language ? settings.settings.appLanguage.rawValue : settings.settings.appRegion ?? "auto"
    }
    private var formatPreview: String {
        let rows = choices
        let id = rows.indices.contains(focus) ? rows[focus].id : selectedID
        let locale = AppLocale(language: localization.context.language, region: id == "auto" ? nil : id).formatLocale
        return L10n.format("Example: %@ · %@ · %@", [
            Date().formatted(.dateTime.day().month(.twoDigits).year().locale(locale)),
            12_345.67.formatted(.number.locale(locale)),
            Int64(1_500_000_000).formatted(.byteCount(style: .file).locale(locale))
        ])
    }

    var body: some View {
        let rows = choices
        ZStack {
            SeleneTheme.scrim65.ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.medium)) {
                Text(L10n.text(mode == .language ? "Choose app language" : "Regional formats")).seleneFont(.screen, .semibold).foregroundColor(SeleneTheme.ink)
                Text(L10n.text(mode == .language ? "Menus, genres and available game descriptions. The games’ own language stays separate." : "Dates, numbers and sizes only. Game descriptions follow the app language."))
                    .seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                if mode == .region {
                    Text(formatPreview).seleneFont(.text).foregroundColor(SeleneTheme.ink)
                }
                if mode == .region {
                TextField(L10n.text("Find a region"), text: $query)
                    .textFieldStyle(.plain).seleneFont(.row).focused($searchFocused)
                    .onSubmit { choose() }
                    .padding(canvas.u(SeleneTokens.Space.line)).background(SeleneTheme.glass)
                    .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content)))
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: canvas.u(SeleneTokens.Space.hairline)) {
                            if rows.isEmpty {
                                Text(L10n.text("No matching regions.")).seleneFont(.text).foregroundColor(SeleneTheme.ink60)
                            }
                            ForEach(rows.indices, id: \.self) { index in
                                Button { focus = index; choose() } label: {
                                    HStack {
                                        Text(rows[index].name).seleneFont(.row)
                                        Spacer()
                                        if rows[index].id == selectedID {
                                            MaterialIconView(.check, size: 22)
                                        }
                                        if mode == .region, rows[index].id != "auto" { Text(rows[index].id).seleneFont(.text).foregroundColor(SeleneTheme.ink60) }
                                    }
                                    .foregroundColor(SeleneTheme.ink)
                                    .padding(canvas.u(SeleneTokens.Space.line))
                                    .background(index == focus ? SeleneTheme.glass : Color.clear)
                                    .seleneRowFocus(index == focus, radius: canvas.u(12))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(index)
                                .accessibilityAddTraits(rows[index].id == selectedID ? .isSelected : [])
                            }
                        }
                        .padding(canvas.u(SeleneTokens.Space.hairline))
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: focus) { _, index in
                        withAnimation(reduceMotion ? nil : SeleneTheme.quick) { proxy.scrollTo(index, anchor: .center) }
                    }
                    .onAppear {
                        focus = rows.firstIndex(where: { $0.id == selectedID }) ?? 0
                        proxy.scrollTo(focus, anchor: .center)
                    }
                }
                .frame(height: canvas.u(420))
                HStack {
                    Spacer()
                    Button(L10n.text("Cancel"), action: onClose).buttonStyle(.plain).seleneFont(.text, .semibold)
                        .foregroundColor(SeleneTheme.glyph).padding(canvas.u(SeleneTokens.Space.compact))
                }
            }
            .padding(canvas.u(SeleneTokens.Space.section))
            .frame(width: canvas.u(800))
            .background(SeleneTheme.glassCard)
            .clipShape(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field)))
            .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.field)).strokeBorder(SeleneTheme.ink15, lineWidth: 1))
        }
        .onChange(of: query) { focus = 0 }
        .onAppear(perform: installKeys)
        .onDisappear { if let keyMonitor { NSEvent.removeMonitor(keyMonitor) } }
        .onReceive(NotificationCenter.default.publisher(for: .nxLocalePickerGamepadAction)) { note in
            guard canHandleInput(), let action = note.object as? GamepadAction else { return }
            switch action {
            case .navigateUp: move(-1)
            case .navigateDown: move(1)
            case .confirm: choose()
            case .cancel: onClose()
            default: break
            }
        }
    }

    private func move(_ delta: Int) {
        searchFocused = false
        focus = min(max(0, focus + delta), max(0, choices.count - 1))
    }

    private func choose() {
        let rows = choices
        guard rows.indices.contains(focus) else { return }
        let id = rows[focus].id
        if mode == .language, let language = AppLanguage(rawValue: id) {
            settings.settings.appLanguage = language
        } else if mode == .region {
            settings.settings.appRegion = id == "auto" ? nil : id
        }
        onClose()
    }

    private func installKeys() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard canHandleInput() else { return event }
            switch event.keyCode {
            case 53: onClose()
            case 125: move(1)
            case 126: move(-1)
            case 36, 76: choose()
            case 49 where !searchFocused: choose()
            default: return event
            }
            return nil
        }
    }
}
