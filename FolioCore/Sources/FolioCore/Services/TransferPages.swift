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
