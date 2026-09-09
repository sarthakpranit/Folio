//
//  CoverDecodePerfTests.swift
//  FolioPerformanceTests
//
//  Measures cover-blob storage weight and decode cost (audit finding #67,
//  hotspot-map "P0 — Cover image memory and decoding").
//
//  Covers are persisted as full-size image blobs on Book.coverImageData and
//  decoded to NSImage while a grid cell renders (BookGroupViews.swift:60–62,
//  1206–1207) with `NSImage(data:)` and no cache. This test:
//    - generates M realistic JPEG covers (~1400×2100)
//    - stores them on Book rows and reports total bytes (→ 5k projection, #67)
//    - measures decoding all M via NSImage(data:) (what a fast scroll pays)
//

import AppKit
import CoreData
import XCTest
@testable import Folio

final class CoverDecodePerfTests: PerfTestCase {

    /// A deterministic ~1200×1800 JPEG that encodes to a realistic book-cover
    /// size (~40–140 KB): a smooth two-stop diagonal gradient plus a per-cover
    /// title band and a little low-amplitude noise so it doesn't collapse to
    /// nothing. This matches what Folio actually stores — an undownsampled
    /// network JPEG on Book.coverImageData (#67).
    private static func makeCoverJPEG(seed: UInt64) -> Data {
        var rng = SplitMix64(seed: seed)
        let w = 1200, h = 1800
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                   bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: w * 3, bitsPerPixel: 24)!
        let ptr = rep.bitmapData!
        let r0 = Int(rng.next() & 0x7F), g0 = Int(rng.next() & 0x7F), b0 = 0x40 + Int(rng.next() & 0x3F)
        let bandTop = h * 3 / 5, bandBot = h * 3 / 5 + h / 8
        for y in 0..<h {
            let ny = (y * 160) / h
            for x in 0..<w {
                let i = y * w * 3 + x * 3
                let nx = (x * 96) / w
                let n = Int(rng.next() & 0x03)
                let inBand = (y >= bandTop && y < bandBot)
                ptr[i]     = UInt8(clamping: (inBand ? 235 : r0 + nx + n))
                ptr[i + 1] = UInt8(clamping: (inBand ? 232 : g0 + ny + n))
                ptr[i + 2] = UInt8(clamping: (inBand ? 225 : b0 + ((nx + ny) >> 1) + n))
            }
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])!
    }

    @MainActor
    private func run(coverCount m: Int) {
        let (_, ctx) = PerfFixture.makeInMemoryContext()

        // A pool of distinct covers, cycled — generating a unique 1200×1800 JPEG
        // per row is prohibitively slow and adds no signal once there is enough
        // variety that NSImage(data:) can't shortcut the decode.
        let poolSize = min(m, 60)
        var pool: [Data] = []
        pool.reserveCapacity(poolSize)
        let genMS = PerfClock.timeMS {
            for i in 0..<poolSize { pool.append(Self.makeCoverJPEG(seed: UInt64(i) &* 0x9E37 &+ 1)) }
        }
        let blobs: [Data] = (0..<m).map { pool[$0 % poolSize] }
        let totalBytes = blobs.reduce(0) { $0 + $1.count }
        let avgKB = Double(totalBytes) / Double(m) / 1024.0

        for (i, b) in blobs.enumerated() {
            let book = Book(context: ctx)
            book.id = UUID()
            book.title = "Cover \(i)"
            book.coverImageData = b
        }
        try? ctx.save()

        PerfLog.shared.record(
            scenario: "cover blobs M=\(m)",
            metric: "avg encoded cover size",
            value: avgKB, unit: "KB", budget: "—", verdict: "INFORMATIONAL",
            note: String(format: "%d-cover pool gen took %.0f ms; total stored ≈ %.1f MB", poolSize, genMS, Double(totalBytes) / 1_048_576.0)
        )
        PerfLog.shared.record(
            scenario: "cover blobs M=\(m)",
            metric: "projected coverImageData weight at 5,000 books",
            value: avgKB * 5_000.0 / 1_024.0, unit: "MB", budget: "—", verdict: "INFORMATIONAL",
            note: "every cover held as a full-size blob in the store (#67)"
        )

        let books = (try? ctx.fetch(Book.fetchRequest())) ?? []
        XCTAssertEqual(books.count, m)

        // (a) What BookGroupViews.swift:61 literally does — NSImage(data:).
        //     NSImage defers pixel decode to first draw, so this measures object
        //     construction + header parse only.
        var made = 0
        let makeMS = PerfClock.medianMS(runs: 3, warmup: 1) {
            made = 0
            for book in books where book.coverImageData.flatMap({ NSImage(data: $0) }) != nil { made += 1 }
        }
        XCTAssertEqual(made, m)
        PerfLog.shared.record(
            scenario: "cover decode M=\(m)",
            metric: "NSImage(data:) construction for all \(m) (median of 3)",
            value: makeMS, unit: "ms",
            budget: "60 fps ⇒ < 16 ms per frame of on-screen covers",
            verdict: "INFORMATIONAL",
            note: String(format: "%.3f ms/cover; header parse only, pixels decoded later at draw", makeMS / Double(m))
        )

        // (b) Forced full rasterisation — the cost SwiftUI actually pays when the
        //     grid renders each cover (via CGImageForProposedRect).
        var rasterised = 0
        let rasterMS = PerfClock.medianMS(runs: 3, warmup: 1) {
            rasterised = 0
            for book in books {
                guard let d = book.coverImageData, let img = NSImage(data: d) else { continue }
                var rect = CGRect(origin: .zero, size: img.size)
                if img.cgImage(forProposedRect: &rect, context: nil, hints: nil) != nil { rasterised += 1 }
            }
        }
        XCTAssertEqual(rasterised, m)
        PerfLog.shared.record(
            scenario: "cover decode M=\(m)",
            metric: "forced rasterisation of all \(m) covers (median of 3)",
            value: rasterMS, unit: "ms",
            budget: "60 fps ⇒ < 16 ms per frame of on-screen covers",
            verdict: "INFORMATIONAL",
            note: String(format: "%.2f ms/cover full decode; no downsample, no cache (#67)", rasterMS / Double(m))
        )
    }

    @MainActor func test_coverDecode_M100() { run(coverCount: 100) }
    @MainActor func test_coverDecode_M500() { run(coverCount: 500) }
}
