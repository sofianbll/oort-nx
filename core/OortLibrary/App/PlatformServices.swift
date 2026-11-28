import Foundation
import Synchronization

/// Resizes and re-encodes an image (a Mac: ImageIO and AppKit, `ImageIOResizer`). The core reads sizes itself
/// (`ImageHeader`); only decoding pixels needs the system.
public protocol ImageResizer: Sendable {
    /// The image at most `maxPixelSize` on its longer side, upright, as PNG or as JPEG; nil when it is not an image.
    func resized(_ data: Data, maxPixelSize: CGFloat, png: Bool) -> Data?
}

/// The language a text is written in (a Mac: NaturalLanguage, `NaturalLanguageDetector`).
public protocol TextLanguageDetector: Sendable {
    /// The leading language as a BCP 47 tag ("en", "zh-Hans") and how sure the guess is, from 0 to 1.
    func dominantLanguage(of text: String) -> (tag: String, confidence: Double)?
}

/// The system services the core asks for through a joint, given once by the app at launch (and by the probes'
/// shared start, `ProbeStart.swift`). Without them the core still runs: no image is resized (each one is refused)
/// and no text has a language; a Debug build says so once per service.
public enum PlatformServices {
    public struct Services: Sendable {
        public var imageResizer: (any ImageResizer)?
        public var languageDetector: (any TextLanguageDetector)?

        public init(imageResizer: (any ImageResizer)? = nil, languageDetector: (any TextLanguageDetector)? = nil) {
            self.imageResizer = imageResizer
            self.languageDetector = languageDetector
        }
    }

    private static let registered = Mutex<Services?>(nil)
    private static let traced = Mutex<Set<String>>([])

    /// Services for the code run inside `withValue`, in place of the registered ones: tests, never the app.
    @TaskLocal package static var scoped: Services?

    /// Gives the core every system service; called once, before the first store or service starts.
    public static func register(imageResizer: any ImageResizer, languageDetector: any TextLanguageDetector) {
        registered.withLock { $0 = Services(imageResizer: imageResizer, languageDetector: languageDetector) }
    }

    package static var imageResizer: (any ImageResizer)? {
        let found = scoped?.imageResizer ?? (scoped == nil ? registered.withLock { $0 }?.imageResizer : nil)
        if found == nil { traceMissing("ImageResizer: images are refused") }
        return found
    }

    package static var languageDetector: (any TextLanguageDetector)? {
        let found = scoped?.languageDetector ?? (scoped == nil ? registered.withLock { $0 }?.languageDetector : nil)
        if found == nil { traceMissing("TextLanguageDetector: texts have no language") }
        return found
    }

    private static func traceMissing(_ what: String) {
        #if DEBUG
        guard scoped == nil, traced.withLock({ $0.insert(what).inserted }) else { return }
        FileHandle.standardError.write(Data("Oort: no \(what) (PlatformServices.register was not called)\n".utf8))
        #endif
    }
}
