//
//  ImportScalingPerfTests.swift
//  FolioPerformanceTests
//
//  Measures import throughput and its scaling curve (audit findings #43, #80, #42).
//
//  ImportService.importBooks is serial, @MainActor, and sleeps
//  `Task.sleep(10ms)` after every file. BookRepository.add saves the view
//  context AND calls refreshAllObjects() per file, and importSingleFile calls
//  findDuplicate (full-table scan) per file. This test drives batches of
//  50 / 200 / 1000 real placeholder files and also isolates:
//    - the raw repository add path (no sleep, no dup check)
//    - the fixed 10 ms/file sleep overhead
//    - the effect of a pre-populated library on per-file time (O(N×M) dup scan)
//
//  There is no stated budget for a bulk import; requirements.md only sets a
//  library-load budget. The regressions here are the SHAPE of the curve
//  (super-linear) and the unavoidable sleep floor.
//

import CoreData
import XCTest
@testable import Folio

final class ImportScalingPerfTests: PerfTestCase {

    // MARK: - Full ImportService path (dup check + save + refresh + 10ms sleep)

    @MainActor
    private func runImportService(fileCount: Int, prePopulate: Int) async {
        let (_, ctx) = PerfFixture.makeInMemoryContext()
        if prePopulate > 0 { _ = PerfFixture.populate(ctx, count: prePopulate) }
        let repo = BookRepository(context: ctx)
        let service = ImportService(repository: repo, parser: FilenameParser())

        let dir = PerfFixture.makePlaceholderFiles(count: fileCount)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(urls.count, fileCount)

        let clock = ContinuousClock()
        let start = clock.now
        let result = await service.importBooks(from: urls)
        let ms = PerfClock.ms(clock.now - start)
        XCTAssertEqual(result.imported, fileCount, "all placeholder files should import")

        let sleepFloor = Double(fileCount) * 10.0
        PerfLog.shared.record(
            scenario: "ImportService.importBooks (library has \(prePopulate) books)",
            metric: "\(fileCount) files — wall time",
            value: ms, unit: "ms",
            budget: "no explicit budget",
            verdict: "INFORMATIONAL",
            note: String(format: "%.2f ms/file; fixed sleep floor ≈ %.0f ms (%.0f%% of total)",
                         ms / Double(fileCount), sleepFloor, 100.0 * sleepFloor / ms)
        )
    }

    func test_import_50_emptyLibrary()   async { await runImportService(fileCount: 50,   prePopulate: 0) }
    func test_import_200_emptyLibrary()  async { await runImportService(fileCount: 200,  prePopulate: 0) }
    func test_import_1000_emptyLibrary() async { await runImportService(fileCount: 1000, prePopulate: 0) }

    /// Same 200-file import, but into a library that already holds 5,000 books —
    /// every file's findDuplicate() now scans 5,000 rows.
    func test_import_200_into5000Library() async { await runImportService(fileCount: 200, prePopulate: 5000) }

    // MARK: - Raw repository add path (isolates save + refreshAllObjects, no sleep)

    @MainActor
    private func runRepoAddOnly(fileCount: Int) {
        let (_, ctx) = PerfFixture.makeInMemoryContext()
        let repo = BookRepository(context: ctx)
        let dir = PerfFixture.makePlaceholderFiles(count: fileCount, seed: 0xADD)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []).sorted { $0.path < $1.path }

        let parser = FilenameParser()
        var added = 0
        let ms = PerfClock.timeMS {
            for url in urls {
                let parsed = parser.parse(url.lastPathComponent)
                let sortTitle = repo.generateSortTitle(parsed.title)
                if (try? repo.add(from: url, title: parsed.title, sortTitle: sortTitle, authorName: parsed.author)) != nil {
                    added += 1
                }
            }
        }
        XCTAssertEqual(added, fileCount)
        PerfLog.shared.record(
            scenario: "BookRepository.add loop (no sleep, no dup check)",
            metric: "\(fileCount) files — wall time",
            value: ms, unit: "ms",
            budget: "—", verdict: "INFORMATIONAL",
            note: String(format: "%.2f ms/file; per-file save() + refreshAllObjects()", ms / Double(fileCount))
        )
    }

    @MainActor func test_repoAdd_50()   { runRepoAddOnly(fileCount: 50) }
    @MainActor func test_repoAdd_200()  { runRepoAddOnly(fileCount: 200) }
    @MainActor func test_repoAdd_1000() { runRepoAddOnly(fileCount: 1000) }
}
