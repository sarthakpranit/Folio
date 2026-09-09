// HTTPTransferServer.swift
// WiFi transfer HTTP server for Folio

import Foundation
@preconcurrency import Swifter
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

    /// Get the security-scoped bookmark data for a book (for external volume access)
    func getBookmarkData(id: String) -> Data?

    /// Get book metadata (title, authors) for conversion
    func getBookMetadata(id: String) -> (title: String, authors: [String])?
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

    /// Cache directory for converted files
    private lazy var conversionCacheURL: URL = {
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("FolioKindleCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }()

    /// Conversion service for Kindle format conversion
    private let conversionService = CalibreConversionService.shared

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
            logger.error("No available port found in range \(self.portRange)")
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

        // Kindle-compatible download (converts to MOBI if needed)
        server["/api/books/:id/kindle"] = { [weak self] request in
            guard let self = self else {
                return .internalServerError
            }
            let bookId = request.params[":id"] ?? ""
            return self.handleKindleDownloadRequest(bookId: bookId)
        }
    }

    /// Handle request for HTML book list page
    private func handleHTMLRequest() -> HttpResponse {
        let books = bookProvider?.getAllBooks() ?? []
        let html = libraryTransferPage(books: books, calibreAvailable: conversionService.isCalibreAvailable)
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

    /// Resolve a book's security-scoped bookmark (if it has one) and begin
    /// access, falling back to direct access on `fileURL`.
    /// - Returns: the URL to read from, and whether the caller must call
    ///   `stopAccessingSecurityScopedResource()` on it when done.
    private func beginSecurityScopedAccess(fileURL: URL, bookmarkData: Data?) -> (url: URL, started: Bool) {
        if let bookmarkData {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if resolved.startAccessingSecurityScopedResource() {
                    return (resolved, true)
                }
            } catch {
                logger.warning("Failed to resolve bookmark, using direct access: \(error.localizedDescription)")
            }
        }
        return (fileURL, fileURL.startAccessingSecurityScopedResource())
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

        // Get format for MIME type
        let format = provider.getBookFormat(id: bookId)
        let mimeType = format?.mimeType ?? "application/octet-stream"
        let filename = fileURL.lastPathComponent

        logger.info("Starting download: \(filename)")

        let (finalURL, stopAccess) = beginSecurityScopedAccess(
            fileURL: fileURL,
            bookmarkData: provider.getBookmarkData(id: bookId)
        )

        // Open the file and read its size for Content-Length before we commit
        // to a 200 response.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: finalURL.path),
              let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: finalURL) else {
            if stopAccess { finalURL.stopAccessingSecurityScopedResource() }
            logger.error("Book file not readable: \(finalURL.path)")
            return .notFound
        }

        // Count the download only while it is actually streaming, and clear the
        // count (and security scope) when the body finishes — not before.
        Task { @MainActor in self.activeDownloads += 1 }
        logger.info("Streaming download: \(filename) (\(fileSize) bytes)")

        return streamingFileResponse(
            handle: handle,
            size: fileSize,
            headers: [
                "Content-Type": mimeType,
                "Content-Disposition": "attachment; filename=\"\(filename)\""
            ],
            onFinish: { [weak self] in
                if stopAccess { finalURL.stopAccessingSecurityScopedResource() }
                Task { @MainActor in self?.activeDownloads -= 1 }
                logger.info("Download completed: \(filename)")
            }
        )
    }

    /// Handle Kindle-compatible download request
    /// Converts non-MOBI formats to MOBI on-the-fly for Kindle browser compatibility
    private func handleKindleDownloadRequest(bookId: String) -> HttpResponse {
        guard let provider = bookProvider else {
            logger.error("No book provider configured")
            return .internalServerError
        }

        guard let fileURL = provider.getBookFileURL(id: bookId) else {
            logger.warning("Book not found: \(bookId)")
            return .notFound
        }

        let format = provider.getBookFormat(id: bookId)
        let originalFilename = fileURL.lastPathComponent

        // If already MOBI/AZW3/PRC, serve directly
        if let fmt = format, fmt.kindleNativeFormat {
            logger.info("Book already Kindle-compatible, serving directly: \(originalFilename)")
            return handleDownloadRequest(bookId: bookId)
        }

        // Check if Calibre is available for conversion
        guard conversionService.isCalibreAvailable else {
            logger.error("Calibre not available for Kindle conversion")
            return htmlResponse(503, "Service Unavailable", transferStatusPage(
                title: "Conversion Unavailable",
                message: "Calibre is required to convert this book to Kindle format. Install Calibre on the Mac, or use Send to Kindle instead."
            ))
        }

        // Check cache first
        let cacheFilename = "\(bookId).mobi"
        let cachedURL = conversionCacheURL.appendingPathComponent(cacheFilename)
        let failureMarkerURL = conversionCacheURL.appendingPathComponent("\(bookId).error")

        if FileManager.default.fileExists(atPath: cachedURL.path) {
            logger.info("Serving cached Kindle conversion: \(cacheFilename)")
            return serveFile(at: cachedURL, originalTitle: fileURL.deletingPathExtension().lastPathComponent)
        }

        // A previous background conversion for this book failed. Show it once,
        // then clear the marker so a fresh request retries.
        if let reason = try? String(contentsOf: failureMarkerURL, encoding: .utf8) {
            try? FileManager.default.removeItem(at: failureMarkerURL)
            return htmlResponse(500, "Conversion Failed", transferStatusPage(
                title: "Conversion Failed",
                message: "Folio couldn’t convert this book to a Kindle format. Reload to try again, or use Send to Kindle instead.",
                detail: reason
            ))
        }

        // Need to convert - resolve security-scoped access first
        let (accessibleURL, didStartAccessing) = beginSecurityScopedAccess(
            fileURL: fileURL,
            bookmarkData: provider.getBookmarkData(id: bookId)
        )

        guard FileManager.default.fileExists(atPath: accessibleURL.path) else {
            if didStartAccessing {
                accessibleURL.stopAccessingSecurityScopedResource()
            }
            logger.error("Source file not accessible for conversion")
            return .notFound
        }

        // Kick the conversion off in the background and return immediately (#60).
        // Blocking this Swifter handler thread on the conversion (previously a
        // `DispatchSemaphore.wait` for up to 300 s) starved the whole handler
        // pool — a few concurrent /kindle requests froze plain downloads and the
        // library page. The conversion writes into the cache; the client is told
        // to come back, and the auto-refreshing page then hits the cache branch
        // above and downloads.
        logger.info("Starting background MOBI conversion for Kindle: \(originalFilename)")

        let metadata = provider.getBookMetadata(id: bookId)
        let bookTitle = metadata?.title ?? fileURL.deletingPathExtension().lastPathComponent
        let bookAuthors = metadata?.authors.joined(separator: " & ") ?? ""
        let cacheDirectory = conversionCacheURL

        Task { @MainActor in self.activeDownloads += 1 }

        Task.detached { [conversionService] in
            defer {
                if didStartAccessing {
                    accessibleURL.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let baseOptions = ConversionOptions.kindle()
                var metadataArgs = ["--title", bookTitle]
                if !bookAuthors.isEmpty {
                    metadataArgs.append(contentsOf: ["--authors", bookAuthors])
                }

                let outputURL = try await conversionService.convert(
                    accessibleURL,
                    to: "mobi",
                    options: ConversionOptions(
                        profile: baseOptions.profile,
                        preserveEmbeddedMetadata: baseOptions.preserveEmbeddedMetadata,
                        quality: baseOptions.quality,
                        outputDirectory: cacheDirectory,
                        additionalArguments: metadataArgs
                    )
                )

                let finalURL = cacheDirectory.appendingPathComponent(cacheFilename)
                if outputURL != finalURL {
                    try? FileManager.default.removeItem(at: finalURL)
                    try FileManager.default.moveItem(at: outputURL, to: finalURL)
                }
                logger.info("Kindle conversion cached: \(cacheFilename)")
            } catch {
                logger.error("Kindle conversion failed: \(error.localizedDescription)")
                try? error.localizedDescription.write(
                    to: cacheDirectory.appendingPathComponent("\(bookId).error"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            await MainActor.run { [weak self] in self?.activeDownloads -= 1 }
        }

        return htmlResponse(202, "Accepted", transferStatusPage(
            title: "Preparing your book",
            message: "Converting “\(bookTitle)” to a Kindle-ready format. This page will refresh and start the download when it’s ready — usually under a minute.",
            autoRefreshSeconds: 20
        ), headers: ["Retry-After": "20"])
    }

    /// Wrap an HTML string in a Swifter response with the right content type.
    private func htmlResponse(_ status: Int, _ reason: String, _ html: String, headers: [String: String] = [:]) -> HttpResponse {
        var allHeaders = headers
        allHeaders["Content-Type"] = "text/html; charset=utf-8"
        return .raw(status, reason, allHeaders) { try $0.write(Data(html.utf8)) }
    }

    /// Build a chunked HTTP response that streams a file straight from disk.
    ///
    /// The previous implementation did `Data(contentsOf:)`, so a 300 MB PDF sat
    /// fully in memory for every concurrent download. Streaming in fixed chunks
    /// keeps memory flat regardless of file or library size.
    /// - Parameter onFinish: run once the body has been fully written (or the
    ///   client disconnected) — used to release security-scoped access and
    ///   decrement the active-download count at the right time.
    private func streamingFileResponse(
        handle: FileHandle,
        size: Int64,
        headers: [String: String],
        onFinish: @escaping () -> Void = {}
    ) -> HttpResponse {
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(size)"

        return .raw(200, "OK", allHeaders) { writer in
            defer {
                try? handle.close()
                onFinish()
            }
            let chunkSize = 256 * 1024
            while true {
                let chunk = try autoreleasepool { try handle.read(upToCount: chunkSize) }
                guard let chunk, !chunk.isEmpty else { break }
                try writer.write(chunk)
            }
        }
    }

    /// Helper to serve a converted (MOBI) file with proper headers
    private func serveFile(at url: URL, originalTitle: String) -> HttpResponse {
        let filename = "\(originalTitle).mobi"

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = (attrs[.size] as? NSNumber)?.int64Value,
              let handle = try? FileHandle(forReadingFrom: url) else {
            logger.error("Failed to open converted file: \(url.path)")
            return .internalServerError
        }

        return streamingFileResponse(
            handle: handle,
            size: fileSize,
            headers: [
                "Content-Type": "application/x-mobipocket-ebook",
                "Content-Disposition": "attachment; filename=\"\(filename)\""
            ]
        )
    }

    /// Get the local IPv4 address an e-reader on the same WiFi can reach.
    ///
    /// Only checking `en0`/`en1` was too narrow: a Mac on WiFi through a USB
    /// dongle uses `en5+`, and a running VPN adds `utun*` addresses that an
    /// e-reader cannot route to. This collects every usable candidate, drops
    /// the ones that are never LAN-reachable, and prefers Wi-Fi.
    private func getLocalIPAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(interface: String, ip: String)] = []

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let interface = ptr?.pointee else { continue }
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)

            // Loopback, VPN tunnels, Apple Wireless Direct Link, and internal
            // bridges are not reachable from a device on the WiFi LAN.
            if name == "lo0" { continue }
            if name.hasPrefix("utun") || name.hasPrefix("ipsec") || name.hasPrefix("ppp")
                || name.hasPrefix("bridge") || name.hasPrefix("awdl") || name.hasPrefix("llw") {
                continue
            }

            // Interface must be up and running.
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP == IFF_UP, flags & IFF_RUNNING == IFF_RUNNING else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            let ip = String(cString: hostname)

            // Self-assigned address (no DHCP lease) — nothing else can reach it.
            if ip.hasPrefix("169.254.") { continue }

            candidates.append((name, ip))
        }

        func rank(_ name: String) -> Int {
            if name == "en0" { return 0 }   // Wi-Fi on Apple silicon / most Macs
            if name.hasPrefix("en") { return 1 } // other Ethernet-style interfaces
            return 2
        }
        return candidates.sorted { rank($0.interface) < rank($1.interface) }.first?.ip
    }
}
