import Foundation

/// A raw DEFLATE stream (RFC 1951), as a ZIP entry holds it, decoded in plain Swift: zlib is a system library on
/// Apple systems only. Written after zlib's reference decoder, `puff`. The input is untrusted: the output may not
/// exceed the size the archive announced, must reach it exactly, and the stream must end at the last input byte.
public enum Inflate {
    public enum Failure: Error, Equatable {
        /// A block, a code or a distance the format does not allow.
        case malformed
        /// The input ended inside the stream.
        case truncated
        /// More bytes than announced, or fewer.
        case wrongSize
        /// Input left after the last block.
        case trailingData
    }

    public static func raw(_ input: Data, size: Int) throws -> Data {
        var state = State(input: [UInt8](input), limit: size)
        var last = false
        while !last {
            last = try state.bits(1) == 1
            switch try state.bits(2) {
            case 0: try state.stored()
            case 1: try state.codes(Fixed.literals, Fixed.distances)
            case 2: try state.dynamic()
            default: throw Failure.malformed
            }
        }
        guard state.position == state.input.count else { throw Failure.trailingData }
        guard state.output.count == size else { throw Failure.wrongSize }
        return Data(state.output)
    }

    /// Canonical Huffman code: how many codes have each length, then the symbols in code order.
    fileprivate struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        /// Nil when the lengths over-subscribe the code (more codes than bits allow).
        init?(lengths: [Int]) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths { count[length] += 1 }
            var left = 1
            for length in 1..<16 {
                left <<= 1
                left -= count[length]
                if left < 0 { return nil }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + count[length] }
            for (value, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = value
                offsets[length] += 1
            }
        }
    }

    private enum Fixed {
        static let literals = Huffman(lengths: (0..<288).map { $0 < 144 ? 8 : $0 < 256 ? 9 : $0 < 280 ? 7 : 8 })!
        static let distances = Huffman(lengths: [Int](repeating: 5, count: 30))!
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
                                     115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
                                       1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
                                        12, 12, 13, 13]
    /// The order in which a dynamic block gives the code lengths of its code-length code.
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private struct State {
        let input: [UInt8]
        let limit: Int
        var output: [UInt8] = []
        /// The next whole byte to read.
        var position = 0
        var buffer = 0
        var buffered = 0

        init(input: [UInt8], limit: Int) {
            self.input = input
            self.limit = limit
            output.reserveCapacity(limit)
        }

        mutating func bits(_ needed: Int) throws -> Int {
            var value = buffer
            while buffered < needed {
                guard position < input.count else { throw Failure.truncated }
                value |= Int(input[position]) << buffered
                position += 1
                buffered += 8
            }
            buffer = value >> needed
            buffered -= needed
            return value & ((1 << needed) - 1)
        }

        mutating func emit(_ byte: UInt8) throws {
            guard output.count < limit else { throw Failure.wrongSize }
            output.append(byte)
        }

        mutating func stored() throws {
            buffer = 0
            buffered = 0
            guard position + 4 <= input.count else { throw Failure.truncated }
            let length = Int(input[position]) | Int(input[position + 1]) << 8
            let check = Int(input[position + 2]) | Int(input[position + 3]) << 8
            guard length == ~check & 0xffff else { throw Failure.malformed }
            position += 4
            guard position + length <= input.count else { throw Failure.truncated }
            guard output.count + length <= limit else { throw Failure.wrongSize }
            output.append(contentsOf: input[position..<(position + length)])
            position += length
        }

        mutating func decode(_ code: Huffman) throws -> Int {
            var value = 0, first = 0, index = 0
            for length in 1..<16 {
                value |= try bits(1)
                let count = code.count[length]
                if value - count < first { return code.symbol[index + (value - first)] }
                index += count
                first += count
                first <<= 1
                value <<= 1
            }
            throw Failure.malformed
        }

        mutating func codes(_ literals: Huffman, _ distances: Huffman) throws {
            while true {
                let symbol = try decode(literals)
                if symbol < 256 {
                    try emit(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    let index = symbol - 257
                    guard index < Inflate.lengthBase.count else { throw Failure.malformed }
                    let length = Inflate.lengthBase[index] + (try bits(Inflate.lengthExtra[index]))
                    let place = try decode(distances)
                    guard place < Inflate.distanceBase.count else { throw Failure.malformed }
                    let distance = Inflate.distanceBase[place] + (try bits(Inflate.distanceExtra[place]))
                    guard distance <= output.count else { throw Failure.malformed }
                    guard output.count + length <= limit else { throw Failure.wrongSize }
                    for _ in 0..<length { output.append(output[output.count - distance]) }
                }
            }
        }

        mutating func dynamic() throws {
            let literalCount = try bits(5) + 257, distanceCount = try bits(5) + 1, lengthCount = try bits(4) + 4
            guard literalCount <= 286, distanceCount <= 30 else { throw Failure.malformed }
            var lengths = [Int](repeating: 0, count: 19)
            for index in 0..<lengthCount { lengths[Inflate.codeLengthOrder[index]] = try bits(3) }
            guard let lengthCode = Huffman(lengths: lengths) else { throw Failure.malformed }
            var all: [Int] = []
            while all.count < literalCount + distanceCount {
                let symbol = try decode(lengthCode)
                switch symbol {
                case 0..<16: all.append(symbol)
                case 16:
                    guard let previous = all.last else { throw Failure.malformed }
                    all += [Int](repeating: previous, count: 3 + (try bits(2)))
                case 17: all += [Int](repeating: 0, count: 3 + (try bits(3)))
                default: all += [Int](repeating: 0, count: 11 + (try bits(7)))
                }
            }
            guard all.count == literalCount + distanceCount, all[256] != 0 else { throw Failure.malformed }
            guard let literals = Huffman(lengths: Array(all[0..<literalCount])),
                  let distances = Huffman(lengths: Array(all[literalCount...])) else { throw Failure.malformed }
            try codes(literals, distances)
        }
    }
}

/// CRC-32 (the one of ZIP and PNG), in plain Swift.
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        (0..<8).reduce(UInt32(value)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    public static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
    }
}
