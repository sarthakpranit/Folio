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
//  - Reads the library's entity lists from LibraryStore (the single source of
//    truth, #47); this type owns orchestration, not the fetched collections
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
//    try LibraryService.shared.addBook(from: url)
//    LibraryStore.shared.books   // the fetched book list
//

import Foundation
import CoreData
import Combine
import SwiftUI
import OSLog
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

    /// The single source of truth for the library's fetched entity lists (#47).
    /// LibraryService reads `store.books` / `.authors` / `.series` / `.tags`; it
    /// no longer holds its own copies or reloads them after a mutation — the
    /// store's fetched-results controllers pick up every context save.
    private let store: LibraryStore

    // MARK: - Published State

    @Published private(set) var isLoading: Bool = false

    /// Set by a scan that finished with books whose files it could not locate.
    /// A scan never deletes on its own (#81) — the UI presents this for the user
    /// to keep or remove. Cleared when they respond.
    @Published var unresolvedMissingFiles: UnresolvedMissingFiles?

    // MARK: - Library Folder

    @AppStorage("libraryFolderBookmarkData") private var libraryFolderBookmarkData: Data = Data()
    private var libraryFolderMonitor: DispatchSourceFileSystemObject?
    private var libraryFolderFileDescriptor: CInt = -1
    private var libraryFolderAccessURL: URL?
    private var scanDebounceTask: Task<Void, Never>?
    private var isLibraryScanRunning = false

    private let logger = Logger(subsystem: "com.folio", category: "LibraryScan")

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
        let container = PersistenceController.shared.container
        let context = container.viewContext

        self.filenameParser = FilenameParser()
        self.repository = BookRepository(context: context)
        self.importService = ImportService(repository: repository, parser: filenameParser, container: container)
        self.searchService = SearchService()
        self.store = LibraryStore.shared

        // Forward ImportService state changes
        importService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // One-time backfill of the v2 `Book.fileName` dedup key (#42) for rows
        // migrated from v1.
        repository.backfillFileNamesIfNeeded()
    }

    // MARK: - Add Book

    /// Add a single book to the library
    @discardableResult
    func addBook(from fileURL: URL, shouldCopy _: Bool = false) throws -> Book {
        let parsed = filenameParser.parse(fileURL.lastPathComponent)
        let sortTitle = repository.generateSortTitle(parsed.title)

        let book = try repository.add(
            from: fileURL,
            title: parsed.title,
            sortTitle: sortTitle,
            authorName: parsed.author
        )

        print("Added book: \(book.title ?? "Unknown")")
        return book
    }

    /// Add a converted format variant and preserve the source book's metadata
    /// so the new format stays grouped with the original.
    @discardableResult
    func addConvertedBook(from fileURL: URL, basedOn sourceBook: Book) throws -> Book {
        let sourceTitle = sourceBook.title ?? filenameParser.parse(fileURL.lastPathComponent).title
        let sourceSortTitle = sourceBook.sortTitle ?? repository.generateSortTitle(sourceTitle)
        let sourceAuthorName = (sourceBook.authors as? Set<Author>)?
            .compactMap(\.name)
            .sorted()
            .first

        let book = try repository.add(
            from: fileURL,
            title: sourceTitle,
            sortTitle: sourceSortTitle,
            authorName: sourceAuthorName
        )

        book.title = sourceBook.title
        book.sortTitle = sourceBook.sortTitle
        book.isbn = sourceBook.isbn
        book.isbn13 = sourceBook.isbn13
        book.publisher = sourceBook.publisher
        book.summary = sourceBook.summary
        book.pageCount = sourceBook.pageCount
        book.language = sourceBook.language
        book.publishedDate = sourceBook.publishedDate
        book.coverImageURL = sourceBook.coverImageURL
        book.coverImageData = sourceBook.coverImageData
        book.series = sourceBook.series
        book.seriesIndex = sourceBook.seriesIndex

        book.authors = nil
        if let authors = sourceBook.authors as? Set<Author> {
            for author in authors {
                book.addToAuthors(author)
            }
        }

        if let tags = sourceBook.tags as? Set<Tag> {
            for tag in tags {
                book.addToTags(tag)
            }
        }

        try book.managedObjectContext?.save()

        return book
    }

    /// Import multiple books from URLs
    func importBooks(from urls: [URL]) async -> ImportResult {
        isLoading = true
        defer { isLoading = false }

        return await importService.importBooks(from: urls)
    }

    // MARK: - Delete Book

    /// Delete a book from the library
    func deleteBook(_ book: Book, deleteFile: Bool = false) throws {
        try repository.delete(book, deleteFile: deleteFile)
        print("Deleted book: \(book.title ?? "Unknown")")
    }

    /// Delete multiple books
    func deleteBooks(_ booksToDelete: [Book], deleteFiles: Bool = false) throws {
        try repository.deleteMultiple(booksToDelete, deleteFiles: deleteFiles)
    }

    // MARK: - Update Book

    /// Update book metadata
    func updateBook(_ book: Book, title: String? = nil, authors: [String]? = nil, summary: String? = nil) throws {
        try repository.update(book, title: title, authorNames: authors, summary: summary)
    }

    /// Set cover image for book
    func setCoverImage(_ imageData: Data, for book: Book) throws {
        try repository.setCoverImage(imageData, for: book)
    }

    // MARK: - Title Cleanup

    /// Clean up book titles by extracting embedded author names
    func cleanupBookTitles(books booksToClean: [Book]? = nil) -> SearchService.CleanupResult {
        let targetBooks = booksToClean ?? store.books

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
        }

        return result
    }

    // MARK: - Search & Filter

    /// Search books by query
    func searchBooks(query: String) -> [Book] {
        searchService.search(books: store.books, query: query)
    }

    /// Filter books by various criteria
    func filterBooks(
        byAuthors filterAuthors: [Author]? = nil,
        bySeries filterSeries: Series? = nil,
        byTags filterTags: [Tag]? = nil,
        byFormat format: String? = nil
    ) -> [Book] {
        searchService.filter(
            books: store.books,
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
            books: store.books,
            authors: store.authors,
            series: store.series,
            tags: store.tags
        )
    }

    // MARK: - Helpers

    /// Generate a sort-friendly title
    func generateSortTitle(_ title: String) -> String {
        repository.generateSortTitle(title)
    }

    // MARK: - Library Folder Scanning

    func startLibraryMonitoringAndScan() async {
        guard let folderURL = resolveLibraryFolderURL() else { return }
        startLibraryFolderMonitoring(for: folderURL)
        _ = await scanLibraryFolder(reason: "App Launch", showToast: false)
    }

    func setLibraryFolder(url: URL) async {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            libraryFolderBookmarkData = bookmarkData
            startLibraryFolderMonitoring(for: url)

            let result = await scanLibraryFolder(reason: "Library Location Set", showToast: true)
            if result == nil {
                showToastMessage(title: "Scan Failed", message: "Could not scan the selected library folder.", isError: true)
            }
        } catch {
            logger.error("Failed to create library folder bookmark: \(error.localizedDescription)")
            showToastMessage(title: "Library Location Failed", message: "Could not access the selected folder.", isError: true)
        }
    }

    func scanLibraryFolder(reason: String, showToast: Bool = true) async -> LibraryScanResult? {
        guard !isLibraryScanRunning else { return nil }
        guard let folderURL = resolveLibraryFolderURL() else { return nil }

        isLibraryScanRunning = true
        defer { isLibraryScanRunning = false }

        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let supportedExtensions = repository.supportedExtensions
        let scannedFiles = await collectEbookFiles(in: folderURL, supportedExtensions: supportedExtensions)

        let existingBooks = store.books
        var existingPathSet = Set<String>()
        for book in existingBooks {
            if let url = book.fileURL {
                existingPathSet.insert(url.standardizedFileURL.path)
            }
        }

        var missingBooks: [Book] = []
        for book in existingBooks {
            guard let fileURL = book.fileURL else {
                missingBooks.append(book)
                continue
            }
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                missingBooks.append(book)
            }
        }

        let filesByName = Dictionary(grouping: scannedFiles, by: { $0.lastPathComponent.lowercased() })
        let scannedPaths = Set(scannedFiles.map { $0.standardizedFileURL.path })
        var claimedPaths = Set<String>()
        var updatedCount = 0
        var unmatchedBooks: [Book] = []

        for book in missingBooks {
            // 1. Security-scoped bookmark: resolves a file that was moved or
            //    renamed within the library folder by its identity, not its
            //    path (#81). Free — the bookmark is already stored.
            if let bookmarkURL = resolveBookmarkMatch(for: book, scannedPaths: scannedPaths, claimedPaths: claimedPaths) {
                applyRematch(book, to: bookmarkURL)
                updatedCount += 1
                claimedPaths.insert(bookmarkURL.standardizedFileURL.path)
                continue
            }

            // 2. Fallback: same filename, size as a tiebreak. A rename defeats
            //    this, and a rename + re-save is exactly the case that used to
            //    destroy the book — hence the bookmark step above and the
            //    "never delete" handling below.
            guard let filename = book.fileURL?.lastPathComponent.lowercased() else {
                unmatchedBooks.append(book)
                continue
            }

            let candidates = (filesByName[filename] ?? []).filter { !claimedPaths.contains($0.standardizedFileURL.path) }
            let matchedURL: URL?
            if candidates.isEmpty {
                matchedURL = nil
            } else if candidates.count == 1 {
                matchedURL = candidates.first
            } else if book.fileSize > 0 {
                matchedURL = candidates.first { fileSize(for: $0) == book.fileSize } ?? candidates.first
            } else {
                matchedURL = candidates.first
            }

            if let newURL = matchedURL {
                applyRematch(book, to: newURL)
                updatedCount += 1
                claimedPaths.insert(newURL.standardizedFileURL.path)
            } else {
                unmatchedBooks.append(book)
            }
        }

        let newFiles = scannedFiles.filter {
            let path = $0.standardizedFileURL.path
            return !existingPathSet.contains(path) && !claimedPaths.contains(path)
        }

        var importResult: ImportResult?
        if !newFiles.isEmpty {
            importResult = await importService.importBooks(from: newFiles)
        }

        // #81: a scan NEVER deletes. Books whose files could not be located keep
        // every bit of their metadata (tags, series, summary, cover, Kindle
        // links); the user decides what to do with them via the review prompt.
        if !unmatchedBooks.isEmpty {
            unresolvedMissingFiles = UnresolvedMissingFiles(books: unmatchedBooks)
        }

        if updatedCount > 0 {
            try? repository.save()
        }

        let result = LibraryScanResult(
            imported: importResult?.imported ?? 0,
            updated: updatedCount,
            unresolved: unmatchedBooks.count,
            skipped: importResult?.skipped ?? 0,
            failed: importResult?.failed ?? 0
        )

        if showToast {
            if result.imported > 0 || result.updated > 0 || result.unresolved > 0 {
                showToastMessage(
                    title: "Library Updated",
                    message: result.summary
                )
            } else if reason == "Manual" {
                showToastMessage(title: "No Changes", message: "No new or missing books found.")
            }
        }

        return result
    }

    private func startLibraryFolderMonitoring(for folderURL: URL) {
        stopLibraryFolderMonitoring()

        if folderURL.startAccessingSecurityScopedResource() {
            libraryFolderAccessURL = folderURL
        }

        let fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            if let accessURL = libraryFolderAccessURL {
                accessURL.stopAccessingSecurityScopedResource()
                libraryFolderAccessURL = nil
            }
            logger.error("Failed to open library folder for monitoring.")
            return
        }

        libraryFolderFileDescriptor = fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            self?.scheduleLibraryScan()
        }

        source.setCancelHandler { [weak self] in
            close(fileDescriptor)
            self?.libraryFolderFileDescriptor = -1
            if let accessURL = self?.libraryFolderAccessURL {
                accessURL.stopAccessingSecurityScopedResource()
                self?.libraryFolderAccessURL = nil
            }
        }

        source.resume()
        libraryFolderMonitor = source
    }

    private func stopLibraryFolderMonitoring() {
        libraryFolderMonitor?.cancel()
        libraryFolderMonitor = nil
        scanDebounceTask?.cancel()
        scanDebounceTask = nil
    }

    private func scheduleLibraryScan() {
        scanDebounceTask?.cancel()
        scanDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            _ = await self?.scanLibraryFolder(reason: "Folder Change", showToast: true)
        }
    }

    private func resolveLibraryFolderURL() -> URL? {
        guard !libraryFolderBookmarkData.isEmpty else { return nil }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: libraryFolderBookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                let newBookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                libraryFolderBookmarkData = newBookmark
            }

            return url
        } catch {
            logger.error("Failed to resolve library folder bookmark: \(error.localizedDescription)")
            return nil
        }
    }

    private func collectEbookFiles(in folderURL: URL, supportedExtensions: [String]) async -> [URL] {
        await Task.detached {
            let fileManager = FileManager.default
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return []
            }

            var files: [URL] = []
            while let element = enumerator.nextObject() as? URL {
                guard let resourceValues = try? element.resourceValues(forKeys: [.isRegularFileKey]),
                      resourceValues.isRegularFile == true else {
                    continue
                }

                if supportedExtensions.contains(element.pathExtension.lowercased()) {
                    files.append(element)
                }
            }
            return files
        }.value
    }

    private func fileSize(for url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Try to locate a book's file via its stored security-scoped bookmark.
    /// A bookmark tracks the file by identity, so it survives a move or rename
    /// within the library folder (#81). Returns a URL only when it resolves to a
    /// file the current scan actually found and nothing else has claimed.
    private func resolveBookmarkMatch(for book: Book, scannedPaths: Set<String>, claimedPaths: Set<String>) -> URL? {
        guard let data = book.bookmarkData else { return nil }

        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        let path = resolved.standardizedFileURL.path
        guard scannedPaths.contains(path), !claimedPaths.contains(path) else { return nil }
        return resolved
    }

    /// Point a book at a newly located file and refresh its derived state.
    private func applyRematch(_ book: Book, to newURL: URL) {
        book.fileURL = newURL
        book.fileSize = fileSize(for: newURL)
        book.dateModified = Date()
        if let bookmarkData = try? newURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            book.bookmarkData = bookmarkData
        }
    }

    /// Remove books the user chose not to keep from the missing-files review.
    /// Files on disk are never touched (#81).
    func removeMissingBooks(_ books: [Book]) {
        guard !books.isEmpty else { return }
        do {
            try repository.deleteMultiple(books, deleteFiles: false)
        } catch {
            logger.error("Failed to remove missing books: \(error.localizedDescription)")
            showToastMessage(title: "Couldn’t Remove Books", message: error.localizedDescription, isError: true)
        }
    }

    private func showToastMessage(title: String, message: String, isError: Bool = false) {
        Task { @MainActor in
            ToastNotificationManager.shared.show(title: title, message: message, isError: isError)
        }
    }

    // MARK: - Conversion

    /// Check if Calibre is available for conversions
    var isCalibreAvailable: Bool {
        CalibreConversionService.shared.isCalibreAvailable
    }

    /// Convert a book file to a target format using Calibre
    func convertBook(at url: URL, to format: String, options: ConversionOptions = .default) async throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let stagedInputURL = try stageConversionInput(from: url)
        let stagingDirectory = stagedInputURL.deletingLastPathComponent()

        defer {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }

        var stagedOptions = options
        stagedOptions.outputDirectory = stagingDirectory

        let stagedOutputURL = try await CalibreConversionService.shared.convert(
            stagedInputURL,
            to: format,
            options: stagedOptions
        )

        return try materializeConvertedBook(
            from: stagedOutputURL,
            originalInputURL: url,
            options: options
        )
    }

    private func stageConversionInput(from url: URL) throws -> URL {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-conversion-\(UUID().uuidString)", isDirectory: true)

        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let stagedInputURL = stagingDirectory.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.copyItem(at: url, to: stagedInputURL)
        return stagedInputURL
    }

    private func materializeConvertedBook(
        from stagedOutputURL: URL,
        originalInputURL: URL,
        options: ConversionOptions
    ) throws -> URL {
        let destinationDirectory = options.outputDirectory ?? originalInputURL.deletingLastPathComponent()
        let accessing = destinationDirectory.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                destinationDirectory.stopAccessingSecurityScopedResource()
            }
        }

        let preferredOutputURL = destinationDirectory.appendingPathComponent(stagedOutputURL.lastPathComponent)
        let finalOutputURL = uniqueOutputURL(for: preferredOutputURL)
        try FileManager.default.copyItem(at: stagedOutputURL, to: finalOutputURL)
        return finalOutputURL
    }

    private func uniqueOutputURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let basename = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension

        for index in 2...1000 {
            let candidate = directory
                .appendingPathComponent("\(basename) (\(index))")
                .appendingPathExtension(pathExtension)

            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return directory
            .appendingPathComponent("\(basename)-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
    }
}

// MARK: - Supporting Types

struct LibraryScanResult {
    let imported: Int
    let updated: Int
    /// Books whose files the scan could not locate. Not removed — surfaced for
    /// the user to keep or remove (#81).
    let unresolved: Int
    let skipped: Int
    let failed: Int

    var summary: String {
        var parts: [String] = []
        if imported > 0 { parts.append("Imported \(imported)") }
        if updated > 0 { parts.append("Updated \(updated) paths") }
        if unresolved > 0 { parts.append("\(unresolved) missing file\(unresolved == 1 ? "" : "s")") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

/// Carries the books from a scan that could not find their files through to the
/// review sheet. Identifiable so it can drive `.sheet(item:)` (#81).
struct UnresolvedMissingFiles: Identifiable {
    let id = UUID()
    let books: [Book]
}

struct ImportResult {
    let imported: Int
    let failed: Int
    let skipped: Int
    let errors: [String]

    init(imported: Int, failed: Int, skipped: Int = 0, errors: [String]) {
        self.imported = imported
        self.failed = failed
        self.skipped = skipped
        self.errors = errors
    }

    var summary: String {
        var parts: [String] = []

        if imported > 0 {
            parts.append("Imported \(imported)")
        }
        if skipped > 0 {
            parts.append("\(skipped) skipped (duplicates)")
        }
        if failed > 0 {
            parts.append("\(failed) failed")
        }

        if parts.isEmpty {
            return "No books imported"
        }
        return parts.joined(separator: ", ")
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
        store.books.map { book in
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
        return store.books.first { $0.id == uuid }?.fileURL
    }

    /// Get the format for a book by its ID
    func getBookFormat(id: String) -> EbookFormat? {
        guard let uuid = UUID(uuidString: id),
              let book = store.books.first(where: { $0.id == uuid }),
              let formatString = book.format else { return nil }
        return EbookFormat(fileExtension: formatString)
    }

    /// Get security-scoped bookmark data for a book
    func getBookmarkData(id: String) -> Data? {
        guard let uuid = UUID(uuidString: id),
              let book = store.books.first(where: { $0.id == uuid }) else { return nil }
        return book.bookmarkData
    }

    /// Get book metadata (title, authors) for conversion
    func getBookMetadata(id: String) -> (title: String, authors: [String])? {
        guard let uuid = UUID(uuidString: id),
              let book = store.books.first(where: { $0.id == uuid }) else { return nil }

        let title = book.title ?? "Unknown"
        let authors = (book.authors as? Set<Author>)?.compactMap { $0.name } ?? []
        return (title: title, authors: authors)
    }
}
