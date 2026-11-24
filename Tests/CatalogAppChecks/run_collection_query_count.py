#!/usr/bin/env python3
"""Count Collection's actual render-time selection queries with synthetic catalog data."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / 'Sources/NXLibrary/Views/Collection/CollectionView.swift').read_text()
select = re.search(r'    (?:private )?func selected.*?(?=    // MARK: - Body)', source, re.S)[0]
snapshot = source[source.index('        let games = self.games'):source.index('        SeleneHomeChrome(')]
hints = re.search(r'rightHints: (contextHints\([^\n]*?\)) \+', source)[1]
task_key = re.search(r'\.task\(id: (art\.steamHeroTaskKey\([^\n]*?\))\)', source)[1]
hint_lookup = re.search(r'(    private func contextHints[^\n]*\{\n.*?)(?=        guard let game)', source, re.S)[1]
host = '''
import Foundation
struct PortedGame {}
enum Integration { case nxnative, steam }
struct CatalogGame {
    let id = UUID()
    let integration = Integration.nxnative
    let nxnativeGame: PortedGame? = PortedGame()
}
struct HintItem {
    enum Button { case y }
    init(_ button: Button, _ title: String) {}
}
enum L10n { static func text(_ title: String) -> String { title } }
struct SteamPlayCoordinator {
    static let shared = Self()
    func hint(for game: CatalogGame) -> [HintItem] { [] }
}
struct Art { func steamHeroTaskKey(_ game: CatalogGame?) -> UUID? { game?.id } }
final class Collection {
    let catalog = (0..<300).map { _ in CatalogGame() }
    lazy var viewModel = Model(librarySelection: .init(selectedGameID: catalog[0].id))
    struct Model {
        let librarySelection: Selection
        struct Selection { let selectedGameID: UUID? }
    }
    let art = Art()
    var queryCount = 0
    var games: [CatalogGame] { queryCount += 1; return catalog }
    // SELECT
    // HINT_LOOKUP
        return []
    }
    func evaluate() {
        // SNAPSHOT
        precondition(games.count == 300)
        _ = HINT_QUERY
        _ = HERO_KEY
    }
}
let collection = Collection()
collection.evaluate()
guard collection.queryCount == 1 else {
    print("FAIL: one render evaluates the 300-game query \\(collection.queryCount) times")
    exit(1)
}
print("Collection: one projection for selection, hints and Steam task identity")
'''
with tempfile.TemporaryDirectory(prefix='oort-collection-query-') as directory:
    check = Path(directory) / 'main.swift'
    binary = check.with_suffix('')
    check.write_text(host.replace('// SELECT', select).replace('// HINT_LOOKUP', hint_lookup)
                     .replace('// SNAPSHOT', snapshot).replace('HINT_QUERY', hints).replace('HERO_KEY', task_key))
    subprocess.run(['xcrun', 'swiftc', check, '-o', binary], check=True)
    subprocess.run([binary], check=True)
