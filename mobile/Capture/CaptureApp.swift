// Renders the app's screens to PNG files with Mac Catalyst: the same UIKit and SwiftUI as iOS, no simulator.
// usage: OortCapture <folder> (AppleLanguages chooses the words). Synthetic games, in-memory settings, one hidden window.
import OortMobile
import ShellHost
import ShellModel
import SwiftUI
import UIKit

@main final class CaptureApp: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: nil, sessionRole: s.role)
        c.delegateClass = CaptureScene.self
        return c
    }
}

final class CaptureScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        let window = UIWindow(windowScene: scene as! UIWindowScene)
        self.window = window
        Task { @MainActor in
            do { try await Capture.run(in: window) } catch { FileHandle.standardError.write(Data("capture: \(error)\n".utf8)); exit(1) }
            exit(0)
        }
    }
}

@MainActor enum Capture {
    struct Frame { let name: String, size: CGSize, phone: Bool, insets: UIEdgeInsets, scale: CGFloat }
    // Catalyst draws the tab bar in the Mac window's own bar, so the pictures leave its place empty (49 points on a phone).
    static let frames = [
        Frame(name: "portrait", size: CGSize(width: 390, height: 844), phone: true, insets: UIEdgeInsets(top: 47, left: 0, bottom: 83, right: 0), scale: 2),
        Frame(name: "paysage", size: CGSize(width: 844, height: 390), phone: true, insets: UIEdgeInsets(top: 0, left: 47, bottom: 70, right: 47), scale: 2),
        Frame(name: "ipad-portrait", size: CGSize(width: 1024, height: 1366), phone: false, insets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), scale: 1),
        Frame(name: "ipad-paysage", size: CGSize(width: 1366, height: 1024), phone: false, insets: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), scale: 1),
    ]

    static func run(in window: UIWindow) async throws {
        let args = ProcessInfo.processInfo.environment
        let out = URL(fileURLWithPath: args["OORT_CAPTURE_DIR"] ?? NSTemporaryDirectory())
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let only = args["OORT_CAPTURE_ONLY"].flatMap { $0.isEmpty ? nil : $0.split(separator: ",").map(String.init) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oort-capture-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try CaptureGames.make(in: root)
        let model = makeModel(root, games: "Frameworks"), empty = makeModel(root, games: "None")
        await settle()
        let sounds = OortSounds(defaults: TestDefaults.make("sounds"))
        sounds.isOn = false
        for frame in frames {
            for screen in OortCaptureEntry.screens + ["empty", "home-large", "options-large"] {
                let name = "\(frame.name)-\(screen)"
                if let only, !only.contains(where: { name.contains($0) }) { continue }
                let base = screen == "empty" ? "home" : screen.replacingOccurrences(of: "-large", with: "")
                let view = OortCaptureEntry.view(base, model: screen == "empty" ? empty : model, sounds: sounds)
                let host = UIHostingController(rootView: view)
                let parent = UIViewController()
                host.traitOverrides.userInterfaceIdiom = frame.phone ? .phone : .pad
                host.traitOverrides.horizontalSizeClass = frame.phone ? .compact : .regular
                host.traitOverrides.verticalSizeClass = frame.phone && frame.size.height < 500 ? .compact : .regular
                host.traitOverrides.preferredContentSizeCategory = screen.hasSuffix("-large") ? .accessibilityLarge : .large
                host.traitOverrides.displayScale = frame.scale
                parent.additionalSafeAreaInsets = frame.insets
                parent.addChild(host)
                parent.view.addSubview(host.view)
                window.rootViewController = parent
                window.frame = CGRect(origin: .zero, size: frame.size)
                parent.view.frame = window.bounds
                host.view.frame = window.bounds
                host.didMove(toParent: parent)
                window.isHidden = false
                window.alpha = 1
                await settle()
                let format = UIGraphicsImageRendererFormat()
                format.scale = frame.scale
                let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                try image.pngData()!.write(to: out.appendingPathComponent(name + ".png"))
                print(name)
            }
        }
    }

    static func settle() async { try? await Task.sleep(for: .milliseconds(650)) }

    static func makeModel(_ root: URL, games: String) -> ShellHostModel {
        let defaults = TestDefaults.keyed("capture")
        let config = ShellHostConfig(gamesRoot: root.appendingPathComponent(games), appDataRoot: root.appendingPathComponent("Documents/games"),
                                     environment: HostEnvironment(chain: "b-000000"), defaults: defaults)
        LastPlayedStore(defaults: defaults(CaptureGames.all[0].id)).record(Date(timeIntervalSinceNow: -7200))
        LastPlayedStore(defaults: defaults(CaptureGames.all[1].id)).record(Date(timeIntervalSinceNow: -190_000))
        return ShellHostModel(config: config, shellSettings: ShellSettingsStore(defaults: TestDefaults.make("shell")))
    }
}
