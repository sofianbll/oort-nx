import XCTest
@testable import OortLibrary

final class SteamManifestPathsTests: XCTestCase {
    func testOnlyManifestsAndTheLibraryIndexAreRelevant() {
        let root = "/Users/p/Library/Application Support/Steam", second = "/Volumes/Games/SteamLibrary"
        let libraries = [root, second]  // as `watch` keeps them: resolved paths
        func relevant(_ path: String) -> Bool { SteamManifestPaths.isRelevant(path, libraries: libraries, root: root) }
        XCTAssertTrue(relevant(root + "/steamapps/appmanifest_3321460.acf"))
        XCTAssertTrue(relevant(second + "/steamapps/appmanifest_10.acf"))
        XCTAssertTrue(relevant(root + "/steamapps/libraryfolders.vdf"))
        XCTAssertFalse(relevant(second + "/steamapps/libraryfolders.vdf"))
        XCTAssertFalse(relevant(root + "/steamapps/downloading/3321460/data.bin"))
        XCTAssertFalse(relevant(root + "/steamapps/common/Game/appmanifest_1.acf"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_1.acf.tmp"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_x.acf"))
        XCTAssertFalse(relevant(root + "/steamapps/appmanifest_.acf"))
        XCTAssertFalse(relevant("/Volumes/Other/steamapps/appmanifest_1.acf"))
        XCTAssertFalse(relevant(root + "/steamapps"))
    }

    func testDroppedEventsCountOnlyForASteamappsFolderOrAbove() {
        let root = "/Users/p/Library/Application Support/Steam"
        func dropped(_ path: String) -> Bool { SteamManifestPaths.isRelevant(path, dropped: true, libraries: [root], root: root) }
        // A drop inside a download's folder says nothing about the manifests: no rescan every batch.
        XCTAssertFalse(dropped(root + "/steamapps/downloading/3321460"))
        XCTAssertFalse(dropped(root + "/steamapps/common/Game"))
        XCTAssertTrue(dropped(root + "/steamapps"))
        XCTAssertTrue(dropped(root + "/steamapps/"))
        XCTAssertTrue(dropped("/Users/p/Library"))
        XCTAssertFalse(dropped("/Volumes/Other"))
        XCTAssertTrue(SteamManifestPaths.isRelevant(root + "/steamapps/appmanifest_1.acf", dropped: false, libraries: [root], root: root))
    }

}
