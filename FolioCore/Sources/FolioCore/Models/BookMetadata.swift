// BookMetadata.swift
// Metadata DTO for books - used for import and API responses

import Foundation

/// Metadata about a book, used for import and API responses
public struct BookMetadata: Codable, Sendable {
    public var title: String
    public var authors: [String]
    public var isbn: String?
    public var isbn13: String?
    public var publisher: String?
    public var publishedDate: Date?
    public var summary: String?
    public var pageCount: Int?
    public var language: String?
    public var coverImageURL: URL?
    public var series: String?
    public var seriesIndex: Double?
    public var tags: [String]

    /// Confidence score for metadata accuracy (0.0 to 1.0)
    public var confidence: Double

    /// Source of the metadata (e.g., "google_books", "open_library", "file")
    public var source: String

    public init(
        title: String,
        authors: [String] = [],
        isbn: String? = nil,
        isbn13: String? = nil,
        publisher: String? = nil,
        publishedDate: Date? = nil,
        summary: String? = nil,
        pageCount: Int? = nil,
        language: String? = nil,
        coverImageURL: URL? = nil,
        series: String? = nil,
        seriesIndex: Double? = nil,
        tags: [String] = [],
        confidence: Double = 0.0,
        source: String = "unknown"
    ) {
        self.title = title
        self.authors = authors
        self.isbn = isbn
        self.isbn13 = isbn13
        self.publisher = publisher
        self.publishedDate = publishedDate
        self.summary = summary
        self.pageCount = pageCount
        self.language = language
        self.coverImageURL = coverImageURL
        self.series = series
        self.seriesIndex = seriesIndex
        self.tags = tags
        self.confidence = confidence
        self.source = source
    }

    /// Create minimal metadata from just a filename
    public static func fromFilename(_ filename: String) -> BookMetadata {
        // Extract title from filename (remove extension, clean up)
        var name = filename

        // Remove common ebook extensions
        let extensions = EbookFormat.fileExtensions
        for ext in extensions {
            if name.lowercased().hasSuffix(".\(ext)") {
                name = String(name.dropLast(ext.count + 1))
            }
        }

        // Try to extract author if filename contains " - " pattern (Author - Title)
        var authors: [String] = []
        var title = name

        if let range = name.range(of: " - ") {
            let possibleAuthor = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let possibleTitle = String(name[range.upperBound...]).trimmingCharacters(in: .whitespaces)

            // If it looks like an author name (has capital letters, reasonable length)
            if possibleAuthor.count < 50 && possibleAuthor.first?.isUppercase == true {
                authors = [possibleAuthor]
                title = possibleTitle
            }
        }

        // Clean up common patterns in title
        title = title
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return BookMetadata(
            title: title,
            authors: authors,
            confidence: 0.2,
            source: "filename"
        )
    }

    /// Merge with another metadata, preferring higher confidence values
    public func merged(with other: BookMetadata) -> BookMetadata {
        var result = self

        // Use the other's value if it has higher confidence
        if other.confidence > self.confidence {
            result.title = other.title
            result.confidence = other.confidence
            result.source = other.source
        }

        // Merge arrays
        if !other.authors.isEmpty {
            result.authors = other.authors
        }
        if !other.tags.isEmpty {
            result.tags = other.tags
        }

        // Fill in missing values
        result.isbn = result.isbn ?? other.isbn
        result.isbn13 = result.isbn13 ?? other.isbn13
        result.publisher = result.publisher ?? other.publisher
        result.publishedDate = result.publishedDate ?? other.publishedDate
        result.summary = result.summary ?? other.summary
        result.pageCount = result.pageCount ?? other.pageCount
        result.language = result.language ?? other.language
        result.coverImageURL = result.coverImageURL ?? other.coverImageURL
        result.series = result.series ?? other.series
        result.seriesIndex = result.seriesIndex ?? other.seriesIndex

        return result
    }
}

/// Data transfer object for book list in HTTP API
public struct BookDTO: Codable, Sendable {
    public let id: String
    public let title: String
    public let authors: [String]
    public let format: String
    public let fileSize: Int64
    public let coverURL: String?
    public let dateAdded: Date

    public init(id: String, title: String, authors: [String], format: String, fileSize: Int64, coverURL: String?, dateAdded: Date) {
        self.id = id
        self.title = title
        self.authors = authors
        self.format = format
        self.fileSize = fileSize
        self.coverURL = coverURL
        self.dateAdded = dateAdded
    }
}
