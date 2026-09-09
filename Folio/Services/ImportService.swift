//
//  ImportService.swift
//  Folio
//
//  Handles the import workflow for adding ebooks to the library.
//  Manages progress tracking, file collection, and batch imports.
//
//  Key Responsibilities:
//  - Import single files and directories (recursively)
//  - Track import progress with @Published properties
//  - Collect valid ebook files from directories
//  - Run bulk row inserts on a background Core Data context (#43)
//  - Coordinate with BookRepository for duplicate detection
//  - Coordinate with FilenameParser for metadata extraction
//
//  Design:
//  - Separates import logic from general library management
//  - Uses @Published for SwiftUI progress binding
//  - Duplicate detection runs on the main-queue viewContext (via BookRepository).
//    The row inserts run on a private-queue background context and are saved one
//    chunk at a time; the viewContext picks them up through the stack's
//    `automaticallyMergesChangesFromParent` (#43). This keeps the main thread
//    free during a large import, so no artificial "let the UI breathe" sleep is
//    needed between files.
//
//  Usage:
//    let importService = ImportService(repository: repo, parser: parser, container: container)
//    let result = await importService.importBooks(from: urls)
//

import Foundation
import CoreData
import Combine
import SwiftUI
import OSLog
import FolioCore

/// Strategy for handling duplicate books during import
enum DuplicateStrategy: String, CaseIterable, Identifiable {
    case skip = "skip"
    case replace = "replace"
    case keepBoth = "keepBoth"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .skip: return "Skip"
        case .replace: return "Replace"
        case .keepBoth: return "Keep Both"
        }
    }
}

/// Service for importing ebooks into the library
@MainActor
class ImportService: ObservableObject {
    private let repository: BookRepository
    private let parser: FilenameParser
    /// Owns the background context used for bulk inserts (#43).
    private let container: NSPersistentContainer

    /// Number of rows inserted per background `save()`. Small enough that import
    /// progress still advances visibly, large enough to amortise the save.
    private static let chunkSize = 25

    /// Usable from the `nonisolated` background helpers below.
    nonisolated private static let logger = Logger(subsystem: "com.folio", category: "Import")

    /// User's preferred duplicate handling strategy
    @AppStorage("duplicateStrategy") private var duplicateStrategyRaw: String = "skip"

    private var duplicateStrategy: DuplicateStrategy {
        DuplicateStrategy(rawValue: duplicateStrategyRaw) ?? .skip
    }

    // Progress tracking
    @Published private(set) var isImporting: Bool = false
    @Published private(set) var importProgress: Double = 0
    @Published private(set) var importTotal: Int = 0
    @Published private(set) var importCurrent: Int = 0
    @Published private(set) var importCurrentBookName: String = ""
    @Published private(set) var duplicatesSkipped: Int = 0

    init(repository: BookRepository, parser: FilenameParser, container: NSPersistentContainer) {
        self.repository = repository
        self.parser = parser
        self.container = container
    }

    // MARK: - Import Operations

    /// Import multiple books from URLs (files or directories)
    func importBooks(from urls: [URL]) async -> ImportResult {
        isImporting = true
        importProgress = 0
        importCurrent = 0
        importCurrentBookName = "Scanning files..."
        duplicatesSkipped = 0

        defer {
            isImporting = false
            importProgress = 1.0
            importCurrentBookName = ""
        }

        // Collect all files to import
        var filesToImport: [URL] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if url.hasDirectoryPath {
                if let files = collectEbookFiles(from: url) {
                    filesToImport.append(contentsOf: files)
                }
            } else if repository.isValidEbookFile(url) {
                filesToImport.append(url)
            }
        }

        importTotal = filesToImport.count
        guard importTotal > 0 else {
            return ImportResult(imported: 0, failed: 0, errors: ["No valid ebook files found"])
        }

        // Pass 1 (main queue): parse filenames and resolve duplicates against the
        // viewContext. Duplicate detection stays on the repository/viewContext so
        // the URI-safe predicate handling in `findDuplicate` has one home; only
        // the writes move off the main thread (#43). `seenKeys` also catches
        // duplicates *within this batch*, which the old per-file-save loop got
        // for free.
        let strategy = duplicateStrategy
        var pending: [PendingImport] = []
        var objectIDsToDelete: [NSManagedObjectID] = []
        var seenKeys = Set<String>()
        var skipped = 0

        for fileURL in filesToImport {
            let filename = fileURL.lastPathComponent
            let parsed = parser.parse(filename)
            let sortTitle = repository.generateSortTitle(parsed.title)
            let keys = Self.dedupeKeys(filename: filename, sortTitle: sortTitle, author: parsed.author)

            let persistedDuplicate = repository.findDuplicate(
                filename: filename,
                title: parsed.title,
                author: parsed.author
            )
            let isDuplicate = persistedDuplicate != nil || keys.contains(where: seenKeys.contains)

            if isDuplicate {
                switch strategy {
                case .skip:
                    skipped += 1
                    continue
                case .replace:
                    if let existing = persistedDuplicate {
                        objectIDsToDelete.append(existing.objectID)
                    }
                case .keepBoth:
                    break
                }
            }

            seenKeys.formUnion(keys)
            pending.append(PendingImport(
                url: fileURL,
                title: parsed.title,
                sortTitle: sortTitle,
                authorName: parsed.author
            ))
        }

        duplicatesSkipped = skipped

        guard !pending.isEmpty else {
            return ImportResult(imported: 0, failed: 0, skipped: skipped, errors: [])
        }

        // Pass 2 (background queue): insert rows on a private-queue context,
        // one `save()` per chunk. The viewContext merges the saves via
        // `automaticallyMergesChangesFromParent`; LibraryService also reloads
        // after import. The `await` per chunk yields the main thread so the
        // @Published progress below renders without any sleep.
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var imported = 0
        var failed = 0
        var errors: [String] = []
        var deletesForFirstChunk = objectIDsToDelete
        var offset = 0

        while offset < pending.count {
            let chunk = Array(pending[offset ..< min(offset + Self.chunkSize, pending.count)])
            offset += chunk.count

            // Hold each file's security scope across the background hop.
            let scoped = chunk.map { ($0.url, $0.url.startAccessingSecurityScopedResource()) }
            let deletes = deletesForFirstChunk
            deletesForFirstChunk = []

            let outcome = await backgroundContext.perform {
                Self.applyChunk(chunk, deleteObjectIDs: deletes, in: backgroundContext)
            }

            for (url, accessing) in scoped where accessing {
                url.stopAccessingSecurityScopedResource()
            }

            imported += outcome.imported
            failed += outcome.failed
            errors.append(contentsOf: outcome.errors)

            importCurrent = min(offset, importTotal)
            importProgress = Double(importCurrent) / Double(importTotal)
            importCurrentBookName = chunk.last?.url.lastPathComponent ?? ""
        }

        importProgress = 1.0
        return ImportResult(imported: imported, failed: failed, skipped: skipped, errors: errors)
    }

    // MARK: - Background Insert

    /// A parsed, duplicate-resolved file waiting to be written. Value type so it
    /// can cross to the background context's queue.
    private struct PendingImport: Sendable {
        let url: URL
        let title: String
        let sortTitle: String
        let authorName: String?
    }

    private struct ChunkOutcome: Sendable {
        let imported: Int
        let failed: Int
        let errors: [String]
    }

    /// Insert one chunk on `context`'s queue and save it as a single batch.
    /// Must be called from inside `context.perform`.
    ///
    /// Mirrors the row construction in `BookRepository.add` — kept separate for
    /// now because `BookRepository` is `@MainActor`/viewContext-bound. ADR-0004
    /// (#24) folds the repository onto a context it owns in M3; this helper
    /// collapses into it then.
    nonisolated private static func applyChunk(
        _ items: [PendingImport],
        deleteObjectIDs: [NSManagedObjectID],
        in context: NSManagedObjectContext
    ) -> ChunkOutcome {
        for objectID in deleteObjectIDs {
            if let existing = try? context.existingObject(with: objectID) {
                context.delete(existing)
            }
        }

        var imported = 0
        var failed = 0
        var errors: [String] = []

        for item in items {
            do {
                try insert(item, into: context)
                imported += 1
            } catch {
                failed += 1
                errors.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard context.hasChanges else {
            return ChunkOutcome(imported: imported, failed: failed, errors: errors)
        }

        do {
            try context.save()
            return ChunkOutcome(imported: imported, failed: failed, errors: errors)
        } catch {
            // A failed batch save means none of this chunk landed — report it as
            // failed, not silently imported.
            logger.error("Background import chunk save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
            return ChunkOutcome(
                imported: 0,
                failed: failed + imported,
                errors: errors + ["Failed to save \(imported) book(s): \(error.localizedDescription)"]
            )
        }
    }

    /// Build one `Book` row in `context`. Does not save.
    nonisolated private static func insert(_ item: PendingImport, into context: NSManagedObjectContext) throws {
        let fileURL = item.url
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard fileURL.isEbookFile else {
            throw LibraryError.invalidFormat(fileURL.pathExtension)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LibraryError.fileNotFound(fileURL)
        }

        let book = Book(context: context)
        book.id = UUID()
        book.fileURL = fileURL
        book.format = fileURL.pathExtension.lowercased()
        book.fileSize = fileURL.fileSize ?? 0
        book.dateAdded = Date()
        book.dateModified = Date()
        book.title = item.title
        book.sortTitle = item.sortTitle

        // Security-scoped bookmark for persistent access after relaunch.
        if let bookmarkData = try? fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            book.bookmarkData = bookmarkData
        }

        if let authorName = item.authorName, !authorName.isEmpty {
            book.addToAuthors(findOrCreateAuthor(name: authorName, in: context))
        }
    }

    /// Background-context twin of `BookRepository.findOrCreateAuthor`.
    nonisolated private static func findOrCreateAuthor(name: String, in context: NSManagedObjectContext) -> Author {
        let request = NSFetchRequest<Author>(entityName: "Author")
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let author = Author(context: context)
        author.id = UUID()
        author.name = name
        author.sortName = sortName(from: name)
        return author
    }

    /// "John Smith" -> "Smith, John" (matches `BookRepository.generateSortName`).
    nonisolated private static func sortName(from name: String) -> String {
        let components = name.components(separatedBy: " ")
        guard components.count > 1 else { return name }

        let lastName = components.last ?? ""
        let firstNames = components.dropLast().joined(separator: " ")
        return "\(lastName), \(firstNames)"
    }

    /// Normalised keys used to spot duplicates *within one import batch*, before
    /// any chunk has been saved. Deliberately mirrors the two checks in
    /// `BookRepository.findDuplicate`: same filename, or same sort-title
    /// (+ author last name when present).
    ///
    /// `internal` (not `private`) so it can be unit-tested directly — the full
    /// `importBooks` path needs a Core Data stack, which FolioTests cannot spin
    /// up a second copy of without racing the test host app's `@FetchRequest`.
    nonisolated static func dedupeKeys(filename: String, sortTitle: String, author: String?) -> [String] {
        var keys = ["file:\(filename.lowercased())"]

        let normalizedTitle = sortTitle.lowercased()
        guard !normalizedTitle.isEmpty else { return keys }

        if let author, !author.isEmpty {
            let lastName = (author.components(separatedBy: " ").last ?? author).lowercased()
            keys.append("title-author:\(normalizedTitle)|\(lastName)")
        } else {
            keys.append("title:\(normalizedTitle)")
        }
        return keys
    }

    // MARK: - File Collection

    /// Collect all ebook files from a directory recursively
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
        while let element = enumerator.nextObject() as? URL {
            guard let resourceValues = try? element.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  repository.isValidEbookFile(element) else {
                continue
            }
            files.append(element)
        }
        return files
    }
}
