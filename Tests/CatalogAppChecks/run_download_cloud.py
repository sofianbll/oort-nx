#!/usr/bin/env python3
"""Check transfer motion and render the real Collection and Spotlight tiles offscreen."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from audit_probe_host import ROOT, run_host

HOST = r'''
import AppKit
import ArcanePorting
import CoreText
import Metal
import NXLibraryCore
@testable import NXLibrary
import SwiftUI

@main struct DownloadCloudProbe {
    static let seed: UInt64 = 0x5E1E4E
    static let folder = URL(fileURLWithPath: /* OUTPUT */, isDirectory: true)
    static let size = CGSize(width: 376, height: 302)

    @MainActor static func main() throws {
        setbuf(stdout, nil)
        assertFixtureHome()
        NSApplication.shared.setActivationPolicy(.prohibited)
        let font = folder.appendingPathComponent("MaterialIcons-Regular.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let palettes = try SelenePaletteCatalog.load(from: folder.appendingPathComponent("palettes.json"))
        let wanted = [("selene", "Selene"), ("vantablack", "Vantablack"), ("oort", "Oort / accents Vesper"),
                      ("catppuccin-latte", "Latte")]
        checkMotion()

        let home = AppData.profile.home
        let workspace = home.appendingPathComponent("synthetic")
        let title = "010000000000D000"
        let icon = workspace.appendingPathComponent("\(title)_build/extract/v0/icon.jpg")
        try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
        let illustration = ImageRenderer(content: Self.illustration.frame(width: 512, height: 512)).cgImage!
        try NSBitmapImageRep(cgImage: illustration).representation(using: .jpeg, properties: [:])!.write(to: icon)
        var game = PortedGame(name: "Lunar Observatory", url: home.appendingPathComponent("Fixture.app"),
                              platform: .macApp, sizeBytes: 0, modificationDate: .distantPast, titleId: title)
        game.workspacePath = workspace.path
        let model = CloudLibraryModel()
        let art = ArtworkStore()
        let box = BoxArtService(artwork: art, index: .init(directory: workspace))
        let item = SpotlightItem.game(game.id)

        func pair(_ state: CloudLibraryState, _ previous: DownloadCloudTileState?, _ seconds: Double,
                  _ palette: SelenePalette, _ intensity: DownloadCloudMotion.Intensity,
                  reduced: Bool = false, before: Bool = false, look: PortingTileLook = .normal) -> some View {
            model.states[game.id] = state
            return HStack(alignment: .center, spacing: 8) {
                CollectionCoverRow(games: [.init(nxnative: game)], selectedID: nil, artwork: art, boxArt: box,
                    boxArtIndexVersion: 0, officialName: { _ in nil }, needsMetadata: { _ in }, tileLook: { _ in look },
                    cloud: model, showsCloudBadges: true, onSelect: { _ in }, onActivate: { _ in })
                    .offset(x: -69, y: -(CollectionRow.bandHeight - CollectionRow.coverHeight) / 2 + 11)
                    .frame(width: 194, height: size.height, alignment: .topLeading).clipped()
                SpotlightRowView(items: [item], gamesByID: [game.id: game], selectedKey: nil, isEmptyFilter: nil,
                    artwork: art, tileLook: { _ in look }, cloud: model, showsCloudBadges: true,
                    onSelect: { _ in }, onActivate: { _ in })
                    .offset(x: -70, y: -5)
                    .frame(width: 174, height: 184, alignment: .topLeading).clipped()
            }
            .frame(width: size.width, height: size.height)
            .background(SeleneTheme.baseGradient(for: palette))
            .environment(\.seleneCanvas, .init(size: SeleneCanvas.design))
            .environment(\.seleneBackdropStyle, .init(palette: palette, animated: false))
            .environment(\.seleneReduceMotion, reduced)
            .environment(\.downloadCloudCapture, .init(seed: seed, time: seconds, intensity: intensity,
                                                      previous: previous, before: before))
        }

        // Render each state immediately: the two real rows read the same observable model.
        func frame(_ snapshot: Shot, _ palette: SelenePalette, _ intensity: DownloadCloudMotion.Intensity,
                   _ scale: CGFloat, reduced: Bool = false, before: Bool = false,
                   look: PortingTileLook = .normal) -> CGImage {
            let renderer = ImageRenderer(content: pair(snapshot.state, snapshot.previous, snapshot.time, palette,
                                                       intensity, reduced: reduced, before: before, look: look))
            renderer.scale = scale
            return renderer.cgImage!
        }

        let checkPalette = palette("selene", in: palettes)
        var pixelChecks = true
        func unchanged(_ first: CGImage, _ second: CGImage, _ label: String) {
            let differences = changedPixels(first, second)
            if differences != 0 {
                print("\(label): \(differences) differing pixels without particles")
                try? save(first, "diagnostic-\(label)-after")
                try? save(second, "diagnostic-\(label)-before")
                pixelChecks = false
            }
        }
        for shot in [Shot("idle", .init()), Shot("queue", queued()), Shot("failed", failed()),
                     Shot("upload", transfer(40, direction: .upload(.app))),
                     Shot("wait", ready()), Shot("already-completed", completed())] {
            unchanged(frame(shot, checkPalette, .fine, 1), frame(shot, checkPalette, .fine, 1, before: true), shot.label)
        }
        let moving = Shot("40%", transfer(40), time: 1.56)
        unchanged(frame(moving, checkPalette, .fine, 1, reduced: true),
                  frame(moving, checkPalette, .fine, 1, reduced: true, before: true), "reduced-running")
        // The shader percentage has its own wall-clock sheen; use the static preparation look for a pixel check.
        let build = PortingTileLook.preparing(step: 1, count: 2, title: "Fixture build", detail: "")
        unchanged(frame(moving, checkPalette, .fine, 1, look: build),
                  frame(moving, checkPalette, .fine, 1, before: true, look: build), "build-preparation")
        let withDots = frame(moving, checkPalette, .fine, 1)
        let plain = frame(moving, checkPalette, .fine, 1, before: true)
        // A running download really changes both call sites; the colour fill itself stays unchanged.
        for bounds in [CGRect(x: 0, y: 0, width: 194, height: 302), CGRect(x: 202, y: 60, width: 174, height: 184)] {
            let differences = changedPixels(withDots.cropping(to: bounds)!, plain.cropping(to: bounds)!)
            if differences == 0 || differences > 500 {
                print("Expected only particle pixels to change in \(bounds), got \(differences)")
                pixelChecks = false
            }
        }
        if pixelChecks {
            print("Both real rows: running dots present; build, reduced running, idle, queue, error, upload, wait, stale success pixel-identical.")
        }

        let shots: [Shot] = [
            .init("1 · 0 %", transfer(0), time: 0.30),
            .init("2 · 25 %", transfer(25), time: 1.23),
            .init("3 · 60 %", transfer(60), time: 2.76),
            .init("4 · Total inconnu", transfer(0, total: 0), time: 3.72),
            .init("5 · Vérification", verifying(), previous: .running(.app, 0.96), time: 0.14),
            .init("6 · Rassemblement", completed(), previous: .verifying(.app, 1), time: 0.22),
            .init("7 · Nuage Oort", completed(), previous: .verifying(.app, 1), time: 0.66),
            .init("8 · Repos", completed(), previous: .verifying(.app, 1), time: 1.12),
        ]
        for (id, label) in wanted {
            let palette = palette(id, in: palettes)
            for intensity in DownloadCloudMotion.Intensity.allCases {
                for scale in [CGFloat(1), 3] {
                    try strip(shots, title: "\(label) · \(intensity == .fine ? "Fine" : "Plus présente") · \(Int(scale))×",
                              scale: scale, file: "\(id)-\(intensity.rawValue)-\(Int(scale))x") {
                        frame($0, palette, intensity, scale)
                    }
                }
            }
        }
        try strip(shots, title: "Selene · Avant · remplissage seul", scale: 1, file: "avant") {
            frame($0, checkPalette, .fine, 1, before: true)
        }
        let reducedShots = Array(shots.prefix(5)) + [
            Shot("6 · Fondu", completed(), previous: .verifying(.app, 1), time: 0.10),
            Shot("7 · Le même nuage s’efface", completed(), previous: .verifying(.app, 1), time: 0.30),
            Shot("8 · Repos", completed(), previous: .verifying(.app, 1), time: 0.50),
        ]
        try strip(reducedShots, title: "Selene · Réduire les animations", scale: 1, file: "mouvement-reduit") {
            frame($0, checkPalette, .fine, 1, reduced: true)
        }

        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("video").path) {
            let palette = palette("oort", in: palettes)
            for i in 0..<126 {
                let t = Double(i) / 24
                let shot: Shot
                if t < 2.9 {
                    shot = Shot("", transfer(Int(t / 2.9 * 100)), time: t + 0.4)
                } else if t < 3.43 {
                    shot = Shot("", verifying(), previous: .running(.app, 0.99), time: t - 2.9)
                } else {
                    shot = Shot("", completed(), previous: .verifying(.app, 1), time: t - 3.43)
                }
                try save(frame(shot, palette, .fine, 1), "video/\(String(format: "%03d", i))")
            }
        }
        checkCompositor(palette: checkPalette)
        if !pixelChecks { exit(1) }
    }

    struct Shot {
        let label: String
        let state: CloudLibraryState
        let previous: DownloadCloudTileState?
        let time: Double
        init(_ label: String, _ state: CloudLibraryState, previous: DownloadCloudTileState? = nil, time: Double = 0) {
            self.label = label; self.state = state; self.previous = previous; self.time = time
        }
    }

    static func transfer(_ bytes: Int, total: Int = 100, direction: CloudLibraryAction = .restore(.app)) -> CloudLibraryState {
        var state = CloudLibraryState()
        state.action = direction
        state.progress = .init(direction == .upload(.app) ? .uploading : .downloading, kind: .app,
                               transfer: .init(bytesTransferred: Int64(bytes), totalBytes: Int64(total)))
        return state
    }

    static func queued() -> CloudLibraryState {
        var state = transfer(40); state.queued = true; return state
    }

    static func verifying() -> CloudLibraryState {
        var state = transfer(100); state.progress = .init(.verifying, kind: .app, downloadComplete: true); return state
    }

    static func ready() -> CloudLibraryState {
        var state = transfer(100); state.progress = .init(.readyToInstall, kind: .app, downloadComplete: true); return state
    }

    static func failed() -> CloudLibraryState {
        var state = CloudLibraryState(); state.issue = (.app, "Fixture failure", true); return state
    }

    static func completed() -> CloudLibraryState {
        var state = CloudLibraryState()
        state.completedItem = .app
        state.copies = [.app: .init(state: .synchronized, hasLocalCopy: true, bytes: 100,
                                   uploadedAt: nil, skippedRoots: [])]
        return state
    }

    static func palette(_ id: String, in palettes: [SelenePalette]) -> SelenePalette {
        palettes.first { $0.id == id }!
    }

    static var illustration: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(hex: 0x152050), Color(hex: 0x26447A), Color(hex: 0xE66C4C)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(hex: 0xF4D181)).frame(width: 145, height: 145).offset(x: 92, y: -237)
            Path { p in
                p.move(to: .init(x: 0, y: 393)); p.addLine(to: .init(x: 126, y: 236))
                p.addLine(to: .init(x: 274, y: 347)); p.addLine(to: .init(x: 378, y: 262))
                p.addLine(to: .init(x: 512, y: 355)); p.addLine(to: .init(x: 512, y: 512))
                p.addLine(to: .init(x: 0, y: 512)); p.closeSubpath()
            }.fill(Color(hex: 0x593863))
            Path { p in
                p.move(to: .init(x: 0, y: 453)); p.addQuadCurve(to: .init(x: 512, y: 367), control: .init(x: 272, y: 328))
                p.addLine(to: .init(x: 512, y: 512)); p.addLine(to: .init(x: 0, y: 512)); p.closeSubpath()
            }.fill(Color(hex: 0x211D3D))
        }
    }

    @MainActor static func strip(_ shots: [Shot], title: String, scale: CGFloat, file: String,
                                 frame: (Shot) -> CGImage) throws {
        let images = shots.map(frame)
        let view = VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text("Collection à gauche, Spotlight à droite · couvertures synthétiques")
                .font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(0..<2) { row in
                HStack(spacing: 10) {
                    ForEach(0..<4) { column in
                        let i = row * 4 + column
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shots[i].label).font(.system(size: 13, weight: .medium))
                            Image(decorative: images[i], scale: scale)
                        }
                    }
                }
            }
        }.padding(16).preferredColorScheme(.dark)
         .foregroundStyle(Color.white).background(Color(hex: 0x12141A))
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        try save(renderer.cgImage!, file)
    }

    static func save(_ image: CGImage, _ name: String) throws {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            .write(to: folder.appendingPathComponent(name + ".png"))
    }

    static func changedPixels(_ first: CGImage, _ second: CGImage) -> Int {
        precondition(first.width == second.width && first.height == second.height)
        func pixels(_ image: CGImage) -> Data {
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: context.data!, count: image.width * image.height * 4)
        }
        let a = pixels(first), b = pixels(second)
        // Ignore one quantization bit from the offscreen compositor; compare actual pixels, not PNG bytes.
        return stride(from: 0, to: a.count, by: 4).reduce(0) { count, index in
            count + ((index..<index + 4).contains { abs(Int(a[$0]) - Int(b[$0])) > 1 } ? 1 : 0)
        }
    }

    static func checkMotion() {
        typealias Motion = DownloadCloudMotion
        func motes(_ scene: Motion.Scene, _ t: Double, _ intensity: Motion.Intensity = .fine) -> [Motion.Mote] {
            Motion.frame(scene, seed: seed, at: t, intensity: intensity).filter { $0.opacity > 0 }
        }
        let a = motes(.drift(0.45), 1.11)
        precondition(a == motes(.drift(0.45), 1.11))
        precondition(a != Motion.frame(.drift(0.45), seed: seed + 1, at: 1.11, intensity: .fine).filter { $0.opacity > 0 })
        precondition(a.count > motes(.drift(0), 1.11).count && a.count < motes(.drift(1), 1.11).count)
        precondition(a.count < motes(.drift(0.45), 1.11, .present).count)
        precondition(a.allSatisfy { abs($0.center.y - 0.55) <= 0.13 })
        let unknown = motes(.drift(nil), 0.33)
        let repeated = motes(.drift(nil), 0.33 + Motion.Scene.drift(nil).duration)
        precondition(unknown.count == repeated.count && zip(unknown, repeated).allSatisfy {
            abs($0.center.y - $1.center.y) < 1e-9 && abs($0.opacity - $1.opacity) < 1e-9
        })
        precondition(unknown != motes(.drift(nil), 0.8))
        precondition(motes(.drift(.nan), 0.33) == unknown)
        let settleStart = motes(.settle(0.7), 0)
        let settleEnd = motes(.settle(0.7), 0.47)
        precondition(zip(settleStart, settleEnd).allSatisfy {
            abs($1.center.y - 0.30) <= abs($0.center.y - 0.30) && $1.opacity < $0.opacity
        })
        precondition(motes(.settle(0.7), 0.55).isEmpty && motes(.completion, 1.10).isEmpty)
        precondition(motes(.completion, 0.22).map(\.center) != motes(.completion, 0.65).map(\.center))
        precondition(motes(.fade, 0.14).map(\.center) == motes(.fade, 0.36).map(\.center))
        precondition(motes(.fade, 0.14)[0].opacity > motes(.fade, 0.36)[0].opacity && motes(.fade, 0.48).isEmpty)

        func project(_ state: CloudLibraryState, look: PortingTileLook = .normal) -> DownloadCloudTileState {
            .init(state, buildLook: look)
        }
        precondition(project(transfer(0, total: 0)) == .running(.app, nil))
        precondition(project(transfer(0)) == .running(.app, 0))
        precondition(project(transfer(43, direction: .restoreBuildCache)) == .running(.cache, 0.43))
        precondition(project(transfer(43, direction: .downloadSources)) == .running(.sources, 0.43))
        precondition(project(transfer(43), look: .filling(0.22)) == .idle)
        precondition(project(queued()).scene(after: project(transfer(40)), reduceMotion: false) == nil)
        precondition(project(failed()).scene(after: project(transfer(40)), reduceMotion: false) == nil)
        precondition(project(ready()).scene(after: project(verifying()), reduceMotion: false) == nil)
        precondition(project(verifying()).scene(after: project(transfer(99)), reduceMotion: false) == .settle(1))
        precondition(project(completed()).scene(after: .running(.sources, 1), reduceMotion: false) == nil)
        precondition(project(completed()).scene(after: project(verifying()), reduceMotion: false) == .completion)
        precondition(project(completed()).scene(after: project(ready()), reduceMotion: true) == .fade)
        precondition(project(completed()).scene(after: project(completed()), reduceMotion: false) == nil)
        print("Pure motion and real phase projection: PASS.")
    }

    @MainActor static func checkCompositor(palette: SelenePalette) {
        let now = CACurrentMediaTime()
        let colors = DownloadCloudColors(palette)
        let size = CGSize(width: 172, height: 278)
        let bounds = CGRect(x: 0, y: 0, width: 688, height: 834)
        let device = MTLCreateSystemDefaultDevice()!
        let queue = device.makeCommandQueue()!
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
                                  width: Int(bounds.width), height: Int(bounds.height), mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        for count in [0, 1, 6, 12] {
            let tiles = (0..<count).map { _ in DownloadCloudLayerView() }
            let start = ProcessInfo.processInfo.systemUptime
            let surface = CALayer()
            surface.frame = bounds
            surface.backgroundColor = NSColor.black.cgColor
            let renderer = CARenderer(mtlTexture: texture, options: [kCARendererMetalCommandQueue: queue])
            let counter = DrawCounter()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (i, tile) in tiles.enumerated() {
                let field = tile.root.sublayers!.first!
                field.frame = CGRect(x: CGFloat(i % 4) * size.width, y: CGFloat(i / 4) * size.height,
                                     width: size.width, height: size.height)
                surface.addSublayer(field)
                tile.apply(.init(scene: .drift(0.65), start: 0, colors: colors, seed: seed + UInt64(i), intensity: .fine),
                           size: size, now: now)
                for particle in field.sublayers ?? [] { particle.delegate = counter }
            }
            renderer.layer = surface
            renderer.bounds = bounds
            CATransaction.commit()
            CATransaction.flush()
            let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
            let fields = surface.sublayers ?? []
            let particles = fields.flatMap { $0.sublayers ?? [] }
            precondition(particles.count == count * 9)
            precondition(particles.allSatisfy { $0.contents != nil && $0.animation(forKey: "cloud")?.repeatCount == .infinity })
            func composite(_ offset: Double) -> [UInt8] {
                renderer.beginFrame(atTime: now + offset, timeStamp: nil)
                renderer.addUpdate(bounds)
                renderer.render()
                renderer.endFrame()
                let fence = queue.makeCommandBuffer()!
                fence.commit()
                fence.waitUntilCompleted()
                precondition(fence.status == .completed)
                let width = Int(bounds.width), height = Int(bounds.height)
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                texture.getBytes(&bytes, bytesPerRow: width * 4,
                                 from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                return bytes
            }
            let first = composite(0.03)
            let last = composite(0.63)
            precondition((first == last) == (count == 0), "\(count) tiles: expected compositor motion only with active dots")
            precondition(counter.redraws == 0)
            for tile in tiles { tile.clear() }
            precondition(fields.allSatisfy { $0.sublayers?.isEmpty != false && $0.animationKeys()?.isEmpty != false }
                && particles.allSatisfy { $0.animationKeys()?.isEmpty != false },
                "\(count) tiles: detach must leave no particle or implicit animation")
            print("\(count) tiles: \(particles.count) layers composited by Metal; \(counter.redraws) bitmap redraws; setup \(String(format: "%.2f", milliseconds)) ms; no animations left on detach.")
        }
    }

    final class DrawCounter: NSObject, CALayerDelegate {
        var redraws = 0
        func draw(_ layer: CALayer, in ctx: CGContext) { redraws += 1 }
    }
}
'''


def main():
    destination = Path(sys.argv[1]).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    with tempfile.TemporaryDirectory(prefix="download-proof-", dir="/private/tmp") as out:
        stage = Path(out)
        for asset in ["Selene/palettes.json", "Selene/Fonts/MaterialIcons-Regular.ttf"]:
            shutil.copyfile(ROOT / "Resources" / asset, stage / Path(asset).name)
        if ffmpeg:
            (stage / "video").mkdir()
        try:
            run_host(HOST.replace("/* OUTPUT */", json.dumps(str(stage))))
        finally:
            for image in stage.glob("*.png"):
                shutil.copyfile(image, destination / image.name)
            if ffmpeg and (stage / "video" / "125.png").is_file():
                subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "24",
                                "-i", str(stage / "video" / "%03d.png"), "-an", "-c:v", "libx264", "-threads", "4",
                                "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(destination / "transfert.mp4")],
                               check=True)


if __name__ == "__main__":
    main()
