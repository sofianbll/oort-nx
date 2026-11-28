import AppKit
import ImageIO
import OortLibrary

/// Images resized for the core (`ImageResizer`): the ImageIO thumbnail and AppKit encoding the core used before,
/// unchanged. JPEG at quality 0.94.
struct ImageIOResizer: ImageResizer {
    func resized(_ data: Data, maxPixelSize: CGFloat, png: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: image)
        if png { return rep.representation(using: .png, properties: [:]) }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.94])
    }
}
