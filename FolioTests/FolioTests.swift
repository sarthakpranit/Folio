//
//  FolioTests.swift
//  FolioTests
//
//  Tests for Folio services including BookRepository and ImportService.
//

import Testing
import CoreData
@testable import Folio

// MARK: - BookRepository Tests

@Suite("BookRepository Tests")
struct BookRepositoryTests {

    /// Create an in-memory persistence controller for testing
    @MainActor
    private func makeRepository() -> (BookRepository, NSManagedObjectContext) {
        let controller = PersistenceController.inMemory()
        let context = controller.container.viewContext
        let repository = BookRepository(context: context)
        return (repository, context)
    }

    @Test("Generate sort title removes leading articles")
    @MainActor
    func testGenerateSortTitle() async throws {
        let (repository, _) = makeRepository()

        #expect(repository.generateSortTitle("The Great Gatsby") == "great gatsby")
        #expect(repository.generateSortTitle("A Tale of Two Cities") == "tale of two cities")
        #expect(repository.generateSortTitle("An American Tragedy") == "american tragedy")
        #expect(repository.generateSortTitle("1984") == "1984")
        #expect(repository.generateSortTitle("Dune") == "dune")
    }

    @Test("Find or create author creates new author")
    @MainActor
    func testFindOrCreateAuthorNew() async throws {
        let (repository, context) = makeRepository()

        let author = repository.findOrCreateAuthor(name: "J.R.R. Tolkien")

        #expect(author.name == "J.R.R. Tolkien")
        #expect(author.sortName == "Tolkien, J.R.R.")
        #expect(author.id != nil)

        // Verify it was saved
        let request = Author.fetchRequest()
        let authors = try context.fetch(request)
        #expect(authors.count == 1)
    }

    @Test("Find or create author finds existing author")
    @MainActor
    func testFindOrCreateAuthorExisting() async throws {
        let (repository, _) = makeRepository()

        // Create first author
        let author1 = repository.findOrCreateAuthor(name: "George Orwell")
        let id1 = author1.id

        // Try to create again with same name
        let author2 = repository.findOrCreateAuthor(name: "George Orwell")

        #expect(author1.id == author2.id)
        #expect(id1 == author2.id)
    }

    @Test("Find or create author is case insensitive")
    @MainActor
    func testFindOrCreateAuthorCaseInsensitive() async throws {
        let (repository, _) = makeRepository()

        let author1 = repository.findOrCreateAuthor(name: "Stephen King")
        let author2 = repository.findOrCreateAuthor(name: "STEPHEN KING")
        let author3 = repository.findOrCreateAuthor(name: "stephen king")

        #expect(author1.id == author2.id)
        #expect(author2.id == author3.id)
    }

    @Test("Find or create series creates new series")
    @MainActor
    func testFindOrCreateSeriesNew() async throws {
        let (repository, context) = makeRepository()

        let series = repository.findOrCreateSeries(name: "The Lord of the Rings")

        #expect(series.name == "The Lord of the Rings")
        #expect(series.id != nil)

        let request = Series.fetchRequest()
        let allSeries = try context.fetch(request)
        #expect(allSeries.count == 1)
    }

    @Test("Find or create tag creates new tag")
    @MainActor
    func testFindOrCreateTagNew() async throws {
        let (repository, context) = makeRepository()

        let tag = repository.findOrCreateTag(name: "Science Fiction", color: "#FF5733")

        #expect(tag.name == "Science Fiction")
        #expect(tag.color == "#FF5733")
        #expect(tag.id != nil)

        let request = Tag.fetchRequest()
        let tags = try context.fetch(request)
        #expect(tags.count == 1)
    }

    @Test("Update book changes title and generates sort title")
    @MainActor
    func testUpdateBookTitle() async throws {
        let (repository, context) = makeRepository()

        // Create a book manually for testing
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Original Title"
        book.sortTitle = "original title"
        book.dateAdded = Date()
        try context.save()

        // Update the title
        try repository.update(book, title: "The New Title", authorNames: nil, summary: nil)

        #expect(book.title == "The New Title")
        #expect(book.sortTitle == "new title")  // "The" removed
    }

    @Test("Update book changes authors")
    @MainActor
    func testUpdateBookAuthors() async throws {
        let (repository, context) = makeRepository()

        // Create a book with an author
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Test Book"
        book.dateAdded = Date()
        let originalAuthor = repository.findOrCreateAuthor(name: "Original Author")
        book.addToAuthors(originalAuthor)
        try context.save()

        #expect((book.authors as? Set<Author>)?.count == 1)

        // Update with new authors
        try repository.update(book, title: nil, authorNames: ["New Author 1", "New Author 2"], summary: nil)

        let authors = book.authors as? Set<Author>
        #expect(authors?.count == 2)
        let authorNames = authors?.compactMap { $0.name } ?? []
        #expect(authorNames.contains("New Author 1"))
        #expect(authorNames.contains("New Author 2"))
    }

    @Test("Is valid ebook file checks extensions")
    @MainActor
    func testIsValidEbookFile() async throws {
        let (repository, _) = makeRepository()

        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.epub")) == true)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.mobi")) == true)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.pdf")) == true)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.azw3")) == true)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.EPUB")) == true)  // Case insensitive
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.txt")) == true)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.doc")) == false)
        #expect(repository.isValidEbookFile(URL(fileURLWithPath: "/test/book.mp3")) == false)
    }
}

// MARK: - Duplicate Detection Tests

@Suite("Duplicate Detection Tests")
struct DuplicateDetectionTests {

    @MainActor
    private func makeRepository() -> (BookRepository, NSManagedObjectContext) {
        let controller = PersistenceController.inMemory()
        let context = controller.container.viewContext
        let repository = BookRepository(context: context)
        return (repository, context)
    }

    @Test("Find duplicate returns nil when no duplicate exists")
    @MainActor
    func testFindDuplicateNoMatch() async throws {
        let (repository, _) = makeRepository()

        let result = repository.findDuplicate(
            filename: "new_book.epub",
            title: "A New Book",
            author: "Unknown Author"
        )

        #expect(result == nil)
    }

    @Test("Find duplicate matches by exact filename")
    @MainActor
    func testFindDuplicateByFilename() async throws {
        let (repository, context) = makeRepository()

        // Create a book with a known filename
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Existing Book"
        book.sortTitle = "existing book"
        book.fileURLString = "/path/to/MyBook.epub"
        book.dateAdded = Date()
        try context.save()

        // Search for duplicate by same filename
        let result = repository.findDuplicate(
            filename: "MyBook.epub",
            title: "Different Title",
            author: nil
        )

        #expect(result != nil)
        #expect(result?.title == "Existing Book")
    }

    @Test("Find duplicate matches by title and author")
    @MainActor
    func testFindDuplicateByTitleAuthor() async throws {
        let (repository, context) = makeRepository()

        // Create a book with known title and author
        let book = Book(context: context)
        book.id = UUID()
        book.title = "The Great Gatsby"
        book.sortTitle = "great gatsby"
        book.dateAdded = Date()

        let author = repository.findOrCreateAuthor(name: "F. Scott Fitzgerald")
        book.addToAuthors(author)
        try context.save()

        // Search for duplicate by title + author
        let result = repository.findDuplicate(
            filename: "different_filename.epub",
            title: "The Great Gatsby",
            author: "Fitzgerald"  // Partial author name (last name)
        )

        #expect(result != nil)
        #expect(result?.title == "The Great Gatsby")
    }

    @Test("Find duplicate is case insensitive for title")
    @MainActor
    func testFindDuplicateCaseInsensitive() async throws {
        let (repository, context) = makeRepository()

        let book = Book(context: context)
        book.id = UUID()
        book.title = "Dune"
        book.sortTitle = "dune"
        book.dateAdded = Date()
        try context.save()

        let result = repository.findDuplicate(
            filename: "other.epub",
            title: "DUNE",
            author: nil
        )

        #expect(result != nil)
    }
}

// MARK: - ImportResult Tests

@Suite("ImportResult Tests")
struct ImportResultTests {

    @Test("Summary with only imports")
    func testSummaryImportOnly() {
        let result = ImportResult(imported: 5, failed: 0, skipped: 0, errors: [])
        #expect(result.summary == "Imported 5")
    }

    @Test("Summary with imports and skips")
    func testSummaryWithSkipped() {
        let result = ImportResult(imported: 3, failed: 0, skipped: 2, errors: [])
        #expect(result.summary == "Imported 3, 2 skipped (duplicates)")
    }

    @Test("Summary with all types")
    func testSummaryAllTypes() {
        let result = ImportResult(imported: 5, failed: 1, skipped: 2, errors: ["error1"])
        #expect(result.summary == "Imported 5, 2 skipped (duplicates), 1 failed")
    }

    @Test("Summary with no imports")
    func testSummaryNoImports() {
        let result = ImportResult(imported: 0, failed: 0, skipped: 0, errors: [])
        #expect(result.summary == "No books imported")
    }
}

// MARK: - DuplicateStrategy Tests

@Suite("DuplicateStrategy Tests")
struct DuplicateStrategyTests {

    @Test("Strategy display names")
    func testDisplayNames() {
        #expect(DuplicateStrategy.skip.displayName == "Skip")
        #expect(DuplicateStrategy.replace.displayName == "Replace")
        #expect(DuplicateStrategy.keepBoth.displayName == "Keep Both")
    }

    @Test("Strategy raw values match preferences")
    func testRawValues() {
        #expect(DuplicateStrategy.skip.rawValue == "skip")
        #expect(DuplicateStrategy.replace.rawValue == "replace")
        #expect(DuplicateStrategy.keepBoth.rawValue == "keepBoth")
    }

    @Test("Strategy initializes from raw value")
    func testInitFromRawValue() {
        #expect(DuplicateStrategy(rawValue: "skip") == .skip)
        #expect(DuplicateStrategy(rawValue: "replace") == .replace)
        #expect(DuplicateStrategy(rawValue: "keepBoth") == .keepBoth)
        #expect(DuplicateStrategy(rawValue: "invalid") == nil)
    }
}
