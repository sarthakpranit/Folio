# Folio Performance Baseline

Status: baseline measurement for Wayfinder ticket
[R9 - Performance measurement harness and baseline](https://github.com/sarthakpranit/Folio/issues/38),
child of the map [#19](https://github.com/sarthakpranit/Folio/issues/19). Companion
to [`docs/performance-hotspot-map.md`](performance-hotspot-map.md), which holds the
priority map and the hypotheses; this file holds the numbers.

This records where Folio actually stands against its stated budgets, measured on a
deterministic fixture, so the implementation phase has something to regress
against. It **fixes nothing** — measurement only. Finding numbers (#42, #43, #63,
#67, #80) refer to the `audit-finding` issues from reviews R1-R8.

## Harness

- **Target:** `FolioPerformanceTests` — an Xcode unit-test bundle with its own
  scheme (`FolioPerformanceTests`). It is **not** in the `Folio` scheme, so it
  never runs with the normal `FolioTests` / `FolioUITests` suites.
- **Source:** `FolioPerformanceTests/` (throwaway prototype — `wayfinder:prototype`):
  - `PerfSupport.swift` — `SplitMix64` seeded RNG, `PerfClock` (median-of-N timing
    on `ContinuousClock`), `PerfLog` (prints one `PERF-ROW` line per measurement),
    and `PerfFixture` (the deterministic Core Data fixture generator).
  - `FindDuplicatePerfTests.swift`, `LoadSearchGroupingPerfTests.swift`,
    `ImportScalingPerfTests.swift`, `CoverDecodePerfTests.swift`.
- **Run:**
  ```
  DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer \
    xcodebuild -scheme FolioPerformanceTests -destination 'platform=macOS' \
    -derivedDataPath /tmp/folio-perf test
  ```
- It measures the **real app code** via `@testable import Folio` —
  `BookRepository`, `ImportService`, `SearchService`, `BookGroupingService`,
  `FilenameParser`, plus a **transcription** of `ContentView.displayedBooks`
  (lines ~81-142) and `ContentView.sortBooks` (`displayedBooks` is a `var` on a
  `View` and can't be called from a test; the copy is marked in the source and
  must be kept in sync).
- Not `XCTMeasure`: its 10x re-run of a multi-second fixture build is impractical
  here. Timing is median of N runs (N = 3-7) after warm-up, wall clock.

### Fixture

`PerfFixture.populate(count:)` builds an in-memory Core Data stack (fresh
`NSInMemoryStoreType` per test, reusing the host app's one `NSManagedObjectModel`
instance to avoid entity-ambiguity) with, at N = 5,000:

- 5,000 `Book` rows, 300 `Author`, 10 `Series`, 12 `Tag`
- ~15% of books draw an ISBN-13 from a small shared pool (so 2-4 collide →
  exercises `BookGroupingService`); ~45% get a unique ISBN; the rest none
- ~12% of titles deliberately collide (adj+noun, no numeral)
- formats cycled across epub / mobi / pdf / azw3 / cbz
- everything seeded → runs are comparable

## Environment

| | |
|---|---|
| Machine | Apple M2, 8 cores, 24 GB RAM (arm64) |
| OS | macOS 27.0 (build 26A5416b) |
| Toolchain | Xcode 27.0 beta (27A5252f), Swift 5 language mode |
| Build config | **Debug**, `-Onone` (unit-test bundle default) |
| Date | 2026-09-09 |
| Baseline suite state | `FolioCore` `swift test` 22/22 · `FolioTests` 20/20 · `FolioUITests` 5/5 · `FolioPerformanceTests` 14/14 (issue #20 + this ticket) |

### Caveats — read before citing a number

1. **Debug / `-Onone`.** A Release build is materially faster. Treat absolute
   values as an upper bound; the *shape* of each curve and the *ratios* between
   scenarios are the signal, and those hold across optimisation levels.
2. **Runs inside the `Folio.app` test host.** On launch the host app renders
   `ContentView`, whose cells fire real metadata network calls — this adds
   scheduler noise (numbers are conservative) and incidentally reproduces
   finding #63 live (see below).
3. Synthetic covers are ~116 KB JPEGs. Real covers from Google Books /
   OpenLibrary are commonly 100-600 KB (cf. #67's own 0.5-3 GB / 5k projection),
   so the cover-weight number here is a **conservative floor**.
4. `NSImage(data:)` defers pixel decode to first draw, so the "construction"
   cover row understates on-screen cost; a forced-rasterisation row is included.

## Budgets (`docs/requirements.md`)

| Budget | Target |
|---|---|
| Startup | < 3 s |
| Library load | < 2 s for 5,000 books |
| Search response | < 100 ms |
| Conversion | < 5 s for a typical 500 KB EPUB |

## Results (measured 2026-09-09)

### Against a budget

| Scenario | Measured | Budget | Verdict |
|---|---:|---|:--:|
| Library load — `fetchAll()` + `groupBooks()` + `primaryBook` eval, N=5,000 (cold) | **15.7 ms** | < 2,000 ms | ✅ PASS |
| `groupBooks()` + `primaryBook` re-eval, N=5,000 (warm, per render pass) | **13.7 ms** | < 100 ms (every view update) | ✅ PASS |
| `SearchService.search()`, N=5,000 — worst of 7 queries | **16.2 ms** | < 100 ms | ✅ PASS |
| `ContentView` inline filter + `sort(.author)` + regroup, N=5,000 — **first keystroke** ("m", ~half the library matches) | **147.0 ms** | < 100 ms | ❌ **FAIL** |
| …same pipeline, keystrokes 2-8 (narrower) | 20-30 ms | < 100 ms | ✅ PASS |
| …inline filter alone ("silent") | 11.9 ms | < 100 ms | ✅ PASS |
| Cover decode — forced rasterisation, 100 covers | 14.3 ms | < 16 ms / frame | ⚠️ borderline |
| Cover decode — forced rasterisation, 500 covers | 75.6 ms | < 16 ms / frame | ❌ over, but 500 on screen at once is unrealistic |
| Startup | not measured | < 3 s | — (needs signpost ticket) |
| Conversion, 500 KB EPUB | not measured | < 5 s | — (needs Calibre-fixture ticket) |

### Scaling / cost curves (no explicit budget — the *shape* is the finding)

| Scenario | 50 | 200 | 1,000 | Notes |
|---|---:|---:|---:|---|
| `BookRepository.add` loop, no dup check, no sleep (ms) | 82.7 | 361 | 2,164 | ≈1.6-2.2 ms/file — per-file `save()` + `refreshAllObjects()` |
| `ImportService.importBooks`, empty library (ms) | 827 | 3,748 | 21,197 | ≈17-21 ms/file; fixed `Task.sleep(10ms)/file` floor = 47-60% of wall time |
| `ImportService.importBooks`, into a **5,000-book** library (ms) | — | **11,345** | — | 56.7 ms/file — 3x the empty-library cost, all of it #42's per-file full-table scan |

| `findDuplicate` per call | N=1,000 | N=5,000 |
|---|---:|---:|
| median per lookup (ms) | 2.58 | 12.01 |
| projected cost inside a 1,000-file import (s) | **2.6** | **12.0** |

| Cover blobs | value |
|---|---:|
| avg synthetic cover (JPEG, 1200×1800) | 116.7 KB |
| **projected `coverImageData` weight at 5,000 books** | **≈ 570 MB** (conservative — real covers larger) |
| `NSImage(data:)` construction, 100 / 500 covers | 12.7 ms / 65.6 ms (~0.13 ms each; decode deferred) |
| forced rasterisation, 100 / 500 covers | 14.3 ms / 75.6 ms (~0.15 ms each) |

Full `PERF-ROW` output for the run is reproducible from the harness; re-run to
regenerate.

## Interpretation

### ❌ P1 — the per-keystroke pipeline blows the 100 ms search budget
Typing into the library search field re-runs, **on every keystroke with no
debounce**: `Array(books)` rebuild → inline title/author filter →
`sortBooks(.author)` (traverses the `authors` relationship set per element) →
`BookGroupingService.groupBooks()` (rebuilds all groups, re-scans `primaryBook`).
At N=5,000 the **first keystroke costs 147 ms** — over budget — because a
one-character query matches ~half the library and the sort+regroup runs on that
large intermediate array. Narrower subsequent queries fall to ~20-30 ms. The
filter *alone* is ~12 ms; the cost is what it's bundled with. Fixes:
debounce input; memoise `displayedBookGroups` with explicit invalidation; push
filter/sort into the `@FetchRequest`.

### ⚠️ #42 — `findDuplicate` is O(N) per call, O(N×M) per import
`findDuplicate` issues a **predicate-less `fetch` of the entire `Book` table** and
linearly scans it in Swift. Cost per call scales with library size (2.6 ms at
N=1k → 12.0 ms at N=5k). `ImportService` calls it once per file, so importing
M files into an N-book library costs ≈ `perCall(N) × M`: **a 1,000-file import
pays ~12 s of pure dup-detection at N=5k**, and it grows with the library. Seen
directly in the scaling table — the same 200-file import takes 3.7 s into an
empty library and **11.3 s into a 5,000-book one**. No stated budget, but this is
avoidable: build one normalized filename/sortTitle index per import → O(M).

### ⚠️ #43 / #80 — import is serial, main-actor, per-file save, sleep-throttled
Two independent costs, measured separately:
- **Per-file persistence:** the raw `add` loop is ~1.6-2.2 ms/file for
  `viewContext.save()` + `viewContext.refreshAllObjects()` **on every file**.
  `refreshAllObjects` after each add is wasteful; saves should batch.
- **The sleep:** `try? await Task.sleep(10 ms)` after every file is a hard floor
  of `10 × fileCount` ms — **47-60% of total import wall time** at the sizes
  measured — and buys nothing that a periodic progress yield wouldn't.
- Combined with #42, `importBooks` is ~17 ms/file empty and ~57 ms/file into a
  5k library. Fix direction: private background context, batched saves, drop the
  per-file sleep and `refreshAllObjects`, replace per-file `findDuplicate` with
  an index.

### ⚠️ #67 — covers are full-size blobs in Core Data
Even with conservative ~116 KB synthetic covers, that projects to **≈ 570 MB of
`coverImageData` resident in the store at 5,000 books**, none downsampled. Decode
*CPU* is not the bottleneck on M2 (~0.15 ms/cover forced), but the **memory
footprint** is: ~570 MB of encoded blobs plus ~8.6 MB of uncompressed bitmap per
on-screen cover (1200×1800×4), with no stored thumbnail and no image cache keyed
by object ID/version. This is a memory finding. Fix: downsample to a stored
thumbnail; add an in-memory cache.

### ✅ Library load, grouping, `SearchService` — currently within budget at 5k
`fetchAll()` + `groupBooks()` is ~16 ms cold — the < 2 s library-load budget is
**not** at risk at 5,000 books on this hardware. `SearchService.search()` is
~15 ms — under the 100 ms bar. Caveats: `groupBooks()` still runs on **every**
SwiftUI body pass (no memoisation, #P1), and `SearchService` is a **second,
separate** search implementation from the one on the keystroke path (hotspot-map
finding) — only the latter is over budget.

### ⚠️ #63 — per-cell `MetadataService()` defeats the rate limiters (mechanism; observed, not benchmarked)
Not measured with a controlled benchmark (needs network). The mechanism:
- `BookGroupCell.task` (`BookGroupViews.swift:203-206`) runs
  `let metadataService = MetadataService()` **per cell, per appearance** (also
  `ContentView.swift:646`, `FolioApp.swift:126`, `BookGroupViews.swift:862`/`1276`).
- `MetadataService.init()` builds fresh `OpenLibraryAPI()` + `GoogleBooksAPI()`.
- Each API instance keeps throttle state (`lastRequestTime`,
  `consecutiveRateLimits`) behind an **instance** `rateLimitQueue`, so
  `enforceRateLimit()` only serialises calls *through that one instance*.
- N visible cells → N independent instances → N simultaneous hits to both
  providers → HTTP 429 → per-instance exponential backoff
  (`GoogleBooksAPI`: `baseRetryDelay = 5 s`, `maxRetryAttempts = 3` → 5 s, 10 s,
  20 s, then give up). This is the "metadata loads slowly in bursts" symptom.

**Observed live** in this harness's own test-host log (host app launching once,
`ContentView` rendering, cells firing):

```
[WARNING] GoogleBooksAPI: Rate limited, retry 1/3 in 5s
[WARNING] GoogleBooksAPI: Rate limited, retry 2/3 in 10s
[WARNING] GoogleBooksAPI: Rate limited, retry 3/3 in 20s
[WARNING] MetadataService: Provider google_books failed: Rate limited: Too many requests
```

Expected fix: one shared/injected `MetadataService` (a single actor-guarded
limiter) + a bounded task group for the visible set.

### Not measured here — need their own tickets
- **Startup < 3 s** — needs a launched Release build with `os_signpost` /
  `XCTApplicationLaunchMetric`.
- **Conversion < 5 s / 500 KB EPUB** — depends on the external Calibre
  `ebook-convert` binary (findings #73/#74: no timeout); needs a conversion
  harness with a fixture EPUB.

## Backlog seeds for D5 / the implementation phase

| Finding | Budget status | Direction |
|---|---|---|
| P1 keystroke pipeline | **FAIL** — first keystroke 147 ms @ 5k | debounce; memoise groups w/ invalidation; filter/sort in the fetch |
| #42 `findDuplicate` | ~12 s pure overhead per 1k-file import @ N=5k | one normalized index per import → O(M) |
| #43/#80 import | 10 ms/file sleep floor + per-file save/refresh | background context, batched saves, drop sleep + `refreshAllObjects` |
| #67 covers | ~570 MB projected store weight | stored thumbnail + in-memory cache |
| #63 metadata | UX stalls (5-20 s bursts) | shared `MetadataService`, bounded concurrency |
| P1 grouping | within budget in isolation | memoise `displayedBookGroups` |
| P2 `SearchService` | within budget | consolidate the two search impls |
| startup / conversion | unmeasured | dedicated signpost + Calibre-fixture tickets |
