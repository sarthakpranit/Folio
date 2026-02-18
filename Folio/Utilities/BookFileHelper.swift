//
// BookFileHelper.swift
// Folio
//
// Handles security-scoped file access for books stored on external volumes.
// macOS sandboxing requires security-scoped bookmarks to maintain access
// to user-selected files across app launches. This helper manages that
// complexity, providing a clean interface for opening books.
//
// Key Responsibilities:
// - Resolving security-scoped bookmarks
// - Copying files to temp directory for safe access
// - Opening books in Apple Books app
// - Updating stale bookmarks automatically
//
// Why This Matters:
// - Folio imports books from user-selected folders
// - Sandboxed apps lose access to files after restart
// - Security-scoped bookmarks persist access rights
// - External volumes (USB drives) require special handling
//
// Usage:
//   BookFileHelper.openInAppleBooks(book)
//

import SwiftUI
import AppKit
import CoreData

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
