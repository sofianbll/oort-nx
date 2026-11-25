// From NX2Apple frontend-ios/Sources/ShellHost/SideloadCertificateStore.swift at a79d397 (MIT, Copyright (c) 2026 seedds, jhaizhou, LNPANDY and NX2Apple contributors). Changes: mobile/PROVENANCE.md.
import CryptoKit
import Foundation
import Security
import ShellModel
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

// MARK: - Minimal ASN.1 DER reader & writer (RFC 5280 / X.690 / RFC 5652)

enum ASN1DER {
    struct Element {
        let tag: UInt8
        let fullRange: Range<Int>
        let valueRange: Range<Int>

        func fullData(in bytes: Data) -> Data {
            bytes.subdata(in: fullRange)
        }

        func valueData(in bytes: Data) -> Data {
            bytes.subdata(in: valueRange)
        }
    }

    static func readElement(in data: Data, at offset: Int) -> Element? {
        let start = data.startIndex
        let end = data.endIndex
        guard offset >= start, offset < end else { return nil }
        let tag = data[offset]
        let lenStart = offset + 1
        guard lenStart < end else { return nil }
        let firstLen = data[lenStart]
        let length: Int
        let valueStart: Int
        if firstLen < 0x80 {
            length = Int(firstLen)
            valueStart = lenStart + 1
        } else {
            let count = Int(firstLen & 0x7f)
            // Reject indefinite length (0x80) and > 4 byte lengths to guard against crafted inputs.
            guard count >= 1, count <= 4, lenStart + count < end else { return nil }
            var accum: UInt64 = 0
            for i in 1...count {
                accum = (accum << 8) | UInt64(data[lenStart + i])
            }
            guard accum <= UInt64(Int.max) else { return nil }
            length = Int(accum)
            valueStart = lenStart + 1 + count
        }
        guard length >= 0, valueStart <= end, length <= end - valueStart else { return nil }
        let valueEnd = valueStart + length
        return Element(tag: tag, fullRange: offset..<valueEnd, valueRange: valueStart..<valueEnd)
    }

    static func children(of element: Element, in data: Data) -> [Element]? {
        var result: [Element] = []
        var cursor = element.valueRange.lowerBound
        while cursor < element.valueRange.upperBound {
            guard let child = readElement(in: data, at: cursor),
                  child.fullRange.upperBound <= element.valueRange.upperBound else {
                return nil
            }
            result.append(child)
            cursor = child.fullRange.upperBound
        }
        return result
    }

    static func encodeLength(_ length: Int) -> Data {
        precondition(length >= 0)
        if length < 0x80 {
            return Data([UInt8(length)])
        }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.append(UInt8(remaining & 0xff))
            remaining >>= 8
        }
        bytes.reverse()
        var out = Data([0x80 | UInt8(bytes.count)])
        out.append(contentsOf: bytes)
        return out
    }

    static func tlv(tag: UInt8, content: Data) -> Data {
        var out = Data([tag])
        out.append(encodeLength(content.count))
        out.append(content)
        return out
    }

    static func sequence(_ items: [Data]) -> Data {
        var body = Data()
        for item in items { body.append(item) }
        return tlv(tag: 0x30, content: body)
    }

    static func set(_ items: [Data], sortByDER: Bool = true) -> Data {
        let ordered = sortByDER ? items.sorted { $0.lexicographicallyPrecedes($1) } : items
        var body = Data()
        for item in ordered { body.append(item) }
        return tlv(tag: 0x31, content: body)
    }

    static func integer(_ value: UInt64) -> Data {
        var bytes: [UInt8] = []
        var v = value
        repeat {
            bytes.append(UInt8(v & 0xff))
            v >>= 8
        } while v > 0
        bytes.reverse()
        if let first = bytes.first, (first & 0x80) != 0 {
            bytes.insert(0x00, at: 0)
        }
        return tlv(tag: 0x02, content: Data(bytes))
    }

    static func octetString(_ data: Data) -> Data {
        tlv(tag: 0x04, content: data)
    }

    static func null() -> Data {
        Data([0x05, 0x00])
    }

    static func oid(_ arcs: [UInt32]) -> Data {
        precondition(arcs.count >= 2 && arcs[0] <= 2 && arcs[1] < 40)
        var body = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            if arc == 0 {
                body.append(0)
                continue
            }
            var chunks: [UInt8] = []
            var v = arc
            while v > 0 {
                chunks.append(UInt8(v & 0x7f))
                v >>= 7
            }
            chunks.reverse()
            for i in 0..<(chunks.count - 1) {
                chunks[i] |= 0x80
            }
            body.append(contentsOf: chunks)
        }
        return tlv(tag: 0x06, content: body)
    }

    static func utcTime(_ date: Date) -> Data {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0)!
        let comps = calendar.dateComponents(in: utc, from: date)
        let year = comps.year ?? 2026
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0
        if year >= 1950 && year <= 2049 {
            let text = String(format: "%02d%02d%02d%02d%02d%02dZ", year % 100, month, day, hour, minute, second)
            return tlv(tag: 0x17, content: Data(text.utf8))
        }
        let text = String(format: "%04d%02d%02d%02d%02d%02dZ", year, month, day, hour, minute, second)
        return tlv(tag: 0x18, content: Data(text.utf8))
    }

    static func contextExplicit(_ tagNumber: UInt8, content: Data) -> Data {
        tlv(tag: 0xA0 | (tagNumber & 0x1f), content: content)
    }

    static func contextImplicitConstructed(_ tagNumber: UInt8, items: [Data]) -> Data {
        var body = Data()
        for item in items { body.append(item) }
        return tlv(tag: 0xA0 | (tagNumber & 0x1f), content: body)
    }
}

// MARK: - X.509 Certificate Metadata Parser

struct X509CertificateInfo: Equatable, Sendable {
    var commonName: String
    var teamID: String
    var notBefore: Date?
    var notAfter: Date?
    var issuerRawTLV: Data
    var subjectRawTLV: Data
    var serialNumberRawTLV: Data
    var fingerprintHex: String
}

enum X509CertificateParser {
    private static let oidCommonName = Data([0x55, 0x04, 0x03]) // 2.5.4.3
    private static let oidOrgUnit = Data([0x55, 0x04, 0x0b])    // 2.5.4.11

    static func parse(der: Data) -> X509CertificateInfo? {
        guard let root = ASN1DER.readElement(in: der, at: der.startIndex),
              root.tag == 0x30,
              let certChildren = ASN1DER.children(of: root, in: der),
              certChildren.count >= 3 else {
            return nil
        }
        let tbs = certChildren[0]
        guard tbs.tag == 0x30,
              let tbsFields = ASN1DER.children(of: tbs, in: der) else {
            return nil
        }
        var idx = 0
        if idx < tbsFields.count && tbsFields[idx].tag == 0xA0 {
            idx += 1 // optional [0] EXPLICIT version
        }
        // TBSCertificate order: serialNumber, signature, issuer, validity, subject
        guard tbsFields.count >= idx + 5 else { return nil }
        let serialEl = tbsFields[idx]
        let issuerEl = tbsFields[idx + 2]
        let validityEl = tbsFields[idx + 3]
        let subjectEl = tbsFields[idx + 4]

        guard serialEl.tag == 0x02,
              issuerEl.tag == 0x30,
              validityEl.tag == 0x30,
              subjectEl.tag == 0x30 else {
            return nil
        }

        let (notBefore, notAfter) = parseValidity(validityEl, in: der)
        let (commonName, teamID) = parseSubject(subjectEl, in: der)
        let digest = SHA256.hash(data: der)
        let fingerprintHex = digest.map { String(format: "%02x", $0) }.joined()

        return X509CertificateInfo(
            commonName: commonName,
            teamID: teamID,
            notBefore: notBefore,
            notAfter: notAfter,
            issuerRawTLV: issuerEl.fullData(in: der),
            subjectRawTLV: subjectEl.fullData(in: der),
            serialNumberRawTLV: serialEl.fullData(in: der),
            fingerprintHex: fingerprintHex
        )
    }

    private static func parseValidity(_ validity: ASN1DER.Element, in data: Data) -> (Date?, Date?) {
        guard let fields = ASN1DER.children(of: validity, in: data), fields.count >= 2 else {
            return (nil, nil)
        }
        return (parseTime(fields[0], in: data), parseTime(fields[1], in: data))
    }

    private static func parseTime(_ el: ASN1DER.Element, in data: Data) -> Date? {
        guard el.tag == 0x17 || el.tag == 0x18,
              let raw = String(data: el.valueData(in: data), encoding: .ascii),
              raw.hasSuffix("Z") else {
            return nil
        }
        let digits = String(raw.dropLast())
        let year: Int
        let restStart: String.Index
        if el.tag == 0x17 {
            guard digits.count == 12, let yy = Int(digits.prefix(2)) else { return nil }
            year = yy >= 50 ? 1900 + yy : 2000 + yy
            restStart = digits.index(digits.startIndex, offsetBy: 2)
        } else {
            guard digits.count == 14, let yyyy = Int(digits.prefix(4)) else { return nil }
            year = yyyy
            restStart = digits.index(digits.startIndex, offsetBy: 4)
        }
        let tail = String(digits[restStart...])
        guard tail.count == 10,
              let month = Int(tail.prefix(2)),
              let day = Int(tail.dropFirst(2).prefix(2)),
              let hour = Int(tail.dropFirst(4).prefix(2)),
              let minute = Int(tail.dropFirst(6).prefix(2)),
              let second = Int(tail.dropFirst(8).prefix(2)) else {
            return nil
        }
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return comps.date
    }

    private static func parseSubject(_ subject: ASN1DER.Element, in data: Data) -> (commonName: String, teamID: String) {
        guard let rdns = ASN1DER.children(of: subject, in: data) else { return ("", "") }
        var commonName = ""
        var orgUnits: [String] = []
        for rdn in rdns where rdn.tag == 0x31 {
            guard let atvs = ASN1DER.children(of: rdn, in: data) else { continue }
            for atv in atvs where atv.tag == 0x30 {
                guard let pair = ASN1DER.children(of: atv, in: data), pair.count >= 2,
                      pair[0].tag == 0x06 else { continue }
                let oidBytes = pair[0].valueData(in: data)
                guard let text = decodeDirectoryString(pair[1], in: data), !text.isEmpty else { continue }
                if oidBytes == oidCommonName, commonName.isEmpty {
                    commonName = text
                } else if oidBytes == oidOrgUnit {
                    orgUnits.append(text)
                }
            }
        }
        let preferredTeam = orgUnits.first { isAppleTeamID($0) } ?? orgUnits.first ?? ""
        return (commonName, preferredTeam)
    }

    private static func isAppleTeamID(_ text: String) -> Bool {
        guard text.count == 10 else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57) || (scalar.value >= 65 && scalar.value <= 90)
        }
    }

    private static func decodeDirectoryString(_ el: ASN1DER.Element, in data: Data) -> String? {
        let bytes = el.valueData(in: data)
        switch el.tag {
        case 0x0c, 0x13, 0x16, 0x14:
            return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
        case 0x1e:
            return String(data: bytes, encoding: .utf16BigEndian)
        default:
            return String(data: bytes, encoding: .utf8)
        }
    }
}

// MARK: - Keychain / Testable Storage Backing

