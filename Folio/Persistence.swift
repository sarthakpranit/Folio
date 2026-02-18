//
//  Persistence.swift
//  Folio
//
//  Core Data stack with CloudKit sync support
//

import CoreData
import CloudKit
import Combine

class PersistenceController: ObservableObject {
    @MainActor static let shared = PersistenceController()

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

    let container: NSPersistentCloudKitContainer

    /// Sync status
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Folio")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        } else {
            // Configure CloudKit sync (disabled for now until entitlements are set up)
            // Uncomment when CloudKit container is configured:
            // description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            //     containerIdentifier: "iCloud.com.folio.ebooks"
            // )

            // Enable persistent history tracking (required for CloudKit)
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                // Log the error but don't crash in production
                print("Core Data store failed to load: \(error), \(error.userInfo)")

                #if DEBUG
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
                #endif
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Observe remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processRemoteStoreChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    @objc private func processRemoteStoreChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.isSyncing = false
            self?.lastSyncDate = Date()
        }
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

        let entities = ["Book", "Author", "Series", "Tag", "Collection"]
        for entityName in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try container.persistentStoreCoordinator.execute(deleteRequest, with: context)
        }

        context.reset()
    }
}
