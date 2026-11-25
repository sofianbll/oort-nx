import Foundation

public enum MoonlightSurface: String, Sendable {
    case classic, arcane, flow
    /// The Oort cloud in cross-section: a shell of dots, its disc and the Sun.
    case cloud
}

/// One dot of the cloud: where it is, the kind of thing it belongs to, and which way it faces.
public struct OortCloudPoint: Sendable {
    public var place: SIMD4<Float> // xyz, kind: 0 shell, 1 rim, 2 disc
    public var normal: SIMD4<Float>

    /// The site's cloud, made once. Unit radius, y down, the cut facing the viewer.
    public static func field() -> [OortCloudPoint] {
        var seed: UInt64 = 5
        func random() -> Float { seed = seed * 16807 % 2_147_483_647; return Float(seed) / 2_147_483_647 }
        var points: [OortCloudPoint] = []
        func add(_ x: Float, _ y: Float, _ z: Float, _ kind: Float, _ nx: Float, _ ny: Float, _ nz: Float) {
            points.append(OortCloudPoint(place: SIMD4(x, y, z, kind), normal: SIMD4(nx, ny, nz, 0)))
        }
        let shell = 9_800, golden = Float.pi * (3 - Float(5).squareRoot())
        for i in 0..<shell {
            let y = 1 - 2 * (Float(i) + 0.5) / Float(shell), r = (1 - y * y).squareRoot()
            let a = (Float(i) * golden).truncatingRemainder(dividingBy: 2 * .pi)
            let x = cos(a) * r, z = sin(a) * r
            if z > 0.1 { continue }
            let k = 0.9 + 0.1 * random()
            add(x * k, y * k, z * k, 0, x, y, z)
        }
        for j in 0..<9 {
            let r = 1 - Float(j) * 0.0165, count = 330 - j * 16
            for i in 0..<count {
                let a = Float(i) / Float(count) * 2 * .pi + Float(j) * 0.02, side = cos(a)
                if side < 0.15, Float(j) > 3 + side * 3 + 3 { continue }
                add(cos(a) * r, sin(a) * r, 0.1 - Float(j) * 0.003, 1, 0, 0, 1)
            }
        }
        for k in 0..<30 {
            let t = 0.16 + Float(k) * 0.0262, count = Int((t * 150).rounded())
            let thickness = 0.004 + 0.085 * pow(t, 2.8), layers = max(1, Int((thickness / 0.016).rounded()))
            for j in 0..<layers {
                let h = layers == 1 ? 0 : (Float(j) / Float(layers - 1) - 0.5) * 2 * thickness
                for i in 0..<count {
                    let a = (Float(i) + Float((k + j) % 2) * 0.5) / Float(count) * 2 * .pi
                    add(cos(a) * t, h, sin(a) * t, 2, 0, h < 0 ? -1 : 1, 0)
                }
            }
        }
        return points
    }
}

/// Fixed local hues, with only a small drift over three minutes.
public enum MoonlightChromatics {
    public static let period: Float = 180
    public static let intensity: Float = 0.5
    public static let colors: [SIMD3<Float>] = [SIMD3(187,91,179), SIMD3(92,181,228), SIMD3(103,92,165)].map { $0 / 255 }

    public static func sample(x: Float, y: Float, time: Float, offset: Float = 0) -> SIMD3<Float> {
        let phase = time / period * 2 * Float.pi
        let pinkWeight = exp(-pow((x - 0.18) / 0.42, 2) - pow((y - 0.77) / 0.5, 2))
        let cyanWeight = exp(-pow((x - 0.84) / 0.42, 2) - pow((y - 0.43) / 0.5, 2))
        let drift = SIMD3<Float>(2.5 * sin(phase), 1.8 * sin(phase + 1), 2.6 * sin(phase + 2)) / 255
        return (colors[0] * pinkWeight + colors[1] * cyanWeight + colors[2] * 0.25) / (pinkWeight + cyanWeight + 0.25) + drift
    }
}
