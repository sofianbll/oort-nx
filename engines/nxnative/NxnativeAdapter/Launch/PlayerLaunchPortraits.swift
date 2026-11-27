import AppKit
import Darwin
import ImageIO
import NXLibraryCore
import UniformTypeIdentifiers

/// Only generated derivatives enter this directory. Its lifetime follows the launched application.
final class PlayerLaunchPortraits: Sendable {
    let directory: URL

    init(in root: URL) throws {
        var template = root.appendingPathComponent("Arcane-players-XXXXXX").path.utf8CString
        let path = template.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress.flatMap { mkdtemp($0) }.map { String(cString: $0) }
        }
        guard let path else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        directory = URL(fileURLWithPath: path, isDirectory: true)
    }

    deinit { clean() }

    func clean() { try? FileManager.default.removeItem(at: directory) }

    func write(_ jpeg: Data, player: Int) throws -> String {
        let file = directory.appendingPathComponent("\(player).jpg")
        guard file.path.utf8.count < 1024 else { throw CocoaError(.fileWriteInvalidFileName) }
        try jpeg.write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return file.path
    }

    static func jpeg(profile: LocalProfile, symbols: [String]) -> Data? {
        let size = 256
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let canvas = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        canvas.setFillColor(red: 0.15, green: 0.29, blue: 0.44, alpha: 1)
        canvas.fill(bounds)
        if let portrait = profile.portrait {
            guard portrait.count <= LocalProfileStore.maximumPortraitBytes,
                  let source = CGImageSourceCreateWithData(portrait as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int, (1...16_384).contains(width),
                  let height = properties[kCGImagePropertyPixelHeight] as? Int, (1...16_384).contains(height),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 512
                  ] as CFDictionary), image.width > 0, image.height > 0 else { return nil }
            let scale = CGFloat(size) / CGFloat(min(image.width, image.height))
            let scaledWidth = CGFloat(image.width) * scale, scaledHeight = CGFloat(image.height) * scale
            canvas.interpolationQuality = .high
            canvas.draw(image, in: CGRect(x: (CGFloat(size) - scaledWidth) / 2, y: (CGFloat(size) - scaledHeight) / 2,
                                          width: scaledWidth, height: scaledHeight))
        } else {
            guard symbols.indices.contains(profile.avatar),
                  let symbol = NSImage(systemSymbolName: symbols[profile.avatar], accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 110, weight: .medium)),
                  let image = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return nil }
            let width = symbol.size.width, height = symbol.size.height
            let rect = CGRect(x: (CGFloat(size) - width) / 2, y: (CGFloat(size) - height) / 2, width: width, height: height)
            canvas.clip(to: rect, mask: image)
            canvas.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            canvas.fill(rect)
            canvas.resetClip()
        }
        guard let image = canvas.makeImage() else { return nil }
        for quality in [0.85, 0.65, 0.45] {
            let bytes = NSMutableData()
            guard let jpeg = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(jpeg, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(jpeg), bytes.length <= 128 * 1024 { return bytes as Data }
        }
        return nil
    }
}
