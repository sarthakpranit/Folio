//
// BookGridView.swift
// Folio
//
// Displays books in a responsive grid layout with adaptive columns.
// Books are grouped by content (ISBN or title) to show different formats
// of the same book together.
//
// Key Responsibilities:
// - Render books in a LazyVGrid with adaptive sizing
// - Handle single and multi-selection states
// - Support double-click to open in Apple Books
// - Show book group detail sheet for format selection
//
// Usage:
//   BookGridView(
//       books: displayedBooks,
//       bookGroups: displayedBookGroups,
//       selectedBook: $selectedBook,
//       selectedBooks: $selectedBooks,
//       isMultiSelectMode: $isMultiSelectMode,
//       libraryService: libraryService,
//       kindleDevices: Array(kindleDevices),
//       viewContext: viewContext
//   )
//

import SwiftUI
import CoreData

struct BookGridView: View {
    let books: [Book]
    let bookGroups: [BookGroup]
    @Binding var selectedBook: Book?
    @Binding var selectedBooks: Set<NSManagedObjectID>
    @Binding var isMultiSelectMode: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @State private var showingBookDetail: Book?
    @State private var showingGroupDetail: BookGroup?
    @State private var showingEditFor: BookGroup?

    /// Grid item size controlled by zoom level (persisted across sessions)
    @AppStorage("gridItemMinSize") private var gridItemMinSize: Double = 150

    /// Zoom step size for keyboard shortcuts
    private static let zoomStep: Double = 25
    private static let minZoom: Double = 100
    private static let maxZoom: Double = 300

    /// Dynamic columns based on zoom level
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: gridItemMinSize, maximum: gridItemMinSize * 1.33), spacing: 20, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(bookGroups) { group in
                    BookGroupGridItemView(
                        group: group,
                        isSelected: isGroupSelected(group),
                        isInMultiSelectMode: isMultiSelectMode,
                        isMultiSelected: isGroupMultiSelected(group),
                        libraryService: libraryService,
                        kindleDevices: kindleDevices,
                        viewContext: viewContext,
                        showingDetailFor: $showingGroupDetail,
                        showingEditFor: $showingEditFor
                    )
                    .onTapGesture(count: 2) {
                        if !isMultiSelectMode {
                            openBookInAppleBooks(group.preferredForReading ?? group.primaryBook)
                        }
                    }
                    .onTapGesture {
                        if isMultiSelectMode {
                            toggleGroupSelection(group)
                        } else {
                            selectedBook = group.primaryBook
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(item: $showingGroupDetail) { group in
            BookGroupDetailView(group: group, libraryService: libraryService, viewContext: viewContext)
        }
        .sheet(item: $showingEditFor) { group in
            BookMetadataEditView(book: group.primaryBook, libraryService: libraryService, viewContext: viewContext)
        }
    }

    private func isGroupSelected(_ group: BookGroup) -> Bool {
        group.books.contains { selectedBook == $0 || selectedBooks.contains($0.objectID) }
    }

    private func isGroupMultiSelected(_ group: BookGroup) -> Bool {
        group.books.contains { selectedBooks.contains($0.objectID) }
    }

    private func toggleGroupSelection(_ group: BookGroup) {
        // Toggle all books in the group together
        let allSelected = group.books.allSatisfy { selectedBooks.contains($0.objectID) }
        if allSelected {
            for book in group.books {
                selectedBooks.remove(book.objectID)
            }
        } else {
            for book in group.books {
                selectedBooks.insert(book.objectID)
            }
        }
    }

    /// Opens the book in Apple Books app
    private func openBookInAppleBooks(_ book: Book) {
        BookFileHelper.openInAppleBooks(book)
    }
}
