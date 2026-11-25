#!/usr/bin/env python3
"""Open Collection sorting and deliver the native Play action to the real guards."""
from pathlib import Path
import subprocess
import tempfile

VIEWS = Path(__file__).resolve().parents[2] / 'Sources/NXLibrary/Views'
shell = (VIEWS / 'Shell/AppShellView.swift').read_text()
layers = (VIEWS / 'Shell/AppShellView+Layers.swift').read_text()
collection = (VIEWS / 'Collection/CollectionView.swift').read_text()
availability = shell[shell.index('    var nativeMenuAvailability:'):
                     shell.index('    /// A game the session')]
play = layers[layers.index('publisher(for: .nxLibraryPlayFocused)'):
              layers.index('        .onReceive(NotificationCenter.default.publisher(for: .nxLibraryOpenDetails)')]
play = play.split(' { _ in', 1)[1].strip().removesuffix('}')
sort = '\n'.join(line for line in collection.splitlines() if 'func openSort()' in line)
host = '''
import Foundation
enum LibraryMenuItem { case sort(Int) }
enum Route { case library, collection }
final class Router {
    var sortMenu: LibraryMenuItem?
    var route = Route.collection
    var isMenuPresented = false
    var isScreenshotViewerOpen = false
    var isSearchPresented = false
    var isPalettePresented = false
    var activityCenterFocus: Int?
}
struct Game {
    var isPlayableLocally = true
    enum Integration { case steam, nxnative }
    var integration = Integration.nxnative
    var nxnativeGame: Game? { self }
    let macShortcut: Int? = nil
}
final class AppViewModel {
    var showSetupCheck = false
    var isGameOptionsOpen = false
    var launchOverlay: Int?
    var currentFocusedGame: Game? = Game()
    var currentFocusedCatalogGame: Game? = Game()
    var isBuilding = false
    var catalogBuildRecoveries: [Int] = []
    var launches = 0
    let macShortcuts = Shortcuts()
    struct Shortcuts { let canEdit = true }
    let playRouter = PlayRouter()
    struct PlayRouter { func supports(_ integration: Game.Integration) -> Bool { true } }
    func pressPlay(_ game: Game) { launches += 1 }
    func launchGame(_ game: Game) { launches += 1 }
}
struct Settings { let settings = Values(); struct Values { let librarySort = 1 } }
struct NativeMenuAvailability {
    let general, palette, addMacApp, play, details, options, catalogRecovery: Bool
}
struct SteamPlayCoordinator {
    static let shared = Self()
    func canPlay(_ game: Game) -> Bool { false }
    func press(_ game: Game) {}
}
final class Shell {
    let router = Router()
    let viewModel = AppViewModel()
    var showsWelcome = false
    var profileFlow: Int?
    var isCloseGameOpen = false
    var nativeDialogOwnsInput = false
    var paletteAvailable = true
    var isHomeRoute = true
    // AVAILABILITY
    func receivePlay() {
        // PLAY
    }
}
final class Collection {
    let router: Router
    let settings = Settings()
    var sortMenu: LibraryMenuItem?
    init(router: Router) { self.router = router }
    // SORT
}
let shell = Shell()
let collection = Collection(router: shell.router)
precondition(shell.nativeMenuAvailability.play)
collection.openSort()
shell.receivePlay()
guard !shell.nativeMenuAvailability.play, !shell.nativeMenuAvailability.details,
      !shell.nativeMenuAvailability.options, shell.viewModel.launches == 0 else {
    print("FAIL: the Game menu can launch a game under Collection sorting")
    exit(1)
}
shell.router.sortMenu = nil
shell.receivePlay()
precondition(shell.viewModel.launches == 1)
print("Sort overlay: native Game commands are unavailable and Play delivery is suppressed")
'''
with tempfile.TemporaryDirectory(prefix='oort-sort-native-menu-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// AVAILABILITY', availability).replace('// PLAY', play).replace('// SORT', sort))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
