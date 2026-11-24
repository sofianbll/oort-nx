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
    static let front = /* FRONT */
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
                  _ palette: SelenePalette,
                  reduced: Bool = false, before: Bool = false, look: PortingTileLook = .normal,
                  cover: Cover = .title, scrimsOnly: Bool = false, artOnly: Bool = false,
                  sample: DownloadCloudMotion.Sample? = nil) -> some View {
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
             .environment(\.downloadCloudCapture, .init(seed: seed, time: seconds,
                                                      previous: previous, before: before, scrimsOnly: scrimsOnly,
                                                       artOnly: artOnly, sample: sample))
        }

        // Render each state immediately: the two real rows read the same observable model.
         func frame(_ snapshot: Shot, _ palette: SelenePalette,
                   _ scale: CGFloat, reduced: Bool = false, before: Bool = false,
                   look: PortingTileLook = .normal, cover: Cover = .title, scrimsOnly: Bool = false,
                   artOnly: Bool = false) -> CGImage {
            let renderer = ImageRenderer(content: pair(snapshot.state, snapshot.previous, snapshot.time, palette,
                 reduced: reduced, before: before, look: look, cover: cover, scrimsOnly: scrimsOnly, artOnly: artOnly,
                 sample: snapshot.sample))
            renderer.scale = scale
            return renderer.cgImage!
        }

        let spotlight = CGRect(x: 212, y: 64, width: 160, height: 160)
        func square(_ image: CGImage, _ scale: CGFloat) -> CGImage {
            image.cropping(to: CGRect(x: spotlight.minX * scale, y: spotlight.minY * scale,
                                      width: spotlight.width * scale, height: spotlight.height * scale))!
        }
        let levels = [0, 20, 60, 95].map { Shot("\($0) %", transfer($0), time: 2.76) }
        if front {
            for (id, label) in wanted.prefix(2) {
                let palette = palette(id, in: palettes)
                for scale: CGFloat in [1, 3] {
                     try strip(levels, title: "\(label) · Vague calme · \(Int(scale))×",
                              scale: scale, file: "\(id)-fine-\(Int(scale))x") { shot, cover in
                         square(frame(shot, palette, scale, cover: cover), scale)
                    }
                }
            }
            try strip(levels, title: "Selene · Réduire les animations", scale: 1, file: "mouvement-reduit") { shot, cover in
                 square(frame(shot, checkPalette, 1, reduced: true, cover: cover), 1)
            }
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
             unchanged(frame(shot, checkPalette, 1), frame(shot, checkPalette, 1, before: true), shot.label)
        }
        let moving = Shot("40%", transfer(40), time: 1.56)
         unchanged(frame(moving, checkPalette, 1, reduced: true),
                   frame(Shot("40%", transfer(40), time: 3), checkPalette, 1, reduced: true),
                  "reduced-running-still")
         precondition(changedPixels(frame(moving, checkPalette, 1, reduced: true),
                                    frame(moving, checkPalette, 1, reduced: true, before: true)) > 0)
        // The shader percentage has its own wall-clock sheen; use the static preparation look for a pixel check.
        let build = PortingTileLook.preparing(step: 1, count: 2, title: "Fixture build", detail: "")
         if front {
             try save(frame(moving, checkPalette, 1, look: build), "porting-preparation")
             try save(frame(moving, checkPalette, 1, reduced: true, look: .filling(0.4)), "porting-compilation")
         }
         unchanged(frame(moving, checkPalette, 1, look: build),
                   frame(moving, checkPalette, 1, before: true, look: build), "build-preparation")
         unchanged(frame(moving, checkPalette, 1, reduced: true, look: .filling(0.4)),
                   frame(moving, checkPalette, 1, reduced: true, before: true, look: .filling(0.4)),
                  "build-compilation")
         let withDots = frame(moving, checkPalette, 1)
         let plain = frame(moving, checkPalette, 1, scrimsOnly: true)
        // A running download really changes both call sites, only near the front.
        for bounds in [CGRect(x: 11, y: 11, width: 172, height: 278), spotlight] {
            let differences = changedPixels(withDots.cropping(to: bounds)!, plain.cropping(to: bounds)!)
            if differences == 0 {
                print("Expected a download effect in \(bounds)")
                pixelChecks = false
            }
            let frontY = bounds.minY + 0.6 * bounds.height
            let above = bounds.intersection(CGRect(x: bounds.minX, y: 0, width: bounds.width,
                height: floor(frontY - 36 * bounds.width / 170)))
            let bottom = ceil(frontY + 12 * bounds.width / 170)
            let below = bounds.intersection(CGRect(x: bounds.minX, y: bottom, width: bounds.width,
                height: bounds.maxY - bottom))
            for (index, area) in [above, below].enumerated() {
                unchanged(withDots.cropping(to: area)!, plain.cropping(to: area)!, "outside-front-\(Int(bounds.width))-\(index)")
            }
        }
        if pixelChecks {
            print("Both real rows: local moving points, fixed reduced-motion front and no stray cloud cues.")
        }

        let yellow = levels.map { shot in
             square(frame(shot, checkPalette, 1, reduced: true, cover: .yellow, scrimsOnly: true), 1)
        }
        func blueColumn(_ image: CGImage) -> [Int] {
            let data = pixels(image)
            return (0..<image.height).map { Int(data[($0 * image.width + image.width / 2) * 4 + 2]) }
        }
        precondition(blueColumn(yellow[0]).dropFirst(2).dropLast(18).allSatisfy { $0 > 195 })
        for (image, edge) in zip(yellow.dropFirst(), [128, 64, 8]) {
            let blue = blueColumn(image)
            precondition(blue[max(2, edge - 5)] > 55 && blue[edge + 5] < 10,
                         "Expected grey above and colour below the measured level \(edge).")
        }
         let gray = square(frame(Shot("", transfer(0, total: 0), time: 2), checkPalette, 1,
                                 cover: .yellow, artOnly: true), 1)
        let grayData = pixels(gray)
        for y in 3..<(gray.height - 3) {
            let i = (y * gray.width + gray.width / 2) * 4
            precondition(Int(grayData[i...i+2].max()!) - Int(grayData[i...i+2].min()!) <= 3)
        }
         let quiet = DownloadCloudMotion.Track(.drift(0.6), at: 0)
         let quietA = Shot("", transfer(60), sample: quiet.sample(at: 4))
         let quietB = Shot("", transfer(60), sample: quiet.sample(at: 6))
         unchanged(frame(quietA, checkPalette, 1), frame(quietB, checkPalette, 1), "quiet-running")

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
         unchanged(frame(shots[9], checkPalette, 1), frame(shots[9], checkPalette, 1, artOnly: true), "cue-ended")
        let title = CGRect(x: 31, y: 213, width: 131, height: 14)
         let fallback = frame(shots[1], checkPalette, 1)
         let fallbackPlain = frame(shots[1], checkPalette, 1, artOnly: true)
        unchanged(fallback.cropping(to: title)!, fallbackPlain.cropping(to: title)!, "title-mask")
        try save(fallback, "collection-titre")
        try save(fallbackPlain, "collection-titre-sans-points")

        var contrasts = [String]()
        for (id, label) in front ? Array(wanted.prefix(2)) : wanted {
            let palette = palette(id, in: palettes)
            for scale in id == "catppuccin-latte" ? [CGFloat(1)] : [1, 3] {
                if !front {
                    try strip(shots, title: "\(label) · Vague calme · \(Int(scale))×",
                              scale: scale, file: "\(id)-fine-\(Int(scale))x") { shot, cover in
                        square(frame(shot, palette, scale, cover: cover), scale)
                    }
                }
                for sample in front ? levels : [shots[2]] {
                    let level = CloudTransferPresentation.fraction(sample.state.progress)
                    let layout = DownloadCloudMotion.frame(.drift(level), seed: seed, at: sample.time, size: spotlight.size)
                    for cover in Cover.art {
                        let all = square(frame(sample, palette, scale, cover: cover), scale)
                        let scrim = square(frame(sample, palette, scale, cover: cover, scrimsOnly: true), scale)
                        let ratios = contrast(all, over: scrim, scale: scale, dots: layout.dots)
                        let minimum = ratios.min() ?? 0
                        let line = "\(id) \(Int(scale))x \(cover.rawValue) \(sample.label): "
                            + "\(ratios.count) band cores, minimum \(String(format: "%.2f", minimum)):1"
                        contrasts.append(line)
                        if minimum < 3 { pixelChecks = false; print(line) }
                    }
                }
            }
        }
        try contrasts.joined(separator: "\n").write(to: folder.appendingPathComponent("contraste.txt"),
                                                    atomically: true, encoding: .utf8)
        try save(square(frame(shots[7], checkPalette, 3, cover: .busy), 3), "signe-oort-fine-3x")
        try strip(shots, title: "Collection · Selene · Vague calme",
                  scale: 1, file: "collection-fine-1x", tileWidth: 172) { shot, cover in
            frame(shot, checkPalette, 1, cover: cover)
                .cropping(to: CGRect(x: 11, y: 11, width: 172, height: 278))!
        }
        let reducedShots = Array(shots.prefix(5)) + [
            Shot("6 · Fondu", completed(), previous: .verifying(.app, 1), time: 0.10),
            Shot("7 · Le même nuage s’efface", completed(), previous: .verifying(.app, 1), time: 0.30),
            Shot("8 · Repos", completed(), previous: .verifying(.app, 1), time: 0.50),
        ]
        if !front {
            try strip(reducedShots, title: "Selene · Réduire les animations", scale: 1, file: "mouvement-reduit") { shot, cover in
                square(frame(shot, checkPalette, 1, reduced: true, cover: cover), 1)
            }
        }

        if /* VIDEO */ {
            typealias Motion = DownloadCloudMotion
            let reports: [(Double, Motion.Scene, CloudLibraryState, String, Int)] = [
                 (0, .drift(0), transfer(0), "Départ", 0),
                 (0.38, .drift(0.06), transfer(6), "Premiers octets", 6),
                 (0.75, .drift(0.19), transfer(19), "Rafale", 19),
                 (0.77, .drift(0.31), transfer(31), "Rafale", 31),
                 (0.92, .drift(0.43), transfer(43), "Rafale", 43),
                 (1.40, .drift(0.48), transfer(48), "Montée", 48),
                 (2.35, .settle(0.48), queued(), "Pause · plus de données", 48),
                 (5.10, .drift(0.55), transfer(55), "Reprise", 55),
                 (5.15, .drift(0.70), transfer(70), "Reprise", 70),
                 (5.65, .drift(0.78), transfer(78), "Reprise", 78),
                 (6.40, .drift(0.92), transfer(92), "Derniers octets", 92),
                 (7.15, .verify(1), verifying(), "Vérification", 100),
                 (7.90, .completion, completed(), "Terminé", 100),
            ]
            var track = Motion.Track(.drift(0), at: 0)
            var current = 0
            var csv = "temps_s,phase,reel_pct,affiche_pct,vitesse_pct_s,amplitude\n"
            var lastLevel = 0.0
            for i in 0..<720 {
                let t = Double(i) / 60
                while current + 1 < reports.count && reports[current + 1].0 <= t {
                    current += 1
                    track.receive(reports[current].1, at: reports[current].0)
                }
                let (_, scene, state, phase, real) = reports[current]
                let sample = track.sample(at: t)
                let level = sample.surface.level! * 100
                let label = phase == "Terminé" && level < 100 ? "Terminé · montée en cours" : phase
                let previous: DownloadCloudTileState = scene == .completion ? .verifying(.app, 1) : .running(.app, Double(real) / 100)
                let shot = Shot("\(label) — réel : \(real) %", state, previous: previous, time: t, sample: sample)
                csv += String(format: "%.4f,%@,%d,%.6f,%.6f,%.6f\n", t, phase, real, level, (level - lastLevel) * 60,
                              sample.surface.activity)
                lastLevel = level
                let row = VStack(alignment: .leading, spacing: 8) {
                    Text(shot.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.8).frame(width: 328, alignment: .leading)
                    HStack(spacing: 8) {
                        ForEach([Cover.busy, .yellow], id: \.self) { cover in
                            Image(decorative: square(frame(shot, checkPalette, 2, cover: cover), 2), scale: 2)
                        }
                    }
                }
                .padding(8).background(Color(hex: 0x12141A))
                let renderer = ImageRenderer(content: row)
                renderer.scale = 2
                try save(renderer.cgImage!, "frames/\(String(format: "%03d", i))")
            }
            try csv.write(to: folder.appendingPathComponent("niveaux-60hz.csv"), atomically: true, encoding: .utf8)
        }
        checkCompositor(palette: checkPalette)
        if !pixelChecks { exit(1) }
    }

    struct Shot {
        let label: String
        let state: CloudLibraryState
        let previous: DownloadCloudTileState?
        let time: Double
         let sample: DownloadCloudMotion.Sample?
         init(_ label: String, _ state: CloudLibraryState, previous: DownloadCloudTileState? = nil,
              time: Double = 0, sample: DownloadCloudMotion.Sample? = nil) {
             self.label = label; self.state = state; self.previous = previous; self.time = time
             self.sample = sample
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
        // Test the lit primary cores, outside the corners and the independently drawn cloud badge.
        return dots.filter {
            let x = $0.center.x, y = $0.center.y
            return $0.kind != .bubble && $0.opacity >= 0.85
                && (8...(CGFloat(width) / scale - 8)).contains(x)
                && (2...(CGFloat(image.height) / scale - 2)).contains(y)
                && (y >= 36 || x < CGFloat(width) / scale - 39)
        }.map {
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
        // Separate renders can round the offscreen tile shadow up to two byte levels apart.
        return stride(from: 0, to: a.count, by: 4).reduce(0) { count, index in
            count + ((index..<index + 4).contains { abs(Int(a[$0]) - Int(b[$0])) > 2 } ? 1 : 0)
        }
    }

    static func checkMotion() {
        typealias Motion = DownloadCloudMotion
        let size = CGSize(width: 172, height: 278)
         func motes(_ scene: Motion.Scene, _ t: Double) -> [Motion.Mote] {
             Motion.frame(scene, seed: seed, at: t, size: size).dots
                .filter { $0.opacity > 0 }
        }
        func points(_ surface: Motion.Surface) -> [Double] {
            (0...40).map { surface.y(at: size.width * Double($0) / 40, in: size) }
        }
        func spread(_ surface: Motion.Surface) -> Double { let ys = points(surface); return ys.max()! - ys.min()! }
         let calm = Motion.preview(.drift(0.6), at: 2.7).surface
         precondition((7...11).contains(spread(calm)))
         precondition(points(calm) != points(Motion.preview(.drift(0.6), at: 3.5).surface))
         precondition(Motion.preview(.drift(nil), at: 1).surface.level == nil)
         for end in [0.0, 1] { precondition(spread(Motion.preview(.drift(end), at: 2.7).surface) == 0) }
         precondition(spread(Motion.preview(.drift(0.95), at: 2.7).surface) < spread(calm))
         let fixed = Motion.preview(.drift(0.6), at: 1, reduced: true).surface
         precondition(spread(fixed) == 0)
         precondition(points(fixed) == points(Motion.preview(.drift(0.6), at: 2, reduced: true).surface))
        let a = motes(.drift(0.45), 1.11)
        precondition(a == motes(.drift(0.45), 1.11))
        precondition(a != Motion.frame(.drift(0.45), seed: seed + 1, at: 1.11,
                                        size: size).dots.filter { $0.opacity > 0 })
         let crest = Motion.preview(.drift(0.45), at: 1.11).surface
        precondition(a.allSatisfy { (0...23).contains(crest.y(at: $0.center.x, in: size) - $0.center.y) })
        precondition(a.filter { $0.kind != .bubble && $0.opacity >= 0.85 }.count == 16)
        let unknown = motes(.drift(nil), 0.33)
        precondition(unknown != motes(.drift(nil), 0.8))
        precondition(motes(.drift(.nan), 0.33) == unknown)
         precondition(motes(.settle(0.7), 0).isEmpty && motes(.completion, 1.20).isEmpty)
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
         precondition(project(queued()).fillScene == nil)
        precondition(project(queued()).hold(after: project(transfer(40))) == .holding(.app, 0.4))
        precondition(project(failed()).hold(after: .running(.sources, 0.4)) == nil)
        precondition(project(failed()).hold(after: project(transfer(40))) == .holding(.app, 0.4))
         precondition(project(failed()).fillScene == nil)
        precondition(project(ready()).fillScene == nil)
        precondition(project(ready()).hold(after: .running(.app, 0.97))?.fillScene == .settle(1))
         precondition(project(verifying()).fillScene == .verify(1))
         precondition(!project(completed()).completes(.running(.sources, 1)))
         precondition(project(completed()).completes(project(verifying())))
         precondition(project(completed()).completes(project(ready())))
         precondition(!project(completed()).completes(project(completed())))
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
                tile.root.frame = CGRect(x: CGFloat(i % 4) * size.width, y: CGFloat(i / 4) * size.height,
                                         width: size.width, height: size.height)
                surface.addSublayer(tile.root)
                let art = ImageRenderer(content: Color.yellow.frame(width: size.width, height: size.height))
                tile.coat.contents = art.cgImage
                 tile.apply(.init(scene: .drift(0.65), colors: colors, seed: seed + UInt64(i)),
                           size: size, now: now)
                for particle in tile.field.sublayers ?? [] { particle.delegate = counter }
            }
            renderer.layer = surface
            renderer.bounds = bounds
            CATransaction.commit()
            CATransaction.flush()
            let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
            let fields = tiles.map(\.field)
            let particles = fields.flatMap { $0.sublayers ?? [] }
            precondition(particles.count == count * 39)
            precondition(tiles.allSatisfy { $0.coat.mask?.animation(forKey: "cloud") != nil })
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
            let quiet = composite(4)
            precondition(quiet == composite(5), "\(count) tiles: stalled surface must be flat and static")
             if count > 0 {
                let a = (Int(size.width / 2) + Int(size.height * 0.2) * Int(bounds.width)) * 4
                let b = (Int(size.width / 2) + Int(size.height * 0.8) * Int(bounds.width)) * 4
                 let one = quiet[a + 1], two = quiet[b + 1]
                 precondition(max(one, two) > 180 && min(one, two) < 50, "colour mask must reveal only one side: \(one), \(two)")
                 for (index, tile) in tiles.enumerated() {
                     tile.apply(.init(scene: .drift(0.94), colors: colors, seed: seed + UInt64(index)),
                                size: size, now: now + 5)
                     let animation = tile.coat.mask?.animation(forKey: "cloud") as? CAAnimationGroup
                     let paths = (animation?.animations?.first as? CAKeyframeAnimation)?.values as? [CGPath]
                     precondition(abs((paths?.first?.boundingBoxOfPath.minY ?? -1) - 0.35 * size.height) < 0.001)
                     precondition(abs((paths?.last?.boundingBoxOfPath.minY ?? -1) - 0.06 * size.height) < 0.001)
                 }
                 precondition(composite(5) == quiet, "new bytes must not move the rendered front on arrival")
             }
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
        wait(1)
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
                      "All 12 synthetic 170 pt tile faces visible; 2.35 s per position before automatic flattening.",
                      "Process CPU is percent of one core; mW from process energy only, excludes WindowServer/GPU."]
             for count in [0, 1, 6, 12, 0] {
                let settled = count == 0 && tiles[0].input != nil
                for (i, tile) in tiles.enumerated() {
                    if i < count || settled {
                        if !settled {
                            tile.setArt(AnyView(Color.yellow), revision: .init(images: []))
                        }
                         tile.input = .init(scene: .drift(0.65), colors: colors, seed: seed + UInt64(i), bytes: Int64(count))
                    } else {
                        tile.input = nil
                    }
                }
                wait(settled ? 4.05 : 0.55)
                if settled {
                    // The model can retain a submitted key after the render server stops sampling it.
                    precondition(tiles.allSatisfy {
                        guard let mask = $0.coat.mask as? CAShapeLayer,
                              let path = mask.presentation()?.path ?? mask.path else { return false }
                        return abs(path.boundingBoxOfPath.minY - tileSize.height * 0.35) < 0.001
                    }, "The quiet coat must remain visible and flat")
                } else {
                    precondition(tiles.filter { $0.coat.mask?.animation(forKey: "cloud") != nil }.count == count)
                }
                let initial = usage()
                let start = CACurrentMediaTime()
                wait(2.35)
                guard visible() else { throw CocoaError(.featureUnsupported) }
                let end = usage()
                let elapsed = CACurrentMediaTime() - start
                let cpu = Double(end.ri_user_time - initial.ri_user_time + end.ri_system_time - initial.ri_system_time)
                    / 1e9 / elapsed * 100
                let nj = end.ri_energy_nj - initial.ri_energy_nj
                let power = Double(nj) / 1e6 / elapsed
                 let line = String(format: "calm, %2d active %@: CPU %.3f%%, process %.3f mW (%llu nJ)",
                                   count, settled ? "(quiet, coat still visible)" : "", cpu, power, nj)
                print(line)
                report.append(line)
                if settled { for tile in tiles { tile.input = nil } }
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
    parser.add_argument("destination", type=Path, nargs="?")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--video", action="store_true")
    modes.add_argument("--onscreen", action="store_true")
    parser.add_argument("--front", action="store_true", help="capture the transfer front at 0/20/60/95 percent")
    args = parser.parse_args()
    if args.destination is None:
        if args.video or args.onscreen or args.front:
            parser.error("capture options require a destination")
        print("SKIP: supply a destination for the download capture")
        return
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
            (stage / "frames").mkdir()
        try:
            run_host(HOST.replace("/* OUTPUT */", json.dumps(str(stage)))
                     .replace("/* ONSCREEN */", str(args.onscreen).lower())
                     .replace("/* FRONT */", str(args.front).lower())
                     .replace("/* VIDEO */", str(args.video).lower()))
        finally:
            for file in stage.iterdir():
                if file.suffix in (".png", ".txt", ".csv"):
                    shutil.copyfile(file, destination / file.name)
            if ffmpeg and (stage / "frames/719.png").is_file():
                video = destination / "transfert-2x.mp4"
                subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "60",
                                "-i", str(stage / "frames/%03d.png"), "-an", "-c:v", "libx264", "-threads", "4",
                                "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                                str(video)], check=True)
                for name, frames in [
                    ("bande-1-montee-pause", [0, 38, 56, 82, 113, 142, 175, 230, 299]),
                    ("bande-2-reprise-fin", [312, 353, 385, 430, 467, 498, 622, 657, 719]),
                ]:
                    selected = "+".join(f"eq(n\\,{i})" for i in frames)
                    subprocess.run([ffmpeg, "-v", "error", "-y", "-threads", "4", "-filter_threads", "4",
                                    "-i", str(video), "-vf",
                                    f"select={selected},scale=344:-2,tile=3x3:padding=8:margin=8:color=0x12141a",
                                    "-frames:v", "1", str(destination / f"{name}.png")], check=True)


if __name__ == "__main__":
    main()
