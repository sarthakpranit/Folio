# Release Plan: Folio
**The Beautiful Ebook Library for Mac**

Version: 1.0
Last Updated: January 2025

---

## Overview

This document provides detailed checklists for each development phase. Use this as your roadmap to ensure complete coverage of all requirements.

**Status Legend:**
- ⬜ Not Started
- 🔄 In Progress
- ✅ Completed
- ⏸️ Blocked
- ⏭️ Deferred

---

## Phase 1: WiFi-First MVP
**Timeline:** 3-4 months
**Goal:** Deliver core ebook management with wireless transfer

### 1.1 Project Setup

- [ ] Create Xcode workspace with macOS and iOS targets
- [ ] Set up Swift Package Manager structure for shared code
- [ ] Configure Core Data model (.xcdatamodeld)
- [ ] Set up CloudKit container and entitlements
- [ ] Create GitHub repository (private initially)
- [ ] Set up .gitignore for Xcode projects
- [ ] Configure Code Signing and Provisioning Profiles
- [ ] Set up continuous integration (GitHub Actions)
- [ ] Create project documentation structure

### 1.2 Core Data Model & Persistence

- [ ] Define Book entity with all attributes
- [ ] Define Author entity with relationships
- [ ] Define Series entity
- [ ] Define Tag entity
- [ ] Define Collection entity
- [ ] Configure entity relationships (many-to-many, one-to-many)
- [ ] Add indices for searchable fields
- [ ] Create NSManagedObject subclasses
- [ ] Implement PersistenceController singleton
- [ ] Configure CloudKit sync options
- [ ] Test iCloud sync between devices
- [ ] Implement merge conflict resolution
- [ ] Create sample data for testing

**Acceptance Criteria:**
- ✅ Core Data stack initializes in <500ms
- ✅ CloudKit sync works between macOS and iOS
- ✅ No data loss during merge conflicts
- ✅ Database supports 10,000+ books without performance degradation

### 1.3 Library Management Service

- [ ] Create LibraryService singleton
- [ ] Implement addBook(from:) method
- [ ] Implement importBooks(from:) for batch import
- [ ] Implement deleteBook(_:deleteFile:) method
- [ ] Implement searchBooks(query:) with full-text search
- [ ] Implement filterBooks(by:) with multiple criteria
- [ ] Create NSFetchedResultsController for efficient data fetching
- [ ] Implement file organization strategies (watch folders vs managed)
- [ ] Add support for multiple library locations
- [ ] Implement Calibre library import
- [ ] Create background processing queue for imports
- [ ] Add progress tracking for long operations
- [ ] Implement error handling and recovery

**Acceptance Criteria:**
- ✅ Import 100 books in <30 seconds
- ✅ Search returns results in <100ms for 5,000 books
- ✅ Zero memory leaks during import/delete operations
- ✅ Graceful handling of corrupt/invalid files

### 1.4 Calibre Integration

- [ ] Bundle Calibre ebook-convert binary with macOS app
- [ ] Verify Calibre binary signatures and permissions
- [ ] Create CalibreConversionService wrapper
- [ ] Implement EPUB → MOBI conversion
- [ ] Implement EPUB → PDF conversion
- [ ] Implement MOBI → EPUB conversion
- [ ] Implement PDF → EPUB conversion (with caveats)
- [ ] Add progress tracking via stdout parsing
- [ ] Implement cancellation support
- [ ] Add conversion quality options (profiles: kindle, kobo, etc.)
- [ ] Implement batch conversion queue
- [ ] Add conversion history/logs
- [ ] Implement getMetadata(from:) using ebook-meta
- [ ] Create comprehensive error handling
- [ ] Test with 100+ diverse ebook files
- [ ] Document GPL v3 license compliance

**Acceptance Criteria:**
- ✅ 85%+ conversion success rate
- ✅ <5 seconds for typical (500KB) EPUB → MOBI
- ✅ Proper error messages for unsupported files
- ✅ No crashes during conversion failures
- ✅ Memory usage <500MB during conversion

### 1.5 Metadata Services

- [ ] Create MetadataService protocol
- [ ] Implement GoogleBooksAPI client
- [ ] Implement OpenLibraryAPI client
- [ ] Create ISBN-based lookup
- [ ] Create title + author lookup
- [ ] Implement cover image download and caching
- [ ] Create fallback strategy (Google → OpenLibrary → Manual)
- [ ] Add metadata confidence scoring
- [ ] Implement user confirmation for ambiguous matches
- [ ] Add background fetching with URLSession
- [ ] Implement disk caching for API responses
- [ ] Add rate limiting and retry logic
- [ ] Create manual metadata editing UI
- [ ] Test metadata accuracy with 100+ books

**Acceptance Criteria:**
- ✅ 85%+ correct metadata on first attempt
- ✅ All fetches complete in background (non-blocking)
- ✅ Graceful degradation when APIs unavailable
- ✅ Cached responses for offline operation

### 1.6 WiFi Transfer - HTTP Server

- [ ] Choose HTTP server library (Swifter vs Vapor)
- [ ] Implement HTTPTransferServer singleton
- [ ] Create start() and stop() methods
- [ ] Implement port discovery (find available port)
- [ ] Get local IP address programmatically
- [ ] Generate book list HTML page
- [ ] Create book detail endpoint (/api/books/:id)
- [ ] Create download endpoint (/api/books/:id/download)
- [ ] Implement proper MIME types for formats
- [ ] Add CSS styling for web UI (mobile-friendly)
- [ ] Create QR code for easy connection (Phase 2, but plan for it)
- [ ] Add server status monitoring (is running, errors)
- [ ] Test with Kindle browser
- [ ] Test with Kobo browser
- [ ] Test with iOS Safari
- [ ] Test with Android Chrome
- [ ] Document firewall configuration requirements

**Acceptance Criteria:**
- ✅ Server starts in <1 second
- ✅ Works on Kindle/Kobo browsers
- ✅ Handles 10 concurrent connections
- ✅ File downloads complete successfully
- ✅ Mobile-friendly web UI

### 1.7 Send to Kindle Integration

- [ ] Create SendToKindleService
- [ ] Implement SMTP email sending
- [ ] Add Kindle email validation
- [ ] Support both @kindle.com and @free.kindle.com
- [ ] Implement email credential storage (Keychain)
- [ ] Create settings UI for Kindle email and sender config
- [ ] Handle 50MB file size limit
- [ ] Add automatic format detection (EPUB, PDF supported)
- [ ] Show delivery status/confirmation
- [ ] Test with actual Kindle device
- [ ] Document setup process (approved senders list)
- [ ] Add troubleshooting guide for common issues

**Acceptance Criteria:**
- ✅ Email delivers to Kindle within 2 minutes
- ✅ EPUB files convert automatically (by Amazon)
- ✅ Clear error messages for common failures
- ✅ Credentials stored securely in Keychain

### 1.8 USB Device Detection (macOS)

- [ ] Create USBDeviceManager using IOKit
- [ ] Implement device connection monitoring
- [ ] Identify Kindle devices (vendor/product IDs)
- [ ] Identify Kobo devices
- [ ] Identify Nook devices (if possible)
- [ ] Implement generic e-reader detection
- [ ] Create NSWorkspace volume mount observer
- [ ] Implement device fingerprinting (check for characteristic files)
- [ ] Create transferBook(_:to:) method
- [ ] Implement automatic format conversion before transfer
- [ ] Verify successful transfer before confirmation
- [ ] Add progress tracking for transfers
- [ ] Test with Kindle Paperwhite
- [ ] Test with Kobo Clara
- [ ] Document unsupported devices

**Acceptance Criteria:**
- ✅ 98%+ device detection success rate
- ✅ Detection within 3 seconds of connection
- ✅ Transfer completes without user intervention
- ✅ Correct format conversion for each device type

### 1.9 macOS UI - Grid View

- [ ] Create BookGridViewController (AppKit)
- [ ] Implement NSCollectionView with compositional layout
- [ ] Create BookGridCell view
- [ ] Implement cover image loading (async)
- [ ] Add image caching (Kingfisher or SDWebImage)
- [ ] Create detail view (SwiftUI)
- [ ] Implement drag-and-drop for book import
- [ ] Add context menu (right-click) actions
- [ ] Create toolbar with search, filter, sort options
- [ ] Implement keyboard navigation
- [ ] Add sidebar for filters (authors, series, tags)
- [ ] Create preferences window (SwiftUI)
- [ ] Test scrolling performance (60fps with 5,000 books)
- [ ] Implement selection and multi-selection
- [ ] Add quick actions (space bar preview, delete key)

**Acceptance Criteria:**
- ✅ 60fps scrolling with 5,000+ books
- ✅ Grid loads in <2 seconds
- ✅ Images load progressively (no blocking)
- ✅ Keyboard navigation fully functional
- ✅ Native macOS look and feel

### 1.10 iOS UI - SwiftUI

- [ ] Create LibraryView (main grid)
- [ ] Implement LazyVGrid with adaptive columns
- [ ] Create BookGridItemView
- [ ] Create BookDetailView
- [ ] Implement search with .searchable modifier
- [ ] Add filter menu (toolbar)
- [ ] Create settings view
- [ ] Implement share extension for importing
- [ ] Create file importer (DocumentPicker)
- [ ] Add WiFi transfer status indicator
- [ ] Create onboarding flow (first launch)
- [ ] Test on iPhone SE (small screen)
- [ ] Test on iPhone Pro Max (large screen)
- [ ] Test on iPad (adaptive layout)
- [ ] Optimize for Dark Mode

**Acceptance Criteria:**
- ✅ Smooth scrolling on iPhone SE
- ✅ Adaptive layout for all screen sizes
- ✅ Share extension works from Files app
- ✅ Settings sync via iCloud
- ✅ Supports both Light and Dark Mode

### 1.11 iCloud Sync

- [ ] Configure CloudKit container
- [ ] Set up NSPersistentCloudKitContainer
- [ ] Enable persistent history tracking
- [ ] Configure automatic merge from parent
- [ ] Test sync between macOS and iOS
- [ ] Test conflict resolution
- [ ] Handle remote change notifications
- [ ] Implement sync status indicator
- [ ] Test with poor network conditions
- [ ] Test with airplane mode toggles
- [ ] Document sync limitations (file storage vs metadata)

**Acceptance Criteria:**
- ✅ Changes sync within 30 seconds on good network
- ✅ No data loss during conflicts
- ✅ Works offline with queue of changes
- ✅ Clear sync status feedback to user

### 1.12 File Management

- [ ] Implement watch folders feature
- [ ] Monitor directories for new files (FSEvents)
- [ ] Auto-import new books when detected
- [ ] Respect user's existing file organization
- [ ] Implement managed library mode (optional)
- [ ] Create file organization templates (Author/Title, Genre/Author/Title)
- [ ] Add "move vs copy" option
- [ ] Implement safe file operations (backup before move)
- [ ] Add duplicate detection
- [ ] Support multiple library locations
- [ ] Test with network drives
- [ ] Test with external USB drives
- [ ] Document recommended file organization

**Acceptance Criteria:**
- ✅ Watch folders detect new files within 5 seconds
- ✅ Zero file corruption during operations
- ✅ Duplicate detection works reliably
- ✅ User can revert file organization changes

### 1.13 Testing & Quality Assurance

**Unit Tests:**
- [ ] LibraryService tests (CRUD operations)
- [ ] CalibreConversionService tests
- [ ] MetadataService tests (mock API responses)
- [ ] SearchService tests (performance benchmarks)
- [ ] USBDeviceManager tests (mock devices)
- [ ] Achieve >80% code coverage

**Integration Tests:**
- [ ] End-to-end import workflow
- [ ] Conversion + transfer workflow
- [ ] iCloud sync between devices
- [ ] WiFi transfer (macOS server → iOS client)

**UI Tests:**
- [ ] macOS: Import via drag-and-drop
- [ ] macOS: Search and filter
- [ ] macOS: Device detection and transfer
- [ ] iOS: Share extension import
- [ ] iOS: WiFi transfer

**Performance Tests:**
- [ ] Startup time <3 seconds
- [ ] Library load time <2 seconds (5,000 books)
- [ ] Search response <100ms
- [ ] Conversion time <5 seconds (typical book)
- [ ] Memory usage <200MB baseline

**Acceptance Criteria:**
- ✅ All tests passing
- ✅ Zero critical bugs
- ✅ <10 known minor bugs
- ✅ Performance targets met on target hardware

### 1.14 Beta Testing

- [ ] Create TestFlight builds (iOS)
- [ ] Create notarized builds (macOS)
- [ ] Recruit 50-100 beta testers
- [ ] Create feedback form (Google Forms/Typeform)
- [ ] Set up crash reporting (opt-in)
- [ ] Monitor beta feedback daily
- [ ] Categorize and prioritize bugs
- [ ] Fix critical bugs within 48 hours
- [ ] Weekly beta updates
- [ ] Conduct user interviews (5-10 testers)

**Acceptance Criteria:**
- ✅ 75%+ WiFi transfer success rate (beta feedback)
- ✅ 85%+ conversion success rate
- ✅ <1% crash rate
- ✅ Positive feedback on UI/UX

### 1.15 Documentation

- [ ] Write user guide (getting started)
- [ ] Create WiFi transfer setup guide
- [ ] Document Send to Kindle setup
- [ ] Write troubleshooting guide
- [ ] Create FAQ
- [ ] Document keyboard shortcuts
- [ ] Write contributing guide (for open source)
- [ ] Create code documentation (inline comments)
- [ ] Generate API documentation (DocC)
- [ ] Record demo video (2-3 minutes)
- [ ] Create screenshot library for App Store

**Acceptance Criteria:**
- ✅ New users can set up WiFi transfer without assistance
- ✅ Common issues covered in FAQ
- ✅ All public APIs documented

### 1.16 Release Preparation

- [ ] Update version number (1.0.0)
- [ ] Create release notes
- [ ] Final code review
- [ ] Run all tests (automated + manual)
- [ ] Test on clean macOS install
- [ ] Test on clean iOS install
- [ ] Verify App Store metadata
- [ ] Create App Store screenshots (all sizes)
- [ ] Write App Store description
- [ ] Prepare promotional materials
- [ ] Set up GitHub Releases page
- [ ] Tag release in Git (v1.0.0)
- [ ] Archive and notarize macOS build
- [ ] Submit iOS app to App Store
- [ ] Submit macOS app to App Store (optional - can do direct distribution)
- [ ] Publish on GitHub (make repository public)
- [ ] Announce on social media/forums

**Acceptance Criteria:**
- ✅ All tests passing
- ✅ Zero known critical bugs
- ✅ App Store approval (if submitting)
- ✅ Successful launch without major issues

---

## Phase 2: Intelligence & Polish
**Timeline:** 2-3 months
**Goal:** Add smart features and improve UX

### 2.1 Bonjour Auto-Discovery

- [ ] Create BonjourService class
- [ ] Advertise HTTP server via NetService
- [ ] Implement service discovery (browse for _folio._tcp)
- [ ] Add zero-config connection UI
- [ ] Show discovered servers in iOS app
- [ ] Test on same WiFi network
- [ ] Test across subnets (if router supports)
- [ ] Handle iOS 14+ local network permission
- [ ] Add permission request with clear explanation
- [ ] Document router compatibility

**Acceptance Criteria:**
- ✅ Auto-discovery works 95%+ of the time
- ✅ Connection established without IP address
- ✅ Clear error message when permission denied

### 2.2 QR Code Connection

- [ ] Generate QR code from server URL
- [ ] Display QR code in macOS app
- [ ] Add camera scanner in iOS app (optional - browser can scan)
- [ ] Design beautiful QR code display
- [ ] Test QR scanning with iPhone camera
- [ ] Test with third-party QR readers

**Acceptance Criteria:**
- ✅ QR code scans successfully on first try
- ✅ Direct link to server (no manual typing)
- ✅ Works with built-in iOS camera app

### 2.3 On-Device LLM Integration (macOS)

- [ ] Research and select LLM model (Llama 3.2-3B recommended)
- [ ] Quantize model to 4-bit (reduce size to ~2GB)
- [ ] Bundle model with macOS app (or download on demand)
- [ ] Integrate Apple MLX framework
- [ ] Create LLMMetadataService
- [ ] Implement loadModel() and unloadModel()
- [ ] Create enhanceMetadata(for:) method
- [ ] Design prompt for metadata extraction
- [ ] Parse JSON output from LLM
- [ ] Implement batch processing UI
- [ ] Add "Enhance Library" button
- [ ] Show progress during batch processing
- [ ] Test genre detection accuracy
- [ ] Test tag extraction quality
- [ ] Measure performance (tokens/second)
- [ ] Monitor memory usage (should unload model after use)
- [ ] Add user preference to enable/disable LLM features

**Acceptance Criteria:**
- ✅ 80%+ categorization accuracy
- ✅ Processes 100 books in <30 minutes
- ✅ Memory returns to baseline after processing
- ✅ No thermal throttling on sustained use

### 2.4 Enhanced Search & Filters

- [ ] Add advanced search syntax (title:, author:, tag:)
- [ ] Implement saved searches
- [ ] Create smart collections (dynamic filters)
- [ ] Add date range filters
- [ ] Implement rating system (optional)
- [ ] Add read/unread status
- [ ] Create "Recently Added" filter
- [ ] Create "Recently Opened" filter
- [ ] Improve search ranking algorithm
- [ ] Add search suggestions
- [ ] Test search with 10,000+ books

**Acceptance Criteria:**
- ✅ Advanced search syntax works intuitively
- ✅ Smart collections update in real-time
- ✅ Search results ranked by relevance

### 2.5 Series Management

- [ ] Create series detail view
- [ ] Show series reading order
- [ ] Auto-detect series from metadata
- [ ] Allow manual series assignment
- [ ] Add "next in series" indicator
- [ ] Create series progress tracking
- [ ] Support multiple series per book (rare but exists)

**Acceptance Criteria:**
- ✅ 90%+ series detection accuracy
- ✅ Reading order is correct
- ✅ Easy to find next book in series

### 2.6 Batch Operations

- [ ] Multi-select books (UI)
- [ ] Batch delete
- [ ] Batch metadata refresh
- [ ] Batch tag assignment
- [ ] Batch collection management
- [ ] Batch conversion
- [ ] Show batch operation progress
- [ ] Support undo for batch operations

**Acceptance Criteria:**
- ✅ Can select 100+ books smoothly
- ✅ Batch operations complete reliably
- ✅ Undo works for all batch operations

### 2.7 Reading Statistics

- [ ] Track "last opened" date
- [ ] Track total reading time (estimate from open duration)
- [ ] Create reading history view
- [ ] Show reading streaks
- [ ] Monthly/yearly reading summary
- [ ] Privacy: all stats stored locally only

**Acceptance Criteria:**
- ✅ Statistics accurate and meaningful
- ✅ Beautiful visualizations
- ✅ No performance impact on library

### 2.8 Export & Backup

- [ ] Export library as CSV
- [ ] Export library as JSON
- [ ] Create library backup (metadata + files)
- [ ] Import from backup
- [ ] Schedule automatic backups (optional)
- [ ] Support exporting to Calibre format

**Acceptance Criteria:**
- ✅ Backup completes for 5,000 books in <5 minutes
- ✅ Restore works flawlessly
- ✅ Export compatible with Calibre

### 2.9 Polish & UX Improvements

- [ ] Add keyboard shortcuts reference
- [ ] Improve error messages (more helpful)
- [ ] Add contextual help tips
- [ ] Improve loading states (skeleton screens)
- [ ] Add empty states (beautiful illustrations)
- [ ] Polish animations and transitions
- [ ] Add sound effects (optional, subtle)
- [ ] Improve accessibility (VoiceOver support)
- [ ] Test with real users (UX testing)

**Acceptance Criteria:**
- ✅ App feels polished and professional
- ✅ All interactions are smooth
- ✅ VoiceOver fully functional

### 2.10 Testing & Release

- [ ] Comprehensive testing (same as Phase 1)
- [ ] Beta testing with 200-500 users
- [ ] Performance regression testing
- [ ] Update documentation
- [ ] Create release notes (2.0)
- [ ] Submit to App Store
- [ ] Publish on GitHub

**Acceptance Criteria:**
- ✅ All Phase 2 features working
- ✅ No regressions from Phase 1
- ✅ Positive user feedback

---

## Phase 3: Advanced Features
**Timeline:** Ongoing/iterative
**Goal:** Power user features and community growth

### 3.1 OPDS Protocol Support

- [ ] Implement OPDS feed generation
- [ ] Create acquisition feeds
- [ ] Support OPDS 1.2 spec
- [ ] Test with OPDS readers (Aldiko, KyBook)
- [ ] Document OPDS setup for users

**Acceptance Criteria:**
- ✅ OPDS feeds validate against spec
- ✅ Works with major OPDS readers

### 3.2 WebDAV Server

- [ ] Research WebDAV implementation options
- [ ] Implement WebDAV server (optional alternative to HTTP)
- [ ] Test with Documents by Readdle
- [ ] Test with GoodReader

**Acceptance Criteria:**
- ✅ WebDAV server functional
- ✅ Compatible with major iOS apps

### 3.3 Reading Goals

- [ ] Set annual reading goal (number of books)
- [ ] Track progress toward goal
- [ ] Create reading challenges
- [ ] Gamification elements (badges, streaks)

**Acceptance Criteria:**
- ✅ Goals motivate users (user feedback)
- ✅ Tracking is accurate

### 3.4 Collections & Shelves

- [ ] Create custom collections
- [ ] Add books to collections (many-to-many)
- [ ] Smart collections (rule-based)
- [ ] Collection sharing (export/import)

**Acceptance Criteria:**
- ✅ Collections organize library effectively
- ✅ Smart collections update automatically

### 3.5 Advanced Metadata

- [ ] Custom metadata fields
- [ ] Bulk metadata editing
- [ ] Metadata templates
- [ ] Integration with GoodReads (optional)
- [ ] Integration with LibraryThing (optional)

**Acceptance Criteria:**
- ✅ Power users can customize metadata fully
- ✅ Third-party integrations work reliably

### 3.6 Plugin/Extension API (If Demand Exists)

- [ ] Design plugin architecture
- [ ] Create plugin SDK
- [ ] Document plugin API
- [ ] Create example plugins
- [ ] Set up plugin repository/marketplace

**Acceptance Criteria:**
- ✅ Community creates useful plugins
- ✅ Plugin system is stable and secure

### 3.7 Community Building

- [ ] Active GitHub repository
- [ ] Contributing guide
- [ ] Issue templates
- [ ] Pull request templates
- [ ] Code of conduct
- [ ] Community forum or Discord
- [ ] Regular development updates

**Acceptance Criteria:**
- ✅ Active community contributions
- ✅ Regular releases with community features
- ✅ Healthy project governance

---

## Continuous Tasks (All Phases)

### Maintenance

- [ ] Monitor crash reports (weekly)
- [ ] Review and respond to user feedback (weekly)
- [ ] Triage GitHub issues (daily when active)
- [ ] Update dependencies (monthly)
- [ ] Security updates (as needed, immediately)
- [ ] Performance monitoring (quarterly)

### Marketing & Growth

- [ ] Post development updates (weekly during active dev)
- [ ] Engage with users on social media
- [ ] Write blog posts about development process
- [ ] Create tutorial videos
- [ ] Present at conferences (optional)
- [ ] Seek press coverage (optional)

### Documentation

- [ ] Keep README updated
- [ ] Update technical docs as architecture evolves
- [ ] Maintain changelog
- [ ] Update screenshots for new features
- [ ] Refresh user guides for new releases

---

## Success Metrics Tracking

### Phase 1 Targets

- [ ] 50-100 beta testers
- [ ] 75%+ WiFi transfer success rate
- [ ] 85%+ conversion success rate
- [ ] <1% crash rate
- [ ] <3s startup time
- [ ] <2s library load (5,000 books)
- [ ] <100ms search response

### Phase 2 Targets

- [ ] 200-500 beta testers
- [ ] 85%+ WiFi transfer success rate
- [ ] 90%+ conversion success rate
- [ ] 80%+ LLM categorization accuracy
- [ ] 80%+ user retention (30 days)
- [ ] Net Promoter Score >50

### Phase 3 Targets

- [ ] 1,000+ users
- [ ] 100+ GitHub stars
- [ ] 10+ community contributors
- [ ] 90%+ feature coverage vs Calibre (for common use cases)
- [ ] Active community (forum/Discord)

---

## Risk Mitigation Checklist

### Technical Risks

- [ ] GPL licensing compliance verified (legal review)
- [ ] Calibre bundling strategy validated
- [ ] iOS background limitations documented and UX designed around them
- [ ] iCloud sync tested thoroughly (no data loss)
- [ ] Performance tested on minimum spec hardware
- [ ] Conversion quality benchmarked against Calibre

### Market Risks

- [ ] Value proposition validated with target users
- [ ] Differentiation from Calibre clearly communicated
- [ ] DRM limitations clearly explained in marketing
- [ ] User expectations managed (not a Calibre clone)

### Operational Risks

- [ ] Development timeline realistic (buffer included)
- [ ] Scope creep managed (strict phase boundaries)
- [ ] Community moderation plan (if needed)
- [ ] Sustainability plan (donations, sponsorships)

---

## Launch Checklist

### Pre-Launch (1 week before)

- [ ] Final testing on all supported OS versions
- [ ] All critical bugs fixed
- [ ] Documentation complete
- [ ] Screenshots and demo video ready
- [ ] Press kit prepared
- [ ] Social media accounts created
- [ ] Launch announcement drafted
- [ ] Beta testers informed of launch date

### Launch Day

- [ ] Publish on GitHub (make public)
- [ ] Create GitHub Release (v1.0.0)
- [ ] Submit to App Store (if applicable)
- [ ] Post launch announcement
- [ ] Share on Reddit (r/calibre, r/ebooks, r/macapps)
- [ ] Share on Hacker News
- [ ] Share on Twitter/X
- [ ] Email beta testers
- [ ] Monitor for critical issues

### Post-Launch (1 week after)

- [ ] Respond to all feedback/issues
- [ ] Hot-fix critical bugs (if any)
- [ ] Thank early adopters
- [ ] Collect user testimonials
- [ ] Plan first update (1.1)

---

**End of Release Plan**

Use this document as a living checklist. Update task statuses as you progress, and add new tasks as requirements emerge.

Happy building! 📚✨
