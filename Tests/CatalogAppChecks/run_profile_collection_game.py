#!/usr/bin/env python3
"""Exercise native menu target resolution without launching a game."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2] / 'Sources/NXLibrary/ViewModels'
controller = (ROOT / 'AppViewModel+Controller.swift').read_text().split('extension AppViewModel', 1)[1]
sources = (ROOT / 'AppViewModel+Sources.swift').read_text()
selection = sources[sources.index('    var currentFocusedCatalogGame'):].rsplit('}', 1)[0]
host = '''
import Foundation
struct PortedGame: Equatable {
    let id = UUID()
    var isHidden = false
}
struct CatalogGame {
    let id: UUID
    let nxnativeGame: PortedGame?
}
enum Route: Equatable { case detail(UUID), library, collection, profileCollection(Int) }
struct Router { var route: Route }
protocol History {}
struct NoPlayHistory: History {}
struct Query {
    func applyCatalog(to games: [CatalogGame], history: History) -> [CatalogGame] {
        fatalError("A profile card must not use the general collection query")
    }
}
struct Selection {
    var selectedGameID: UUID?
    var query = Query()
}
struct Spotlight { var selectedGameID: UUID? }
struct AppViewModel {
    var router: Router?
    var libraryGames: [PortedGame] = []
    var spotlight = Spotlight()
    var librarySelection: Selection
    var visibleCatalogGames: [CatalogGame]
    var playSessionStore: History?
    // CATALOG_SELECTION
}
// GAME_SELECTION
let game = PortedGame()
let steam = UUID()
var vm = AppViewModel(router: Router(route: .profileCollection(0)),
                      librarySelection: Selection(selectedGameID: game.id),
                      visibleCatalogGames: [.init(id: game.id, nxnativeGame: game),
                                            .init(id: steam, nxnativeGame: nil)])
guard vm.currentFocusedGame == game else {
    print("FAIL: the native Game menu has no Switch target on a profile card")
    exit(1)
}
vm.librarySelection.selectedGameID = steam
precondition(vm.currentFocusedGame == nil && vm.currentFocusedCatalogGame?.id == steam)
vm.librarySelection.selectedGameID = UUID()
precondition(vm.currentFocusedGame == nil)
print("Profile Collection: selected Switch game resolves; Steam and stale selections stay separate")
'''
with tempfile.TemporaryDirectory(prefix='oort-profile-collection-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// CATALOG_SELECTION', selection)
                      .replace('// GAME_SELECTION', 'extension AppViewModel' + controller))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
