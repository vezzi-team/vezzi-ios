import Foundation

extension String {
    /// Capitalize only the first letter, preserving street names, abbreviations and house suffixes.
    nonisolated var addressCapitalized: String {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = text.firstIndex(where: { $0.isLetter || $0.isNumber }), text[index].isLetter else { return text }
        return text[..<index] + text[index].uppercased() + text[text.index(after: index)...]
    }
}
