#!/usr/bin/env python3
"""Exercise the real logo search path through a suspended, synthetic provider."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
loader = (ROOT / 'apps/mac/OortMac/Views/Spotlight/GameArtLoader.swift').read_text()
logo = loader[loader.index('    /// Games already looked up online'):loader.index('    private init()')] + \
    loader[loader.index('    func logo(for game: PortedGame'):loader.index('    static func decodedCost')]
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
    func fetch(titleID: String, remoteURL: URL?, kind: Slot) async -> URL? { remoteURL }
}
@MainActor enum OnlineArtwork {
    struct Hit { let url: URL; let fallback: URL? }
    static var requests = 0
    static var suspended: CheckedContinuation<Void, Never>?
    static let image = URL(fileURLWithPath: "/found-logo")
    static func find(names: [String], slot: Slot, platform: Platform) async -> [Hit] {
        requests += 1
        if requests == 1 { await withCheckedContinuation { suspended = $0 } }
        return requests == 2 ? [Hit(url: image, fallback: nil)] : []
    }
}
@MainActor final class Loader {
    private let logos = NSCache<NSUUID, NSImage>()
    func cachedLogo(for game: PortedGame) -> NSImage? { logos.object(forKey: game.id as NSUUID) }
    static var returning = false
    static func decodeLogo(at url: URL) async -> NSImage? {
        if returning {
            returning = false
            // The old request may resume only after the returning call reaches its next suspension.
            OnlineArtwork.suspended?.resume()
        }
        return url == OnlineArtwork.image ? NSImage() : nil
    }
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
        Loader.returning = true
        let returned = await load()
        _ = await task.value
        guard returned != nil, OnlineArtwork.requests == 2 else {
            print("FAIL: returning before the cancelled search exits loses the available logo")
            exit(1)
        }
        precondition(loader.cachedLogo(for: game) != nil)
        let missing = PortedGame()
        for _ in 0..<2 {
            let image = await loader.logo(for: missing, metadata: nil, artwork: ArtworkStore(),
                                          personalizations: CatalogPersonalizations())
            precondition(image == nil)
        }
        precondition(OnlineArtwork.requests == 3, "Completed misses should not repeat")
        print("Logo search: rapid return finds the logo; a completed miss stays cached")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='oort-logo-cancellation-') as directory:
    source = Path(directory) / 'Check.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// LOGO', logo))
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', source, '-o', executable], check=True)
    subprocess.run([executable], check=True, timeout=10)
