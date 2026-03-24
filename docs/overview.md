# Folio Overview

Folio is a native macOS ebook manager focused on a fast, beautiful library experience and effortless wireless transfer. The initial release is macOS-only with WiFi transfer and Send to Kindle as marquee features. iOS and USB workflows are still deferred.

## Value Proposition
- "The Beautiful Ebook Library for Mac"
- WiFi-first transfer (HTTP server + Send to Kindle)
- Automatic metadata and cover enrichment
- Local-first, privacy-respecting, GPL v3 (Calibre integration)

## Current Phase
- Phase 2: polish and library-management follow-through (in progress)
- Phase 1: WiFi-first MVP is complete

## Scope Snapshot
In scope for macOS launch:
- Library management with search, filters, and sorting
- WiFi transfer via built-in HTTP server
- Send to Kindle via SMTP
- Calibre-powered conversion
- Metadata fetching (Google Books + Open Library)

Deferred:
- iOS app
- USB device workflows
- LLM-based metadata enhancement
- CloudKit sync enablement until entitlements and validation are ready

For detailed requirements and implementation, see `docs/requirements.md` and `docs/roadmap.md`.
