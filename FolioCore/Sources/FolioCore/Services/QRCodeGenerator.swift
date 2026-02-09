// QRCodeGenerator.swift
// QR Code generation for WiFi transfer URLs

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

// MARK: - QR Code Generator

/// Generates QR codes for Folio server URLs
/// Uses Core Image's built-in QR code generator
public final class QRCodeGenerator {

    // MARK: - Properties

    /// Shared instance
    public static let shared = QRCodeGenerator()

    /// CIContext for rendering
    private let context = CIContext()

    /// The QR code filter
    private let qrFilter = CIFilter.qrCodeGenerator()

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Generate a QR code image from a URL string
    /// - Parameters:
    ///   - urlString: The URL to encode in the QR code
    ///   - size: The desired size of the output image (default: 200x200)
    ///   - correctionLevel: Error correction level (L, M, Q, H) - default is M
    /// - Returns: Platform-specific image (NSImage on macOS, UIImage on iOS)
    public func generate(from urlString: String, size: CGFloat = 200, correctionLevel: CorrectionLevel = .medium) -> PlatformImage? {
        guard let data = urlString.data(using: .utf8) else {
            logger.error("Failed to encode URL string to data")
            return nil
        }

        // Configure the filter
        qrFilter.message = data
        qrFilter.correctionLevel = correctionLevel.rawValue

        // Get the CIImage output
        guard let ciImage = qrFilter.outputImage else {
            logger.error("Failed to generate QR code CIImage")
            return nil
        }

        // Scale the image to the desired size
        let scaleX = size / ciImage.extent.size.width
        let scaleY = size / ciImage.extent.size.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Convert to CGImage
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            logger.error("Failed to create CGImage from CIImage")
            return nil
        }

        #if os(macOS)
        // Create NSImage from CGImage
        let image = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        return image
        #else
        // Create UIImage from CGImage
        return UIImage(cgImage: cgImage)
        #endif
    }

    /// Generate a QR code with custom styling
    /// - Parameters:
    ///   - urlString: The URL to encode
    ///   - size: Output size
    ///   - foregroundColor: Color of the QR code modules (default: black)
    ///   - backgroundColor: Background color (default: white)
    /// - Returns: Styled QR code image
    public func generateStyled(
        from urlString: String,
        size: CGFloat = 200,
        foregroundColor: CIColor = CIColor.black,
        backgroundColor: CIColor = CIColor.white
    ) -> PlatformImage? {
        guard let data = urlString.data(using: .utf8) else {
            return nil
        }

        // Generate base QR code
        qrFilter.message = data
        qrFilter.correctionLevel = CorrectionLevel.medium.rawValue

        guard let ciImage = qrFilter.outputImage else {
            return nil
        }

        // Apply false color filter for custom colors
        let colorFilter = CIFilter.falseColor()
        colorFilter.inputImage = ciImage
        colorFilter.color0 = foregroundColor
        colorFilter.color1 = backgroundColor

        guard let coloredImage = colorFilter.outputImage else {
            return nil
        }

        // Scale to desired size
        let scaleX = size / coloredImage.extent.size.width
        let scaleY = size / coloredImage.extent.size.height
        let scaledImage = coloredImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Convert to platform image
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return nil
        }

        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    /// Generate QR code data as PNG
    /// - Parameters:
    ///   - urlString: The URL to encode
    ///   - size: Output size
    /// - Returns: PNG data of the QR code
    public func generatePNGData(from urlString: String, size: CGFloat = 200) -> Data? {
        guard let image = generate(from: urlString, size: size) else {
            return nil
        }

        #if os(macOS)
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return image.pngData()
        #endif
    }
}

// MARK: - Correction Level

extension QRCodeGenerator {
    /// Error correction level for QR codes
    /// Higher levels can recover more data but result in larger codes
    public enum CorrectionLevel: String {
        /// ~7% error correction - smallest code
        case low = "L"

        /// ~15% error correction - default, good balance
        case medium = "M"

        /// ~25% error correction
        case quartile = "Q"

        /// ~30% error correction - most robust, largest code
        case high = "H"
    }
}

// MARK: - Convenience Extensions

#if os(macOS)
extension QRCodeGenerator {
    /// Generate a QR code suitable for display in a SwiftUI Image view
    /// - Parameters:
    ///   - urlString: The URL to encode
    ///   - size: Output size
    /// - Returns: NSImage ready for SwiftUI
    public func generateForSwiftUI(from urlString: String, size: CGFloat = 200) -> NSImage? {
        generate(from: urlString, size: size)
    }
}
#endif
