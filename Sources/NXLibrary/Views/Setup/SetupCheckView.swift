import SwiftUI
import NXLibraryCore
import ArcanePorting

/// "Let's get Arcane ready" (Selene's SetupScreen): a card per thing Arcane
/// needs, rising in one after another; the focused card's story in a fixed panel
/// below; Install all and Continue. It checks again every few seconds, so a step
/// finished elsewhere ticks over by itself.
struct SetupCheckView: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var model: SetupCheckModel
    let isFirstRun: Bool

    @State var focus: SetupFocus = .carryOn
    @State var focusPlaced = false
    @State var shakes = 0
    @State var pendingTool: SetupItemID?
    @State var toolFocus: SeleneConfirmButton = .cancel
    @State private var risen = false
    @State private var popping: Set<SetupItemID> = []

    static let cardSize = CGSize(width: 240, height: 140)
    static let gap: CGFloat = 18

    init(viewModel: AppViewModel, isFirstRun: Bool) {
        self.viewModel = viewModel
        self.isFirstRun = isFirstRun
        self.model = viewModel.setupCheck
    }

    var items: [SetupItem] { SetupCheck.requirements(model.items) }
    var rows: [Int] { SetupGrid.rowCounts(items.count, maxPerRow: 3) }
    var setup: SetupCheckModel { model }

    var body: some View {
        ZStack {
            SeleneBackdrop()
            VStack(spacing: 0) {
                SetupStepIndicator(page: .requirements).padding(.bottom, canvas.u(SeleneTokens.Space.control))
                Text(L10n.text("Tools for building Switch games"))
                    .seleneFont(.screen, .semibold)
                    .foregroundColor(SeleneTheme.ink)
                Text(L10n.text("You don’t need these tools to play a game that’s already built."))
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75)
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
                grid.padding(.top, canvas.u(SeleneTokens.Space.section))
                panel.padding(.top, canvas.u(SeleneTokens.Space.titleGap))
                buttons.padding(.top, canvas.u(SeleneTokens.Space.panel))
            }
            .modifier(SeleneShake(amount: CGFloat(shakes), distance: 8))
            .seleneOverlayOwnership(pendingTool == nil)
            .offset(y: canvas.u(-20))
            VStack {
                Spacer(minLength: 0)
                SeleneHintsBar(right: [HintItem(.a, L10n.text("Select")), HintItem(.b, L10n.text("Back"))],
                               bottom: SeleneBottomScrim.hintsBottom, leftInset: 18)
            }.seleneOverlayOwnership(pendingTool == nil)
            if let pendingTool {
                SeleneOverlay(style: .dialog) {
                    SeleneConfirmDialog(title: pendingTool == .engine ? "Prepare nxnative?" : "Install the Metal compiler?",
                                        message: toolMessage(pendingTool), confirmTitle: "Continue", focus: $toolFocus,
                                        onCancel: { self.pendingTool = nil }, onConfirm: confirmTool)
                }
            }
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .onAppear {
            model.startRechecking()
            withAnimation(nil) { risen = false }
            DispatchQueue.main.async { risen = true }
        }
        .onDisappear {
            model.stopRechecking()
            model.rememberStates()
        }
        .onChange(of: items.map(\.state)) { placeInitialFocus() }
        .onChange(of: model.justReady) { _, ready in pop(ready) }
        .onReceive(NotificationCenter.default.publisher(for: .nxSetupCheckGamepadAction)) { note in
            if let action = note.object as? GamepadAction { handle(action) }
        }
    }

    private func toolMessage(_ tool: SetupItemID) -> String {
        if tool == .engine {
            return L10n.format("Oort will contact the engine’s Git server and prepare the tested nxnative revision in %@. This can update that checkout.",
                               [viewModel.setup.nxnativePath])
        }
        return L10n.format("Oort will ask Apple to download the Metal compiler for Xcode at %@. It does not replace Xcode.",
                           [viewModel.setup.resolvedDeveloperDir().path])
    }

    func confirmTool() {
        guard let pendingTool else { return }
        self.pendingTool = nil
        setup.activate(pendingTool)
    }

    // MARK: - Cards

    private var grid: some View {
        VStack(spacing: canvas.u(Self.gap)) {
            ForEach(Array(rows.enumerated()), id: \.offset) { row, count in
                HStack(spacing: canvas.u(Self.gap)) {
                    let start = rows.prefix(row).reduce(0, +)
                    ForEach(start..<(start + count), id: \.self) { index in
                        card(items[index], index: index)
                    }
                }
            }
        }
    }

    private func card(_ item: SetupItem, index: Int) -> some View {
        let focused = focus == .card(index)
        return VStack(spacing: 0) {
            MaterialIconView(Self.icon(item.id), size: 26)
                .foregroundColor(SeleneTheme.glyph)
                .frame(height: canvas.u(30))
            Text(L10n.text(item.title))
                .seleneFont(.text, .semibold)
                .foregroundColor(SeleneTheme.ink)
                .lineLimit(1)
                .padding(.top, canvas.u(SeleneTokens.Space.compact))
            StatusChip(item: item, popping: popping.contains(item.id))
                .padding(.top, canvas.u(SeleneTokens.Space.small))
            if let error = item.inlineError {
                Text(verbatim: error)
                    .seleneFont(.text)
                    .foregroundStyle(SeleneTheme.danger)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, canvas.u(SeleneTokens.Space.tight))
                    .help(error)
            }
            if item.state == .working {
                OortMeter(share: item.progress, height: nil, fill: SeleneTheme.glyph)
                    .frame(width: canvas.u(176), height: canvas.u(5))
                    .padding(.top, canvas.u(SeleneTokens.Space.small))
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, canvas.u(item.inlineError == nil ? 20 : SeleneTokens.Space.tight))
        .padding(.horizontal, canvas.u(SeleneTokens.Space.medium))
        .frame(width: canvas.u(Self.cardSize.width), height: canvas.u(Self.cardSize.height))
        .oortPanel(radius: canvas.u(SeleneTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: canvas.u(SeleneTheme.cardRadius), style: .continuous)
            .strokeBorder(focused ? SeleneTheme.focus : SeleneTheme.ink15,
                          lineWidth: canvas.u(focused ? 3 : 1)))
        .oortGlow(focused)
        .scaleEffect(focused && !reduceMotion ? 1.06 : 1)
        .animation(reduceMotion ? nil : SeleneTheme.focusIn, value: focused)
        .opacity(risen ? 1 : 0)
        .offset(y: risen || reduceMotion ? 0 : canvas.u(24))
        .animation(reduceMotion ? nil : SeleneTheme.standard.delay(0.14 + Double(index) * 0.045), value: risen)
        .contentShape(Rectangle())
        .onHover { if $0 { move(to: .card(index)) } }
        .onTapGesture { move(to: .card(index)); activate() }
    }

    static func icon(_ id: SetupItemID) -> MaterialIcon {
        switch id {
        case .xcode: return .build
        case .metal: return .monitor
        case .engine: return .rocket
        case .runtime: return .storage
        case .keys: return .key
        case .library, .sources: return .folder
        }
    }

    private func pop(_ ready: Set<SetupItemID>) {
        guard !ready.isEmpty, !reduceMotion else { return }
        popping.formUnion(ready)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { popping.subtract(ready) }
    }

    // MARK: - Panel

    private var panel: some View {
        let story = panelStory
        return HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.large)) {
            MaterialIconView(story.icon, size: 34)
                .foregroundColor(story.tone)
                .frame(width: canvas.u(40))
            VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.compact)) {
                HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                    Text(L10n.text(story.title)).seleneFont(.heading, .semibold).foregroundColor(SeleneTheme.ink)
                    Text(story.state.uppercased())
                        .seleneFont(.badge, .bold)
                        .foregroundColor(story.tone)
                }
                Text(story.about)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink90)
                    .fixedSize(horizontal: false, vertical: true)
                Text(story.detail)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink75)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(story.detail)
            }
            Spacer(minLength: 0)
            if let action = story.action {
                Text(action).seleneFont(.text, .semibold).foregroundColor(SeleneTheme.ink)
            }
        }
        .padding(canvas.u(SeleneTokens.Space.titleGap))
        .frame(width: canvas.u(960), height: canvas.u(156), alignment: .topLeading)
        .oortPanel(radius: canvas.u(SeleneTheme.cardRadius))
        .clipped()
    }

    private struct Story {
        var icon: MaterialIcon, tone: Color, title: String, state: String
        var about: String, detail: String, action: String?
    }

    private var panelStory: Story {
        switch focus {
        case .card(let index) where items.indices.contains(index):
            let item = items[index]
            return Story(icon: Self.icon(item.id), tone: StatusChip.tone(item), title: item.title,
                         state: StatusChip.stateName(item), about: item.about, detail: item.detail,
                         action: item.actionTitle)
        default:
            let required = items.filter(\.isRequired)
            let ready = required.filter { $0.state == .ready }.count
            let left = required.filter { $0.state != .ready }.map(\.title)
            if left.isEmpty {
                return Story(icon: .check, tone: SeleneTheme.success, title: L10n.text("All set"), state: L10n.text("Ready"),
                             about: L10n.text("Everything Arcane needs is here."), detail: "", action: "Continue")
            }
            return Story(icon: .checklist, tone: SeleneTheme.glyph, title: L10n.format("%@ of %@ ready", [String(describing: ready), String(describing: required.count)]),
                         state: L10n.format("%@ left", [String(describing: left.count)]), about: L10n.format("Still to do: %@.", [String(describing: left.joined(separator: ", "))]),
                         detail: L10n.text("Build setup can wait. Existing game apps still play."),
                         action: "Continue")
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        SelenePillButton(title: "Continue", focused: focus == .carryOn) {
            move(to: .carryOn); activate()
        }
        .onHover { if $0 { move(to: .carryOn) } }
    }
}

enum SetupFocus: Equatable { case card(Int), carryOn }

/// The card's state in a word or two, coloured by state; a running action breathes.
private struct StatusChip: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    let item: SetupItem
    let popping: Bool
    @State private var dim = false

    static func tone(_ state: SetupState) -> Color {
        switch state {
        case .ready: return SeleneTheme.success
        case .missing, .needsYou: return SeleneTheme.glyph
        case .working: return SeleneTheme.ink82
        case .warning: return SeleneTheme.untested
        case .failed: return SeleneTheme.danger
        }
    }

    /// Ready but untested by Arcane (the newest engine) reads orange, without an alarm.
    static func tone(_ item: SetupItem) -> Color {
        item.isUntested && item.state == .ready ? SeleneTheme.untested : tone(item.state)
    }

    static func stateName(_ item: SetupItem) -> String {
        item.chip.replacingOccurrences(of: "✓ ", with: "").capitalized
    }

    var body: some View {
        let tone = Self.tone(item)
        OortTag(text: item.chip, tone: tone)
            .frame(maxWidth: canvas.u(200))
            .scaleEffect(popping && !reduceMotion ? 1.18 : 1)
            .animation(reduceMotion ? nil : SeleneTheme.quick, value: popping)
            .opacity(item.state == .working && dim ? 0.45 : 1)
            .onAppear(perform: breathe)
            .onChange(of: item.state) { breathe() }
    }

    private func breathe() {
        guard item.state == .working, !reduceMotion else { dim = false; return }
        withAnimation(SeleneTheme.ease(SeleneTokens.Motion.pulse).repeatForever(autoreverses: true)) { dim = true }
    }
}

/// A working card's bar: it fills with the progress the install reports, and
/// sweeps when there is no number yet (or holds still with Reduce Motion).
