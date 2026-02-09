// GoogleBooksAPI.swift
// Google Books API client for fetching book metadata

import Foundation
import SwiftyJSON

/// Client for the Google Books API
/// Documentation: https://developers.google.com/books/docs/v1/reference/volumes
public final class GoogleBooksAPI: MetadataProvider, @unchecked Sendable {

    // MARK: - Constants

    private static let baseURL = "https://www.googleapis.com/books/v1/volumes"
    private static let maxResults = 10

    /// Rate limiting: minimum seconds between requests (more conservative without API key)
    private static let minRequestInterval: Double = 2.0

    /// Maximum retry attempts for rate-limited requests
    private static let maxRetryAttempts = 3

    /// Base delay for exponential backoff (seconds)
    private static let baseRetryDelay: Double = 5.0

    // MARK: - Properties

    private let session: URLSession
    private let apiKey: String?

    /// Last request timestamp for rate limiting
    private var lastRequestTime: Date = .distantPast
    private let rateLimitQueue = DispatchQueue(label: "com.folio.googlebooksapi.ratelimit")

    /// Track consecutive rate limit hits for adaptive throttling
    private var consecutiveRateLimits: Int = 0

    public var providerName: String { "google_books" }

    // MARK: - Initialization

    /// Initialize the Google Books API client
    /// - Parameter apiKey: Optional API key for higher rate limits
    public init(apiKey: String? = nil) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - MetadataProvider Protocol

    public func fetchMetadata(isbn: String) async throws -> BookMetadata? {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        let query = "isbn:\(cleanISBN)"

        guard let url = buildSearchURL(query: query) else {
            throw MetadataError.invalidRequest("Failed to build search URL")
        }

        return try await executeWithRetry {
            await self.enforceRateLimit()

            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)

            let json = JSON(data)

            guard let firstItem = json["items"].array?.first else {
                return nil
            }

            return self.parseVolumeInfo(firstItem["volumeInfo"], confidence: 0.95)
        }
    }

    public func fetchMetadata(title: String, author: String?) async throws -> [BookMetadata] {
        var queryParts: [String] = []

        // Clean and format title for search
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty {
            queryParts.append("intitle:\(cleanTitle)")
        }

        // Add author if provided
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            queryParts.append("inauthor:\(author)")
        }

        guard !queryParts.isEmpty else {
            logger.warning("Google Books: Empty query - no title or author provided")
            return []
        }

        let query = queryParts.joined(separator: "+")
        logger.info("Google Books: Searching for '\(query)'")

        guard let url = buildSearchURL(query: query) else {
            logger.error("Google Books: Failed to build search URL for query: \(query)")
            throw MetadataError.invalidRequest("Failed to build search URL")
        }

        logger.debug("Google Books: Request URL: \(url.absoluteString)")

        // Use retry logic for rate limiting
        return try await executeWithRetry {
            await self.enforceRateLimit()

            let (data, response) = try await self.session.data(from: url)
            try self.validateResponse(response)

            let json = JSON(data)

            // Log raw response for debugging
            let totalItems = json["totalItems"].intValue
            logger.info("Google Books: Found \(totalItems) total items")

            guard let items = json["items"].array else {
                logger.info("Google Books: No items in response (totalItems: \(totalItems))")
                if let errorMessage = json["error"]["message"].string {
                    logger.error("Google Books API error: \(errorMessage)")
                }
                return []
            }

            logger.debug("Google Books: Processing \(items.count) items")

            let results = items.compactMap { item -> BookMetadata? in
                let volumeInfo = item["volumeInfo"]

                // Calculate confidence based on how well the result matches the query
                let confidence = self.calculateConfidence(
                    volumeInfo: volumeInfo,
                    searchTitle: cleanTitle,
                    searchAuthor: author
                )

                return self.parseVolumeInfo(volumeInfo, confidence: confidence)
            }

            logger.info("Google Books: Returning \(results.count) metadata results")
            return results
        }
    }

    public func fetchCoverImage(isbn: String) async throws -> URL? {
        if let metadata = try await fetchMetadata(isbn: isbn) {
            return metadata.coverImageURL
        }
        return nil
    }

    // MARK: - Private Methods

    /// Build the search URL with query parameters
    private func buildSearchURL(query: String) -> URL? {
        var components = URLComponents(string: Self.baseURL)

        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(Self.maxResults)),
            URLQueryItem(name: "printType", value: "books")
        ]

        if let apiKey = apiKey, !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    /// Parse volume info JSON to BookMetadata
    private func parseVolumeInfo(_ volumeInfo: JSON, confidence: Double) -> BookMetadata? {
        guard let title = volumeInfo["title"].string, !title.isEmpty else {
            return nil
        }

        let authors = volumeInfo["authors"].arrayValue.compactMap { $0.string }

        // Parse ISBN identifiers
        var isbn: String?
        var isbn13: String?

        if let identifiers = volumeInfo["industryIdentifiers"].array {
            for identifier in identifiers {
                let type = identifier["type"].stringValue
                let id = identifier["identifier"].stringValue

                if type == "ISBN_10" {
                    isbn = id
                } else if type == "ISBN_13" {
                    isbn13 = id
                }
            }
        }

        // Parse published date
        var publishedDate: Date?
        if let dateString = volumeInfo["publishedDate"].string {
            publishedDate = parseDate(dateString)
        }

        // Get cover image URL - prefer larger images
        var coverImageURL: URL?
        if let imageLinks = volumeInfo["imageLinks"].dictionary {
            // Try to get the best quality image available
            let preferredSizes = ["extraLarge", "large", "medium", "small", "thumbnail", "smallThumbnail"]
            for size in preferredSizes {
                if let urlString = imageLinks[size]?.string,
                   let url = URL(string: urlString.replacingOccurrences(of: "http://", with: "https://")) {
                    coverImageURL = url
                    break
                }
            }
        }

        // Parse categories as tags
        let tags = volumeInfo["categories"].arrayValue.compactMap { $0.string }

        return BookMetadata(
            title: title,
            authors: authors,
            isbn: isbn,
            isbn13: isbn13,
            publisher: volumeInfo["publisher"].string,
            publishedDate: publishedDate,
            summary: volumeInfo["description"].string,
            pageCount: volumeInfo["pageCount"].int,
            language: volumeInfo["language"].string,
            coverImageURL: coverImageURL,
            series: nil, // Google Books doesn't provide series info reliably
            seriesIndex: nil,
            tags: tags,
            confidence: confidence,
            source: providerName
        )
    }

    /// Calculate confidence score based on how well the result matches the search
    private func calculateConfidence(volumeInfo: JSON, searchTitle: String, searchAuthor: String?) -> Double {
        var score: Double = 0.5 // Base score

        let resultTitle = volumeInfo["title"].stringValue.lowercased()
        let searchTitleLower = searchTitle.lowercased()

        // Title matching
        if resultTitle == searchTitleLower {
            score += 0.3
        } else if resultTitle.contains(searchTitleLower) || searchTitleLower.contains(resultTitle) {
            score += 0.15
        }

        // Author matching
        if let searchAuthor = searchAuthor?.lowercased() {
            let resultAuthors = volumeInfo["authors"].arrayValue.map { $0.stringValue.lowercased() }
            if resultAuthors.contains(where: { $0.contains(searchAuthor) || searchAuthor.contains($0) }) {
                score += 0.15
            }
        }

        // Bonus for having ISBN
        if volumeInfo["industryIdentifiers"].array != nil {
            score += 0.05
        }

        return min(score, 0.95) // Cap at 0.95 for non-ISBN searches
    }

    /// Parse various date formats from Google Books
    private func parseDate(_ dateString: String) -> Date? {
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM"
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
        case 403:
            throw MetadataError.rateLimited("API rate limit exceeded or invalid API key")
        case 404:
            throw MetadataError.notFound("Resource not found")
        case 429:
            throw MetadataError.rateLimited("Too many requests")
        case 500...599:
            throw MetadataError.serverError("Google Books server error: \(httpResponse.statusCode)")
        default:
            throw MetadataError.networkError("HTTP error: \(httpResponse.statusCode)")
        }
    }

    /// Enforce rate limiting between requests
    private func enforceRateLimit() async {
        await withCheckedContinuation { continuation in
            rateLimitQueue.async {
                let now = Date()
                // Adaptive interval: increase delay if we've been rate limited recently
                let adaptiveInterval = Self.minRequestInterval * Double(1 + self.consecutiveRateLimits)
                let elapsed = now.timeIntervalSince(self.lastRequestTime)

                if elapsed < adaptiveInterval {
                    let delay = adaptiveInterval - elapsed
                    logger.debug("Google Books: Rate limit delay \(String(format: "%.1f", delay))s")
                    Thread.sleep(forTimeInterval: delay)
                }

                self.lastRequestTime = Date()
                continuation.resume()
            }
        }
    }

    /// Execute request with automatic retry on rate limiting
    private func executeWithRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var lastError: Error?

        for attempt in 0..<Self.maxRetryAttempts {
            do {
                let result = try await operation()
                // Success - reset rate limit counter
                rateLimitQueue.sync { consecutiveRateLimits = 0 }
                return result
            } catch let error as MetadataError {
                if case .rateLimited = error {
                    // Increment rate limit counter for adaptive throttling
                    rateLimitQueue.sync { consecutiveRateLimits += 1 }

                    let delay = Self.baseRetryDelay * pow(2.0, Double(attempt))
                    logger.warning("Google Books: Rate limited, retry \(attempt + 1)/\(Self.maxRetryAttempts) in \(Int(delay))s")

                    if attempt < Self.maxRetryAttempts - 1 {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                }
                lastError = error
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw lastError ?? MetadataError.networkError("Max retries exceeded")
    }
}
