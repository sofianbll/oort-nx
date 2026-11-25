import GameController
import ShellHost
import ShellModel
import SwiftUI
import UniformTypeIdentifiers

/// The whole app over the host: four tabs, the host's questions, and adding a game.
public struct OortRootView: View {
    @Bindable private var model: ShellHostModel
    @State private var nav: OortNav
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
        .tint(Oort.focus)
        .preferredColorScheme(.dark)
        .modifier(TouchEndsPad(nav: nav))
        .transformEnvironment(\.oortStill) { $0 = $0 || model.launchingGame }
        .overlay {
            if model.launchingGame || model.isDeepLinkLaunching { LaunchCover(title: model.details.first { $0.id == nav.selected }?.game.title ?? "") }
        }
        .animation(.easeInOut(duration: SeleneTokens.Motion.screen), value: model.launchingGame)
        .alert("Oort NX", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button(Oort.text("OK")) { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .alert(Oort.text("Which save do you want?"), isPresented: Binding(get: { model.cloudConflict != nil }, set: { if !$0 { model.cancelCloudConflictIfPending() } }),
               presenting: model.cloudConflict) { prompt in
            if !prompt.isUnreadable { Button(Oort.text("The folder's")) { model.resolveCloudConflict(.useCloud) } }
            Button(Oort.text("This device's")) { model.resolveCloudConflict(.useDevice) }
            Button(Oort.text("Play without the folder")) { model.resolveCloudConflict(.playOffline) }
            Button(Oort.text("Cancel"), role: .cancel) { model.resolveCloudConflict(.cancel) }
        } message: { prompt in
            Text([prompt.gameTitle, prompt.reason, Oort.text("Folder: \(prompt.cloudDevice) \(prompt.cloudSaved)"), Oort.text("This device: \(prompt.localSaved)")]
                .filter { !$0.isEmpty }.joined(separator: "\n"))
        }
        .sheet(item: $model.log) { LogScreen(log: $0) }
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
    }
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
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        return tap
    }
    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) { touched() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
