#!/usr/bin/env python3
"""Check download tiles; render real rows or measure isolated layers in a visible synthetic window."""
import argparse
import json
import shutil
import subprocess
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
    enum Cover: String, CaseIterable {
        case black, white, yellow, busy, title
        static let art: [Self] = [.black, .white, .yellow, .busy]
    }

    @MainActor static func main() throws {
        setbuf(stdout, nil)
        assertFixtureHome()
        NSApplication.shared.setActivationPolicy(/* ONSCREEN */ ? .accessory : .prohibited)
        let font = folder.appendingPathComponent("MaterialIcons-Regular.ttf")
        precondition(CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil))
        let palettes = try SelenePaletteCatalog.load(from: folder.appendingPathComponent("palettes.json"))
        let wanted = [("selene", "Selene"), ("vantablack", "Vantablack"), ("catppuccin-latte", "Latte")]
        checkMotion()
        let checkPalette = palette("selene", in: palettes)
        if /* ONSCREEN */ {
            try checkWindow(checkPalette)
            return
        }

        let home = AppData.profile.home
        let workspace = home.appendingPathComponent("synthetic")
        var fixtures: [Cover: PortedGame] = [:]
        for (i, face) in Cover.allCases.enumerated() {
            let title = "010000000000D00\(i)"
            let icon = workspace.appendingPathComponent("\(title)_build/extract/v0/icon.jpg")
            try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
            let illustration = ImageRenderer(content: artFor(face).frame(width: 512, height: 512)).cgImage!
            try NSBitmapImageRep(cgImage: illustration).representation(using: .jpeg, properties: [:])!.write(to: icon)
            var game = PortedGame(name: "Lunar Observatory", url: home.appendingPathComponent("Fixture-\(face).app"),
                                   platform: .macApp, sizeBytes: 0, modificationDate: .distantPast, titleId: title)
            game.workspacePath = workspace.path
            fixtures[face] = game
            if face != .title {
                let portraitSize = CGSize(width: 344, height: 556)
                let portrait = ImageRenderer(content: artFor(face).frame(width: portraitSize.width,
                                                                         height: portraitSize.height)).cgImage!
                CoverArtMemo.shared.setObject(NSImage(cgImage: portrait, size: portraitSize),
                    forKey: CoverArtMemo.key(game.id, revision: ArtworkPicks.shared.revision))
            }
        }
        let model = CloudLibraryModel()
        let art = ArtworkStore()
        let box = BoxArtService(artwork: art, index: .init(directory: workspace))

        func pair(_ state: CloudLibraryState, _ previous: DownloadCloudTileState?, _ seconds: Double,
                  _ palette: SelenePalette, _ intensity: DownloadCloudMotion.Intensity,
                  reduced: Bool = false, before: Bool = false, look: PortingTileLook = .normal,
                  cover: Cover = .title, scrimsOnly: Bool = false) -> some View {
            let game = fixtures[cover]!
            let item = SpotlightItem.game(game.id)
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
                                                      previous: previous, before: before, scrimsOnly: scrimsOnly))
        }

        // Render each state immediately: the two real rows read the same observable model.
        func frame(_ snapshot: Shot, _ palette: SelenePalette, _ intensity: DownloadCloudMotion.Intensity,
                   _ scale: CGFloat, reduced: Bool = false, before: Bool = false,
                   look: PortingTileLook = .normal, cover: Cover = .title, scrimsOnly: Bool = false) -> CGImage {
            let renderer = ImageRenderer(content: pair(snapshot.state, snapshot.previous, snapshot.time, palette,
                intensity, reduced: reduced, before: before, look: look, cover: cover, scrimsOnly: scrimsOnly))
            renderer.scale = scale
            return renderer.cgImage!
        }

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
            if differences == 0 || differences > 5_500 {
                print("Expected local effects only in \(bounds), got \(differences) changed pixels")
                pixelChecks = false
            }
        }
        if pixelChecks {
            print("Both real rows: running dots present; build, reduced running, idle, queue, error, upload, wait, stale success pixel-identical.")
        }

        let shots: [Shot] = [
            .init("01 · Départ", transfer(0), time: 0.30),
            .init("02 · 20 %", transfer(20), time: 1.23),
            .init("03 · 60 %", transfer(60), time: 2.76),
            .init("04 · Total inconnu", transfer(0, total: 0), time: 3.72),
            .init("05 · Vérification", verifying(), previous: .running(.app, 0.96), time: 0.14),
            .init("06 · Rassemblement", completed(), previous: .verifying(.app, 1), time: 0.31),
            .init("07 · Signe Oort", completed(), previous: .verifying(.app, 1), time: 0.57),
            .init("08 · Éclat", completed(), previous: .verifying(.app, 1), time: 0.75),
            .init("09 · Dissolution", completed(), previous: .verifying(.app, 1), time: 1.02),
            .init("10 · Repos", completed(), previous: .verifying(.app, 1), time: 1.21),
        ]
        unchanged(frame(shots[9], checkPalette, .fine, 1), frame(shots[9], checkPalette, .fine, 1, before: true),
                  "cue-ended")
        let title = CGRect(x: 31, y: 213, width: 131, height: 14)
        let fallback = frame(shots[1], checkPalette, .fine, 1)
        let fallbackPlain = frame(shots[1], checkPalette, .fine, 1, before: true)
        unchanged(fallback.cropping(to: title)!, fallbackPlain.cropping(to: title)!, "title-mask")
        try save(fallback, "collection-titre")
        try save(fallbackPlain, "collection-titre-sans-points")

        let spotlight = CGRect(x: 212, y: 64, width: 160, height: 160)
        func square(_ image: CGImage, _ scale: CGFloat) -> CGImage {
            image.cropping(to: CGRect(x: spotlight.minX * scale, y: spotlight.minY * scale,
                                      width: spotlight.width * scale, height: spotlight.height * scale))!
        }
        var contrasts = [String]()
        for (id, label) in wanted {
            let palette = palette(id, in: palettes)
            for intensity in id == "catppuccin-latte" ? [.fine] : DownloadCloudMotion.Intensity.allCases {
                for scale in id == "catppuccin-latte" ? [CGFloat(1)] : [1, 3] {
                    try strip(shots, title: "\(label) · \(intensity == .fine ? "Fine" : "Plus présente") · \(Int(scale))×",
                                      scale: scale, file: "\(id)-\(intensity.rawValue)-\(Int(scale))x") { shot, cover in
                        square(frame(shot, palette, intensity, scale, cover: cover), scale)
                    }
                    let sample = shots[2]
                    let layout = DownloadCloudMotion.frame(.drift(0.6), seed: seed, at: sample.time,
                                                          intensity: intensity, size: spotlight.size)
                    for cover in Cover.art.dropLast() {
                        let all = square(frame(sample, palette, intensity, scale, cover: cover), scale)
                        let scrim = square(frame(sample, palette, intensity, scale, cover: cover, scrimsOnly: true), scale)
                        let ratios = contrast(all, over: scrim, scale: scale, dots: layout.dots)
                        let minimum = ratios.min() ?? 0
                        let line = "\(id) \(intensity.rawValue) \(Int(scale))x \(cover.rawValue): "
                            + "\(ratios.count) band cores, minimum \(String(format: "%.2f", minimum)):1"
                        contrasts.append(line)
                        if minimum < 3 { pixelChecks = false; print(line) }
                    }
                }
            }
        }
        try contrasts.joined(separator: "\n").write(to: folder.appendingPathComponent("contraste.txt"),
                                                    atomically: true, encoding: .utf8)
        for intensity in DownloadCloudMotion.Intensity.allCases {
            try save(square(frame(shots[7], checkPalette, intensity, 3, cover: .busy), 3), "signe-oort-\(intensity)-3x")
            try strip(shots, title: "Collection · Selene · \(intensity == .fine ? "Fine" : "Plus présente")",
                      scale: 1, file: "collection-\(intensity.rawValue)-1x", tileWidth: 172) { shot, cover in
                frame(shot, checkPalette, intensity, 1, cover: cover)
                    .cropping(to: CGRect(x: 11, y: 11, width: 172, height: 278))!
            }
        }
        let reducedShots = Array(shots.prefix(5)) + [
            Shot("6 · Fondu", completed(), previous: .verifying(.app, 1), time: 0.10),
            Shot("7 · Le même nuage s’efface", completed(), previous: .verifying(.app, 1), time: 0.30),
            Shot("8 · Repos", completed(), previous: .verifying(.app, 1), time: 0.50),
        ]
        try strip(reducedShots, title: "Selene · Réduire les animations", scale: 1, file: "mouvement-reduit") { shot, cover in
            square(frame(shot, checkPalette, .fine, 1, reduced: true, cover: cover), 1)
        }

        if /* VIDEO */ {
            for intensity in DownloadCloudMotion.Intensity.allCases {
                for i in 0..<360 {
                    let t = Double(i) / 60
                    let known: Shot
                    if t < 3.7 {
                        known = Shot("", transfer(Int(t / 3.7 * 10_000), total: 10_000), time: t + 0.4)
                    } else if t < 4.25 {
                        known = Shot("", verifying(), previous: .running(.app, 0.99), time: t - 3.7)
                    } else {
                        known = Shot("", completed(), previous: .verifying(.app, 1), time: t - 4.25)
                    }
                    let unknown = t < 3.7 ? Shot("", transfer(0, total: 0), time: t + 0.4) : known
                    let row = HStack(spacing: 8) {
                        ForEach(Cover.art, id: \.self) { cover in
                            Image(decorative: square(frame(cover == .black ? unknown : known, checkPalette,
                                                            intensity, 1, cover: cover), 1), scale: 1)
                        }
                    }.padding(8).background(Color(hex: 0x12141A))
                    try save(ImageRenderer(content: row).cgImage!, "\(intensity.rawValue)/\(String(format: "%03d", i))")
                }
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

    @ViewBuilder static func artFor(_ face: Cover) -> some View {
        switch face {
        case .black: Color.black
        case .white: Color.white
        case .yellow: Color(hex: 0xFFDD00)
        case .busy: illustration
        case .title: illustration
        }
    }

    static var illustration: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Color(hex: 0x152050), Color(hex: 0x2E7FB3), Color(hex: 0xFF7D81)],
                               startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(hex: 0xFFE69B)).frame(width: 144, height: 144).offset(x: 92, y: -237)
                ForEach(0..<22) { i in
                    Circle().fill(Color.white.opacity(Double(i % 5 + 2) * 0.11))
                        .frame(width: Double(i % 4 + 1) * 2.5)
                        .offset(x: Double((i * 127) % 461 - 228), y: Double(-(i * 53) % 230 - 230))
                }
            Path { p in
                p.move(to: .init(x: 0, y: 393)); p.addLine(to: .init(x: 126, y: 236))
                p.addLine(to: .init(x: 274, y: 347)); p.addLine(to: .init(x: 378, y: 262))
                p.addLine(to: .init(x: 512, y: 355)); p.addLine(to: .init(x: 512, y: 512))
                p.addLine(to: .init(x: 0, y: 512)); p.closeSubpath()
            }.fill(Color(hex: 0xBB4978))
            Path { p in
                p.move(to: .init(x: 0, y: 453)); p.addQuadCurve(to: .init(x: 512, y: 367), control: .init(x: 272, y: 328))
                p.addLine(to: .init(x: 512, y: 512)); p.addLine(to: .init(x: 0, y: 512)); p.closeSubpath()
            }.fill(Color(hex: 0x28305E))
                ForEach(0..<8) { i in
                    Path { p in
                        let y = Double(390 + i * 13)
                        p.move(to: .init(x: 0, y: y + 40))
                        p.addQuadCurve(to: .init(x: 512, y: y - 20), control: .init(x: 251, y: y - 37))
                    }.stroke(Color(hex: i % 2 == 0 ? 0x7DF8DE : 0x5096D0).opacity(0.66), lineWidth: 3)
                }
            }.frame(width: 512, height: 512)
             .scaleEffect(x: proxy.size.width / 512, y: proxy.size.height / 512, anchor: .topLeading)
        }
    }

    @MainActor static func strip(_ shots: [Shot], title: String, scale: CGFloat, file: String, tileWidth: CGFloat = 160,
                                 frame: (Shot, Cover) -> CGImage) throws {
        let images = shots.map { shot in Cover.art.map { frame(shot, $0) } }
        let view = VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 22, weight: .semibold))
            HStack(spacing: 8) {
                Color.clear.frame(width: 122, height: 1)
                ForEach(["Noir", "Blanc", "Jaune", "Coloré"], id: \.self) {
                    Text($0).frame(width: tileWidth, alignment: .leading)
                }
            }.font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(shots.indices, id: \.self) { row in
                HStack(spacing: 8) {
                    Text(shots[row].label).font(.system(size: 12, weight: .medium))
                        .frame(width: 122, alignment: .leading)
                    ForEach(Cover.art.indices, id: \.self) { column in
                        Image(decorative: images[row][column], scale: scale)
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

    static func pixels(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    static func contrast(_ image: CGImage, over background: CGImage, scale: CGFloat,
                         dots: [DownloadCloudMotion.Mote]) -> [Double] {
        let a = pixels(image), b = pixels(background)
        let width = image.width
        func luminance(_ pixels: Data, at index: Int) -> Double {
            func linear(_ byte: UInt8) -> Double {
                let srgb = Double(byte) / 255
                return srgb <= 0.04045 ? srgb / 12.92 : pow((srgb + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1])
                + 0.0722 * linear(pixels[index + 2])
        }
        // Test all fully lit primary cores; sub-pixel fringe and softly fading pinpoints are not cores.
        return dots.filter { $0.radius >= 1.25 && $0.opacity >= 0.85 }.map {
            let x = Int($0.center.x * scale), y = Int($0.center.y * scale)
            return (y-1...y+1).flatMap { row in
                (x-1...x+1).map { column in
                    let index = (row * width + column) * 4
                    return (luminance(a, at: index) + 0.05) / (luminance(b, at: index) + 0.05)
                }
            }.max()!
        }
    }

    static func changedPixels(_ first: CGImage, _ second: CGImage) -> Int {
        precondition(first.width == second.width && first.height == second.height)
        let a = pixels(first), b = pixels(second)
        // Ignore one quantization bit from the offscreen compositor; compare actual pixels, not PNG bytes.
        return stride(from: 0, to: a.count, by: 4).reduce(0) { count, index in
            count + ((index..<index + 4).contains { abs(Int(a[$0]) - Int(b[$0])) > 1 } ? 1 : 0)
        }
    }

    static func checkMotion() {
        typealias Motion = DownloadCloudMotion
        let size = CGSize(width: 172, height: 278)
        func motes(_ scene: Motion.Scene, _ t: Double, _ intensity: Motion.Intensity = .fine) -> [Motion.Mote] {
            Motion.frame(scene, seed: seed, at: t, intensity: intensity, size: size).dots.filter { $0.opacity > 0 }
        }
        let a = motes(.drift(0.45), 1.11)
        precondition(a == motes(.drift(0.45), 1.11))
        precondition(a != Motion.frame(.drift(0.45), seed: seed + 1, at: 1.11,
                                       intensity: .fine, size: size).dots.filter { $0.opacity > 0 })
        precondition(a.count > motes(.drift(0), 1.11).count && a.count < motes(.drift(1), 1.11).count)
        precondition(a.count < motes(.drift(0.45), 1.11, .present).count)
        precondition(a.allSatisfy { (0...24).contains(0.55 * size.height - $0.center.y) })
        precondition(a.filter { $0.radius > 1.3 && $0.opacity >= 0.85 }.count >= 8)
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
            abs($1.center.y - 0.30 * size.height) <= abs($0.center.y - 0.30 * size.height) && $1.opacity < $0.opacity
        })
        precondition(motes(.settle(0.7), 0.55).isEmpty && motes(.completion, 1.20).isEmpty)
        precondition(motes(.completion, 0.22).map(\.center) != motes(.completion, 0.65).map(\.center))
        let mark = motes(.completion, 0.77)
        precondition((80...110).contains(mark.count) && mark.filter { $0.kind == .star }.count == 1)
        let sun = mark.last!.center
        precondition(abs(sun.x - size.width / 2) < 1e-9 && abs(sun.y - size.height * 0.46) < 1e-9)
        precondition(mark.last!.radius > motes(.completion, 0.59).last!.radius)
        precondition(motes(.fade, 0.14).map(\.center) == motes(.fade, 0.36).map(\.center))
        precondition(motes(.fade, 0.14).last?.kind == .sun)
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
            precondition((count == 0 && particles.isEmpty) || (count * 35...count * 49).contains(particles.count))
            precondition(particles.allSatisfy { $0.contents != nil })
            precondition(particles.filter { $0.animation(forKey: "cloud")?.repeatCount == .infinity }.count
                         == particles.count - count, "only the local scrims are static")
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

    @MainActor static func checkWindow(_ palette: SelenePalette) throws {
        NSApplication.shared.finishLaunching()
        guard let screen = NSScreen.main else { throw CocoaError(.featureUnsupported) }
        let tileSize = CGSize(width: 170, height: 170)
        let size = CGSize(width: 738, height: 560)
        guard screen.visibleFrame.width >= size.width, screen.visibleFrame.height >= size.height else {
            throw CocoaError(.featureUnsupported)
        }
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false, screen: screen)
        window.title = "Oort NX · mesure locale · données synthétiques"
        window.center()
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.045, alpha: 1).cgColor
        window.contentView = content
        let colors = DownloadCloudColors(palette)
        let tiles = (0..<12).map { i -> DownloadCloudLayerView in
            let bounds = CGRect(origin: .zero, size: tileSize)
            let face = NSView(frame: CGRect(x: 17 + (i % 4) * 178, y: 17 + (i / 4) * 180, width: 170, height: 170))
            face.wantsLayer = true
            face.layer?.cornerRadius = 13
            face.layer?.masksToBounds = true
            face.layer?.backgroundColor = [NSColor.black, .white, .systemYellow, .systemTeal][i % 4].cgColor
            content.addSubview(face)
            let tile = DownloadCloudLayerView()
            tile.frame = bounds
            face.addSubview(tile)
            precondition(content.bounds.contains(face.frame))
            return tile
        }
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        func wait(_ seconds: Double) {
            let deadline = Date(timeIntervalSinceNow: seconds)
            while deadline.timeIntervalSinceNow > 0 {
                // Receive AppKit's own window/occlusion events, not just run-loop timers.
                if let event = NSApp.nextEvent(matching: .any, until: deadline, inMode: .default, dequeue: true) {
                    NSApp.sendEvent(event)
                }
            }
        }
        func visible() -> Bool {
            guard window.isVisible, window.windowNumber > 0, tiles.allSatisfy({ $0.window === window }) else { return false }
            if window.occlusionState.contains(.visible) { return true }
            let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber))
                as? [[String: Any]]
            return info?.first?[kCGWindowIsOnscreen as String] as? Bool == true
        }
        wait(0.5)
        guard visible() else {
            print("Probe window not onscreen: visible=\(window.isVisible), occlusion=\(window.occlusionState.rawValue), "
                  + "window=\(window.windowNumber), attached=\(tiles.filter { $0.window === window }.count).")
            throw CocoaError(.featureUnsupported)
        }

        let clock = WindowClock()
        let link = window.displayLink(target: clock, selector: #selector(WindowClock.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .current, forMode: .common)
        wait(1.3)
        link.invalidate()
        let rate = clock.rate
        print("Visible across \(Int(screen.frame.width))×\(Int(screen.frame.height)) points; display maximum "
              + "\(screen.maximumFramesPerSecond) Hz; 60 Hz window display link delivered \(String(format: "%.1f", rate)) Hz.")

        func usage() -> rusage_info_v6 {
            var usage = rusage_info_v6()
            let result = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V6, $0) }
            }
            precondition(result == 0)
            return usage
        }

        var report = ["Apple Core Animation, \(screen.maximumFramesPerSecond) Hz display, requested ≤60 fps;",
                      "window callback \(String(format: "%.1f", rate)) Hz (not measured compositor cadence).",
                      "All 12 synthetic 170 pt tile faces visible; 8 s per position after warm-up.",
                      "Process CPU is percent of one core; mW from process energy only, excludes WindowServer/GPU."]
        for intensity in DownloadCloudMotion.Intensity.allCases {
            for count in [0, 1, 6, 12, 0] {
                let settled = count == 0 && tiles[0].input != nil
                for (i, tile) in tiles.enumerated() {
                    if i < count || settled {
                        tile.input = .init(scene: settled ? .completion : .drift(0.65), start: CACurrentMediaTime(),
                                           colors: colors, seed: seed + UInt64(i), intensity: intensity)
                    } else {
                        tile.input = nil
                    }
                }
                wait(settled ? 1.7 : 0.55)
                if count == 0 {
                    precondition(tiles.allSatisfy { $0.root.sublayers?.first?.sublayers?.isEmpty != false })
                } else {
                    precondition(tiles.filter { $0.root.sublayers?.first?.sublayers?.first?.presentation() != nil }.count == count)
                }
                let initial = usage()
                let start = CACurrentMediaTime()
                wait(8)
                guard visible() else { throw CocoaError(.featureUnsupported) }
                let end = usage()
                let elapsed = CACurrentMediaTime() - start
                let cpu = Double(end.ri_user_time - initial.ri_user_time + end.ri_system_time - initial.ri_system_time)
                    / 1e9 / elapsed * 100
                let nj = end.ri_energy_nj - initial.ri_energy_nj
                let power = Double(nj) / 1e6 / elapsed
                let line = String(format: "%@, %2d active %@: CPU %.3f%%, process %.3f mW (%llu nJ)",
                                  intensity.rawValue, count, settled ? "(cue finished)" : "", cpu, power, nj)
                print(line)
                report.append(line)
                if settled { for tile in tiles { tile.input = nil } }
            }
        }
        try report.joined(separator: "\n").write(to: folder.appendingPathComponent("fenetre.txt"),
                                                 atomically: true, encoding: .utf8)
    }

    final class WindowClock: NSObject {
        var first: Double?
        var last: Double = 0
        var frames = 0
        @objc func tick(_ link: CADisplayLink) {
            if first == nil { first = link.timestamp }
            last = link.timestamp
            frames += 1
        }
        var rate: Double { first.map { last > $0 ? Double(frames - 1) / (last - $0) : 0 } ?? 0 }
    }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--video", action="store_true")
    modes.add_argument("--onscreen", action="store_true")
    args = parser.parse_args()
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg") if args.video else None
    if args.video and not ffmpeg:
        parser.error("--video needs ffmpeg")
    with tempfile.TemporaryDirectory(prefix="download-proof-") as out:
        stage = Path(out)
        for asset in ["Selene/palettes.json", "Selene/Fonts/MaterialIcons-Regular.ttf"]:
            shutil.copyfile(ROOT / "Resources" / asset, stage / Path(asset).name)
        if ffmpeg:
            for intensity in ("fine", "present"):
                (stage / intensity).mkdir()
        try:
            run_host(HOST.replace("/* OUTPUT */", json.dumps(str(stage)))
                     .replace("/* ONSCREEN */", str(args.onscreen).lower())
                     .replace("/* VIDEO */", str(args.video).lower()))
        finally:
            for file in stage.iterdir():
                if file.suffix in (".png", ".txt"):
                    shutil.copyfile(file, destination / file.name)
            for intensity in ("fine", "present") if ffmpeg else ():
                if (stage / intensity / "359.png").is_file():
                    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "60",
                                    "-i", str(stage / intensity / "%03d.png"), "-an", "-c:v", "libx264", "-threads", "4",
                                    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                                    str(destination / f"transfert-{intensity}.mp4")], check=True)


if __name__ == "__main__":
    main()
