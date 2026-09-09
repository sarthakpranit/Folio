//
// CoverImageStore.swift
// Folio
//
// The app-side boundary in front of FolioCore's CoverImageProcessor. Every
// screen that downloads a cover funnels the raw bytes through here before they
// touch Book.coverImageData, so covers are downscaled + re-encoded in exactly
// one place instead of being stored verbatim (#67).
//
// Usage:
//   if let bytes = CoverImageStore.processedForStorage(downloadedData) {
//       book.coverImageData = bytes
//   }
//

import Foundation
import OSLog
import FolioCore

/// Prepares downloaded cover bytes for persistence.
enum CoverImageStore {

    private static let logger = Logger(subsystem: "com.folio", category: "CoverImage")

    /// Downscale + re-encode a freshly downloaded cover before it is written to
    /// Core Data.
    ///
    /// - Parameter data: Raw image bytes as returned by the cover download.
    /// - Returns: Downscaled JPEG bytes ready to assign to `Book.coverImageData`,
    ///   or `nil` if the bytes could not be processed (logged, never stored raw).
    static func processedForStorage(_ data: Data) -> Data? {
        do {
            return try CoverImageProcessor.downscaledAndReEncoded(data)
        } catch {
            logger.error("Cover downscale failed, skipping store: \(error.localizedDescription)")
            return nil
        }
    }
}
