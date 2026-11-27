import AppKit

@MainActor final class NativePlayFixture: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        let started = root.appendingPathComponent("started")
        try! Data("\(getpid()) \(NSApp.windows.count)".utf8).write(to: started)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(0) }
    }
}

@main struct Fixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = NativePlayFixture()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
