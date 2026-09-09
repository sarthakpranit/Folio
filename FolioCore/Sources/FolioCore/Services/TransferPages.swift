// TransferPages.swift
// Static HTML for the WiFi transfer server's status and error responses.

import Foundation

/// A full-page HTML body for a transfer-server status or error page.
///
/// One template replaces the several near-identical inline copies that lived in
/// `HTTPTransferServer` (#61). Every interpolated value is escaped with
/// `String.xmlEscaped` — no per-call-site hand escaping.
///
/// - Parameters:
///   - title: page heading, also the `<title>`.
///   - message: one-line explanation shown to the reader.
///   - detail: optional smaller line (e.g. an error description).
///   - autoRefreshSeconds: if set, the page reloads itself after N seconds —
///     used by the "conversion in progress" response so the reader lands on the
///     finished download without doing anything.
func transferStatusPage(
    title: String,
    message: String,
    detail: String? = nil,
    autoRefreshSeconds: Int? = nil
) -> String {
    let refreshTag = autoRefreshSeconds.map { "<meta http-equiv=\"refresh\" content=\"\($0)\">" } ?? ""
    let detailTag = detail.map { "<p class=\"detail\">\($0.xmlEscaped)</p>" } ?? ""

    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <title>\(title.xmlEscaped)</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(refreshTag)
        <style>
            body { font-family: -apple-system, system-ui, sans-serif; padding: 2rem; text-align: center; background: #1a1a2e; color: #fff; }
            h1 { color: #ff6b6b; }
            p { color: #ccc; }
            .detail { font-size: 0.8rem; color: #888; word-break: break-word; }
        </style>
    </head>
    <body>
        <h1>\(title.xmlEscaped)</h1>
        <p>\(message.xmlEscaped)</p>
        \(detailTag)
    </body>
    </html>
    """
}

/// The mobile-friendly library page served at `/` by the WiFi transfer server.
/// Extracted from `HTTPTransferServer` (#61) — it was ~300 lines of inline
/// HTML/CSS in a 900-line file.
///
/// - Parameter calibreAvailable: whether the server can offer on-the-fly
///   Kindle conversion (drives the per-book buttons).
func libraryTransferPage(books: [BookDTO], calibreAvailable: Bool) -> String {

    let bookRows = books.map { book -> String in
        let authors = book.authors.joined(separator: ", ")
        let sizeFormatted = formatFileSize(book.fileSize)
        let formatUpper = book.format.uppercased()
        let format = EbookFormat(fileExtension: book.format)
        let isKindleNative = format?.kindleNativeFormat ?? false
        let isConvertible = format?.supportsConversion ?? false

        // A Kindle's browser can only open a Kindle-native file. For anything
        // else we need Calibre to convert first; without it the raw download
        // below is a dead file on a Kindle, so say so rather than fail quietly.
        let kindleButton: String
        let downloadLabel: String
        if isKindleNative {
            kindleButton = ""
            downloadLabel = "Download"
        } else if calibreAvailable && isConvertible {
            kindleButton = """
                <a href="/api/books/\(book.id)/kindle" class="kindle-btn" download>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>
                    </svg>
                    Send to Kindle
                </a>
            """
            downloadLabel = "Original \(formatUpper)"
        } else if isConvertible {
            kindleButton = """
                <span class="kindle-hint">Install Calibre on the Mac<br>for Kindle-ready downloads</span>
            """
            downloadLabel = "Download"
        } else {
            kindleButton = ""
            downloadLabel = "Download"
        }

        return """
        <div class="book-card">
            <div class="book-info">
                <h2 class="book-title">\(book.title.xmlEscaped)</h2>
                <p class="book-author">\((authors.isEmpty ? "Unknown Author" : authors).xmlEscaped)</p>
                <div class="book-meta">
                    <span class="format-badge">\(formatUpper)</span>
                    <span class="file-size">\(sizeFormatted)</span>
                </div>
            </div>
            <div class="button-group">
                \(kindleButton)
                <a href="/api/books/\(book.id)/download" class="download-btn" download>
                    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
                        <polyline points="7 10 12 15 17 10"/>
                        <line x1="12" y1="15" x2="12" y2="3"/>
                    </svg>
                    \(downloadLabel)
                </a>
            </div>
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

            .button-group {
                display: flex;
                flex-direction: column;
                gap: 0.5rem;
                flex-shrink: 0;
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

            .kindle-btn {
                display: flex;
                align-items: center;
                justify-content: center;
                gap: 0.4rem;
                background: linear-gradient(135deg, #f97316 0%, #ea580c 100%);
                color: white;
                padding: 0.5rem 0.75rem;
                border-radius: 6px;
                text-decoration: none;
                font-weight: 500;
                font-size: 0.75rem;
                white-space: nowrap;
                transition: opacity 0.2s;
            }

            .kindle-btn:active {
                opacity: 0.8;
            }

            .kindle-hint {
                font-size: 0.7rem;
                color: rgba(255, 255, 255, 0.45);
                text-align: center;
                line-height: 1.3;
                max-width: 140px;
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
            <p>Powered by <a href="https://github.com/sarthakpranit/Folio">Folio</a></p>
        </footer>
    </body>
    </html>
    """
}

private func formatFileSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    formatter.allowedUnits = [.useMB, .useKB]
    return formatter.string(fromByteCount: bytes)
}
