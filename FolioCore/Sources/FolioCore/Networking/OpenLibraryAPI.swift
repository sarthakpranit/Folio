// OpenLibraryAPI.swift
// Open Library API client for fetching book metadata and cover images

import Foundation
import SwiftyJSON

/// Client for the Open Library API
/// Documentation: https://openlibrary.org/developers/api
public final class OpenLibraryAPI: MetadataProvider, @unchecked Sendable {

    // MARK: - Constants

    private static let searchBaseURL = "https://openlibrary.org/search.json"
    private static let isbnBaseURL = "https://openlibrary.org/isbn"
    private static let coversBaseURL = "https://covers.openlibrary.org/b"
    private static let maxResults = 10

    /// Rate limiting: max requests per second (Open Library recommends 1 req/sec for polite usage)
    private static let rateLimitPerSecond: Double = 1.0

    // MARK: - Properties

    private let session: URLSession

    /// Last request timestamp for rate limiting
    private var lastRequestTime: Date = .distantPast
    private let rateLimitQueue = DispatchQueue(label: "com.folio.openlibraryapi.ratelimit")

    public var providerName: String { "open_library" }

    // MARK: - Initialization

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        // Add User-Agent header as required by Open Library API guidelines
        config.httpAdditionalHeaders = [
            "User-Agent": "Folio/1.0 (macOS ebook manager; https://github.com/folio-app)"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - MetadataProvider Protocol

    public func fetchMetadata(isbn: String) async throws -> BookMetadata? {
        await enforceRateLimit()

        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")

        // Use the ISBN endpoint for direct lookup
        guard let url = URL(string: "\(Self.isbnBaseURL)/\(cleanISBN).json") else {
            throw MetadataError.invalidRequest("Failed to build ISBN URL")
        }

        do {
            let (data, response) = try await session.data(from: url)
            try validateResponse(response)

            let json = JSON(data)

            // Parse the book data
            guard let title = json["title"].string, !title.isEmpty else {
                return nil
            }

            // Get authors - need to fetch author details separately
            var authors: [String] = []
            if let authorRefs = json["authors"].array {
                for authorRef in authorRefs {
                    if let authorKey = authorRef["key"].string {
                        if let authorName = try? await fetchAuthorName(key: authorKey) {
                            authors.append(authorName)
                        }
                    }
                }
            }

            // Parse published date
            var publishedDate: Date?
            if let dateString = json["publish_date"].string {
                publishedDate = parseDate(dateString)
            }

            // Get cover image URL
            let coverImageURL = buildCoverURL(isbn: cleanISBN, size: .large)

            // Parse publishers
            let publisher = json["publishers"].arrayValue.first?["name"].string
                ?? json["publishers"].arrayValue.first?.string

            // Parse subjects as tags
            let tags = json["subjects"].arrayValue.compactMap { subject -> String? in
                subject["name"].string ?? subject.string
            }

            return BookMetadata(
                title: title,
                authors: authors,
                isbn: cleanISBN.count == 10 ? cleanISBN : nil,
                isbn13: cleanISBN.count == 13 ? cleanISBN : nil,
                publisher: publisher,
                publishedDate: publishedDate,
                summary: json["description"].string ?? json["description"]["value"].string,
                pageCount: json["number_of_pages"].int,
                language: nil, // Language requires additional lookup
                coverImageURL: coverImageURL,
                series: nil,
                seriesIndex: nil,
                tags: tags,
                confidence: 0.90, // High confidence for ISBN match
                source: providerName
            )
        } catch let error as MetadataError where error == .notFound("Resource not found") {
            return nil
        }
    }

    public func fetchMetadata(title: String, author: String?) async throws -> [BookMetadata] {
        await enforceRateLimit()

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else {
            logger.warning("Open Library: Empty query - no title provided")
            return []
        }

        // Build the search query using 'q' parameter (more flexible than separate title/author params)
        // Format: "title author" for general search
        var searchQuery = cleanTitle
        if let author = cleanAuthor, !author.isEmpty {
            searchQuery += " \(author)"
        }

        guard var components = URLComponents(string: Self.searchBaseURL) else {
            throw MetadataError.invalidRequest("Failed to build search URL")
        }

        // Use 'q' for general search query and specify fields we need
        components.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "limit", value: String(Self.maxResults)),
            URLQueryItem(name: "fields", value: "key,title,author_name,author_key,first_publish_year,publisher,isbn,cover_i,number_of_pages_median,language,subject")
        ]

        guard let url = components.url else {
            throw MetadataError.invalidRequest("Failed to build search URL")
        }

        logger.info("Open Library: Searching for q='\(searchQuery)'")
        logger.debug("Open Library: Request URL: \(url.absoluteString)")

        do {
            let (data, response) = try await session.data(from: url)
            try validateResponse(response)

            let json = JSON(data)

            // Log the raw response for debugging
            logger.debug("Open Library: Raw response keys: \(json.dictionaryValue.keys.joined(separator: ", "))")

            let numFound = json["numFound"].intValue
            logger.info("Open Library: Found \(numFound) total results")

            guard let docs = json["docs"].array, !docs.isEmpty else {
                logger.info("Open Library: No docs in response (numFound: \(numFound))")
                return []
            }

            logger.debug("Open Library: Processing \(docs.count) docs")

            let results = docs.compactMap { doc -> BookMetadata? in
                parseSearchResult(doc, searchTitle: cleanTitle, searchAuthor: cleanAuthor)
            }

            logger.info("Open Library: Returning \(results.count) metadata results")
            return results
        } catch {
            logger.error("Open Library: Request failed - \(error.localizedDescription)")
            throw error
        }
    }

    public func fetchCoverImage(isbn: String) async throws -> URL? {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        return buildCoverURL(isbn: cleanISBN, size: .large)
    }

    // MARK: - Cover Image Helpers

    /// Cover image sizes available from Open Library
    public enum CoverSize: String {
        case small = "S"
        case medium = "M"
        case large = "L"
    }

    /// Get cover image URL for an ISBN
    /// - Parameters:
    ///   - isbn: The book ISBN
    ///   - size: Desired image size
    /// - Returns: URL for the cover image, or nil if invalid
    public func buildCoverURL(isbn: String, size: CoverSize = .large) -> URL? {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        return URL(string: "\(Self.coversBaseURL)/isbn/\(cleanISBN)-\(size.rawValue).jpg")
    }

    /// Get cover image URL by Open Library ID
    /// - Parameters:
    ///   - olid: Open Library ID (e.g., "OL12345M")
    ///   - size: Desired image size
    /// - Returns: URL for the cover image
    public func buildCoverURL(olid: String, size: CoverSize = .large) -> URL? {
        return URL(string: "\(Self.coversBaseURL)/olid/\(olid)-\(size.rawValue).jpg")
    }

    /// Get cover image URL by cover ID
    /// - Parameters:
    ///   - coverId: Cover ID from Open Library
    ///   - size: Desired image size
    /// - Returns: URL for the cover image
    public func buildCoverURL(coverId: Int, size: CoverSize = .large) -> URL? {
        return URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-\(size.rawValue).jpg")
    }

    // MARK: - Private Methods

    /// Fetch author name from author key
    private func fetchAuthorName(key: String) async throws -> String? {
        await enforceRateLimit()

        guard let url = URL(string: "https://openlibrary.org\(key).json") else {
            return nil
        }

        let (data, response) = try await session.data(from: url)
        try validateResponse(response)

        let json = JSON(data)
        return json["name"].string
    }

    /// Parse a search result document to BookMetadata
    private func parseSearchResult(_ doc: JSON, searchTitle: String, searchAuthor: String?) -> BookMetadata? {
        guard let title = doc["title"].string, !title.isEmpty else {
            logger.debug("Open Library: Skipping doc with no title")
            return nil
        }

        // Get authors from author_name array
        let authors = doc["author_name"].arrayValue.compactMap { $0.string }
        logger.debug("Open Library: Parsing '\(title)' by \(authors.joined(separator: ", "))")

        // Get ISBN - can be array of strings
        let isbns = doc["isbn"].arrayValue.compactMap { $0.string }
        var isbn: String?
        var isbn13: String?

        for isbnValue in isbns {
            let cleanISBN = isbnValue.replacingOccurrences(of: "-", with: "")
            if cleanISBN.count == 10 && isbn == nil {
                isbn = cleanISBN
            } else if cleanISBN.count == 13 && isbn13 == nil {
                isbn13 = cleanISBN
            }
            if isbn != nil && isbn13 != nil { break }
        }

        // Parse first publish year
        var publishedDate: Date?
        if let year = doc["first_publish_year"].int {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            publishedDate = formatter.date(from: String(year))
        }

        // Get cover image URL from cover_i (this is the cover ID)
        var coverImageURL: URL?
        if let coverId = doc["cover_i"].int {
            coverImageURL = buildCoverURL(coverId: coverId, size: .large)
            logger.debug("Open Library: Cover ID \(coverId) for '\(title)'")
        } else if let isbnForCover = isbn13 ?? isbn {
            // Fallback to ISBN-based cover URL
            coverImageURL = buildCoverURL(isbn: isbnForCover, size: .large)
        }

        // Get publisher - can be array
        let publisher = doc["publisher"].arrayValue.first?.string

        // Get subjects as tags
        let tags = doc["subject"].arrayValue.prefix(10).compactMap { $0.string }

        // Calculate confidence
        let confidence = calculateConfidence(
            resultTitle: title,
            resultAuthors: authors,
            searchTitle: searchTitle,
            searchAuthor: searchAuthor
        )

        return BookMetadata(
            title: title,
            authors: authors,
            isbn: isbn,
            isbn13: isbn13,
            publisher: publisher,
            publishedDate: publishedDate,
            summary: nil, // Search results don't include descriptions
            pageCount: doc["number_of_pages_median"].int,
            language: doc["language"].arrayValue.first?.string,
            coverImageURL: coverImageURL,
            series: nil,
            seriesIndex: nil,
            tags: Array(tags),
            confidence: confidence,
            source: providerName
        )
    }

    /// Calculate confidence score for search results
    private func calculateConfidence(resultTitle: String, resultAuthors: [String], searchTitle: String, searchAuthor: String?) -> Double {
        var score: Double = 0.5

        let resultTitleLower = resultTitle.lowercased()
        let searchTitleLower = searchTitle.lowercased()

        // Title matching
        if resultTitleLower == searchTitleLower {
            score += 0.3
        } else if resultTitleLower.contains(searchTitleLower) || searchTitleLower.contains(resultTitleLower) {
            score += 0.15
        }

        // Author matching
        if let searchAuthor = searchAuthor?.lowercased() {
            let authorsLower = resultAuthors.map { $0.lowercased() }
            if authorsLower.contains(where: { $0.contains(searchAuthor) || searchAuthor.contains($0) }) {
                score += 0.15
            }
        }

        return min(score, 0.85) // Cap at 0.85 for search results (lower than Google Books)
    }

    /// Parse various date formats from Open Library
    private func parseDate(_ dateString: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MMMM d, yyyy"
                f.locale = Locale(identifier: "en_US")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MMMM yyyy"
                f.locale = Locale(identifier: "en_US")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    /// Validate HTTP response
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MetadataError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200...299:
            return
        case 400:
            throw MetadataError.invalidRequest("Bad request")
        case 404:
            throw MetadataError.notFound("Resource not found")
        case 429:
            throw MetadataError.rateLimited("Too many requests - please slow down")
        case 500...599:
            throw MetadataError.serverError("Open Library server error: \(httpResponse.statusCode)")
        default:
            throw MetadataError.networkError("HTTP error: \(httpResponse.statusCode)")
        }
    }

    /// Enforce rate limiting between requests
    private func enforceRateLimit() async {
        await withCheckedContinuation { continuation in
            rateLimitQueue.async {
                let now = Date()
                let minInterval = 1.0 / Self.rateLimitPerSecond
                let elapsed = now.timeIntervalSince(self.lastRequestTime)

                if elapsed < minInterval {
                    let delay = minInterval - elapsed
                    Thread.sleep(forTimeInterval: delay)
                }

                self.lastRequestTime = Date()
                continuation.resume()
            }
        }
    }
}
