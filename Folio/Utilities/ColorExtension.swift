//
// ColorExtension.swift
// Folio
//
// Extension for initializing SwiftUI Color from hex strings.
// Supports 6-digit hex codes with or without # prefix.
//
// Usage:
//   Color(hex: "#FF5733")
//   Color(hex: "FF5733")
//

import SwiftUI

extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: A 6-digit hex color code (with or without # prefix)
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
