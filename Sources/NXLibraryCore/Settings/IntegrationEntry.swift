import Foundation

/// A text of the catalog and what fills it. `key` is a key of Localizable.xcstrings (on Windows and Linux, of
/// desktop/strings.json too); `count` picks its plural and fills its `%lld`; `args` fill its `%@`, in order.
/// Each app puts it into words once, with its own lookup: nothing here is translated.
public struct IntegrationWords: Equatable, Sendable {
    public let key: String
    public let count: Int?
    public let args: [String]

    public init(_ key: String, count: Int? = nil, args: [String] = []) {
        (self.key, self.count, self.args) = (key, count, args)
    }

    /// Shown as it is: a path, a number.
    public static func verbatim(_ text: String) -> Self { .init("%@", args: [text]) }
}

/// What A asks of the owner of an entry, with what it asks for. The owner does it, at once or into its draft;
/// a drawing never does.
public enum IntegrationRequest: Equatable, Sendable {
    case steam(enabled: Bool), refreshSteam, cancelSteamRefresh, chooseSteamFolder, readSteamAgain
    case online(on: Bool), clearOnline
}

/// A page, picker or dialog an entry opens in the same app. The app has one way to each (Windows and Linux:
/// `PAGES` in desktop/ui/app.js, checked by IntegrationsTests).
public enum IntegrationRoute: String, CaseIterable, Equatable, Sendable {
    case steamLibrary
    case programs, integrations, folder, match, onlineQuestion
}

/// How much an integration needs the player, beside its status in the overview of integrations.
public enum IntegrationEmphasis: Equatable, Sendable { case neutral, working, attention }

/// Asked before a request that cannot be taken back. Cancel has the focus.
public struct IntegrationConfirmation: Equatable, Sendable {
    public let title: IntegrationWords
    public let message: IntegrationWords
    public let confirm: IntegrationWords

    public init(title: IntegrationWords, message: IntegrationWords, confirm: IntegrationWords) {
        (self.title, self.message, self.confirm) = (title, message, confirm)
    }
}

/// One row about an integration as the player meets it, decided once from its owner's facts: what it says, whether
/// it is on, whether A does something and what it asks. Drawing it is each app's; doing it is the owner's.
public struct IntegrationEntry: Equatable, Sendable {
    public enum Control: Equatable, Sendable {
        /// A switch; A asks for the other state.
        case toggle(checked: Bool)
        /// A named button at the end of the row.
        case button(IntegrationWords)
        /// A value at the end, and a named button that changes it.
        case value(String, button: IntegrationWords)
        /// The whole row is the button.
        case row
        /// Goes to another page; nothing is asked of an owner.
        case open(IntegrationRoute)
    }

    /// The request's identity, stable while the facts change: the focus stays on it.
    public let id: String
    /// What the drawn row is known by (the Mac's settings rows go by their title).
    public let rowID: String
    public let title: IntegrationWords
    public var about: IntegrationWords?
    public var info: IntegrationWords?
    public var value: IntegrationWords?
    /// Joined by ". " where the app has one line of help.
    public var help: [IntegrationWords]
    /// The app's own name for its picture: a platform on the Mac, an icon on Windows and Linux.
    public var icon: String?
    public let control: Control
    /// Nil: the row still takes the focus, and A is refused.
    public var request: IntegrationRequest?
    public var confirmation: IntegrationConfirmation?

    public init(id: String, rowID: String? = nil, title: IntegrationWords, about: IntegrationWords? = nil,
                info: IntegrationWords? = nil, value: IntegrationWords? = nil, help: [IntegrationWords] = [],
                icon: String? = nil, control: Control, request: IntegrationRequest?,
                confirmation: IntegrationConfirmation? = nil) {
        (self.id, self.rowID, self.title, self.about, self.info) = (id, rowID ?? title.key, title, about, info)
        (self.value, self.help, self.icon, self.control, self.request, self.confirmation) = (value, help, icon, control, request, confirmation)
    }

    public var checked: Bool? { if case .toggle(let checked) = control { checked } else { nil } }
}

/// Steam on this computer. Its switch is the same wherever it is drawn: it shows the choice waiting (in a draft, in
/// the first steps) or else the one in force, and A asks for the other. Its words and states are decided beside their
/// owners' facts: NXLibraryCore/Steam/SteamSourceEntries.swift on the Mac, Companion+Integrations.swift on Windows and
/// Linux. Whether a choice applies at once or waits is the place's.
public enum SteamSourceEntries {
    public static func sourceSwitch(id: String, inForce: Bool, waiting: Bool? = nil) -> IntegrationEntry {
        let checked = waiting ?? inForce
        return IntegrationEntry(id: id, title: .init("Steam"), control: .toggle(checked: checked), request: .steam(enabled: !checked))
    }
}

public extension SettingsRowAction {
    /// The row's focus slot and A, from the same entry the row is drawn from: `ask` is what its click does too.
    /// A refused entry keeps its slot, and A does nothing.
    init(_ entry: IntegrationEntry, ask: @escaping (IntegrationEntry) -> Void) {
        self.init(id: entry.id, title: entry.title.key, rowID: entry.rowID, isEnabled: entry.request != nil) {
            if entry.request != nil { ask(entry) }
        }
    }
}
