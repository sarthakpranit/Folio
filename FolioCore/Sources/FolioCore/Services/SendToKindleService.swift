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

/// A native Swift SMTP client using CFStream for STARTTLS support
/// This implementation properly supports in-place TLS upgrade required by STARTTLS
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

        // Use CFStream which properly supports STARTTLS (in-place TLS upgrade)
        let smtpConnection = try SMTPStreamConnection(host: host, port: port)

        if useImplicitTLS {
            // Port 465: Enable TLS immediately before any communication
            try smtpConnection.enableTLS()
        }

        // SMTP conversation
        try smtpConnection.readResponse() // Read greeting (220)
        try smtpConnection.sendCommand("EHLO folio.local")
        try smtpConnection.readResponse() // Read EHLO response

        // Handle STARTTLS for port 587
        if useTLS && !useImplicitTLS {
            try smtpConnection.sendCommand("STARTTLS")
            try smtpConnection.readResponse() // Read 220 Ready to start TLS

            // Upgrade the EXISTING connection to TLS (this is the key fix!)
            try smtpConnection.enableTLS()

            // Re-send EHLO after TLS upgrade
            try smtpConnection.sendCommand("EHLO folio.local")
            try smtpConnection.readResponse()
        }

        // Authenticate using AUTH LOGIN
        try smtpConnection.sendCommand("AUTH LOGIN")
        try smtpConnection.readResponse() // Read 334 (username prompt)

        let base64User = Data(username.utf8).base64EncodedString()
        try smtpConnection.sendCommand(base64User)
        try smtpConnection.readResponse() // Read 334 (password prompt)

        let base64Pass = Data(password.utf8).base64EncodedString()
        try smtpConnection.sendCommand(base64Pass)
        try smtpConnection.readResponse() // Read 235 (auth successful)

        // Send email envelope
        try smtpConnection.sendCommand("MAIL FROM:<\(username)>")
        try smtpConnection.readResponse() // Read 250

        try smtpConnection.sendCommand("RCPT TO:<\(recipient)>")
        try smtpConnection.readResponse() // Read 250

        try smtpConnection.sendCommand("DATA")
        try smtpConnection.readResponse() // Read 354

        // Send message body (end with CRLF.CRLF)
        try smtpConnection.sendData(message + "\r\n.\r\n")
        try smtpConnection.readResponse() // Read 250

        try smtpConnection.sendCommand("QUIT")
        smtpConnection.close()
    }
}

// MARK: - SMTP Stream Connection

/// A CFStream-based connection that supports STARTTLS (in-place TLS upgrade)
private final class SMTPStreamConnection: @unchecked Sendable {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let host: String
    private let port: Int

    init(host: String, port: Int) throws {
        self.host = host
        self.port = port

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(
            kCFAllocatorDefault,
            host as CFString,
            UInt32(port),
            &readStream,
            &writeStream
        )

        guard let inputCF = readStream?.takeRetainedValue(),
              let outputCF = writeStream?.takeRetainedValue() else {
            throw SendToKindleError.sendFailed("Failed to create socket streams to \(host):\(port)")
        }

        inputStream = inputCF as InputStream
        outputStream = outputCF as OutputStream

        // Open the streams
        inputStream?.open()
        outputStream?.open()

        // Wait for streams to be ready
        try waitForStreamsReady()
    }

    private func waitForStreamsReady() throws {
        let timeout: TimeInterval = 30
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            let inputStatus = inputStream?.streamStatus ?? .error
            let outputStatus = outputStream?.streamStatus ?? .error

            if inputStatus == .error || outputStatus == .error {
                let inputError = inputStream?.streamError?.localizedDescription ?? "unknown"
                let outputError = outputStream?.streamError?.localizedDescription ?? "unknown"
                throw SendToKindleError.sendFailed("Stream error - input: \(inputError), output: \(outputError)")
            }

            if inputStatus == .open && outputStatus == .open {
                return // Ready!
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        throw SendToKindleError.sendFailed("Timeout waiting for streams to open")
    }

    /// Upgrade the existing connection to TLS (supports STARTTLS)
    func enableTLS() throws {
        guard let input = inputStream, let output = outputStream else {
            throw SendToKindleError.sendFailed("Streams not initialized")
        }

        // Set SSL/TLS properties on the existing streams
        // This is the key difference from NWConnection - we upgrade in-place
        let sslSettings: [String: Any] = [
            kCFStreamSSLLevel as String: kCFStreamSocketSecurityLevelNegotiatedSSL,
            kCFStreamSSLPeerName as String: host,
            // Allow self-signed certs for testing (remove in production if needed)
            kCFStreamSSLValidatesCertificateChain as String: true
        ]

        // Apply SSL settings to both streams
        let inputSuccess = CFReadStreamSetProperty(
            input as CFReadStream,
            CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings),
            sslSettings as CFDictionary
        )

        let outputSuccess = CFWriteStreamSetProperty(
            output as CFWriteStream,
            CFStreamPropertyKey(rawValue: kCFStreamPropertySSLSettings),
            sslSettings as CFDictionary
        )

        guard inputSuccess && outputSuccess else {
            throw SendToKindleError.sendFailed("Failed to enable TLS on streams")
        }

        // Wait for TLS handshake to complete
        try waitForTLSHandshake()

        kindleLogger.debug("TLS enabled successfully for \(self.host)")
    }

    private func waitForTLSHandshake() throws {
        let timeout: TimeInterval = 30
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            // Check for errors
            if let inputError = inputStream?.streamError {
                throw SendToKindleError.sendFailed("TLS handshake failed (input): \(inputError.localizedDescription)")
            }
            if let outputError = outputStream?.streamError {
                throw SendToKindleError.sendFailed("TLS handshake failed (output): \(outputError.localizedDescription)")
            }

            // Check if streams are still open (TLS upgrade preserves open state)
            let inputStatus = inputStream?.streamStatus ?? .error
            let outputStatus = outputStream?.streamStatus ?? .error

            if inputStatus == .open && outputStatus == .open {
                // Give a small delay for TLS negotiation to fully complete
                Thread.sleep(forTimeInterval: 0.1)
                return
            }

            if inputStatus == .error || outputStatus == .error {
                throw SendToKindleError.sendFailed("Stream entered error state during TLS handshake")
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        throw SendToKindleError.sendFailed("TLS handshake timeout")
    }

    func sendCommand(_ command: String) throws {
        try sendData(command + "\r\n")
    }

    func sendData(_ data: String) throws {
        guard let output = outputStream else {
            throw SendToKindleError.sendFailed("Output stream not available")
        }

        guard let dataBytes = data.data(using: .utf8) else {
            throw SendToKindleError.sendFailed("Failed to encode data as UTF-8")
        }

        var totalWritten = 0
        let bytes = [UInt8](dataBytes)

        while totalWritten < bytes.count {
            let written = output.write(bytes, maxLength: bytes.count - totalWritten)
            if written < 0 {
                throw SendToKindleError.sendFailed("Write error: \(output.streamError?.localizedDescription ?? "unknown")")
            }
            if written == 0 {
                // Stream is full, wait a bit
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            totalWritten += written
        }
    }

    @discardableResult
    func readResponse() throws -> String {
        guard let input = inputStream else {
            throw SendToKindleError.sendFailed("Input stream not available")
        }

        var response = ""
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        let timeout: TimeInterval = 30
        let startTime = Date()

        // Read until we have a complete SMTP response
        while Date().timeIntervalSince(startTime) < timeout {
            // Wait for data to be available
            if !input.hasBytesAvailable {
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }

            let bytesRead = input.read(&buffer, maxLength: bufferSize)

            if bytesRead < 0 {
                throw SendToKindleError.sendFailed("Read error: \(input.streamError?.localizedDescription ?? "unknown")")
            }

            if bytesRead == 0 {
                continue
            }

            guard let chunk = String(bytes: buffer[0..<bytesRead], encoding: .utf8) else {
                throw SendToKindleError.sendFailed("Invalid UTF-8 response")
            }

            response += chunk

            // SMTP responses end with \r\n and multi-line responses have a space after the code on the last line
            // Single line: "220 smtp.gmail.com ready\r\n"
            // Multi-line: "250-SIZE 35882577\r\n250 8BITMIME\r\n"
            if response.hasSuffix("\r\n") {
                let lines = response.components(separatedBy: "\r\n").filter { !$0.isEmpty }
                if let lastLine = lines.last {
                    // Check if this is the final line (code followed by space, not dash)
                    if lastLine.count >= 4 {
                        let index = lastLine.index(lastLine.startIndex, offsetBy: 3)
                        let separator = lastLine[index]
                        if separator == " " || separator == "\r" || separator == "\n" {
                            break // Complete response
                        }
                    } else if lastLine.count >= 3 {
                        break // Short response like "250"
                    }
                }
            }
        }

        if response.isEmpty {
            throw SendToKindleError.sendFailed("No response received (timeout)")
        }

        // Check for SMTP error codes (4xx or 5xx)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstChar = trimmed.first, firstChar == "4" || firstChar == "5" {
            throw SendToKindleError.sendFailed("SMTP error: \(trimmed)")
        }

        kindleLogger.debug("SMTP response: \(trimmed)")
        return response
    }

    func close() {
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
    }

    deinit {
        close()
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
