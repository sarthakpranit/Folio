// FolioCore.swift
// Main module file - exports all public types

import Foundation

/// FolioCore version
public let FolioCoreVersion = "1.0.0"

/// FolioCore build date
public let FolioCoreBuildDate = "2025-02-08"

/// Log levels for FolioCore
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Simple logger for FolioCore
public final class FolioLogger: @unchecked Sendable {
    public static let shared = FolioLogger()

    public var minimumLevel: LogLevel = .info
    public var isEnabled: Bool = true

    private init() {}

    public func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard isEnabled, level >= minimumLevel else { return }

        let filename = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)

        let levelString: String
        switch level {
        case .debug: levelString = "DEBUG"
        case .info: levelString = "INFO"
        case .warning: levelString = "WARNING"
        case .error: levelString = "ERROR"
        }

        print("[\(timestamp)] [\(levelString)] [\(filename):\(line)] \(message)")
    }

    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}

/// Global logger instance
public let logger = FolioLogger.shared
