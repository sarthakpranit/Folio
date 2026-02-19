//
//  LibraryService.swift
//  Folio
//
//  LibraryService is the facade for all library operations.
//  It coordinates specialized services and provides a unified interface for views.
//
//  Architecture:
//  - Facade pattern: Single entry point for UI layer
//  - Delegates to specialized services: BookRepository, ImportService, SearchService
//  - Manages @Published state for SwiftUI binding
//  - Implements HTTPTransferBookProvider for WiFi transfer integration
//
//  Specialized Services:
//  - BookRepository: Core Data CRUD operations
//  - ImportService: Import workflow with progress tracking
//  - SearchService: Search and filter operations
//  - FilenameParser: Filename parsing utility
//
//  Usage:
//    // Views use LibraryService.shared
//    LibraryService.shared.refresh()
//    let results = LibraryService.shared.searchBooks(query: "tolkien")
//

import Foundation
import CoreData
import Combine
import UniformTypeIdentifiers
import FolioCore

/// Facade for library operations - coordinates specialized services
@MainActor
class LibraryService: ObservableObject {
    static let shared = LibraryService()

    // MARK: - Specialized Services

    private let repository: BookRepository
    private let importService: ImportService
    private let searchService: SearchService
    private let filenameParser: FilenameParser

    // MARK: - Published State

    @Published private(set) var books: [Book] = []
    @Published private(set) var authors: [Author] = []
    @Published private(set) var series: [Series] = []
    @Published private(set) var tags: [Tag] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?

    // Import progress (delegated from ImportService)
    var isImporting: Bool { importService.isImporting }
    var importProgress: Double { importService.importProgress }
    var importTotal: Int { importService.importTotal }
    var importCurrent: Int { importService.importCurrent }
    var importCurrentBookName: String { importService.importCurrentBookName }

    /// Supported import formats (delegated from repository)
    var supportedExtensions: [String] { repository.supportedExtensions }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        let context = PersistenceController.shared.container.viewContext

        self.filenameParser = FilenameParser()
        self.repository = BookRepository(context: context)
        self.importService = ImportService(repository: repository, parser: filenameParser)
        self.searchService = SearchService()

        // Forward ImportService state changes
        importService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        loadAll()
    }

    // MARK: - Loading

    private func loadAll() {
        loadBooks()
        loadAuthors()
        loadSeries()
        loadTags()
    }

    func loadBooks() {
        do {
            books = try repository.fetchAll()
        } catch {
            self.error = error
            print("Failed to load books: \(error.localizedDescription)")
        }
    }

    func loadAuthors() {
        do {
            authors = try repository.fetchAllAuthors()
        } catch {
            print("Failed to load authors: \(error.localizedDescription)")
        }
    }

    func loadSeries() {
        do {
            series = try repository.fetchAllSeries()
        } catch {
            print("Failed to load series: \(error.localizedDescription)")
        }
    }

    func loadTags() {
        do {
            tags = try repository.fetchAllTags()
        } catch {
            print("Failed to load tags: \(error.localizedDescription)")
        }
    }

    /// Refresh all data from database
    func refresh() {
        loadAll()
        objectWillChange.send()
        print("[LibraryService] Refreshed - Authors: \(authors.count), Series: \(series.count), Tags: \(tags.count)")
    }

    // MARK: - Add Book

    /// Add a single book to the library
    @discardableResult
    func addBook(from fileURL: URL, shouldCopy: Bool = false) throws -> Book {
        let parsed = filenameParser.parse(fileURL.lastPathComponent)
        let sortTitle = repository.generateSortTitle(parsed.title)

        let book = try repository.add(
            from: fileURL,
            title: parsed.title,
            sortTitle: sortTitle,
            authorName: parsed.author
        )

        loadBooks()
        objectWillChange.send()

        print("Added book: \(book.title ?? "Unknown")")
        return book
    }

    /// Import multiple books from URLs
    func importBooks(from urls: [URL]) async -> ImportResult {
        isLoading = true
        defer {
            isLoading = false
            loadAll()
            objectWillChange.send()
        }

        return await importService.importBooks(from: urls)
    }

    // MARK: - Delete Book

    /// Delete a book from the library
    func deleteBook(_ book: Book, deleteFile: Bool = false) throws {
        try repository.delete(book, deleteFile: deleteFile)
        loadBooks()
        objectWillChange.send()
        print("Deleted book: \(book.title ?? "Unknown")")
    }

    /// Delete multiple books
    func deleteBooks(_ booksToDelete: [Book], deleteFiles: Bool = false) throws {
        try repository.deleteMultiple(booksToDelete, deleteFiles: deleteFiles)
        loadBooks()
        objectWillChange.send()
    }

    // MARK: - Update Book

    /// Update book metadata
    func updateBook(_ book: Book, title: String? = nil, authors: [String]? = nil, summary: String? = nil) throws {
        try repository.update(book, title: title, authorNames: authors, summary: summary)
        loadBooks()
        loadAuthors()
    }

    /// Set cover image for book
    func setCoverImage(_ imageData: Data, for book: Book) throws {
        try repository.setCoverImage(imageData, for: book)
    }

    // MARK: - Title Cleanup

    /// Clean up book titles by extracting embedded author names
    func cleanupBookTitles(books booksToClean: [Book]? = nil) -> SearchService.CleanupResult {
        let targetBooks = booksToClean ?? self.books

        let result = searchService.cleanupBookTitles(
            books: targetBooks,
            parser: filenameParser,
            findOrCreateAuthor: { [weak self] name in
                self?.repository.findOrCreateAuthor(name: name) ?? Author()
            },
            generateSortTitle: { [weak self] title in
                self?.repository.generateSortTitle(title) ?? title.lowercased()
            }
        )

        if result.titlesFixed > 0 {
            try? repository.save()
            loadBooks()
            loadAuthors()
            objectWillChange.send()
        }

        return result
    }

    // MARK: - Search & Filter

    /// Search books by query
    func searchBooks(query: String) -> [Book] {
        searchService.search(books: books, query: query)
    }

    /// Filter books by various criteria
    func filterBooks(
        byAuthors filterAuthors: [Author]? = nil,
        bySeries filterSeries: Series? = nil,
        byTags filterTags: [Tag]? = nil,
        byFormat format: String? = nil
    ) -> [Book] {
        searchService.filter(
            books: books,
            byAuthors: filterAuthors,
            bySeries: filterSeries,
            byTags: filterTags,
            byFormat: format
        )
    }

    // MARK: - Relationship Entities

    /// Find or create an author by name
    func findOrCreateAuthor(name: String) -> Author {
        repository.findOrCreateAuthor(name: name)
    }

    /// Find or create a series by name
    func findOrCreateSeries(name: String) -> Series {
        repository.findOrCreateSeries(name: name)
    }

    /// Find or create a tag by name
    func findOrCreateTag(name: String, color: String? = nil) -> Tag {
        repository.findOrCreateTag(name: name, color: color)
    }

    /// Add tag to book
    func addTag(_ tagName: String, to book: Book, color: String? = nil) throws {
        try repository.addTag(tagName, to: book, color: color)
        loadTags()
    }

    // MARK: - Collections

    /// Create a new collection
    func createCollection(name: String, iconName: String? = nil) throws -> Collection {
        try repository.createCollection(name: name, iconName: iconName)
    }

    // MARK: - Statistics

    /// Get library statistics
    var statistics: LibraryStatistics {
        searchService.calculateStatistics(
            books: books,
            authors: authors,
            series: series,
            tags: tags
        )
    }

    // MARK: - Helpers

    /// Generate a sort-friendly title
    func generateSortTitle(_ title: String) -> String {
        repository.generateSortTitle(title)
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

    /// Get security-scoped bookmark data for a book
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
