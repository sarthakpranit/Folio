//
//  FilenameParser.swift
//  Folio
//
//  Utility for parsing ebook filenames to extract title and author.
//  Uses pattern matching to handle common filename conventions.
//
//  Supported Patterns:
//  - "Title - Author.epub" (most common)
//  - "Author - Title.epub" (detected by name heuristics)
//  - "Title (Author).epub" or "Title [Author].epub"
//  - "Title by Author.epub"
//
//  Design:
//  - Pure utility with no side effects
//  - Uses regex for pattern matching
//  - Includes author name detection heuristics
//
//  Usage:
//    let parser = FilenameParser()
//    let result = parser.parse("The Hobbit - J.R.R. Tolkien.epub")
//    // result.title == "The Hobbit"
//    // result.author == "J.R.R. Tolkien"
//

import Foundation

/// Utility for parsing ebook filenames
struct FilenameParser {

    /// Result of parsing a filename
    struct ParsedFilename {
        let title: String
        let author: String?
    }

    // MARK: - Parsing

    /// Extract title and author from a filename
    func parse(_ filename: String) -> ParsedFilename {
        var name = filename

        // Remove extension
        if let dotIndex = name.lastIndex(of: ".") {
            name = String(name[..<dotIndex])
        }

        // Replace underscores with spaces
        name = name.replacingOccurrences(of: "_", with: " ")

        // Try different patterns

        // Pattern 1: "Title (Author)" or "Title [Author]"
        if let parenMatch = name.range(of: #"\s*[\(\[]([^\)\]]+)[\)\]]\s*$"#, options: .regularExpression) {
            let authorPart = String(name[parenMatch])
                .trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
            let titlePart = String(name[..<parenMatch.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !authorPart.isEmpty && !titlePart.isEmpty {
                return ParsedFilename(title: titlePart, author: authorPart)
            }
        }

        // Pattern 2: "Title by Author"
        if let byRange = name.range(of: " by ", options: .caseInsensitive) {
            let titlePart = String(name[..<byRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let authorPart = String(name[byRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !authorPart.isEmpty && !titlePart.isEmpty && looksLikeAuthorName(authorPart) {
                return ParsedFilename(title: titlePart, author: authorPart)
            }
        }

        // Pattern 3: "Title - Author" (most common)
        let dashSeparators = [" - ", " – ", " — "]  // Regular dash, en-dash, em-dash
        for separator in dashSeparators {
            if let dashRange = name.range(of: separator) {
                let firstPart = String(name[..<dashRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let secondPart = String(name[dashRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !firstPart.isEmpty && !secondPart.isEmpty {
                    if looksLikeAuthorName(secondPart) && !looksLikeAuthorName(firstPart) {
                        return ParsedFilename(title: firstPart, author: secondPart)
                    } else if looksLikeAuthorName(firstPart) && !looksLikeAuthorName(secondPart) {
                        return ParsedFilename(title: secondPart, author: firstPart)
                    } else if looksLikeAuthorName(secondPart) {
                        return ParsedFilename(title: firstPart, author: secondPart)
                    }
                }
            }
        }

        // No pattern matched - clean up and return as title only
        let cleanedTitle = name
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedFilename(title: cleanedTitle, author: nil)
    }

    // MARK: - Whitespace Normalization

    /// Normalize whitespace in a string (collapse multiple spaces to single, trim edges)
    func normalizeWhitespace(_ text: String) -> String {
        return text
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Author Detection

    /// Check if a string looks like an author name
    /// Uses heuristics: 2-5 words, capitalized, possibly with initials
    func looksLikeAuthorName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Author names are typically 1-6 words
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 1 && words.count <= 6 else { return false }

        // Check if words look like name parts (capitalized, possibly with periods)
        // Uses Unicode property escapes for international names (José, García)
        let namePattern = #"^\p{Lu}[\p{L}]*\.?$"#
        let regex = try? NSRegularExpression(pattern: namePattern)

        var nameWordCount = 0
        for word in words {
            let range = NSRange(word.startIndex..., in: word)
            if regex?.firstMatch(in: word, range: range) != nil {
                nameWordCount += 1
            }
        }

        // Most words should look like names
        return Double(nameWordCount) / Double(words.count) >= 0.5
    }
}
