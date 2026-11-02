import Foundation

/// SQLite's numeric representation is not a lossless Decimal encoding.
nonisolated enum ExactDecimal {
    static func encode(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func decode(_ text: String?, legacy: NSDecimalNumber?, entity: String, id: String) throws -> Decimal? {
        // Version 1 has no text field. Previously lost digits cannot be reconstructed.
        guard let text else { return legacy?.decimalValue }
        guard let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, encode(value) == text else {
            throw CatalogError.invalidRecord(entity: entity, id: id)
        }
        return value
    }
}
