// KeychainService.swift
// Secure credential storage using macOS Keychain

import Foundation
import Security

/// Generic Keychain wrapper for storing credentials securely
public final class KeychainService: Sendable {

    // MARK: - Types

    /// Errors specific to Keychain operations
    public enum KeychainError: LocalizedError {
        case encodingFailed
        case saveFailed(OSStatus)
        case retrieveFailed(OSStatus)
        case deleteFailed(OSStatus)
        case itemNotFound
        case unexpectedData

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode password data"
            case .saveFailed(let status):
                return "Failed to save to Keychain (status: \(status))"
            case .retrieveFailed(let status):
                return "Failed to retrieve from Keychain (status: \(status))"
            case .deleteFailed(let status):
                return "Failed to delete from Keychain (status: \(status))"
            case .itemNotFound:
                return "Item not found in Keychain"
            case .unexpectedData:
                return "Unexpected data format in Keychain"
            }
        }
    }

    // MARK: - Properties

    /// Service identifier for Keychain items
    private let serviceName: String

    /// Access group for shared Keychain access (optional)
    private let accessGroup: String?

    /// Shared instance for app-wide use
    public static let shared = KeychainService(serviceName: "com.folio.ebook-manager")

    // MARK: - Initialization

    /// Initialize with custom service name
    /// - Parameters:
    ///   - serviceName: Identifier for Keychain items (typically bundle ID)
    ///   - accessGroup: Optional access group for sharing across apps
    public init(serviceName: String, accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    // MARK: - Public Methods

    /// Save a password to the Keychain
    /// - Parameters:
    ///   - password: The password string to store
    ///   - account: The account identifier (e.g., email address)
    /// - Throws: `KeychainError` if the save operation fails
    public func save(password: String, for account: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Check if item already exists
        if (try? retrieve(for: account)) != nil {
            // Update existing item
            try update(passwordData: passwordData, for: account)
        } else {
            // Create new item
            try create(passwordData: passwordData, for: account)
        }

        logger.debug("Saved credentials for account: \(account)")
    }

    /// Retrieve a password from the Keychain
    /// - Parameter account: The account identifier
    /// - Returns: The stored password string
    /// - Throws: `KeychainError` if retrieval fails or item not found
    public func retrieve(for account: String) throws -> String {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return password

        case errSecItemNotFound:
            throw KeychainError.itemNotFound

        default:
            throw KeychainError.retrieveFailed(status)
        }
    }

    /// Delete a password from the Keychain
    /// - Parameter account: The account identifier
    /// - Throws: `KeychainError` if deletion fails
    public func delete(for account: String) throws {
        let query = baseQuery(for: account)
        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            // Success or already deleted
            logger.debug("Deleted credentials for account: \(account)")

        default:
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if credentials exist for an account
    /// - Parameter account: The account identifier
    /// - Returns: `true` if credentials exist
    public func exists(for account: String) -> Bool {
        (try? retrieve(for: account)) != nil
    }

    // MARK: - Private Methods

    /// Build base query dictionary for Keychain operations
    private func baseQuery(for account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }

    /// Create a new Keychain item
    private func create(passwordData: Data, for account: String) throws {
        var query = baseQuery(for: account)
        query[kSecValueData as String] = passwordData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Update an existing Keychain item
    private func update(passwordData: Data, for account: String) throws {
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
}

// MARK: - Convenience Extensions

extension KeychainService {

    /// Predefined account keys for Folio
    public enum AccountKey {
        /// SMTP password for Send to Kindle
        public static let smtpPassword = "smtp.password"

        /// SMTP username for Send to Kindle
        public static let smtpUsername = "smtp.username"
    }
}
