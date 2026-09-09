# ADR 0003 — The `FolioCore` boundary: keep it, with an explicit rule

- **Status:** Accepted (2026-09-09)
- **Wayfinder ticket:** [D3 — Is the FolioCore boundary real or leaky?](https://github.com/sarthakpranit/Folio/issues/23) · map [#19](https://github.com/sarthakpranit/Folio/issues/19)
- **Informed by:** R3 ([#32](https://github.com/sarthakpranit/Folio/issues/32))

## Context

Folio is split into two modules:

- **`Folio`** — the macOS app: SwiftUI views, the Core Data model + stack, app services (`LibraryService`, `BookRepository`, `ImportService`, `SearchService`).
- **`FolioCore`** — a Swift package: HTTP transfer server, Bonjour, QR generation, metadata API clients, Send-to-Kindle, Calibre wrapper, and utility extensions. `Package.swift` declares `.macOS(.v13)` and `.iOS(.v16)`.

R3's finding: the seam is **real but half-built**.

- **No hard leaks** — nothing in `FolioCore` imports SwiftUI or CoreData. `QRCodeGenerator`'s `PlatformImage` (`NSImage`/`UIImage` behind `#if os`) is a clean cross-platform abstraction. `HTTPTransferBookProvider` is a proper dependency inversion — the server has no idea `LibraryService` exists.
- **Soft coupling** — `HTTPTransferServer` and `BonjourService` are `@MainActor … : ObservableObject` with `@Published` properties, consumed by the app as `@StateObject` / `@ObservedObject`. This ties them to SwiftUI's observation model (Combine).
- **Under-used** — the app reimplements utilities `FolioCore` already provides and tests: `BookRepository.generateSortTitle` vs `String.sortableTitle`; `BookRepository.supportedExtensions` literal vs `SupportedFormats`; ad-hoc ISBN handling vs `String.isValidISBN10/13`; `HTTPTransferServer`'s own `escapeHTML` vs `String.htmlEscaped`.

## Decision

1. **Keep the `Folio` / `FolioCore` split.** It is the one piece of deliberate architecture in the codebase; collapsing it discards `QRCodeGenerator`, the tested string/ISBN/date/format utilities, and the provider protocol for no gain.

2. **Seam rule — what may cross the line:**
   - `FolioCore` **may** expose `ObservableObject` / `@Published` / Combine types and `@MainActor` isolation. Folio's frontends will only ever be SwiftUI on Apple platforms, so this coupling is acceptable.
   - `FolioCore` **may not** `import SwiftUI`, `import CoreData`, or import AppKit/UIKit for view/layout code. Platform image types (`NSImage`/`UIImage`) are allowed behind `#if os(...)` for image *generation*, not UI.
   - The app **must** consume `FolioCore`'s utilities rather than reimplementing them. Where both exist, `FolioCore`'s is canonical and the app-side copy is deleted.
   - `FolioCore` owns no persistence. It exchanges plain value types (`BookMetadata`, `BookDTO`, …) and protocols (`HTTPTransferBookProvider`, `MetadataProvider`) with the app.

3. **Core Data stays app-side** — the model (`Folio.xcdatamodeld`) and `BookRepository`. `architecture.md` already states this. D3 does not attempt to solve persistence-for-iOS; that is a future effort's first ticket if an iOS target is ever built.

4. **`FolioCore` stays iOS-buildable as a live constraint.** Keep `.iOS(.v16)` in `Package.swift`. It is nearly free: the constraint it enforces (no macOS-only imports in Core) *is* the seam rule above, so a compiler checks the rule at no extra cost, and the stated future iOS option is preserved. Revisit only under a strict "don't maintain for unshipped platforms" reading.

## Consequences

- **Implementation-phase work** (already filed): delete app-side forks and depend on `FolioCore` — R3 [#58](https://github.com/sarthakpranit/Folio/issues/58) (sortableTitle / SupportedFormats / ISBN), R3 [#61](https://github.com/sarthakpranit/Folio/issues/61) (`escapeHTML` → `String.htmlEscaped`), R4 [#70](https://github.com/sarthakpranit/Folio/issues/70) (ISBN ×3), R6 [#82](https://github.com/sarthakpranit/Folio/issues/82) (one `SupportedFormats`), R6 [#83](https://github.com/sarthakpranit/Folio/issues/83)/[#84](https://github.com/sarthakpranit/Folio/issues/84) (scanner + bookmark helpers — decide their module then).
- **D4 (concurrency)** is not constrained by this ADR — `FolioCore` may adopt actors freely; the seam rule permits whatever isolation model D4 chooses, as long as no SwiftUI/CoreData import appears.
- **D5** should add a CI check: `swift build` of `FolioCore` for both `macOS` and `iOS` destinations, plus a grep gate forbidding `import SwiftUI` / `import CoreData` under `FolioCore/Sources`.
- **New `FolioCore` code** for shared concerns (a folder scanner, a bookmark/security-scoped-access helper — R6 #83/#84) is acceptable and preferred over app-side duplication, provided it holds no persistence and obeys the seam rule.
