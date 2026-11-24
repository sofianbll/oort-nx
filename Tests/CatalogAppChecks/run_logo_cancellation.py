#!/usr/bin/env python3
"""Exercise the real logo search path through a suspended, synthetic provider."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
loader = (ROOT / 'Sources/NXLibrary/Views/Spotlight/GameArtLoader.swift').read_text()
logo = loader[loader.index('    func logo(for game: PortedGame'):loader.index('    /// Decodes off')]
host = '''
import Foundation
class NSImage: NSObject {}
struct PortedGame {
    let id = UUID()
    let sources: [Source] = []
    struct Source { let url: URL }
    let url = URL(fileURLWithPath: "/synthetic")
    let name = "Fixture"
    let isSwitch2 = false
}
struct NintendoStoreMetadata {
    let name = "Fixture"
    let logoURL: URL? = nil
}
struct CatalogPersonalizations { func nxnativeKey(for game: PortedGame) -> String { game.name } }
enum Slot { case logo }
enum Platform { case switch2, `switch` }
struct ArtworkPicks {
    static let shared = Self()
    func url(titleID: String, slot: Slot) -> URL? { nil }
}
struct ArtworkStore {
    func cachedURL(titleID: String, kind: Slot) -> URL? { nil }
    func fetch(titleID: String, remoteURL: URL?, kind: Slot) async -> URL? { nil }
}
@MainActor enum OnlineArtwork {
    struct Hit { let url: URL; let fallback: URL? }
    static var requests = 0
    static var suspended: CheckedContinuation<Void, Never>?
    static func find(names: [String], slot: Slot, platform: Platform) async -> [Hit] {
        requests += 1
        if requests == 1 { await withCheckedContinuation { suspended = $0 } }
        return []
    }
}
@MainActor final class Loader {
    private var searchedOnline: Set<UUID> = []
    private let logos = NSCache<NSUUID, NSImage>()
    func cachedLogo(for game: PortedGame) -> NSImage? { logos.object(forKey: game.id as NSUUID) }
    static func decodeLogo(at url: URL) async -> NSImage? { nil }
    // LOGO
}
@main struct Check {
    @MainActor static func main() async {
        let game = PortedGame()
        let loader = Loader()
        let load = { @MainActor in
            await loader.logo(for: game, metadata: nil, artwork: ArtworkStore(),
                              personalizations: CatalogPersonalizations())
        }
        let task = Task { await load() }
        while OnlineArtwork.suspended == nil { await Task.yield() }
        task.cancel()
        OnlineArtwork.suspended?.resume()
        _ = await task.value
        _ = await load()
        guard OnlineArtwork.requests == 2 else {
            print("FAIL: cancellation suppressed the next logo request")
            exit(1)
        }
        _ = await load()
        precondition(OnlineArtwork.requests == 2, "Completed misses should not repeat")
        print("Logo search: cancellation permits retry; a completed miss stays cached")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='oort-logo-cancellation-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// LOGO', logo))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', source, '-o', executable], check=True)
    subprocess.run([executable], check=True, timeout=10)
