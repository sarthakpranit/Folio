//
//  BookRepository.swift
//  Folio
//
//  The BookRepository is the single source of truth for book persistence.
//  It handles all Core Data operations, providing a clean interface that
//  hides the complexity of managed object contexts.
//
//  Key Responsibilities:
//  - CRUD operations for books
//  - Security-scoped bookmark management for external file access
//  - Relationship entity creation (authors, series, tags)
//  - Core Data fetch and save operations
//
//  Design:
//  - Follows Repository pattern from Domain-Driven Design
//  - All operations go through viewContext for @MainActor safety
//  - Provides findOrCreate methods for relationship entities
//
//  Usage:
//    let repo = BookRepository(context: viewContext)
//    let book = try repo.add(from: fileURL)
//    try repo.delete(book)
//

import Foundation
import CoreData

/// Repository for book persistence operations
@MainActor
class BookRepository {
    private let viewContext: NSManagedObjectContext

    /// Supported ebook file extensions
    let supportedExtensions = ["epub", "mobi", "azw3", "pdf", "cbz", "cbr", "fb2", "txt", "rtf"]

    init(context: NSManagedObjectContext) {
        self.viewContext = context
    }

    // MARK: - Fetch Operations

    /// Fetch all books sorted by date added
    func fetchAll() throws -> [Book] {
        let request = Book.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Book.dateAdded, ascending: false)]
        return try viewContext.fetch(request)
    }

    /// Fetch all authors sorted by sort name
    func fetchAllAuthors() throws -> [Author] {
        let request = Author.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Author.sortName, ascending: true)]
        return try viewContext.fetch(request)
    }

    /// Fetch all series sorted by name
    func fetchAllSeries() throws -> [Series] {
        let request = Series.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Series.name, ascending: true)]
        return try viewContext.fetch(request)
    }

    /// Fetch all tags sorted by name
    func fetchAllTags() throws -> [Tag] {
        let request = Tag.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]
        return try viewContext.fetch(request)
    }

    // MARK: - Duplicate Detection

    /// Find a duplicate book by filename or title+author match
    /// - Parameters:
    ///   - filename: The filename to check
    ///   - title: The parsed title
    ///   - author: Optional parsed author name
    /// - Returns: Existing book if duplicate found, nil otherwise
    func findDuplicate(filename: String, title: String, author: String?) -> Book? {
        // Check 1: Same filename already in library
        let filenameRequest = Book.fetchRequest()
        filenameRequest.predicate = NSPredicate(format: "fileURLString CONTAINS[c] %@", filename)
        filenameRequest.fetchLimit = 1

        if let match = try? viewContext.fetch(filenameRequest).first {
            return match
        }

        // Check 2: Same sortTitle + author match
        let normalizedTitle = generateSortTitle(title)
        var predicates: [NSPredicate] = [
            NSPredicate(format: "sortTitle ==[c] %@", normalizedTitle)
        ]

        // If author is provided, add it to the predicate
        if let author = author, !author.isEmpty {
            // Match on last name (most common identifier)
            let lastName = author.components(separatedBy: " ").last ?? author
            predicates.append(NSPredicate(format: "ANY authors.name CONTAINS[c] %@", lastName))
        }

        let titleRequest = Book.fetchRequest()
        titleRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        titleRequest.fetchLimit = 1

        return try? viewContext.fetch(titleRequest).first
    }

    // MARK: - Add Book

    /// Add a single book to the repository
    /// - Parameters:
    ///   - fileURL: URL of the ebook file
    ///   - title: Parsed title
    ///   - authorName: Optional parsed author name
    /// - Returns: The created Book entity
    @discardableResult
    func add(from fileURL: URL, title: String, sortTitle: String, authorName: String?) throws -> Book {
        // Start accessing security-scoped resource
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
        book.title = title
        book.sortTitle = sortTitle

        // Create security-scoped bookmark for persistent access
        if let bookmarkData = try? fileURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            book.bookmarkData = bookmarkData
        }

        // Add author if provided
        if let authorName = authorName, !authorName.isEmpty {
            let author = findOrCreateAuthor(name: authorName)
            book.addToAuthors(author)
        }

        try viewContext.save()
        viewContext.refreshAllObjects()

        return book
    }

    // MARK: - Delete Operations

    /// Delete a single book
    func delete(_ book: Book, deleteFile: Bool = false) throws {
        if deleteFile, let fileURL = book.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Refresh related Kindle devices so their syncedBooks count updates in UI
        if let kindleDevices = book.kindleDevices as? Set<KindleDevice> {
            for device in kindleDevices {
                viewContext.refresh(device, mergeChanges: true)
            }
        }

        viewContext.delete(book)
        try viewContext.save()
    }

    /// Delete multiple books
    func deleteMultiple(_ books: [Book], deleteFiles: Bool = false) throws {
        // Collect all affected Kindle devices before deletion
        var affectedDevices = Set<KindleDevice>()
        for book in books {
            if let kindleDevices = book.kindleDevices as? Set<KindleDevice> {
                affectedDevices.formUnion(kindleDevices)
            }
        }

        for book in books {
            if deleteFiles, let fileURL = book.fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            viewContext.delete(book)
        }

        // Refresh affected Kindle devices so their syncedBooks count updates in UI
        for device in affectedDevices {
            viewContext.refresh(device, mergeChanges: true)
        }

        try viewContext.save()
    }

    // MARK: - Update Operations

    /// Update book metadata
    func update(_ book: Book, title: String?, authorNames: [String]?, summary: String?) throws {
        if let title = title {
            book.title = title
            book.sortTitle = generateSortTitle(title)
        }

        if let authorNames = authorNames {
            book.authors = nil
            for name in authorNames {
                let author = findOrCreateAuthor(name: name)
                book.addToAuthors(author)
            }
        }

        if let summary = summary {
            book.summary = summary
        }

        book.dateModified = Date()
        try viewContext.save()
    }

    /// Set cover image for a book
    func setCoverImage(_ imageData: Data, for book: Book) throws {
        book.coverImageData = imageData
        book.dateModified = Date()
        try viewContext.save()
    }

    // MARK: - Relationship Entities

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

    /// Find or create a series by name
    func findOrCreateSeries(name: String) -> Series {
        let request = Series.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1

        if let existing = try? viewContext.fetch(request).first {
            return existing
        }

        let series = Series(context: viewContext)
        series.id = UUID()
        series.name = name
        return series
    }

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

    /// Add a tag to a book
    func addTag(_ tagName: String, to book: Book, color: String? = nil) throws {
        let tag = findOrCreateTag(name: tagName, color: color)
        book.addToTags(tag)
        book.dateModified = Date()
        try viewContext.save()
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

    // MARK: - Save

    /// Save any pending changes
    func save() throws {
        if viewContext.hasChanges {
            try viewContext.save()
        }
    }

    // MARK: - Helpers

    func isValidEbookFile(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func getFileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int64 else {
            return 0
        }
        return size
    }

    /// Generate a sort-friendly title by removing leading articles
    func generateSortTitle(_ title: String) -> String {
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
