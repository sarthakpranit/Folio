//
//  SearchService.swift
//  Folio
//
//  Handles search and filter operations for the book library.
//  Provides in-memory filtering with optimized algorithms.
//
//  Key Responsibilities:
//  - Full-text search across books (title, author, ISBN, series)
//  - Multi-criteria filtering (author, series, tags, format)
//  - Statistics calculation for library analytics
//  - Title cleanup with author extraction
//
//  Design:
//  - Pure functions for filtering (no state mutation)
//  - Operates on arrays passed in, doesn't manage data
//  - Coordinator pattern: receives data, returns filtered results
//
//  Usage:
//    let searchService = SearchService()
//    let results = searchService.search(books: allBooks, query: "tolkien")
//    let filtered = searchService.filter(books: allBooks, byFormat: "epub")
//

import Foundation

/// Service for search and filter operations
struct SearchService {

    // MARK: - Search

    /// Search books by query string
    /// Matches against title, author names, ISBN, and series name
    func search(books: [Book], query: String) -> [Book] {
        guard !query.isEmpty else { return books }

        let lowercasedQuery = query.lowercased()

        return books.filter { book in
            // Title match
            if book.title?.lowercased().contains(lowercasedQuery) == true {
                return true
            }

            // Author match
            if let bookAuthors = book.authors as? Set<Author> {
                for author in bookAuthors {
                    if author.name?.lowercased().contains(lowercasedQuery) == true {
                        return true
                    }
                }
            }

            // ISBN match
            if book.isbn?.contains(query) == true || book.isbn13?.contains(query) == true {
                return true
            }

            // Series match
            if book.series?.name?.lowercased().contains(lowercasedQuery) == true {
                return true
            }

            return false
        }
    }

    // MARK: - Filter

    /// Filter books by various criteria
    func filter(
        books: [Book],
        byAuthors filterAuthors: [Author]? = nil,
        bySeries filterSeries: Series? = nil,
        byTags filterTags: [Tag]? = nil,
        byFormat format: String? = nil
    ) -> [Book] {
        var result = books

        if let filterAuthors = filterAuthors, !filterAuthors.isEmpty {
            result = result.filter { book in
                guard let bookAuthors = book.authors as? Set<Author> else { return false }
                return !bookAuthors.isDisjoint(with: Set(filterAuthors))
            }
        }

        if let filterSeries = filterSeries {
            result = result.filter { $0.series == filterSeries }
        }

        if let filterTags = filterTags, !filterTags.isEmpty {
            result = result.filter { book in
                guard let bookTags = book.tags as? Set<Tag> else { return false }
                return !bookTags.isDisjoint(with: Set(filterTags))
            }
        }

        if let format = format {
            result = result.filter { $0.format == format }
        }

        return result
    }

    // MARK: - Statistics

    /// Calculate library statistics
    func calculateStatistics(
        books: [Book],
        authors: [Author],
        series: [Series],
        tags: [Tag]
    ) -> LibraryStatistics {
        let totalBooks = books.count
        let totalSize = books.reduce(0) { $0 + $1.fileSize }

        var formatCounts: [String: Int] = [:]
        for book in books {
            if let format = book.format {
                formatCounts[format, default: 0] += 1
            }
        }

        return LibraryStatistics(
            totalBooks: totalBooks,
            totalSizeBytes: totalSize,
            formatCounts: formatCounts,
            authorCount: authors.count,
            seriesCount: series.count,
            tagCount: tags.count
        )
    }

    // MARK: - Title Cleanup

    /// Result of cleaning book titles
    struct CleanupResult {
        let booksProcessed: Int
        let titlesFixed: Int
        let authorsExtracted: Int
    }

    /// Clean up book titles by extracting embedded author names
    /// - Parameters:
    ///   - books: Books to clean
    ///   - parser: FilenameParser for extracting author names
    ///   - findOrCreateAuthor: Closure to find or create author entity
    ///   - generateSortTitle: Closure to generate sort title
    /// - Returns: Cleanup result with counts
    func cleanupBookTitles(
        books: [Book],
        parser: FilenameParser,
        findOrCreateAuthor: (String) -> Author,
        generateSortTitle: (String) -> String
    ) -> CleanupResult {
        var titlesFixed = 0
        var authorsExtracted = 0

        for book in books {
            guard let currentTitle = book.title else { continue }

            // Step 0: Normalize whitespace
            var newTitle = parser.normalizeWhitespace(currentTitle)
            var didFix = newTitle != currentTitle

            // Step 1: Remove existing author names from title
            if let existingAuthors = book.authors as? Set<Author>, !existingAuthors.isEmpty {
                for author in existingAuthors {
                    guard let authorName = author.name, !authorName.isEmpty else { continue }

                    let normalizedTitle = parser.normalizeWhitespace(newTitle).lowercased()
                    let normalizedAuthor = parser.normalizeWhitespace(authorName).lowercased()

                    if normalizedTitle.hasSuffix(normalizedAuthor) {
                        let titleWithoutAuthor = String(newTitle.dropLast(authorName.count))
                        newTitle = parser.normalizeWhitespace(titleWithoutAuthor)
                        didFix = true
                    } else if normalizedTitle.hasPrefix(normalizedAuthor) {
                        let titleWithoutAuthor = String(newTitle.dropFirst(authorName.count))
                        newTitle = parser.normalizeWhitespace(titleWithoutAuthor)
                        didFix = true
                    }
                }
            }

            // Step 2: Parse for separator-based patterns
            let parsed = parser.parse(newTitle + ".epub")

            if let extractedAuthor = parsed.author,
               !extractedAuthor.isEmpty,
               parsed.title != newTitle {

                let existingAuthors = (book.authors as? Set<Author>) ?? []
                let hasAuthor = existingAuthors.contains { author in
                    author.name?.lowercased() == extractedAuthor.lowercased()
                }

                newTitle = parser.normalizeWhitespace(parsed.title)
                didFix = true

                if !hasAuthor {
                    let author = findOrCreateAuthor(extractedAuthor)
                    book.addToAuthors(author)
                    authorsExtracted += 1
                }
            }

            // Step 3: Apply changes
            newTitle = parser.normalizeWhitespace(newTitle)

            if didFix && newTitle != currentTitle {
                book.title = newTitle
                book.sortTitle = generateSortTitle(newTitle)
                titlesFixed += 1
            }
        }

        return CleanupResult(
            booksProcessed: books.count,
            titlesFixed: titlesFixed,
            authorsExtracted: authorsExtracted
        )
    }
}
