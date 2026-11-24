#!/usr/bin/env python3
"""Record the actual hero cache configuration and insertion costs."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2] / 'Sources/NXLibrary/Views/Spotlight'
art = (ROOT / 'GameArtLoader.swift').read_text()
played = (ROOT / 'GameArtLoader+Played.swift').read_text()
configuration = art[art.index('    private init()'):art.index('    func cachedHero')]
native = next(line for line in art.splitlines() if 'heroes.setObject(' in line)
steam = [line for line in played.splitlines() if 'steamArt.setObject(' in line]
cost = ''
if '    static func decodedCost(' in art:
    cost = art[art.index('    static func decodedCost('):art.index('    /// Decodes off')]
host = '''
import Foundation
struct Game { let id = UUID() }
struct Image {
    let representations = [Representation()]
    struct Representation { let pixelsWide = 2560, pixelsHigh = 1440 }
}
final class Cache<Key> {
    var countLimit = 0
    var totalCostLimit = 0
    var cost = 0
    func setObject(_ image: Image, forKey key: Key, cost: Int = 0) { self.cost = cost }
}
final class Loader {
    private let heroes = Cache<NSUUID>()
    private let logos = Cache<NSUUID>()
    let steamArt = Cache<NSString>()
    // CONFIG
    // COST
    static func check() {
        let loader = Loader()
        let game = Game(), image = Image()
        loader.native(game: game, image: image)
        loader.steamHero(image)
        guard loader.heroes.totalCostLimit > 0, loader.steamArt.totalCostLimit > 0,
              loader.heroes.cost == 14_745_600, loader.steamArt.cost == 14_745_600 else {
            print("FAIL: 2560×1440 hero insertions have no decoded-byte cost or budget")
            exit(1)
        }
        loader.steamLogo(image)
        precondition(loader.steamArt.cost == 14_745_600, "Steam logos share the same cache budget")
        print("Hero cache: Switch and Steam insertions charge decoded bytes against a byte limit")
    }
    func native(game: Game, image: Image?) {
        // NATIVE
    }
    func steamHero(_ image: Image) {
        let key = "hero" as NSString
        // STEAM_HERO
    }
    func steamLogo(_ image: Image) {
        let key = "logo" as NSString
        // STEAM_LOGO
    }
}
typealias NSImage = Image
Loader.check()
'''
with tempfile.TemporaryDirectory(prefix='oort-hero-budget-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// CONFIG', configuration).replace('// COST', cost)
                      .replace('// NATIVE', native).replace('// STEAM_HERO', steam[0])
                      .replace('// STEAM_LOGO', steam[1]))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
