#!/usr/bin/env python3
"""Render the real Mods band with each game's page offsets, without windows or app data."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
import sys  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import names  # noqa: E402  architecture/names.json
BIN = ROOT / '.build/debug'
VIEWS = ROOT / 'Sources/NXLibrary/Views'


def excerpt(path, start, end):
    text = (VIEWS / path).read_text()
    first = text.index(start)
    return text[first:text.index(end, first)]


host = r'''
import AppKit
import SwiftUI
import NXLibraryCore
import ArcanePorting

private struct MotionKey: EnvironmentKey { static let defaultValue = true }
private struct LocaleKey: EnvironmentKey { static let defaultValue = L10n.context }
extension EnvironmentValues {
    var seleneReduceMotion: Bool { self[MotionKey.self] }
    var nxAppLocale: AppLocale { self[LocaleKey.self] }
}
enum SeleneTheme {
    static let focus = Color.red
    static let glassSolid = Color.gray
    static let ink = Color.white
    static let ink60 = Color.gray, ink75 = Color.gray, ink82 = Color.gray, artShade = Color.black, artInk = Color.white
}
struct OortTag: View {
    enum Preset { case quiet, panel, art }
    let text: String
    var preset: Preset = .quiet
    var body: some View { Text(text) }
}
extension View { func oortRing(_ on: Bool, radius: CGFloat, gap: CGFloat) -> some View { overlay(RoundedRectangle(cornerRadius: radius + gap).strokeBorder(Color.red, lineWidth: on ? 3 : 0).padding(-gap)) } }
enum SpotlightScreenshotStrip {
    static let motion = Animation.easeOut(duration: 0.25)
''' + excerpt('Spotlight/SpotlightScreenshotStrip.swift', '    struct Style:', '    @Environment') + r'''
}
struct GameBananaImageView: View {
    let url: URL?
    let maxPixelSize: Int
    var body: some View { Color.gray }
}
struct MaterialIconView: View {
    let size: CGFloat
    init(_ icon: MaterialIcon, size: CGFloat) { self.size = size }
    var body: some View { Color.white.frame(width: size, height: size) }
}
final class GameBananaBandModel: ObservableObject {
    enum Phase { case idle, ready }
    enum MoreState { case hidden, available, loading, failed }
    enum InstallState { case downloading(Double), installing, failed, done }
    let displayedMods: [AvailableMod]
    let statusTiles: [ModsBandAction] = [.wrongGame, .moreMods]
    let canSearchMods = true
    let phase = Phase.ready
    let moreState = MoreState.available
    let installs: [Int: InstallState] = [:]
    let matchedName: String? = "Fixture"
    func statusLine(context: AppLocale) -> String? { nil }
    func candidate(_ id: Int) -> GameBananaGame? { nil }

    init(onlineCount: Int) {
        displayedMods = (0..<onlineCount).map {
            AvailableMod(id: $0, rank: $0, name: "Mod \($0)", author: "Fixture", avatarURL: nil,
                         images: [], thumbnailURL: nil, version: "", updated: .distantPast,
                         pageURL: URL(string: "https://gamebanana.com")!, description: "", likes: 0, downloads: 0,
                         files: [])
        }
    }
}
struct ModsBandHost { let tiles: [ModsBandTile] }
''' + excerpt('Detail/DetailsBands.swift', 'struct DetailsBandTitle: View', '/// Band 1:') + \
    excerpt('Detail/DetailsBands.swift', 'struct DetailsModsBand: View', '/// An image from') + r'''
struct GameDetailView {
    let canvas: SeleneCanvas
    let focus: DetailsFocus
    let modsHost: ModsBandHost
    var currentModel: (mods: [LocalMod]?, bands: DetailsFocus.Bands) {
        ([], DetailsFocus.Bands(mods: modsHost.tiles.count))
    }
''' + excerpt('Detail/GameDetailView.swift', '    private var pageMask:', '    private func aboutLookup(') + r'''
    @MainActor func viewport(_ band: DetailsModsBand) -> some View {
        Color.clear.overlay(alignment: .topLeading) {
            band.offset(x: canvas.u(110), y: canvas.u(Self.modsBandTop + pageShift))
        }
        .frame(width: canvas.stageSize.width, height: canvas.stageSize.height)
        .clipped()
        .offset(x: canvas.stageOrigin.x, y: canvas.stageOrigin.y)
        .frame(width: canvas.size.width, height: canvas.size.height, alignment: .topLeading)
        .mask(pageMask)
    }
}
enum SpotlightPageBlock { case head, genres, strip, description, mods, more, about }
struct SpotlightView {
    static let moreGap: CGFloat = 72
    let canvas: SeleneCanvas
    let blocks: [SpotlightPageBlock: CGFloat]
    let modsHost: ModsBandHost
    func storeOffset() -> CGFloat { fatalError("Not the store") }
''' + excerpt('Spotlight/SpotlightView+PageLayout.swift', '    static let pageTravel:', '    /// Between About this game') + r'''
    @MainActor func viewport(_ band: DetailsModsBand, offset: CGFloat) -> some View {
        Color.clear.overlay(alignment: .topLeading) {
            band.offset(x: canvas.u(110), y: canvas.u(420 + 72) + (blocks[.description] ?? 0) + offset)
        }
        .frame(width: canvas.size.width, height: canvas.size.height)
        .mask(pageMask)
    }
}

@main struct Check {
    @MainActor static func render(_ view: some View, canvas: SeleneCanvas) -> CGImage {
        ImageRenderer(content: view.environment(\.seleneCanvas, canvas)).cgImage!
    }

    // A complete ring has both its upper and its lower red edge in the centre of the focused tile.
    @MainActor static func ringHeight(_ image: CGImage, column: Int, canvas: SeleneCanvas) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let style = SpotlightScreenshotStrip.Style.details
        let x = Int(canvas.u(110 + CGFloat(column) * (style.tileWidth + style.gap) + style.tileWidth / 2))
        let edges = (0..<bitmap.pixelsHigh).filter { y in
            guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
            return pixel.alphaComponent > 0.90 && pixel.redComponent > pixel.greenComponent + 0.40
        }
        return (edges.last ?? 0) - (edges.first ?? 0)
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var failures = 0
        for size in [CGSize(width: 1920, height: 1080), CGSize(width: 1280, height: 800)] {
            let canvas = SeleneCanvas(size: size)
            for (count, indices) in [(1, [0]), (24, [0, 26, 27]), (60, [0, 26, 63])] {
                let model = GameBananaBandModel(onlineCount: count)
                let tiles = DetailsModsBand.tiles(mods: [], gameBanana: model)
                let modsHost = ModsBandHost(tiles: tiles)
                let bands = DetailsFocus.Bands(mods: tiles.count)
                let last = tiles.count - 1
                for index in indices {
                    let band = DetailsModsBand(mods: [], records: [:], gameBanana: model,
                                               focusedIndex: index, onFocus: { _ in }, onOpen: { _ in })
                    let height = render(band, canvas: canvas).height
                    let spotlight = SpotlightView(canvas: canvas, blocks: [
                        .description: canvas.u(520), .mods: CGFloat(height) + canvas.u(72)
                    ], modsHost: modsHost)
                    var state = SpotlightState(focus: .mods)
                    var focus = DetailsFocus()
                    let column = index % ModsBandLayout.columns
                    state.modsIndex = min(column, last)
                    focus.focus(zone: DetailsFocus.modsZone, index: column, in: bands)
                    for _ in 0..<(index / ModsBandLayout.columns) {
                        _ = state.moveDown(selectedIsGame: true, screenshotCount: 0, modsCount: bands.mods)
                        _ = focus.down(in: bands)
                    }
                    precondition(state.modsIndex == index && focus.mod == index, "Down reaches the focused tile")
                    let details = GameDetailView(canvas: canvas, focus: focus, modsHost: modsHost)
                    let targets = [("Spotlight", render(spotlight.viewport(band, offset: spotlight.pageOffset(state)),
                                                         canvas: canvas)),
                                   ("Details", render(details.viewport(band), canvas: canvas))]
                    for (label, image) in targets {
                        let ring = ringHeight(image, column: index % ModsBandLayout.columns, canvas: canvas)
                        if let folder = ProcessInfo.processInfo.environment["NX_TEST_MODS_SNAPSHOTS"] {
                            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                            try! png.write(to: URL(fileURLWithPath: folder)
                                .appendingPathComponent("\(label)-\(Int(size.width))-\(count)-\(index).png"))
                        }
                        if ring < Int(canvas.u(158)) {
                            print("FAIL: \(label) \(size), \(count) mods, focus \(index), opaque ring height \(ring)")
                            failures += 1
                        }
                    }
                    if index == last {
                        let wheelEnd = spotlight.pageScrollEnd(hasMore: false)
                        if spotlight.visibleModIndex(at: wheelEnd, keeping: last, count: tiles.count) != last ||
                           spotlight.visibleModIndex(at: wheelEnd, keeping: column, count: tiles.count) == nil ||
                           (count == 60 && spotlight.visibleModIndex(at: wheelEnd, keeping: column, count: tiles.count) == column) {
                            print("FAIL: wheel cannot reach or select a visible row at the end, \(size), \(count) mods")
                            failures += 1
                        }
                    }
                }
            }
        }
        if failures > 0 { exit(1) }
        print("Mods band: full focus ring in Spotlight and Details at 1920×1080 and 1280×800.")
    }
}
'''

with tempfile.TemporaryDirectory(prefix='mods-band-scroll-check-') as folder:
    scratch = Path(folder)
    swift = scratch / 'check.swift'
    swift.write_text(host)
    executable = scratch / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-I', str(BIN), str(swift),
                    str(VIEWS / 'Theme/SeleneCanvasEnvironment.swift'),
                    str(VIEWS / 'Components/SeleneBottomScrim.swift'),
                    *map(str, names.objects(BIN)),
                    '-o', str(executable)], cwd=ROOT, check=True)
    subprocess.run([str(executable)], check=True,
                   env=dict(os.environ, PACKAGE_RESOURCE_BUNDLE_PATH=str(BIN)))
