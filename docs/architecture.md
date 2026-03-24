# Architecture

Folio currently has two concrete implementation layers:

1. Folio App (macOS target)
   - SwiftUI UI for the grid, table, sidebar, overlays, settings, and Kindle flows
   - Core Data model and persistence wiring
   - App-specific services such as `LibraryService`, `BookRepository`, and import coordination

2. FolioCore (Swift Package)
   - UI-agnostic services and models
   - Metadata clients, HTTP transfer server, Bonjour, QR generation, Send to Kindle, Calibre integration
   - Intended to stay reusable for any future iOS target

## Data Flow
SwiftUI views -> `LibraryService` facade -> repositories/import/search helpers -> Core Data and FolioCore services -> UI refresh

## Notes
- The library grid is implemented with SwiftUI `LazyVGrid`, not AppKit `NSCollectionView`.
- Core Data lives in the app target today; FolioCore is reusable service code rather than the persistence layer.
- CloudKit support is scaffolded but not enabled end-to-end yet.
