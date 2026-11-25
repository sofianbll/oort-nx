import GameController
import ShellHost
import ShellModel
import SwiftUI
import UniformTypeIdentifiers

/// The whole app over the host: four tabs, the host's questions, and adding a game.
public struct OortRootView: View {
    @Bindable private var model: ShellHostModel
    @State private var nav: OortNav
    @State private var sidebar = false
    private let importRoot: URL?
    private let checkSigner: @Sendable (URL) -> String?

    /// `importRoot` is `Documents/Frameworks`; nil leaves adding a game out. `checkSigner` says why a game cannot run here.
    public init(model: ShellHostModel, sounds: OortSounds, importRoot: URL?, checkSigner: @escaping @Sendable (URL) -> String? = { _ in nil }) {
        self.init(model: model, nav: OortNav(sounds: sounds), importRoot: importRoot, checkSigner: checkSigner)
    }

    init(model: ShellHostModel, nav: OortNav, importRoot: URL?, checkSigner: @escaping @Sendable (URL) -> String? = { _ in nil }) {
        self.model = model
        _nav = State(initialValue: nav)
        self.importRoot = importRoot
        self.checkSigner = checkSigner
    }

    public var body: some View {
        TabView(selection: $nav.tab) {
            Tab(Oort.text("Home"), systemImage: "sparkles", value: OortTab.home) { stack(.home) { HomeView(model: model, nav: nav) } }
            Tab(Oort.text("Library"), systemImage: "square.grid.2x2.fill", value: OortTab.library) { stack(.library) { LibraryScreen(model: model, nav: nav) } }
            Tab(Oort.text("Controllers"), systemImage: "gamecontroller.fill", value: OortTab.controllers) { stack(.controllers) { ControllersScreen(model: model, nav: nav) } }
            Tab(Oort.text("Settings"), systemImage: "gearshape.fill", value: OortTab.settings) { stack(.settings) { SettingsScreen(model: model, nav: nav) } }
        }
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .tabViewStyle(.sidebarAdaptable)
        .accessibilityHidden(question != nil)
        // The iPad's sidebar fills its chosen line with the tint, under white words.
        .tint(sidebar ? Oort.chosen : Oort.focus)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .background { OortKeys(place: [nav.tab.rawValue] + (nav.paths[nav.tab] ?? []).map { "\($0)" }) { model.keyPressed($0) } }
        #endif
        .modifier(TouchEndsPad(nav: nav))
        .onAppear {
            nav.cover = { [nav] in
                if nav.importing { return { nav.importing = false } }
                if nav.picking { return { nav.picking = false } }
                #if os(iOS)
                return OortOverlay.close()
                #else
                return nil
                #endif
            }
        }
        .transformEnvironment(\.oortStill) { $0 = $0 || model.launchingGame }
        .overlay {
            if model.launchingGame || model.isDeepLinkLaunching { LaunchCover(title: model.details.first { $0.id == nav.selected }?.game.title ?? "") }
        }
        .animation(.easeInOut(duration: SeleneTokens.Motion.screen), value: model.launchingGame)
        .overlay {
            if let question { OortDialog(question: question, model: model, nav: nav).id(question.title + question.message) }
        }
        .sheet(item: $model.log) { LogScreen(log: $0, model: model, nav: nav) }
        .fileImporter(isPresented: $nav.importing, allowedContentTypes: [.framework, .folder]) { result in
            guard case .success(let url) = result, let importRoot else { return }
            Task {
                let check = checkSigner
                let outcome = await Task.detached { Result { try FrameworkImport.run(url, into: importRoot, check: check) } }.value
                switch outcome {
                case .success(let id): model.reload(); nav.selected = id; nav.tab = .home; nav.sounds.play(.success)
                case .failure(let error): model.notice = error.localizedDescription; nav.sounds.play(.deny)
                }
            }
        }
    }

    /// What the app asks now: the host's questions first, then the screen's.
    private var question: OortQuestion? {
        if let prompt = model.cloudConflict {
            var choices: [OortQuestion.Choice] = []
            if !prompt.isUnreadable { choices.append(.init(label: Oort.text("The folder's")) { model.resolveCloudConflict(.useCloud) }) }
            choices.append(.init(label: Oort.text("This device's")) { model.resolveCloudConflict(.useDevice) })
            choices.append(.init(label: Oort.text("Play without the folder")) { model.resolveCloudConflict(.playOffline) })
            let message = [prompt.gameTitle, prompt.reason, Oort.text("Folder: \(prompt.cloudDevice) \(prompt.cloudSaved)"), Oort.text("This device: \(prompt.localSaved)")]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            return OortQuestion(title: Oort.text("Which save do you want?"), message: message, choices: choices) { model.resolveCloudConflict(.cancel) }
        }
        if let notice = model.notice { return OortQuestion(title: "Oort NX", message: notice, cancelLabel: Oort.text("OK")) { model.notice = nil } }
        return nav.question
    }

    private func stack(_ tab: OortTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { nav.paths[tab] ?? [] }, set: { nav.paths[tab] = $0 })) {
            root().navigationDestination(for: OortRoute.self) { route in
                switch route {
                case .game(let id): GameScreen(id: id, model: model, nav: nav)
                case .options(let id): OptionsScreen(id: id, model: model, nav: nav)
                case .cheats(let id): CheatsScreen(id: id, model: model, nav: nav)
                case .mapping(let id): MappingScreen(id: id, model: model, nav: nav)
                case .padTest: PadTestScreen(model: model, nav: nav)
                case .activity: ActivityScreen(model: model, nav: nav)
                case .credits: CreditsScreen(model: model, nav: nav)
                case .notices: NoticesScreen(model: model, nav: nav)
                }
            }
        }
        .tint(Oort.focus)
        .background { SidebarSeen(sidebar: $sidebar) }
    }
}

/// Where the tabs are: along the top, the bottom, or in the sidebar.
private struct SidebarSeen: View {
    @Binding var sidebar: Bool
    #if os(iOS)
    @Environment(\.tabBarPlacement) private var place
    var body: some View { Color.clear.onChange(of: place, initial: true) { sidebar = place == .sidebar }.accessibilityHidden(true) }
    #else
    var body: some View { Color.clear }
    #endif
}

/// Night, the cloud and the game's name while it starts.
private struct LaunchCover: View {
    let title: String
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            OortBackdrop()
            VStack(alignment: .leading, spacing: SeleneTokens.Space.compact) {
                if !title.isEmpty { Text(title).font(.largeTitle.bold()).foregroundStyle(Oort.ink) }
                Text(Oort.text("Starting…")).foregroundStyle(Oort.ink2)
            }
            .padding(SeleneTokens.Space.section)
        }
        .environment(\.oortStill, true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .transition(.opacity)
    }
}

private struct LogScreen: View {
    let log: LogPresentation
    let model: ShellHostModel
    let nav: OortNav
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.text ?? Oort.text("This game has no log yet. It writes one when it runs."))
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Oort.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SeleneTokens.Space.medium)
            }
            .defaultScrollAnchor(.bottom)
            .modifier(OortReading(model: model, nav: nav) { dismiss() })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                OortHints(nav: nav, hints: [(.back, Oort.text("Close"))]).padding(SeleneTokens.Space.compact)
            }
            .background(Oort.page)
            .navigationTitle(log.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(Oort.text("Close")) { dismiss() } }
                if let text = log.text { ToolbarItem(placement: .primaryAction) { ShareLink(item: text) } }
            }
        }
    }
}

/// A finger on the screen takes the focus ring and the hints away until the next press.
private struct TouchEndsPad: ViewModifier {
    let nav: OortNav
    func body(content: Content) -> some View {
        #if os(iOS)
        // The controller drives Oort's own focus, not the system's: a press never counts twice.
        content.handlesGameControllerEvents(matching: .gamepad).gesture(AnyTouch { if nav.device != nil { nav.device = nil } })
        #else
        content
        #endif
    }
}

#if os(iOS)
private struct AnyTouch: UIGestureRecognizerRepresentable {
    let touched: () -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        // A press of no length begins as the finger lands: a tap, a swipe or a hold.
        let touch = UILongPressGestureRecognizer()
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delaysTouchesEnded = false
        touch.delegate = context.coordinator
        return touch
    }
    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { touched() }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
