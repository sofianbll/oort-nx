#!/usr/bin/env python3
"""Send real Collection input commands with no games and record their effects."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4] / 'apps/mac/OortMac/Views/Collection'
inputs = (ROOT / 'CollectionView+Input.swift').read_text()
handle = inputs[inputs.index('    func handle('):inputs.index('    func activateCatalog(')]
host = '''
import Foundation
enum GamepadAction: Equatable {
    case navigateLeft, navigateRight, tabPrevious, tabNext, navigateUp, navigateDown, confirm, cancel
    case jumpToStart, jumpToEnd, rightStickPress, secondaryAction, contextAction, view, search, browseSearch, menu, menuHold, controlCenter, fullMenu, profiles, notice
}
enum LibrarySortMenu {
    static func handle(_ action: GamepadAction, focused: inout Int?, choose: (Int) -> Void) {}
}
enum SpotlightTopBar { static func openProfile() {} }
struct Filter { func shifted(by step: Int, in tabs: [Int]) -> Self { self } }
struct Game {
    let id = UUID()
    var isPlayableLocally = true
    var isCloudSourcePlaceholder = false
    enum Integration { case steam, native }
    var integration = Integration.native
    let macShortcut: Int? = nil
}
enum Route { case library, startUp, collection }
final class Router {
    var sortMenu: Int?
    var route = Route.collection
    var isSearchPresented = false
    var isMenuPresented = false
    var adds = 0
    func openAddGame() { adds += 1 }
    func showDetail(_ id: UUID) {}
    func back() {}
    func setInitialRoute(_ route: Route) {}
    func openSettings(_ route: Route) {}
    func handleIntegrationBar(_ action: GamepadAction, profileFocused: inout Bool, hasProfile: Bool) -> Bool { false }
}
struct Settings { let settings = Values(); struct Values { let viewButtonSwitches = true; let libraryTabs: [Int] = [] } }
struct Cloud { func downloadItem(for game: Game) -> Int? { nil } }
enum Origin { case collection }
struct SoundEffectService {
    static let shared = Self()
    enum Sound { case focus, click }
    func play(_ sound: Sound) {}
}
final class Model {
    var imports = 0
    var isScanningLibrary = false
    var gamesWithFilesHere: Set<UUID> = []
    let macShortcuts = Shortcuts()
    struct Shortcuts { func showTileOptions(_ game: Game) {} }
    let librarySelection = Selection()
    final class Selection {
        var selectedGameID: UUID?
        func moveIDs(_ ids: [UUID], by step: Int) -> UUID? { nil }
        func jumpIDs(_ ids: [UUID], toEnd: Bool) -> UUID? { nil }
    }
    func importExistingBuilds() { imports += 1 }
    func openSteamOptions(_ game: Game, from origin: Origin) {}
    func openGameOptions(_ game: Game, from origin: Origin) {}
}
final class Collection {
    let router = Router()
    let viewModel = Model()
    let settings = Settings()
    let cloud = Cloud()
    let filter = Filter()
    var sortMenu: Int?
    var profileFocused = false
    let integrationBar: Int? = nil
    var profile: Int?
    var profileCard: Int?
    var hasAnyGame = false
    var importFocused = false
    var showsEmptyActions: Bool { profileCard == nil && !hasAnyGame && !viewModel.isScanningLibrary }
    let games: [Game] = []
    let selectedCatalogGame: Game? = nil
    let selectedGame: Game? = nil
    func setSort(_ sort: Int) {}
    func setFilter(_ filter: Filter) {}
    func openSort() {}
    func choose(_ item: Int) {}
    func activateCatalog(_ record: Game) {}
    // HANDLE
}
let collection = Collection()
collection.handle(.navigateRight)
collection.handle(.confirm)
guard collection.viewModel.imports == 1, collection.router.adds == 0 else {
    print("FAIL: Right then A on empty Collection opens Add Game rather than importing builds")
    exit(1)
}
collection.handle(.navigateLeft)
collection.handle(.confirm)
precondition(collection.viewModel.imports == 1 && collection.router.adds == 1)
collection.viewModel.isScanningLibrary = true
collection.handle(.navigateRight)
collection.handle(.confirm)
precondition(collection.viewModel.imports == 1 && collection.router.adds == 1)
print("Empty Collection: Right+A imports, Left+A opens Add Game, scanning suppresses both")
'''
with tempfile.TemporaryDirectory(prefix='oort-empty-collection-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// HANDLE', handle))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
