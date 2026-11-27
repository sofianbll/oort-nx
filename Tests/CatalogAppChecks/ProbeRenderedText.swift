import AppKit
import PDFKit
import SwiftUI

// Frames kept in memory by name: the probe writes no capture beyond its PNG and PDF.
nonisolated(unsafe) private var probeFrames: [String: (shown: CGImage, hidden: CGImage)] = [:]
nonisolated(unsafe) private var probeSelfTest: [String]? = nil

/// Saves the PDF of a render beside its PNG, and keeps the frame with every text redacted for `assertVisible`.
@MainActor
func saveProbeText<V: View, H: View>(_ renderer: ImageRenderer<V>, hidden: ImageRenderer<H>, beside image: URL) throws {
    try probePDF(renderer).write(to: image.deletingPathExtension().appendingPathExtension("pdf"))
    guard let shown = renderer.cgImage, let redacted = hidden.cgImage else { throw CocoaError(.fileWriteUnknown) }
    probeFrames[image.deletingPathExtension().lastPathComponent] = (shown, redacted)
    if probeSelfTest == nil { probeSelfTest = probeVisibilitySelfTest() }
}

@MainActor
private func probePDF<V: View>(_ renderer: ImageRenderer<V>) throws -> Data {
    let data = NSMutableData()
    renderer.render { size, draw in
        var bounds = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { return }
        context.beginPDFPage(nil)
        draw(context)
        context.endPDFPage()
        context.closePDF()
    }
    guard data.length > 0 else { throw CocoaError(.fileWriteUnknown) }
    return data as Data
}

/// Every string drawn into the render, clipped, covered or not. Says which words exist, not that they are seen.
func readProbeText(_ output: URL, name: String) throws -> String {
    let url = output.appendingPathComponent(name + ".pdf")
    guard let page = PDFDocument(url: url)?.page(at: 0),
          let text = page.selection(for: page.bounds(for: .mediaBox))?.string, !text.isEmpty else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
    }
    return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// Proves that each text is seen, from pixels only (rule R13). For one occurrence of the text at least:
/// 1. its line boxes, read from the PDF, lie inside the frame;
/// 2. the render with every text redacted differs from the shown render across the box: nothing covers it;
/// 3. its most contrasted pixel stands out from the surrounding background by `probeMinimumContrast`.
/// Case, accents, apostrophes and spaces are compared loosely, as the probes write their expectations.
/// Returns the problems; an empty list means every text is visible.
func assertVisible(_ output: URL, name: String, _ texts: [String]) -> [String] {
    guard let selfTest = probeSelfTest else { return ["\(name): no frame was saved for assertVisible"] }
    guard selfTest.isEmpty else { return selfTest.map { "assertVisible self-test: \($0)" } }
    guard let frames = probeFrames[name] else { return ["\(name): no frame was saved for assertVisible"] }
    guard let page = PDFDocument(url: output.appendingPathComponent(name + ".pdf"))?.page(at: 0) else {
        return ["\(name): its PDF cannot be read"]
    }
    let shown = ProbeBitmap(frames.shown), hidden = ProbeBitmap(frames.hidden)
    return texts.compactMap { text in
        let verdicts: [String?] = probeLines(of: text, on: page).map { lines in
            guard !lines.isEmpty else { return "no line box" }
            return lines.lazy.compactMap { probeVisibility(of: $0, page: page, shown: shown, hidden: hidden) }.first
        }
        if verdicts.isEmpty { return "\(name): \"\(text)\" is not drawn" }
        if verdicts.contains(where: { $0 == nil }) { return nil }
        return "\(name): \"\(text)\" is drawn but not visible (\(verdicts.compactMap { $0 }.joined(separator: "; ")))"
    }
}

private func probeFold(_ character: String) -> String {
    let folded = character.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
        .replacingOccurrences(of: "\u{2019}", with: "'")
    return folded.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) } && !folded.isEmpty
        ? " " : folded
}

/// The line boxes of every occurrence of `text` on the page, in PDF points.
private func probeLines(of text: String, on page: PDFPage) -> [[CGRect]] {
    let source = (page.string ?? "") as NSString
    var folded: [unichar] = [], origin: [Int] = []
    for index in 0..<source.length {
        for unit in probeFold(source.substring(with: NSRange(location: index, length: 1))).utf16
        where !(unit == 32 && folded.last == 32) {
            folded.append(unit)
            origin.append(index)
        }
    }
    let needle = Array(text.map { probeFold(String($0)) }.joined()
        .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ").utf16)
    guard !needle.isEmpty, needle.count <= folded.count else { return [] }
    var found: [[CGRect]] = []
    for start in 0...(folded.count - needle.count) where Array(folded[start..<start + needle.count]) == needle {
        let first = origin[start], last = origin[start + needle.count - 1]
        guard let selection = page.selection(for: NSRange(location: first, length: last - first + 1)) else { continue }
        found.append(selection.selectionsByLine().map { $0.bounds(for: page) }.filter { !$0.isEmpty })
    }
    return found
}

/// nil when this line box is visible; otherwise the reason.
private func probeVisibility(of line: CGRect, page: PDFPage, shown: ProbeBitmap, hidden: ProbeBitmap) -> String? {
    let media = page.bounds(for: .mediaBox)
    let scaleX = Double(shown.width) / media.width, scaleY = Double(shown.height) / media.height
    let box = CGRect(x: (line.minX - media.minX) * scaleX, y: (media.maxY - line.maxY) * scaleY,
                     width: line.width * scaleX, height: line.height * scaleY)
    let frame = CGRect(x: 0, y: 0, width: shown.width, height: shown.height).insetBy(dx: -1, dy: -1)
    guard frame.contains(box) else { return "outside the frame" }
    let xs = Int(box.minX.rounded(.up))..<max(Int(box.minX.rounded(.up)) + 1, Int(box.maxX.rounded(.down)))
    let ys = Int(box.minY.rounded(.up))..<max(Int(box.minY.rounded(.up)) + 1, Int(box.maxY.rounded(.down)))
    var changedColumns = 0, ink: [Double] = []
    for x in xs {
        var changed = false
        for y in ys where shown.differs(from: hidden, x, y) {
            changed = true
            ink.append(shown.luminance(x, y))
        }
        if changed { changedColumns += 1 }
    }
    let covered = Double(changedColumns) / Double(xs.count)
    guard covered >= 0.8 else { return String(format: "%.0f%% of its width in front", covered * 100) }
    var ring: [Double] = []
    for x in (xs.lowerBound - 3)..<(xs.upperBound + 3) {
        for y in [ys.lowerBound - 3, ys.lowerBound - 2, ys.upperBound + 1, ys.upperBound + 2] { ring.append(shown.luminance(x, y)) }
    }
    for y in ys { for x in [xs.lowerBound - 3, xs.lowerBound - 2, xs.upperBound + 1, xs.upperBound + 2] { ring.append(shown.luminance(x, y)) } }
    let background = ring.compactMap { $0.isNaN ? nil : $0 }.sorted()
    guard !background.isEmpty else { return "no background around it" }
    let base = background[background.count / 2]
    let contrast = ink.map { (max($0, base) + 0.05) / (min($0, base) + 0.05) }.max() ?? 1
    return contrast >= probeMinimumContrast ? nil : String(format: "contrast %.2f:1 < %.2f:1", contrast, probeMinimumContrast)
}

private struct ProbeBitmap {
    let width: Int, height: Int
    private let rgba: [UInt8]

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                    bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        rgba = data
    }

    /// Row 0 is the top of the image.
    func luminance(_ x: Int, _ y: Int) -> Double {
        guard x >= 0, y >= 0, x < width, y < height else { return .nan }
        let i = (y * width + x) * 4
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgba[i]) + 0.7152 * linear(rgba[i + 1]) + 0.0722 * linear(rgba[i + 2])
    }

    func differs(from other: ProbeBitmap, _ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height, other.width == width, other.height == height else { return false }
        let i = (y * width + x) * 4
        return (0..<3).contains { abs(Int(rgba[i + $0]) - Int(other.rgba[i + $0])) > 24 }
    }
}

/// The red examples of assertVisible, run once per probe: an outside text (frame), a covered and a clipped one (front)
/// and a faint one (contrast) must each be refused, and a plain one accepted. Returns what went wrong; empty when the
/// helper still tells them apart.
@MainActor
private func probeVisibilitySelfTest() -> [String] {
    let background = Color(red: 0.09, green: 0.13, blue: 0.20)
    func scene<V: View>(_ content: V) -> AnyView {
        AnyView(content.font(.system(size: 22)).foregroundStyle(.white)
            .frame(width: 320, height: 120, alignment: .topLeading).padding(20)
            .frame(width: 360, height: 160).background(background))
    }
    let cases: [(String, AnyView, Bool)] = [
        ("plain", scene(Text("Plain words")), true),
        ("covered", scene(ZStack(alignment: .topLeading) { Text("Covered words"); background.frame(width: 300, height: 60) }), false),
        ("clipped", scene(Text("Clipped words here").fixedSize().frame(width: 30, alignment: .leading).clipped()), false),
        ("outside", scene(Text("Outside words").offset(x: 900)), false),
        ("faint", scene(Text("Faint words").foregroundStyle(Color(white: 0.35))), false),
    ]
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("oort-visible-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    var problems: [String] = []
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, view, visible) in cases {
            let image = folder.appendingPathComponent("self-\(name).png")
            try probePDF(ImageRenderer(content: view)).write(to: image.deletingPathExtension().appendingPathExtension("pdf"))
            guard let shown = ImageRenderer(content: view).cgImage,
                  let hidden = ImageRenderer(content: view.redacted(reason: .placeholder)).cgImage else {
                problems.append("\(name): no image"); continue
            }
            probeFrames["self-\(name)"] = (shown, hidden)
            probeSelfTest = []
            let text = name.prefix(1).uppercased() + name.dropFirst() + " words"
            let refused = !assertVisible(folder, name: "self-\(name)", [text]).isEmpty
            probeFrames["self-\(name)"] = nil
            if refused == visible { problems.append("\(name) text was \(visible ? "refused" : "accepted")") }
        }
    } catch {
        problems.append("\(error)")
    }
    return problems
}
