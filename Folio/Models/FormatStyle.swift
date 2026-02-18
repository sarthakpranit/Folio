//
//  FormatStyle.swift
//  Folio
//
//  A value object that encapsulates the visual styling for ebook formats.
//  Consolidates the duplicate formatColor/formatIcon implementations
//  scattered throughout the codebase into a single source of truth.
//
//  Design Philosophy:
//  - EPUB (blue): The standard, universal ebook format
//  - PDF (red): Document-focused, print-ready
//  - MOBI/AZW3 (orange): Kindle-native formats, warm/fire themed
//  - CBZ/CBR (purple): Comic book archives, creative content
//  - TXT/RTF (gray): Plain text, minimal styling
//
//  Usage:
//    let style = FormatStyle(format: "epub")
//    Image(systemName: style.icon)
//        .foregroundColor(style.color)
//        .background(style.color.opacity(0.15))
//

import SwiftUI

/// Encapsulates the visual styling for a book format
struct FormatStyle {
    let format: String
    
    /// The SF Symbol icon name for this format
    var icon: String {
        switch format.lowercased() {
        case "epub": return "book.closed.fill"
        case "pdf": return "doc.text.fill"
        case "mobi", "azw3": return "flame.fill"
        case "cbz", "cbr": return "photo.stack.fill"
        case "txt": return "doc.plaintext.fill"
        case "rtf": return "doc.richtext.fill"
        case "fb2": return "text.book.closed.fill"
        default: return "doc.fill"
        }
    }
    
    /// The accent color for this format
    var color: Color {
        switch format.lowercased() {
        case "epub": return .blue
        case "pdf": return .red
        case "mobi", "azw3": return .orange
        case "cbz", "cbr": return .purple
        case "txt", "rtf": return .gray
        case "fb2": return .green
        default: return .gray
        }
    }
    
    /// A gradient background suitable for cover overlays
    var gradient: LinearGradient {
        let colors: [Color]
        switch format.lowercased() {
        case "epub": colors = [.blue, .blue.opacity(0.7)]
        case "pdf": colors = [.red, .red.opacity(0.7)]
        case "mobi", "azw3": colors = [.orange, .yellow.opacity(0.7)]
        case "cbz", "cbr": colors = [.purple, .purple.opacity(0.7)]
        default: colors = [.gray, .gray.opacity(0.7)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    /// A badge view showing the format with icon
    @ViewBuilder
    func badge() -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(format.uppercased())
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

// MARK: - Convenience Extensions

extension FormatStyle {
    /// Initialize from a Book's format property
    init(book: Book) {
        self.format = book.format ?? "unknown"
    }
}
