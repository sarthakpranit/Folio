// MetadataService.swift
// Metadata service that aggregates multiple providers with fallback strategy

import Foundation

// MARK: - Metadata Errors

/// Errors that can occur during metadata fetching
public enum MetadataError: LocalizedError, Equatable {
    case invalidRequest(String)
    case networkError(String)
    case notFound(String)
    case rateLimited(String)
    case serverError(String)
    case noProvidersAvailable
    case allProvidersFailed([String])

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .notFound(let message):
            return "Not found: \(message)"
        case .rateLimited(let message):
            return "Rate limited: \(message)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .noProvidersAvailable:
            return "No metadata providers available"
        case .allProvidersFailed(let errors):
            return "All providers failed: \(errors.joined(separator: "; "))"
        }
    }

    public static func == (lhs: MetadataError, rhs: MetadataError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidRequest(let l), .invalidRequest(let r)): return l == r
        case (.networkError(let l), .networkError(let r)): return l == r
        case (.notFound(let l), .notFound(let r)): return l == r
        case (.rateLimited(let l), .rateLimited(let r)): return l == r
        case (.serverError(let l), .serverError(let r)): return l == r
        case (.noProvidersAvailable, .noProvidersAvailable): return true
        case (.allProvidersFailed(let l), .allProvidersFailed(let r)): return l == r
        default: return false
        }
    }
}

// MARK: - Metadata Provider Protocol

/// Protocol for metadata providers (Google Books, Open Library, etc.)
public protocol MetadataProvider: Sendable {
    /// Unique identifier for this provider
    var providerName: String { get }

    /// Fetch metadata by ISBN (10 or 13 digit)
    /// - Parameter isbn: The book ISBN
    /// - Returns: BookMetadata if found, nil otherwise
    func fetchMetadata(isbn: String) async throws -> BookMetadata?

    /// Fetch metadata by title and optional author
    /// - Parameters:
    ///   - title: Book title to search for
    ///   - author: Optional author name
    /// - Returns: Array of matching BookMetadata, sorted by confidence
    func fetchMetadata(title: String, author: String?) async throws -> [BookMetadata]

    /// Fetch cover image URL for a book
    /// - Parameter isbn: The book ISBN
    /// - Returns: URL to cover image if available
    func fetchCoverImage(isbn: String) async throws -> URL?
}

// MARK: - Metadata Search Options

/// Options for controlling metadata search behavior
public struct MetadataSearchOptions: Sendable {
    /// Minimum confidence score to accept a result (0.0 to 1.0)
    public var minimumConfidence: Double

    /// Whether to try all providers and merge results
    public var mergeResults: Bool

    /// Maximum number of results to return
    public var maxResults: Int

    /// Whether to fetch cover images
    public var fetchCovers: Bool

    public init(
        minimumConfidence: Double = 0.5,
        mergeResults: Bool = false,
        maxResults: Int = 10,
        fetchCovers: Bool = true
    ) {
        self.minimumConfidence = minimumConfidence
        self.mergeResults = mergeResults
        self.maxResults = maxResults
        self.fetchCovers = fetchCovers
    }

    /// Default options for ISBN lookup (high confidence expected)
    public static let isbnLookup = MetadataSearchOptions(
        minimumConfidence: 0.8,
        mergeResults: true,
        maxResults: 1,
        fetchCovers: true
    )

    /// Default options for title/author search
    public static let titleSearch = MetadataSearchOptions(
        minimumConfidence: 0.5,
        mergeResults: false,
        maxResults: 10,
        fetchCovers: true
    )
}

// MARK: - Metadata Service

/// Service that aggregates multiple metadata providers with fallback strategy
///
/// The service tries providers in order of priority (Open Library first, then Google Books).
/// Open Library is preferred as it has no API key requirement and more lenient rate limits.
/// For ISBN lookups, it can merge results from multiple providers for better coverage.
/// For title searches, it returns results from the first provider that succeeds.
public final class MetadataService: @unchecked Sendable {

    // MARK: - Properties

    /// Ordered list of metadata providers (higher priority first)
    private var providers: [MetadataProvider]

    /// Shared instance with default providers
    public static let shared = MetadataService()

    // MARK: - Initialization

    /// Initialize with default providers (Open Library only - no API key, lenient rate limits)
    public init() {
        self.providers = [
            OpenLibraryAPI()     // Primary and only: No API key required, 1 req/sec rate limit
            // Google Books removed due to aggressive rate limiting without API key
        ]
    }

    /// Initialize with custom providers
    /// - Parameter providers: Ordered list of providers (higher priority first)
    public init(providers: [MetadataProvider]) {
        self.providers = providers
    }

    /// Initialize with Google Books API key (prioritizes Google Books when API key is provided)
    /// - Parameter googleBooksAPIKey: API key for Google Books (increases rate limits significantly)
    public convenience init(googleBooksAPIKey: String) {
        self.init()
        // With an API key, Google Books has much higher rate limits, so prioritize it
        self.providers = [
            GoogleBooksAPI(apiKey: googleBooksAPIKey),
            OpenLibraryAPI()
        ]
    }

    // MARK: - Public Methods

    /// Add a metadata provider
    /// - Parameters:
    ///   - provider: The provider to add
    ///   - priority: If true, adds at the beginning (highest priority)
    public func addProvider(_ provider: MetadataProvider, highPriority: Bool = false) {
        if highPriority {
            providers.insert(provider, at: 0)
        } else {
            providers.append(provider)
        }
    }

    /// Remove a provider by name
    /// - Parameter name: The provider name to remove
    public func removeProvider(named name: String) {
        providers.removeAll { $0.providerName == name }
    }

    /// Fetch metadata by ISBN with fallback to secondary providers
    /// - Parameters:
    ///   - isbn: ISBN-10 or ISBN-13
    ///   - options: Search options
    /// - Returns: BookMetadata if found
    public func fetchMetadata(
        isbn: String,
        options: MetadataSearchOptions = .isbnLookup
    ) async throws -> BookMetadata? {
        guard !providers.isEmpty else {
            throw MetadataError.noProvidersAvailable
        }

        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
        var errors: [String] = []
        var result: BookMetadata?

        for provider in providers {
            do {
                logger.debug("Fetching ISBN \(cleanISBN) from \(provider.providerName)")

                if let metadata = try await provider.fetchMetadata(isbn: cleanISBN) {
                    if metadata.confidence >= options.minimumConfidence {
                        logger.info("Found metadata from \(provider.providerName) with confidence \(metadata.confidence)")

                        if options.mergeResults {
                            // Merge with existing result if we have one
                            result = result?.merged(with: metadata) ?? metadata
                        } else {
                            // Return first good result
                            return metadata
                        }
                    }
                }
            } catch let error as MetadataError {
                let errorMsg = "\(provider.providerName): \(error.localizedDescription)"
                errors.append(errorMsg)
                logger.warning("Provider \(provider.providerName) failed: \(error.localizedDescription)")

                // Continue to next provider unless it's a fatal error
                if case .rateLimited = error {
                    continue
                }
            } catch {
                let errorMsg = "\(provider.providerName): \(error.localizedDescription)"
                errors.append(errorMsg)
                logger.warning("Provider \(provider.providerName) failed: \(error.localizedDescription)")
            }
        }

        // Return merged result if we have one
        if let result = result {
            return result
        }

        // No results found - return nil (not an error, just no data)
        if errors.isEmpty {
            return nil
        }

        // All providers failed with errors
        throw MetadataError.allProvidersFailed(errors)
    }

    /// Fetch metadata by title and author with fallback strategy
    /// - Parameters:
    ///   - title: Book title
    ///   - author: Optional author name
    ///   - options: Search options
    /// - Returns: Array of matching metadata sorted by confidence
    public func fetchMetadata(
        title: String,
        author: String? = nil,
        options: MetadataSearchOptions = .titleSearch
    ) async throws -> [BookMetadata] {
        guard !providers.isEmpty else {
            throw MetadataError.noProvidersAvailable
        }

        var errors: [String] = []
        var allResults: [BookMetadata] = []

        for provider in providers {
            do {
                logger.debug("Searching '\(title)' by \(author ?? "unknown") from \(provider.providerName)")

                let results = try await provider.fetchMetadata(title: title, author: author)

                let filteredResults = results.filter { $0.confidence >= options.minimumConfidence }

                if !filteredResults.isEmpty {
                    logger.info("Found \(filteredResults.count) results from \(provider.providerName)")

                    if options.mergeResults {
                        allResults.append(contentsOf: filteredResults)
                    } else {
                        // Return first successful provider's results
                        return Array(filteredResults.prefix(options.maxResults))
                    }
                }
            } catch let error as MetadataError {
                let errorMsg = "\(provider.providerName): \(error.localizedDescription)"
                errors.append(errorMsg)
                logger.warning("Provider \(provider.providerName) failed: \(error.localizedDescription)")
            } catch {
                let errorMsg = "\(provider.providerName): \(error.localizedDescription)"
                errors.append(errorMsg)
                logger.warning("Provider \(provider.providerName) failed: \(error.localizedDescription)")
            }
        }

        // Return merged and sorted results
        if !allResults.isEmpty {
            let sortedResults = allResults.sorted { $0.confidence > $1.confidence }
            return Array(sortedResults.prefix(options.maxResults))
        }

        // No results but no errors either
        if errors.isEmpty {
            return []
        }

        // All providers failed
        throw MetadataError.allProvidersFailed(errors)
    }

    /// Fetch cover image URL for a book
    /// - Parameter isbn: The book ISBN
    /// - Returns: URL to cover image from first provider that has one
    public func fetchCoverImage(isbn: String) async throws -> URL? {
        guard !providers.isEmpty else {
            throw MetadataError.noProvidersAvailable
        }

        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")

        for provider in providers {
            do {
                if let url = try await provider.fetchCoverImage(isbn: cleanISBN) {
                    logger.debug("Found cover image from \(provider.providerName)")
                    return url
                }
            } catch {
                logger.debug("Cover fetch from \(provider.providerName) failed: \(error.localizedDescription)")
                // Continue to next provider
            }
        }

        return nil
    }

    /// Enhance existing metadata by fetching additional information
    /// - Parameters:
    ///   - metadata: Existing metadata to enhance
    ///   - options: Search options
    /// - Returns: Enhanced metadata merged with fetched data
    public func enhanceMetadata(
        _ metadata: BookMetadata,
        options: MetadataSearchOptions = .isbnLookup
    ) async throws -> BookMetadata {
        // Try ISBN first if available
        if let isbn = metadata.isbn13 ?? metadata.isbn {
            if let fetched = try await fetchMetadata(isbn: isbn, options: options) {
                return metadata.merged(with: fetched)
            }
        }

        // Fall back to title/author search
        if !metadata.title.isEmpty {
            let results = try await fetchMetadata(
                title: metadata.title,
                author: metadata.authors.first,
                options: options
            )

            if let best = results.first, best.confidence > metadata.confidence {
                return metadata.merged(with: best)
            }
        }

        return metadata
    }

    /// Check if a valid ISBN
    /// - Parameter isbn: String to validate
    /// - Returns: true if valid ISBN-10 or ISBN-13
    public static func isValidISBN(_ isbn: String) -> Bool {
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if cleanISBN.count == 10 {
            return isValidISBN10(cleanISBN)
        } else if cleanISBN.count == 13 {
            return isValidISBN13(cleanISBN)
        }
        return false
    }

    /// Convert ISBN-10 to ISBN-13
    /// - Parameter isbn10: Valid ISBN-10
    /// - Returns: ISBN-13 or nil if invalid input
    public static func isbn10ToISBN13(_ isbn10: String) -> String? {
        let clean = isbn10.replacingOccurrences(of: "-", with: "")
        guard clean.count == 10, isValidISBN10(clean) else { return nil }

        // Remove check digit and prepend 978
        let prefix = "978" + String(clean.dropLast())

        // Calculate new check digit
        var sum = 0
        for (index, char) in prefix.enumerated() {
            guard let digit = Int(String(char)) else { return nil }
            let weight = (index % 2 == 0) ? 1 : 3
            sum += digit * weight
        }

        let checkDigit = (10 - (sum % 10)) % 10
        return prefix + String(checkDigit)
    }

    // MARK: - Private Methods

    private static func isValidISBN10(_ isbn: String) -> Bool {
        guard isbn.count == 10 else { return false }

        var sum = 0
        for (index, char) in isbn.enumerated() {
            let weight = 10 - index
            if char == "X" && index == 9 {
                sum += 10 * weight
            } else if let digit = Int(String(char)) {
                sum += digit * weight
            } else {
                return false
            }
        }

        return sum % 11 == 0
    }

    private static func isValidISBN13(_ isbn: String) -> Bool {
        guard isbn.count == 13 else { return false }

        var sum = 0
        for (index, char) in isbn.enumerated() {
            guard let digit = Int(String(char)) else { return false }
            let weight = (index % 2 == 0) ? 1 : 3
            sum += digit * weight
        }

        return sum % 10 == 0
    }
}
