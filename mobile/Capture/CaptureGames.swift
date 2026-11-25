import UIKit

/// Invented games with drawn covers: no real game, cover or name.
enum CaptureGames {
    static let all: [(id: String, name: String, hue: CGFloat, draw: (CGContext, CGSize, CGFloat) -> Void)] = [
        ("0100000000AA1000", "Le phare de Brume", 0.58, lighthouse), ("0100000000AA2000", "Marée haute", 0.50, tide),
        ("0100000000AA3000", "Collines rouges", 0.02, hills), ("0100000000AA4000", "Verre", 0.76, glass),
        ("0100000000AA5000", "Aimant", 0.12, magnet), ("0100000000AA6000", "Écho", 0.36, echo),
    ]

    /// The games as files: their frameworks, and the data of all but one. `marker` is the symbol their code is checked by.
    static func make(in root: URL, frameworks folder: String = "Frameworks", marker: String = "m") throws {
        let fm = FileManager.default, frameworks = root.appendingPathComponent(folder), games = root.appendingPathComponent("Documents/games")
        for (index, game) in all.enumerated() {
            let fw = frameworks.appendingPathComponent("DmGame\(game.id).framework")
            try fm.createDirectory(at: fw.appendingPathComponent("dm"), withIntermediateDirectories: true)
            let manifest: [String: Any] = ["schema": 1, "title_id": game.id, "name": game.name, "display_version": "1.\(index).0", "package_version": "65536",
                "modules": ["main"], "nro_count": 0, "chain": index == 3 ? "b-111111" : "b-000000", "loader": "FR", "framework": "DmGame\(game.id).framework",
                "framework_executable": "DmGame", "image_marker": marker, "profile": "profile.tsv", "shader_map": "dm/shader_map.tsv", "launcher": "dm/launcher.json",
                "romfs_marker": "marker", "romfs_identity": "DMROMFSID1 capture", "min_os": "26.0"]
            try JSONSerialization.data(withJSONObject: manifest).write(to: fw.appendingPathComponent("game.manifest.json"))
            try JSONSerialization.data(withJSONObject: settings(game.id)).write(to: fw.appendingPathComponent("dm/launcher.json"))
            try Data("x".utf8).write(to: fw.appendingPathComponent("DmGame"))
            try picture(game.draw, CGSize(width: 1280, height: 720), game.hue).write(to: fw.appendingPathComponent("banner.png"))
            try picture(game.draw, CGSize(width: 512, height: 512), game.hue).write(to: fw.appendingPathComponent("icon.png"))
            try fm.createDirectory(at: fw.appendingPathComponent("msl/b-000000"), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: fw.appendingPathComponent("msl/b-000000/a.metallib"))
            if index != 4 {
                let data = games.appendingPathComponent(game.id + "/romfs")
                try fm.createDirectory(at: data, withIntermediateDirectories: true)
                try Data().write(to: data.appendingPathComponent("marker"))
            }
        }
    }

    static func settings(_ id: String) -> [String: Any] {
        func row(_ env: String, _ kind: String, _ section: String, _ label: String, _ note: String, _ def: String, _ more: [String: Any]) -> [String: Any] {
            ["env": env, "kind": kind, "section": section, "label": label, "note": note, "default": def].merging(more) { $1 }
        }
        return ["schema": 1, "game": id, "settings": [
            row("DM_OPMODE", "choice", "Game", "Console mode", "", "0", ["options": [["1", "Docked"], ["0", "Handheld"]]]),
            row("DM_SHOW_FPS", "toggle", "Game", "Frame-rate counter", "", "0", ["on": "1", "off": "0"]),
            row("DM_METAL_HUD", "toggle", "Game", "Performance overlay", "", "0", ["on": "1", "off": "0"]),
            row("DM_PRESENT_UPSCALE", "choice", "Performance", "Upscaling", "", "off", ["options": [["off", "Off"], ["metalfx", "MetalFX"]]]),
            row("DM_RENDER_SCALE", "range", "Performance", "Render scale", "", "1.0", ["min": 0.5, "max": 1.0, "step": 0.05]),
        ]]
    }

    static func picture(_ draw: (CGContext, CGSize, CGFloat) -> Void, _ size: CGSize, _ hue: CGFloat) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            let g = context.cgContext
            let colors = [color(hue, 0.65, 0.16), color(hue + 0.05, 0.6, 0.5), color(hue + 0.12, 0.45, 0.9)].map(\.cgColor)
            g.drawLinearGradient(CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 0.62, 1])!, start: .zero, end: CGPoint(x: size.width * 0.2, y: size.height), options: .drawsAfterEndLocation)
            draw(g, size, hue)
        }
    }
    static func color(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor { UIColor(hue: h.truncatingRemainder(dividingBy: 1), saturation: s, brightness: b, alpha: a) }
    static func wave(_ g: CGContext, _ s: CGSize, _ y: CGFloat, _ amp: CGFloat, _ period: CGFloat, _ c: UIColor) {
        g.setFillColor(c.cgColor)
        g.move(to: CGPoint(x: 0, y: s.height))
        for x in stride(from: 0, through: s.width, by: 4) { g.addLine(to: CGPoint(x: x, y: s.height * y + sin(x / s.width * .pi * period) * s.height * amp)) }
        g.addLine(to: CGPoint(x: s.width, y: s.height))
        g.fillPath()
    }
    static func lighthouse(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        let x = s.width * 0.68, u = s.height
        g.setFillColor(UIColor(white: 1, alpha: 0.16).cgColor)
        for y in [0.1, 0.42] { g.move(to: CGPoint(x: x, y: u * 0.27)); g.addLine(to: CGPoint(x: 0, y: u * y)); g.addLine(to: CGPoint(x: 0, y: u * (y + 0.14))); g.fillPath() }
        wave(g, s, 0.78, 0.04, 3, color(h + 0.02, 0.7, 0.2))
        g.setFillColor(color(h, 0.1, 0.95).cgColor)
        g.move(to: CGPoint(x: x - u * 0.06, y: u * 0.3)); g.addLine(to: CGPoint(x: x + u * 0.06, y: u * 0.3)); g.addLine(to: CGPoint(x: x + u * 0.1, y: u * 0.85)); g.addLine(to: CGPoint(x: x - u * 0.1, y: u * 0.85)); g.fillPath()
        g.setFillColor(color(0.02, 0.75, 0.8).cgColor)
        for y in [0.4, 0.6] { g.fill(CGRect(x: x - u * 0.085, y: u * y, width: u * 0.17, height: u * 0.09)) }
        g.setFillColor(color(0.13, 0.5, 1).cgColor); g.fillEllipse(in: CGRect(x: x - u * 0.05, y: u * 0.2, width: u * 0.1, height: u * 0.1))
        wave(g, s, 0.88, 0.03, 4, color(h, 0.8, 0.1))
    }
    static func tide(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        g.setFillColor(color(0.1, 0.35, 1).cgColor); g.fillEllipse(in: CGRect(x: s.width * 0.6, y: s.height * 0.15, width: s.height * 0.4, height: s.height * 0.4))
        for i in 0..<6 { wave(g, s, 0.48 + CGFloat(i) * 0.09, 0.035, CGFloat(3 + i), color(h + CGFloat(i) * 0.015, 0.7, 0.75 - CGFloat(i) * 0.11, 0.9)) }
    }
    static func hills(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        g.setFillColor(color(0.12, 0.3, 1).cgColor); g.fillEllipse(in: CGRect(x: s.width * 0.62, y: s.height * 0.2, width: s.height * 0.24, height: s.height * 0.24))
        for i in 0..<5 { wave(g, s, 0.45 + CGFloat(i) * 0.11, 0.09 - CGFloat(i) * 0.01, 1.5 + CGFloat(i) * 0.7, color(h + CGFloat(i) * 0.01, 0.75, 0.7 - CGFloat(i) * 0.13)) }
    }
    static func glass(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        for i in 0..<9 {
            let x = s.width * (0.25 + CGFloat(i) * 0.08), t = CGFloat(i)
            g.setFillColor(color(h + t * 0.03, 0.5, 0.95, 0.4).cgColor)
            g.move(to: CGPoint(x: x, y: s.height * (0.1 + t.truncatingRemainder(dividingBy: 3) * 0.1))); g.addLine(to: CGPoint(x: x + s.height * 0.2, y: s.height * 0.5))
            g.addLine(to: CGPoint(x: x, y: s.height * 0.95)); g.addLine(to: CGPoint(x: x - s.height * 0.18, y: s.height * 0.55)); g.fillPath()
        }
    }
    static func magnet(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        g.setLineWidth(s.height * 0.012)
        for i in 1..<9 { g.setStrokeColor(color(h + CGFloat(i) * 0.02, 0.5, 1, 0.7).cgColor); let r = s.height * 0.08 * CGFloat(i); g.strokeEllipse(in: CGRect(x: s.width * 0.62 - r, y: s.height * 0.5 - r * 0.6, width: r * 2, height: r * 1.2)) }
        g.setFillColor(color(h, 0.8, 1).cgColor); g.fillEllipse(in: CGRect(x: s.width * 0.62 - s.height * 0.07, y: s.height * 0.43, width: s.height * 0.14, height: s.height * 0.14))
    }
    static func echo(_ g: CGContext, _ s: CGSize, _ h: CGFloat) {
        for i in 0..<14 { g.setFillColor(color(h + CGFloat(i) * 0.01, 0.6, 0.95, 0.85).cgColor); let v = abs(sin(CGFloat(i) * 0.9)) * s.height * 0.6 + s.height * 0.06; g.fill(CGRect(x: s.width * (0.2 + CGFloat(i) * 0.05), y: (s.height - v) / 2, width: s.width * 0.022, height: v)) }
    }
}
