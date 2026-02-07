// Date+Extensions.swift
// Date utility extensions for formatting and parsing

import Foundation

public extension Date {
    /// ISO8601 formatted string
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }

    /// Relative time string (e.g., "2 hours ago")
    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    /// Short date string (e.g., "Jan 15, 2025")
    var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    /// Full date string (e.g., "January 15, 2025 at 3:30 PM")
    var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    /// Year only (e.g., "2025")
    var yearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: self)
    }

    /// Check if date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Check if date is yesterday
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Check if date is within the last week
    var isWithinLastWeek: Bool {
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return false
        }
        return self > weekAgo
    }

    /// Parse date from various formats commonly found in ebook metadata
    static func fromMetadataString(_ string: String) -> Date? {
        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "MMMM d, yyyy",
            "MMM d, yyyy",
            "yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try ISO8601
        if let date = ISO8601DateFormatter().date(from: string) {
            return date
        }

        return nil
    }
}
