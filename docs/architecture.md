# Architecture

Folio is split into two layers:

1. FolioCore (Swift Package)
   - Models, services, networking clients, utilities
   - UI-agnostic, shared with future iOS target

2. Folio App (macOS target)
   - SwiftUI/AppKit UI, app lifecycle, assets, entitlements
   - Core Data model and persistence wiring

## Data Flow
UI/ViewModels -> FolioCore services -> Core Data -> published changes -> UI updates

## Rationale
- Shared, testable business logic
- Keeps platform-specific concerns out of the core
- Eases Phase 2 iOS addition
