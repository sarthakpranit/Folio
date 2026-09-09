//
// CoverImageProcessor.swift
// FolioCore
//
// The single place that turns freshly downloaded cover bytes into the bytes
// Folio actually stores. Covers come off the network at whatever size a
// provider hands back (Open Library "L", Google "extraLarge", ...) and used to
// land in Core Data verbatim — ~0.5-3 GB projected at 5,000 books (#67).
//
// Key Responsibilities:
// - Downscale to a display-sized long edge (ImageIO thumbnailing, never upscales)
// - Re-encode as JPEG so PNG/large sources shrink to a predictable weight
//
// Pure bytes-in / bytes-out: only ImageIO + CoreGraphics, no CoreData, no UI.
//
// Usage:
//   let stored = try CoverImageProcessor.downscaledAndReEncoded(downloadedData)
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Errors

/// Failures raised while processing a cover image.
public enum CoverImageError: LocalizedError, Equatable {
    /// The input bytes could not be read as an image.
    case decodeFailed
    /// The downscaled image could not be re-encoded.
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case .decodeFailed:
            return "Cover image could not be decoded"
        case .encodeFailed:
            return "Cover image could not be re-encoded"
        }
    }
}

// MARK: - Cover Image Processor

/// Downscales and re-encodes cover artwork before it is persisted.
///
/// A namespace of stateless functions: every call builds its own
/// `CGImageSource` / `CGImageDestination`, so concurrent callers never share
/// mutable state.
public enum CoverImageProcessor {

    /// Default maximum length, in pixels, of the longer edge of a stored cover.
    public static let defaultMaxPixelSize = 400

    /// Default JPEG quality (0.0-1.0) for the re-encoded cover.
    public static let defaultCompressionQuality: CGFloat = 0.8

    /// Downscale `imageData` so its longer edge is at most `maxPixelSize`, then
    /// re-encode as JPEG.
    ///
    /// Thumbnailing never upscales: an already-small source comes back at its
    /// original dimensions, just re-encoded.
    ///
    /// - Parameters:
    ///   - imageData: Raw image bytes as downloaded (PNG, JPEG, ...).
    ///   - maxPixelSize: Maximum length of the longer edge, in pixels.
    ///   - compressionQuality: JPEG quality, 0.0-1.0.
    /// - Returns: Re-encoded JPEG bytes.
    /// - Throws: ``CoverImageError`` if the bytes cannot be decoded or re-encoded.
    public static func downscaledAndReEncoded(
        _ imageData: Data,
        maxPixelSize: Int = defaultMaxPixelSize,
        compressionQuality: CGFloat = defaultCompressionQuality
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            throw CoverImageError.decodeFailed
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else {
            throw CoverImageError.decodeFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw CoverImageError.encodeFailed
        }

        let destinationOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, thumbnail, destinationOptions as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw CoverImageError.encodeFailed
        }

        return output as Data
    }
}
