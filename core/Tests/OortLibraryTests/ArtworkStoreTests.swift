import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Synchronization
@testable import OortLibrary

final class ArtworkStoreTests: XCTestCase {
    @dynamicMemberLookup private final class FakeClient: ArtworkHTTPClient {
        struct State: Sendable {
            var body: Data?
            var error: Error?
            var calls = 0
        }
        private let state = Mutex(State())
        subscript<Value: Sendable>(dynamicMember key: WritableKeyPath<State, Value>) -> Value {
            get { state.withLock { $0[keyPath: key] } }
            set { state.withLock { $0[keyPath: key] = newValue } }
        }
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let now = state.withLock { $0.calls += 1; return $0 }
            if let error = now.error { throw error }
            return (now.body ?? Data(), HTTPURLResponse(url: request.url!, statusCode: 200,
                                                    httpVersion: nil, headerFields: nil)!)
        }
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NXArt-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The core resizes through the joint; `ImageIOResizerTests` (OortMacTests) checks real pixels on a Mac.
    override func invokeTest() {
        PlatformServices.$scoped.withValue(.init(imageResizer: FakeImageResizer())) { super.invokeTest() }
    }

    private func imageData(width: Int, height: Int) -> Data {
        TestImages.jpegHeader(width: width, height: height)
    }

    /// `downsample` is the joint's resizer, here the fake: no larger than asked, and nothing for bytes that are no image.
    func testDownsampleGoesThroughTheResizer() {
        let jpeg = ArtworkStore.downsample(imageData(width: 4000, height: 3000), maxPixelSize: 2560)
        XCTAssertEqual(jpeg.flatMap(TestImages.longerSide), 2560)
        XCTAssertEqual(ArtworkStore.downsample(TestImages.png(width: 64, height: 32), maxPixelSize: 512, png: true)
            .flatMap(ImageHeader.pixelSize)?.width, 64, "never enlarged")
        XCTAssertNil(ArtworkStore.downsample(Data("not an image".utf8), maxPixelSize: 512))
    }

    func testFetchCachesAndDoesNotRedownload() async throws {
        let client = FakeClient()
        client.body = imageData(width: 3000, height: 2000)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = URL(string: "https://example.com/hero.jpg")!
        let first = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertNotNil(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(first).path))
        let second = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertEqual(first, second)
        XCTAssertEqual(client.calls, 1)
    }

    func testFailureReturnsNilWithoutCache() async {
        let client = FakeClient()
        client.error = URLError(.notConnectedToInternet)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = URL(string: "https://example.com/hero.jpg")!
        let result = await store.fetch(titleID: "0100", remoteURL: url, kind: .hero)
        XCTAssertNil(result)
    }

    func testNilRemoteURLReturnsCachedFileWhenPresent() async {
        let client = FakeClient()
        client.body = imageData(width: 800, height: 600)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = URL(string: "https://example.com/cover.jpg")!
        let cached = await store.fetch(titleID: "0100", remoteURL: url, kind: .boxart)
        XCTAssertNotNil(cached)
        let offline = await store.fetch(titleID: "0100", remoteURL: nil, kind: .boxart)
        XCTAssertEqual(cached, offline)
    }

    func testClearRemovesFiles() async {
        let client = FakeClient()
        client.body = imageData(width: 800, height: 600)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        _ = await store.fetch(titleID: "0100",
                              remoteURL: URL(string: "https://example.com/cover.jpg"),
                              kind: .boxart)
        XCTAssertGreaterThan(store.cacheSize(), 0)
        store.clear { try FileManager.default.removeItem(at: $0) }
        XCTAssertEqual(store.cacheSize(), 0)
    }

    func testTrimRemovesFilesOverCap() async {
        let client = FakeClient()
        client.body = imageData(width: 800, height: 600)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        _ = await store.fetch(titleID: "0100",
                              remoteURL: URL(string: "https://example.com/cover.jpg"),
                              kind: .boxart)
        XCTAssertGreaterThan(store.cacheSize(), 0)
        store.trimCache(maxBytes: 1)
        XCTAssertEqual(store.cacheSize(), 0)
    }

    func testDownsampleLimitsHeroAndCover() async throws {
        let client = FakeClient()
        client.body = imageData(width: 4000, height: 3000)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let heroFetched = await store.fetch(titleID: "0100",
                                     remoteURL: URL(string: "https://example.com/h.jpg"),
                                     kind: .hero)
        let hero = try XCTUnwrap(heroFetched)
        let coverFetched = await store.fetch(titleID: "0100",
                                      remoteURL: URL(string: "https://example.com/c.jpg"),
                                      kind: .boxart)
        let cover = try XCTUnwrap(coverFetched)
        XCTAssertEqual(TestImages.longerSide(try Data(contentsOf: hero)), 2560)
        XCTAssertEqual(TestImages.longerSide(try Data(contentsOf: cover)), 1400)
    }

    func testLogoPreservesPNG() async throws {
        let client = FakeClient()
        client.body = imageData(width: 800, height: 400)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let logoFetched = await store.fetch(titleID: "0100",
                                     remoteURL: URL(string: "https://example.com/logo.png"),
                                     kind: .logo)
        let logo = try XCTUnwrap(logoFetched)
        XCTAssertEqual(logo.pathExtension, "png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: logo.path))
    }

    func testSquareKindFileURL() async {
        let client = FakeClient()
        client.body = imageData(width: 1024, height: 1024)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = await store.fetch(titleID: "0100ABC",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)
        XCTAssertEqual(url, dir.appendingPathComponent("0100ABC").appendingPathComponent("square.png"))
        XCTAssertEqual(store.cachedURL(titleID: "0100ABC", kind: .square), url)
    }

    func testSquareMaxPixelSize512() async throws {
        XCTAssertEqual(ArtworkKind.square.maxPixelSize, 512)
        let client = FakeClient()
        client.body = imageData(width: 1024, height: 1024)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let urlFetched = await store.fetch(titleID: "0100",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)
        let url = try XCTUnwrap(urlFetched)
        XCTAssertEqual(TestImages.longerSide(try Data(contentsOf: url)), 512)
    }

    /// The square is asked for as PNG, so transparency can survive; that ImageIO keeps it is `ImageIOResizerTests`.
    func testSquareIsAskedForAsPNG() async throws {
        let client = FakeClient()
        client.body = TestImages.png(width: 64, height: 64)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let urlFetched = await store.fetch(titleID: "0100",
                                    remoteURL: URL(string: "https://example.com/s.png"),
                                    kind: .square)
        let url = try XCTUnwrap(urlFetched)
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: url).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    /// Without an `ImageResizer` nothing is cached: an image is never kept unchecked.
    func testWithoutAResizerNothingIsKept() async {
        let client = FakeClient()
        client.body = imageData(width: 800, height: 600)
        let store = ArtworkStore(cacheDirectory: tempDir(), client: client)
        let url = await PlatformServices.$scoped.withValue(.init()) {
            await store.fetch(titleID: "0100", remoteURL: URL(string: "https://example.com/c.jpg"), kind: .boxart)
        }
        XCTAssertNil(url)
        XCTAssertEqual(store.cacheSize(), 0)
    }

    func testScreenshotCachePath() async throws {
        let client = FakeClient()
        client.body = imageData(width: 3200, height: 1800)
        let dir = tempDir()
        let store = ArtworkStore(cacheDirectory: dir, client: client)
        let url = URL(string: "https://api.nlib.cc/nx/0100/screen/1")!
        let first = await store.screenshot(titleID: "0100", index: 1, remoteURL: url)
        XCTAssertEqual(first?.lastPathComponent, "screen-1.jpg")
        XCTAssertEqual(first?.deletingLastPathComponent().lastPathComponent, "0100")
        XCTAssertEqual(TestImages.longerSide(try Data(contentsOf: try XCTUnwrap(first))), 1600)
        let second = await store.screenshot(titleID: "0100", index: 1, remoteURL: url)
        XCTAssertEqual(first, second)
        XCTAssertEqual(client.calls, 1)
    }
}
