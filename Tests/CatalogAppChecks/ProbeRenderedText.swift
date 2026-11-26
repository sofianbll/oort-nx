import AppKit
import PDFKit
import SwiftUI

@MainActor
func saveProbeText<V: View>(_ renderer: ImageRenderer<V>, beside image: URL) throws {
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
    try (data as Data).write(to: image.deletingPathExtension().appendingPathExtension("pdf"))
}

func readProbeText(_ output: URL, name: String) throws -> String {
    let url = output.appendingPathComponent(name + ".pdf")
    guard let page = PDFDocument(url: url)?.page(at: 0),
          let text = page.selection(for: page.bounds(for: .mediaBox))?.string, !text.isEmpty else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
    }
    return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
