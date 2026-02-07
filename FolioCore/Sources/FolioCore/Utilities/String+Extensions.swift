// String+Extensions.swift
// String utility extensions for search, validation, and formatting

import Foundation

public extension String {
    /// Generate trigrams for fuzzy search indexing
    func trigrams() -> Set<String> {
        let normalized = self.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3 else {
            return [normalized]
        }

        var result = Set<String>()
        let chars = Array(normalized)

        for i in 0..<(chars.count - 2) {
            let trigram = String(chars[i..<(i + 3)])
            result.insert(trigram)
        }

        return result
    }

    /// Escape XML special characters
    var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Escape HTML special characters
    var htmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Generate sort-friendly version (remove articles, normalize)
    var sortableTitle: String {
        let articles = ["the ", "a ", "an "]
        var result = self.lowercased()

        for article in articles {
            if result.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Check if string is a valid ISBN-10
    var isValidISBN10: Bool {
        let digits = self.filter { $0.isNumber || $0 == "X" }
        guard digits.count == 10 else { return false }

        var sum = 0
        for (index, char) in digits.enumerated() {
            let value: Int
            if char == "X" {
                value = 10
            } else {
                value = Int(String(char)) ?? 0
            }
            sum += value * (10 - index)
        }

        return sum % 11 == 0
    }

    /// Check if string is a valid ISBN-13
    var isValidISBN13: Bool {
        let digits = self.filter { $0.isNumber }
        guard digits.count == 13 else { return false }

        var sum = 0
        for (index, char) in digits.enumerated() {
            let value = Int(String(char)) ?? 0
            sum += value * (index % 2 == 0 ? 1 : 3)
        }

        return sum % 10 == 0
    }

    /// Normalize ISBN (remove hyphens, spaces)
    var normalizedISBN: String {
        return self.filter { $0.isNumber || $0 == "X" }.uppercased()
    }
}
