# Folio — Target Architecture

The north star for the contributor-readiness implementation phase (Wayfinder map [#19](https://github.com/sarthakpranit/Folio/issues/19)). It synthesises the eight subsystem reviews (R1–R9, [#30](https://github.com/sarthakpranit/Folio/issues/30)–[#38](https://github.com/sarthakpranit/Folio/issues/38)), the usability evaluation (U1, [#26](https://github.com/sarthakpranit/Folio/issues/26)), and ADRs 0001–0004 into one picture of where the code is going.

This document describes the **intended** state. It is not a description of `main` today. Every `audit-finding` issue is a step from here to there.

---

## 1. Layers

Data and control flow strictly downward. Upper layers depend on lower layers, never the reverse.

```
┌────────────────────────────────────────────────────────────┐
│  VIEWS (SwiftUI)                                            │  render + bind only; no business logic
├────────────────────────────────────────────────────────────┤
│  STORE + ACTIONS                                            │
│   · LibraryStore        (@MainActor @Observable)            │  the one book-list source of truth
│   · *Coordinator / *Actions  (import, conversion, kindle,   │  user intents; call services, surface results
│      folder-watch, book-group actions)                      │
├────────────────────────────────────────────────────────────┤
│  SERVICES  (actors, injected)                               │  metadata, transfer, bonjour, conversion,
│                                                            │  send-to-kindle, keychain, QR
├────────────────────────────────────────────────────────────┤
│  REPOSITORY  (@MainActor)                                   │  the only door to Core Data
├────────────────────────────────────────────────────────────┤
│  CORE DATA  (app target only)                               │  Book, Author, Series, Tag, Collection, KindleDevice
└────────────────────────────────────────────────────────────┘

FolioCore (Swift package)  ── UI-agnostic services + value types + utilities; see §6
```

### LibraryService

`LibraryService` **stays** (name kept for continuity) but is **gutted to a composition root**: it constructs and wires `LibraryStore`, the coordinators, the repository, and the injected services, and exposes nothing else except genuinely cross-cutting operations. The library-folder watcher and the conversion orchestration are extracted into their own coordinators. It holds **no** `@Published` collections.

---

## 2. Source of truth — `LibraryStore`

**Decision (D5.1):** one `LibraryStore`, `@MainActor` + `@Observable`, wrapping an `NSFetchedResultsController` for change observation. It owns the displayed-book pipeline:

```
FRC (Book fetch) ──► filter ──► sort ──► group (BookGroup) ──► displayedGroups
```

- Every view that shows books observes `LibraryStore`. The per-view `@FetchRequest`s (`ContentView`, `SidebarView`, `BookTableView`) are removed.
- Filter, sort, and grouping are **memoised** keyed by `(sidebar filter, search text, sort option, backing-set identity)`. Grouping never recomputes on an unrelated change.
- The search field is **debounced** (~200 ms). This is the fix for [#118](https://github.com/sarthakpranit/Folio/issues/118) (147 ms per keystroke at 5k books).
- Selection is **one model**: `Set<NSManagedObjectID>` owned by the store. The `Set<String>` in `BookTableView` and the separate `selectedBook: Book?` are gone ([#92](https://github.com/sarthakpranit/Folio/issues/92)).
- Navigation targets (detail / edit) are one enum owned once, passed down — not re-declared `@State` per view.

`BookGroup` and `BookGroupingService` keep their current grouping rules (ISBN first, normalised title fallback; format-priority for `primaryBook`) — see [CONTEXT.md](../CONTEXT.md).

---

## 3. Concurrency model (ADR 0004)

- **Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`, zero diagnostics.** `FolioCore` migrates first as a self-contained milestone; the app migrates incrementally as service-layer tickets land; the language-mode flip is gated on zero warnings.
- **Services are `actor`s.** Every `@unchecked Sendable` on a service and every hand-rolled `NSLock` / serial `DispatchQueue` used for synchronisation is **removed**, not annotated away. Rate limiters use `Task.sleep`, not `Thread.sleep`.
- **Core Data:** all access through the `@MainActor` repository. `NSManagedObject` instances never cross an isolation boundary — `NSManagedObjectID` and value snapshots do. Bulk writes (import) use a dedicated background context owned inside the repository, merging back by object ID.
- **HTTP server:** the request-handling surface is `nonisolated`; it marshals to the main actor only for state mutation, or the server core is modelled as an `actor` with a `nonisolated` façade. `@preconcurrency import Swifter`.
- No blocking work on `@MainActor`: file copies, `attributesOfItem`, `fileExists` loops, subprocess spawns all move off the main actor.

---

## 4. Error-handling policy

- Coordination, repository, and service methods **`throw`** typed errors (`LibraryError`, `MetadataError`, `ConversionError`, …). No `try?` on anything whose failure matters — **never** on `context.save()`.
- The UI layer catches and surfaces via **one** path: `ToastNotificationManager`. Errors are actionable where possible (e.g. a Send-to-Kindle failure offers "Open Settings" — U1 [#114](https://github.com/sarthakpranit/Folio/issues/114)).
- "Silent success that isn't" is a bug: a failed cover fetch, a skipped import, a dropped save must be visible (U1 [#108](https://github.com/sarthakpranit/Folio/issues/108), R4 [#68](https://github.com/sarthakpranit/Folio/issues/68), R1 [#41](https://github.com/sarthakpranit/Folio/issues/41)).
- Data-destroying operations require explicit confirmation and never fire on a single failed heuristic (R1 [#39](https://github.com/sarthakpranit/Folio/issues/39) recovery-first startup; R6 [#81](https://github.com/sarthakpranit/Folio/issues/81) scan reconciliation marks "missing", does not delete).

---

## 5. Logging policy

`os.Logger` everywhere, one subsystem (`com.folio`) with a category per component. `print(...)` is banned (~26 sites). `FolioCore`'s hand-rolled `FolioLogger` is **deleted** (R3 [#59](https://github.com/sarthakpranit/Folio/issues/59)); `FolioCore` uses `os.Logger` too.

---

## 6. The `FolioCore` seam (ADR 0003)

- `FolioCore` **may** expose `ObservableObject` / `@Published` / Combine and `@MainActor`. It **may not** `import SwiftUI`, `import CoreData`, or import AppKit/UIKit for layout. Platform image types behind `#if os(...)` are fine.
- The app **consumes** `FolioCore` utilities — it never reimplements them. The forks the reviews found are deleted: `sortableTitle` vs `generateSortTitle`, `SupportedFormats` vs the extension literal, ISBN validation (×3 → 1), `String.htmlEscaped` vs the server's own `escapeHTML`.
- `FolioCore` owns **no persistence**. It exchanges value types (`BookMetadata`, `BookDTO`) and protocols (`HTTPTransferBookProvider`, `MetadataProvider`) with the app.
- New shared concerns (folder scanner, security-scoped-access helper) belong in `FolioCore` if they hold no persistence and obey the rule.

---

## 7. Distribution & licence (ADR 0001, 0002)

- Ships as a **notarized DMG** (Sparkle + GitHub Releases the intended updater). Mac App Store is out of scope; signing/notary/appcast mechanics are a later distribution effort.
- **Calibre is an external, optional runtime dependency.** The app is fully usable without it — only format conversion and on-the-fly Kindle conversion disable. Its absence is surfaced first-class: launch detection, a clear "install / locate Calibre" affordance, a Preferences path override (U1 [#111](https://github.com/sarthakpranit/Folio/issues/111), [#105](https://github.com/sarthakpranit/Folio/issues/105)).
- Licence is **GPL v3** (swap the MIT `LICENSE` file, [#104](https://github.com/sarthakpranit/Folio/issues/104)).

---

## 8. Single home for each concern

The reviews found the same logic implemented many times. Target: one owner each.

| Concern | Canonical home |
|---|---|
| Supported ebook formats | `FolioCore/SupportedFormats` (one list; drop delegate, importer, repository, Calibre input list all read it) |
| Sort-title / article stripping | `FolioCore` `String.sortableTitle` |
| ISBN validate / normalise / convert | `FolioCore` `String` + one ISBN helper (delete `MetadataService.isValidISBN*`, app copies) |
| HTML escaping | `FolioCore` `String.htmlEscaped` |
| Date-from-metadata parsing | `FolioCore` `Date.fromMetadataString` (static formatters; providers stop rebuilding) |
| Recursive ebook directory walk | one `EbookFolderScanner` (off the main actor) |
| Security-scoped bookmark resolve + stale-refresh | one `SecurityScopedAccess` helper |
| Metadata fetch → apply → cover → save | one `MetadataCoordinator.fetchAndApply(for:)` (delete the ~6 view copies) |
| Kindle send | `SendToKindleService` + one `KindleActions` (delete the 3 view copies) |
| Conversion orchestration (stage / run / timeout / cancel / progress) | one `ConversionCoordinator` |
| Book-group display strings | one `BookGroupPresenter` |
| HTTP-server response validation / confidence scoring | shared base in `FolioCore` between the two API clients |

---

## 9. Dead-code register (remove during the implementation phase)

- CloudKit scaffolding — container type, history tracking, `isSyncing/syncError/lastSyncDate`, `import CloudKit` (R1 [#40](https://github.com/sarthakpranit/Folio/issues/40)).
- Conversion progress + cancellation subsystem — `progressPublisher`, `parseProgress`, `cancelConversion*` — currently ~150 lines with no consumer. Either wire it to the UI (U1 [#107](https://github.com/sarthakpranit/Folio/issues/107)) **or** delete it; do not leave it dormant (R5 [#72](https://github.com/sarthakpranit/Folio/issues/72)).
- Dead facade methods — `searchBooks`, `filterBooks`, `addBook`, `updateBook`, `addTag` (R2 [#49](https://github.com/sarthakpranit/Folio/issues/49)).
- `ConversionOptions.quality` (never emitted, R5 [#78](https://github.com/sarthakpranit/Folio/issues/78)).
- Three dead Preferences controls — `autoFetchMetadata`, `preferredMetadataSource`, `defaultViewMode` (wire or delete each; U1 [#110](https://github.com/sarthakpranit/Folio/issues/110)).
- `FolioUITests.testExample` (asserts nothing, R8 [#98](https://github.com/sarthakpranit/Folio/issues/98)); stray empty `FolioCore/Tests/FolioCodeTests/` (R8 [#103](https://github.com/sarthakpranit/Folio/issues/103)).
- Dead HTTP `/cover` route (R3 [#62](https://github.com/sarthakpranit/Folio/issues/62)).

---

## 10. "Done" per subsystem

- **Persistence** — no CloudKit; `id`/core attributes non-optional with uniqueness constraints + a migration; recovery-first startup; one `@MainActor` repository as the only writer; indexed dedup key; background-context import; `LibraryStore`/FRC in place.
- **`FolioCore`** — Swift 6 language mode, actors, `os.Logger`; builds for macOS **and** iOS; grep-gate proves no `import SwiftUI`/`import CoreData`; no app-side forks remain.
- **Metadata** — one shared `MetadataService`; one bounded work queue (dedupe by book id, `maxConcurrent≈2`); shared provider base; covers downsized before storage; fetch failures marked and backed off; low-confidence matches are offered, not auto-applied (U1 [#106](https://github.com/sarthakpranit/Folio/issues/106), [#116](https://github.com/sarthakpranit/Folio/issues/116)).
- **Conversion** — one `ConversionCoordinator` with a timeout, real progress, and a Cancel button; `getMetadata` drains its pipe and has a timeout; no `Process`/`Pipe` races.
- **Import & scan** — background, batched, cancellable, per-file report; one scanner; one canonical format list; scan reconciliation never deletes on a single failed heuristic; `FilenameParser` has a test table.
- **View layer** — no business logic in a `View`; `BookGroupViews` split, one file per view, none over 500 lines; `ContentView` decomposed; `.sheet(item:)`; key monitor removed on teardown; one selection model.
- **Tests** — a test-support module (store factory, fixtures); service-level suites for metadata/conversion/import/scan; failure-path and boundary tests; performance baselines committed; CI runs it all.
- **UX** — a first-run experience; visible active sort/filter; keyboard navigation in the grid; consistent, actionable error surfaces; metadata provenance visible.

---

## 11. CI gates (added with M5)

1. Build `Folio` + run all suites (app + `FolioCore` + `FolioPerformanceTests`) — zero failures.
2. Build `FolioCore` for `macOS` **and** `iOS` destinations.
3. `SWIFT_STRICT_CONCURRENCY=complete` on both modules — zero concurrency diagnostics.
4. Grep gate: no `import SwiftUI` / `import CoreData` under `FolioCore/Sources`; no `print(` under `Folio/` or `FolioCore/Sources/`.
5. File-length gate at the documented limits (Views 300 / ViewModels 400 / Services 300 / Utilities 200; hard cap 500).
6. Performance tests fail on regression against the committed baseline.

---

## 12. Implementation milestones

Defined here; the implementation-phase kickoff creates the GitHub Milestones and buckets every `audit-finding` issue.

| | Theme | Anchors |
|---|---|---|
| **M0** | Stop the bleeding (data loss / hangs) | #39, #81, #73, #74, #41 (persistence) |
| **M1** | `FolioCore` → Swift 6 | actors, delete `FolioLogger`, seam-rule CI, delete app forks (#58, #61, #70) |
| **M2** | Persistence & the store | #40, #44, #42, #43, `LibraryStore`/FRC, #46 |
| **M3** | Services layer | #48, #63, #64, #83, #84, #72, #65, #75–#77 |
| **M4** | View layer + UX | #88, #89, #90, #91, #92, #94, #118, #105–#117 |
| **M5** | Tests + CI | #96–#103, #98, the six gates above |
| **M6** | Housekeeping | #104, `print`→`OSLog`, `try?` audit, deployment-target unify, dead-code sweep, #119, DOC1/DOC2 |

**M0 is done first, unconditionally.** M1 precedes the app's Swift 6 work. Otherwise the order can flex.
