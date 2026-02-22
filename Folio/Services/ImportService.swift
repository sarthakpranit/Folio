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
//  - Coordinate with BookRepository for persistence
//  - Coordinate with FilenameParser for metadata extraction
//
//  Design:
//  - Separates import logic from general library management
//  - Uses @Published for SwiftUI progress binding
//  - Async operations with proper cancellation support
//
//  Usage:
//    let importService = ImportService(repository: repo, parser: parser)
//    let result = await importService.importBooks(from: urls)
//

import Foundation
import CoreData
import Combine
import SwiftUI

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

/// Error for import-specific issues
enum ImportError: LocalizedError {
    case duplicateSkipped(String)

    var errorDescription: String? {
        switch self {
        case .duplicateSkipped(let title):
            return "Duplicate skipped: \(title)"
        }
    }
}

/// Service for importing ebooks into the library
@MainActor
class ImportService: ObservableObject {
    private let repository: BookRepository
    private let parser: FilenameParser

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

    init(repository: BookRepository, parser: FilenameParser) {
        self.repository = repository
        self.parser = parser
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

        var imported = 0
        var failed = 0
        var skipped = 0
        var errors: [String] = []

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

        // Import each file with progress updates
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

                try importSingleFile(fileURL)
                imported += 1
            } catch let error as ImportError {
                // Handle duplicate skipped separately from failures
                skipped += 1
                duplicatesSkipped = skipped
            } catch {
                failed += 1
                errors.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            }

            // Small delay to allow UI updates
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        importProgress = 1.0
        return ImportResult(imported: imported, failed: failed, skipped: skipped, errors: errors)
    }

    /// Import a single file with duplicate detection
    private func importSingleFile(_ fileURL: URL) throws {
        let filename = fileURL.lastPathComponent
        let parsed = parser.parse(filename)

        // Check for duplicates
        if let existingBook = repository.findDuplicate(
            filename: filename,
            title: parsed.title,
            author: parsed.author
        ) {
            switch duplicateStrategy {
            case .skip:
                throw ImportError.duplicateSkipped(existingBook.title ?? filename)

            case .replace:
                // Delete existing book (keep file on disk, just remove from library)
                try repository.delete(existingBook, deleteFile: false)
                // Continue to add the new file

            case .keepBoth:
                // Do nothing, continue to add as new entry
                break
            }
        }

        let sortTitle = repository.generateSortTitle(parsed.title)
        try repository.add(
            from: fileURL,
            title: parsed.title,
            sortTitle: sortTitle,
            authorName: parsed.author
        )
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
