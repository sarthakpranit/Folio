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
- Core Data (CloudKit-ready)
- AppKit grid for performance, SwiftUI for supporting views

## Core Data Model (Phase 1)
Entities: Book, Author, Series, Tag, Collection
Key indices: Book.title, Book.dateAdded, Book.lastOpened, Author.name, Series.name

## Phase Summary
Phase 1: macOS WiFi + Send to Kindle MVP
Phase 2: iOS + USB + Bonjour/QR polish, optional LLM metadata
Phase 3: advanced features

For historical detail and full original specs, see `docs/archive/prd.md` and `docs/archive/technical-requirements.md`.
