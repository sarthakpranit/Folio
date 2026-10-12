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

    @Test("Find duplicate matches on the indexed fileName key, case-insensitively")
    @MainActor
    func testFindDuplicateByFilename() async throws {
        let (repository, context) = makeRepository()

        // The duplicate contract is filename-based, not full-URL-based. Since
        // #42 the match runs against `Book.fileName` — a lowercased, indexed
        // copy of `fileURL.lastPathComponent` that `add()` sets — via an
        // `==[c]` predicate, not a full-table scan over the URI-valued fileURL.
        let book = Book(context: context)
        book.id = UUID()
        book.title = "Existing Book"
        book.sortTitle = "existing book"
        book.fileURL = URL(fileURLWithPath: "/Volumes/Library/Existing/MyBook.epub")
        book.fileName = "mybook.epub"
        book.dateAdded = Date()
        try context.save()

        // Caller passes the raw last path component; case must not matter.
        let result = repository.findDuplicate(
            filename: "MyBook.epub",
            title: "Different Title",
            author: nil
        )

        #expect(result != nil)
        #expect(result?.title == "Existing Book")
    }

    @Test("add() records the dedup key so re-importing the same file is caught")
    @MainActor
    func testAddPopulatesFileNameForDuplicateDetection() async throws {
        let (repository, _) = makeRepository()

        // Why this matters: import calls findDuplicate once per file to skip
        // files already in the library. That only works if add() denormalises
        // the filename into the indexed `fileName` key (#42) at insert time.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Folio-\(UUID().uuidString)-Test Book.epub")
        try Data("epub".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let added = try repository.add(
            from: tempURL,
            title: "Test Book",
            sortTitle: "test book",
            authorName: nil
        )
        #expect(added.fileName == tempURL.lastPathComponent.lowercased())

        // A second import of the same file, discovered under a different parsed
        // title, is still recognised as a duplicate via the filename branch.
        let dup = repository.findDuplicate(
            filename: tempURL.lastPathComponent,
            title: "Completely Different Title",
            author: nil
        )
        #expect(dup?.objectID == added.objectID)
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

// MARK: - deleteAllData Tests

@Suite("deleteAllData Tests")
struct DeleteAllDataTests {

    @Test("Removes rows from every entity, including KindleDevice")
    @MainActor
    func testDeletesAllEntities() async throws {
        let controller = PersistenceController.inMemory()
        let context = controller.container.viewContext

        // One row per model entity. KindleDevice matters here: it was absent
        // from the delete list, so a "reset" silently kept Kindle devices (#46).
        let book = Book(context: context); book.id = UUID(); book.title = "Dune"; book.dateAdded = Date()
        let author = Author(context: context); author.id = UUID(); author.name = "Frank Herbert"
        let series = Series(context: context); series.id = UUID(); series.name = "Dune"
        let tag = Tag(context: context); tag.id = UUID(); tag.name = "SciFi"
        let collection = Collection(context: context); collection.id = UUID(); collection.name = "Favourites"
        let device = KindleDevice(context: context); device.id = UUID(); device.email = "me@kindle.com"
        try context.save()

        try controller.deleteAllData()

        for entityName in ["Book", "Author", "Series", "Tag", "Collection", "KindleDevice"] {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let count = try context.count(for: request)
            #expect(count == 0, "\(entityName) rows should be gone after deleteAllData")
        }
    }

    @Test("Invalidates objects already materialised in the context")
    @MainActor
    func testInvalidatesLiveObjects() async throws {
        let controller = PersistenceController.inMemory()
        let context = controller.container.viewContext

        let book = Book(context: context)
        book.id = UUID()
        book.title = "Neuromancer"
        book.dateAdded = Date()
        try context.save()

        // A batch delete bypasses the context; without merging the deleted IDs
        // this still-live reference would fault-crash on next access (the
        // stale-object class of bug from R1 / #46). After the merge it must be
        // marked deleted instead.
        try controller.deleteAllData()

        #expect(book.isDeleted || book.managedObjectContext == nil)
    }
}

// MARK: - Core Data Model Migration Tests

/// Guards the model versions' shape and their migration behaviour.
///
/// - v1 -> v2 (#42/#44/#45) was deliberately kept **lightweight** — indexes,
///   a new optional attribute, uniqueness constraints — so existing stores
///   migrate with no mapping model and no data loss (`testLightweightMigrationFromV1`).
/// - v2 -> v3 (#136/#137) is deliberately **not** lightweight: `Book.id` /
///   `Book.dateAdded` become non-optional and `fileURL` (URI) is replaced by
///   `filePath` (String). Per the pre-1.0 "clean base" call, there is no
///   mapping model — an incompatible store surfaces via the recovery screen
///   (decision #4 / #39), it is never silently rewritten.
///   `testV2StoreRejectedByV3WithoutInference` pins that: Core Data *would*
///   infer a lossy migration (dropping `fileURL`), so `Persistence.swift`
///   turns inference off and the open must throw instead.
@Suite("Core Data Model Migration")
struct CoreDataMigrationTests {

    private func momdURL() throws -> URL {
        let bundle = Bundle(for: PersistenceController.self)
        let url = try #require(bundle.url(forResource: "Folio", withExtension: "momd"),
                               "Folio.momd must be bundled with the app")
        return url
    }

    private func model(_ name: String) throws -> NSManagedObjectModel {
        let momd = try momdURL()
        let url = momd.appendingPathComponent("\(name).mom")
        return try #require(NSManagedObjectModel(contentsOf: url), "missing compiled model \(name).mom")
    }

    @Test("v2 model declares the constraints and indexes the tickets asked for")
    func testV2ModelShape() throws {
        let v2 = try model("Folio 2")
        let entities = v2.entitiesByName

        // #44 — uniqueness constraints.
        func constraintValues(_ entity: String) -> Set<String> {
            let constraints = entities[entity]?.uniquenessConstraints ?? []
            return Set(constraints.flatMap { group in
                group.map { element -> String in
                    (element as? NSPropertyDescription)?.name ?? String(describing: element)
                }
            })
        }
        #expect(constraintValues("Book").contains("id"))
        #expect(constraintValues("Author").contains("name"))
        #expect(constraintValues("Series").contains("name"))
        #expect(constraintValues("Tag").contains("name"))

        // #45 — fetch indexes.
        func indexNames(_ entity: String) -> Set<String> {
            Set((entities[entity]?.indexes ?? []).map { $0.name })
        }
        #expect(indexNames("Book").isSuperset(of: ["bySortTitle", "byISBN", "byISBN13", "byFileName"]))
        #expect(indexNames("Tag").contains("byName"))
        #expect(indexNames("Collection").contains("byName"))

        // #42 — the dedup key exists and #44 kept Book.id optional on purpose
        // (UUID has no static default, so non-optional needs a mapping model).
        let book = try #require(entities["Book"])
        #expect(book.attributesByName["fileName"] != nil)
        #expect(book.attributesByName["id"]?.isOptional == true)
        #expect(book.attributesByName["title"]?.isOptional == false)
        #expect(book.attributesByName["format"]?.isOptional == false)
    }

    @Test("A v1 store opens under the v2 model via lightweight migration, keeping its rows")
    func testLightweightMigrationFromV1() throws {
        let v1 = try model("Folio")
        let v2 = try model("Folio 2")

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioMigration-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1. Create a store with the v1 model and insert one book.
        let bookID = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1)
            try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            try context.performAndWait {
                let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
                book.setValue(bookID, forKey: "id")
                book.setValue("Old World", forKey: "title")
                book.setValue("old world", forKey: "sortTitle")
                book.setValue(URL(fileURLWithPath: "/books/Old World.epub"), forKey: "fileURL")
                book.setValue(Date(), forKey: "dateAdded")
                try context.save()
            }
            if let store = coordinator.persistentStores.first {
                try coordinator.remove(store)
            }
        }

        // 2. Reopen the same file with the v2 model and inferred migration on.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v2)
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        // Throws if the delta is not lightweight-migratable.
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: "Book")
            let books = try context.fetch(request)
            #expect(books.count == 1)
            #expect(books.first?.value(forKey: "id") as? UUID == bookID)
            // The new attribute lands nil for migrated rows — this is exactly
            // what BookRepository.backfillFileNamesIfNeeded() then fills in.
            #expect(books.first?.value(forKey: "fileName") == nil)
        }
    }

    @Test("v3 model makes Book.id / Book.dateAdded non-optional and stores the path as a String")
    func testV3ModelShape() throws {
        let v3 = try model("Folio 3")
        let book = try #require(v3.entitiesByName["Book"])

        // #136 — DB-level integrity: id and dateAdded can no longer be nil.
        #expect(book.attributesByName["id"]?.isOptional == false)
        #expect(book.attributesByName["dateAdded"]?.isOptional == false)

        // #137 — the URI attribute is gone; the location is a plain String.
        #expect(book.attributesByName["fileURL"] == nil)
        let filePath = try #require(book.attributesByName["filePath"])
        #expect(filePath.attributeType == .stringAttributeType)

        // Everything v2 established is still in place. Compiled-model uniqueness
        // constraint elements come back as bare property-name strings, not
        // `NSPropertyDescription`s — handle both, as `testV2ModelShape` does.
        #expect(book.attributesByName["fileName"] != nil)
        let idConstraint = book.uniquenessConstraints.flatMap { group in
            group.map { ($0 as? NSPropertyDescription)?.name ?? String(describing: $0) }
        }
        #expect(idConstraint.contains("id"))
        #expect(Set(book.indexes.map(\.name)).isSuperset(of: ["bySortTitle", "byFileName", "byISBN"]))
    }

    @Test("Under Persistence.swift's rules (no inferred mapping) a v2 store cannot open as v3")
    func testV2StoreRejectedByV3WithoutInference() throws {
        let v2 = try model("Folio 2")
        let v3 = try model("Folio 3")

        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolioMigration-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // A minimal valid v2 store with one fully-populated row.
        let makeCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v2)
        try makeCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = makeCoordinator
        try context.performAndWait {
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(UUID(), forKey: "id")
            book.setValue("Kept", forKey: "title")
            book.setValue(Date(), forKey: "dateAdded")
            book.setValue(URL(fileURLWithPath: "/books/Kept.epub"), forKey: "fileURL")
            try context.save()
        }
        if let store = makeCoordinator.persistentStores.first { try makeCoordinator.remove(store) }

        // Core Data WOULD infer a migration here (dropping `fileURL`, orphaning
        // the book) if asked. `Persistence.swift` sets
        // `shouldInferMappingModelAutomatically = false` precisely so it doesn't:
        // an incompatible store must throw and hand off to the recovery screen
        // (decision #4 / #39), never be silently rewritten. This pins that.
        let v3Coordinator = NSPersistentStoreCoordinator(managedObjectModel: v3)
        let options: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: false
        ]
        #expect(throws: (any Error).self) {
            try v3Coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
        }
    }
}
