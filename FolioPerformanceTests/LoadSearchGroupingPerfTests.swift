//
//  LoadSearchGroupingPerfTests.swift
//  FolioPerformanceTests
//
//  Measures the main-thread library-load, grouping and search paths at N = 5,000.
//
//  Budgets (docs/requirements.md):
//    - Library load: < 2,000 ms for 5,000 books
//    - Search response: < 100 ms
//
//  Covered here:
//    1. fetchAll() + BookGroupingService.groupBooks()          (P1 grouping/sort)
//    2. SearchService.search()                                  (P2 search service)
//    3. ContentView's inline title/author filter + sortBooks()  (P1 per-keystroke)
//
//  (3) is a faithful transcription of Folio/ContentView.swift `displayedBooks`
//  (lines ~81–142) and `sortBooks` (lines ~150–180); `displayedBooks` is a
//  `var` on a `View` and cannot be called from a test, so the closure body is
//  copied here. If ContentView changes, this copy must be updated.
//

import CoreData
import XCTest
@testable import Folio

final class LoadSearchGroupingPerfTests: PerfTestCase {

    private static let N = 5_000

    @MainActor
    private func loadedBooks() -> (BookRepository, [Book]) {
        let (_, ctx) = PerfFixture.makeInMemoryContext()
        _ = PerfFixture.populate(ctx, count: Self.N)
        let repo = BookRepository(context: ctx)
        let books = (try? repo.fetchAll()) ?? []
        XCTAssertEqual(books.count, Self.N)
        return (repo, books)
    }

    // MARK: - 1. Library load: fetch + group

    @MainActor
    func test_fetchAll_plus_groupBooks_N5000() {
        let (_, ctx) = PerfFixture.makeInMemoryContext()
        _ = PerfFixture.populate(ctx, count: Self.N)
        let repo = BookRepository(context: ctx)

        // Cold: fetch from the store then group (what a library open pays).
        var groups: [BookGroup] = []
        let coldMS = PerfClock.timeMS {
            let books = (try? repo.fetchAll()) ?? []
            groups = BookGroupingService.groupBooks(books)
        }
        XCTAssertGreaterThan(groups.count, 0)
        _ = groups.map { $0.primaryBook.title }   // force primaryBook eval like the grid does

        PerfLog.shared.record(
            scenario: "library load N=5000",
            metric: "fetchAll() + groupBooks() + primaryBook eval (cold)",
            value: coldMS,
            unit: "ms",
            budget: "< 2000 ms",
            verdict: coldMS < 2_000 ? "PASS" : "FAIL",
            note: "\(groups.count) groups; main-thread"
        )

        // Warm re-group only (what every SwiftUI body re-eval pays: displayedBookGroups).
        let warmBooks = (try? repo.fetchAll()) ?? []
        let regroupMS = PerfClock.medianMS(runs: 7, warmup: 2) {
            let g = BookGroupingService.groupBooks(warmBooks)
            _ = g.map { $0.primaryBook.objectID }
        }
        PerfLog.shared.record(
            scenario: "library load N=5000",
            metric: "groupBooks() + primaryBook re-eval (warm, per body pass)",
            value: regroupMS,
            unit: "ms",
            budget: "< 100 ms (runs on every view update)",
            verdict: regroupMS < 100 ? "PASS" : "FAIL",
            note: "recomputed every render; no memoisation (#P1)"
        )
    }

    // MARK: - 2. SearchService.search()

    @MainActor
    func test_SearchService_search_N5000() {
        let (_, books) = loadedBooks()
        let svc = SearchService()
        let queries = ["silent", "garden", "okafor", "the", "meridian", "979", "zzznomatch"]

        var worst = 0.0
        for q in queries {
            var hits = 0
            let m = PerfClock.medianMS(runs: 7, warmup: 2) {
                hits = svc.search(books: books, query: q).count
            }
            worst = max(worst, m)
            PerfLog.shared.record(
                scenario: "SearchService.search N=5000",
                metric: "query \"\(q)\" (\(hits) hits, median of 7)",
                value: m,
                unit: "ms",
                budget: "< 100 ms",
                verdict: m < 100 ? "PASS" : "FAIL",
                note: "in-memory filter; walks authors/isbn/series per book"
            )
        }
        PerfLog.shared.record(
            scenario: "SearchService.search N=5000",
            metric: "worst query in set",
            value: worst, unit: "ms", budget: "< 100 ms",
            verdict: worst < 100 ? "PASS" : "FAIL",
            note: "SearchService is invoked programmatically; ContentView uses its own copy"
        )
    }

    // MARK: - 3. ContentView inline filter + sort (per keystroke)

    @MainActor
    func test_ContentView_inlineFilter_and_sort_N5000() {
        let (_, books) = loadedBooks()

        // --- transcription of ContentView.displayedBooks search block ---
        func inlineFilter(_ input: [Book], query rawQuery: String) -> [Book] {
            guard !rawQuery.isEmpty else { return input }
            let query = rawQuery.lowercased()
            return input.filter { book in
                if book.title?.lowercased().contains(query) == true { return true }
                if let authors = book.authors as? Set<Author> {
                    for author in authors where author.name?.lowercased().contains(query) == true {
                        return true
                    }
                }
                return false
            }
        }
        // --- transcription of ContentView.sortBooks(.author) (relationship traversal) ---
        func sortByAuthor(_ input: [Book]) -> [Book] {
            input.sorted {
                let a1 = ($0.authors as? Set<Author>)?.first?.sortName ?? ""
                let a2 = ($1.authors as? Set<Author>)?.first?.sortName ?? ""
                return a1 < a2
            }
        }

        // Simulate typing a 7-char query one character at a time — each keystroke
        // re-runs the whole filter+sort+group pipeline over Array(books).
        let target = "meridian"
        var perKeystroke: [Double] = []
        for len in 1...target.count {
            let q = String(target.prefix(len))
            let m = PerfClock.medianMS(runs: 5, warmup: 1) {
                let filtered = inlineFilter(books, query: q)
                let sorted = sortByAuthor(filtered)
                _ = BookGroupingService.groupBooks(sorted)
            }
            perKeystroke.append(m)
            PerfLog.shared.record(
                scenario: "ContentView keystroke N=5000",
                metric: "filter+sort(author)+group for \"\(q)\"",
                value: m, unit: "ms", budget: "< 100 ms",
                verdict: m < 100 ? "PASS" : "FAIL",
                note: "full pipeline per keystroke; Array(books) rebuilt each time"
            )
        }
        let worst = perKeystroke.max() ?? 0
        PerfLog.shared.record(
            scenario: "ContentView keystroke N=5000",
            metric: "worst single keystroke",
            value: worst, unit: "ms", budget: "< 100 ms",
            verdict: worst < 100 ? "PASS" : "FAIL",
            note: "no debounce (#P1/#P2)"
        )

        // Pure filter cost alone, no sort/group, for reference.
        let filterOnly = PerfClock.medianMS(runs: 7, warmup: 2) { _ = inlineFilter(books, query: "silent") }
        PerfLog.shared.record(
            scenario: "ContentView keystroke N=5000",
            metric: "inline filter only, query \"silent\"",
            value: filterOnly, unit: "ms", budget: "< 100 ms",
            verdict: filterOnly < 100 ? "PASS" : "FAIL",
            note: "isolates the filter from sort+group"
        )
    }
}
