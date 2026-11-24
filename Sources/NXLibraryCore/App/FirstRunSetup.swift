import Foundation

/// The current first-run tour and the resumable legacy Porting path share the Setup layer.
public struct FirstRunSetup: Equatable {
    public enum Page: String {
        case welcome, controller, profile, localGames, services, look
        case found, requirements, games

        public static let tour: [Self] = [.welcome, .controller, .profile, .localGames, .services, .look]
        public var isGuided: Bool { Self.tour.contains(self) }
        public func guidedStep(_ offset: Int) -> Self? {
            guard let index = Self.tour.firstIndex(of: self), Self.tour.indices.contains(index + offset) else { return nil }
            return Self.tour[index + offset]
        }
    }
    public enum LibraryState: Equatable { case scanning, empty, ready }

    public private(set) var page: Page
    public private(set) var isCompleted: Bool
    /// The Steam switch on `found`: nil until chosen, then kept on every page of the first launch
    /// and applied when it finishes, through Open library or through Porting.
    public private(set) var steamChoice: Bool?

    public init(completed: Bool = false, savedPage: String? = nil, savedSteamChoice: Bool? = nil) {
        isCompleted = completed
        steamChoice = completed ? nil : savedSteamChoice
        // Settings → Open Setup starts on the requirements; an interrupted first launch resumes where it was.
        page = completed ? .requirements : savedPage.flatMap(Page.init(rawValue:)) ?? .welcome
    }

    public var pageToRemember: String? { isCompleted ? nil : page.rawValue }
    public var steamChoiceToRemember: Bool? { isCompleted ? nil : steamChoice }

    public mutating func chooseSteam(_ on: Bool) {
        guard !isCompleted else { return }
        steamChoice = on
    }

    public mutating func openTour() { page = .welcome }

    @discardableResult public mutating func moveTour(_ offset: Int) -> Bool {
        guard let next = page.guidedStep(offset) else { return false }
        page = next
        return true
    }

    /// The Porting card on `found`: the requirements of today's Setup.
    public mutating func openPorting() {
        page = .requirements
    }

    /// Back from the requirements during the first launch; a finished setup has no `found` page.
    public mutating func returnToFound() {
        guard !isCompleted else { return }
        page = .found
    }

    public mutating func advance() {
        page = .games
    }

    public mutating func goBack() {
        page = .requirements
    }

    public mutating func finish() {
        isCompleted = true
        page = .requirements
    }

    public static func libraryState(isScanning: Bool, gameCount: Int) -> LibraryState {
        isScanning ? .scanning : gameCount > 0 ? .ready : .empty
    }

    /// An accepted picker arrival is consumed once, independently of whether Add Game changed route.
    public struct ReviewEntry {
        private var reviewedID: UUID?
        public init() {}

        public mutating func consume(_ id: UUID?, isReady: Bool, titleCount: Int) -> Bool {
            guard let id, id != reviewedID, isReady, titleCount == 1 else { return false }
            reviewedID = id
            return true
        }
    }

    public enum Focus: Equatable {
        case apps, file, folder, back, finish
        /// The `found` page: the Steam switch (only when Steam is there), the Porting card, Open library.
        case steamToggle, portingCard, openLibrary

        public static let initialOnFound: Self = .openLibrary

        public func movedOnFound(_ direction: MoveDirection, hasSteam: Bool) -> Self {
            switch (self, direction) {
            case (.steamToggle, .down): return .portingCard
            case (.portingCard, .up): return hasSteam ? .steamToggle : .portingCard
            case (.portingCard, .down): return .openLibrary
            case (.openLibrary, .up): return .portingCard
            default: return self
            }
        }

        public func moved(_ direction: MoveDirection) -> Self {
            switch (self, direction) {
            case (.apps, .down): return .file
            case (.file, .up): return .apps
            case (.file, .down): return .folder
            case (.folder, .up): return .file
            case (.folder, .down): return .finish
            case (.finish, .left): return .back
            case (.back, .right): return .finish
            case (.finish, .up), (.back, .up): return .folder
            default: return self
            }
        }
    }
}
