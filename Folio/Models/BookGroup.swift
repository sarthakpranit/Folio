//
//  BookGroup.swift
//  Folio
//
//  Groups multiple format variants of the same book for unified display
//

import Foundation
import CoreData

/// Represents a logical book that may have multiple format variants (e.g., EPUB + MOBI)
struct BookGroup: Identifiable {
    /// Unique identifier (ISBN or normalized title)
    let id: String

    /// All format variants of this book
    let books: [Book]

    /// The book with the best metadata (cover, summary, etc.)
    var primaryBook: Book {
        // Prefer book with cover image, then most metadata
        books.max { book1, book2 in
            metadataScore(book1) < metadataScore(book2)
        } ?? books[0]
    }

    /// All available formats, sorted alphabetically
    var formats: [String] {
        books.compactMap { $0.format?.lowercased() }
            .unique()
            .sorted()
    }

    /// Combined file size of all formats
    var totalSize: Int64 {
        books.reduce(0) { $0 + $1.fileSize }
    }

    /// Best format for Kindle transfer via Send to Kindle
    /// Amazon discontinued MOBI support in 2022. EPUB is now preferred (Amazon converts to AZW).
    var preferredForKindle: Book? {
        let kindlePriority = ["epub", "azw3", "pdf", "txt"]
        for format in kindlePriority {
            if let book = books.first(where: { $0.format?.lowercased() == format }) {
                return book
            }
        }
        return books.first
    }

    /// Best format for reading (EPUB > PDF > MOBI > AZW3)
    var preferredForReading: Book? {
        let readingPriority = ["epub", "pdf", "mobi", "azw3"]
        for format in readingPriority {
            if let book = books.first(where: { $0.format?.lowercased() == format }) {
                return book
            }
        }
        return books.first
    }

    /// Get book for a specific format
    func book(for format: String) -> Book? {
        books.first { $0.format?.lowercased() == format.lowercased() }
    }

    /// Check if group has multiple formats
    var hasMultipleFormats: Bool {
        formats.count > 1
    }

    // MARK: - Sortable Properties (for Table column sorting)

    /// Sortable title string for table column sorting
    var sortableTitle: String {
        primaryBook.sortTitle ?? primaryBook.title ?? ""
    }

    /// Sortable author string (first author's sortName)
    var sortableAuthor: String {
        (primaryBook.authors as? Set<Author>)?.compactMap { $0.sortName }.sorted().first ?? ""
    }

    /// Sortable date added (epoch for comparison)
    var sortableDateAdded: Date {
        primaryBook.dateAdded ?? Date.distantPast
    }

    /// Sortable file size
    var sortableSize: Int64 {
        totalSize
    }

    // MARK: - Private Helpers

    /// Calculate metadata completeness score for a book
    private func metadataScore(_ book: Book) -> Int {
        var score = 0
        if book.coverImageData != nil { score += 10 }
        if book.summary != nil && !book.summary!.isEmpty { score += 5 }
        if book.isbn13 != nil || book.isbn != nil { score += 3 }
        if book.publisher != nil { score += 2 }
        if book.pageCount > 0 { score += 1 }
        if let authors = book.authors as? Set<Author>, !authors.isEmpty { score += 2 }
        return score
    }
}

// MARK: - Book Grouping Service

/// Service for grouping books by content (ISBN or title)
enum BookGroupingService {

    /// Group an array of books by their content identity
    /// - Parameter books: Array of Book entities, pre-sorted by the caller
    /// - Returns: Array of BookGroup, preserving the input sort order
    ///           (groups appear in the order their first book appears in the input)
    static func groupBooks(_ books: [Book]) -> [BookGroup] {
        // Group by computed key, preserving first-seen order
        var groups: [String: [Book]] = [:]
        var orderedKeys: [String] = []

        for book in books {
            let key = groupKey(for: book)
            if groups[key] == nil {
                orderedKeys.append(key)
            }
            groups[key, default: []].append(book)
        }

        // Convert to BookGroup array in the order groups were first encountered
        return orderedKeys.compactMap { key in
            guard let groupedBooks = groups[key] else { return nil }
            return BookGroup(id: key, books: groupedBooks)
        }
    }

    /// Compute the grouping key for a book
    /// Priority: ISBN-13 > ISBN-10 > Normalized Title
    static func groupKey(for book: Book) -> String {
        // Prefer ISBN for accurate matching
        if let isbn13 = book.isbn13, !isbn13.isEmpty {
            return "isbn:\(isbn13)"
        }

        if let isbn = book.isbn, !isbn.isEmpty {
            return "isbn:\(isbn)"
        }

        // Fall back to normalized title
        return "title:\(normalizeTitle(book.title ?? "untitled"))"
    }

    /// Normalize a title for comparison
    /// - Lowercase
    /// - Remove leading articles (the, a, an)
    /// - Remove non-alphanumeric characters
    /// - Trim whitespace
    static func normalizeTitle(_ title: String) -> String {
        var normalized = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading articles
        let articles = ["the ", "a ", "an "]
        for article in articles {
            if normalized.hasPrefix(article) {
                normalized = String(normalized.dropFirst(article.count))
                break
            }
        }

        // Keep only alphanumeric and spaces, then collapse multiple spaces
        normalized = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return normalized
    }
}

// MARK: - Array Extension

extension Array where Element: Hashable {
    /// Returns array with duplicate elements removed, preserving order
    func unique() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
