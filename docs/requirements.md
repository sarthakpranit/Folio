# Requirements

This document consolidates the PRD and technical requirements into a single source of truth.

## Product Summary
- macOS-first ebook manager with a beautiful library UI
- WiFi transfer and Send to Kindle are core flows
- Automatic metadata and cover enrichment
- Calibre conversion for format compatibility
- Local-first and privacy-respecting (GPL v3)

## Core Features (Phase 1)
1. Smart format conversion
2. Universal wireless transfer
3. Visual library browser
4. Automatic metadata enhancement
5. Flexible file management

## Platform Targets
- Phase 1: macOS 13+
- Phase 2: iOS 16+ (deferred)

## Performance Targets
- Startup < 3s
- Library load < 2s for 5,000 books
- Search response < 100ms
- Conversion < 5s for typical 500KB EPUB

## Core Architecture Decisions
- Calibre CLI for conversion and metadata
- Swifter for HTTP server
- Core Data in the macOS app target, with CloudKit scaffolding not yet enabled
- SwiftUI grid/table/sidebar UI, coordinated through `LibraryService`

## Core Data Model (Phase 1)
Entities: Book, Author, Series, Tag, Collection, KindleDevice
Key indices: Book.title, Book.dateAdded, Book.lastOpened, Author.name, Series.name, KindleDevice.name

## Phase Summary
Phase 1: macOS WiFi + Send to Kindle MVP
Phase 2: library-management polish, search/saved-search follow-through, device validation, optional CloudKit work
Phase 3: advanced features
