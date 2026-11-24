import Foundation
import XCTest
import zlib
@testable import NXLibraryCore

final class SoundPackTests: XCTestCase {
    func testMissingEventsAndImportSnapshot() throws {
        try withFolder { root in
            let source = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
            let manifest = source.appendingPathComponent("manifest.json")
            try metadata.write(to: manifest)
            try wave.write(to: source.appendingPathComponent("tone.wav"))
            let pack = try SoundPack.read(source)
            XCTAssertNil(pack.audio(for: .move))
            XCTAssertEqual(pack.audio(for: .select), wave)
            let library = SoundPackLibrary(root: root.appendingPathComponent("installed"), bundled: nil)
            try Data().write(to: manifest)
            try library.install(pack)
            XCTAssertEqual(try library.load("custom.fixture")?.audio(for: .select), wave)
            XCTAssertNil(try library.load("selene"))
            XCTAssertThrowsError(try library.install(pack))
            XCTAssertThrowsError(try library.load("custom.../outside"))
        }
    }

    func testRejectsInvalidManifestsAndAudio() throws {
        try withFolder { root in
            let manifest = root.appendingPathComponent("manifest.json")
            let wav = root.appendingPathComponent("tone.wav")
            try wave.write(to: wav)
            for (target, value) in [("fixture", "../outside"), ("tone.wav", "../tone.wav"),
                                    ("select", "exec"), ("\"format\":1", "\"script\":\"oops\",\"format\":1")] {
                let modified = String(decoding: metadata, as: UTF8.self).replacingOccurrences(of: target, with: value)
                try Data(modified.utf8).write(to: manifest)
                XCTAssertThrowsError(try SoundPack.read(root), modified)
            }
            try metadata.write(to: manifest)
            try Data(repeating: 0, count: 4 * 1024 * 1024 + 1).write(to: wav)
            XCTAssertThrowsError(try SoundPack.read(root))
            var tooLoud = wave
            tooLoud.replaceSubrange(44..<46, with: [0xff, 0x7f])
            try tooLoud.write(to: wav)
            XCTAssertThrowsError(try SoundPack.read(root))
            try FileManager.default.removeItem(at: wav)
            try FileManager.default.createSymbolicLink(at: wav, withDestinationURL: manifest)
            XCTAssertThrowsError(try SoundPack.read(root))
        }
    }

    func testZIPRejectsTraversalInEitherHeaderAndOversize() throws {
        try withFolder { root in
            let archive = root.appendingPathComponent("fixture.oortsound")
            let files = [("manifest.json", metadata), ("tone.wav", wave)]
            try zip(files).write(to: archive)
            XCTAssertEqual(try SoundPack.read(archive).audio(for: .select), wave)
            try zip(files, deflated: true).write(to: archive)
            XCTAssertEqual(try SoundPack.read(archive).audio(for: .select), wave)
            for bytes in [zip([("manifest.json", metadata), ("../a.wav", wave)]),
                          zip(files, centralName: "../a.wav"),
                          zip(files, declaredSize: 5 * 1024 * 1024)] {
                try bytes.write(to: archive)
                XCTAssertThrowsError(try SoundPack.read(archive))
            }
        }
    }

    func testLegacySettingsDefaultAndPackChoiceRoundTrip() throws {
        let defaults = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults.soundPackID, "selene")
        var selected = defaults
        selected.soundPackID = "custom.fixture"
        let reopened = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(reopened.soundPackID, "custom.fixture")
        XCTAssertEqual(SettingsReset.resetShared(.soundMusic, in: reopened).soundPackID, "selene")
    }

    func testBundledOriginalsValidateWithoutChangingTheDefault() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        try withFolder { root in
            let library = SoundPackLibrary(root: root, bundled: sources.appendingPathComponent("Resources/SoundPacks"))
            XCTAssertEqual(library.choices().map(\.name), ["Selene", "Oort", "Pollen", "Umbra", "Impulsion"])
            let oort = try XCTUnwrap(library.load("oort"))
            XCTAssertNil(oort.audio(for: .move))
            XCTAssertNil(oort.audio(for: .boot))
            XCTAssertEqual(oort.audio(for: .resume)?.count, 44 + 7_680)
        }
    }

    private let metadata = Data(#"{"format":1,"id":"fixture","name":"Fixture","author":"Tests","license":"CC0-1.0","version":"1.0.0","events":{"select":["tone.wav"]}}"#.utf8)
    private var wave: Data {
        Data([82,73,70,70, 4,2,0,0, 87,65,86,69, 102,109,116,32, 16,0,0,0, 1,0,1,0,
              192,93,0,0, 128,187,0,0, 2,0,16,0, 100,97,116,97, 224,1,0,0]) + Data(repeating: 0, count: 480)
    }

    private func withFolder(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func zip(_ files: [(String, Data)], centralName: String? = nil, declaredSize: Int? = nil,
                     deflated: Bool = false) -> Data {
        func le(_ v: Int, _ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) }) }
        var local = Data(), central = Data()
        for (index, file) in files.enumerated() {
            let name = Data(file.0.utf8), alternate = centralName.map { Data($0.utf8) }
            let centralFile = index == 1 ? alternate ?? name : name
            let crc = file.1.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(file.1.count)) }
            // A raw DEFLATE final uncompressed block, independent of the importer.
            let bytes = deflated ? Data([1]) + le(file.1.count, 2) + le(~file.1.count, 2) + file.1 : file.1
            var shared = le(20, 2) + le(0, 2) + le(deflated ? 8 : 0, 2) + le(0, 4)
            shared.append(le(Int(crc), 4))
            shared.append(le(bytes.count, 4))
            shared.append(le(declaredSize ?? file.1.count, 4))
            var entry = le(0x02014b50, 4) + le(20, 2) + shared + le(centralFile.count, 2)
            entry.append(Data(repeating: 0, count: 12))
            entry.append(le(local.count, 4))
            central.append(entry + centralFile)
            local.append(le(0x04034b50, 4) + shared + le(name.count, 2) + le(0, 2) + name + bytes)
        }
        var end = le(0x06054b50, 4) + le(0, 4) + le(files.count, 2) + le(files.count, 2)
        end.append(le(central.count, 4) + le(local.count, 4) + le(0, 2))
        return local + central + end
    }
}
