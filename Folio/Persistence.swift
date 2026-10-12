//
//  Persistence.swift
//  Folio
//
//  Core Data stack.
//

import CoreData
import Combine
import OSLog

/// A Core Data store that would not open. Held and surfaced instead of crashing
/// or silently continuing against no store (#39). Recovery-first (decision #4):
/// the store file itself is never touched.
struct StoreLoadFailure: Identifiable {
    let id = UUID()
    let underlyingError: NSError
    /// Location of the store that failed, for "reveal in Finder".
    let storeURL: URL?

    var message: String { underlyingError.localizedDescription }
}

class PersistenceController: ObservableObject {
    @MainActor static let shared = PersistenceController()

    private static let logger = Logger(subsystem: "com.folio", category: "Persistence")

    /// Non-nil when `loadPersistentStores` failed. The app shows a recovery
    /// screen in place of the library while this is set, so no write can land
    /// on a half-open stack (#39).
    @Published var loadFailure: StoreLoadFailure?

    /// Preview instance for SwiftUI previews
    @MainActor
    static let preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext

        // Create sample data
        let book = Book(context: viewContext)
        book.id = UUID()
        book.title = "The Great Gatsby"
        book.sortTitle = "great gatsby"
        book.format = "epub"
        book.fileURL = URL(fileURLWithPath: "/sample/great-gatsby.epub")
        book.fileSize = 1024000
        book.dateAdded = Date()
        book.dateModified = Date()
        book.summary = "A novel about the American dream set in the Jazz Age."

        let author = Author(context: viewContext)
        author.id = UUID()
        author.name = "F. Scott Fitzgerald"
        author.sortName = "Fitzgerald, F. Scott"
        author.books = [book]

        book.authors = [author]

        let tag = Tag(context: viewContext)
        tag.id = UUID()
        tag.name = "Classic"
        tag.color = "#8B4513"
        tag.books = [book]

        book.tags = [tag]

        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    /// In-memory instance for testing
    static func inMemory() -> PersistenceController {
        PersistenceController(inMemory: true)
    }

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Folio")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Apply an explicit mapping model when a model version ships one, but
            // never let Core Data *infer* a migration. Inference silently drops
            // renamed/removed attributes — the v2→v3 change (#137) renames
            // `fileURL` to `filePath`, which inference would "migrate" by
            // orphaning every book. With inference off, an incompatible store
            // throws here and the recovery screen takes over (decision #4 / #39):
            // pre-1.0, the store is recreated on the user's terms, never
            // rewritten under them. Re-enable inference only alongside a real
            // migration story.
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = false
        }

        container.loadPersistentStores { [weak self] storeDescription, error in
            if let error = error as NSError? {
                // Recovery-first (decision #4): leave the store file untouched,
                // surface the failure, and let the user decide. Do NOT fall
                // through — an app running against a store that failed to load
                // shows an empty library and loses data on the next write (#39).
                //
                // This store is loaded synchronously (local SQLite, no
                // `shouldAddStoreAsynchronously`), so the completion runs on the
                // calling thread during `init`, before the first `body` pass.
                // Assigning here means the recovery screen is shown from the
                // very first render — `ContentView` never mounts against the
                // half-open stack.
                Self.logger.fault("Core Data store failed to load: \(error.localizedDescription, privacy: .public) — \(String(describing: error.userInfo), privacy: .public)")
                self?.loadFailure = StoreLoadFailure(
                    underlyingError: error,
                    storeURL: storeDescription.url
                )
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Save the view context if there are changes
    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }

    /// Perform work on a background context
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Delete all data (for testing/reset)
    func deleteAllData() throws {
        let context = container.viewContext

        // Every entity in the model. Omitting one leaves its rows behind —
        // KindleDevice used to be missing, so "delete all data" kept the
        // configured Kindle devices (#46).
        let entities = ["Book", "Author", "Series", "Tag", "Collection", "KindleDevice"]

        var deletedObjectIDs: [NSManagedObjectID] = []
        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            let result = try container.persistentStoreCoordinator.execute(deleteRequest, with: context) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                deletedObjectIDs.append(contentsOf: objectIDs)
            }
        }

        // A batch delete writes straight to the store and never tells the
        // context, so anything already materialised (e.g. LibraryStore.books)
        // stays live and throws the next time it is touched. Merging the
        // deleted IDs turns those rows into deleted objects instead of leaving
        // them dangling (#46) — replaces the old blunt `context.reset()`.
        // The merge also drives LibraryStore's fetched-results controllers, so
        // the UI's book list empties without any manual reload.
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
            into: [container.viewContext]
        )
    }
}
