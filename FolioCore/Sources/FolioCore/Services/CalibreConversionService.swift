// CalibreConversionService.swift
// Wrapper around Calibre's ebook-convert CLI for format conversion

import Foundation
import Combine

// MARK: - ConversionOptions

/// Options for ebook conversion
public struct ConversionOptions: Sendable {
    /// Device profile for optimized output (kindle, kobo, ipad, etc.)
    public var profile: String?

    /// Preserve metadata embedded in the source file
    public var preserveEmbeddedMetadata: Bool

    /// Image quality (0-100) for output
    public var quality: Int

    /// Custom output directory (defaults to same directory as input)
    public var outputDirectory: URL?

    /// Additional Calibre CLI arguments
    public var additionalArguments: [String]

    public init(
        profile: String? = nil,
        preserveEmbeddedMetadata: Bool = true,
        quality: Int = 85,
        outputDirectory: URL? = nil,
        additionalArguments: [String] = []
    ) {
        self.profile = profile
        self.preserveEmbeddedMetadata = preserveEmbeddedMetadata
        self.quality = max(0, min(100, quality))
        self.outputDirectory = outputDirectory
        self.additionalArguments = additionalArguments
    }

    /// Default options for high-quality output
    public static let `default` = ConversionOptions()

    /// Optimized for Kindle devices
    public static func kindle() -> ConversionOptions {
        ConversionOptions(profile: "kindle_oasis", quality: 90)
    }

    /// Optimized for Kobo devices
    public static func kobo() -> ConversionOptions {
        ConversionOptions(profile: "kobo", quality: 85)
    }

    /// Optimized for iPad
    public static func ipad() -> ConversionOptions {
        ConversionOptions(profile: "ipad3", quality: 95)
    }
}

// MARK: - ConversionProgress

/// Progress information during conversion
public struct ConversionProgress: Sendable {
    public let id: UUID
    public let percentComplete: Double
    public let currentOperation: String
    public let startTime: Date

    public var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    public init(id: UUID, percentComplete: Double, currentOperation: String, startTime: Date) {
        self.id = id
        self.percentComplete = percentComplete
        self.currentOperation = currentOperation
        self.startTime = startTime
    }
}

// MARK: - ConversionJob

/// Represents an active conversion job
public final class ConversionJob: @unchecked Sendable {
    public let id: UUID
    public let inputURL: URL
    public let outputFormat: String
    public let options: ConversionOptions
    public let startTime: Date

    internal var process: Process?
    internal var isCancelled: Bool = false

    private let lock = NSLock()

    internal init(id: UUID, inputURL: URL, outputFormat: String, options: ConversionOptions) {
        self.id = id
        self.inputURL = inputURL
        self.outputFormat = outputFormat
        self.options = options
        self.startTime = Date()
    }

    internal func cancel() {
        lock.lock()
        defer { lock.unlock() }
        isCancelled = true
        process?.terminate()
    }

    internal var wasCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}

// MARK: - CalibreConversionService

/// Service for converting ebooks using Calibre's ebook-convert CLI
public final class CalibreConversionService: @unchecked Sendable {

    // MARK: - Properties

    /// Shared instance
    public static let shared = CalibreConversionService()

    /// Publisher for conversion progress updates
    public let progressPublisher = PassthroughSubject<ConversionProgress, Never>()

    /// Currently active conversion jobs
    private var activeJobs: [UUID: ConversionJob] = [:]
    private let jobsLock = NSLock()

    /// Path to ebook-convert executable
    private var ebookConvertPath: String?

    /// Path to ebook-meta executable
    private var ebookMetaPath: String?

    /// Supported input formats for conversion
    public static let supportedInputFormats: Set<String> = [
        "epub", "mobi", "azw3", "pdf", "fb2", "lit", "pdb", "txt", "rtf", "docx", "html", "htmlz"
    ]

    /// Supported output formats for conversion
    public static let supportedOutputFormats: Set<String> = [
        "epub", "mobi", "azw3", "pdf"
    ]

    /// Common paths where Calibre might be installed
    private static let calibreSearchPaths: [String] = [
        "/Applications/calibre.app/Contents/MacOS/ebook-convert",
        "/usr/local/bin/ebook-convert",
        "/opt/homebrew/bin/ebook-convert",
        "/usr/bin/ebook-convert"
    ]

    private static let calibreMetaSearchPaths: [String] = [
        "/Applications/calibre.app/Contents/MacOS/ebook-meta",
        "/usr/local/bin/ebook-meta",
        "/opt/homebrew/bin/ebook-meta",
        "/usr/bin/ebook-meta"
    ]

    // MARK: - Initialization

    public init() {
        self.ebookConvertPath = Self.findExecutable(searchPaths: Self.calibreSearchPaths)
        self.ebookMetaPath = Self.findExecutable(searchPaths: Self.calibreMetaSearchPaths)
    }

    // MARK: - Public API

    /// Check if Calibre is available on the system
    public var isCalibreAvailable: Bool {
        ebookConvertPath != nil
    }

    /// Get the path to the ebook-convert executable
    public var calibrePath: String? {
        ebookConvertPath
    }

    /// Refresh the Calibre path search (call if user installs Calibre during session)
    public func refreshCalibrePath() {
        ebookConvertPath = Self.findExecutable(searchPaths: Self.calibreSearchPaths)
        ebookMetaPath = Self.findExecutable(searchPaths: Self.calibreMetaSearchPaths)
    }

    /// Convert an ebook from one format to another
    /// - Parameters:
    ///   - inputURL: Source file URL
    ///   - outputFormat: Target format (epub, mobi, azw3, pdf)
    ///   - options: Conversion options
    /// - Returns: URL of the converted file
    /// - Throws: ConversionError if conversion fails
    public func convert(
        _ inputURL: URL,
        to outputFormat: String,
        options: ConversionOptions = .default
    ) async throws -> URL {
        // Validate Calibre is available
        guard let convertPath = ebookConvertPath else {
            throw ConversionError.calibreNotFound
        }

        // Validate input file exists
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw FolioError.fileNotFound(inputURL)
        }

        // Validate input format
        let inputFormat = inputURL.pathExtension.lowercased()
        guard Self.supportedInputFormats.contains(inputFormat) else {
            throw ConversionError.unsupportedInputFormat(inputFormat)
        }

        // Validate output format
        let normalizedOutputFormat = outputFormat.lowercased()
        guard Self.supportedOutputFormats.contains(normalizedOutputFormat) else {
            throw ConversionError.unsupportedOutputFormat(outputFormat)
        }

        // Create conversion job
        let jobId = UUID()
        let job = ConversionJob(id: jobId, inputURL: inputURL, outputFormat: normalizedOutputFormat, options: options)

        // Register job
        jobsLock.lock()
        activeJobs[jobId] = job
        jobsLock.unlock()

        defer {
            jobsLock.lock()
            activeJobs.removeValue(forKey: jobId)
            jobsLock.unlock()
        }

        // Determine output path
        let outputURL = determineOutputURL(for: inputURL, format: normalizedOutputFormat, options: options)

        // Build arguments
        var arguments = [inputURL.path, outputURL.path]
        arguments.append(contentsOf: buildConversionArguments(options: options, outputFormat: normalizedOutputFormat))

        // Run conversion
        logger.info("Starting conversion: \(inputURL.lastPathComponent) -> \(normalizedOutputFormat)")

        let result = try await runProcess(
            executablePath: convertPath,
            arguments: arguments,
            job: job
        )

        // Check if cancelled
        if job.wasCancelled {
            // Clean up partial output
            try? FileManager.default.removeItem(at: outputURL)
            throw ConversionError.cancelled
        }

        // Check exit code
        if result.exitCode != 0 {
            throw ConversionError.processFailed(exitCode: result.exitCode, stderr: result.stderr)
        }

        // Verify output was created
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ConversionError.processFailed(exitCode: result.exitCode, stderr: "Output file was not created")
        }

        logger.info("Conversion complete: \(outputURL.lastPathComponent)")

        return outputURL
    }

    /// Extract metadata from an ebook file using ebook-meta
    /// - Parameter fileURL: URL of the ebook file
    /// - Returns: BookMetadata extracted from the file
    /// - Throws: ConversionError if metadata extraction fails
    public func getMetadata(from fileURL: URL) async throws -> BookMetadata {
        // Validate ebook-meta is available
        guard let metaPath = ebookMetaPath else {
            throw ConversionError.calibreNotFound
        }

        // Validate file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw FolioError.fileNotFound(fileURL)
        }

        // Run ebook-meta
        let process = Process()
        process.executableURL = URL(fileURLWithPath: metaPath)
        process.arguments = [fileURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                process.terminationHandler = { _ in
                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        continuation.resume(throwing: ConversionError.processFailed(
                            exitCode: process.terminationStatus,
                            stderr: stderr
                        ))
                        return
                    }

                    let metadata = self.parseMetadata(from: stdout, fileURL: fileURL)
                    continuation.resume(returning: metadata)
                }
            } catch {
                continuation.resume(throwing: ConversionError.processFailed(
                    exitCode: -1,
                    stderr: error.localizedDescription
                ))
            }
        }
    }

    /// Cancel an active conversion
    /// - Parameter id: UUID of the conversion job to cancel
    public func cancelConversion(id: UUID) {
        jobsLock.lock()
        let job = activeJobs[id]
        jobsLock.unlock()

        job?.cancel()
        logger.info("Cancelled conversion: \(id)")
    }

    /// Cancel all active conversions
    public func cancelAllConversions() {
        jobsLock.lock()
        let jobs = Array(activeJobs.values)
        jobsLock.unlock()

        for job in jobs {
            job.cancel()
        }
        logger.info("Cancelled all conversions")
    }

    /// Check if a specific conversion job is active
    /// - Parameter id: UUID of the conversion job
    /// - Returns: True if the job is still running
    public func isConversionActive(id: UUID) -> Bool {
        jobsLock.lock()
        defer { jobsLock.unlock() }
        return activeJobs[id] != nil
    }

    /// Get count of active conversions
    public var activeConversionCount: Int {
        jobsLock.lock()
        defer { jobsLock.unlock() }
        return activeJobs.count
    }

    // MARK: - Private Methods

    /// Find an executable in the search paths or user's PATH
    private static func findExecutable(searchPaths: [String]) -> String? {
        let fileManager = FileManager.default

        // Check known paths first
        for path in searchPaths {
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try to find in PATH using 'which'
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [searchPaths.first?.components(separatedBy: "/").last ?? "ebook-convert"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty,
                   fileManager.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {
            // Ignore errors, just return nil
        }

        return nil
    }

    /// Determine the output URL for conversion
    private func determineOutputURL(for inputURL: URL, format: String, options: ConversionOptions) -> URL {
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let outputFilename = "\(filename).\(format)"

        let outputDirectory = options.outputDirectory ?? inputURL.deletingLastPathComponent()
        return outputDirectory.appendingPathComponent(outputFilename)
    }

    /// Build command-line arguments for conversion
    private func buildConversionArguments(options: ConversionOptions, outputFormat: String) -> [String] {
        var args: [String] = []

        // Add profile if specified
        if let profile = options.profile {
            args.append(contentsOf: ["--output-profile", profile])
        }

        // Image quality for PDF/MOBI output
        if outputFormat == "pdf" || outputFormat == "mobi" || outputFormat == "azw3" {
            args.append(contentsOf: ["--jpeg-quality", String(options.quality)])
        }

        // Preserve metadata option
        if options.preserveEmbeddedMetadata {
            args.append("--read-metadata-from-opf")
        }

        // Add any additional arguments
        args.append(contentsOf: options.additionalArguments)

        return args
    }

    /// Run a process and capture output with progress tracking
    private func runProcess(
        executablePath: String,
        arguments: [String],
        job: ConversionJob
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Store process reference for cancellation
            job.process = process

            var stdoutBuffer = ""
            var stderrBuffer = ""

            // Handle stdout for progress parsing
            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                if let output = String(data: data, encoding: .utf8) {
                    stdoutBuffer += output
                    self?.parseProgress(from: output, job: job)
                }
            }

            // Handle stderr
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                if let output = String(data: data, encoding: .utf8) {
                    stderrBuffer += output
                }
            }

            process.terminationHandler = { _ in
                // Clean up handlers
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                // Read any remaining data
                let remainingStdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let remainingStderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if let output = String(data: remainingStdout, encoding: .utf8) {
                    stdoutBuffer += output
                }
                if let output = String(data: remainingStderr, encoding: .utf8) {
                    stderrBuffer += output
                }

                continuation.resume(returning: (
                    exitCode: process.terminationStatus,
                    stdout: stdoutBuffer,
                    stderr: stderrBuffer
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ConversionError.processFailed(
                    exitCode: -1,
                    stderr: error.localizedDescription
                ))
            }
        }
    }

    /// Parse progress from ebook-convert output
    /// Calibre outputs progress like: "23% Converting..."
    private func parseProgress(from output: String, job: ConversionJob) {
        // Match patterns like "23%" or "23% Converting..."
        let pattern = #"(\d{1,3})%\s*(.*?)(?:\n|$)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return
        }

        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, options: [], range: range)

        for match in matches {
            if let percentRange = Range(match.range(at: 1), in: output),
               let percent = Double(output[percentRange]) {

                var operation = ""
                if let operationRange = Range(match.range(at: 2), in: output) {
                    operation = String(output[operationRange]).trimmingCharacters(in: .whitespaces)
                }

                let progress = ConversionProgress(
                    id: job.id,
                    percentComplete: min(100, max(0, percent)),
                    currentOperation: operation.isEmpty ? "Converting..." : operation,
                    startTime: job.startTime
                )

                progressPublisher.send(progress)
            }
        }
    }

    /// Parse metadata from ebook-meta output
    private func parseMetadata(from output: String, fileURL: URL) -> BookMetadata {
        var title = fileURL.deletingPathExtension().lastPathComponent
        var authors: [String] = []
        var publisher: String?
        var publishedDate: Date?
        var language: String?
        var tags: [String] = []
        var series: String?
        var seriesIndex: Double?
        var isbn: String?

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)

                guard !value.isEmpty else { continue }

                switch key {
                case "title":
                    title = value

                case "author(s)", "authors", "author":
                    // Authors may be separated by " & " or ", "
                    authors = value
                        .components(separatedBy: "&")
                        .flatMap { $0.components(separatedBy: ",") }
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                case "publisher":
                    publisher = value

                case "published", "publication date", "pubdate":
                    // Try common date formats
                    let dateFormatters = [
                        "yyyy-MM-dd",
                        "yyyy",
                        "MMM dd, yyyy",
                        "MMMM dd, yyyy"
                    ].map { format -> DateFormatter in
                        let formatter = DateFormatter()
                        formatter.dateFormat = format
                        formatter.locale = Locale(identifier: "en_US_POSIX")
                        return formatter
                    }

                    for formatter in dateFormatters {
                        if let date = formatter.date(from: value) {
                            publishedDate = date
                            break
                        }
                    }

                case "language", "languages":
                    language = value

                case "tags", "subjects", "subject":
                    tags = value
                        .components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }

                case "series":
                    // Format might be "Series Name [5]" or just "Series Name"
                    if let bracketRange = value.range(of: #"\[(\d+(?:\.\d+)?)\]"#, options: .regularExpression) {
                        series = String(value[..<bracketRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let indexString = value[bracketRange].dropFirst().dropLast()
                        seriesIndex = Double(indexString)
                    } else {
                        series = value
                    }

                case "series index", "series_index":
                    seriesIndex = Double(value)

                case "isbn":
                    isbn = value.replacingOccurrences(of: "-", with: "")

                default:
                    break
                }
            }
        }

        // Determine ISBN type
        var isbn10: String?
        var isbn13: String?
        if let isbnValue = isbn {
            if isbnValue.count == 13 {
                isbn13 = isbnValue
            } else if isbnValue.count == 10 {
                isbn10 = isbnValue
            }
        }

        return BookMetadata(
            title: title,
            authors: authors,
            isbn: isbn10,
            isbn13: isbn13,
            publisher: publisher,
            publishedDate: publishedDate,
            language: language,
            series: series,
            seriesIndex: seriesIndex,
            tags: tags,
            confidence: 0.8,
            source: "calibre"
        )
    }
}
