import OortLibrary

/// Shared folder wording for Setup, Settings and their pickers.
public enum GameFoldersCopy {
    public static let appsTitle = "Game apps"
    public static var appsAbout: String {
        L10n.text("Choose where to keep your game apps.")
    }
    public static var appsContents: String {
        L10n.text("Mac apps made when you choose Build.")
    }
    public static var appsPickerMessage: String {
        L10n.text("Choose where to keep your game apps. Put any existing nxnative games (.app) here. Change it later in Settings → Porting → Game folders.")
    }
    public static let sourcesTitle = "Game files"
    public static let keysTitle = "Keys"
    public static let appBadges = [".app"]
    public static let sourceBadges = FileBrowser.gameExtensions.map { "." + $0 }
    public static let keyBadges = ["prod.keys"]
    public static var sourcesContents: String {
        L10n.text("Your own Switch files: cartridge, eShop or update.") + " " +
        L10n.text("A .nup holds a Switch 2 game, with its updates and extras if included. An update can stand in for the base game.")
    }
    public static var keysContents: String {
        L10n.text("Your Switch key file lets Oort read protected game files. It stays on this Mac.")
    }

    public static func sourceFormats(extractedFolders: Bool) -> String {
        L10n.text("NSP, XCI, NSZ, XCZ or Switch 2 NUP files") + (extractedFolders ? L10n.text(", or extracted folders") : "")
    }

    public static func sourcesAbout(extractedFolders: Bool) -> String {
        L10n.format("Optional: %@ for building.", [String(describing: sourceFormats(extractedFolders: extractedFolders))])
    }

    public static func sourcesPickerMessage(extractedFolders: Bool) -> String {
        L10n.format("Choose a folder with your %@. Existing apps play without these files. Change it later in Settings → Porting → Game folders.", [String(describing: sourceFormats(extractedFolders: extractedFolders))])
    }
}
