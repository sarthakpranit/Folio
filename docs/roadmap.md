# Roadmap

This roadmap consolidates the release plan and current session state. It tracks what is done, what is in progress, and what remains.

## Current Phase
Phase 2: polish and library-management follow-through (in progress)

## Completed Highlights
- Core Data model and persistence
- LibraryService CRUD, search, filters
- Calibre conversion service with progress/cancel
- Metadata services (Google Books + Open Library)
- WiFi HTTP server
- Send to Kindle service with Keychain storage
- macOS UI grid and sidebar
- Sorting and table view fixes
- QR code + Bonjour flow

## In Progress / Next Up
- Enhanced search syntax (title:, author:, tag:)
- Saved searches and smart collections
- Real-device testing for WiFi transfer and Send to Kindle
- CloudKit entitlements setup and sync validation

## Follow-up Cleanup
- Tighten repository/docs/test consistency after recent architecture changes
- Decide whether collections remain dormant or move into active UI scope
- Remove or document any intentionally dormant dependencies and stubs

## Longer-Term (Phase 2+)
- iOS target and UI parity
- USB device workflows
- LLM metadata enhancement (optional)
