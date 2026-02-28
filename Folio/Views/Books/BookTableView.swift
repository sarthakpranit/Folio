//
// BookTableView.swift
// Folio
//
// Table view for displaying books in a sortable, column-based layout.
// Shows book metadata in columns: Title, Author, Year, Date Added, Formats, Size, Tags.
//
// Key Responsibilities:
// - Display books in a native macOS Table view with sortable column headers
// - Support multi-selection via table selection
// - Show format badges with color coding
// - Handle context menu and double-click actions
// - Communicate sort changes back to ContentView via bindings
//

import SwiftUI
import CoreData

struct BookTableView: View {
    let books: [Book]
    let bookGroups: [BookGroup]
    @Binding var selectedBook: Book?
    @Binding var selectedBooks: Set<NSManagedObjectID>
    @Binding var isMultiSelectMode: Bool
    @Binding var currentSortOption: SortOption
    @Binding var sortAscending: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext

    @State private var selection: Set<String> = []
    @State private var showingGroupDetail: BookGroup?
    @State private var showingEditFor: BookGroup?
    @State private var sortOrder: [KeyPathComparator<BookGroup>] = [
        KeyPathComparator(\.sortableTitle, order: .forward)
    ]

    var body: some View {
        tableContent
            .onChange(of: selection) { newSelection in
                syncSelection(newSelection)
            }
            .onChange(of: sortOrder) { newOrder in
                applySortOrder(newOrder)
            }
            .onAppear {
                // Initialize sortOrder from current sort state
                syncSortOrderFromOption()
            }
            .onChange(of: currentSortOption) { _ in
                syncSortOrderFromOption()
            }
            .onChange(of: sortAscending) { _ in
                syncSortOrderFromOption()
            }
            .sheet(item: $showingGroupDetail) { group in
                BookGroupDetailView(group: group, libraryService: libraryService, viewContext: viewContext)
            }
    }

    private var tableContent: some View {
        Table(bookGroups, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.sortableTitle) { (group: BookGroup) in
                Text(group.primaryBook.title ?? "Unknown")
                    .lineLimit(1)
            }
            .width(min: 150, ideal: 250)

            TableColumn("Author", value: \.sortableAuthor) { (group: BookGroup) in
                Text(authorText(for: group))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Year") { (group: BookGroup) in
                Text(yearText(for: group))
                    .foregroundColor(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Date Added", value: \.sortableDateAdded) { (group: BookGroup) in
                Text(dateAddedText(for: group))
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Formats") { (group: BookGroup) in
                formatsView(for: group)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Size", value: \.sortableSize) { (group: BookGroup) in
                Text(sizeText(for: group))
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

            TableColumn("Tags") { (group: BookGroup) in
                Text(tagsText(for: group))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { selectedIds in
            contextMenuContent(for: selectedIds)
        } primaryAction: { selectedIds in
            handlePrimaryAction(selectedIds)
        }
    }

    // MARK: - Sort Synchronization

    /// Map a column header click (KeyPathComparator) back to SortOption + ascending
    private func applySortOrder(_ newOrder: [KeyPathComparator<BookGroup>]) {
        guard let first = newOrder.first else { return }
        let ascending = first.order == .forward

        // Map keypath to SortOption
        let newOption: SortOption
        switch first.keyPath {
        case \BookGroup.sortableTitle:
            newOption = .title
        case \BookGroup.sortableAuthor:
            newOption = .author
        case \BookGroup.sortableDateAdded:
            newOption = .dateAdded
        case \BookGroup.sortableSize:
            newOption = .fileSize
        default:
            return
        }

        // Only update if actually changed (avoid feedback loop)
        if newOption != currentSortOption || ascending != sortAscending {
            currentSortOption = newOption
            sortAscending = ascending
        }
    }

    /// Sync the table's sortOrder state from ContentView's SortOption
    private func syncSortOrderFromOption() {
        let order: SortOrder = sortAscending ? .forward : .reverse

        let comparator: KeyPathComparator<BookGroup>
        switch currentSortOption {
        case .title:
            comparator = KeyPathComparator(\.sortableTitle, order: order)
        case .author:
            comparator = KeyPathComparator(\.sortableAuthor, order: order)
        case .dateAdded:
            comparator = KeyPathComparator(\.sortableDateAdded, order: order)
        case .recentlyOpened:
            comparator = KeyPathComparator(\.sortableDateAdded, order: order)
        case .fileSize:
            comparator = KeyPathComparator(\.sortableSize, order: order)
        }

        if sortOrder.first?.keyPath != comparator.keyPath || sortOrder.first?.order != comparator.order {
            sortOrder = [comparator]
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private func contextMenuContent(for selectedIds: Set<String>) -> some View {
        if let groupId = selectedIds.first,
           let group = bookGroups.first(where: { $0.id == groupId }) {
            BookGroupContextMenuContent(
                group: group,
                libraryService: libraryService,
                kindleDevices: kindleDevices,
                viewContext: viewContext,
                showingDetailFor: $showingGroupDetail,
                showingEditFor: $showingEditFor
            )
        }
    }

    private func handlePrimaryAction(_ selectedIds: Set<String>) {
        if let groupId = selectedIds.first,
           let group = bookGroups.first(where: { $0.id == groupId }),
           let book = group.preferredForReading {
            BookFileHelper.openInAppleBooks(book)
        }
    }

    private func syncSelection(_ newSelection: Set<String>) {
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

    private func sizeText(for group: BookGroup) -> String {
        ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file)
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
