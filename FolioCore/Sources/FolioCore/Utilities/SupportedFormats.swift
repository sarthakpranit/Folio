// SupportedFormats.swift
// Supported ebook formats and their properties

import Foundation

/// Supported ebook formats and their properties
public enum EbookFormat: String, CaseIterable, Identifiable, Sendable {
    case epub = "epub"
    case mobi = "mobi"
    case azw3 = "azw3"
    case pdf = "pdf"
    case cbz = "cbz"
    case cbr = "cbr"
    case fb2 = "fb2"
    case lit = "lit"
    case pdb = "pdb"
    case txt = "txt"
    case rtf = "rtf"
    case docx = "docx"

    public var id: String { rawValue }

    /// Display name for the format
    public var displayName: String {
        switch self {
        case .epub: return "EPUB"
        case .mobi: return "MOBI"
        case .azw3: return "AZW3"
        case .pdf: return "PDF"
        case .cbz: return "CBZ (Comic)"
        case .cbr: return "CBR (Comic)"
        case .fb2: return "FictionBook"
        case .lit: return "LIT"
        case .pdb: return "PDB"
        case .txt: return "Plain Text"
        case .rtf: return "Rich Text"
        case .docx: return "Word Document"
        }
    }

    /// MIME type for HTTP responses
    public var mimeType: String {
        switch self {
        case .epub: return "application/epub+zip"
        case .mobi: return "application/x-mobipocket-ebook"
        case .azw3: return "application/vnd.amazon.ebook"
        case .pdf: return "application/pdf"
        case .cbz: return "application/vnd.comicbook+zip"
        case .cbr: return "application/vnd.comicbook-rar"
        case .fb2: return "application/x-fictionbook+xml"
        case .lit: return "application/x-ms-reader"
        case .pdb: return "application/vnd.palm"
        case .txt: return "text/plain"
        case .rtf: return "application/rtf"
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        }
    }

    /// Can be converted to other formats by Calibre
    public var supportsConversion: Bool {
        switch self {
        case .epub, .mobi, .azw3, .pdf, .fb2, .lit, .pdb, .txt, .rtf, .docx:
            return true
        case .cbz, .cbr:
            return false // Comics are image-based
        }
    }

    /// Supported by Kindle devices via Send to Kindle
    /// Note: Amazon discontinued MOBI support in 2022. EPUB, AZW3, and KFX are the supported formats.
    /// PDF and TXT are also supported but may have formatting limitations.
    public var kindleCompatible: Bool {
        switch self {
        case .epub, .azw3:
            return true
        case .pdf, .txt:
            return true // Supported but with limitations
        default:
            return false
        }
    }

    /// Native Kindle format that can be downloaded via Kindle browser
    /// The Kindle experimental browser only accepts: .azw, .prc, .mobi, .txt
    public var kindleNativeFormat: Bool {
        switch self {
        case .mobi, .azw3, .txt:
            return true
        default:
            return false
        }
    }

    /// Supported by Kobo devices
    public var koboCompatible: Bool {
        switch self {
        case .epub, .pdf, .txt, .cbz, .cbr:
            return true
        default:
            return false
        }
    }

    /// Initialize from file extension
    public init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }

    /// Initialize from URL
    public init?(url: URL) {
        self.init(fileExtension: url.pathExtension)
    }

    /// All formats supported for import
    public static var importFormats: [EbookFormat] {
        allCases
    }

    /// File extensions for open panel
    public static var fileExtensions: [String] {
        allCases.map { $0.rawValue }
    }
}
