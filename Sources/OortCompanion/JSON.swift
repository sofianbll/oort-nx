import Foundation
@preconcurrency import NXLibraryCore

/// Replies read like what they send.
extension CatalogJSON: ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByStringLiteral,
                       ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral, ExpressibleByNilLiteral {
    public init(dictionaryLiteral elements: (String, CatalogJSON)...) { self = .object(Dictionary(elements) { $1 }) }
    public init(arrayLiteral elements: CatalogJSON...) { self = .array(elements) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Decimal(value)) }
    public init(nilLiteral: ()) { self = .null }

    static func text(_ value: String?) -> CatalogJSON { value.map(CatalogJSON.string) ?? .null }
    static func number(_ value: Double) -> CatalogJSON {
        // Through text: a Double read as Decimal carries its binary tail.
        .number(Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? 0)
    }
    static func number(_ value: Int) -> CatalogJSON { .number(Decimal(value)) }
    static func list(_ values: [String]) -> CatalogJSON { .array(values.map(CatalogJSON.string)) }

    var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
}
