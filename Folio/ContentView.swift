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

// MARK: - Toast Notification Manager

/// Manages toast-style notifications for user feedback
@MainActor
class ToastNotificationManager: ObservableObject {
    static let shared = ToastNotificationManager()

    @Published var isShowing = false
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var isError: Bool = false

    private var dismissTask: Task<Void, Never>?

    func show(title: String, message: String, isError: Bool = false) {
        self.title = title
        self.message = message
        self.isError = isError
        self.isShowing = true

        // Auto-dismiss after delay
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: isError ? 4_000_000_000 : 3_000_000_000)
            if !Task.isCancelled {
                self.isShowing = false
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        isShowing = false
    }
}

// MARK: - Toast View

struct ToastView: View {
    @ObservedObject var manager: ToastNotificationManager

    var body: some View {
        if manager.isShowing {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: manager.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(manager.isError ? .orange : .green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.title)
                            .font(.headline)
                        Text(manager.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        manager.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: manager.isShowing)
        }
    }
}

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

// MARK: - Library View Mode

enum LibraryViewMode: String, CaseIterable {
    case grid = "Grid"
    case table = "Table"

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .table: return "list.bullet"
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

    // View mode and Sorting
    @State private var viewMode: LibraryViewMode = .grid
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

    /// Displayed books grouped by content (ISBN or title)
    var displayedBookGroups: [BookGroup] {
        BookGroupingService.groupBooks(displayedBooks)
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

        ToolbarItem(placement: .automatic) {
            viewModeToggle
        }
    }

    private var viewModeToggle: some View {
        Picker("View", selection: $viewMode) {
            ForEach(LibraryViewMode.allCases, id: \.self) { mode in
                Image(systemName: mode.icon)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .help("Switch between Grid and Table view")
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
        .overlay(alignment: .bottom) {
            ToastView(manager: ToastNotificationManager.shared)
        }
        .navigationTitle(navigationTitle)
        .id(refreshID)
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave, object: viewContext)) { _ in
            refreshID = UUID()
        }
        // Cmd+A to select all books
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "a" {
                    selectAllBooks()
                    return nil // Consume the event
                }
                return event
            }
        }
    }

    /// Select all books in the current view
    private func selectAllBooks() {
        isMultiSelectMode = true
        selectedBooks = Set(displayedBooks.map { $0.objectID })
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
                    switch viewMode {
                    case .grid:
                        BookGridView(
                            books: displayedBooks,
                            bookGroups: displayedBookGroups,
                            selectedBook: $selectedBook,
                            selectedBooks: $selectedBooks,
                            isMultiSelectMode: $isMultiSelectMode,
                            libraryService: libraryService,
                            kindleDevices: Array(kindleDevices),
                            viewContext: viewContext
                        )
                    case .table:
                        BookTableView(
                            books: displayedBooks,
                            bookGroups: displayedBookGroups,
                            selectedBook: $selectedBook,
                            selectedBooks: $selectedBooks,
                            isMultiSelectMode: $isMultiSelectMode,
                            libraryService: libraryService,
                            kindleDevices: Array(kindleDevices),
                            viewContext: viewContext
                        )
                    }
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
    let bookGroups: [BookGroup]
    @Binding var selectedBook: Book?
    @Binding var selectedBooks: Set<NSManagedObjectID>
    @Binding var isMultiSelectMode: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @State private var showingBookDetail: Book?
    @State private var showingGroupDetail: BookGroup?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(bookGroups) { group in
                    BookGroupGridItemView(
                        group: group,
                        isSelected: isGroupSelected(group),
                        isInMultiSelectMode: isMultiSelectMode,
                        isMultiSelected: isGroupMultiSelected(group),
                        libraryService: libraryService,
                        kindleDevices: kindleDevices,
                        viewContext: viewContext,
                        showingDetailFor: $showingGroupDetail
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

// MARK: - Book Table View

/// Table view for displaying books in a sortable, column-based layout
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
                    .background(formatColor(for: format).opacity(0.15))
                    .foregroundColor(formatColor(for: format))
                    .clipShape(Capsule())
            }
        }
    }

    private func formatColor(for format: String) -> Color {
        switch format.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        default: return .gray
        }
    }
}

// MARK: - Book Group Context Menu Content

/// Reusable context menu content for book groups (used by both grid and table views)
struct BookGroupContextMenuContent: View {
    let group: BookGroup
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var showingDetailFor: BookGroup?

    private var primaryBook: Book { group.primaryBook }

    private func showNotification(title: String, message: String, isError: Bool = false) {
        Task { @MainActor in
            ToastNotificationManager.shared.show(title: title, message: message, isError: isError)
        }
    }

    private func isOnDevice(_ device: KindleDevice) -> Bool {
        group.books.contains { book in
            guard let devices = book.kindleDevices as? Set<KindleDevice> else { return false }
            return devices.contains(device)
        }
    }

    var body: some View {
        if let readingBook = group.preferredForReading {
            Button("Open in Apple Books") {
                BookFileHelper.openInAppleBooks(readingBook)
            }
        }

        Button("Open with Default App") {
            if let book = group.preferredForReading, let url = book.fileURL {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Show in Finder") {
            if let book = group.preferredForReading, let url = book.fileURL {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
        }

        Divider()

        Button("Get Info...") {
            showingDetailFor = group
        }

        Divider()

        Menu("Send to Kindle...") {
            if kindleDevices.isEmpty {
                Text("No Kindle devices configured")
                    .foregroundColor(.secondary)
            } else {
                if let kindleBook = group.preferredForKindle {
                    Text("Will send: \(kindleBook.format?.uppercased() ?? "Unknown")")
                        .font(.caption)

                    Divider()

                    ForEach(kindleDevices, id: \.objectID) { device in
                        Button {
                            Task { await sendToKindle(book: kindleBook, device: device) }
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
        }

        Divider()

        Button("Delete", role: .destructive) {
            for book in group.books {
                try? libraryService.deleteBook(book)
            }
        }
    }

    private func sendToKindle(book: Book, device: KindleDevice) async {
        guard let kindleEmail = device.email else {
            showNotification(title: "No Kindle Email", message: "Please configure an email for \(device.name ?? "this Kindle").", isError: true)
            return
        }

        let sendService = SendToKindleService.shared
        let isConfigured = await sendService.isConfigured
        guard isConfigured else {
            showNotification(title: "Email Not Configured", message: "Please configure SMTP email settings in Kindle Settings.", isError: true)
            return
        }

        guard let (accessibleURL, didStartAccessing) = BookFileHelper.resolveSecurityScopedURL(for: book) else {
            showNotification(title: "Access Denied", message: "Could not access the book file. Try re-importing.", isError: true)
            return
        }

        defer {
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await sendService.send(fileURL: accessibleURL, to: kindleEmail, bookTitle: book.title ?? "Untitled")
            if result.success {
                await MainActor.run {
                    book.addToKindleDevices(device)
                    device.lastSyncDate = Date()
                    try? viewContext.save()
                }
                showNotification(title: "Sent to Kindle", message: "\(book.title ?? "Book") sent to \(device.name ?? "Kindle")")
            }
        } catch {
            showNotification(title: "Send Failed", message: error.localizedDescription, isError: true)
        }
    }
}

// MARK: - Book Group Grid Item

/// Grid item view for displaying a grouped book with multiple format variants
struct BookGroupGridItemView: View {
    let group: BookGroup
    let isSelected: Bool
    let isInMultiSelectMode: Bool
    let isMultiSelected: Bool
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var showingDetailFor: BookGroup?
    @State private var isLoadingMetadata = false

    /// The primary book used for display (best metadata)
    private var primaryBook: Book { group.primaryBook }

    /// Check if any book in group is synced to any Kindle
    private var isOnKindle: Bool {
        group.books.contains { book in
            guard let devices = book.kindleDevices as? Set<KindleDevice> else { return false }
            return !devices.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(coverBackgroundGradient)

                    if let coverData = primaryBook.coverImageData,
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

                            Text(primaryBook.format?.uppercased() ?? "")
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
            Text(primaryBook.title ?? "Unknown")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Authors
            if let authors = primaryBook.authors as? Set<Author>, !authors.isEmpty {
                Text(authors.compactMap { $0.name }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Format badges (showing all formats) and total file size
            HStack(spacing: 4) {
                ForEach(group.formats, id: \.self) { format in
                    Text(format.uppercased())
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(formatColor(for: format).opacity(0.15))
                        .foregroundColor(formatColor(for: format))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(formattedTotalSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
        .contextMenu {
            BookGroupContextMenu(
                group: group,
                libraryService: libraryService,
                kindleDevices: kindleDevices,
                viewContext: viewContext,
                isLoadingMetadata: $isLoadingMetadata,
                showingDetailFor: $showingDetailFor
            )
        }
        .task {
            // Auto-fetch metadata if primary book has no cover
            if primaryBook.coverImageData == nil && primaryBook.coverImageURL == nil {
                await fetchMetadataIfNeeded()
            }
        }
    }

    private var coverBackgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch primaryBook.format?.lowercased() {
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
        switch primaryBook.format?.lowercased() {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.text.fill"
        case "mobi", "azw3": return "flame.fill"
        case "cbz", "cbr": return "photo.stack.fill"
        case "txt": return "doc.plaintext.fill"
        default: return "doc.fill"
        }
    }

    private func formatColor(for format: String) -> Color {
        switch format.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        default: return .gray
        }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file)
    }

    private func fetchMetadataIfNeeded() async {
        guard !isLoadingMetadata else { return }

        let title = primaryBook.title ?? ""
        guard !title.isEmpty else { return }

        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        do {
            let metadataService = MetadataService()
            let results = try await metadataService.fetchMetadata(title: title, author: nil)

            if let metadata = results.first {
                await MainActor.run {
                    // Update primary book with fetched metadata
                    if let isbn = metadata.isbn { primaryBook.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { primaryBook.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { primaryBook.publisher = publisher }
                    if let summary = metadata.summary { primaryBook.summary = summary }
                    if let pageCount = metadata.pageCount { primaryBook.pageCount = Int32(pageCount) }
                    if let language = metadata.language { primaryBook.language = language }

                    // Also update ISBN on other books in group for better grouping
                    for book in group.books {
                        if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                        if let isbn = metadata.isbn { book.isbn = isbn }
                    }

                    // Create and link Author entities
                    if !metadata.authors.isEmpty {
                        primaryBook.authors = nil
                        for authorName in metadata.authors {
                            let author = libraryService.findOrCreateAuthor(name: authorName)
                            primaryBook.addToAuthors(author)
                        }
                    }

                    // Create and link Series entity
                    if let seriesName = metadata.series, !seriesName.isEmpty {
                        let series = libraryService.findOrCreateSeries(name: seriesName)
                        primaryBook.series = series
                        if let index = metadata.seriesIndex {
                            primaryBook.seriesIndex = index
                        }
                    }

                    // Create and link Tag entities
                    if !metadata.tags.isEmpty {
                        for tagName in metadata.tags {
                            let tag = libraryService.findOrCreateTag(name: tagName)
                            primaryBook.addToTags(tag)
                        }
                    }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        primaryBook.coverImageURL = coverURL
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? primaryBook.managedObjectContext?.save()
                    libraryService.refresh()
                }
            }
        } catch {
            print("[Metadata] ERROR for '\(title)': \(error)")
        }
    }

    private func fetchCoverImage(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            await MainActor.run {
                primaryBook.coverImageData = data
                try? primaryBook.managedObjectContext?.save()
            }
        } catch {
            print("Failed to fetch cover image: \(error)")
        }
    }
}

// MARK: - Book Group Context Menu

/// Context menu for a grouped book with actions for all formats
struct BookGroupContextMenu: View {
    let group: BookGroup
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var isLoadingMetadata: Bool
    @Binding var showingDetailFor: BookGroup?

    private var primaryBook: Book { group.primaryBook }

    // Show user feedback via toast notification
    private func showNotification(title: String, message: String, isError: Bool = false) {
        Task { @MainActor in
            ToastNotificationManager.shared.show(title: title, message: message, isError: isError)
        }
    }

    /// Check if any book in group is synced to a specific Kindle
    private func isOnDevice(_ device: KindleDevice) -> Bool {
        group.books.contains { book in
            guard let devices = book.kindleDevices as? Set<KindleDevice> else { return false }
            return devices.contains(device)
        }
    }

    var body: some View {
        // Open actions - prefer reading format
        if let readingBook = group.preferredForReading {
            Button("Open in Apple Books") {
                BookFileHelper.openInAppleBooks(readingBook)
            }
        }

        Button("Open with Default App") {
            if let book = group.preferredForReading, let url = book.fileURL {
                NSWorkspace.shared.open(url)
            }
        }

        // Show all formats in Finder
        Button("Show All Formats in Finder") {
            for book in group.books {
                if let url = book.fileURL {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            }
        }

        Divider()

        Button("Get Info...") {
            showingDetailFor = group
        }

        Button("Fetch Metadata") {
            Task {
                await fetchMetadata()
            }
        }
        .disabled(isLoadingMetadata)

        Divider()

        // Send to Kindle - uses preferred Kindle format (MOBI > AZW3 > EPUB)
        Menu("Send to Kindle...") {
            if kindleDevices.isEmpty {
                Text("No Kindle devices configured")
                    .foregroundColor(.secondary)
            } else {
                if let kindleBook = group.preferredForKindle {
                    Text("Will send: \(kindleBook.format?.uppercased() ?? "Unknown")")
                        .font(.caption)

                    Divider()

                    ForEach(kindleDevices, id: \.objectID) { device in
                        Button {
                            Task { await sendToKindle(book: kindleBook, device: device) }
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
        }

        // Individual format actions
        if group.hasMultipleFormats {
            Menu("Format Actions...") {
                ForEach(group.books.sorted(by: { ($0.format ?? "") < ($1.format ?? "") }), id: \.objectID) { book in
                    Menu(book.format?.uppercased() ?? "Unknown") {
                        Button("Open") {
                            BookFileHelper.openInAppleBooks(book)
                        }

                        Button("Show in Finder") {
                            if let url = book.fileURL {
                                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                            }
                        }

                        Divider()

                        Button("Delete \(book.format?.uppercased() ?? "") Only", role: .destructive) {
                            try? libraryService.deleteBook(book)
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

        Button("Delete All Formats", role: .destructive) {
            for book in group.books {
                try? libraryService.deleteBook(book)
            }
        }
    }

    private func sendToKindle(book: Book, device: KindleDevice) async {
        guard let kindleEmail = device.email else {
            showNotification(
                title: "No Kindle Email",
                message: "Please configure an email for \(device.name ?? "this Kindle").",
                isError: true
            )
            return
        }

        let sendService = SendToKindleService.shared

        let isConfigured = await sendService.isConfigured
        guard isConfigured else {
            showNotification(
                title: "Email Not Configured",
                message: "Please configure SMTP email settings in Kindle Settings.",
                isError: true
            )
            return
        }

        guard let (accessibleURL, didStartAccessing) = BookFileHelper.resolveSecurityScopedURL(for: book) else {
            showNotification(
                title: "Access Denied",
                message: "Could not access the book file. Try re-importing.",
                isError: true
            )
            return
        }

        defer {
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await sendService.send(
                fileURL: accessibleURL,
                to: kindleEmail,
                bookTitle: book.title ?? "Untitled"
            )

            if result.success {
                await MainActor.run {
                    book.addToKindleDevices(device)
                    device.lastSyncDate = Date()
                    try? viewContext.save()
                }
                showNotification(
                    title: "Sent to Kindle",
                    message: "\(book.title ?? "Book") (\(book.format?.uppercased() ?? "")) sent to \(device.name ?? "Kindle")"
                )
            }
        } catch {
            showNotification(
                title: "Send Failed",
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func toggleKindleSync(device: KindleDevice) {
        // Toggle sync for all books in the group
        let isCurrentlyOnDevice = isOnDevice(device)

        for book in group.books {
            if isCurrentlyOnDevice {
                book.removeFromKindleDevices(device)
            } else {
                book.addToKindleDevices(device)
            }
        }
        try? viewContext.save()
    }

    private func fetchMetadata() async {
        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        let title = primaryBook.title ?? ""
        let authorName = (primaryBook.authors as? Set<Author>)?.first?.name

        do {
            let metadataService = MetadataService()
            let results = try await metadataService.fetchMetadata(title: title, author: authorName)
            if let metadata = results.first {
                await MainActor.run {
                    // Update all books in group with ISBNs for better grouping
                    for book in group.books {
                        if let isbn = metadata.isbn { book.isbn = isbn }
                        if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    }

                    // Update primary book with full metadata
                    if let publisher = metadata.publisher { primaryBook.publisher = publisher }
                    if let summary = metadata.summary { primaryBook.summary = summary }
                    if let pageCount = metadata.pageCount { primaryBook.pageCount = Int32(pageCount) }
                    if let language = metadata.language { primaryBook.language = language }

                    if let coverURL = metadata.coverImageURL {
                        primaryBook.coverImageURL = coverURL
                        Task {
                            if let (data, _) = try? await URLSession.shared.data(from: coverURL) {
                                await MainActor.run {
                                    primaryBook.coverImageData = data
                                    try? primaryBook.managedObjectContext?.save()
                                }
                            }
                        }
                    }

                    try? primaryBook.managedObjectContext?.save()
                    libraryService.refresh()
                }
            }
        } catch {
            print("Failed to fetch metadata: \(error)")
        }
    }
}

// MARK: - Book Group Detail View

/// Detail view for a book group showing all format variants
struct BookGroupDetailView: View {
    let group: BookGroup
    let libraryService: LibraryService
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss
    @State private var isLoadingMetadata = false
    @State private var metadataError: String?

    private var primaryBook: Book { group.primaryBook }

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
                            Text(primaryBook.title ?? "Unknown Title")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let authors = primaryBook.authors as? Set<Author>, !authors.isEmpty {
                                Text(authors.compactMap { $0.name }.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            // All format badges
                            HStack(spacing: 6) {
                                ForEach(group.formats, id: \.self) { format in
                                    Text(format.uppercased())
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(formatColor(for: format).opacity(0.15))
                                        .foregroundColor(formatColor(for: format))
                                        .clipShape(Capsule())
                                }
                            }

                            Text("Total: \(formattedTotalSize)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if let series = primaryBook.series, let name = series.name {
                                HStack(spacing: 4) {
                                    Image(systemName: "text.book.closed")
                                        .foregroundColor(.secondary)
                                    Text(name)
                                        .font(.subheadline)
                                    if primaryBook.seriesIndex > 0 {
                                        Text("#\(Int(primaryBook.seriesIndex))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer()

                            // Action buttons
                            HStack(spacing: 12) {
                                Button(action: openPreferredFormat) {
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

                    // Format variants section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available Formats")
                            .font(.headline)

                        ForEach(group.books.sorted(by: { ($0.format ?? "") < ($1.format ?? "") }), id: \.objectID) { book in
                            formatRow(for: book)
                        }
                    }
                    .padding(.horizontal)

                    Divider()

                    // Metadata details
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Details")
                            .font(.headline)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ], spacing: 12) {
                            metadataRow("Publisher", primaryBook.publisher)
                            metadataRow("Language", primaryBook.language)
                            metadataRow("Pages", primaryBook.pageCount > 0 ? "\(primaryBook.pageCount)" : nil)
                            metadataRow("ISBN", primaryBook.isbn13 ?? primaryBook.isbn)
                            metadataRow("Added", formatDate(primaryBook.dateAdded))
                            metadataRow("Last Opened", formatDate(primaryBook.lastOpened))
                        }
                    }
                    .padding(.horizontal)

                    // Tags
                    if let tags = primaryBook.tags as? Set<Tag>, !tags.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)

                            FlowLayout(spacing: 8) {
                                ForEach(Array(tags).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.objectID) { tag in
                                    Text(tag.name ?? "")
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Summary
                    if let summary = primaryBook.summary, !summary.isEmpty {
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
        .frame(minWidth: 550, minHeight: 500)
        .frame(maxWidth: 650, maxHeight: 800)
    }

    @ViewBuilder
    private func formatRow(for book: Book) -> some View {
        HStack(spacing: 12) {
            // Format badge
            Text(book.format?.uppercased() ?? "")
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 50)
                .padding(.vertical, 6)
                .background(formatColor(for: book.format ?? "").opacity(0.15))
                .foregroundColor(formatColor(for: book.format ?? ""))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // File size
            Text(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            // File path (truncated)
            if let url = book.fileURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Action buttons
            Button(action: { BookFileHelper.openInAppleBooks(book) }) {
                Image(systemName: "book")
            }
            .buttonStyle(.borderless)
            .help("Open in Apple Books")

            Button(action: {
                if let url = book.fileURL {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            }) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var coverImageView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(coverBackgroundGradient)

            if let coverData = primaryBook.coverImageData,
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
                    Text(primaryBook.format?.uppercased() ?? "")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }

    private var coverBackgroundGradient: LinearGradient {
        let colors: [Color] = {
            switch primaryBook.format?.lowercased() {
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
        switch primaryBook.format?.lowercased() {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.text.fill"
        case "mobi", "azw3": return "flame.fill"
        case "cbz", "cbr": return "photo.stack.fill"
        default: return "doc.fill"
        }
    }

    private func formatColor(for format: String) -> Color {
        switch format.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        default: return .gray
        }
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file)
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

    private func openPreferredFormat() {
        if let book = group.preferredForReading {
            BookFileHelper.openInAppleBooks(book)
        }
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

        let title = primaryBook.title ?? ""
        let authorName = (primaryBook.authors as? Set<Author>)?.first?.name

        do {
            let metadataService = MetadataService()
            let results = try await metadataService.fetchMetadata(title: title, author: authorName)

            if let metadata = results.first {
                await MainActor.run {
                    // Update all books in group with ISBNs
                    for book in group.books {
                        if let isbn = metadata.isbn { book.isbn = isbn }
                        if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    }

                    // Update primary book with full metadata
                    if let publisher = metadata.publisher { primaryBook.publisher = publisher }
                    if let summary = metadata.summary { primaryBook.summary = summary }
                    if let pageCount = metadata.pageCount { primaryBook.pageCount = Int32(pageCount) }
                    if let language = metadata.language { primaryBook.language = language }

                    // Create and link Author entities
                    if !metadata.authors.isEmpty {
                        primaryBook.authors = nil
                        for authorName in metadata.authors {
                            let author = libraryService.findOrCreateAuthor(name: authorName)
                            primaryBook.addToAuthors(author)
                        }
                    }

                    // Create and link Series entity
                    if let seriesName = metadata.series, !seriesName.isEmpty {
                        let series = libraryService.findOrCreateSeries(name: seriesName)
                        primaryBook.series = series
                        if let index = metadata.seriesIndex {
                            primaryBook.seriesIndex = index
                        }
                    }

                    // Create and link Tag entities
                    if !metadata.tags.isEmpty {
                        for tagName in metadata.tags {
                            let tag = libraryService.findOrCreateTag(name: tagName)
                            primaryBook.addToTags(tag)
                        }
                    }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        primaryBook.coverImageURL = coverURL
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? primaryBook.managedObjectContext?.save()
                    libraryService.refresh()
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
                primaryBook.coverImageData = data
                try? primaryBook.managedObjectContext?.save()
            }
        } catch {
            print("Failed to fetch cover image: \(error)")
        }
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
                print("[Metadata] Series: \(metadata.series ?? "none"), Tags: \(metadata.tags)")

                await MainActor.run {
                    // Update book with fetched metadata
                    if let isbn = metadata.isbn { book.isbn = isbn }
                    if let isbn13 = metadata.isbn13 { book.isbn13 = isbn13 }
                    if let publisher = metadata.publisher { book.publisher = publisher }
                    if let summary = metadata.summary { book.summary = summary }
                    if let pageCount = metadata.pageCount { book.pageCount = Int32(pageCount) }
                    if let language = metadata.language { book.language = language }

                    // Create and link Author entities
                    if !metadata.authors.isEmpty {
                        // Clear existing authors first
                        book.authors = nil
                        for authorName in metadata.authors {
                            let author = libraryService.findOrCreateAuthor(name: authorName)
                            book.addToAuthors(author)
                        }
                        print("[Metadata] Added \(metadata.authors.count) author(s)")
                    }

                    // Create and link Series entity
                    if let seriesName = metadata.series, !seriesName.isEmpty {
                        let series = libraryService.findOrCreateSeries(name: seriesName)
                        book.series = series
                        if let index = metadata.seriesIndex {
                            book.seriesIndex = index
                        }
                        print("[Metadata] Added series: \(seriesName)")
                    }

                    // Create and link Tag entities
                    if !metadata.tags.isEmpty {
                        for tagName in metadata.tags {
                            let tag = libraryService.findOrCreateTag(name: tagName)
                            book.addToTags(tag)
                        }
                        print("[Metadata] Added \(metadata.tags.count) tag(s)")
                    }

                    // Fetch cover image if URL is available
                    if let coverURL = metadata.coverImageURL {
                        book.coverImageURL = coverURL
                        print("[Metadata] Fetching cover image from: \(coverURL)")
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? book.managedObjectContext?.save()

                    // Refresh library service to update sidebar counts
                    libraryService.refresh()

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

    // Show user feedback via toast notification
    private func showNotification(title: String, message: String, isError: Bool = false) {
        Task { @MainActor in
            ToastNotificationManager.shared.show(title: title, message: message, isError: isError)
        }
    }

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
        let conversionService = CalibreConversionService.shared

        guard conversionService.isCalibreAvailable else {
            showNotification(
                title: "Calibre Not Found",
                message: "Please install Calibre to convert ebooks.",
                isError: true
            )
            return
        }

        // Resolve security-scoped access for the book file
        guard let (accessibleURL, didStartAccessing) = BookFileHelper.resolveSecurityScopedURL(for: book) else {
            showNotification(
                title: "Access Denied",
                message: "Could not access the book file. Try re-importing.",
                isError: true
            )
            return
        }

        defer {
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let outputURL = try await conversionService.convert(accessibleURL, to: format)

            // Add converted book to library
            await MainActor.run {
                do {
                    try libraryService.addBook(from: outputURL)
                    showNotification(
                        title: "Conversion Complete",
                        message: "\(book.title ?? "Book") converted to \(format.uppercased())"
                    )
                } catch {
                    showNotification(
                        title: "Import Failed",
                        message: "Converted file could not be added to library.",
                        isError: true
                    )
                }
            }
        } catch ConversionError.calibreNotFound {
            showNotification(
                title: "Calibre Not Found",
                message: "Please install Calibre to convert ebooks.",
                isError: true
            )
        } catch ConversionError.cancelled {
            showNotification(
                title: "Conversion Cancelled",
                message: "The conversion was cancelled."
            )
        } catch {
            showNotification(
                title: "Conversion Failed",
                message: error.localizedDescription,
                isError: true
            )
        }
    }

    private func sendToKindle(device: KindleDevice) async {
        guard let kindleEmail = device.email else {
            showNotification(
                title: "No Kindle Email",
                message: "Please configure an email for \(device.name ?? "this Kindle").",
                isError: true
            )
            return
        }

        let sendService = SendToKindleService.shared

        // Check if SMTP is configured
        let isConfigured = await sendService.isConfigured
        guard isConfigured else {
            showNotification(
                title: "Email Not Configured",
                message: "Please configure SMTP email settings in Kindle Settings.",
                isError: true
            )
            return
        }

        // Resolve security-scoped access for the book file
        guard let (accessibleURL, didStartAccessing) = BookFileHelper.resolveSecurityScopedURL(for: book) else {
            showNotification(
                title: "Access Denied",
                message: "Could not access the book file. Try re-importing.",
                isError: true
            )
            return
        }

        defer {
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let result = try await sendService.send(
                fileURL: accessibleURL,
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
                showNotification(
                    title: "Sent to Kindle",
                    message: "\(book.title ?? "Book") sent to \(device.name ?? "Kindle")"
                )
            }
        } catch SendToKindleError.fileTooLarge(let size) {
            let sizeStr = SendToKindleService.formatFileSize(size)
            showNotification(
                title: "File Too Large",
                message: "File is \(sizeStr). Amazon limit is 50 MB.",
                isError: true
            )
        } catch SendToKindleError.invalidKindleEmail(let email) {
            showNotification(
                title: "Invalid Kindle Email",
                message: "\(email) is not a valid Kindle email address.",
                isError: true
            )
        } catch SendToKindleError.smtpConfigMissing {
            showNotification(
                title: "Email Not Configured",
                message: "Please configure SMTP email settings.",
                isError: true
            )
        } catch {
            showNotification(
                title: "Send Failed",
                message: error.localizedDescription,
                isError: true
            )
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

                    // Tags
                    if let tags = book.tags as? Set<Tag>, !tags.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags")
                                .font(.headline)

                            FlowLayout(spacing: 8) {
                                ForEach(Array(tags).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }), id: \.objectID) { tag in
                                    Text(tag.name ?? "")
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundColor(.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

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

                    // File Information
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("File Information")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 6) {
                            if let fileURL = book.fileURL {
                                HStack(alignment: .top) {
                                    Text("Path:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 60, alignment: .leading)
                                    Text(fileURL.path)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                        .textSelection(.enabled)
                                }

                                Button(action: {
                                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: "")
                                }) {
                                    Label("Show in Finder", systemImage: "folder")
                                        .font(.caption)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    .padding(.horizontal)

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
                        Task {
                            await fetchCoverImage(from: coverURL)
                        }
                    }

                    try? book.managedObjectContext?.save()
                    libraryService.refresh()
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

    // SMTP Configuration
    @State private var selectedProvider: SMTPProvider = .gmail
    @State private var smtpHost: String = ""
    @State private var smtpPort: String = "587"
    @State private var smtpUsername: String = ""
    @State private var smtpPassword: String = ""
    @State private var useTLS: Bool = true
    @State private var isSavingSMTP = false
    @State private var smtpSaveError: String?
    @State private var smtpSaveSuccess = false
    @State private var isConfigured = false

    enum SMTPProvider: String, CaseIterable {
        case gmail = "Gmail"
        case outlook = "Outlook / Hotmail"
        case icloud = "iCloud"
        case custom = "Custom SMTP"

        var host: String {
            switch self {
            case .gmail: return "smtp.gmail.com"
            case .outlook: return "smtp.office365.com"
            case .icloud: return "smtp.mail.me.com"
            case .custom: return ""
            }
        }

        var port: Int {
            switch self {
            case .gmail, .outlook, .icloud: return 587
            case .custom: return 587
            }
        }
    }

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

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // SMTP Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.accentColor)
                            Text("Email Settings (for Send to Kindle)")
                                .font(.headline)

                            Spacer()

                            if isConfigured {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Configured")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        Text("Configure your email account to send books to your Kindle. For Gmail, you'll need an App Password.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Provider picker
                        Picker("Email Provider", selection: $selectedProvider) {
                            ForEach(SMTPProvider.allCases, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProvider) { newValue in
                            if newValue != .custom {
                                smtpHost = newValue.host
                                smtpPort = String(newValue.port)
                            }
                        }

                        // SMTP fields
                        if selectedProvider == .custom {
                            HStack {
                                TextField("SMTP Host", text: $smtpHost)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Port", text: $smtpPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }

                        TextField("Email Address", text: $smtpUsername)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password / App Password", text: $smtpPassword)
                            .textFieldStyle(.roundedBorder)

                        if selectedProvider == .gmail {
                            Link(destination: URL(string: "https://myaccount.google.com/apppasswords")!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Create Gmail App Password")
                                }
                                .font(.caption)
                            }
                        }

                        Toggle("Use TLS (recommended)", isOn: $useTLS)
                            .font(.subheadline)

                        if let error = smtpSaveError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        if smtpSaveSuccess {
                            Text("Email settings saved successfully!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        HStack {
                            Button("Save Email Settings") {
                                saveSMTPConfiguration()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(smtpUsername.isEmpty || smtpPassword.isEmpty || isSavingSMTP)

                            if isSavingSMTP {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Kindle Devices Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Kindle Devices")
                                .font(.headline)
                        }

                        if kindleDevices.isEmpty {
                            VStack(spacing: 8) {
                                Text("No Kindle devices added yet.")
                                    .foregroundColor(.secondary)
                                Text("Add your Kindle's email address to send books.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ForEach(kindleDevices, id: \.objectID) { device in
                                KindleDeviceRow(device: device, viewContext: viewContext) {
                                    deviceToDelete = device
                                    showingDeleteConfirmation = true
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
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
        .frame(width: 550, height: 550)
        .onAppear {
            loadExistingSMTPConfiguration()
        }
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

    private func loadExistingSMTPConfiguration() {
        Task {
            let sendService = SendToKindleService.shared
            isConfigured = await sendService.isConfigured

            if let config = await sendService.getSMTPConfiguration() {
                await MainActor.run {
                    smtpHost = config.host
                    smtpPort = String(config.port)
                    smtpUsername = config.username
                    useTLS = config.useTLS

                    // Determine which provider matches
                    if config.host == SMTPProvider.gmail.host {
                        selectedProvider = .gmail
                    } else if config.host == SMTPProvider.outlook.host {
                        selectedProvider = .outlook
                    } else if config.host == SMTPProvider.icloud.host {
                        selectedProvider = .icloud
                    } else {
                        selectedProvider = .custom
                    }
                }
            }
        }
    }

    private func saveSMTPConfiguration() {
        smtpSaveError = nil
        smtpSaveSuccess = false
        isSavingSMTP = true

        let host = selectedProvider == .custom ? smtpHost : selectedProvider.host
        let port = Int(smtpPort) ?? 587

        Task {
            do {
                let config = SendToKindleService.SMTPConfiguration(
                    host: host,
                    port: port,
                    username: smtpUsername,
                    useTLS: useTLS
                )

                try await SendToKindleService.shared.configure(smtp: config, password: smtpPassword)

                await MainActor.run {
                    isSavingSMTP = false
                    smtpSaveSuccess = true
                    isConfigured = true

                    // Clear success message after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        smtpSaveSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingSMTP = false
                    smtpSaveError = "Failed to save: \(error.localizedDescription)"
                }
            }
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

// MARK: - Flow Layout

/// A layout that arranges views in a flowing horizontal wrap
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        let containerWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > containerWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxWidth = max(maxWidth, currentX)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
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
