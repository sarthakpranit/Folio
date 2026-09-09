//
//  PerfSupport.swift
//  FolioPerformanceTests
//
//  Throwaway measurement harness for Wayfinder ticket R9 (issue #38).
//  This target is NOT part of the `Folio` scheme and does not run with the
//  normal test suites. Run it explicitly:
//
//    DEVELOPER_DIR=... xcodebuild -scheme FolioPerformanceTests \
//        -destination 'platform=macOS' -derivedDataPath <scratch> test
//
//  It exists only to record a performance baseline against the budgets in
//  docs/requirements.md / docs/performance-hotspot-map.md. It measures the
//  real app code (via `@testable import Folio`) on a deterministic, seeded
//  in-memory Core Data fixture. Nothing here is production code and nothing
//  here is meant to be optimised — see docs/performance-baseline.md.
//

import CoreData
import XCTest
@testable import Folio

// MARK: - Deterministic RNG

/// SplitMix64 — a tiny, fully deterministic PRNG so fixture runs are comparable.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Timing helpers

enum PerfClock {
    /// Milliseconds for a `Duration`.
    static func ms(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1_000.0 + Double(c.attoseconds) / 1_000_000_000_000_000.0
    }

    /// Run `body` `warmup` times (untimed) then `runs` times, returning the median wall time.
    @discardableResult
    static func medianMS(runs: Int = 5, warmup: Int = 1, _ body: () throws -> Void) rethrows -> Double {
        for _ in 0..<max(0, warmup) { try body() }
        var samples: [Double] = []
        let clock = ContinuousClock()
        for _ in 0..<max(1, runs) {
            let d = try clock.measure { try body() }
            samples.append(ms(d))
        }
        samples.sort()
        return samples[samples.count / 2]
    }

    static func timeMS(_ body: () throws -> Void) rethrows -> Double {
        let clock = ContinuousClock()
        return ms(try clock.measure { try body() })
    }
}

// MARK: - Result logging

/// Collects one row per measurement and prints a machine-readable table at the
/// end of the run so the numbers can be transcribed into the baseline doc.
final class PerfLog {
    struct Row {
        let scenario: String
        let metric: String
        let value: Double
        let unit: String
        let budget: String
        let verdict: String
        let note: String
    }

    static let shared = PerfLog()
    private(set) var rows: [Row] = []
    private let lock = NSLock()

    func record(scenario: String,
                metric: String,
                value: Double,
                unit: String = "ms",
                budget: String = "—",
                verdict: String = "—",
                note: String = "") {
        let row = Row(scenario: scenario, metric: metric, value: value,
                      unit: unit, budget: budget, verdict: verdict, note: note)
        lock.lock(); rows.append(row); lock.unlock()
        let v = String(format: "%.3f", value)
        print("PERF-ROW\t\(scenario)\t\(metric)\t\(v)\t\(unit)\t\(budget)\t\(verdict)\t\(note)")
    }

    func dump() {
        lock.lock(); let all = rows; lock.unlock()
        guard !all.isEmpty else { return }
        print("\n===== FOLIO PERF BASELINE — RESULTS =====")
        print("scenario | metric | value | unit | budget | verdict | note")
        for r in all {
            let v = String(format: "%.3f", r.value)
            print("\(r.scenario) | \(r.metric) | \(v) | \(r.unit) | \(r.budget) | \(r.verdict) | \(r.note)")
        }
        print("===== END RESULTS =====\n")
    }
}

/// Base class: builds the results table and prints it once after the whole run.
class PerfTestCase: XCTestCase {
    override class func tearDown() {
        PerfLog.shared.dump()
        super.tearDown()
    }
}

// MARK: - Deterministic fixture generator

enum PerfFixture {

    // Small word pools — enough variety for realistic grouping / sort / search
    // behaviour without pulling in a data file.
    static let adjectives = ["Silent", "Broken", "Golden", "Hidden", "Last", "First", "Distant",
                             "Frozen", "Crimson", "Hollow", "Burning", "Quiet", "Restless",
                             "Ancient", "Electric", "Salt", "Iron", "Glass", "Winter", "Summer"]
    static let nouns = ["Garden", "Empire", "Machine", "River", "Harbor", "Signal", "Orchard",
                        "Cathedral", "Circuit", "Meridian", "Archive", "Lantern", "Compass",
                        "Continent", "Foundry", "Almanac", "Observatory", "Threshold", "Aviary", "Ledger"]
    static let firstNames = ["Ada", "Marcus", "Priya", "Neil", "Ingrid", "Tomas", "Yuki",
                             "Rosa", "Dmitri", "Fatima", "Lars", "Chen", "Amara", "Owen", "Sofia"]
    static let lastNames = ["Okafor", "Lindqvist", "Nakamura", "Fernandez", "Bauer", "Petrova",
                            "Costa", "Haddad", "Sørensen", "Kowalski", "Reyes", "Novak",
                            "Abbott", "Delacroix", "Mbeki", "Rossi", "Thornton", "Vance", "Ito", "Bright"]
    static let seriesNames = ["The Meridian Cycle", "Foundry Chronicles", "Salt & Signal",
                              "The Archive Sequence", "Continental Drift", "Lantern Keepers",
                              "The Hollow Years", "Compass Rose", "Iron Almanac", "Winterlight"]
    static let tagPool = ["fiction", "sci-fi", "history", "reference", "biography", "essays",
                          "fantasy", "thriller", "poetry", "science", "travel", "unread"]
    static let formats = ["epub", "mobi", "pdf", "azw3", "cbz"]

    struct Result {
        let books: Int
        let authors: Int
        let series: Int
        let tags: Int
        let withISBN: Int
        let sharedISBNGroups: Int
        let elapsedMS: Double
    }

    /// Populate `context` with `count` deterministic Book rows plus a realistic
    /// spread of Author / Series / Tag relationships.
    ///
    /// - `sharedISBNRatio`: fraction of books that draw an ISBN from a small
    ///   shared pool (so 2–4 books collide) — exercises `BookGroupingService`.
    /// - `withCovers` / `coverBytes`: attach a synthetic cover blob of the given
    ///   size to every Nth book (`coverEveryN`) to exercise the #67 blob path.
    @discardableResult
    @MainActor
    static func populate(_ context: NSManagedObjectContext,
                         count: Int,
                         seed: UInt64 = 0xF0_11_0_BA_5E,
                         sharedISBNRatio: Double = 0.15,
                         uniqueISBNRatio: Double = 0.45,
                         withCovers: Bool = false,
                         coverBytes: Int = 400_000,
                         coverEveryN: Int = 1) -> Result {
        var rng = SplitMix64(seed: seed)
        let started = ContinuousClock().now

        func pick<T>(_ arr: [T]) -> T { arr[Int(rng.next() % UInt64(arr.count))] }
        func chance(_ p: Double) -> Bool { Double(rng.next() % 10_000) / 10_000.0 < p }

        // Pre-create relationship entities so we exercise findOrCreate-style reuse
        // without paying a fetch per book inside the loop.
        var authors: [Author] = []
        for f in firstNames {
            for l in lastNames {
                let a = Author(context: context)
                a.id = UUID()
                a.name = "\(f) \(l)"
                a.sortName = "\(l), \(f)"
                authors.append(a)
            }
        }
        var seriesList: [Series] = []
        for name in seriesNames {
            let s = Series(context: context)
            s.id = UUID()
            s.name = name
            seriesList.append(s)
        }
        var tags: [Tag] = []
        for name in tagPool {
            let t = Tag(context: context)
            t.id = UUID()
            t.name = name
            tags.append(t)
        }

        let sharedISBNPool: [String] = (0..<max(1, Int(Double(count) * sharedISBNRatio / 3.0))).map {
            String(format: "978%010d", 1_000_000 + $0)
        }

        var withISBN = 0
        var uniqueCounter = 5_000_000
        let coverBlob = withCovers ? Data(repeating: 0xAB, count: coverBytes) : nil

        for i in 0..<count {
            let book = Book(context: context)
            book.id = UUID()

            let adj = pick(adjectives)
            let noun = pick(nouns)
            // ~12% of titles deliberately collide (adj+noun with no numeral) so the
            // title-based grouping / duplicate paths get real work.
            let title = chance(0.12) ? "\(adj) \(noun)" : "\(adj) \(noun) \(Int(rng.next() % 90) + 1)"
            book.title = title
            book.sortTitle = sortTitle(for: title)

            let fmt = formats[i % formats.count]
            book.format = fmt
            book.fileSize = Int64(rng.next() % 4_000_000) + 40_000
            book.dateAdded = Date(timeIntervalSince1970: 1_600_000_000 + Double(i) * 1_800)
            book.dateModified = book.dateAdded
            let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            book.fileURL = URL(fileURLWithPath: "/tmp/folio-fixture/\(slug)-\(i).\(fmt)")
            // Mirror BookRepository.add: the v2 indexed dedup key (#42).
            book.fileName = book.fileURL?.lastPathComponent.lowercased()

            if chance(sharedISBNRatio) {
                book.isbn13 = sharedISBNPool[Int(rng.next() % UInt64(sharedISBNPool.count))]
                withISBN += 1
            } else if chance(uniqueISBNRatio / (1.0 - sharedISBNRatio)) {
                uniqueCounter += 1
                book.isbn13 = String(format: "979%010d", uniqueCounter)
                withISBN += 1
            }

            // 1–2 authors
            book.addToAuthors(authors[Int(rng.next() % UInt64(authors.count))])
            if chance(0.35) {
                book.addToAuthors(authors[Int(rng.next() % UInt64(authors.count))])
            }

            // ~30% in a series
            if chance(0.30) {
                book.series = seriesList[Int(rng.next() % UInt64(seriesList.count))]
                book.seriesIndex = Double(rng.next() % 9) + 1
            }

            // 1–3 tags
            let tagCount = 1 + Int(rng.next() % 3)
            for _ in 0..<tagCount {
                book.addToTags(tags[Int(rng.next() % UInt64(tags.count))])
            }

            if chance(0.55) {
                book.summary = "\(adj) \(noun): a deterministic fixture summary generated for perf run \(i)."
            }
            if chance(0.4) { book.publisher = pick(lastNames) + " Press" }
            book.pageCount = Int32(rng.next() % 900) + 20

            if let blob = coverBlob, i % max(1, coverEveryN) == 0 {
                book.coverImageData = blob
            }

            if i % 500 == 499 { try? context.save() }
        }
        try? context.save()

        let elapsed = PerfClock.ms(ContinuousClock().now - started)
        return Result(books: count,
                      authors: authors.count,
                      series: seriesList.count,
                      tags: tags.count,
                      withISBN: withISBN,
                      sharedISBNGroups: sharedISBNPool.count,
                      elapsedMS: elapsed)
    }

    /// Mirror of `BookRepository.generateSortTitle` (kept local so the fixture
    /// has no ordering dependency on the type under test).
    static func sortTitle(for title: String) -> String {
        var result = title.lowercased()
        for article in ["the ", "a ", "an "] where result.hasPrefix(article) {
            result = String(result.dropFirst(article.count)); break
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The single `NSManagedObjectModel` the app test host already loaded.
    /// Reusing this exact instance (rather than letting each new container parse
    /// its own copy of `Folio.momd`) is what keeps `Book.entity()` /
    /// `Type.fetchRequest()` unambiguous — otherwise two rival
    /// `NSEntityDescription`s claim each subclass and fetches throw
    /// "a fetch request must have an entity".
    @MainActor
    private static let hostModel: NSManagedObjectModel =
        PersistenceController.shared.container.managedObjectModel

    /// A fresh, isolated `NSInMemoryStoreType` stack backed by the host model.
    /// Fresh per test — no cross-test state, no wipe needed.
    @MainActor
    static func makeInMemoryContext() -> (NSPersistentContainer, NSManagedObjectContext) {
        let container = NSPersistentContainer(name: "FolioPerf", managedObjectModel: hostModel)
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, e in loadError = e }
        precondition(loadError == nil, "perf in-memory store failed to load: \(String(describing: loadError))")
        let ctx = container.viewContext
        ctx.automaticallyMergesChangesFromParent = false
        return (container, ctx)
    }

    /// Write `count` tiny valid-extension placeholder files into a temp dir.
    static func makePlaceholderFiles(count: Int, seed: UInt64 = 0xABCDEF) -> URL {
        var rng = SplitMix64(seed: seed)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("folio-perf-import-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<count {
            let adj = adjectives[Int(rng.next() % UInt64(adjectives.count))]
            let noun = nouns[Int(rng.next() % UInt64(nouns.count))]
            let last = lastNames[Int(rng.next() % UInt64(lastNames.count))]
            let fmt = formats[i % formats.count]
            // "ZZPERF" prefix keeps placeholder titles out of the fixture's title
            // space so pre-populated-library import tests see zero false duplicates.
            let name = "ZZPERF \(adj) \(noun) \(i) - \(firstNames[Int(rng.next() % UInt64(firstNames.count))]) \(last).\(fmt)"
            let url = dir.appendingPathComponent(name)
            let body = "FOLIO-PERF-PLACEHOLDER-\(i)".data(using: .utf8)!
            try? body.write(to: url)
        }
        return dir
    }
}
