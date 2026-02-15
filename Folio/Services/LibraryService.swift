//
//  LibraryService.swift
//  Folio
//
//  Main service for managing the ebook library
//

import Foundation
import CoreData
import Combine
import UniformTypeIdentifiers
import FolioCore

/// Main service for managing the ebook library
@MainActor
class LibraryService: ObservableObject {
    static let shared = LibraryService()

    private let persistenceController: PersistenceController
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var books: [Book] = []
    @Published private(set) var authors: [Author] = []
    @Published private(set) var series: [Series] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // Import progress tracking
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importTotal: Int = 0
    @Published private(set) var importCurrent: Int = 0
    @Published private(set) var importCurrentBookName: String = ""

    /// Supported import formats
    let supportedExtensions = ["epub", "mobi", "azw3", "pdf", "cbz", "cbr", "fb2", "txt", "rtf"]

    private init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        loadBooks()
        loadAuthors()
        loadSeries()
        loadTags()
    }

    // MARK: - Loading

    private var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    func loadBooks() {
        let request = Book.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Book.dateAdded, ascending: false)]

        do {
            books = try viewContext.fetch(request)
        } catch {
            self.error = error
            print("Failed to load books: \(error.localizedDescription)")
        }
    }

    func loadAuthors() {
        let request = Author.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Author.sortName, ascending: true)]

        do {
            authors = try viewContext.fetch(request)
        } catch {
            print("Failed to load authors: \(error.localizedDescription)")
        }
    }

    func loadSeries() {
        let request = Series.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Series.name, ascending: true)]

        do {
            series = try viewContext.fetch(request)
        } catch {
            print("Failed to load series: \(error.localizedDescription)")
        }
    }

    func loadTags() {
        let request = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]

        do {
            tags = try viewContext.fetch(request)
        } catch {
            print("Failed to load tags: \(error.localizedDescription)")
        }
    }

    /// Refresh all data from database
    func refresh() {
        loadBooks()
        loadAuthors()
        loadSeries()
        loadTags()
        objectWillChange.send()
        print("[LibraryService] Refreshed - Authors: \(authors.count), Series: \(series.count), Tags: \(tags.count)")
    }

    // MARK: - Add Book

    /// Add a single book to the library
    /// - Parameters:
    ///   - fileURL: URL of the ebook file
    ///   - shouldCopy: Whether to copy the file to the library folder
    /// - Returns: The created Book entity
    @discardableResult
    func addBook(from fileURL: URL, shouldCopy: Bool = false) throws -> Book {
        // Start accessing security-scoped resource for files from Finder
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard isValidEbookFile(fileURL) else {
            throw LibraryError.invalidFormat(fileURL.pathExtension)
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LibraryError.fileNotFound(fileURL)
        }

        let book = Book(context: viewContext)
        book.id = UUID()
        book.fileURL = fileURL
        book.format = fileURL.pathExtension.lowercased()
        book.fileSize = getFileSize(fileURL)
        book.dateAdded = Date()
        book.dateModified = Date()

        // Create and store a security-scoped bookmark for persistent file access
        do {
            let bookmarkData = try fileURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            book.bookmarkData = bookmarkData
            print("Created security-scoped bookmark for: \(fileURL.lastPathComponent)")
        } catch {
            print("Failed to create bookmark for \(fileURL.lastPathComponent): \(error)")
            // Continue without bookmark - file may still work if accessed in same session
        }

        // Extract title and author from filename
        let parsed = parseFilename(fileURL.lastPathComponent)
        book.title = parsed.title
        book.sortTitle = generateSortTitle(parsed.title)

        // Set author if extracted from filename
        if let authorName = parsed.author, !authorName.isEmpty {
            let author = findOrCreateAuthor(name: authorName)
            book.addToAuthors(author)
            print("Extracted author from filename: \(authorName)")
        }

        try viewContext.save()

        // Refresh the context to ensure @FetchRequest sees the changes
        viewContext.refreshAllObjects()

        loadBooks()
        objectWillChange.send()

        print("Added book: \(book.title ?? "Unknown")")
        return book
    }

    /// Import multiple books from URLs (e.g., from drag and drop)
    func importBooks(from urls: [URL]) async -> ImportResult {
        isLoading = true
        isImporting = true
        importProgress = 0
        importCurrent = 0
        importCurrentBookName = "Scanning files..."

        defer {
            isLoading = false
            isImporting = false
            importProgress = 1.0
            importCurrentBookName = ""
        }

        var imported = 0
        var failed = 0
        var errors: [String] = []

        // First, collect all files to import (for progress calculation)
        var filesToImport: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if url.hasDirectoryPath {
                // Collect files from directory
                if let files = collectEbookFiles(from: url) {
                    filesToImport.append(contentsOf: files)
                }
            } else if isValidEbookFile(url) {
                filesToImport.append(url)
            }
        }

        importTotal = filesToImport.count
        guard importTotal > 0 else {
            return ImportResult(imported: 0, failed: 0, errors: ["No valid ebook files found"])
        }

        // Now import each file with progress updates
        for (index, fileURL) in filesToImport.enumerated() {
            importCurrent = index + 1
            importCurrentBookName = fileURL.lastPathComponent
            importProgress = Double(index) / Double(importTotal)

            do {
                let accessing = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if accessing {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                try addBook(from: fileURL)
                imported += 1
            } catch {
                failed += 1
                errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            }

            // Small delay to allow UI updates
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        importProgress = 1.0
        return ImportResult(imported: imported, failed: failed, errors: errors)
    }

    /// Collect all ebook files from a directory (for progress calculation)
    private func collectEbookFiles(from directoryURL: URL) -> [URL]? {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return nil
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  isValidEbookFile(fileURL) else {
                continue
            }
            files.append(fileURL)
        }
        return files
    }

    /// Import all ebooks from a directory (recursively searches all subdirectories)
    private func importBooksFromDirectory(_ directoryURL: URL) async throws -> Int {
        let fileManager = FileManager.default

        // Use enumerator for recursive directory traversal
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            print("Failed to create directory enumerator for: \(directoryURL.path)")
            return 0
        }

        var importedCount = 0
        var totalFound = 0

        // Enumerate all files recursively
        for case let fileURL as URL in enumerator {
            // Check if it's a regular file (not a directory)
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            // Check if it's a valid ebook file
            guard isValidEbookFile(fileURL) else {
                continue
            }

            totalFound += 1

            do {
                try addBook(from: fileURL)
                importedCount += 1

                // Log progress for large imports
                if importedCount % 10 == 0 {
                    print("Imported \(importedCount) books so far...")
                }
            } catch {
                print("Failed to import \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        print("Recursive import complete: \(importedCount)/\(totalFound) books imported from \(directoryURL.lastPathComponent)")
        return importedCount
    }

    // MARK: - Delete Book

    /// Delete a book from the library
    func deleteBook(_ book: Book, deleteFile: Bool = false) throws {
        if deleteFile, let fileURL = book.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        viewContext.delete(book)
        try viewContext.save()
        loadBooks()

        print("Deleted book: \(book.title ?? "Unknown")")
    }

    /// Delete multiple books
    func deleteBooks(_ booksToDelete: [Book], deleteFiles: Bool = false) throws {
        for book in booksToDelete {
            if deleteFiles, let fileURL = book.fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            viewContext.delete(book)
        }

        try viewContext.save()
        loadBooks()
    }

    // MARK: - Title Cleanup

    /// Result of cleaning book titles
    struct CleanupResult {
        let booksProcessed: Int
        let titlesFixed: Int
        let authorsExtracted: Int
    }

    /// Clean up book titles by extracting embedded author names
    /// This fixes books where the title contains "Title - Author" format
    func cleanupBookTitles(books booksToClean: [Book]? = nil) -> CleanupResult {
        let targetBooks = booksToClean ?? self.books
        var titlesFixed = 0
        var authorsExtracted = 0

        for book in targetBooks {
            guard let currentTitle = book.title else { continue }

            // Check if this book might have an embedded author in the title
            let parsed = parseFilename(currentTitle + ".epub") // Add fake extension for parsing

            // Only update if we found an author AND the title changed significantly
            if let extractedAuthor = parsed.author,
               !extractedAuthor.isEmpty,
               parsed.title != currentTitle {

                // Check if book already has this author
                let existingAuthors = (book.authors as? Set<Author>) ?? []
                let hasAuthor = existingAuthors.contains { author in
                    author.name?.lowercased() == extractedAuthor.lowercased()
                }

                // Update title
                let oldTitle = book.title
                book.title = parsed.title
                book.sortTitle = generateSortTitle(parsed.title)
                titlesFixed += 1
                print("Fixed title: '\(oldTitle ?? "")' -> '\(parsed.title)'")

                // Add author if not already present
                if !hasAuthor {
                    let author = findOrCreateAuthor(name: extractedAuthor)
                    book.addToAuthors(author)
                    authorsExtracted += 1
                    print("Extracted author: '\(extractedAuthor)'")
                }
            }
        }

        // Save changes
        if titlesFixed > 0 {
            try? viewContext.save()
            loadBooks()
            loadAuthors()
            objectWillChange.send()
        }

        return CleanupResult(
            booksProcessed: targetBooks.count,
            titlesFixed: titlesFixed,
            authorsExtracted: authorsExtracted
        )
    }

    // MARK: - Search

    /// Search books by query
    func searchBooks(query: String) -> [Book] {
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
    func filterBooks(
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

    // MARK: - Update Book

    /// Update book metadata
    func updateBook(_ book: Book, title: String? = nil, authors: [String]? = nil, summary: String? = nil) throws {
        if let title = title {
            book.title = title
            book.sortTitle = generateSortTitle(title)
        }

        if let authorNames = authors {
            // Clear existing authors
            book.authors = nil

            for authorName in authorNames {
                let author = findOrCreateAuthor(name: authorName)
                book.addToAuthors(author)
            }
        }

        if let summary = summary {
            book.summary = summary
        }

        book.dateModified = Date()

        try viewContext.save()
        loadBooks()
        loadAuthors()
    }

    /// Set cover image for book
    func setCoverImage(_ imageData: Data, for book: Book) throws {
        book.coverImageData = imageData
        book.dateModified = Date()
        try viewContext.save()
    }

    // MARK: - Authors

    /// Find or create an author by name
    func findOrCreateAuthor(name: String) -> Author {
        let request = Author.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let author = Author(context: viewContext)
        author.id = UUID()
        author.name = name
        author.sortName = generateSortName(name)
        return author
    }

    // MARK: - Series

    /// Find or create a series by name
    func findOrCreateSeries(name: String) -> Series {
        let request = Series.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let newSeries = Series(context: viewContext)
        newSeries.id = UUID()
        newSeries.name = name
        return newSeries
    }

    // MARK: - Tags

    /// Find or create a tag by name
    func findOrCreateTag(name: String, color: String? = nil) -> Tag {
        let request = Tag.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let tag = Tag(context: viewContext)
        tag.id = UUID()
        tag.name = name
        tag.color = color
        return tag
    }

    /// Add tag to book
    func addTag(_ tagName: String, to book: Book, color: String? = nil) throws {
        let tag = findOrCreateTag(name: tagName, color: color)
        book.addToTags(tag)
        book.dateModified = Date()
        try viewContext.save()
        loadTags()
    }

    // MARK: - Collections

    /// Create a new collection
    func createCollection(name: String, iconName: String? = nil) throws -> Collection {
        let collection = Collection(context: viewContext)
        collection.id = UUID()
        collection.name = name
        collection.iconName = iconName
        collection.dateCreated = Date()

        try viewContext.save()
        return collection
    }

    // MARK: - Statistics

    /// Get library statistics
    var statistics: LibraryStatistics {
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

    // MARK: - Helpers

    private func isValidEbookFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func getFileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Parsed result from filename containing title and optional author
    struct ParsedFilename {
        let title: String
        let author: String?
    }

    /// Extract title and author from a filename
    /// Supports patterns like:
    /// - "Title - Author.epub"
    /// - "Author - Title.epub" (less common, detected by checking if first part looks like a name)
    /// - "Title (Author).epub"
    /// - "Title by Author.epub"
    private func parseFilename(_ filename: String) -> ParsedFilename {
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
        // Split on " - " and determine which part is title vs author
        let dashSeparators = [" - ", " – ", " — "]  // Regular dash, en-dash, em-dash
        for separator in dashSeparators {
            if let dashRange = name.range(of: separator) {
                let firstPart = String(name[..<dashRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let secondPart = String(name[dashRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                // The author part usually looks like a name (capitalized words, no special chars)
                // Title is usually longer and may have more varied characters
                if !firstPart.isEmpty && !secondPart.isEmpty {
                    if looksLikeAuthorName(secondPart) && !looksLikeAuthorName(firstPart) {
                        // "Title - Author" format
                        return ParsedFilename(title: firstPart, author: secondPart)
                    } else if looksLikeAuthorName(firstPart) && !looksLikeAuthorName(secondPart) {
                        // "Author - Title" format
                        return ParsedFilename(title: secondPart, author: firstPart)
                    } else if looksLikeAuthorName(secondPart) {
                        // Default to "Title - Author" if both could be names
                        return ParsedFilename(title: firstPart, author: secondPart)
                    }
                }
            }
        }

        // No pattern matched - just clean up and return as title
        let cleanedTitle = name
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedFilename(title: cleanedTitle, author: nil)
    }

    /// Check if a string looks like an author name (e.g., "J.R.R. Tolkien", "George R.R. Martin")
    private func looksLikeAuthorName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Author names are typically 2-5 words
        let words = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 1 && words.count <= 6 else { return false }

        // Check if words look like name parts (capitalized, possibly with periods for initials)
        let namePattern = #"^[A-Z][a-zA-Z]*\.?$"#
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

    /// Legacy function for backward compatibility - extracts only title
    private func extractTitleFromFilename(_ filename: String) -> String {
        return parseFilename(filename).title
    }

    private func generateSortTitle(_ title: String) -> String {
        let articles = ["the ", "a ", "an "]
        var result = title.lowercased()

        for article in articles {
            if result.hasPrefix(article) {
                result = String(result.dropFirst(article.count))
                break
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func generateSortName(_ name: String) -> String {
        // "John Smith" -> "Smith, John"
        let components = name.components(separatedBy: " ")
        guard components.count > 1 else { return name }

        let lastName = components.last ?? ""
        let firstNames = components.dropLast().joined(separator: " ")
        return "\(lastName), \(firstNames)"
    }
}

// MARK: - Supporting Types

struct ImportResult {
    let imported: Int
    let failed: Int
    let errors: [String]

    var summary: String {
        if failed == 0 {
            return "Successfully imported \(imported) book(s)"
        } else {
            return "Imported \(imported) book(s), \(failed) failed"
        }
    }
}

struct LibraryStatistics {
    let totalBooks: Int
    let totalSizeBytes: Int64
    let formatCounts: [String: Int]
    let authorCount: Int
    let seriesCount: Int
    let tagCount: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSizeBytes, countStyle: .file)
    }
}

enum LibraryError: LocalizedError {
    case fileNotFound(URL)
    case invalidFormat(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .invalidFormat(let format):
            return "Unsupported format: \(format)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}

// MARK: - HTTPTransferBookProvider Conformance

extension LibraryService: HTTPTransferBookProvider {
    /// Get all books as DTOs for the HTTP transfer server
    func getAllBooks() -> [BookDTO] {
        books.map { book in
            let authorNames = (book.authors as? Set<Author>)?.compactMap { $0.name } ?? []
            return BookDTO(
                id: book.id?.uuidString ?? UUID().uuidString,
                title: book.title ?? "Unknown",
                authors: authorNames,
                format: book.format ?? "unknown",
                fileSize: book.fileSize,
                coverURL: nil,
                dateAdded: book.dateAdded ?? Date()
            )
        }
    }

    /// Get the file URL for a book by its ID
    func getBookFileURL(id: String) -> URL? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return books.first { $0.id == uuid }?.fileURL
    }

    /// Get the format for a book by its ID
    func getBookFormat(id: String) -> EbookFormat? {
        guard let uuid = UUID(uuidString: id),
              let book = books.first(where: { $0.id == uuid }),
              let formatString = book.format else { return nil }
        return EbookFormat(fileExtension: formatString)
    }

    /// Get security-scoped bookmark data for a book (for external volume access)
    func getBookmarkData(id: String) -> Data? {
        guard let uuid = UUID(uuidString: id),
              let book = books.first(where: { $0.id == uuid }) else { return nil }
        return book.bookmarkData
    }

    /// Get book metadata (title, authors) for conversion
    func getBookMetadata(id: String) -> (title: String, authors: [String])? {
        guard let uuid = UUID(uuidString: id),
              let book = books.first(where: { $0.id == uuid }) else { return nil }

        let title = book.title ?? "Unknown"
        let authors = (book.authors as? Set<Author>)?.compactMap { $0.name } ?? []
        return (title: title, authors: authors)
    }
}
