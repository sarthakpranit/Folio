//
// BookGroupViews.swift
// Folio
//
// Views for displaying and managing book groups - collections of the same book
// in different formats (e.g., EPUB + MOBI + PDF of the same title).
//
// Components:
// - BookGroupGridItemView: Grid item showing a grouped book with format badges
// - BookGroupContextMenuContent: Reusable context menu (table view)
// - BookGroupContextMenu: Full context menu (grid view)
// - BookGroupDetailView: Detailed view with all formats and metadata
//
// Key Responsibilities:
// - Display books grouped by content (ISBN or title)
// - Show available formats with color-coded badges
// - Handle Send to Kindle for best format selection
// - Fetch and display metadata from online services
//

import SwiftUI
import CoreData
import FolioCore

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
                        .fill(FormatStyle(format: primaryBook.format ?? "").gradient)

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
                                Image(systemName: FormatStyle(format: primaryBook.format ?? "").icon)
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
                    FormatStyle(format: format).badge()
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
                    // Use the metadata title (from library databases) instead of filename-parsed title
                    if !metadata.title.isEmpty && metadata.confidence >= 0.5 {
                        primaryBook.title = metadata.title
                        primaryBook.sortTitle = libraryService.generateSortTitle(metadata.title)
                        // Update all books in the group with the correct title
                        for book in group.books {
                            book.title = metadata.title
                            book.sortTitle = libraryService.generateSortTitle(metadata.title)
                        }
                    }

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

// MARK: - Book Group Context Menu Content

/// Reusable context menu content for book groups (used by table view)
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

// MARK: - Book Group Context Menu

/// Full context menu for grid view with all format actions
struct BookGroupContextMenu: View {
    let group: BookGroup
    let libraryService: LibraryService
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Binding var isLoadingMetadata: Bool
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
                    // Use the metadata title (from library databases) instead of filename-parsed title
                    if !metadata.title.isEmpty && metadata.confidence >= 0.5 {
                        for book in group.books {
                            book.title = metadata.title
                            book.sortTitle = libraryService.generateSortTitle(metadata.title)
                        }
                    }

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

                    // Create and link Author entities from metadata
                    if !metadata.authors.isEmpty {
                        primaryBook.authors = nil
                        for authorName in metadata.authors {
                            let author = libraryService.findOrCreateAuthor(name: authorName)
                            primaryBook.addToAuthors(author)
                        }
                    }

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
                                    FormatStyle(format: format).badge()
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
                .background(FormatStyle(format: book.format ?? "").color.opacity(0.15))
                .foregroundColor(FormatStyle(format: book.format ?? "").color)
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
                .fill(FormatStyle(format: primaryBook.format ?? "").gradient)

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
                        Image(systemName: FormatStyle(format: primaryBook.format ?? "").icon)
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
                    // Use the metadata title (from library databases) instead of filename-parsed title
                    if !metadata.title.isEmpty && metadata.confidence >= 0.5 {
                        for book in group.books {
                            book.title = metadata.title
                            book.sortTitle = libraryService.generateSortTitle(metadata.title)
                        }
                    }

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
