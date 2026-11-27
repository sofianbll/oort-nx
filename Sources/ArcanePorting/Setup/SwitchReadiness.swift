import Foundation
import NXLibraryCore

/// Proposal (feat/proposition-accueil-ryujinx): the checked state of each Switch prerequisite for the engine in
/// use, described once for the Mac (nxnative) and the PC (Ryujinx-Nextendo). The views show the same rows and words
/// on both; only what an engine needs changes: the firmware is Ryujinx's alone, compiled apps are nxnative's alone.
///
/// Nothing here holds a key value or a private path: only names, counts, versions and folder names. The adapter
/// fills it from its checks; this branch fills it with fixtures to show the screens.
public struct SwitchReadiness: Equatable, Sendable {
    public enum Engine: String, Sendable { case nxnative, ryujinx }

    /// How a line reads: green when ready, neutral when something is still to do, red when a choice failed.
    public enum Tone: Sendable { case ready, todo, optional, warning, problem }

    public struct Line: Equatable, Sendable {
        public let tone: Tone
        public let title: String
        public let detail: String?
    }

    public enum EngineState: Equatable, Sendable {
        /// `portable`: the data sits next to the program (`portable/`), else in the user profile.
        case ready(version: String, portable: Bool)
        case notFound
        case tooOld(found: String, required: String)
    }

    public enum KeysState: Equatable, Sendable {
        case imported(firmware: String)
        case missing
        /// A title.keys was chosen as prod.keys: no header_key, no master_key.
        case notProdKeys
        /// Detect Ryujinx found no prod.keys in the folder or in its system folder.
        case nothingDetected
    }

    public enum TitleKeysState: Equatable, Sendable {
        case present(titles: Int)
        case absent
    }

    public enum FirmwareState: Equatable, Sendable {
        case installed(version: String)
        case missing
        case keysTooOld(keys: String, firmware: String)
    }

    public enum FoldersState: Equatable, Sendable {
        case none
        case empty(folder: String)
        case found(folder: String, games: Int, skipped: Int)
    }

    /// One row of the Compatibility panel, as the adapter reports it.
    public struct Check: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let detail: String
        public let tone: Tone
        public init(_ id: String, title: String, detail: String, tone: Tone) {
            self.id = id
            self.title = title
            self.detail = detail
            self.tone = tone
        }
    }

    public var engine: Engine
    public var engineState: EngineState
    public var keys: KeysState
    public var titleKeys: TitleKeysState
    public var firmware: FirmwareState
    public var folders: FoldersState
    public var checks: [Check]

    public init(engine: Engine, engineState: EngineState, keys: KeysState, titleKeys: TitleKeysState = .absent,
                firmware: FirmwareState = .missing, folders: FoldersState = .none, checks: [Check] = []) {
        self.engine = engine
        self.engineState = engineState
        self.keys = keys
        self.titleKeys = titleKeys
        self.firmware = firmware
        self.folders = folders
        self.checks = checks
    }

    public static let ryujinxDownload = URL(string: "https://nextendo.network/download")!

    public var engineName: String { engine == .ryujinx ? "Ryujinx-Nextendo" : "nxnative" }
    /// Ryujinx-Nextendo 1.10.7 reads these; it does not read .nsz, .xcz or a Switch 2 .nup.
    public var formats: [String] {
        engine == .ryujinx ? [".nsp", ".xci", ".pfs0", ".nca", ".nro"] : GameFoldersCopy.sourceBadges
    }
    public var formatList: String { formats.map { $0.dropFirst().uppercased() }.joined(separator: " · ") }
    public var needsFirmware: Bool { engine == .ryujinx }
    /// The folder rows' words without what this engine cannot read (a Switch 2 .nup) or where it does not run.
    public var sourcesContents: String {
        engine == .ryujinx ? L10n.text("Your own Switch files: cartridge, eShop or update.") : GameFoldersCopy.sourcesContents
    }
    public var keysContents: String {
        engine == .ryujinx ? L10n.text("Your Switch key file lets Oort read protected game files. It stays on this computer.")
            : GameFoldersCopy.keysContents
    }
    public var compiles: Bool { engine == .nxnative }

    // MARK: - Lines

    public var engineLine: Line {
        switch engineState {
        case .ready(let version, let portable):
            return Line(tone: .ready, title: L10n.format("Ready · %@", [version]),
                        detail: engine == .nxnative ? nil
                            : L10n.text(portable ? "Portable copy: its data stays next to the program."
                                                 : "Its data is in your user folder."))
        case .notFound:
            return Line(tone: .todo, title: L10n.text("Not found"),
                        detail: L10n.text("Oort does not provide Ryujinx. Get it from the official page, then choose its folder."))
        case .tooOld(let found, let required):
            return Line(tone: .problem, title: L10n.format("Too old · %@", [found]),
                        detail: L10n.format("Playing online with friends needs version %@. Update it from the official page.", [required]))
        }
    }

    public var keysLine: Line {
        switch keys {
        case .imported(let firmware):
            if case .keysTooOld = self.firmware, needsFirmware {
                return Line(tone: .problem, title: L10n.format("Keys too old · up to firmware %@", [firmware]), detail: nil)
            }
            return Line(tone: .ready, title: L10n.format("Keys imported · up to firmware %@", [firmware]), detail: nil)
        case .missing:
            return Line(tone: .todo, title: L10n.text("No keys yet"),
                        detail: L10n.text("Choose your prod.keys file, or find it in Ryujinx."))
        case .notProdKeys:
            return Line(tone: .problem, title: L10n.text("This file is a title.keys"),
                        detail: L10n.text("Choose prod.keys first. You can add title.keys after."))
        case .nothingDetected:
            return Line(tone: .problem, title: L10n.text("No prod.keys in this folder"),
                        detail: L10n.text("Choose the folder where Ryujinx is installed."))
        }
    }

    public var titleKeysLine: Line {
        switch titleKeys {
        case .present(let titles):
            return Line(tone: .ready, title: L10n.format("title.keys checked · %@ titles", [titles.formatted(.number.locale(L10n.context.formatLocale))]),
                        detail: nil)
        case .absent:
            return Line(tone: .optional, title: L10n.text("title.keys · optional"),
                        detail: L10n.text("Some eShop games, updates and DLC need it."))
        }
    }

    public var firmwareLine: Line {
        switch firmware {
        case .installed(let version):
            return Line(tone: .ready, title: L10n.format("Installed · %@", [version]),
                        detail: L10n.text("It works with your keys."))
        case .missing:
            return Line(tone: .todo, title: L10n.text("Not installed"),
                        detail: L10n.text("Choose a firmware .zip, .xci or folder. Oort checks it before Ryujinx installs it."))
        case .keysTooOld(let keys, let firmware):
            return Line(tone: .problem, title: L10n.text("Keys too old for this firmware"),
                        detail: L10n.format("Your keys go up to firmware %@; this one needs %@. Update your keys first.", [keys, firmware]))
        }
    }

    public var foldersLine: Line {
        switch folders {
        case .none:
            return Line(tone: .todo, title: L10n.text("No folder chosen"),
                        detail: L10n.text("Choose the folder that holds your game files."))
        case .empty(let folder):
            return Line(tone: .todo, title: L10n.text("No games found"),
                        detail: L10n.format("%@ has no file that %@ reads.", [folder, engineName]))
        case .found(let folder, let games, let skipped):
            return Line(tone: skipped > 0 ? .warning : .ready, title: L10n.format("%@ · %@ games read", [folder, String(games)]),
                        detail: skipped > 0
                            ? L10n.format("%@ .nsz or .xcz files skipped: decompress them to .nsp or .xci for %@.", [String(skipped), engineName])
                            : nil)
        }
    }

    /// What First steps says under its rows: a failed key choice first, then a folder still to choose or empty.
    public var firstStepsLine: Line? {
        if keysLine.tone == .problem { return keysLine }
        switch folders {
        case .none: return Line(tone: .todo, title: L10n.text("No folder chosen yet. You can add games later."), detail: nil)
        case .empty: return foldersLine
        case .found: return foldersLine.tone == .warning ? foldersLine : nil
        }
    }

    /// The Compatibility panel's head: the worst of the engine, the keys and, for Ryujinx, the firmware.
    public var overall: Line {
        let lines = [engineLine, keysLine] + (needsFirmware ? [firmwareLine] : [])
        if lines.contains(where: { $0.tone == .problem }) {
            return Line(tone: .problem, title: L10n.text("Something to fix"), detail: nil)
        }
        if lines.contains(where: { $0.tone == .todo }) {
            return Line(tone: .todo, title: L10n.text("To finish"), detail: nil)
        }
        return Line(tone: .ready, title: L10n.text("Ready to play"), detail: nil)
    }
}
