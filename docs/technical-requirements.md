# Technical Requirements Document: Folio
**The Beautiful Ebook Library for Mac**

Version: 1.0
Last Updated: January 2025
Status: Active Development

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Technology Stack](#technology-stack)
3. [Phase 1: WiFi-First MVP](#phase-1-wifi-first-mvp)
4. [Phase 2: Intelligence & Polish](#phase-2-intelligence--polish)
5. [Phase 3: Advanced Features](#phase-3-advanced-features)
6. [Performance Requirements](#performance-requirements)
7. [Security & Privacy](#security--privacy)
8. [Testing Strategy](#testing-strategy)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Folio macOS App                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  AppKit UI   │  │   SwiftUI    │  │ Core Data    │  │
│  │ (Grid View)  │  │ (Other Views)│  │  (Database)  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                  │                  │          │
│  ┌──────┴──────────────────┴──────────────────┴───────┐ │
│  │          Library Management Core                    │ │
│  │   (Business Logic, Metadata, File Management)       │ │
│  └──────┬─────────┬──────────┬────────────┬───────────┘ │
│         │         │          │            │              │
│  ┌──────┴────┐ ┌──┴──────┐ ┌─┴────────┐ ┌─┴───────────┐ │
│  │ Calibre   │ │  HTTP   │ │  Email   │ │ USB Device  │ │
│  │ Converter │ │  Server │ │  (SMTP)  │ │   Manager   │ │
│  └───────────┘ └─────────┘ └──────────┘ └─────────────┘ │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │ iCloud Sync
                       │
┌──────────────────────┴──────────────────────────────────┐
│                   Folio iOS App                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │          Pure SwiftUI Interface                      ││
│  └──────────────────┬──────────────────────────────────┘│
│  ┌──────────────────┴──────────────────────────────────┐│
│  │          Library Management Core (Shared)            ││
│  └──────┬──────────────┬──────────────────────────────┘ │
│         │              │                                  │
│  ┌──────┴────┐    ┌────┴──────┐                          │
│  │   HTTP    │    │   Email   │                          │
│  │   Server  │    │  (SMTP)   │                          │
│  └───────────┘    └───────────┘                          │
└─────────────────────────────────────────────────────────┘
```

### Core Components

**1. Library Management Core**
- Singleton service managing all library operations
- Platform-agnostic business logic (shared between macOS/iOS)
- Responsibilities:
  - Book metadata management
  - File organization and indexing
  - Search and filtering
  - Import/export operations

**2. Data Persistence Layer**
- Core Data stack with CloudKit sync
- SQLite backing store
- Entities: Book, Author, Series, Tag, Collection
- Lightweight migrations for schema updates

**3. Conversion Engine**
- Wrapper around Calibre ebook-convert
- Process management for subprocess calls
- Progress tracking and cancellation support
- Error handling and recovery

**4. Transfer Services**
- HTTP Server (Swifter or Vapor lightweight)
- SMTP Email Client (for Send to Kindle)
- USB Device Manager (IOKit on macOS)
- Bonjour Service (NetService)

**5. Metadata Services**
- Google Books API client
- Open Library API client
- Fallback and caching strategy
- Background fetch with URLSession

---

## Technology Stack

### macOS Application

**Language & Frameworks:**
- **Swift 5.9+** (primary language)
- **AppKit** (NSCollectionView for grid - 60fps performance)
- **SwiftUI** (detail views, preferences, auxiliary UI)
- **Core Data** (with CloudKit sync)
- **Combine** (reactive programming)

**Key Dependencies:**
- **Calibre CLI** (bundled - ebook-convert, ebook-meta)
- **Readium Swift Toolkit** (EPUB parsing and reading)
- **Swifter** or **Vapor** (lightweight HTTP server)
- **SwiftyJSON** (JSON parsing for APIs)
- **Kingfisher** or **SDWebImage** (async image loading/caching)

**Build System:**
- Xcode 15+
- Swift Package Manager (SPM) for dependencies
- Minimum deployment: macOS 13 (Ventura)

### iOS Application

**Language & Frameworks:**
- **Swift 5.9+**
- **SwiftUI** (entire UI layer)
- **Core Data** (CloudKit sync with macOS)
- **Combine**

**Key Dependencies:**
- Same HTTP server library (Swifter/Vapor)
- Same metadata API clients
- Kingfisher for images
- Document Picker integration

**Build System:**
- Xcode 15+
- Swift Package Manager
- Minimum deployment: iOS 16

### Shared Code

**Core Logic Shared via Swift Package:**
```
FolioCore/
├── Sources/
│   ├── Models/          # Core Data entities
│   ├── Services/        # Business logic
│   ├── Networking/      # API clients
│   ├── Utilities/       # Extensions, helpers
│   └── Protocols/       # Shared interfaces
└── Tests/
    └── FolioCoreTests/
```

---

## Phase 1: WiFi-First MVP

**Timeline:** 3-4 months (1 developer)
**Goal:** Deliver core ebook management with wireless transfer

### 1.1 Core Data Model

**Entities:**

```swift
// Book.swift
@objc(Book)
public class Book: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var title: String
    @NSManaged public var sortTitle: String? // For proper alphabetization
    @NSManaged public var isbn: String?
    @NSManaged public var isbn13: String?
    @NSManaged public var fileURL: URL
    @NSManaged public var format: String // epub, mobi, pdf, azw3
    @NSManaged public var fileSize: Int64
    @NSManaged public var coverImageData: Data?
    @NSManaged public var coverImageURL: URL?
    @NSManaged public var summary: String?
    @NSManaged public var publishedDate: Date?
    @NSManaged public var dateAdded: Date
    @NSManaged public var dateModified: Date
    @NSManaged public var lastOpened: Date?
    @NSManaged public var pageCount: Int32
    @NSManaged public var language: String?
    @NSManaged public var publisher: String?

    // Relationships
    @NSManaged public var authors: NSSet? // Book -> Author (many-to-many)
    @NSManaged public var series: Series? // Book -> Series (many-to-one)
    @NSManaged public var tags: NSSet? // Book -> Tag (many-to-many)
    @NSManaged public var collections: NSSet? // Book -> Collection (many-to-many)
}

// Author.swift
@objc(Author)
public class Author: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var sortName: String? // "Rowling, J.K."
    @NSManaged public var bio: String?
    @NSManaged public var imageURL: URL?

    @NSManaged public var books: NSSet? // Author -> Book
}

// Series.swift
@objc(Series)
public class Series: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var summary: String?

    @NSManaged public var books: NSSet? // Series -> Book
}

// Tag.swift
@objc(Tag)
public class Tag: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var color: String? // Hex color code

    @NSManaged public var books: NSSet?
}

// Collection.swift
@objc(Collection)
public class Collection: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var iconName: String?
    @NSManaged public var dateCreated: Date

    @NSManaged public var books: NSSet?
}
```

**Indices:**
```swift
// In .xcdatamodeld file, add indices on:
- Book.title
- Book.dateAdded
- Book.lastOpened
- Author.name
- Series.name
```

### 1.2 Library Management Service

**Core Service Interface:**

```swift
// LibraryService.swift
import Foundation
import CoreData
import Combine

public class LibraryService: ObservableObject {
    public static let shared = LibraryService()

    // Core Data stack
    private let persistentContainer: NSPersistentCloudKitContainer

    // Publishers for reactive UI
    @Published public private(set) var books: [Book] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?

    // MARK: - Book Management

    /// Add book to library
    /// - Parameters:
    ///   - fileURL: Local file URL
    ///   - shouldMove: Whether to move file to library location
    /// - Returns: Created Book entity
    public func addBook(from fileURL: URL, shouldMove: Bool = false) async throws -> Book

    /// Import books from directory
    /// - Parameter directoryURL: Folder containing ebooks
    /// - Returns: Count of imported books
    public func importBooks(from directoryURL: URL) async throws -> Int

    /// Delete book (optionally delete file)
    public func deleteBook(_ book: Book, deleteFile: Bool = false) async throws

    /// Update book metadata
    public func updateMetadata(for book: Book, metadata: BookMetadata) async throws

    // MARK: - Search & Filter

    /// Search books by query
    public func searchBooks(query: String) -> [Book]

    /// Filter books by criteria
    public func filterBooks(
        by authors: [Author]?,
        series: Series?,
        tags: [Tag]?,
        format: String?
    ) -> [Book]

    // MARK: - Metadata Enhancement

    /// Fetch metadata for book from APIs
    public func fetchMetadata(for book: Book) async throws -> BookMetadata?

    // MARK: - Watch Folders

    /// Monitor directory for new books
    public func startWatching(directory: URL)

    /// Stop monitoring directory
    public func stopWatching(directory: URL)
}
```

### 1.3 Calibre Integration

**Conversion Service:**

```swift
// CalibreConversionService.swift
import Foundation
import Combine

public class CalibreConversionService {
    public static let shared = CalibreConversionService()

    private let calibreBasePath: URL
    private var activeConversions: [UUID: Process] = [:]

    /// Convert ebook from one format to another
    /// - Parameters:
    ///   - inputURL: Source file
    ///   - outputFormat: Target format (mobi, epub, pdf, azw3)
    ///   - options: Conversion options (profile, quality, etc.)
    /// - Returns: Publisher tracking progress and completion
    public func convert(
        _ inputURL: URL,
        to outputFormat: String,
        options: ConversionOptions = .default
    ) -> AnyPublisher<ConversionProgress, Error> {
        // Implementation:
        // 1. Validate input file exists
        // 2. Create temp output path
        // 3. Build ebook-convert command
        // 4. Execute Process with monitoring
        // 5. Track progress via output parsing
        // 6. Return URL on completion
    }

    /// Cancel ongoing conversion
    public func cancelConversion(id: UUID)

    /// Get metadata from ebook file
    public func getMetadata(from fileURL: URL) async throws -> BookMetadata
}

public struct ConversionOptions {
    var profile: String = "kindle" // kindle, kobo, ipad, etc.
    var preserveEmbeddedMetadata: Bool = true
    var removeDRM: Bool = false // Always false (legal compliance)
    var quality: Int = 90 // Image quality 0-100

    public static let `default` = ConversionOptions()
}

public enum ConversionProgress {
    case started
    case progress(Double) // 0.0 to 1.0
    case completed(URL)
}
```

**Bundling Calibre:**

```bash
# In Xcode build phase, copy Calibre binaries
# macOS/Resources/calibre/
├── ebook-convert
├── ebook-meta
├── ebook-polish
└── lib/ (required dylibs)
```

**Process Execution:**

```swift
// Execute ebook-convert
let process = Process()
process.executableURL = Bundle.main.url(
    forResource: "ebook-convert",
    withExtension: nil,
    subdirectory: "calibre"
)

process.arguments = [
    inputURL.path,
    outputURL.path,
    "--output-profile", options.profile,
    "--mobi-keep-original-images"
]

// Monitor output for progress
let pipe = Pipe()
process.standardOutput = pipe
process.standardError = pipe

pipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    if let output = String(data: data, encoding: .utf8) {
        // Parse progress: "Converted 23% (Chapter 5/21)"
        self.parseProgress(output)
    }
}

try process.run()
process.waitUntilExit()
```

### 1.4 WiFi Transfer - HTTP Server

**HTTP Server Implementation:**

```swift
// HTTPTransferServer.swift
import Foundation
import Swifter

public class HTTPTransferServer: ObservableObject {
    public static let shared = HTTPTransferServer()

    private var server: HttpServer?
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var serverURL: String?

    /// Start HTTP server on available port
    public func start() throws {
        server = HttpServer()

        // Serve web UI
        server["GET", "/"] = { request in
            return .ok(.html(self.generateBookListHTML()))
        }

        // List books as JSON
        server["GET", "/api/books"] = { request in
            let books = LibraryService.shared.books
            let json = try JSONEncoder().encode(books.map { BookDTO(from: $0) })
            return .ok(.data(json, contentType: "application/json"))
        }

        // Download book file
        server["GET", "/api/books/:id/download"] = { request in
            guard let bookID = request.params[":id"],
                  let uuid = UUID(uuidString: bookID),
                  let book = self.getBook(by: uuid),
                  let data = try? Data(contentsOf: book.fileURL) else {
                return .notFound
            }

            return .ok(.data(data, contentType: self.mimeType(for: book.format)))
        }

        // Find available port
        let port: UInt16 = try self.findAvailablePort()
        try server?.start(port)

        // Get local IP
        self.serverURL = "http://\(self.getLocalIPAddress()):\(port)"
        self.isRunning = true
    }

    /// Stop HTTP server
    public func stop() {
        server?.stop()
        isRunning = false
        serverURL = nil
    }

    // MARK: - HTML Generation

    private func generateBookListHTML() -> String {
        let books = LibraryService.shared.books

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Folio - Select Book</title>
            <style>
                body { font-family: -apple-system, sans-serif; padding: 20px; }
                .book { border: 1px solid #ddd; padding: 15px; margin: 10px 0; border-radius: 8px; }
                .book:hover { background: #f5f5f5; }
                .book img { max-width: 100px; height: auto; float: left; margin-right: 15px; }
                .book h3 { margin: 0 0 5px 0; }
                .book p { margin: 0; color: #666; }
                a.download { display: inline-block; margin-top: 10px; padding: 8px 15px;
                             background: #007AFF; color: white; text-decoration: none;
                             border-radius: 5px; }
            </style>
        </head>
        <body>
            <h1>📚 Folio Library</h1>
            <p>Select a book to download to your device</p>
            \(books.map { self.bookHTML($0) }.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private func bookHTML(_ book: Book) -> String {
        let coverImage = book.coverImageURL?.absoluteString ?? ""
        let authors = (book.authors as? Set<Author>)?.map { $0.name }.joined(separator: ", ") ?? "Unknown"

        return """
        <div class="book">
            \(coverImage.isEmpty ? "" : "<img src=\"\(coverImage)\" alt=\"Cover\">")
            <h3>\(book.title)</h3>
            <p>by \(authors)</p>
            <p>Format: \(book.format.uppercased())</p>
            <a href="/api/books/\(book.id.uuidString)/download" class="download">Download</a>
        </div>
        """
    }

    // MARK: - Helpers

    private func findAvailablePort() throws -> UInt16 {
        // Try common ports, fall back to random
        for port in [8080, 8000, 8888, 9000] {
            if isPortAvailable(UInt16(port)) {
                return UInt16(port)
            }
        }
        return UInt16.random(in: 49152...65535)
    }

    private func getLocalIPAddress() -> String {
        var address: String = "localhost"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return address }
        guard let firstAddr = ifaddr else { return address }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
               addr.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                    address = String(cString: hostname)
                }
            }
        }
        freeifaddrs(ifaddr)
        return address
    }
}
```

### 1.5 Send to Kindle Integration

**Email Service:**

```swift
// SendToKindleService.swift
import Foundation

public class SendToKindleService {
    public static let shared = SendToKindleService()

    private let smtpServer = "smtp.gmail.com" // User configurable
    private let smtpPort = 587

    /// Send ebook to Kindle via email
    /// - Parameters:
    ///   - book: Book to send
    ///   - kindleEmail: User's Kindle email (@kindle.com or @free.kindle.com)
    ///   - senderEmail: Approved sender email
    ///   - senderPassword: Email account password (stored in Keychain)
    public func sendToKindle(
        book: Book,
        kindleEmail: String,
        senderEmail: String,
        senderPassword: String
    ) async throws {
        // Validate file size (50MB limit for email)
        guard book.fileSize < 50_000_000 else {
            throw SendToKindleError.fileTooLarge
        }

        // Amazon supports EPUB natively now, but convert if needed
        var fileToSend = book.fileURL
        if book.format == "mobi" || book.format == "azw3" {
            // No conversion needed
        } else if book.format == "epub" || book.format == "pdf" {
            // Amazon converts these formats
        } else {
            // Convert to EPUB first
            fileToSend = try await self.convertToEPUB(book)
        }

        // Create email with attachment
        let email = EmailMessage(
            from: senderEmail,
            to: kindleEmail,
            subject: "Book: \(book.title)",
            body: "Sent from Folio - The Beautiful Ebook Library",
            attachment: fileToSend
        )

        // Send via SMTP
        try await self.sendEmail(email, password: senderPassword)
    }

    /// Validate Kindle email format
    public func validateKindleEmail(_ email: String) -> Bool {
        let pattern = "^[\\w._%+-]+@(kindle\\.com|free\\.kindle\\.com)$"
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    private func sendEmail(_ message: EmailMessage, password: String) async throws {
        // Use SwiftSMTP or similar library
        // Implementation details omitted for brevity
    }
}

public enum SendToKindleError: Error {
    case fileTooLarge
    case invalidKindleEmail
    case emailNotApproved
    case networkError
}
```

### 1.6 USB Device Detection (macOS)

**Device Manager:**

```swift
// USBDeviceManager.swift (macOS only)
import Foundation
import IOKit
import IOKit.usb

public class USBDeviceManager: ObservableObject {
    public static let shared = USBDeviceManager()

    @Published public private(set) var connectedDevices: [EReaderDevice] = []

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    /// Start monitoring for USB device connections
    public func startMonitoring() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort).takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        // Monitor for Kindle devices
        self.registerDeviceNotification(vendorID: 0x1949, productID: 0x0004) // Kindle
        self.registerDeviceNotification(vendorID: 0x1949, productID: 0x0008) // Kindle Keyboard

        // Monitor for Kobo devices
        self.registerDeviceNotification(vendorID: 0x2237, productID: 0x4165) // Kobo

        // Also monitor volume mount events
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(volumeDidMount),
            name: NSWorkspace.didMountNotification,
            object: nil
        )
    }

    /// Transfer book to device
    public func transferBook(_ book: Book, to device: EReaderDevice) async throws {
        guard let mountPoint = device.mountPoint else {
            throw DeviceError.notMounted
        }

        // Determine target directory
        let targetDir = mountPoint.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // Convert format if needed
        var fileToTransfer = book.fileURL
        if book.format != device.preferredFormat {
            fileToTransfer = try await CalibreConversionService.shared.convert(
                book.fileURL,
                to: device.preferredFormat,
                options: .default
            )
        }

        // Copy file
        let destination = targetDir.appendingPathComponent(fileToTransfer.lastPathComponent)
        try FileManager.default.copyItem(at: fileToTransfer, to: destination)

        // Verify transfer
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw DeviceError.transferFailed
        }
    }

    @objc private func volumeDidMount(_ notification: Notification) {
        guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
            return
        }

        // Check if this is an e-reader
        if let device = self.identifyDevice(at: volumeURL) {
            DispatchQueue.main.async {
                self.connectedDevices.append(device)
            }
        }
    }

    private func identifyDevice(at url: URL) -> EReaderDevice? {
        // Check for Kindle (has system/version.txt)
        if FileManager.default.fileExists(atPath: url.appendingPathComponent("system/version.txt").path) {
            return EReaderDevice(type: .kindle, name: "Kindle", mountPoint: url, preferredFormat: "mobi")
        }

        // Check for Kobo (has .kobo directory)
        if FileManager.default.fileExists(atPath: url.appendingPathComponent(".kobo").path) {
            return EReaderDevice(type: .kobo, name: "Kobo", mountPoint: url, preferredFormat: "epub")
        }

        return nil
    }
}

public struct EReaderDevice: Identifiable {
    public let id = UUID()
    public let type: DeviceType
    public let name: String
    public let mountPoint: URL?
    public let preferredFormat: String

    public enum DeviceType {
        case kindle, kobo, nook, generic
    }
}

public enum DeviceError: Error {
    case notMounted
    case transferFailed
    case unsupportedFormat
}
```

### 1.7 macOS UI - Grid View

**AppKit Collection View (for performance):**

```swift
// BookGridViewController.swift
import AppKit

class BookGridViewController: NSViewController {

    private lazy var collectionView: NSCollectionView = {
        let cv = NSCollectionView()
        cv.collectionViewLayout = createGridLayout()
        cv.delegate = self
        cv.dataSource = self
        cv.register(BookGridCell.self, forItemWithIdentifier: BookGridCell.identifier)
        cv.backgroundColors = [.clear]
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        return cv
    }()

    private var books: [Book] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        observeLibraryChanges()
    }

    private func createGridLayout() -> NSCollectionViewLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .absolute(180),
            heightDimension: .absolute(280)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(280)
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: groupSize,
            subitems: [item]
        )
        group.interItemSpacing = .fixed(20)

        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 20
        section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)

        return NSCollectionViewCompositionalLayout(section: section)
    }
}

extension BookGridViewController: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return books.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: BookGridCell.identifier,
            for: indexPath
        ) as! BookGridCell

        item.configure(with: books[indexPath.item])
        return item
    }
}

// BookGridCell.swift
class BookGridCell: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("BookGridCell")

    private let coverImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")

    override func loadView() {
        self.view = NSView()
        setupSubviews()
    }

    func configure(with book: Book) {
        titleLabel.stringValue = book.title
        authorLabel.stringValue = (book.authors as? Set<Author>)?.first?.name ?? "Unknown"

        // Load cover image asynchronously
        if let coverData = book.coverImageData {
            coverImageView.image = NSImage(data: coverData)
        } else if let coverURL = book.coverImageURL {
            ImageCache.shared.loadImage(from: coverURL) { [weak self] image in
                self?.coverImageView.image = image
            }
        } else {
            coverImageView.image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: nil)
        }
    }
}
```

### 1.8 iOS UI - SwiftUI

**Main Library View:**

```swift
// LibraryView.swift
import SwiftUI

struct LibraryView: View {
    @StateObject private var library = LibraryService.shared
    @State private var searchText = ""
    @State private var selectedFilter: FilterOption = .all

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(filteredBooks) { book in
                        NavigationLink(destination: BookDetailView(book: book)) {
                            BookGridItemView(book: book)
                        }
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search books...")
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(FilterOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 20)]
    }

    private var filteredBooks: [Book] {
        let books = library.books

        if searchText.isEmpty {
            return books
        } else {
            return library.searchBooks(query: searchText)
        }
    }
}

// BookGridItemView.swift
struct BookGridItemView: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
            AsyncImage(url: book.coverImageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 140, height: 210)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "book.closed")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 140, height: 210)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .shadow(radius: 4)

            // Title
            Text(book.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(.primary)

            // Author
            if let author = (book.authors as? Set<Author>)?.first {
                Text(author.name)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 140)
    }
}
```

### 1.9 iCloud Sync Configuration

**Core Data + CloudKit Setup:**

```swift
// PersistenceController.swift
import CoreData
import CloudKit

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    init() {
        container = NSPersistentCloudKitContainer(name: "Folio")

        // Configure CloudKit sync
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No store description found")
        }

        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.com.yourname.Folio"
        )

        // Enable persistent history tracking (required for CloudKit)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load Core Data stack: \(error)")
            }
        }

        // Automatically merge changes from CloudKit
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Observe remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processRemoteStoreChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    @objc private func processRemoteStoreChange(_ notification: Notification) {
        // Handle remote changes from other devices
        DispatchQueue.main.async {
            // Refresh UI or notify user
        }
    }
}
```

**File Sync Strategy:**

```swift
// Note: Core Data syncs metadata, but book FILES need separate handling

// Option 1: Store files in iCloud Drive (user-visible)
// ~/Library/Mobile Documents/iCloud~com~yourname~Folio/Books/

// Option 2: Store file URLs only, don't sync actual files
// - Smaller iCloud footprint
// - User manually keeps files in Dropbox/Google Drive
// - App indexes from multiple locations

// Recommended: Option 2 for Phase 1 (less complex)
```

---

## Phase 2: Intelligence & Polish

**Timeline:** 2-3 months
**Goal:** Add smart features, improve UX, expand compatibility

### 2.1 Bonjour Auto-Discovery

**Service Advertisement:**

```swift
// BonjourService.swift
import Foundation

class BonjourService: NSObject, ObservableObject {
    private var netService: NetService?
    @Published var isPublishing = false

    func startPublishing(port: UInt16) {
        // Advertise HTTP server via Bonjour
        netService = NetService(
            domain: "local.",
            type: "_folio._tcp.",
            name: "Folio Library",
            port: Int32(port)
        )

        netService?.delegate = self
        netService?.publish()
        isPublishing = true
    }

    func stopPublishing() {
        netService?.stop()
        isPublishing = false
    }
}

extension BonjourService: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("Bonjour service published: \(sender.name)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("Failed to publish Bonjour service: \(errorDict)")
    }
}
```

### 2.2 QR Code Connection

**QR Code Generation:**

```swift
// QRCodeView.swift (macOS/iOS)
import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let url: String

    var body: some View {
        VStack(spacing: 20) {
            Text("Scan to Connect")
                .font(.headline)

            Image(uiImage: generateQRCode(from: url))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)

            Text(url)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        if let outputImage = filter.outputImage {
            let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }

        return UIImage(systemName: "xmark") ?? UIImage()
    }
}
```

### 2.3 On-Device LLM Integration (macOS)

**MLX Model Integration:**

```swift
// LLMMetadataService.swift (macOS only)
import Foundation
// import MLX // Apple's MLX framework

class LLMMetadataService {
    static let shared = LLMMetadataService()

    private var model: Any? // MLXModel placeholder
    private let modelPath = "models/llama-3.2-3b-q4" // Quantized model

    /// Load LLM model (lazy loading)
    func loadModel() async throws {
        guard model == nil else { return }

        // Load quantized 3B model from app resources
        // model = try await MLXModel.load(from: modelPath)
        // Placeholder - actual MLX implementation
    }

    /// Enhance book metadata using LLM
    func enhanceMetadata(for book: Book) async throws -> EnhancedMetadata {
        try await loadModel()

        // Prepare prompt
        let prompt = """
        Analyze this book and extract metadata:

        Title: \(book.title)
        Description: \(book.summary ?? "N/A")

        Please provide:
        1. Primary genre (single word)
        2. 3-5 relevant tags
        3. Mood/tone (e.g., dark, light, suspenseful)
        4. Recommended age range

        Format as JSON:
        """

        // Run inference (placeholder)
        // let response = try await model?.generate(prompt: prompt)
        let response = "{}" // Placeholder

        return try JSONDecoder().decode(EnhancedMetadata.self, from: response.data(using: .utf8)!)
    }

    /// Unload model to free memory
    func unloadModel() {
        model = nil
    }
}

struct EnhancedMetadata: Codable {
    let genre: String
    let tags: [String]
    let mood: String
    let ageRange: String
}
```

**Background Processing:**

```swift
// Batch enhance metadata for entire library
func enhanceLibraryMetadata() async {
    let books = LibraryService.shared.books.filter { $0.summary != nil }

    for book in books {
        do {
            let enhanced = try await LLMMetadataService.shared.enhanceMetadata(for: book)

            // Apply enhancements
            await MainActor.run {
                book.tags = Set(enhanced.tags.map { Tag(name: $0) })
                // Update other fields
                try? LibraryService.shared.save()
            }

            // Add delay to avoid thermal throttling
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        } catch {
            print("Failed to enhance \(book.title): \(error)")
        }
    }

    // Unload model when done
    LLMMetadataService.shared.unloadModel()
}
```

---

## Phase 3: Advanced Features

**Timeline:** Ongoing/iterative
**Goal:** Power user features, community building

### 3.1 OPDS Protocol Support

**OPDS Feed Generation:**

```swift
// OPDSServer.swift
import Foundation
import Swifter

class OPDSServer {
    private var server: HttpServer?

    /// Start OPDS catalog server
    func start(on port: UInt16) throws {
        server = HttpServer()

        // Root catalog
        server?["/opds"] = { request in
            return .ok(.xml(self.generateRootCatalog()))
        }

        // Acquisition feed (books)
        server?["/opds/books"] = { request in
            return .ok(.xml(self.generateBooksFeed()))
        }

        // Book entry
        server?["/opds/books/:id"] = { request in
            guard let bookID = request.params[":id"],
                  let uuid = UUID(uuidString: bookID) else {
                return .notFound
            }
            return .ok(.xml(self.generateBookEntry(uuid)))
        }

        try server?.start(port)
    }

    private func generateRootCatalog() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <id>urn:uuid:\(UUID().uuidString)</id>
            <title>Folio Library</title>
            <updated>\(ISO8601DateFormatter().string(from: Date()))</updated>
            <author>
                <name>Folio</name>
            </author>
            <link rel="self" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
            <link rel="start" href="/opds" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>

            <entry>
                <title>All Books</title>
                <link rel="subsection" href="/opds/books" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
                <updated>\(ISO8601DateFormatter().string(from: Date()))</updated>
                <id>all-books</id>
                <content type="text">Browse all books in library</content>
            </entry>
        </feed>
        """
    }

    private func generateBooksFeed() -> String {
        let books = LibraryService.shared.books

        let entries = books.map { book in
            """
            <entry>
                <title>\(book.title.xmlEscaped)</title>
                <id>urn:uuid:\(book.id)</id>
                <updated>\(ISO8601DateFormatter().string(from: book.dateModified))</updated>
                <author><name>\((book.authors as? Set<Author>)?.first?.name ?? "Unknown")</name></author>
                <link rel="http://opds-spec.org/acquisition"
                      href="/api/books/\(book.id)/download"
                      type="application/epub+zip"/>
                <summary>\(book.summary?.xmlEscaped ?? "")</summary>
            </entry>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
            <id>all-books</id>
            <title>All Books</title>
            <updated>\(ISO8601DateFormatter().string(from: Date()))</updated>
            <link rel="self" href="/opds/books" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
            \(entries)
        </feed>
        """
    }
}

extension String {
    var xmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
```

---

## Performance Requirements

### Startup Performance

**Target:** <3 seconds cold start

**Optimization Strategy:**
1. **Lazy Loading:**
   - Load visible books first (first 50-100)
   - Defer metadata service initialization
   - Lazy initialize Calibre wrapper

2. **Background Initialization:**
   ```swift
   // Launch sequence
   func application(_ application: NSApplication) {
       // Critical path (main thread)
       - Initialize Core Data stack (lightweight)
       - Load UI scaffolding
       - Display initial books (from cache)

       // Background thread
       DispatchQueue.global(qos: .utility).async {
           - Initialize metadata services
           - Start file system watchers
           - Sync with iCloud
           - Warm up conversion service
       }
   }
   ```

3. **Caching:**
   - Cache cover images on disk
   - Cache search indices in memory
   - Persist UI state (scroll position, filters)

### Library Loading Performance

**Target:** <2 seconds for 5,000 books

**Implementation:**
```swift
// Use NSFetchedResultsController with batching
let fetchRequest = Book.fetchRequest()
fetchRequest.fetchBatchSize = 50
fetchRequest.sortDescriptors = [NSSortDescriptor(key: "dateAdded", ascending: false)]

let controller = NSFetchedResultsController(
    fetchRequest: fetchRequest,
    managedObjectContext: context,
    sectionNameKeyPath: nil,
    cacheName: "BooksCache"
)
```

### Search Performance

**Target:** <100ms response time

**Optimization:**
```swift
// Core Data indices + in-memory filtering
class SearchService {
    private var searchIndex: [String: [Book]] = [:]

    func buildIndex() {
        // Build trigram index for fuzzy search
        for book in books {
            let trigrams = book.title.trigrams()
            for trigram in trigrams {
                searchIndex[trigram, default: []].append(book)
            }
        }
    }

    func search(_ query: String) -> [Book] {
        // O(1) lookup via index
        let queryTrigrams = query.trigrams()
        var results: Set<Book> = []

        for trigram in queryTrigrams {
            if let matches = searchIndex[trigram] {
                results.formUnion(matches)
            }
        }

        return Array(results).sorted { $0.title < $1.title }
    }
}
```

### Conversion Performance

**Target:** <5 seconds for typical book

**Metrics to Track:**
- Input file size
- Output file size
- Conversion time
- Success/failure rate
- Memory usage during conversion

**Optimization:**
```swift
// Parallel conversion queue
let conversionQueue = OperationQueue()
conversionQueue.maxConcurrentOperationCount = ProcessInfo.processInfo.processorCount

// Add conversion job
let operation = BlockOperation {
    try CalibreConversionService.shared.convert(book, to: format)
}
conversionQueue.addOperation(operation)
```

---

## Security & Privacy

### Data Protection

**File Encryption:**
```swift
// Enable Data Protection for app container
// In entitlements:
<key>com.apple.developer.default-data-protection</key>
<string>NSFileProtectionComplete</string>
```

**Keychain Storage:**
```swift
// Store sensitive data (email passwords) in Keychain
class KeychainService {
    func save(password: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: password.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        SecItemDelete(query as CFDictionary) // Remove existing
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }
}
```

### Network Security

**HTTPS for Metadata APIs:**
```swift
// Enforce HTTPS for all network requests
let configuration = URLSessionConfiguration.default
configuration.urlCache = URLCache.shared
configuration.requestCachePolicy = .returnCacheDataElseLoad
configuration.tlsMinimumSupportedProtocolVersion = .TLSv12

let session = URLSession(configuration: configuration)
```

**Local HTTP Server Security:**
```swift
// Only bind to localhost/local network (not public)
// No authentication required (local network trust model)
// Optional: Add simple token-based auth for paranoid users
```

### Privacy Compliance

**No Telemetry (Default):**
- Zero data collection
- No analytics
- No crash reporting (unless user opts in)

**Optional Opt-In Analytics:**
```swift
// If user enables analytics
struct AnalyticsEvent: Codable {
    let eventName: String // e.g., "book_imported", "wifi_transfer_success"
    let timestamp: Date
    let anonymousID: UUID // Randomly generated, not tied to user
    // No PII (personally identifiable information)
    // No book titles, authors, or content
}
```

**Privacy Manifest (App Privacy Report):**
```xml
<!-- PrivacyInfo.xcprivacy -->
<key>NSPrivacyTracking</key>
<false/>
<key>NSPrivacyCollectedDataTypes</key>
<array/>
<key>NSPrivacyTrackingDomains</key>
<array/>
```

---

## Testing Strategy

### Unit Tests

**Coverage Target:** >80% for business logic

**Key Areas:**
```swift
// LibraryServiceTests.swift
class LibraryServiceTests: XCTestCase {
    func testAddBook() {
        // Given: Valid EPUB file
        // When: Add to library
        // Then: Book entity created, file copied
    }

    func testSearchBooks() {
        // Given: Library with 100 books
        // When: Search for "Harry Potter"
        // Then: Returns matching books in <100ms
    }

    func testFilterBooks() {
        // Given: Books with various genres
        // When: Filter by genre
        // Then: Returns only matching books
    }
}

// CalibreConversionServiceTests.swift
class ConversionTests: XCTestCase {
    func testEPUBToMOBI() async throws {
        // Given: Sample EPUB file
        // When: Convert to MOBI
        // Then: Valid MOBI file created
    }

    func testConversionPerformance() async throws {
        // Given: 500KB EPUB
        // When: Convert to MOBI
        // Then: Completes in <5 seconds
    }
}
```

### Integration Tests

**Test Scenarios:**
1. End-to-end import workflow
2. WiFi transfer from macOS to iOS
3. Send to Kindle integration
4. iCloud sync between devices
5. USB device detection and transfer

### UI Tests

**Critical Paths:**
```swift
// LibraryUITests.swift
class LibraryUITests: XCTestCase {
    func testImportBook() {
        // Given: macOS app launched
        // When: Drag EPUB file onto window
        // Then: Book appears in grid within 3 seconds
    }

    func testWiFiTransfer() {
        // Given: HTTP server running
        // When: Open Safari to server URL
        // Then: Book list appears, download works
    }
}
```

### Performance Testing

**Instruments Profiles:**
- Time Profiler (identify bottlenecks)
- Allocations (memory leaks, retain cycles)
- Leaks (find memory leaks)
- Network (API call performance)
- File Activity (disk I/O optimization)

**Load Testing:**
```swift
// Test with varying library sizes
func testLibraryScaling() {
    measure {
        // Load library with 1K, 5K, 10K books
        // Measure startup time, search time, scroll performance
    }
}
```

### Beta Testing Plan

**Phase 1 Beta:**
- 50-100 users
- TestFlight distribution
- Focus on WiFi transfer reliability
- Gather conversion quality feedback
- Monitor crash reports

**Phase 2 Beta:**
- 200-500 users
- Test LLM features
- Performance testing on various hardware
- macOS/iOS sync testing

---

## Development Tools & Setup

### Xcode Configuration

**Project Structure:**
```
Folio.xcodeproj
├── Folio (macOS)
│   ├── App
│   ├── Views
│   ├── Services
│   ├── Models
│   ├── Resources
│   └── Info.plist
├── Folio (iOS)
│   ├── App
│   ├── Views
│   ├── Services
│   └── Info.plist
├── FolioCore (Shared Package)
│   ├── Sources
│   └── Tests
└── FolioTests
```

### Swift Package Dependencies

**Package.swift:**
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FolioCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/readium/swift-toolkit.git", from: "2.6.0"),
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
        // Add other dependencies
    ],
    targets: [
        .target(
            name: "FolioCore",
            dependencies: [
                .product(name: "ReadiumShared", package: "swift-toolkit"),
                .product(name: "Swifter", package: "swifter")
            ]
        ),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"]
        )
    ]
)
```

### Git Workflow

**Branch Strategy:**
```bash
main            # Stable, release-ready
develop         # Integration branch
feature/*       # Feature branches
bugfix/*        # Bug fixes
release/*       # Release candidates
```

**Commit Conventions:**
```
feat: Add WiFi transfer HTTP server
fix: Resolve Core Data merge conflict
docs: Update technical requirements
test: Add conversion performance tests
refactor: Extract metadata service protocol
```

---

## Deployment

### App Store Submission

**macOS App:**
- Sandbox enabled (with file access entitlements)
- Hardened Runtime enabled
- Notarization required
- App category: Productivity

**iOS App:**
- Standard App Store submission
- App category: Productivity
- Required permissions: Local Network, Photo Library (for covers)

### Open Source Release

**GitHub Repository:**
```
https://github.com/yourusername/folio
├── README.md
├── LICENSE (GPL v3)
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── docs/
│   ├── installation.md
│   ├── development.md
│   └── architecture.md
└── .github/
    ├── ISSUE_TEMPLATE/
    └── workflows/ (CI/CD)
```

**Release Process:**
1. Tag release (v1.0.0)
2. Generate release notes
3. Build signed binaries
4. Upload to GitHub Releases
5. Submit to App Store
6. Update website/documentation

---

**End of Technical Requirements Document**

This document will be updated as implementation progresses and new requirements emerge.
