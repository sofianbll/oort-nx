import Foundation

/// Linear convolution in plain Swift (radix-2 FFT in Double), so sound synthesis needs no Accelerate.
public enum Convolution {
    /// The first `count` samples of `signal * kernel`: y[n] = sum over q of signal[n - q] * kernel[q].
    public static func convolve(_ signal: [Float], _ kernel: [Float], count: Int) -> [Float] {
        guard count > 0, !signal.isEmpty, !kernel.isEmpty else { return [Float](repeating: 0, count: max(0, count)) }
        var size = 2
        while size < signal.count + kernel.count - 1 { size <<= 1 }
        // One complex transform carries both real inputs: z = signal + i * kernel.
        var re = [Double](repeating: 0, count: size), im = [Double](repeating: 0, count: size)
        for (n, v) in signal.enumerated() { re[n] = Double(v) }
        for (n, v) in kernel.enumerated() { im[n] = Double(v) }
        let table = Twiddles(size: size)
        transform(&re, &im, table, inverse: false)
        var outRe = [Double](repeating: 0, count: size), outIm = [Double](repeating: 0, count: size)
        for k in 0..<size {
            let m = (size - k) & (size - 1)
            // X = (Z[k] + conj Z[m]) / 2, H = (Z[k] - conj Z[m]) / 2i, then X * H.
            let xr = (re[k] + re[m]) / 2, xi = (im[k] - im[m]) / 2
            let hr = (im[k] + im[m]) / 2, hi = (re[m] - re[k]) / 2
            outRe[k] = xr * hr - xi * hi
            outIm[k] = xr * hi + xi * hr
        }
        transform(&outRe, &outIm, table, inverse: true)
        let scale = 1 / Double(size)
        return (0..<count).map { $0 < size ? Float(outRe[$0] * scale) : 0 }
    }

    private struct Twiddles {
        let cos: [Double], sin: [Double]
        init(size: Int) {
            let half = size / 2
            cos = (0..<half).map { Foundation.cos(2 * Double.pi * Double($0) / Double(size)) }
            sin = (0..<half).map { Foundation.sin(2 * Double.pi * Double($0) / Double(size)) }
        }
    }

    private static func transform(_ re: inout [Double], _ im: inout [Double], _ table: Twiddles, inverse: Bool) {
        let n = re.count
        let sign: Double = inverse ? 1 : -1
        re.withUnsafeMutableBufferPointer { re in
            im.withUnsafeMutableBufferPointer { im in
                table.cos.withUnsafeBufferPointer { cosT in
                    table.sin.withUnsafeBufferPointer { sinT in
                        var j = 0
                        for i in 1..<n {
                            var bit = n >> 1
                            while j & bit != 0 { j ^= bit; bit >>= 1 }
                            j ^= bit
                            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
                        }
                        var length = 2
                        while length <= n {
                            let half = length / 2, step = n / length
                            var start = 0
                            while start < n {
                                for k in 0..<half {
                                    let wr = cosT[k * step], wi = sign * sinT[k * step]
                                    let a = start + k, b = a + half
                                    let tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr
                                    re[b] = re[a] - tr; im[b] = im[a] - ti
                                    re[a] += tr; im[a] += ti
                                }
                                start += length
                            }
                            length <<= 1
                        }
                    }
                }
            }
        }
    }
}
