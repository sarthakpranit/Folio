# Folio Performance Hotspot Map

Status: investigation baseline for Wayfinder ticket [Concurrency, Memory, and I/O Hotspot Priorities](https://github.com/sarthakpranit/Folio/issues/5).

This is a prioritization map, not a claim that every path is currently slow. The next implementation tickets should measure each target before and after changing it.

## Existing budgets

The project requirements define these release budgets:

- Startup: under 3 seconds.
- Library load: under 2 seconds for 5,000 books.
- Search response: under 100 milliseconds.
- Typical conversion: under 5 seconds for a 500 KB EPUB.

There are currently no automated performance tests for these budgets.

## Priority map

### P0 — Import and scan persistence path

Evidence:

- `ImportService.importBooks` processes every file serially on the main actor (`Folio/Services/ImportService.swift:88-160`).
- Each imported file calls `BookRepository.add`, which saves the view context and then calls `refreshAllObjects` (`Folio/Services/BookRepository.swift:126-171`).
- Duplicate detection fetches the full `Book` set for every candidate file before applying the filename comparison (`Folio/Services/BookRepository.swift:83-93`).
- Library monitoring can trigger scans after filesystem events; a scan performs a full directory enumeration and then imports new files (`Folio/Services/LibraryService.swift:390-489`).

Risk: large imports and folder rescans can block the UI, create repeated Core Data work, and scale poorly as `books × imported files`.

Measure first: import 100/1,000/5,000 representative files; scan an unchanged 5,000-book folder; record wall time, main-thread utilization, save count, and peak memory.

Likely direction: move file enumeration and persistence to a private background context, batch saves, and replace per-file duplicate fetches with one normalized index for the import operation. Preserve the existing duplicate strategy and recovery behavior.

### P0 — Cover image memory and decoding

Evidence:

- Grid cells decode Core Data binary cover data into a new `NSImage` while rendering (`Folio/Views/Books/BookGroupViews.swift:60-62`).
- The same view applies multiple blurred/resized image layers, and the detail view repeats direct `NSImage(data:)` decoding.
- Cover downloads store the complete network response in `coverImageData` without a byte limit or downsampling (`Folio/Views/Books/BookGroupViews.swift:307-313`).
- Metadata fetches can start from each visible group’s `.task` (`Folio/Views/Books/BookGroupViews.swift:202-205`), while the app-level “Fetch Missing Metadata” loop processes all missing books serially (`Folio/FolioApp.swift:105-155`).

Risk: large covers and many visible cells can cause memory spikes, repeated decoding, and scroll hitching; concurrent metadata/cover work can amplify this.

Measure first: scroll a 5,000-book library with 100/1,000 covers; record peak resident memory, image decode time, network concurrency, and dropped-frame symptoms.

Likely direction: store/display bounded thumbnails or downsample before Core Data persistence, add an in-memory image cache keyed by object ID/version, and deduplicate/cap metadata requests. Do not introduce a third-party image framework without profiling.

### P1 — Main-thread collection, grouping, and sorting

Evidence:

- `ContentView` converts `FetchedResults` to an array, filters it, sorts it, and groups it on view evaluation (`Folio/ContentView.swift:54-136`).
- Author-based sort and search traverse Core Data relationship sets for each book (`Folio/ContentView.swift:142-151`, `Folio/ContentView.swift:116-123`).
- `BookGroupingService.groupBooks` rebuilds dictionaries and `BookGroup.primaryBook` rescans metadata when the view derives or renders groups (`Folio/Models/BookGroup.swift:20-31`, `Folio/Models/BookGroup.swift:103-120`).

Risk: repeated SwiftUI body evaluation can make the 5,000-book target fail even if Core Data fetches are acceptable.

Measure first: type a 20-character search query and switch sort/view modes over 5,000 generated books; measure per-keystroke latency and body/grouping time.

Likely direction: move filtering/sorting into fetch requests where practical, debounce search input, and cache derived group/index data with explicit invalidation. Keep current grouping semantics.

### P1 — Metadata and conversion I/O

Evidence:

- Metadata providers are tried sequentially, and cover fetches are separate network requests (`FolioCore/Sources/FolioCore/Services/MetadataService.swift:195-333`).
- App-wide metadata fetching loops through every incomplete book and saves after each book (`Folio/FolioApp.swift:130-155`).
- Conversion stages a full input copy and later copies the full output back to the destination (`Folio/Services/LibraryService.swift:601-676`).
- Calibre process output uses `readDataToEndOfFile` in several paths (`FolioCore/Sources/FolioCore/Services/CalibreConversionService.swift:317-318`, `550-553`).

Risk: network and disk work can be serialized unnecessarily; large process output or simultaneous conversions may increase memory and I/O pressure.

Measure first: metadata batch throughput with offline/slow providers, conversion wall time and peak memory for representative EPUB sizes, and concurrent conversion behavior.

Likely direction: bounded task groups for metadata, one save per batch, cancellation, and explicit conversion concurrency limits. Preserve user-visible progress and cleanup guarantees.

### P2 — Search implementation

Evidence:

- `SearchService.search` performs lowercase conversion and relationship traversal across the full in-memory array (`Folio/Services/SearchService.swift:27-61`).
- `ContentView` independently implements a narrower title/author search over the same array (`Folio/ContentView.swift:116-124`).

Risk: duplicate search logic can drift, and the current approach is only safe while the full library fits comfortably in memory.

Likely direction: consolidate semantics first, then benchmark. Move to a fetch-backed search or an indexed normalized search field only if the <100ms target fails.

## Required measurement tickets

The next implementation work should create testable tickets for:

1. A reproducible performance harness with seeded Core Data fixtures at 100, 1,000, and 5,000 books.
2. Import/scan persistence batching and duplicate-index measurement.
3. Cover decode/downsampling/cache measurement.
4. Search and grouping latency measurement.
5. Metadata/conversion I/O concurrency and cancellation measurement.

No optimization should be accepted without before/after results against the applicable budget and a regression test for the user-visible behavior it preserves.
