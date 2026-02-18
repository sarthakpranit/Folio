// SendToKindleService.swift
// Send ebooks to Kindle devices via email

import Foundation

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
            logger.warning("Format \(format.rawValue) may not be compatible with Kindle")
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

            logger.info("Successfully sent '\(bookTitle)' to \(kindleEmail)")

            return SendResult(
                success: true,
                bookTitle: bookTitle,
                kindleEmail: kindleEmail,
                message: "Book sent successfully"
            )
        } catch {
            logger.error("Failed to send '\(bookTitle)': \(error.localizedDescription)")
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
        logger.info("SMTP configuration saved for \(configuration.host)")
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
        logger.info("SMTP configuration cleared")
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

    /// Send an email with attachment using system mail command
    /// This is a simplified MVP implementation. For production, consider using
    /// a proper SMTP library like SwiftSMTP or BlueSSLService.
    private func sendEmail(
        to recipient: String,
        subject: String,
        attachmentURL: URL,
        smtpConfig: SMTPConfiguration,
        password: String
    ) async throws {
        // For MVP, we use a Python script approach which is more reliable
        // than the built-in mail command for SMTP with TLS
        let script = createSendEmailScript(
            to: recipient,
            subject: subject,
            attachmentPath: attachmentURL.path,
            smtpHost: smtpConfig.host,
            smtpPort: smtpConfig.port,
            smtpUser: smtpConfig.username,
            smtpPassword: password,
            useTLS: smtpConfig.useTLS
        )

        // Write script to temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("folio_send_email.py")

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        // Execute Python script
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw SendToKindleError.sendFailed(errorMessage)
        }
    }

    /// Create a Python script for sending email with attachment
    /// Using Python's smtplib as it's reliable and available on macOS
    private func createSendEmailScript(
        to recipient: String,
        subject: String,
        attachmentPath: String,
        smtpHost: String,
        smtpPort: Int,
        smtpUser: String,
        smtpPassword: String,
        useTLS: Bool
    ) -> String {
        // Escape special characters for Python
        let escapedPassword = smtpPassword.replacingOccurrences(of: "'", with: "\\'")
        let escapedSubject = subject.replacingOccurrences(of: "'", with: "\\'")

        return """
        #!/usr/bin/env python3
        import smtplib
        import os
        from email.mime.multipart import MIMEMultipart
        from email.mime.base import MIMEBase
        from email.mime.text import MIMEText
        from email import encoders

        def send_email():
            msg = MIMEMultipart()
            msg['From'] = '\(smtpUser)'
            msg['To'] = '\(recipient)'
            msg['Subject'] = '\(escapedSubject)'

            # Add body text
            body = 'Sent from Folio - Your Beautiful Ebook Library'
            msg.attach(MIMEText(body, 'plain'))

            # Attach the file
            attachment_path = '\(attachmentPath)'
            filename = os.path.basename(attachment_path)

            with open(attachment_path, 'rb') as f:
                part = MIMEBase('application', 'octet-stream')
                part.set_payload(f.read())

            encoders.encode_base64(part)
            part.add_header('Content-Disposition', f'attachment; filename="{filename}"')
            msg.attach(part)

            # Send the email
            server = smtplib.SMTP('\(smtpHost)', \(smtpPort))
            \(useTLS ? "server.starttls()" : "")
            server.login('\(smtpUser)', '\(escapedPassword)')
            server.send_message(msg)
            server.quit()

        if __name__ == '__main__':
            send_email()
        """
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
