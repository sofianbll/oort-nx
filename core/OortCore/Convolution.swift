import Foundation

/// Linear convolution in plain Swift (radix-2 FFT in Double), so sound synthesis needs no Accelerate.
///
/// The loops are plain `while` loops over raw pointers: a Debug build (the tests) does not specialise `for … in`
/// ranges or array subscripts, which then cost more than the arithmetic.
public enum Convolution {
    /// The first `count` samples of `signal * kernel`: y[n] = sum over q of signal[n - q] * kernel[q].
    public static func convolve(_ signal: [Float], _ kernel: [Float], count: Int) -> [Float] {
        // Trailing zeros, and samples past `count`, add nothing to the first `count` outputs: a smaller transform.
        func trimmed(_ values: [Float]) -> [Float] {
            let end = min(count, (values.lastIndex { $0 != 0 } ?? -1) + 1)
            return end == values.count ? values : Array(values.prefix(max(0, end)))
        }
        let signal = trimmed(signal), kernel = trimmed(kernel)
        guard count > 0, !signal.isEmpty, !kernel.isEmpty else { return [Float](repeating: 0, count: max(0, count)) }
        var size = 2
        while size < signal.count + kernel.count - 1 { size <<= 1 }
        // One complex transform carries both real inputs: z = signal + i * kernel.
        var re = [Double](repeating: 0, count: size), im = [Double](repeating: 0, count: size)
        re.withUnsafeMutableBufferPointer { re in
            signal.withUnsafeBufferPointer { signal in
                var n = 0
                while n < signal.count { re[n] = Double(signal[n]); n += 1 }
            }
        }
        im.withUnsafeMutableBufferPointer { im in
            kernel.withUnsafeBufferPointer { kernel in
                var n = 0
                while n < kernel.count { im[n] = Double(kernel[n]); n += 1 }
            }
        }
        let table = Twiddles(size: size)
        transform(&re, &im, table, inverse: false)
        var outRe = [Double](repeating: 0, count: size), outIm = [Double](repeating: 0, count: size)
        re.withUnsafeBufferPointer { re in
            im.withUnsafeBufferPointer { im in
                outRe.withUnsafeMutableBufferPointer { outRe in
                    outIm.withUnsafeMutableBufferPointer { outIm in
                        var k = 0
                        while k < size {
                            let m = (size - k) & (size - 1)
                            // X = (Z[k] + conj Z[m]) / 2, H = (Z[k] - conj Z[m]) / 2i, then X * H.
                            let xr = (re[k] + re[m]) / 2, xi = (im[k] - im[m]) / 2
                            let hr = (im[k] + im[m]) / 2, hi = (re[m] - re[k]) / 2
                            outRe[k] = xr * hr - xi * hi
                            outIm[k] = xr * hi + xi * hr
                            k += 1
                        }
                    }
                }
            }
        }
        transform(&outRe, &outIm, table, inverse: true)
        let scale = 1 / Double(size)
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { result in
            outRe.withUnsafeBufferPointer { outRe in
                var n = 0
                while n < min(count, size) { result[n] = Float(outRe[n] * scale); n += 1 }
            }
        }
        return result
    }

    private struct Twiddles {
        var cos: [Double], sin: [Double]
        init(size: Int) {
            let half = size / 2
            cos = [Double](repeating: 0, count: half)
            sin = [Double](repeating: 0, count: half)
            var k = 0
            while k < half {
                let angle = 2 * Double.pi * Double(k) / Double(size)
                cos[k] = Foundation.cos(angle)
                sin[k] = Foundation.sin(angle)
                k += 1
            }
        }
    }

    private static func transform(_ re: inout [Double], _ im: inout [Double], _ table: Twiddles, inverse: Bool) {
        let n = re.count
        let sign: Double = inverse ? 1 : -1
        re.withUnsafeMutableBufferPointer { reBuffer in
            im.withUnsafeMutableBufferPointer { imBuffer in
                table.cos.withUnsafeBufferPointer { cosBuffer in
                    table.sin.withUnsafeBufferPointer { sinBuffer in
                        let re = reBuffer.baseAddress!, im = imBuffer.baseAddress!
                        let cosT = cosBuffer.baseAddress!, sinT = sinBuffer.baseAddress!
                        var i = 1, j = 0
                        while i < n {
                            var bit = n >> 1
                            while j & bit != 0 { j ^= bit; bit >>= 1 }
                            j ^= bit
                            if i < j {
                                let r = re[i], m = im[i]
                                re[i] = re[j]; im[i] = im[j]
                                re[j] = r; im[j] = m
                            }
                            i += 1
                        }
                        var length = 2
                        while length <= n {
                            let half = length / 2, step = n / length
                            var start = 0
                            while start < n {
                                var k = 0
                                while k < half {
                                    let wr = cosT[k * step], wi = sign * sinT[k * step]
                                    let a = start + k, b = a + half
                                    let tr = re[b] * wr - im[b] * wi, ti = re[b] * wi + im[b] * wr
                                    re[b] = re[a] - tr; im[b] = im[a] - ti
                                    re[a] += tr; im[a] += ti
                                    k += 1
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
