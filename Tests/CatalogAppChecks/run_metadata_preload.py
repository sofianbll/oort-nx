#!/usr/bin/env python3
"""Measure which thread executes the real model's cache preload entry point."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
model = (ROOT / 'Sources/NXLibrary/ViewModels/StoreMetadataModel.swift').read_text()
line = next(line for line in model.splitlines() if 'func preloadCachedStoreMetadata()' in line)
preload = model[model.index(line):
                model.index("    /// The store's metadata as fetched, before")]
host = '''
import Foundation
typealias AppLocale = String
enum L10n { static let context = "en" }
struct PortedGame: Sendable {
    let id = UUID()
    let titleId: String? = "0100000000001000"
}
struct NintendoStoreMetadata: Sendable { let readOnMain: Bool }
struct Service: Sendable {
    func cachedForDisplay(for id: String, locale: String) -> NintendoStoreMetadata? {
        .init(readOnMain: Thread.isMainThread)
    }
    func isInLanguage(_ metadata: NintendoStoreMetadata, locale: String) -> Bool { true }
}
struct App {
    let libraryGames = (0..<300).map { _ in PortedGame() }
    var currentFocusedGame: PortedGame? { libraryGames.last }
}
@MainActor final class Store {
    let app = App()
    let storeMetadataService = Service()
    var metadataLocaleGeneration = UUID()
    var cachedMetadataPreload: Task<Void, Never>?
    var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    func setStoreMetadata(_ metadata: NintendoStoreMetadata, for game: PortedGame) {
        precondition(Thread.isMainThread)
        storeMetadata[game.id] = metadata
    }
    func queueLanguageFetch(_ games: [PortedGame]) { precondition(games.isEmpty) }
    // PRELOAD
}
@main struct Check {
    @MainActor static func main() async {
        let store = Store()
        store.preloadCachedStoreMetadata()
        for _ in 0..<250 where store.storeMetadata.count < 300 {
            try? await Task.sleep(for: .milliseconds(1))
        }
        guard store.storeMetadata.count == 300,
              !store.storeMetadata.values.contains(where: { $0.readOnMain }) else {
            print("FAIL: cache preload reads on the main thread or loses results")
            exit(1)
        }
        print("Metadata preload: 300 synthetic cache reads off the main thread, applied on main")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='oort-metadata-preload-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// PRELOAD', preload))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
