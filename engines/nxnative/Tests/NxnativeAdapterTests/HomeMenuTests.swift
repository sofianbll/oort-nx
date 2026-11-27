import XCTest
@testable import ArcanePorting

final class HomeMenuTests: XCTestCase {
    func testLaunchOptsInOnlyWithTheBuiltHostCapabilityAndLauncherBundleID() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let host = app.appendingPathComponent("Contents/MacOS/dmhost")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: app) }

        XCTAssertFalse(HomeMenu.supported(by: app))
        try Data("DM_HOME_MENU_LAUNCHER\0DM_LAUNCHER_BUNDLE_ID\0".utf8).write(to: host)
        XCTAssertFalse(HomeMenu.supported(by: app))
        try Data("\0DM_HOME_MENU_LAUNCHER\0DM_LAUNCHER_BUNDLE_ID\0org.nxnative.resume.%d\0org.nxnative.quit.%d\0".utf8).write(to: host)
        XCTAssertTrue(HomeMenu.supported(by: app))
        try Data("\0DM_HOME_MENU_LAUNCHER\0DM_LAUNCHER_BUNDLE_ID\0org.nxnative.%@.%d\0".utf8).write(to: host)
        XCTAssertTrue(HomeMenu.supported(by: app))

        XCTAssertEqual(HomeMenu.environment(supported: true, launcherBundleID: "local.arcane.dev"),
                       ["DM_HOME_MENU_LAUNCHER": "1", "DM_LAUNCHER_BUNDLE_ID": "local.arcane.dev"])
        XCTAssertTrue(HomeMenu.environment(supported: false, launcherBundleID: "local.arcane.dev").isEmpty)
        XCTAssertTrue(HomeMenu.environment(supported: true, launcherBundleID: nil).isEmpty)
    }

    func testFindsAndSignalsOnlyTheHostChild() throws {
        let executable = URL(fileURLWithPath: "/bin/sleep")
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        wrapper.arguments = ["-c", "/usr/bin/tail -f /dev/null & helper=$!; \"$1\" 5 & wait $!; kill $helper; wait $helper",
                             "wrapper", executable.path]
        wrapper.standardError = FileHandle.nullDevice
        try wrapper.run()
        defer { wrapper.waitUntilExit() }
        let deadline = Date().addingTimeInterval(2)
        var found: HomeMenu.Host?
        while found == nil, wrapper.isRunning, Date() < deadline {
            found = HomeMenu.Host.find(appPID: wrapper.processIdentifier, executable: executable)
            if found == nil { Thread.sleep(forTimeInterval: 0.02) }
        }
        let host = try XCTUnwrap(found)
        XCTAssertNotEqual(host.pid, wrapper.processIdentifier)
        XCTAssertEqual(HomeMenu.Host.find(appPID: host.pid, executable: executable), host)
        XCTAssertTrue(host.terminate())
        wrapper.waitUntilExit()
        XCTAssertFalse(host.isAlive)
        XCTAssertFalse(host.terminate())
    }

    func testPauseResumeQuitAndExitForTheHostPID() {
        var session = HomeMenu.Session(pid: 411)
        XCTAssertEqual(session.phase, .running)
        XCTAssertNil(session.resumeRequest())
        XCTAssertEqual(session.resumeRequest(hostIsHidden: true), "org.nxnative.resume.411")
        XCTAssertNil(session.requestQuit())
        session.receive(.paused, from: 410)
        XCTAssertEqual(session.phase, .running)
        session.receive(.paused, from: 411)
        XCTAssertEqual(session.phase, .paused)
        XCTAssertEqual(session.resumeRequest(), "org.nxnative.resume.411")
        session.receive(.resumed, from: 411)
        XCTAssertEqual(session.phase, .running)
        XCTAssertNil(session.resumeRequest())
        session.receive(.paused, from: 411)
        XCTAssertEqual(session.requestQuit(), "org.nxnative.quit.411")
        XCTAssertEqual(session.phase, .quitting)
        XCTAssertNil(session.resumeRequest(hostIsHidden: true))
        XCTAssertNil(session.requestQuit())
        session.quitTimedOut()
        XCTAssertEqual(session.phase, .paused)
        session.receive(.exited, from: 411)
        session.receive(.paused, from: 411)
        XCTAssertEqual(session.phase, .exited)
        XCTAssertNil(session.resumeRequest(hostIsHidden: true))
    }
}
