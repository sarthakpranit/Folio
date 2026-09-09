//
//  ImportScalingPerfTests.swift
//  FolioPerformanceTests
//
//  Measures import throughput and its scaling curve (audit findings #43, #80, #42).
//
//  Since #43, ImportService.importBooks parses + resolves duplicates on the
//  main-queue viewContext, then inserts on a background context saved one chunk
//  at a time (no per-file `Task.sleep`, no per-file `refreshAllObjects()`).
//  `importSingleFile`'s per-file `findDuplicate` (full-table scan) still runs on
//  the main thread. This test drives batches of 50 / 200 / 1000 real placeholder
//  files and also isolates:
//    - the raw repository add path (single-book path: per-file save, no dup check)
//    - the effect of a pre-populated library on per-file time (O(N×M) dup scan)
//
//  There is no stated budget for a bulk import; requirements.md only sets a
//  library-load budget. The regression to watch here is the SHAPE of the curve
//  (super-linear in a pre-populated library, from the main-thread dup scan).
//

import CoreData
import XCTest
@testable import Folio

final class ImportScalingPerfTests: PerfTestCase {

    // MARK: - Full ImportService path (main-thread dup check + batched background insert)

    @MainActor
    private func runImportService(fileCount: Int, prePopulate: Int) async {
        let (container, ctx) = PerfFixture.makeInMemoryContext()
        if prePopulate > 0 { _ = PerfFixture.populate(ctx, count: prePopulate) }
        let repo = BookRepository(context: ctx)
        let service = ImportService(repository: repo, parser: FilenameParser(), container: container)

        let dir = PerfFixture.makePlaceholderFiles(count: fileCount)
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        XCTAssertEqual(urls.count, fileCount)

        let clock = ContinuousClock()
        let start = clock.now
        let result = await service.importBooks(from: urls)
        let ms = PerfClock.ms(clock.now - start)
        XCTAssertEqual(result.imported, fileCount, "all placeholder files should import")

        PerfLog.shared.record(
            scenario: "ImportService.importBooks (library has \(prePopulate) books)",
            metric: "\(fileCount) files — wall time",
            value: ms, unit: "ms",
            budget: "no explicit budget",
            verdict: "INFORMATIONAL",
            note: String(format: "%.2f ms/file (background-context insert, one save per 25-file chunk)",
                         ms / Double(fileCount))
        )
    }

    func test_import_50_emptyLibrary()   async { await runImportService(fileCount: 50,   prePopulate: 0) }
    func test_import_200_emptyLibrary()  async { await runImportService(fileCount: 200,  prePopulate: 0) }
    func test_import_1000_emptyLibrary() async { await runImportService(fileCount: 1000, prePopulate: 0) }

    /// Same 200-file import, but into a library that already holds 5,000 books —
    /// every file's findDuplicate() now scans 5,000 rows.
    func test_import_200_into5000Library() async { await runImportService(fileCount: 200, prePopulate: 5000) }

    // MARK: - Raw repository add path (single-book path: isolates the per-file save)

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
            note: String(format: "%.2f ms/file; per-file viewContext.save()", ms / Double(fileCount))
        )
    }

    @MainActor func test_repoAdd_50()   { runRepoAddOnly(fileCount: 50) }
    @MainActor func test_repoAdd_200()  { runRepoAddOnly(fileCount: 200) }
    @MainActor func test_repoAdd_1000() { runRepoAddOnly(fileCount: 1000) }
}
