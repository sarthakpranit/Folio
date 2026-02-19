//
//  FolioCoreTests.swift
//  FolioCoreTests
//
//  Unit tests for FolioCore utilities and models
//

import XCTest
@testable import FolioCore

final class FolioCoreTests: XCTestCase {

    // MARK: - EbookFormat Tests

    func testEbookFormatFromExtension() {
        XCTAssertEqual(EbookFormat(fileExtension: "epub"), .epub)
        XCTAssertEqual(EbookFormat(fileExtension: "EPUB"), .epub)
        XCTAssertEqual(EbookFormat(fileExtension: "mobi"), .mobi)
        XCTAssertEqual(EbookFormat(fileExtension: "pdf"), .pdf)
        XCTAssertEqual(EbookFormat(fileExtension: "azw3"), .azw3)
        XCTAssertNil(EbookFormat(fileExtension: "unknown"))
    }

    func testEbookFormatFromURL() {
        let epubURL = URL(fileURLWithPath: "/path/to/book.epub")
        let mobiURL = URL(fileURLWithPath: "/path/to/book.mobi")
        let unknownURL = URL(fileURLWithPath: "/path/to/file.xyz")

        XCTAssertEqual(EbookFormat(url: epubURL), .epub)
        XCTAssertEqual(EbookFormat(url: mobiURL), .mobi)
        XCTAssertNil(EbookFormat(url: unknownURL))
    }

    func testMimeTypes() {
        XCTAssertEqual(EbookFormat.epub.mimeType, "application/epub+zip")
        XCTAssertEqual(EbookFormat.pdf.mimeType, "application/pdf")
        XCTAssertEqual(EbookFormat.mobi.mimeType, "application/x-mobipocket-ebook")
    }

    func testKindleCompatibility() {
        // Amazon discontinued MOBI support via Send to Kindle in 2022
        XCTAssertFalse(EbookFormat.mobi.kindleCompatible)
        // Supported formats for Send to Kindle
        XCTAssertTrue(EbookFormat.azw3.kindleCompatible)
        XCTAssertTrue(EbookFormat.epub.kindleCompatible) // Amazon converts to AZW
        XCTAssertTrue(EbookFormat.pdf.kindleCompatible)
        XCTAssertTrue(EbookFormat.txt.kindleCompatible)
        // Unsupported formats
        XCTAssertFalse(EbookFormat.cbz.kindleCompatible)
        XCTAssertFalse(EbookFormat.cbr.kindleCompatible)
        XCTAssertFalse(EbookFormat.fb2.kindleCompatible)
    }

    // MARK: - String Extension Tests

    func testTrigrams() {
        let trigrams = "hello".trigrams()
        XCTAssertTrue(trigrams.contains("hel"))
        XCTAssertTrue(trigrams.contains("ell"))
        XCTAssertTrue(trigrams.contains("llo"))
        XCTAssertEqual(trigrams.count, 3)

        // Short strings
        XCTAssertEqual("ab".trigrams(), ["ab"])
        XCTAssertEqual("".trigrams(), [""])
    }

    func testSortableTitle() {
        XCTAssertEqual("The Great Gatsby".sortableTitle, "great gatsby")
        XCTAssertEqual("A Tale of Two Cities".sortableTitle, "tale of two cities")
        XCTAssertEqual("An Introduction to Swift".sortableTitle, "introduction to swift")
        XCTAssertEqual("Harry Potter".sortableTitle, "harry potter")
    }

    func testXMLEscaping() {
        XCTAssertEqual("Hello & World".xmlEscaped, "Hello &amp; World")
        XCTAssertEqual("<script>".xmlEscaped, "&lt;script&gt;")
        XCTAssertEqual("\"quoted\"".xmlEscaped, "&quot;quoted&quot;")
    }

    func testISBN10Validation() {
        XCTAssertTrue("0-306-40615-2".isValidISBN10)
        XCTAssertTrue("0306406152".isValidISBN10)
        XCTAssertTrue("155860832X".isValidISBN10) // X check digit
        XCTAssertFalse("1234567890".isValidISBN10)
        XCTAssertFalse("12345".isValidISBN10)
    }

    func testISBN13Validation() {
        XCTAssertTrue("978-0-306-40615-7".isValidISBN13)
        XCTAssertTrue("9780306406157".isValidISBN13)
        XCTAssertFalse("9780306406150".isValidISBN13)
        XCTAssertFalse("123456789012".isValidISBN13)
    }

    func testNormalizedISBN() {
        XCTAssertEqual("978-0-306-40615-7".normalizedISBN, "9780306406157")
        XCTAssertEqual("0-306-40615-2".normalizedISBN, "0306406152")
        XCTAssertEqual("1-55860-832-X".normalizedISBN, "155860832X")
    }

    // MARK: - URL Extension Tests

    func testIsEbookFile() {
        XCTAssertTrue(URL(fileURLWithPath: "/book.epub").isEbookFile)
        XCTAssertTrue(URL(fileURLWithPath: "/book.MOBI").isEbookFile)
        XCTAssertTrue(URL(fileURLWithPath: "/book.pdf").isEbookFile)
        XCTAssertTrue(URL(fileURLWithPath: "/book.txt").isEbookFile) // TXT is a supported ebook format
        XCTAssertFalse(URL(fileURLWithPath: "/image.jpg").isEbookFile)
        XCTAssertFalse(URL(fileURLWithPath: "/document.doc").isEbookFile) // DOC is not supported (DOCX is)
    }

    func testEbookFormat() {
        XCTAssertEqual(URL(fileURLWithPath: "/book.epub").ebookFormat, .epub)
        XCTAssertEqual(URL(fileURLWithPath: "/book.mobi").ebookFormat, .mobi)
        XCTAssertNil(URL(fileURLWithPath: "/file.xyz").ebookFormat)
    }

    // MARK: - Date Extension Tests

    func testISO8601Format() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(date.iso8601, "1970-01-01T00:00:00Z")
    }

    func testMetadataDateParsing() {
        XCTAssertNotNil(Date.fromMetadataString("2025-01-15"))
        XCTAssertNotNil(Date.fromMetadataString("2025/01/15"))
        XCTAssertNotNil(Date.fromMetadataString("January 15, 2025"))
        XCTAssertNotNil(Date.fromMetadataString("2025"))
        XCTAssertNil(Date.fromMetadataString("invalid"))
    }

    // MARK: - BookMetadata Tests

    func testBookMetadataFromFilename() {
        let metadata1 = BookMetadata.fromFilename("The Great Gatsby.epub")
        XCTAssertEqual(metadata1.title, "The Great Gatsby")
        XCTAssertTrue(metadata1.authors.isEmpty)
        XCTAssertEqual(metadata1.source, "filename")
        XCTAssertEqual(metadata1.confidence, 0.2)

        let metadata2 = BookMetadata.fromFilename("F. Scott Fitzgerald - The Great Gatsby.epub")
        XCTAssertEqual(metadata2.title, "The Great Gatsby")
        XCTAssertEqual(metadata2.authors, ["F. Scott Fitzgerald"])

        let metadata3 = BookMetadata.fromFilename("book_with_underscores.mobi")
        XCTAssertEqual(metadata3.title, "book with underscores")
    }

    func testBookMetadataMerge() {
        let lowConfidence = BookMetadata(
            title: "Unknown",
            authors: [],
            confidence: 0.2,
            source: "filename"
        )

        let highConfidence = BookMetadata(
            title: "The Great Gatsby",
            authors: ["F. Scott Fitzgerald"],
            isbn13: "9780743273565",
            publisher: "Scribner",
            confidence: 0.9,
            source: "google_books"
        )

        let merged = lowConfidence.merged(with: highConfidence)

        XCTAssertEqual(merged.title, "The Great Gatsby")
        XCTAssertEqual(merged.authors, ["F. Scott Fitzgerald"])
        XCTAssertEqual(merged.isbn13, "9780743273565")
        XCTAssertEqual(merged.publisher, "Scribner")
        XCTAssertEqual(merged.confidence, 0.9)
        XCTAssertEqual(merged.source, "google_books")
    }

    // MARK: - Logger Tests

    func testLoggerLevels() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
    }

    // MARK: - Error Types Tests

    func testFolioErrorDescriptions() {
        let fileNotFound = FolioError.fileNotFound(URL(fileURLWithPath: "/test.epub"))
        XCTAssertTrue(fileNotFound.errorDescription?.contains("test.epub") ?? false)

        let invalidFormat = FolioError.invalidFormat("xyz")
        XCTAssertTrue(invalidFormat.errorDescription?.contains("xyz") ?? false)
    }

    func testConversionErrorDescriptions() {
        let calibreNotFound = ConversionError.calibreNotFound
        XCTAssertTrue(calibreNotFound.errorDescription?.contains("Calibre") ?? false)

        let processFailed = ConversionError.processFailed(exitCode: 1, stderr: "error message")
        XCTAssertTrue(processFailed.errorDescription?.contains("error message") ?? false)
    }

    func testSendToKindleErrorDescriptions() {
        let fileTooLarge = SendToKindleError.fileTooLarge(60_000_000)
        XCTAssertTrue(fileTooLarge.errorDescription?.contains("60") ?? false)
        XCTAssertTrue(fileTooLarge.errorDescription?.contains("50 MB") ?? false)

        let invalidEmail = SendToKindleError.invalidKindleEmail("test@gmail.com")
        XCTAssertTrue(invalidEmail.errorDescription?.contains("test@gmail.com") ?? false)
    }

    // MARK: - Performance Tests

    func testTrigramPerformance() {
        let longString = String(repeating: "a", count: 10000)

        measure {
            _ = longString.trigrams()
        }
    }

    func testSearchPerformance() {
        let titles = (0..<1000).map { "Book Title \($0)" }

        measure {
            for title in titles {
                _ = title.sortableTitle
            }
        }
    }
}
