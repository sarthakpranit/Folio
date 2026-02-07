//
//  ContentView.swift
//  Folio
//
//  Main content view with sidebar navigation and book grid
//

import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var libraryService = LibraryService.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Book.dateAdded, ascending: false)],
        animation: .default)
    private var books: FetchedResults<Book>

    @State private var searchText = ""
    @State private var selectedBook: Book?
    @State private var isDropTargeted = false
    @State private var showingImportResult = false
    @State private var importResult: ImportResult?

    var filteredBooks: [Book] {
        if searchText.isEmpty {
            return Array(books)
        } else {
            return libraryService.searchBooks(query: searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(libraryService: libraryService)
        } detail: {
            ZStack {
                if books.isEmpty {
                    EmptyLibraryView(libraryService: libraryService)
                } else {
                    BookGridView(
                        books: filteredBooks,
                        selectedBook: $selectedBook
                    )
                }

                // Drop overlay
                DropOverlayView(isTargeted: isDropTargeted)
            }
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
            ToolbarItemGroup(placement: .primaryAction) {
                FileImportButton(libraryService: libraryService)

                Button(action: {}) {
                    Label("WiFi Transfer", systemImage: "wifi")
                }
                .help("Start WiFi transfer server")
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Title") {}
                    Button("Author") {}
                    Button("Date Added") {}
                    Button("Recently Opened") {}
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .alert("Import Complete", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text(result.summary)
            }
        }
        .navigationTitle("Folio")
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var libraryService: LibraryService

    var body: some View {
        List {
            Section("Library") {
                NavigationLink {
                    Text("All Books")
                } label: {
                    Label("All Books", systemImage: "books.vertical")
                        .badge(libraryService.books.count)
                }

                NavigationLink {
                    Text("Recently Added")
                } label: {
                    Label("Recently Added", systemImage: "clock")
                }

                NavigationLink {
                    Text("Recently Opened")
                } label: {
                    Label("Recently Opened", systemImage: "book")
                }
            }

            Section("Browse") {
                NavigationLink {
                    AuthorListView(authors: libraryService.authors)
                } label: {
                    Label("Authors", systemImage: "person.2")
                        .badge(libraryService.authors.count)
                }

                NavigationLink {
                    SeriesListView(series: libraryService.series)
                } label: {
                    Label("Series", systemImage: "text.book.closed")
                        .badge(libraryService.series.count)
                }

                NavigationLink {
                    TagListView(tags: libraryService.tags)
                } label: {
                    Label("Tags", systemImage: "tag")
                        .badge(libraryService.tags.count)
                }
            }

            Section("Formats") {
                ForEach(Array(libraryService.statistics.formatCounts.keys.sorted()), id: \.self) { format in
                    NavigationLink {
                        Text("\(format.uppercased()) Books")
                    } label: {
                        Label(format.uppercased(), systemImage: "doc")
                            .badge(libraryService.statistics.formatCounts[format] ?? 0)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Folio")
    }
}

// MARK: - Book Grid View

struct BookGridView: View {
    let books: [Book]
    @Binding var selectedBook: Book?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books, id: \.id) { book in
                    BookGridItemView(book: book, isSelected: selectedBook == book)
                        .onTapGesture {
                            selectedBook = book
                        }
                        .onTapGesture(count: 2) {
                            openBook(book)
                        }
                }
            }
            .padding()
        }
        .navigationTitle("All Books (\(books.count))")
    }

    private func openBook(_ book: Book) {
        guard let fileURL = book.fileURL else { return }
        NSWorkspace.shared.open(fileURL)

        // Update last opened
        book.lastOpened = Date()
        try? book.managedObjectContext?.save()
    }
}

// MARK: - Book Grid Item

struct BookGridItemView: View {
    let book: Book
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))

                if let coverData = book.coverImageData,
                   let nsImage = NSImage(data: coverData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)

                        Text(book.format?.uppercased() ?? "")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(radius: isSelected ? 5 : 2)

            // Title
            Text(book.title ?? "Unknown")
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Authors
            if let authors = book.authors as? Set<Author>,
               let firstAuthor = authors.first {
                Text(firstAuthor.name ?? "Unknown Author")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Format badge
            HStack(spacing: 4) {
                Text(book.format?.uppercased() ?? "")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())

                Spacer()

                Text(formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
        .contextMenu {
            BookContextMenu(book: book)
        }
    }

    private var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file)
    }
}

// MARK: - Book Context Menu

struct BookContextMenu: View {
    let book: Book

    var body: some View {
        Button("Open") {
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

        Button("Get Info") {
            // TODO: Show info panel
        }

        Button("Edit Metadata...") {
            // TODO: Show metadata editor
        }

        Divider()

        Menu("Convert to...") {
            Button("EPUB") {}
            Button("MOBI") {}
            Button("PDF") {}
            Button("AZW3") {}
        }

        Menu("Send to...") {
            Button("Kindle") {}
            Button("WiFi Transfer") {}
        }

        Divider()

        Button("Delete", role: .destructive) {
            try? LibraryService.shared.deleteBook(book)
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

    var body: some View {
        List(authors, id: \.id) { author in
            NavigationLink {
                Text("Books by \(author.name ?? "Unknown")")
            } label: {
                VStack(alignment: .leading) {
                    Text(author.name ?? "Unknown")
                    if let books = author.books as? Set<Book> {
                        Text("\(books.count) book(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Authors")
    }
}

// MARK: - Series List View

struct SeriesListView: View {
    let series: [Series]

    var body: some View {
        List(series, id: \.id) { s in
            NavigationLink {
                Text("Books in \(s.name ?? "Unknown")")
            } label: {
                VStack(alignment: .leading) {
                    Text(s.name ?? "Unknown")
                    if let books = s.books as? Set<Book> {
                        Text("\(books.count) book(s)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Series")
    }
}

// MARK: - Tag List View

struct TagListView: View {
    let tags: [Tag]

    var body: some View {
        List(tags, id: \.id) { tag in
            NavigationLink {
                Text("Books tagged \(tag.name ?? "Unknown")")
            } label: {
                HStack {
                    Circle()
                        .fill(Color(hex: tag.color ?? "#007AFF") ?? .accentColor)
                        .frame(width: 12, height: 12)

                    Text(tag.name ?? "Unknown")

                    Spacer()

                    if let books = tag.books as? Set<Book> {
                        Text("\(books.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Tags")
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
