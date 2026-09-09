//
//  FindDuplicatePerfTests.swift
//  FolioPerformanceTests
//
//  Measures BookRepository.findDuplicate (audit finding #42).
//
//  findDuplicate fetches the FULL Book table (`viewContext.fetch(filenameRequest)`
//  with no predicate) and then runs a Swift `.first(where:)` linear scan for every
//  candidate file. Import calls it once per file, so a run of M imported files over
//  a library of N books is O(N × M). These tests fix M and vary N to expose the
//  per-call cost that gets multiplied.
//

import CoreData
import XCTest
@testable import Folio

final class FindDuplicatePerfTests: PerfTestCase {

    /// 200 lookups (≈50% hits, ≈50% misses) against a library of `n` books.
    @MainActor
    private func runFindDuplicate(n: Int) {
        let (_, ctx) = PerfFixture.makeInMemoryContext()
        let fixture = PerfFixture.populate(ctx, count: n)
        let repo = BookRepository(context: ctx)

        // Build a deterministic query set: half point at real rows, half are novel.
        let all = (try? repo.fetchAll()) ?? []
        XCTAssertEqual(all.count, n, "fixture should have materialised \(n) books")

        var rng = SplitMix64(seed: 0x51DE)
        struct Q { let filename: String; let title: String; let author: String? }
        var queries: [Q] = []
        for i in 0..<200 {
            if i % 2 == 0, !all.isEmpty {
                let b = all[Int(rng.next() % UInt64(all.count))]
                queries.append(Q(filename: b.fileURL?.lastPathComponent ?? "x.epub",
                                 title: b.title ?? "x",
                                 author: (b.authors as? Set<Author>)?.first?.name))
            } else {
                queries.append(Q(filename: "no-such-file-\(i)-\(rng.next()).epub",
                                 title: "Nonexistent Title \(i) \(rng.next())",
                                 author: "Ghost Writer \(i)"))
            }
        }

        var sink = 0
        let perBatchMS = PerfClock.medianMS(runs: 5, warmup: 1) {
            for q in queries {
                if repo.findDuplicate(filename: q.filename, title: q.title, author: q.author) != nil {
                    sink += 1
                }
            }
        }
        XCTAssertGreaterThan(sink, 0)

        let perCall = perBatchMS / 200.0
        PerfLog.shared.record(
            scenario: "findDuplicate N=\(n)",
            metric: "per lookup (median of 5, 200 lookups/batch)",
            value: perCall,
            unit: "ms",
            budget: "no explicit budget; multiplied by files-per-import",
            verdict: "INFORMATIONAL",
            note: "full-table fetch + linear scan per call (#42); import cost ≈ perCall × N_files"
        )
        PerfLog.shared.record(
            scenario: "findDuplicate N=\(n)",
            metric: "projected cost for a 1,000-file import",
            value: perCall * 1_000.0,
            unit: "ms",
            budget: "—",
            verdict: "INFORMATIONAL",
            note: "O(N×M): 1000 files each scanning \(n) rows"
        )
    }

    @MainActor func test_findDuplicate_N1000() { runFindDuplicate(n: 1_000) }
    @MainActor func test_findDuplicate_N5000() { runFindDuplicate(n: 5_000) }
}
