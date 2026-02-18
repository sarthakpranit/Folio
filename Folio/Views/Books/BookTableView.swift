//
// BookTableView.swift
// Folio
//
// Table view for displaying books in a sortable, column-based layout.
// Shows book metadata in columns: Title, Author, Year, Date Added, Formats, Size, Tags.
//
// Key Responsibilities:
// - Display books in a native macOS Table view
// - Support multi-selection via table selection
// - Show format badges with color coding
// - Handle context menu and double-click actions
//
// Usage:
//   BookTableView(
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

struct BookTableView: View {
    let books: [Book]
    let bookGroups: [BookGroup]
    @Binding var selectedBook: Book?
    @Binding var selectedBooks: Set<NSManagedObjectID>
    @Binding var isMultiSelectMode: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext

    @State private var selection: Set<String> = []
    @State private var showingGroupDetail: BookGroup?

    var body: some View {
        Table(bookGroups, selection: $selection) {
            TableColumn("Title") { group in
                Text(group.primaryBook.title ?? "Unknown")
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Author") { group in
                Text(authorText(for: group))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Year") { group in
                Text(yearText(for: group))
                    .foregroundColor(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Date Added") { group in
                Text(dateAddedText(for: group))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Formats") { group in
                formatsView(for: group)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Size") { group in
                Text(ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Tags") { group in
                Text(tagsText(for: group))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { selectedIds in
            if let groupId = selectedIds.first,
               let group = bookGroups.first(where: { $0.id == groupId }) {
                BookGroupContextMenuContent(
                    group: group,
                    libraryService: libraryService,
                    kindleDevices: kindleDevices,
                    viewContext: viewContext,
                    showingDetailFor: $showingGroupDetail
                )
            }
        } primaryAction: { selectedIds in
            // Double-click action - open book
            if let groupId = selectedIds.first,
               let group = bookGroups.first(where: { $0.id == groupId }),
               let book = group.preferredForReading {
                BookFileHelper.openInAppleBooks(book)
            }
        }
        .onChange(of: selection) { newSelection in
            // Sync table selection with app selection state
            selectedBooks.removeAll()
            for groupId in newSelection {
                if let group = bookGroups.first(where: { $0.id == groupId }) {
                    for book in group.books {
                        selectedBooks.insert(book.objectID)
                    }
                }
            }
            isMultiSelectMode = !selectedBooks.isEmpty
        }
        .sheet(item: $showingGroupDetail) { group in
            BookGroupDetailView(group: group, libraryService: libraryService, viewContext: viewContext)
        }
    }

    // MARK: - Helper Functions

    private func authorText(for group: BookGroup) -> String {
        if let authors = group.primaryBook.authors as? Set<Author>, !authors.isEmpty {
            return authors.compactMap { $0.name }.sorted().joined(separator: ", ")
        }
        return "—"
    }

    private func yearText(for group: BookGroup) -> String {
        if let date = group.primaryBook.publishedDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            return formatter.string(from: date)
        }
        return "—"
    }

    private func dateAddedText(for group: BookGroup) -> String {
        if let date = group.primaryBook.dateAdded {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return "—"
    }

    private func tagsText(for group: BookGroup) -> String {
        if let tags = group.primaryBook.tags as? Set<Tag>, !tags.isEmpty {
            return tags.compactMap { $0.name }.sorted().joined(separator: ", ")
        }
        return "—"
    }

    @ViewBuilder
    private func formatsView(for group: BookGroup) -> some View {
        HStack(spacing: 4) {
            ForEach(group.formats, id: \.self) { format in
                Text(format.uppercased())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(FormatStyle(format: format).color.opacity(0.15))
                    .foregroundColor(FormatStyle(format: format).color)
                    .clipShape(Capsule())
            }
        }
    }
}
