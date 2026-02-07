// HTTPTransferServer.swift
// WiFi transfer HTTP server for Folio

import Foundation
import Swifter
import Combine

// MARK: - Book Provider Protocol

/// Protocol for providing books to the HTTP transfer server
/// This allows the server to work independently of LibraryService
public protocol HTTPTransferBookProvider: AnyObject {
    /// Get all books available for transfer
    func getAllBooks() -> [BookDTO]

    /// Get the file URL for a book by its ID
    func getBookFileURL(id: String) -> URL?

    /// Get the format for a book by its ID
    func getBookFormat(id: String) -> EbookFormat?
}

// MARK: - HTTP Transfer Server

/// HTTP server for WiFi book transfer to mobile devices
/// Provides a mobile-friendly web interface and JSON API for downloading books
@MainActor
public final class HTTPTransferServer: ObservableObject {

    // MARK: - Published Properties

    /// Whether the server is currently running
    @Published public private(set) var isRunning: Bool = false

    /// The full URL where the server is accessible (e.g., "http://192.168.1.100:8080")
    @Published public private(set) var serverURL: String?

    /// The port the server is running on
    @Published public private(set) var port: UInt16 = 0

    /// Number of active downloads
    @Published public private(set) var activeDownloads: Int = 0

    // MARK: - Private Properties

    private var server: HttpServer?
    private weak var bookProvider: HTTPTransferBookProvider?

    /// Port range to try when starting the server
    private let portRange: ClosedRange<UInt16> = 8080...8180

    // MARK: - Initialization

    public init() {}

    /// Initialize with a book provider
    public init(bookProvider: HTTPTransferBookProvider) {
        self.bookProvider = bookProvider
    }

    // MARK: - Public Methods

    /// Set the book provider
    public func setBookProvider(_ provider: HTTPTransferBookProvider) {
        self.bookProvider = provider
    }

    /// Start the HTTP server
    /// - Throws: TransferError if no port is available
    public func start() throws {
        guard !isRunning else {
            logger.warning("Server is already running")
            return
        }

        let httpServer = HttpServer()

        // Configure routes
        configureRoutes(httpServer)

        // Find available port and start
        var startedPort: UInt16?

        for testPort in portRange {
            do {
                try httpServer.start(testPort, forceIPv4: true)
                startedPort = testPort
                logger.info("HTTP server started on port \(testPort)")
                break
            } catch {
                logger.debug("Port \(testPort) unavailable, trying next...")
                continue
            }
        }

        guard let port = startedPort else {
            logger.error("No available port found in range \(portRange)")
            throw TransferError.portUnavailable
        }

        self.server = httpServer
        self.port = port
        self.isRunning = true

        // Build server URL with local IP
        if let ipAddress = getLocalIPAddress() {
            self.serverURL = "http://\(ipAddress):\(port)"
            logger.info("Server accessible at \(self.serverURL ?? "unknown")")
        } else {
            self.serverURL = "http://localhost:\(port)"
            logger.warning("Could not determine local IP, using localhost")
        }
    }

    /// Stop the HTTP server
    public func stop() {
        guard isRunning else { return }

        server?.stop()
        server = nil
        isRunning = false
        serverURL = nil
        port = 0
        activeDownloads = 0

        logger.info("HTTP server stopped")
    }

    // MARK: - Private Methods

    /// Configure all HTTP routes
    private func configureRoutes(_ server: HttpServer) {
        // HTML page with book list
        server["/"] = { [weak self] request in
            guard let self = self else {
                return .internalServerError
            }
            return self.handleHTMLRequest()
        }

        // JSON API: Get all books
        server["/api/books"] = { [weak self] request in
            guard let self = self else {
                return .internalServerError
            }
            return self.handleBooksAPIRequest()
        }

        // JSON API: Download book
        server["/api/books/:id/download"] = { [weak self] request in
            guard let self = self else {
                return .internalServerError
            }
            let bookId = request.params[":id"] ?? ""
            return self.handleDownloadRequest(bookId: bookId)
        }

        // Serve cover images
        server["/api/books/:id/cover"] = { [weak self] request in
            guard let self = self else {
                return .internalServerError
            }
            let bookId = request.params[":id"] ?? ""
            return self.handleCoverRequest(bookId: bookId)
        }
    }

    /// Handle request for HTML book list page
    private func handleHTMLRequest() -> HttpResponse {
        let books = bookProvider?.getAllBooks() ?? []
        let html = generateHTMLPage(books: books)
        return .ok(.html(html))
    }

    /// Handle JSON API request for books list
    private func handleBooksAPIRequest() -> HttpResponse {
        let books = bookProvider?.getAllBooks() ?? []

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(books)

            return .ok(.data(jsonData, contentType: "application/json"))
        } catch {
            logger.error("Failed to encode books to JSON: \(error)")
            return .internalServerError
        }
    }

    /// Handle download request for a specific book
    private func handleDownloadRequest(bookId: String) -> HttpResponse {
        guard let provider = bookProvider else {
            logger.error("No book provider configured")
            return .internalServerError
        }

        guard let fileURL = provider.getBookFileURL(id: bookId) else {
            logger.warning("Book not found: \(bookId)")
            return .notFound
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("Book file does not exist: \(fileURL.path)")
            return .notFound
        }

        // Get format for MIME type
        let format = provider.getBookFormat(id: bookId)
        let mimeType = format?.mimeType ?? "application/octet-stream"
        let filename = fileURL.lastPathComponent

        // Increment active downloads
        Task { @MainActor in
            self.activeDownloads += 1
        }

        logger.info("Starting download: \(filename)")

        do {
            let fileData = try Data(contentsOf: fileURL)

            // Decrement active downloads when done
            Task { @MainActor in
                self.activeDownloads -= 1
            }

            logger.info("Download completed: \(filename)")

            // Return file with proper headers
            return .raw(200, "OK", [
                "Content-Type": mimeType,
                "Content-Disposition": "attachment; filename=\"\(filename)\"",
                "Content-Length": "\(fileData.count)"
            ]) { writer in
                try writer.write(fileData)
            }
        } catch {
            Task { @MainActor in
                self.activeDownloads -= 1
            }
            logger.error("Failed to read book file: \(error)")
            return .internalServerError
        }
    }

    /// Handle cover image request
    private func handleCoverRequest(bookId: String) -> HttpResponse {
        // Placeholder - would need cover URL from provider
        // For now, return a placeholder or 404
        return .notFound
    }

    /// Generate mobile-friendly HTML page
    private func generateHTMLPage(books: [BookDTO]) -> String {
        let bookRows = books.map { book -> String in
            let authors = book.authors.joined(separator: ", ")
            let sizeFormatted = formatFileSize(book.fileSize)
            let formatUpper = book.format.uppercased()

            return """
            <div class="book-card">
                <div class="book-info">
                    <h2 class="book-title">\(escapeHTML(book.title))</h2>
                    <p class="book-author">\(escapeHTML(authors.isEmpty ? "Unknown Author" : authors))</p>
                    <div class="book-meta">
                        <span class="format-badge">\(formatUpper)</span>
                        <span class="file-size">\(sizeFormatted)</span>
                    </div>
                </div>
                <a href="/api/books/\(book.id)/download" class="download-btn" download>
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                        <polyline points="7 10 12 15 17 10"/>
                        <line x1="12" y1="15" x2="12" y2="3"/>
                    </svg>
                    Download
                </a>
            </div>
            """
        }.joined(separator: "\n")

        let emptyState = books.isEmpty ? """
            <div class="empty-state">
                <svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="#999" stroke-width="1.5">
                    <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/>
                    <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>
                </svg>
                <h2>No Books Available</h2>
                <p>Add some books to your Folio library to transfer them here.</p>
            </div>
            """ : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>Folio Library</title>
            <style>
                * {
                    box-sizing: border-box;
                    margin: 0;
                    padding: 0;
                }

                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    min-height: 100vh;
                    color: #fff;
                    padding: 0;
                }

                .header {
                    background: rgba(255, 255, 255, 0.05);
                    backdrop-filter: blur(10px);
                    padding: 1.5rem;
                    text-align: center;
                    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
                    position: sticky;
                    top: 0;
                    z-index: 100;
                }

                .header h1 {
                    font-size: 1.5rem;
                    font-weight: 600;
                    letter-spacing: 0.5px;
                }

                .header .subtitle {
                    font-size: 0.875rem;
                    color: rgba(255, 255, 255, 0.6);
                    margin-top: 0.25rem;
                }

                .book-count {
                    font-size: 0.75rem;
                    color: rgba(255, 255, 255, 0.5);
                    margin-top: 0.5rem;
                }

                .container {
                    max-width: 600px;
                    margin: 0 auto;
                    padding: 1rem;
                }

                .book-card {
                    background: rgba(255, 255, 255, 0.08);
                    border-radius: 12px;
                    padding: 1rem;
                    margin-bottom: 0.75rem;
                    display: flex;
                    align-items: center;
                    gap: 1rem;
                    border: 1px solid rgba(255, 255, 255, 0.1);
                    transition: transform 0.2s, background 0.2s;
                }

                .book-card:active {
                    transform: scale(0.98);
                    background: rgba(255, 255, 255, 0.12);
                }

                .book-info {
                    flex: 1;
                    min-width: 0;
                }

                .book-title {
                    font-size: 1rem;
                    font-weight: 600;
                    margin-bottom: 0.25rem;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                }

                .book-author {
                    font-size: 0.875rem;
                    color: rgba(255, 255, 255, 0.7);
                    margin-bottom: 0.5rem;
                    white-space: nowrap;
                    overflow: hidden;
                    text-overflow: ellipsis;
                }

                .book-meta {
                    display: flex;
                    align-items: center;
                    gap: 0.5rem;
                }

                .format-badge {
                    background: rgba(99, 102, 241, 0.3);
                    color: #a5b4fc;
                    padding: 0.2rem 0.5rem;
                    border-radius: 4px;
                    font-size: 0.7rem;
                    font-weight: 600;
                    letter-spacing: 0.5px;
                }

                .file-size {
                    font-size: 0.75rem;
                    color: rgba(255, 255, 255, 0.5);
                }

                .download-btn {
                    display: flex;
                    align-items: center;
                    gap: 0.5rem;
                    background: linear-gradient(135deg, #6366f1 0%, #8b5cf6 100%);
                    color: white;
                    padding: 0.75rem 1rem;
                    border-radius: 8px;
                    text-decoration: none;
                    font-weight: 500;
                    font-size: 0.875rem;
                    white-space: nowrap;
                    transition: opacity 0.2s;
                    flex-shrink: 0;
                }

                .download-btn:active {
                    opacity: 0.8;
                }

                .empty-state {
                    text-align: center;
                    padding: 4rem 2rem;
                    color: rgba(255, 255, 255, 0.6);
                }

                .empty-state svg {
                    margin-bottom: 1rem;
                }

                .empty-state h2 {
                    font-size: 1.25rem;
                    margin-bottom: 0.5rem;
                    color: rgba(255, 255, 255, 0.8);
                }

                .empty-state p {
                    font-size: 0.875rem;
                }

                .footer {
                    text-align: center;
                    padding: 2rem 1rem;
                    color: rgba(255, 255, 255, 0.4);
                    font-size: 0.75rem;
                }

                .footer a {
                    color: rgba(255, 255, 255, 0.6);
                    text-decoration: none;
                }

                @media (max-width: 400px) {
                    .download-btn span {
                        display: none;
                    }

                    .download-btn {
                        padding: 0.75rem;
                    }
                }
            </style>
        </head>
        <body>
            <header class="header">
                <h1>Folio Library</h1>
                <p class="subtitle">WiFi Book Transfer</p>
                <p class="book-count">\(books.count) book\(books.count == 1 ? "" : "s") available</p>
            </header>

            <main class="container">
                \(books.isEmpty ? emptyState : bookRows)
            </main>

            <footer class="footer">
                <p>Powered by <a href="https://github.com/user/folio">Folio</a></p>
            </footer>
        </body>
        </html>
        """
    }

    /// Get local IP address for display
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee else { continue }

            let addrFamily = interface.ifa_addr.pointee.sa_family

            // Check for IPv4
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Skip loopback interface
                if name == "lo0" { continue }

                // Prefer en0 (WiFi on Mac) or en1
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)

                    // If we found en0, prefer it
                    if name == "en0" { break }
                }
            }
        }

        return address
    }

    /// Format file size for display
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useKB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Escape HTML special characters
    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
