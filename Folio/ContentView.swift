//
//  ContentView.swift
//  Folio
//
//  Main content view with sidebar navigation and book grid.
//  This is the primary view container that orchestrates the library UI,
//  including sidebar navigation, book grid/table views, and overlays.
//
//  Architecture:
//  - Uses extracted components: ToastView, BookFileHelper, SortOption, etc.
//  - Manages selection state for books and sidebar
//  - Coordinates with LibraryService for data operations
//

import SwiftUI
import CoreData
import FolioCore
import Combine

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

                Button {
                    cleanupSelectedBookTitles()
                } label: {
                    Label("Clean Up Titles", systemImage: "text.badge.checkmark")
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

    /// Clean up titles of selected books by extracting embedded author names
    private func cleanupSelectedBookTitles() {
        let booksToClean = selectedBookObjects
        let result = libraryService.cleanupBookTitles(books: booksToClean)

        if result.titlesFixed > 0 {
            ToastNotificationManager.shared.show(
                title: "Titles Cleaned",
                message: "Fixed \(result.titlesFixed) title(s), extracted \(result.authorsExtracted) author(s)"
            )
        } else {
            ToastNotificationManager.shared.show(
                title: "No Changes",
                message: "No embedded author names found in selected books"
            )
        }

        selectedBooks.removeAll()
        isMultiSelectMode = false
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

            Divider()

            Button {
                cleanupAllBookTitles()
            } label: {
                Label("Clean All Titles", systemImage: "text.badge.checkmark")
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    /// Clean up titles of ALL books in the library
    private func cleanupAllBookTitles() {
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
                selection: $selectedSidebarItem
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
        .overlay(alignment: .top) {
            if libraryService.isImporting {
                ImportProgressBar(
                    progress: libraryService.importProgress,
                    currentBook: libraryService.importCurrentBookName,
                    current: libraryService.importCurrent,
                    total: libraryService.importTotal
                )
            }
        }
        .overlay(alignment: .bottom) {
            ToastView(manager: ToastNotificationManager.shared)
        }
        .navigationTitle(navigationTitle)
        // Note: Removed .id(refreshID) and NSManagedObjectContextDidSave observer
        // that was forcing full view recreation on every Core Data save.
        // @FetchRequest already observes Core Data changes automatically,
        // and the forced refresh was causing scroll position reset.
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

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
