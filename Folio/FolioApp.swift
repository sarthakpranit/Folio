//
//  FolioApp.swift
//  Folio
//
//  Created by Sarthak Pranit on 14/12/2025.
//

import SwiftUI
import CoreData
import FolioCore

@main
struct FolioApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var libraryService = LibraryService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
        .commands {
            // File menu additions
            CommandGroup(after: .newItem) {
                Divider()

                Button("Fetch Missing Metadata") {
                    Task {
                        await fetchMissingMetadata()
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Clean All Titles") {
                    cleanAllTitles()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }
    }

    /// Fetch metadata for books that don't have cover images or complete metadata
    @MainActor
    private func fetchMissingMetadata() async {
        let books = libraryService.books.filter { book in
            // Books missing cover image or summary are considered to need metadata
            book.coverImageData == nil || book.summary == nil || book.summary?.isEmpty == true
        }

        guard !books.isEmpty else {
            ToastNotificationManager.shared.show(
                title: "All Books Complete",
                message: "All books already have metadata"
            )
            return
        }

        ToastNotificationManager.shared.show(
            title: "Fetching Metadata",
            message: "Updating \(books.count) book(s)..."
        )

        let metadataService = MetadataService()
        var successCount = 0
        var failCount = 0

        for book in books {
            let title = book.title ?? ""
            let authorName = (book.authors as? Set<Author>)?.first?.name

            do {
                let results = try await metadataService.fetchMetadata(title: title, author: authorName)
                if let metadata = results.first {
                    // Update book with fetched metadata
                    if let isbn = metadata.isbn { book.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { book.publisher = publisher }
                    if let summary = metadata.summary { book.summary = summary }
                    if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                    if let language = metadata.language { book.language = language }

                    // Create and link Author entities
                    if !metadata.authors.isEmpty {
                        book.authors = nil
                        for authorName in metadata.authors {
                            let author = libraryService.findOrCreateAuthor(name: authorName)
                            book.addToAuthors(author)
                        }
                    }

                    // Create and link Series entity
                    if let seriesName = metadata.series, !seriesName.isEmpty {
                        let series = libraryService.findOrCreateSeries(name: seriesName)
                        book.series = series
                        if let index = metadata.seriesIndex {
                            book.seriesIndex = index
                        }
                    }

                    // Create and link Tag entities
                    if !metadata.tags.isEmpty {
                        for tagName in metadata.tags {
                            let tag = libraryService.findOrCreateTag(name: tagName)
                            book.addToTags(tag)
                        }
                    }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        book.coverImageURL = coverURL
                        if let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                            book.coverImageData = data
                        }
                    }

                    try? book.managedObjectContext?.save()
                    successCount += 1
                } else {
                    failCount += 1
                }
            } catch {
                failCount += 1
                print("Failed to fetch metadata for \(title): \(error)")
            }
        }

        libraryService.refresh()

        ToastNotificationManager.shared.show(
            title: "Metadata Complete",
            message: "Updated \(successCount) book(s), \(failCount) failed"
        )
    }

    /// Clean all book titles by extracting embedded author names
    @MainActor
    private func cleanAllTitles() {
        let result = libraryService.cleanupBookTitles()

        if result.titlesFixed > 0 {
            ToastNotificationManager.shared.show(
                title: "Titles Cleaned",
                message: "Fixed \(result.titlesFixed) of \(result.booksProcessed) book(s), extracted \(result.authorsExtracted) author(s)"
            )
        } else {
            ToastNotificationManager.shared.show(
                title: "No Changes",
                message: "No embedded author names found in \(result.booksProcessed) books"
            )
        }
    }
}
