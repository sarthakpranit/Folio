//
//  ContentView.swift
//  Folio
//
//  Main content view with sidebar navigation and book grid
//

import SwiftUI
import CoreData
import FolioCore
import Combine

// MARK: - Book File Helper

/// Shared utility for handling security-scoped file access
/// Used across views to properly access books on external volumes
enum BookFileHelper {

    /// Opens a book file in Apple Books app, handling security-scoped bookmarks
    /// - Parameters:
    ///   - book: The book to open
    ///   - updateLastOpened: Whether to update the lastOpened date (default: true)
    static func openInAppleBooks(_ book: Book, updateLastOpened: Bool = true) {
        guard let fileURL = book.fileURL else { return }

        // Resolve security-scoped bookmark to get access to the file
        guard let (accessibleURL, didStartAccessing) = resolveSecurityScopedURL(for: book) else {
            print("Could not resolve security-scoped access for: \(fileURL.lastPathComponent)")
            return
        }

        // Copy to a temp location first (most reliable approach for sandboxed apps)
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileURL.lastPathComponent)

        do {
            // Remove existing temp file if any
            try? FileManager.default.removeItem(at: tempURL)

            // Copy to temp while we have security access
            try FileManager.default.copyItem(at: accessibleURL, to: tempURL)

            // Stop accessing the security-scoped resource
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }

            // Open the temp copy with Apple Books
            let booksAppURL = URL(fileURLWithPath: "/System/Applications/Books.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.open(
                [tempURL],
                withApplicationAt: booksAppURL,
                configuration: configuration
            ) { _, error in
                if let error = error {
                    print("Failed to open in Books: \(error)")
                    // Fallback: try default app
                    NSWorkspace.shared.open(tempURL)
                }
            }

            print("Opened book from temp copy: \(tempURL)")

        } catch {
            // Stop accessing on error
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }

            print("Failed to copy book to temp: \(error)")

            // Last resort: try to open directly (may not work for external volumes)
            NSWorkspace.shared.open(accessibleURL)
        }

        // Update last opened date
        if updateLastOpened {
            book.lastOpened = Date()
            try? book.managedObjectContext?.save()
        }
    }

    /// Resolve security-scoped URL from a book's bookmark data
    /// - Parameter book: The book whose file URL to resolve
    /// - Returns: Tuple of (accessibleURL, didStartAccessing) or nil if resolution fails
    static func resolveSecurityScopedURL(for book: Book) -> (URL, Bool)? {
        guard let fileURL = book.fileURL else { return nil }

        // First, try to resolve from stored bookmark data
        if let bookmarkData = book.bookmarkData {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                if resolvedURL.startAccessingSecurityScopedResource() {
                    // Update bookmark if stale
                    if isStale {
                        if let newBookmarkData = try? resolvedURL.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        ) {
                            book.bookmarkData = newBookmarkData
                            try? book.managedObjectContext?.save()
                            print("Updated stale bookmark for: \(fileURL.lastPathComponent)")
                        }
                    }
                    return (resolvedURL, true)
                }
            } catch {
                print("Failed to resolve bookmark: \(error)")
            }
        }

        // Fallback: try direct access (only works for files in accessible locations)
        if fileURL.startAccessingSecurityScopedResource() {
            return (fileURL, true)
        }

        // No access possible
        print("No security-scoped access available for: \(fileURL.lastPathComponent)")
        return nil
    }
}

// MARK: - Sort Options

enum SortOption: String, CaseIterable, Identifiable {
    case title = "Title"
    case author = "Author"
    case dateAdded = "Date Added"
    case recentlyOpened = "Recently Opened"
    case fileSize = "File Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .author: return "person"
        case .dateAdded: return "calendar.badge.plus"
        case .recentlyOpened: return "clock"
        case .fileSize: return "doc"
        }
    }

    func sortDescriptor(ascending: Bool = true) -> NSSortDescriptor {
        switch self {
        case .title:
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .author:
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .dateAdded:
            return NSSortDescriptor(keyPath: \Book.dateAdded, ascending: !ascending)
        case .recentlyOpened:
            return NSSortDescriptor(keyPath: \Book.lastOpened, ascending: !ascending)
        case .fileSize:
            return NSSortDescriptor(keyPath: \Book.fileSize, ascending: !ascending)
        }
    }
}

// MARK: - Sidebar Selection

enum SidebarItem: Hashable {
    case allBooks
    case recentlyAdded
    case recentlyOpened
    case authors
    case series
    case tags
    case format(String)
    case author(Author)
    case singleSeries(Series)
    case tag(Tag)
    case kindleDevice(KindleDevice)
    case kindleDevices
}

// MARK: - Main Content View

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var libraryService = LibraryService.shared

    @FetchRequest(
        entity: Book.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.dateAdded, ascending: false)],
        predicate: nil,
        animation: .default)
    private var books: FetchedResults<Book>

    @FetchRequest(
        entity: KindleDevice.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \KindleDevice.name, ascending: true)],
        animation: .default)
    private var kindleDevices: FetchedResults<KindleDevice>

    @State private var selectedSidebarItem: SidebarItem? = .allBooks
    @State private var searchText = ""
    @State private var selectedBook: Book?
    @State private var selectedBooks: Set<NSManagedObjectID> = []
    @State private var isMultiSelectMode = false
    @State private var isDropTargeted = false
    @State private var showingImportResult = false
    @State private var importResult: ImportResult?
    @State private var refreshID = UUID()

    // Sorting
    @State private var currentSortOption: SortOption = .dateAdded
    @State private var sortAscending = false

    // Conversion & Send to Kindle
    @State private var isConverting = false
    @State private var conversionProgress: Double = 0
    @State private var conversionStatus: String = ""
    @State private var showingConversionAlert = false
    @State private var conversionAlertMessage = ""
    @State private var showingSendToKindleSheet = false
    @State private var showingKindleSettings = false
    @State private var showingAddKindleDevice = false

    // Batch operations
    @State private var showingBatchDeleteConfirmation = false

    var displayedBooks: [Book] {
        var result = Array(books)

        // Apply sidebar filter
        switch selectedSidebarItem {
        case .allBooks, .none:
            break
        case .recentlyAdded:
            // Last 30 days
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            result = result.filter { ($0.dateAdded ?? Date.distantPast) > thirtyDaysAgo }
        case .recentlyOpened:
            result = result.filter { $0.lastOpened != nil }
                .sorted { ($0.lastOpened ?? .distantPast) > ($1.lastOpened ?? .distantPast) }
        case .format(let format):
            result = result.filter { $0.format == format }
        case .author(let author):
            result = result.filter { book in
                guard let bookAuthors = book.authors as? Set<Author> else { return false }
                return bookAuthors.contains(author)
            }
        case .singleSeries(let series):
            result = result.filter { $0.series == series }
        case .tag(let tag):
            result = result.filter { book in
                guard let bookTags = book.tags as? Set<Tag> else { return false }
                return bookTags.contains(tag)
            }
        case .kindleDevice(let device):
            result = result.filter { book in
                guard let kindleDevices = book.kindleDevices as? Set<KindleDevice> else { return false }
                return kindleDevices.contains(device)
            }
        case .kindleDevices:
            // Show all books that are on any Kindle
            result = result.filter { book in
                guard let kindleDevices = book.kindleDevices as? Set<KindleDevice> else { return false }
                return !kindleDevices.isEmpty
            }
        case .authors, .series, .tags:
            // These show list views, not book grids
            break
        }

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { book in
                if book.title?.lowercased().contains(query) == true { return true }
                if let authors = book.authors as? Set<Author> {
                    for author in authors {
                        if author.name?.lowercased().contains(query) == true { return true }
                    }
                }
                return false
            }
        }

        // Apply sorting
        result = sortBooks(result)

        return result
    }

    /// Sort books based on current sort option
    private func sortBooks(_ books: [Book]) -> [Book] {
        switch currentSortOption {
        case .title:
            return books.sorted {
                let t1 = $0.sortTitle ?? $0.title ?? ""
                let t2 = $1.sortTitle ?? $1.title ?? ""
                return sortAscending ? t1 < t2 : t1 > t2
            }
        case .author:
            return books.sorted {
                let a1 = ($0.authors as? Set<Author>)?.first?.sortName ?? ""
                let a2 = ($1.authors as? Set<Author>)?.first?.sortName ?? ""
                return sortAscending ? a1 < a2 : a1 > a2
            }
        case .dateAdded:
            return books.sorted {
                let d1 = $0.dateAdded ?? Date.distantPast
                let d2 = $1.dateAdded ?? Date.distantPast
                return sortAscending ? d1 < d2 : d1 > d2
            }
        case .recentlyOpened:
            return books.sorted {
                let d1 = $0.lastOpened ?? Date.distantPast
                let d2 = $1.lastOpened ?? Date.distantPast
                return sortAscending ? d1 < d2 : d1 > d2
            }
        case .fileSize:
            return books.sorted {
                return sortAscending ? $0.fileSize < $1.fileSize : $0.fileSize > $1.fileSize
            }
        }
    }

    /// Get selected Book objects from their ObjectIDs
    var selectedBookObjects: [Book] {
        books.filter { selectedBooks.contains($0.objectID) }
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            FileImportButton(libraryService: libraryService)
            WiFiTransferButton(libraryService: libraryService)
        }

        ToolbarItem(placement: .automatic) {
            multiSelectToggle
        }

        ToolbarItem(placement: .automatic) {
            batchActionsMenu
        }

        ToolbarItem(placement: .automatic) {
            sortMenu
        }

        ToolbarItem(placement: .automatic) {
            kindleMenu
        }
    }

    private var multiSelectToggle: some View {
        Toggle(isOn: $isMultiSelectMode) {
            Label("Select", systemImage: isMultiSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
        }
        .toggleStyle(.button)
        .help("Toggle multi-select mode")
        .onChange(of: isMultiSelectMode) { newValue in
            if !newValue {
                selectedBooks.removeAll()
            }
        }
    }

    @ViewBuilder
    private var batchActionsMenu: some View {
        if !selectedBooks.isEmpty {
            Menu {
                Button(role: .destructive) {
                    showingBatchDeleteConfirmation = true
                } label: {
                    Label("Delete \(selectedBooks.count) Book(s)", systemImage: "trash")
                }

                Divider()

                Button {
                    Task { await batchFetchMetadata() }
                } label: {
                    Label("Fetch Metadata", systemImage: "arrow.clockwise")
                }

                Menu("Convert to...") {
                    Button("EPUB") { Task { await batchConvert(to: "epub") } }
                    Button("MOBI") { Task { await batchConvert(to: "mobi") } }
                    Button("PDF") { Task { await batchConvert(to: "pdf") } }
                    Button("AZW3") { Task { await batchConvert(to: "azw3") } }
                }

                if let defaultKindle = kindleDevices.first(where: { $0.isDefault }) ?? kindleDevices.first {
                    Button {
                        Task { await batchSendToKindle(device: defaultKindle) }
                    } label: {
                        Label("Send to \(defaultKindle.name ?? "Kindle")", systemImage: "paperplane")
                    }
                }
            } label: {
                Label("\(selectedBooks.count) Selected", systemImage: "square.stack.3d.up")
            }
        } else {
            EmptyView()
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    if currentSortOption == option {
                        sortAscending.toggle()
                    } else {
                        currentSortOption = option
                        sortAscending = option == .title || option == .author
                    }
                } label: {
                    if currentSortOption == option {
                        Label(option.rawValue, systemImage: sortAscending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }

            Divider()

            Button {
                sortAscending.toggle()
            } label: {
                Label(sortAscending ? "Ascending" : "Descending",
                      systemImage: sortAscending ? "arrow.up" : "arrow.down")
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    private var kindleMenu: some View {
        Menu {
            if kindleDevices.isEmpty {
                Button {
                    showingAddKindleDevice = true
                } label: {
                    Label("Add Kindle Device", systemImage: "plus")
                }
            } else {
                ForEach(kindleDevices, id: \.objectID) { device in
                    Button {
                        selectedSidebarItem = .kindleDevice(device)
                    } label: {
                        Text(device.name ?? "Kindle")
                    }
                }

                Divider()

                Button {
                    showingAddKindleDevice = true
                } label: {
                    Label("Add Kindle Device", systemImage: "plus")
                }

                Button {
                    showingKindleSettings = true
                } label: {
                    Label("Kindle Settings", systemImage: "gear")
                }
            }
        } label: {
            Label("Kindle", systemImage: "flame")
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                libraryService: libraryService,
                selection: $selectedSidebarItem,
                kindleDevices: Array(kindleDevices)
            )
        } detail: {
            detailView
                .onDrop(
                    of: ImportDropDelegate.supportedTypes,
                    delegate: ImportDropDelegate(
                        libraryService: libraryService,
                        isTargeted: $isDropTargeted,
                        onImportComplete: { result in
                            importResult = result
                            showingImportResult = true
                        }
                    )
                )
        }
        .searchable(text: $searchText, prompt: "Search books...")
        .toolbar {
            toolbarContent
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text(result.summary)
            }
        }
        .alert("Conversion", isPresented: $showingConversionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(conversionAlertMessage)
        }
        .alert("Delete \(selectedBooks.count) Book(s)?", isPresented: $showingBatchDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                batchDeleteBooks()
            }
        } message: {
            Text("This action cannot be undone. The books will be removed from your library.")
        }
        .sheet(isPresented: $showingAddKindleDevice) {
            AddKindleDeviceView(viewContext: viewContext)
        }
        .sheet(isPresented: $showingKindleSettings) {
            KindleSettingsView(viewContext: viewContext, kindleDevices: Array(kindleDevices))
        }
        .sheet(isPresented: $showingSendToKindleSheet) {
            if let book = selectedBook {
                SendToKindleView(book: book, kindleDevices: Array(kindleDevices), viewContext: viewContext)
            }
        }
        .overlay {
            if isConverting {
                ConversionProgressOverlay(progress: conversionProgress, status: conversionStatus)
            }
        }
        .navigationTitle(navigationTitle)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
            refreshID = UUID()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            switch selectedSidebarItem {
            case .authors:
                AuthorListView(authors: libraryService.authors, selection: $selectedSidebarItem)
            case .series:
                SeriesListView(series: libraryService.series, selection: $selectedSidebarItem)
            case .tags:
                TagListView(tags: libraryService.tags, selection: $selectedSidebarItem)
            default:
                if books.isEmpty {
                    EmptyLibraryView(libraryService: libraryService)
                } else if displayedBooks.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No books match your filter")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                } else {
                    BookGridView(
                        books: displayedBooks,
                        selectedBook: $selectedBook,
                        selectedBooks: $selectedBooks,
                        isMultiSelectMode: $isMultiSelectMode,
                        libraryService: libraryService,
                        kindleDevices: Array(kindleDevices),
                        viewContext: viewContext
                    )
                }
            }

            // Drop overlay
            DropOverlayView(isTargeted: isDropTargeted)
        }
    }

    private var navigationTitle: String {
        switch selectedSidebarItem {
        case .allBooks, .none:
            return "All Books"
        case .recentlyAdded:
            return "Recently Added"
        case .recentlyOpened:
            return "Recently Opened"
        case .authors:
            return "Authors"
        case .series:
            return "Series"
        case .tags:
            return "Tags"
        case .format(let format):
            return "\(format.uppercased()) Books"
        case .author(let author):
            return author.name ?? "Unknown Author"
        case .singleSeries(let series):
            return series.name ?? "Unknown Series"
        case .tag(let tag):
            return tag.name ?? "Unknown Tag"
        case .kindleDevice(let device):
            return "On \(device.name ?? "Kindle")"
        case .kindleDevices:
            return "All Kindle Books"
        }
    }

    // MARK: - Batch Operations

    private func batchDeleteBooks() {
        let booksToDelete = selectedBookObjects
        do {
            try libraryService.deleteBooks(booksToDelete, deleteFiles: false)
            selectedBooks.removeAll()
            isMultiSelectMode = false
        } catch {
            print("Failed to delete books: \(error)")
        }
    }

    private func batchFetchMetadata() async {
        let booksToUpdate = selectedBookObjects
        let metadataService = MetadataService()

        for book in booksToUpdate {
            let title = book.title ?? ""
            let authorName = (book.authors as? Set<Author>)?.first?.name

            do {
                let results = try await metadataService.fetchMetadata(title: title, author: authorName)
                if let metadata = results.first {
                    await MainActor.run {
                        if let isbn = metadata.isbn { book.isbn = isbn }
                        if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                        if let publisher = metadata.publisher { book.publisher = publisher }
                        if let summary = metadata.summary { book.summary = summary }
                        if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                        if let language = metadata.language { book.language = language }

                        if let coverURL = metadata.coverImageURL {
                            book.coverImageURL = coverURL
                            Task {
                                if let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                                    await MainActor.run {
                                        book.coverImageData = data
                                        try? book.managedObjectContext?.save()
                                    }
                                }
                            }
                        }

                        try? book.managedObjectContext?.save()
                    }
                }
            } catch {
                print("Failed to fetch metadata for \(title): \(error)")
            }
        }

        selectedBooks.removeAll()
        isMultiSelectMode = false
    }

    private func batchConvert(to format: String) async {
        let booksToConvert = selectedBookObjects
        let conversionService = CalibreConversionService.shared

        guard conversionService.isCalibreAvailable else {
            conversionAlertMessage = "Calibre is not installed. Please install Calibre to convert ebooks."
            showingConversionAlert = true
            return
        }

        isConverting = true
        var successCount = 0
        var failCount = 0

        for (index, book) in booksToConvert.enumerated() {
            guard let fileURL = book.fileURL else { continue }

            await MainActor.run {
                conversionProgress = Double(index) / Double(booksToConvert.count)
                conversionStatus = "Converting \(book.title ?? "book") to \(format.uppercased())..."
            }

            do {
                let outputURL = try await conversionService.convert(fileURL, to: format)

                // Add the converted book to library
                await MainActor.run {
                    do {
                        try libraryService.addBook(from: outputURL)
                        successCount += 1
                    } catch {
                        failCount += 1
                    }
                }
            } catch {
                failCount += 1
                print("Conversion failed for \(book.title ?? "book"): \(error)")
            }
        }

        await MainActor.run {
            isConverting = false
            conversionAlertMessage = "Converted \(successCount) book(s) successfully. \(failCount > 0 ? "\(failCount) failed." : "")"
            showingConversionAlert = true
            selectedBooks.removeAll()
            isMultiSelectMode = false
        }
    }

    private func batchSendToKindle(device: KindleDevice) async {
        guard let kindleEmail = device.email else {
            conversionAlertMessage = "No Kindle email configured for \(device.name ?? "device")."
            showingConversionAlert = true
            return
        }

        let sendService = SendToKindleService.shared
        let isConfigured = await sendService.isConfigured

        guard isConfigured else {
            conversionAlertMessage = "SMTP email not configured. Please configure email settings first."
            showingConversionAlert = true
            return
        }

        let booksToSend = selectedBookObjects
        var successCount = 0
        var failCount = 0

        for book in booksToSend {
            guard let fileURL = book.fileURL else { continue }

            do {
                let result = try await sendService.send(
                    fileURL: fileURL,
                    to: kindleEmail,
                    bookTitle: book.title ?? "Untitled"
                )

                if result.success {
                    successCount += 1
                    // Mark book as synced to this device
                    await MainActor.run {
                        book.addToKindleDevices(device)
                        device.lastSyncDate = Date()
                        try? viewContext.save()
                    }
                } else {
                    failCount += 1
                }
            } catch {
                failCount += 1
                print("Failed to send \(book.title ?? "book") to Kindle: \(error)")
            }
        }

        await MainActor.run {
            conversionAlertMessage = "Sent \(successCount) book(s) to Kindle. \(failCount > 0 ? "\(failCount) failed." : "")"
            showingConversionAlert = true
            selectedBooks.removeAll()
            isMultiSelectMode = false
        }
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var libraryService: LibraryService
    @Binding var selection: SidebarItem?
    var kindleDevices: [KindleDevice]

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Books", systemImage: "books.vertical")
                    .badge(libraryService.books.count)
                    .tag(SidebarItem.allBooks)

                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarItem.recentlyAdded)

                Label("Recently Opened", systemImage: "book")
                    .tag(SidebarItem.recentlyOpened)
            }

            Section("Browse") {
                Label("Authors", systemImage: "person.2")
                    .badge(libraryService.authors.count)
                    .tag(SidebarItem.authors)

                Label("Series", systemImage: "text.book.closed")
                    .badge(libraryService.series.count)
                    .tag(SidebarItem.series)

                Label("Tags", systemImage: "tag")
                    .badge(libraryService.tags.count)
                    .tag(SidebarItem.tags)
            }

            if !kindleDevices.isEmpty {
                Section("Kindle Devices") {
                    ForEach(kindleDevices, id: \.objectID) { device in
                        HStack {
                            Label(device.name ?? "Kindle", systemImage: "flame")
                            if device.isDefault {
                                Spacer()
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .badge((device.syncedBooks as? Set<Book>)?.count ?? 0)
                        .tag(SidebarItem.kindleDevice(device))
                    }
                }
            }

            if !libraryService.statistics.formatCounts.isEmpty {
                Section("Formats") {
                    ForEach(Array(libraryService.statistics.formatCounts.keys.sorted()), id: \.self) { format in
                        Label(format.uppercased(), systemImage: formatIcon(for: format))
                            .badge(libraryService.statistics.formatCounts[format] ?? 0)
                            .tag(SidebarItem.format(format))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Folio")
    }

    private func formatIcon(for format: String) -> String {
        switch format.lowercased() {
        case "epub": return "doc.richtext"
        case "pdf": return "doc.text"
        case "mobi", "azw3": return "doc.plaintext"
        case "cbz", "cbr": return "photo.on.rectangle"
        default: return "doc"
        }
    }
}

// MARK: - Book Grid View

struct BookGridView: View {
    let books: [Book]
    @Binding var selectedBook: Book?
    @Binding var selectedBooks: Set<NSManagedObjectID>
    @Binding var isMultiSelectMode: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @State private var showingBookDetail: Book?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books, id: \.objectID) { book in
                    BookGridItemView(
                        book: book,
                        isSelected: selectedBook == book || selectedBooks.contains(book.objectID),
                        isInMultiSelectMode: isMultiSelectMode,
                        isMultiSelected: selectedBooks.contains(book.objectID),
                        libraryService: libraryService,
                        kindleDevices: kindleDevices,
                        viewContext: viewContext,
                        showingDetailFor: $showingBookDetail
                    )
                    .onTapGesture(count: 2) {
                        if !isMultiSelectMode {
                            openBookInAppleBooks(book)
                        }
                    }
                    .onTapGesture {
                        if isMultiSelectMode {
                            toggleSelection(book)
                        } else {
                            selectedBook = book
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(item: $showingBookDetail) { book in
            BookDetailView(book: book, libraryService: libraryService)
        }
    }

    private func toggleSelection(_ book: Book) {
        if selectedBooks.contains(book.objectID) {
            selectedBooks.remove(book.objectID)
        } else {
            selectedBooks.insert(book.objectID)
        }
    }

    /// Opens the book in Apple Books app
    private func openBookInAppleBooks(_ book: Book) {
        BookFileHelper.openInAppleBooks(book)
    }
}

// MARK: - Book Grid Item

struct BookGridItemView: View {
    @ObservedObject var book: Book
    let isSelected: Bool
    let isInMultiSelectMode: Bool
    let isMultiSelected: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var showingDetailFor: Book?
    @State private var isLoadingMetadata = false

    /// Check if book is synced to any Kindle
    private var isOnKindle: Bool {
        guard let devices = book.kindleDevices as? Set<KindleDevice> else { return false }
        return !devices.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(coverBackgroundGradient)

                    if let coverData = book.coverImageData,
                       let nsImage = NSImage(data: coverData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        VStack(spacing: 8) {
                            if isLoadingMetadata {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: formatIcon)
                                    .font(.system(size: 32))
                                    .foregroundColor(.white.opacity(0.8))
                            }

                            Text(book.format?.uppercased() ?? "")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }

                // Multi-select checkbox
                if isInMultiSelectMode {
                    ZStack {
                        Circle()
                            .fill(isMultiSelected ? Color.accentColor : Color.white.opacity(0.9))
                            .frame(width: 24, height: 24)
                            .shadow(radius: 2)

                        if isMultiSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(8)
                }

                // Kindle sync indicator
                if isOnKindle && !isInMultiSelectMode {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                        Text("Kindle")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.9))
                    .clipShape(Capsule())
                    .padding(6)
                }
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.2), radius: isSelected ? 8 : 4, y: 2)

            // Title
            Text(book.title ?? "Unknown")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Authors
            if let authors = book.authors as? Set<Author>, !authors.isEmpty {
                Text(authors.compactMap { $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Format badge and file size
            HStack(spacing: 4) {
                Text(book.format?.uppercased() ?? "")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(formatColor.opacity(0.15))
                    .foregroundColor(formatColor)
                    .clipShape(Capsule())

                Spacer()

                Text(formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
        .contextMenu {
            BookContextMenu(
                book: book,
                libraryService: libraryService,
                kindleDevices: kindleDevices,
                viewContext: viewContext,
                isLoadingMetadata: $isLoadingMetadata,
                showingDetailFor: $showingDetailFor
            )
        }
        .task {
            // Auto-fetch metadata if book has no cover and title looks like a filename
            if book.coverImageData == nil && book.coverImageURL == nil {
                await fetchMetadataIfNeeded()
            }
        }
    }

    private var coverBackgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch book.format?.lowercased() {
            case "epub": return [Color.blue.opacity(0.6), Color.blue.opacity(0.8)]
            case "pdf": return [Color.red.opacity(0.6), Color.red.opacity(0.8)]
            case "mobi", "azw3": return [Color.orange.opacity(0.6), Color.orange.opacity(0.8)]
            case "cbz", "cbr": return [Color.purple.opacity(0.6), Color.purple.opacity(0.8)]
            default: return [Color.gray.opacity(0.4), Color.gray.opacity(0.6)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var formatIcon: String {
        switch book.format?.lowercased() {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.text.fill"
        case "mobi", "azw3": return "flame.fill"
        case "cbz", "cbr": return "photo.stack.fill"
        case "txt": return "doc.plaintext.fill"
        default: return "doc.fill"
        }
    }

    private var formatColor: Color {
        switch book.format?.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        default: return .gray
        }
    }

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file)
    }

    private func fetchMetadataIfNeeded() async {
        guard !isLoadingMetadata else {
            print("[Metadata] Skipping - already loading for: \(book.title ?? "unknown")")
            return
        }

        // Only fetch if title looks like a filename (no spaces or underscores suggest parsed filename)
        let title = book.title ?? ""
        guard !title.isEmpty else {
            print("[Metadata] Skipping - empty title")
            return
        }

        print("[Metadata] Starting fetch for: '\(title)'")
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        do {
            let metadataService = MetadataService()
            print("[Metadata] Calling MetadataService.fetchMetadata...")
            let results = try await metadataService.fetchMetadata(title: title, author: nil)
            print("[Metadata] Got \(results.count) results")

            if let metadata = results.first {
                print("[Metadata] Best match: '\(metadata.title)' by \(metadata.authors.joined(separator: ", "))")
                print("[Metadata] Cover URL: \(metadata.coverImageURL?.absoluteString ?? "none")")

                await MainActor.run {
                    // Update book with fetched metadata
                    if let isbn = metadata.isbn { book.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { book.publisher = publisher }
                    if let summary = metadata.summary { book.summary = summary }
                    if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                    if let language = metadata.language { book.language = language }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        book.coverImageURL = coverURL
                        print("[Metadata] Fetching cover image from: \(coverURL)")
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? book.managedObjectContext?.save()
                    print("[Metadata] Saved metadata to book")
                }
            } else {
                print("[Metadata] No results found for: '\(title)'")
            }
        } catch {
            print("[Metadata] ERROR for '\(title)': \(error)")
        }
    }

    private func fetchCoverImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                book.coverImageData = data
                try? book.managedObjectContext?.save()
            }
        } catch {
            print("Failed to fetch cover image: \(error)")
        }
    }
}

// MARK: - Book Context Menu

struct BookContextMenu: View {
    let book: Book
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var isLoadingMetadata: Bool
    @Binding var showingDetailFor: Book?

    @State private var isConverting = false
    @State private var conversionError: String?

    /// Check if book is synced to a specific Kindle
    private func isOnDevice(_ device: KindleDevice) -> Bool {
        guard let devices = book.kindleDevices as? Set<KindleDevice> else { return false }
        return devices.contains(device)
    }

    var body: some View {
        Button("Open in Apple Books") {
            openInAppleBooks()
        }

        Button("Open with Default App") {
            if let url = book.fileURL {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Show in Finder") {
            if let url = book.fileURL {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
        }

        Divider()

        Button("Get Info...") {
            showingDetailFor = book
        }

        Button("Fetch Metadata") {
            Task {
                await fetchMetadata()
            }
        }
        .disabled(isLoadingMetadata)

        Divider()

        Menu("Convert to...") {
            let currentFormat = book.format?.lowercased() ?? ""

            if currentFormat != "epub" {
                Button("EPUB") {
                    Task { await convertBook(to: "epub") }
                }
            }
            if currentFormat != "mobi" {
                Button("MOBI") {
                    Task { await convertBook(to: "mobi") }
                }
            }
            if currentFormat != "pdf" {
                Button("PDF") {
                    Task { await convertBook(to: "pdf") }
                }
            }
            if currentFormat != "azw3" {
                Button("AZW3") {
                    Task { await convertBook(to: "azw3") }
                }
            }
        }
        .disabled(!CalibreConversionService.shared.isCalibreAvailable)

        Menu("Send to Kindle...") {
            if kindleDevices.isEmpty {
                Text("No Kindle devices configured")
                    .foregroundColor(.secondary)
            } else {
                ForEach(kindleDevices, id: \.objectID) { device in
                    Button {
                        Task { await sendToKindle(device: device) }
                    } label: {
                        HStack {
                            Text(device.name ?? "Kindle")
                            if isOnDevice(device) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        // Mark as synced (manual tracking)
        if !kindleDevices.isEmpty {
            Menu("Mark as on Kindle...") {
                ForEach(kindleDevices, id: \.objectID) { device in
                    Button {
                        toggleKindleSync(device: device)
                    } label: {
                        HStack {
                            Text(device.name ?? "Kindle")
                            if isOnDevice(device) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            try? libraryService.deleteBook(book)
        }
    }

    private func openInAppleBooks() {
        BookFileHelper.openInAppleBooks(book)
    }

    private func convertBook(to format: String) async {
        guard let fileURL = book.fileURL else { return }

        let conversionService = CalibreConversionService.shared

        guard conversionService.isCalibreAvailable else {
            print("Calibre not available")
            return
        }

        do {
            let outputURL = try await conversionService.convert(fileURL, to: format)
            print("Conversion complete: \(outputURL.lastPathComponent)")

            // Add converted book to library
            await MainActor.run {
                do {
                    try libraryService.addBook(from: outputURL)
                } catch {
                    print("Failed to add converted book: \(error)")
                }
            }
        } catch {
            print("Conversion failed: \(error)")
        }
    }

    private func sendToKindle(device: KindleDevice) async {
        guard let fileURL = book.fileURL,
              let kindleEmail = device.email else { return }

        let sendService = SendToKindleService.shared

        do {
            let result = try await sendService.send(
                fileURL: fileURL,
                to: kindleEmail,
                bookTitle: book.title ?? "Untitled"
            )

            if result.success {
                // Mark book as synced to this device
                await MainActor.run {
                    book.addToKindleDevices(device)
                    device.lastSyncDate = Date()
                    try? viewContext.save()
                }
                print("Sent to Kindle: \(result.message)")
            }
        } catch {
            print("Failed to send to Kindle: \(error)")
        }
    }

    private func toggleKindleSync(device: KindleDevice) {
        if isOnDevice(device) {
            book.removeFromKindleDevices(device)
        } else {
            book.addToKindleDevices(device)
        }
        try? viewContext.save()
    }

    private func fetchMetadata() async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        let title = book.title ?? ""
        let authorName = (book.authors as? Set<Author>)?.first?.name

        do {
            let metadataService = MetadataService()
            let results = try await metadataService.fetchMetadata(title: title, author: authorName)
            if let metadata = results.first {
                await MainActor.run {
                    if let isbn = metadata.isbn { book.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { book.publisher = publisher }
                    if let summary = metadata.summary { book.summary = summary }
                    if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                    if let language = metadata.language { book.language = language }

                    if let coverURL = metadata.coverImageURL {
                        book.coverImageURL = coverURL
                        Task {
                            if let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                                await MainActor.run {
                                    book.coverImageData = data
                                    try? book.managedObjectContext?.save()
                                }
                            }
                        }
                    }

                    try? book.managedObjectContext?.save()
                }
            }
        } catch {
            print("Failed to fetch metadata: \(error)")
        }
    }
}

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    let libraryService: LibraryService

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 72))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Import your ebooks to get started.\nDrag and drop files or click the button below.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            FileImportButton(libraryService: libraryService)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            VStack(spacing: 4) {
                Text("Supported formats:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("EPUB, MOBI, AZW3, PDF, CBZ, CBR, FB2, TXT, RTF")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(60)
    }
}

// MARK: - Author List View

struct AuthorListView: View {
    let authors: [Author]
    @Binding var selection: SidebarItem?

    var body: some View {
        if authors.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No authors yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Import books to see authors here")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(authors, id: \.objectID) { author in
                Button {
                    selection = .author(author)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(author.name ?? "Unknown")
                                .font(.headline)
                            if let books = author.books as? Set<Book> {
                                Text("\(books.count) book(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Series List View

struct SeriesListView: View {
    let series: [Series]
    @Binding var selection: SidebarItem?

    var body: some View {
        if series.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No series yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Add books to series to see them here")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(series, id: \.objectID) { s in
                Button {
                    selection = .singleSeries(s)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name ?? "Unknown")
                                .font(.headline)
                            if let books = s.books as? Set<Book> {
                                Text("\(books.count) book(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tag List View

struct TagListView: View {
    let tags: [Tag]
    @Binding var selection: SidebarItem?

    var body: some View {
        if tags.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "tag")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No tags yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Add tags to books to organize them")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(tags, id: \.objectID) { tag in
                Button {
                    selection = .tag(tag)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.color ?? "#007AFF") ?? .accentColor)
                            .frame(width: 12, height: 12)

                        Text(tag.name ?? "Unknown")
                            .font(.headline)

                        Spacer()

                        if let books = tag.books as? Set<Book> {
                            Text("\(books.count)")
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Book Detail View

struct BookDetailView: View {
    @ObservedObject var book: Book
    let libraryService: LibraryService
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingMetadata = false
    @State private var metadataError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Book Details")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 24) {
                    // Cover and basic info
                    HStack(alignment: .top, spacing: 20) {
                        // Cover image
                        coverImageView
                            .frame(width: 150, height: 220)

                        // Basic info
                        VStack(alignment: .leading, spacing: 12) {
                            Text(book.title ?? "Unknown Title")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let authors = book.authors as? Set<Author>, !authors.isEmpty {
                                Text(authors.compactMap { $0.name }.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                formatBadge
                                Text(formattedFileSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let series = book.series, let name = series.name {
                                HStack(spacing: 4) {
                                    Image(systemName: "text.book.closed")
                                        .foregroundColor(.secondary)
                                    Text(name)
                                        .font(.subheadline)
                                    if book.seriesIndex > 0 {
                                        Text("#\(Int(book.seriesIndex))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: openInAppleBooks) {
                                    Label("Read", systemImage: "book")
                                }
                                .buttonStyle(.borderedProminent)

                                Button(action: refreshMetadata) {
                                    if isLoadingMetadata {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Label("Refresh Metadata", systemImage: "arrow.clockwise")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isLoadingMetadata)
                            }
                        }
                    }
                    .padding()

                    Divider()

                    // Metadata details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Details")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], spacing: 12) {
                            metadataRow("Publisher", book.publisher)
                            metadataRow("Language", book.language)
                            metadataRow("Pages", book.pageCount > 0 ? "\(book.pageCount)" : nil)
                            metadataRow("ISBN", book.isbn13 ?? book.isbn)
                            metadataRow("Added", formatDate(book.dateAdded))
                            metadataRow("Last Opened", formatDate(book.lastOpened))
                        }
                    }
                    .padding(.horizontal)

                    // Summary
                    if let summary = book.summary, !summary.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Summary")
                                .font(.headline)

                            Text(summary)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Error message
                    if let error = metadataError {
                        Divider()

                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .frame(maxWidth: 600, maxHeight: 700)
    }

    @ViewBuilder
    private var coverImageView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(coverBackgroundGradient)

            if let coverData = book.coverImageData,
               let nsImage = NSImage(data: coverData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 8) {
                    if isLoadingMetadata {
                        ProgressView()
                    } else {
                        Image(systemName: formatIcon)
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(book.format?.uppercased() ?? "")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private var formatBadge: some View {
        Text(book.format?.uppercased() ?? "")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(formatColor.opacity(0.15))
            .foregroundColor(formatColor)
            .clipShape(Capsule())
    }

    private var coverBackgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch book.format?.lowercased() {
            case "epub": return [Color.blue.opacity(0.6), Color.blue.opacity(0.8)]
            case "pdf": return [Color.red.opacity(0.6), Color.red.opacity(0.8)]
            case "mobi", "azw3": return [Color.orange.opacity(0.6), Color.orange.opacity(0.8)]
            case "cbz", "cbr": return [Color.purple.opacity(0.6), Color.purple.opacity(0.8)]
            default: return [Color.gray.opacity(0.4), Color.gray.opacity(0.6)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var formatIcon: String {
        switch book.format?.lowercased() {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.text.fill"
        case "mobi", "azw3": return "flame.fill"
        case "cbz", "cbr": return "photo.stack.fill"
        default: return "doc.fill"
        }
    }

    private var formatColor: Color {
        switch book.format?.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        default: return .gray
        }
    }

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file)
    }

    private func metadataRow(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value ?? "—")
                .font(.subheadline)
        }
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func openInAppleBooks() {
        BookFileHelper.openInAppleBooks(book)
    }

    private func refreshMetadata() {
        Task {
            await fetchMetadata()
        }
    }

    private func fetchMetadata() async {
        guard !isLoadingMetadata else { return }

        isLoadingMetadata = true
        metadataError = nil
        defer { isLoadingMetadata = false }

        let title = book.title ?? ""
        let authorName = (book.authors as? Set<Author>)?.first?.name

        do {
            let metadataService = MetadataService()
            let results = try await metadataService.fetchMetadata(title: title, author: authorName)

            if let metadata = results.first {
                await MainActor.run {
                    // Update book with fetched metadata
                    if let isbn = metadata.isbn { book.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { book.publisher = publisher }
                    if let summary = metadata.summary { book.summary = summary }
                    if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                    if let language = metadata.language { book.language = language }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        book.coverImageURL = coverURL
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? book.managedObjectContext?.save()
                }
            } else {
                await MainActor.run {
                    metadataError = "No metadata found for '\(title)'"
                }
            }
        } catch {
            await MainActor.run {
                metadataError = "Failed to fetch metadata: \(error.localizedDescription)"
            }
        }
    }

    private func fetchCoverImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                book.coverImageData = data
                try? book.managedObjectContext?.save()
            }
        } catch {
            print("Failed to fetch cover image: \(error)")
        }
    }
}

// MARK: - Conversion Progress Overlay

struct ConversionProgressOverlay: View {
    let progress: Double
    let status: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text("Converting...")
                        .font(.headline)
                }
                .progressViewStyle(.linear)
                .frame(width: 300)

                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(40)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
}

// MARK: - Add Kindle Device View

struct AddKindleDeviceView: View {
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss

    @State private var deviceName = ""
    @State private var kindleEmail = ""
    @State private var isDefault = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Kindle Device")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section {
                    TextField("Device Name", text: $deviceName, prompt: Text("e.g., My Kindle Paperwhite"))

                    TextField("Kindle Email", text: $kindleEmail, prompt: Text("yourname@kindle.com"))

                    Toggle("Set as Default Device", isOn: $isDefault)
                }

                Section {
                    Text("Your Kindle email can be found in Amazon Account → Devices → Kindle Settings. Make sure to add your sender email to the approved senders list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = validationError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Device") {
                    addDevice()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(deviceName.isEmpty || kindleEmail.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }

    private func addDevice() {
        // Validate email
        let email = kindleEmail.lowercased().trimmingCharacters(in: .whitespaces)
        guard email.hasSuffix("@kindle.com") || email.hasSuffix("@free.kindle.com") else {
            validationError = "Invalid Kindle email. Must end with @kindle.com or @free.kindle.com"
            return
        }

        // Create device
        let device = KindleDevice(context: viewContext)
        device.id = UUID()
        device.name = deviceName.trimmingCharacters(in: .whitespaces)
        device.email = email
        device.dateAdded = Date()
        device.isDefault = isDefault

        // If this is default, unset other defaults
        if isDefault {
            let request = KindleDevice.fetchRequest()
            request.predicate = NSPredicate(format: "isDefault == YES AND self != %@", device)
            if let others = try? viewContext.fetch(request) {
                for other in others {
                    other.isDefault = false
                }
            }
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            validationError = "Failed to save device: \(error.localizedDescription)"
        }
    }
}

// MARK: - Kindle Settings View

struct KindleSettingsView: View {
    let viewContext: NSManagedObjectContext
    let kindleDevices: [KindleDevice]
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var deviceToDelete: KindleDevice?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Kindle Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if kindleDevices.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flame")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Kindle Devices")
                        .font(.title2)
                    Text("Add a Kindle device to start sending books.")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(kindleDevices, id: \.objectID) { device in
                        KindleDeviceRow(device: device, viewContext: viewContext) {
                            deviceToDelete = device
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .alert("Delete Device?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let device = deviceToDelete {
                    viewContext.delete(device)
                    try? viewContext.save()
                }
            }
        } message: {
            Text("This will remove the device from Folio. Books already on the device will not be affected.")
        }
    }
}

struct KindleDeviceRow: View {
    @ObservedObject var device: KindleDevice
    let viewContext: NSManagedObjectContext
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name ?? "Kindle")
                        .font(.headline)
                    if device.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(device.email ?? "No email")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let syncedBooks = device.syncedBooks as? Set<Book> {
                    Text("\(syncedBooks.count) book(s) synced")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                if !device.isDefault {
                    Button {
                        setAsDefault()
                    } label: {
                        Label("Set as Default", systemImage: "star")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Device", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.vertical, 4)
    }

    private func setAsDefault() {
        // Unset other defaults
        let request = KindleDevice.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        if let others = try? viewContext.fetch(request) {
            for other in others {
                other.isDefault = false
            }
        }

        device.isDefault = true
        try? viewContext.save()
    }
}

// MARK: - Send to Kindle View

struct SendToKindleView: View {
    let book: Book
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDevice: KindleDevice?
    @State private var isSending = false
    @State private var sendResult: String?
    @State private var sendSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Send to Kindle")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                // Book info
                HStack(spacing: 16) {
                    if let coverData = book.coverImageData,
                       let nsImage = NSImage(data: coverData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 80)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .foregroundColor(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title ?? "Untitled")
                            .font(.headline)
                            .lineLimit(2)

                        Text(book.format?.uppercased() ?? "")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Device selection
                if kindleDevices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("No Kindle devices configured")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("Send to", selection: $selectedDevice) {
                        ForEach(kindleDevices, id: \.objectID) { device in
                            Text(device.name ?? "Kindle").tag(device as KindleDevice?)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                // Result message
                if let result = sendResult {
                    HStack {
                        Image(systemName: sendSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(sendSuccess ? .green : .orange)
                        Text(result)
                    }
                    .padding()
                    .background(sendSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }

                Button("Send") {
                    Task {
                        await sendBook()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDevice == nil || isSending)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .onAppear {
            selectedDevice = kindleDevices.first(where: { $0.isDefault }) ?? kindleDevices.first
        }
    }

    private func sendBook() async {
        guard let device = selectedDevice,
              let kindleEmail = device.email,
              let fileURL = book.fileURL else { return }

        isSending = true
        sendResult = nil

        let sendService = SendToKindleService.shared

        do {
            let result = try await sendService.send(
                fileURL: fileURL,
                to: kindleEmail,
                bookTitle: book.title ?? "Untitled"
            )

            await MainActor.run {
                sendSuccess = result.success
                sendResult = result.message

                if result.success {
                    // Mark as synced
                    book.addToKindleDevices(device)
                    device.lastSyncDate = Date()
                    try? viewContext.save()
                }
            }
        } catch let error as SendToKindleError {
            await MainActor.run {
                sendSuccess = false
                switch error {
                case .fileTooLarge(let size):
                    sendResult = "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Maximum is 50 MB."
                case .invalidKindleEmail(let email):
                    sendResult = "Invalid Kindle email: \(email)"
                case .smtpConfigMissing:
                    sendResult = "SMTP email not configured. Please set up email in settings."
                case .smtpAuthFailed:
                    sendResult = "SMTP authentication failed. Check your email credentials."
                case .sendFailed(let message):
                    sendResult = "Send failed: \(message)"
                }
            }
        } catch {
            await MainActor.run {
                sendSuccess = false
                sendResult = "Error: \(error.localizedDescription)"
            }
        }

        isSending = false
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
