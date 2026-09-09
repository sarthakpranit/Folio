# ADR 0004 — Migrate to Swift 6 language mode with complete strict concurrency

- **Status:** Accepted (2026-09-09)
- **Wayfinder ticket:** [D4 — Swift 6 language mode and strict concurrency](https://github.com/sarthakpranit/Folio/issues/24) · map [#19](https://github.com/sarthakpranit/Folio/issues/19)
- **Informed by:** R1 ([#43](https://github.com/sarthakpranit/Folio/issues/43)), R2 ([#52](https://github.com/sarthakpranit/Folio/issues/52)), R3 ([#56](https://github.com/sarthakpranit/Folio/issues/56), [#59](https://github.com/sarthakpranit/Folio/issues/59), [#62](https://github.com/sarthakpranit/Folio/issues/62)), R4 ([#65](https://github.com/sarthakpranit/Folio/issues/65)), R5 ([#75](https://github.com/sarthakpranit/Folio/issues/75), [#76](https://github.com/sarthakpranit/Folio/issues/76), [#77](https://github.com/sarthakpranit/Folio/issues/77))

## Context

`SWIFT_VERSION` is `5.0`. The reviews found the same concurrency shape across every service:
`final class … : @unchecked Sendable` wrapping mutable state, guarded by hand-rolled `NSLock` / serial `DispatchQueue`, with completion callbacks and Combine `send`s firing off the main thread. Concrete instances: `@MainActor` `HTTPTransferServer` whose Swifter handlers run on socket threads (#56); `@unchecked Sendable` `FolioLogger` / `MetadataService` / API clients with unsynchronised mutable fields (#59, #65); `QRCodeGenerator.shared` racing on a shared `CIFilter` (#62); `Process`/`Pipe` teardown races (#75); blocking `which` at first `.shared` touch (#76); all Core Data writes on the main-thread `viewContext` (#43, #52).

Fixing these one by one on Swift 5 has no enforcement — nothing stops the next change reintroducing a race.

## Decision

1. **The implementation phase migrates the whole codebase to Swift 6 language mode with `-strict-concurrency=complete`.** Target: `Folio` app + `FolioCore` both build under Swift 6 language mode with zero concurrency diagnostics. Not "targeted", not "stay on 5 and fix the known ones".

2. **Sequencing — module by module, then a lens, no monster ticket:**
   - **`FolioCore` first**, as a self-contained milestone: it has no Core Data, is mostly value types plus ~5 services that become `actor`s. Bump its `swift-tools-version` / language mode to 6 once it is clean. (D3 already requires it to stay iOS-buildable; this is the same discipline.)
   - **Then the app**, migrated *incrementally as the service-layer implementation tickets land* — each ticket that touches a service leaves that area Swift-6-clean.
   - Turn on `SWIFT_STRICT_CONCURRENCY = complete` **as warnings** early (while still nominally Swift 5) so the warning list is the running to-do.
   - The final flip of the app target to Swift 6 language mode is its own small ticket, **gated on zero concurrency warnings**.

3. **Core Data principle** (details belong to the R1 persistence tickets):
   - All Core Data access goes through a single `@MainActor`-isolated repository (consistent with the source-of-truth resolution expected from R2 [#47](https://github.com/sarthakpranit/Folio/issues/47)).
   - `NSManagedObject` instances never cross an isolation boundary. `NSManagedObjectID` and plain value snapshots do.
   - Background writes (bulk import, R1 [#43](https://github.com/sarthakpranit/Folio/issues/43)) use a dedicated background context owned *inside* that actor, merging results back by object ID.

4. **Third-party:** `Swifter` (1.5.0) is not `Sendable`-clean. Use `@preconcurrency import Swifter` and wrap the server in an `actor` façade (already required by R3 [#56](https://github.com/sarthakpranit/Folio/issues/56)). Replacing Swifter is out of scope for this effort unless it hard-blocks the build. `SwiftyJSON` similarly gets `@preconcurrency import` if needed.

5. **Services become `actor`s** by default (`MetadataService`, the API clients, `CalibreConversionService`, `BonjourService`, the transfer server's non-UI core). Hand-rolled `NSLock`/`DispatchQueue` synchronisation and every `@unchecked Sendable` on a service is removed, not annotated away. `os.Logger` replaces `FolioLogger` (D5 logging policy).

## Consequences

- **D5** records this as an explicit acceptance criterion of `docs/architecture-target.md`, and adds a CI job: build both modules with `SWIFT_STRICT_CONCURRENCY=complete` and fail on any concurrency diagnostic.
- The concurrency findings (#43, #52, #56, #59, #62, #65, #75, #76, #77) are no longer independent fixes — they are subsumed by "this module now compiles under Swift 6". Their issues stay as the checklist of hotspots to verify.
- `FolioCore`'s migration is a prerequisite for the app's, so it is sequenced first in the implementation phase (after D5).
- Expected churn is large but mechanical and compiler-guided; it is done per-module, each step independently reviewable and green.
