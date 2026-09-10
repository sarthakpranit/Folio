//
//  LibraryStore.swift
//  Folio
//
//  LibraryStore is the single source of truth for the library's fetched entity
//  lists (books, authors, series, tags).
//
//  Before this, LibraryService held @Published book/author/series/tag arrays and
//  reloaded them by hand (loadAll() + objectWillChange.send()) after every
//  mutation, while ContentView and SidebarView ran their own @FetchRequest over
//  the same store. Two parallel lists, kept in sync only because both observed
//  Core Data (#47).
//
//  Now one NSFetchedResultsController per entity feeds these @Published arrays.
//  Any save on the view context — including background-context imports merged in
//  via automaticallyMergesChangesFromParent, and batch deletes merged via
//  NSManagedObjectContext.mergeChanges — updates them automatically. No caller
//  ever asks the store to reload.
//
//  Scope: this owns *what* the library contains. Filtering, sorting, grouping,
//  search debouncing and selection remain in the view layer for now (#118, #92).
//
//  Usage:
//    @EnvironmentObject var store: LibraryStore   // in views
//    LibraryStore.shared.books                    // non-view callers
//

import Foundation
import Combine
import CoreData
import OSLog

/// Single source of truth for the library's fetched entity lists.
@MainActor
final class LibraryStore: NSObject, ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var books: [Book] = []
    @Published private(set) var authors: [Author] = []
    @Published private(set) var series: [Series] = []
    @Published private(set) var tags: [Tag] = []

    private let booksController: NSFetchedResultsController<Book>
    private let authorsController: NSFetchedResultsController<Author>
    private let seriesController: NSFetchedResultsController<Series>
    private let tagsController: NSFetchedResultsController<Tag>

    private let logger = Logger(subsystem: "com.folio", category: "LibraryStore")

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        // Sort descriptors match what BookRepository.fetchAll*() used before the
        // move, so ordering the UI already depends on is unchanged.
        booksController = Self.makeController(
            for: Book.fetchRequest(),
            sortedBy: [NSSortDescriptor(keyPath: \Book.dateAdded, ascending: false)],
            in: context
        )
        authorsController = Self.makeController(
            for: Author.fetchRequest(),
            sortedBy: [NSSortDescriptor(keyPath: \Author.sortName, ascending: true)],
            in: context
        )
        seriesController = Self.makeController(
            for: Series.fetchRequest(),
            sortedBy: [NSSortDescriptor(keyPath: \Series.name, ascending: true)],
            in: context
        )
        tagsController = Self.makeController(
            for: Tag.fetchRequest(),
            sortedBy: [NSSortDescriptor(keyPath: \Tag.name, ascending: true)],
            in: context
        )

        super.init()

        booksController.delegate = self
        authorsController.delegate = self
        seriesController.delegate = self
        tagsController.delegate = self

        performInitialFetch()
    }

    private static func makeController<T: NSManagedObject>(
        for request: NSFetchRequest<T>,
        sortedBy sortDescriptors: [NSSortDescriptor],
        in context: NSManagedObjectContext
    ) -> NSFetchedResultsController<T> {
        request.sortDescriptors = sortDescriptors
        return NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }

    private func performInitialFetch() {
        do {
            try booksController.performFetch()
            try authorsController.performFetch()
            try seriesController.performFetch()
            try tagsController.performFetch()
        } catch {
            logger.error("Initial fetch failed: \(error.localizedDescription, privacy: .public)")
        }
        books = booksController.fetchedObjects ?? []
        authors = authorsController.fetchedObjects ?? []
        series = seriesController.fetchedObjects ?? []
        tags = tagsController.fetchedObjects ?? []
    }
}

extension LibraryStore: NSFetchedResultsControllerDelegate {
    /// Republish only the list that actually changed, so an author/series/tag
    /// edit does not invalidate `books` (and the view-layer filter/sort/group
    /// pipeline that reads it — #118).
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if controller === booksController {
            books = booksController.fetchedObjects ?? []
        } else if controller === authorsController {
            authors = authorsController.fetchedObjects ?? []
        } else if controller === seriesController {
            series = seriesController.fetchedObjects ?? []
        } else if controller === tagsController {
            tags = tagsController.fetchedObjects ?? []
        }
    }
}
