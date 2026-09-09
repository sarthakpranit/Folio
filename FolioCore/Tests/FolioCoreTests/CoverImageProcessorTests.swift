//
//  CoverImageProcessorTests.swift
//  FolioCoreTests
//
//  Verifies that CoverImageProcessor is a safe funnel for cover bytes headed
//  into the store (#67): a large source must come back within the pixel cap and
//  weigh less than it did.
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FolioCore

final class CoverImageProcessorTests: XCTestCase {

    func testDownscaleShrinksDimensionsAndByteCount() throws {
        let sourcePixels = 1200
        let largePNG = try Self.noisePNG(pixels: sourcePixels)

        let processed = try CoverImageProcessor.downscaledAndReEncoded(largePNG)

        // Re-encoded cover weighs less than the raw download.
        XCTAssertLessThan(processed.count, largePNG.count)

        // Longer edge is capped, and genuinely smaller than the source.
        let (width, height) = try Self.pixelSize(of: processed)
        XCTAssertLessThanOrEqual(max(width, height), CoverImageProcessor.defaultMaxPixelSize)
        XCTAssertLessThan(max(width, height), sourcePixels)
    }

    func testAlreadySmallSourceIsNotUpscaled() throws {
        let sourcePixels = 120
        let smallPNG = try Self.noisePNG(pixels: sourcePixels)

        let processed = try CoverImageProcessor.downscaledAndReEncoded(smallPNG)

        let (width, height) = try Self.pixelSize(of: processed)
        XCTAssertEqual(max(width, height), sourcePixels)
    }

    func testNonImageDataThrowsDecodeFailed() {
        let junk = Data("definitely not an image".utf8)
        XCTAssertThrowsError(try CoverImageProcessor.downscaledAndReEncoded(junk)) { error in
            XCTAssertEqual(error as? CoverImageError, .decodeFailed)
        }
    }

    // MARK: - Helpers

    /// Build an incompressible RGBA noise PNG so byte-count assertions are not
    /// at the mercy of PNG run-length compression.
    private static func noisePNG(pixels: Int) throws -> Data {
        let bytesPerRow = pixels * 4
        var raw = [UInt8](repeating: 0, count: bytesPerRow * pixels)
        var state: UInt64 = 0x9E3779B97F4A7C15
        for index in raw.indices {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            raw[index] = UInt8(state & 0xFF)
        }

        let context = try XCTUnwrap(raw.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        })
        let image = try XCTUnwrap(context.makeImage())

        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private static func pixelSize(of data: Data) throws -> (Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        return (width, height)
    }
}
