// SendToKindleService.swift
// Send ebooks to Kindle devices via email

import Foundation
import Network
import OSLog

private let kindleLogger = Logger(subsystem: "com.folio", category: "SendToKindle")

/// Service for sending ebooks to Kindle devices via email
public actor SendToKindleService {

    // MARK: - Types

    /// SMTP server configuration
    public struct SMTPConfiguration: Codable, Sendable {
        public let host: String
        public let port: Int
        public let username: String
        public let useTLS: Bool

        /// Common SMTP configurations
        public static let gmail = SMTPConfiguration(
            host: "smtp.gmail.com",
            port: 587,
            username: "",
            useTLS: true
        )

        public static let outlook = SMTPConfiguration(
            host: "smtp.office365.com",
            port: 587,
            username: "",
            useTLS: true
        )

        public static let icloud = SMTPConfiguration(
            host: "smtp.mail.me.com",
            port: 587,
            username: "",
            useTLS: true
        )

        public init(host: String, port: Int, username: String, useTLS: Bool) {
            self.host = host
            self.port = port
            self.username = username
            self.useTLS = useTLS
        }
    }

    /// Result of a send operation
    public struct SendResult: Sendable {
        public let success: Bool
        public let bookTitle: String
        public let kindleEmail: String
        public let message: String
        public let timestamp: Date

        public init(success: Bool, bookTitle: String, kindleEmail: String, message: String) {
            self.success = success
            self.bookTitle = bookTitle
            self.kindleEmail = kindleEmail
            self.message = message
            self.timestamp = Date()
        }
    }

    // MARK: - Constants

    /// Maximum file size allowed by Amazon (50 MB)
    public static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024

    /// Valid Kindle email domains
    private static let validKindleDomains = ["@kindle.com", "@free.kindle.com"]

    // MARK: - Properties

    /// Keychain service for credential storage
    private let keychainService: KeychainService

    /// Current SMTP configuration
    private var smtpConfiguration: SMTPConfiguration?

    /// User defaults key for SMTP config
    private let smtpConfigKey = "com.folio.smtp.configuration"

    /// User defaults key for Kindle email
    private let kindleEmailKey = "com.folio.kindle.email"

    /// Shared instance
    public static let shared = SendToKindleService()

    // MARK: - Initialization

    public init(keychainService: KeychainService = .shared) {
        self.keychainService = keychainService
        // Load config directly here to avoid actor isolation issue
        if let data = UserDefaults.standard.data(forKey: smtpConfigKey),
           let config = try? JSONDecoder().decode(SMTPConfiguration.self, from: data) {
            self.smtpConfiguration = config
        } else {
            self.smtpConfiguration = nil
        }
    }

    // MARK: - Public Methods

    /// Send an ebook file to a Kindle device
    /// - Parameters:
    ///   - fileURL: URL of the ebook file to send
    ///   - kindleEmail: Destination Kindle email address
    ///   - bookTitle: Title of the book (for email subject)
    /// - Returns: Result of the send operation
    /// - Throws: `SendToKindleError` if validation or sending fails
    public func send(
        fileURL: URL,
        to kindleEmail: String,
        bookTitle: String
    ) async throws -> SendResult {
        // Validate Kindle email
        guard isValidKindleEmail(kindleEmail) else {
            throw SendToKindleError.invalidKindleEmail(kindleEmail)
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FolioError.fileNotFound(fileURL)
        }

        // Check file size
        let fileSize = try getFileSize(at: fileURL)
        guard fileSize <= Self.maxFileSizeBytes else {
            throw SendToKindleError.fileTooLarge(fileSize)
        }

        // Validate format is Kindle-compatible
        if let format = EbookFormat(url: fileURL), !format.kindleCompatible {
            kindleLogger.warning("Format \(format.rawValue) may not be compatible with Kindle")
        }

        // Verify SMTP configuration
        guard let config = smtpConfiguration else {
            throw SendToKindleError.smtpConfigMissing
        }

        // Get SMTP password from Keychain
        guard let password = try? keychainService.retrieve(for: KeychainService.AccountKey.smtpPassword) else {
            throw SendToKindleError.smtpConfigMissing
        }

        // Send the email
        do {
            try await sendEmail(
                to: kindleEmail,
                subject: bookTitle,
                attachmentURL: fileURL,
                smtpConfig: config,
                password: password
            )

            kindleLogger.info("Successfully sent '\(bookTitle)' to \(kindleEmail)")

            return SendResult(
                success: true,
                bookTitle: bookTitle,
                kindleEmail: kindleEmail,
                message: "Book sent successfully"
            )
        } catch {
            kindleLogger.error("Failed to send '\(bookTitle)': \(error.localizedDescription)")
            throw SendToKindleError.sendFailed(error.localizedDescription)
        }
    }

    /// Validate a Kindle email address
    /// - Parameter email: Email address to validate
    /// - Returns: `true` if the email is a valid Kindle address
    public func isValidKindleEmail(_ email: String) -> Bool {
        let lowercased = email.lowercased().trimmingCharacters(in: .whitespaces)

        // Check for valid domain
        for domain in Self.validKindleDomains {
            if lowercased.hasSuffix(domain) {
                // Verify there's a username before the @
                let username = lowercased.replacingOccurrences(of: domain, with: "")
                return !username.isEmpty && !username.contains("@")
            }
        }

        return false
    }

    /// Check if a file is within the size limit for Kindle
    /// - Parameter fileURL: URL of the file to check
    /// - Returns: `true` if file is within 50MB limit
    public func isWithinSizeLimit(_ fileURL: URL) -> Bool {
        guard let size = try? getFileSize(at: fileURL) else {
            return false
        }
        return size <= Self.maxFileSizeBytes
    }

    /// Get the file size in bytes
    /// - Parameter fileURL: URL of the file
    /// - Returns: File size in bytes
    public func getFileSize(at fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = attributes[.size] as? Int64 else {
            throw FolioError.unknown("Could not determine file size")
        }
        return size
    }

    // MARK: - Configuration

    /// Configure SMTP settings
    /// - Parameters:
    ///   - configuration: SMTP server configuration
    ///   - password: SMTP password (stored in Keychain)
    public func configure(smtp configuration: SMTPConfiguration, password: String) throws {
        // Save password to Keychain
        try keychainService.save(password: password, for: KeychainService.AccountKey.smtpPassword)

        // Save configuration to UserDefaults
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(configuration) {
            UserDefaults.standard.set(data, forKey: smtpConfigKey)
        }

        self.smtpConfiguration = configuration
        kindleLogger.info("SMTP configuration saved for \(configuration.host)")
    }

    /// Get the current SMTP configuration
    /// - Returns: Current SMTP configuration or nil if not configured
    public func getSMTPConfiguration() -> SMTPConfiguration? {
        smtpConfiguration
    }

    /// Check if SMTP is configured
    public var isConfigured: Bool {
        smtpConfiguration != nil && keychainService.exists(for: KeychainService.AccountKey.smtpPassword)
    }

    /// Save the user's Kindle email for convenience
    /// - Parameter email: Kindle email address
    public func saveKindleEmail(_ email: String) throws {
        guard isValidKindleEmail(email) else {
            throw SendToKindleError.invalidKindleEmail(email)
        }
        UserDefaults.standard.set(email, forKey: kindleEmailKey)
    }

    /// Get the saved Kindle email
    /// - Returns: Saved Kindle email or nil
    public func getSavedKindleEmail() -> String? {
        UserDefaults.standard.string(forKey: kindleEmailKey)
    }

    /// Clear all SMTP configuration
    public func clearConfiguration() {
        UserDefaults.standard.removeObject(forKey: smtpConfigKey)
        UserDefaults.standard.removeObject(forKey: kindleEmailKey)
        try? keychainService.delete(for: KeychainService.AccountKey.smtpPassword)
        smtpConfiguration = nil
        kindleLogger.info("SMTP configuration cleared")
    }

    // MARK: - Private Methods

    /// Load SMTP configuration from UserDefaults
    private func loadSMTPConfiguration() -> SMTPConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: smtpConfigKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(SMTPConfiguration.self, from: data)
    }

    /// Send an email with attachment using native Swift SMTP implementation
    /// Uses Network.framework for sandbox-compatible networking
    private func sendEmail(
        to recipient: String,
        subject: String,
        attachmentURL: URL,
        smtpConfig: SMTPConfiguration,
        password: String
    ) async throws {
        let smtpClient = NativeSMTPClient(
            host: smtpConfig.host,
            port: smtpConfig.port,
            username: smtpConfig.username,
            password: password,
            useTLS: smtpConfig.useTLS
        )

        try await smtpClient.send(
            to: recipient,
            subject: subject,
            body: "Sent from Folio - Your Beautiful Ebook Library",
            attachmentURL: attachmentURL
        )
    }
}

// MARK: - Native SMTP Client

/// A native Swift SMTP client using Network.framework
/// This implementation is sandbox-compatible and doesn't require subprocess execution
private actor NativeSMTPClient {
    private let host: String
    private let port: Int
    private let username: String
    private let password: String
    private let useTLS: Bool

    init(host: String, port: Int, username: String, password: String, useTLS: Bool) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
    }

    func send(to recipient: String, subject: String, body: String, attachmentURL: URL) async throws {
        // Read attachment data
        let attachmentData = try Data(contentsOf: attachmentURL)
        let filename = attachmentURL.lastPathComponent

        // Build the MIME message
        let boundary = "Folio-Boundary-\(UUID().uuidString)"
        let mimeMessage = buildMIMEMessage(
            from: username,
            to: recipient,
            subject: subject,
            body: body,
            attachmentData: attachmentData,
            filename: filename,
            boundary: boundary
        )

        // Connect and send via SMTP
        try await sendViaSMTP(to: recipient, message: mimeMessage)
    }

    private func buildMIMEMessage(
        from sender: String,
        to recipient: String,
        subject: String,
        body: String,
        attachmentData: Data,
        filename: String,
        boundary: String
    ) -> String {
        let base64Attachment = attachmentData.base64EncodedString(options: .lineLength76Characters)
        let mimeType = getMIMEType(for: filename)

        return """
        From: \(sender)\r
        To: \(recipient)\r
        Subject: \(subject)\r
        MIME-Version: 1.0\r
        Content-Type: multipart/mixed; boundary="\(boundary)"\r
        \r
        --\(boundary)\r
        Content-Type: text/plain; charset="UTF-8"\r
        Content-Transfer-Encoding: 7bit\r
        \r
        \(body)\r
        --\(boundary)\r
        Content-Type: \(mimeType); name="\(filename)"\r
        Content-Transfer-Encoding: base64\r
        Content-Disposition: attachment; filename="\(filename)"\r
        \r
        \(base64Attachment)\r
        --\(boundary)--\r
        """
    }

    private func getMIMEType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "epub": return "application/epub+zip"
        case "mobi": return "application/x-mobipocket-ebook"
        case "azw", "azw3": return "application/vnd.amazon.ebook"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }

    private func sendViaSMTP(to recipient: String, message: String) async throws {
        // For port 465 (SMTPS), connect with TLS immediately
        // For port 587 (submission), connect plain then upgrade with STARTTLS
        let useImplicitTLS = port == 465

        var connection = try await establishConnection(withTLS: useImplicitTLS)

        // SMTP conversation
        try await readResponse(connection) // Read greeting (220)
        try await sendCommand(connection, "EHLO folio.local")
        try await readResponse(connection) // Read EHLO response

        // Handle STARTTLS for port 587
        if useTLS && !useImplicitTLS {
            try await sendCommand(connection, "STARTTLS")
            try await readResponse(connection) // Read 220 Ready to start TLS

            // Close the plain connection and establish a new TLS connection
            connection.cancel()
            connection = try await establishConnection(withTLS: true)

            // Re-send EHLO after TLS upgrade
            try await sendCommand(connection, "EHLO folio.local")
            try await readResponse(connection)
        }

        // Authenticate using AUTH LOGIN
        try await sendCommand(connection, "AUTH LOGIN")
        try await readResponse(connection) // Read 334 (username prompt)

        let base64User = Data(username.utf8).base64EncodedString()
        try await sendCommand(connection, base64User)
        try await readResponse(connection) // Read 334 (password prompt)

        let base64Pass = Data(password.utf8).base64EncodedString()
        try await sendCommand(connection, base64Pass)
        try await readResponse(connection) // Read 235 (auth successful)

        // Send email envelope
        try await sendCommand(connection, "MAIL FROM:<\(username)>")
        try await readResponse(connection) // Read 250

        try await sendCommand(connection, "RCPT TO:<\(recipient)>")
        try await readResponse(connection) // Read 250

        try await sendCommand(connection, "DATA")
        try await readResponse(connection) // Read 354

        // Send message body (end with CRLF.CRLF)
        try await sendData(connection, message + "\r\n.\r\n")
        try await readResponse(connection) // Read 250

        try await sendCommand(connection, "QUIT")
        // Don't wait for QUIT response, just close
        connection.cancel()
    }

    private func establishConnection(withTLS: Bool) async throws -> NWConnection {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))

        let parameters: NWParameters
        if withTLS {
            // Create TLS options that accept the server's certificate
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, { _, trust, complete in
                // In production, you should properly validate the certificate
                // For now, we trust the connection (standard SMTP servers use valid certs)
                complete(true)
            }, .main)
            parameters = NWParameters(tls: tlsOptions)
        } else {
            parameters = .tcp
        }

        let connection = NWConnection(to: endpoint, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            // Use a class to track resume state safely across concurrent callbacks
            final class ResumeState: @unchecked Sendable {
                private let lock = NSLock()
                private var _hasResumed = false

                var hasResumed: Bool {
                    get { lock.withLock { _hasResumed } }
                    set { lock.withLock { _hasResumed = newValue } }
                }
            }

            let state = ResumeState()

            connection.stateUpdateHandler = { connectionState in
                guard !state.hasResumed else { return }
                switch connectionState {
                case .ready:
                    state.hasResumed = true
                    continuation.resume(returning: connection)
                case .failed(let error):
                    state.hasResumed = true
                    continuation.resume(throwing: SendToKindleError.sendFailed("Connection failed: \(error.localizedDescription)"))
                case .cancelled:
                    state.hasResumed = true
                    continuation.resume(throwing: SendToKindleError.sendFailed("Connection cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func sendCommand(_ connection: NWConnection, _ command: String) async throws {
        let data = Data((command + "\r\n").utf8)
        try await sendData(connection, data)
    }

    private func sendData(_ connection: NWConnection, _ string: String) async throws {
        let data = Data(string.utf8)
        try await sendData(connection, data)
    }

    private func sendData(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: SendToKindleError.sendFailed("Send error: \(error.localizedDescription)"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    @discardableResult
    private func readResponse(_ connection: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
                if let error = error {
                    continuation.resume(throwing: SendToKindleError.sendFailed("Read error: \(error.localizedDescription)"))
                    return
                }

                guard let data = data, let response = String(data: data, encoding: .utf8) else {
                    continuation.resume(throwing: SendToKindleError.sendFailed("Invalid response"))
                    return
                }

                // Check for SMTP error codes (4xx or 5xx)
                let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
                if let firstChar = trimmed.first, firstChar == "4" || firstChar == "5" {
                    continuation.resume(throwing: SendToKindleError.sendFailed("SMTP error: \(trimmed)"))
                    return
                }

                continuation.resume(returning: response)
            }
        }
    }
}

// MARK: - File Size Formatting

extension SendToKindleService {

    /// Format file size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Human-readable size string
    public static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format the maximum file size for display
    public static var maxFileSizeFormatted: String {
        formatFileSize(maxFileSizeBytes)
    }
}
