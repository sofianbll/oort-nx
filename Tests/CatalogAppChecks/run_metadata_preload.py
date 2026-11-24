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
start = model.index('    func clearMetadataCache()')
clear = model[start:model.index('\n    }\n', start) + len('\n    }\n')]
host = '''
import Foundation
typealias AppLocale = String
enum L10n { static var context = "en" }
struct PortedGame: Sendable {
    let id = UUID()
    let titleId: String? = "0100000000001000"
}
struct NintendoStoreMetadata: Sendable { let readOnMain: Bool; let locale: String }
final class ReadGate: Sendable {
    let reads: AsyncStream<Void>
    let read: AsyncStream<Void>.Continuation
    let resume = DispatchSemaphore(value: 0)
    init() { (reads, read) = AsyncStream.makeStream() }
}
struct Service: Sendable {
    var gate: ReadGate?
    func cachedForDisplay(for id: String, locale: String) -> NintendoStoreMetadata? {
        let entry = NintendoStoreMetadata(readOnMain: Thread.isMainThread, locale: gate == nil ? locale : "en")
        if let gate { gate.read.yield(()); gate.resume.wait() }
        return entry
    }
    func isInLanguage(_ metadata: NintendoStoreMetadata, locale: String) -> Bool { metadata.locale == locale }
    func clearCache() {}
}
struct WikipediaDescriptionService {
    static let shared = Self()
    func clearCache() {}
}
struct App {
    var libraryGames = (0..<300).map { _ in PortedGame() }
    var currentFocusedGame: PortedGame? { libraryGames.last }
}
@MainActor final class Store {
    var app = App()
    var storeMetadataService = Service()
    var metadataLocaleGeneration = UUID()
    var cachedMetadataPreload: Task<Void, Never>?
    var localizedMetadataRefresh: Task<Void, Never>?
    var languageFetchResume: Task<Void, Never>?
    var languageFetchQueue: [PortedGame] = []
    var languageFetchWaiting: [PortedGame] = []
    var storeMetadataLoading: Set<UUID> = []
    var storeMetadataErrors: [UUID: String] = [:]
    var storeMetadata: [UUID: NintendoStoreMetadata] = [:]
    var storeMetadataOriginals: [UUID: NintendoStoreMetadata] = [:]
    func setStoreMetadata(_ metadata: NintendoStoreMetadata, for game: PortedGame) {
        precondition(Thread.isMainThread)
        storeMetadataOriginals[game.id] = metadata
        storeMetadata[game.id] = metadata
    }
    func queueLanguageFetch(_ games: [PortedGame]) { languageFetchQueue += games }
    // PRELOAD
    // CLEAR
}
@main struct Check {
    @MainActor static func main() async {
        let store = Store()
        store.preloadCachedStoreMetadata()
        await store.cachedMetadataPreload?.value
        guard store.storeMetadata.count == 300,
              !store.storeMetadata.values.contains(where: { $0.readOnMain }) else {
            print("FAIL: cache preload reads on the main thread or loses results")
            exit(1)
        }
        for locale in ["en", "fr"] {
            let store = Store()
            L10n.context = locale
            store.app.libraryGames = [PortedGame()]
            let gate = ReadGate()
            store.storeMetadataService.gate = gate
            store.preloadCachedStoreMetadata()
            let preload = store.cachedMetadataPreload
            for await _ in gate.reads { break }
            store.clearMetadataCache()
            gate.resume.signal()
            await preload?.value
            guard store.storeMetadata.isEmpty, store.storeMetadataOriginals.isEmpty,
                  store.languageFetchQueue.isEmpty else {
                print("FAIL: a completed disk read restores cleared metadata or queues a translation (\\(locale))")
                exit(1)
            }
            store.storeMetadataService.gate = nil
            store.preloadCachedStoreMetadata()
            await store.cachedMetadataPreload?.value
            precondition(store.storeMetadata.values.first?.locale == locale, "New reads still work after a clear")
        }
        print("Metadata preload: 300 synthetic cache reads off the main thread, applied on main")
        print("Metadata preload: clearing discards in-flight reads and permits new loads (EN/FR)")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='oort-metadata-preload-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// PRELOAD', preload).replace('// CLEAR', clear))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', source, '-o', executable], check=True)
    subprocess.run([executable], check=True, timeout=10)
