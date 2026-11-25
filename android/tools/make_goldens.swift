// Writes the numbers the Kotlin ports of the Oort cloud and OortSynth must reproduce.
// Built from the real Swift sources, so the Android tests compare against the Mac's own output:
//   swiftc -O android/tools/make_goldens.swift Sources/NXLibraryCore/Selene/MoonlightAppearance.swift \
//     Sources/NXLibraryCore/Selene/OortSynth.swift -o /tmp/make_goldens && /tmp/make_goldens > android/app/src/test/resources/goldens.json
import Foundation

// The only symbol OortSynth takes from SoundPack.swift; the cases are copied from there.
public enum SoundPackEvent: String, CaseIterable, Sendable {
    case move, select, confirm, back, deny, open, close, play, resume, success, notification, boot, ambience
}

func r(_ x: Float) -> Double { (Double(x) * 1e7).rounded() / 1e7 }

func decode(_ data: Data) -> (frames: Int, left: [Int16]) {
    let body = data.dropFirst(44)
    var left: [Int16] = []
    var i = body.startIndex
    while i + 3 < body.endIndex {
        left.append(Int16(bitPattern: UInt16(body[i]) | UInt16(body[i + 1]) << 8))
        i += 4
    }
    return (left.count, left)
}
@main struct Goldens {
 static func main() throws {
var out: [String: Any] = [:]

let points = OortCloudPoint.field()
var kinds: [String: Any] = [:]
for kind in 0...2 {
    let part = points.filter { Int($0.place.w) == kind }
    var sums = [0.0, 0.0, 0.0]
    for p in part { sums[0] += Double(p.place.x); sums[1] += Double(p.place.y); sums[2] += Double(p.place.z) }
    kinds[String(kind)] = ["count": part.count, "sum": sums.map { ($0 * 1e4).rounded() / 1e4 }]
}
func row(_ p: OortCloudPoint) -> [Double] {
    [r(p.place.x), r(p.place.y), r(p.place.z), Double(p.place.w), r(p.normal.x), r(p.normal.y), r(p.normal.z)]
}
out["cloud"] = ["count": points.count, "kinds": kinds,
                "samples": [0, 1, 2, points.count / 3, points.count / 2, points.count - 1].map { ["index": $0, "point": row(points[$0])] }]

var sounds: [[String: Any]] = []
let cases: [(String, SoundPackEvent, Int)] = [
    ("oort", .move, 0), ("oort", .move, 3), ("oort", .select, 0), ("oort", .success, 0), ("oort", .boot, 0),
    ("umbra", .confirm, 0), ("impulsion", .deny, 0), ("pollen", .open, 0),
]
for (pack, event, step) in cases {
    guard let synth = OortSynth(pack: pack), let wav = synth.wav(event, step: step) else { continue }
    let (frames, left) = decode(wav)
    var energy = 0.0
    for s in left { energy += Double(s) * Double(s) }
    let probes = [0, 50, 200, 1000, 5000, 20000, 48000, 90000].filter { $0 < frames }
    sounds.append(["pack": pack, "event": event.rawValue, "step": step, "frames": frames,
                   "rms": ((energy / Double(frames)).squareRoot() * 1000).rounded() / 1000,
                   "probes": probes.map { ["index": $0, "left": Int($0 < left.count ? left[$0] : 0)] }])
}
out["sounds"] = sounds

let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)

 }
}
