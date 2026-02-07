// FolioError.swift
// Comprehensive error types for Folio

import Foundation

/// Base error types for Folio
public enum FolioError: LocalizedError {
    case fileNotFound(URL)
    case invalidFormat(String)
    case importFailed(String)
    case conversionFailed(String)
    case networkError(Error)
    case persistenceError(Error)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .invalidFormat(let format):
            return "Invalid or unsupported format: \(format)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        case .conversionFailed(let reason):
            return "Conversion failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .persistenceError(let error):
            return "Database error: \(error.localizedDescription)"
        case .unknown(let message):
            return message
        }
    }
}

/// Errors specific to Calibre conversion
public enum ConversionError: LocalizedError {
    case calibreNotFound
    case unsupportedInputFormat(String)
    case unsupportedOutputFormat(String)
    case conversionTimeout
    case processFailed(exitCode: Int32, stderr: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .calibreNotFound:
            return "Calibre ebook-convert not found. Please ensure Calibre is installed."
        case .unsupportedInputFormat(let format):
            return "Unsupported input format: \(format)"
        case .unsupportedOutputFormat(let format):
            return "Unsupported output format: \(format)"
        case .conversionTimeout:
            return "Conversion timed out"
        case .processFailed(let code, let stderr):
            return "Conversion failed (exit code \(code)): \(stderr)"
        case .cancelled:
            return "Conversion was cancelled"
        }
    }
}

/// Errors specific to Send to Kindle
public enum SendToKindleError: LocalizedError {
    case fileTooLarge(Int64)
    case invalidKindleEmail(String)
    case smtpConfigMissing
    case smtpAuthFailed
    case sendFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge(let size):
            let mb = Double(size) / 1_000_000
            return "File too large (\(String(format: "%.1f", mb)) MB). Maximum is 50 MB."
        case .invalidKindleEmail(let email):
            return "Invalid Kindle email: \(email). Must end with @kindle.com or @free.kindle.com"
        case .smtpConfigMissing:
            return "Email configuration not set. Please configure in Preferences."
        case .smtpAuthFailed:
            return "SMTP authentication failed. Check email credentials."
        case .sendFailed(let reason):
            return "Failed to send: \(reason)"
        }
    }
}

/// Errors specific to HTTP transfer
public enum TransferError: LocalizedError {
    case serverNotRunning
    case portUnavailable
    case bookNotFound(UUID)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serverNotRunning:
            return "Transfer server is not running"
        case .portUnavailable:
            return "No available port found for server"
        case .bookNotFound(let id):
            return "Book not found: \(id)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}
