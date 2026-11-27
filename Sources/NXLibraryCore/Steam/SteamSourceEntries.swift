import Foundation

/// Steam's rows on the Mac, decided once from its owners' facts (CatalogSourcesModel, the first launch's reader):
/// in Settings › Sources, on the first launch's `found` page and in the overview of integrations. The views draw
/// them; A goes to the owner of each request.
public extension SteamSourceEntries {
    /// What a state of the source says, once for every place that shows it.
    struct State: Equatable, Sendable {
        /// Settings › Sources, under Refresh Steam.
        public let detail: IntegrationWords
        /// The overview of integrations: Steam's status.
        public let summary: IntegrationWords
        public let emphasis: IntegrationEmphasis
    }

    static func state(_ status: CatalogSourceStatus, found: Int) -> State {
        switch status {
        case .disabled: State(detail: .init("Enable Steam to find its installed Mac games."), summary: .init("Steam source off"), emphasis: .neutral)
        case .idle: State(detail: .init("Ready to check Steam."), summary: .init("Steam not scanned yet"), emphasis: .neutral)
        case .scanning: State(detail: .init("Checking Steam libraries…"), summary: .init("Reading Steam libraries…"), emphasis: .working)
        case .ready: State(detail: .init("%lld Steam installations found", count: found),
                           summary: .init(found == 0 ? "No games found" : "Steam library scanned"), emphasis: .neutral)
        case .partial: State(detail: .init("Some installations could not be checked. Your library has been kept."),
                             summary: .init("Steam scan incomplete"), emphasis: .attention)
        case .cancelled: State(detail: .init("Scan stopped. Refresh when you are ready."), summary: .init("Steam scan cancelled"), emphasis: .attention)
        case .failed: State(detail: .init("Steam could not be refreshed. Your library has been kept."), summary: .init("Steam scan failed"), emphasis: .attention)
        }
    }

    /// What turning the source off keeps: under the switch, and again when a changed choice is saved.
    static let keptWhenOff = IntegrationWords("Your Steam files stay where they are. Disabling this source keeps its games and personal choices.")

    /// Settings › Sources, in their order: the source (its choice waits in the draft until Save), its refresh, its folder.
    struct MacRows: Equatable, Sendable {
        public let source, refresh, folder: IntegrationEntry
        public var all: [IntegrationEntry] { [source, refresh, folder] }
    }

    static func mac(applied: Bool, staged: Bool?, status: CatalogSourceStatus, found: Int, root: String) -> MacRows {
        var source = sourceSwitch(id: "steamSource", inForce: applied, waiting: staged)
        source.icon = "Steam"
        source.about = .init("Find installed native Mac games in your Steam libraries.")
        source.info = keptWhenOff
        // A refresh needs the source in force; a failed one can always be tried again.
        let canRefresh = applied || status == .failed
        let refresh = IntegrationEntry(id: "steamRefresh", title: .init("Refresh Steam"), about: state(status, found: found).detail,
                                       control: .button(.init(status == .scanning ? "Cancel" : "Refresh")),
                                       request: canRefresh ? (status == .scanning ? .cancelSteamRefresh : .refreshSteam) : nil)
        let folder = IntegrationEntry(id: "steamFolder", title: .init("Steam folder"),
                                      about: .init("Choose the Steam folder containing steamapps."),
                                      control: .value(root, button: .init("Change")), request: .chooseSteamFolder)
        return MacRows(source: source, refresh: refresh, folder: folder)
    }

    /// Steam's rows of Settings › Sources as Search and Changed list them, in their order: the identity and title they
    /// are drawn with, and what each is for whatever its state (the refresh shows its state; it is found by what it does).
    static let searchRows: [SettingDescriptor] = {
        let rows = mac(applied: true, staged: nil, status: .idle, found: 0, root: "")
        let about = [rows.source.about, .init("Check enabled Steam libraries without changing your game files."), rows.folder.about]
        return zip(rows.all, about).map { SettingsCatalog.action($0.id, .sources, $0.title.key, $1?.key ?? "") }
    }()

    /// A Steam choice waiting in the draft holds the switch and the folder: both rows show it waiting.
    static let draftRows: [String] = {
        let rows = mac(applied: true, staged: nil, status: .idle, found: 0, root: "")
        return [rows.source.rowID, rows.folder.rowID]
    }()

    /// The tour's Steam service: set up while the source is in force. A opens Settings › Sources on the source's switch.
    static func tour(inForce: Bool) -> OptionalServiceEntries.Service {
        let source = mac(applied: inForce, staged: nil, status: .idle, found: 0, root: "").source
        return .init(OptionalServiceEntries.entry("steam", "Steam", "Read your installed Mac games from Steam.", .store, setUp: inForce),
                     section: .sources, row: source.rowID)
    }

    /// The first launch's `found` page: the switch when Steam was read, Retry when it could not be read in full, nothing
    /// without Steam. The reader never reports both a count and a failure. The choice waits in FirstRunSetup until the
    /// first launch ends.
    static func found(_ findings: FirstRunFindings?, inForce: Bool, waiting: Bool?) -> IntegrationEntry? {
        if let count = findings?.steamGameCount {
            var entry = sourceSwitch(id: "steamToggle", inForce: inForce, waiting: waiting)
            entry.icon = "Steam"
            entry.about = .init("%lld installed Mac games", count: count)
            return entry
        }
        guard findings?.steamReadFailed == true else { return nil }
        return IntegrationEntry(id: "steamToggle", title: .init("Steam"),
                                about: .init("Steam couldn't be read completely. Try again or continue and check Settings → Sources later."),
                                icon: "Steam", control: .button(.init("Retry")), request: .readSteamAgain)
    }
}
