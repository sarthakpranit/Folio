# Product Requirements Document: Folio - The Beautiful Ebook Library for Mac

## Executive Summary

**The Problem:** Current ebook management tools (primarily Calibre) overwhelm users with complexity while failing at core tasks. Users spend more time fighting the software than reading books.

**The Solution:** The Beautiful Ebook Library for Mac. A native macOS/iOS app that does five things exceptionally well: convert formats, transfer wirelessly to devices, organize books beautifully, manage metadata automatically, and stay out of the user's way.

**Target Users:** Mac users frustrated with Calibre's complexity and dated UI. iPhone users who want seamless ebook management. People who want to read books, not manage software.

**Value Proposition:** "The Beautiful Ebook Library for Mac" - where gorgeous native UI meets powerful ebook management, with WiFi transfer that makes cables obsolete.

**Success Metric:** Users can go from "I just downloaded a book" to "I'm reading it on my device" in under 60 seconds, wirelessly, without thinking about the software.

---

## Technical Decisions (January 2025)

After comprehensive technical analysis, the following architectural decisions have been made:

### Core Technology Choices

**1. Format Conversion Strategy**
- **Decision:** Use Calibre's ebook-convert engine via subprocess calls
- **Rationale:**
  - Proven quality (battle-tested by millions of users)
  - Comprehensive format support (EPUB, MOBI, AZW3, PDF)
  - 85-90% conversion success rate achievable
  - Faster to market (2-3 weeks vs 6-12 months for native implementation)
- **Licensing:** GPL v3 compliance - project will be open source from day 1
- **Performance:** Expect <5 seconds for 70% of typical books

**2. WiFi Transfer as Primary Method**
- **Decision:** WiFi transfer is the marquee feature, not fallback
- **Methods:**
  - HTTP server with web UI (universal - works with any device)
  - Send to Kindle via email (best Kindle experience)
  - Bonjour auto-discovery (Phase 2)
  - OPDS protocol (Phase 3, optional)
- **Rationale:**
  - Solves iOS USB limitation completely
  - More convenient than cables for most workflows
  - Enables true feature parity between macOS and iOS
  - Differentiates from Calibre's USB-first approach

**3. Platform Strategy**
- **macOS:** Primary platform with full capabilities
  - Native AppKit for performance-critical views (grid with 60fps scrolling)
  - SwiftUI for modern UI where appropriate
  - Full USB and WiFi transfer support
- **iOS:** Equal partner with WiFi-enabled feature set
  - Pure SwiftUI (better iOS performance)
  - Full WiFi transfer capabilities (HTTP server + Send to Kindle)
  - Library browsing, reading, metadata management
  - Share extension for importing books
- **Target:** macOS 13+, iOS 16+

**4. On-Device LLMs**
- **Decision:** Phase 2 feature (after core ebook management proven)
- **Scope:**
  - macOS-only initially (memory constraints on iOS)
  - Optional user-initiated background processing
  - Smart categorization, genre detection, series extraction
  - Uses Apple MLX with quantized 3B parameter models
- **Rationale:** Lower initial risk, focus on core value first

**5. Open Source Commitment**
- **Decision:** Full open source project (GPL v3)
- **Rationale:**
  - GPL compliance for Calibre integration
  - Community contributions for device support
  - Transparency builds trust
  - Aligns with "Beautiful Ebook Library" mission

### Revised Positioning

**Not:** "Calibre replacement" or "Works with everything"

**Instead:** "The Beautiful Ebook Library for Mac"
- Best-in-class macOS/iOS experience for DRM-free ebooks
- WiFi-first wireless convenience
- Works beautifully with library books, public domain, and personal collections
- Partner with Calibre, don't compete on features—compete on experience

---

## The Core Problem (Why This Matters)

### What Users Actually Said

Real feedback from Calibre users reveals consistent pain points:

- "Takes 7+ minutes to start, system completely freezes"
- "Crashes constantly during format conversion"
- "My Kindle isn't recognized after updates"
- "Interface looks like Windows 95"
- "I have 1,000+ books and can't find anything"
- "Forces me to organize files its way, not mine"

### The Fundamental Issue

Calibre was built with a "professional librarian" philosophy - comprehensive cataloging, extensive metadata management, advanced editing capabilities. But **most users aren't librarians**. They're readers who need reliability and simplicity.

Current solutions ask users to adapt to the software. We're building software that adapts to users.

---

## Core Features (The Essential 20%)

These five features must work flawlessly, instantly, every time. Everything else is secondary.

### 1. Smart Format Conversion

**What it does:** Converts ebooks between formats (EPUB, MOBI, AZW3, PDF) automatically when needed.

**Why it matters:** Different devices read different formats. This is the #1 pain point causing workflow breakdowns.

**Requirements:**
- Conversion happens transparently - user selects device, software converts automatically
- Maximum 5 seconds for typical ebook conversion
- Preserves formatting, images, and table of contents
- Shows clear progress indicator
- If conversion fails, shows plain-language explanation and suggests fixes
- Batch conversion for multiple books

**Success Criteria:**
- 95%+ conversion success rate on first attempt
- User never needs to think about what format their device needs
- No "memory error" or unexplained crashes

### 2. Universal Device Support

**What it does:** Detects any ebook reader (Kindle, Kobo, Nook, tablets, phones) and transfers books seamlessly.

**Why it matters:** If books can't reach devices, the whole workflow fails. Device recognition is the #2 complaint.

**Requirements:**
- Auto-detect device within 3 seconds of connection
- Transfer books with drag-and-drop OR one-click "Send to Device"
- Automatic format conversion during transfer if needed
- Works with: Kindle (all models), Kobo, Nook, generic Android/iOS readers
- Shows transfer progress with estimated time
- Verifies successful transfer before removing from queue
- Supports wireless transfer via Calibre Content Server or email

**Success Criteria:**
- Device detected 98%+ of the time on first connection
- Transfer completes without user troubleshooting
- Works after device firmware updates without software changes

### 3. Visual Library Browser

**What it does:** Shows your books with covers in a browsable, searchable interface that makes sense to normal humans.

**Why it matters:** Users described Calibre as showing "just a giant list of books." People think visually - they remember covers, not filenames.

**Requirements:**
- Grid view with book covers as primary interface (not tables)
- Instant search-as-you-type across title, author, series
- Filter by: Recently Added, Author, Series, Genre, Read/Unread
- Sort by: Title, Author, Date Added, Date Published
- "Continue Reading" section showing recently opened books
- Responsive design - works on any screen size
- Opens books in default reader with double-click

**Visual Organization:**
```
[Search bar: "Type to find books..."]

Recent Reading:     [Book 1] [Book 2] [Book 3]

Filter: [All ▾] [Author ▾] [Series ▾] [Genre ▾] Sort: [Recent ▾]

[Book Cover] [Book Cover] [Book Cover] [Book Cover]
   Title          Title          Title          Title
   Author         Author         Author         Author

[Book Cover] [Book Cover] [Book Cover] [Book Cover]
   Title          Title          Title          Title
   Author         Author         Author         Author
```

**Success Criteria:**
- Users can find any book in under 10 seconds
- No training required - intuitive on first use
- Loads library of 5,000 books in under 2 seconds

### 4. Automatic Metadata Enhancement

**What it does:** Fetches book covers, descriptions, author info, and publication details automatically, without user intervention.

**Why it matters:** Users want books to look good and be properly identified, but don't want to manually research metadata.

**Requirements:**
- Automatic lookup when book added (using filename, ISBN, or embedded metadata)
- Searches multiple sources: Google Books, Open Library, Amazon (where permitted)
- Downloads high-quality cover images
- Fills in: Title, Author, Series (with position), Publication Date, Description, Genres
- Suggests matches if uncertain - user confirms with one click
- "Refresh Metadata" option for batch updates
- Works offline with cached data

**Success Criteria:**
- 85%+ books get correct metadata on first import
- Runs in background without slowing down the app
- Never blocks user from reading while fetching metadata

### 5. Flexible File Management

**What it does:** Respects however users want to organize their files. Works with existing folder structures.

**Why it matters:** The #1 complaint about Calibre was forcing its own folder structure. Users have existing organizations they don't want disrupted.

**Requirements:**
- Two modes:
  - **Watch Folders:** Point to existing book folders, app indexes them in place
  - **Managed Library:** App organizes books (optional, user choice)
- Never moves files without explicit permission
- Changes are reversible
- Works with cloud storage folders (Dropbox, Google Drive, OneDrive)
- Supports multiple library locations (home, work, external drive)

**Folder Structure Options:**
- User's existing structure (leave as-is)
- Author/Title (if user chooses managed mode)
- Genre/Author/Title (if user chooses managed mode)
- Flat structure (all books in one folder)

**Success Criteria:**
- User can add 1,000 existing books without any files moving
- Switching between managed/unmanaged is one click + confirmation
- No file corruption or data loss during any operation

---

## What We're NOT Building (Intentionally Excluded)

Being clear about what we're not doing is as important as what we are doing.

**Not Included in v1:**
- Built-in ebook editor (users can use external tools)
- Server/sharing functionality (focused on personal use)
- News downloading (out of scope)
- Email-to-device without cloud service
- Plugin architecture (adds complexity)
- Advanced cataloging (Dewey Decimal, etc.)
- DRM removal (legal gray area)
- Audiobook management (different use case)

**Why These Are Excluded:**
Each adds significant complexity that would compromise the core mission: simple, fast, reliable ebook management. Power users who need these features should continue using Calibre or specialized tools.

---

## User Stories (How People Will Use This)

### Story 1: The Frustrated Calibre User
**Name:** Sarah, Teacher, 1,200 books in Calibre

**Current Pain:** "Calibre takes 8 minutes to start. Half the time my Kindle isn't recognized. I spent an hour last week trying to figure out why a book wouldn't convert."

**Using Our Product:**
1. Opens app (2 second startup)
2. Drops EPUB file onto window
3. App fetches cover and metadata automatically (5 seconds)
4. Plugs in Kindle
5. Device appears, shows it needs MOBI format
6. Clicks "Send to Kindle"
7. Book converts and transfers (10 seconds)
8. Reading 30 seconds after starting

**Result:** Total time from download to reading: under 1 minute.

### Story 2: The Simple Reader
**Name:** Marco, Retiree, 200 books, not technical

**Current Pain:** "I don't understand why books are different formats. I just want to read what the library sends me."

**Using Our Product:**
1. Downloads EPUB from library
2. Opens app, drags file in
3. App handles everything automatically
4. Sees book appear with nice cover
5. Connects Kobo reader
6. Clicks the book, then "Send to Device"
7. Reading

**Result:** Never thinks about formats, conversion, or metadata. It just works.

### Story 3: The Large Collection Manager
**Name:** Alex, Student, 3,000+ academic PDFs and ebooks

**Current Pain:** "Calibre can't handle my collection size. It's slow and I can't find anything. The search is useless."

**Using Our Product:**
1. Points app to existing book folders (no importing needed)
2. App indexes in background while Alex continues working
3. Types partial book title in search
4. Results appear instantly as typing
5. Filters by "Added Last Month" to see recent downloads
6. Transfers needed books to tablet for reading

**Result:** Large library stays organized without performance degradation.

---

## Success Metrics (How We Know It's Working)

### Primary Metrics
- **Time to First Read:** Average time from adding a book to reading it on device < 60 seconds
- **Crash Rate:** < 0.1% of operations result in crash or error
- **Device Recognition Rate:** > 98% of device connections work on first attempt
- **User Retention:** 80%+ of users still using after 30 days

### Quality Metrics
- **Conversion Success:** 95%+ of format conversions complete successfully
- **Metadata Accuracy:** 85%+ of books get correct metadata automatically
- **Performance:** App startup < 3 seconds, library of 5,000 books loads < 2 seconds
- **User Satisfaction:** Net Promoter Score > 50

### Behavioral Metrics
- **Support Tickets:** < 5% of users contact support in first month
- **Feature Discovery:** 90%+ of users successfully convert, transfer, and organize within first week
- **Advanced Features:** < 20% of users need features beyond the core five

---

## Technical Requirements

### Performance Targets
- **Startup Time:** < 3 seconds cold start
- **Library Loading:** < 2 seconds for 5,000 books
- **Search Response:** < 100ms to show results
- **Conversion Speed:** < 5 seconds for typical 500KB EPUB
- **Transfer Speed:** Limited only by USB/device speed
- **Memory Usage:** < 200MB RAM baseline

### Platform Support
- **Phase 1:** Windows 10/11, macOS 11+
- **Phase 2:** Linux (Ubuntu, Debian)
- **Future:** iOS/Android companion apps

### File Format Support

**Must Support (Phase 1):**
- EPUB (2.0, 3.0)
- MOBI/AZW3
- PDF
- TXT

**Nice to Have (Phase 2):**
- AZW (older Kindle)
- CBZ/CBR (comics)
- DJVU
- FB2

### Data Storage
- **Library Database:** SQLite (fast, reliable, portable)
- **File Organization:** User's choice (managed or unmanaged)
- **Settings Storage:** JSON config files
- **Cloud Backup:** Optional via user's cloud provider

### Security & Privacy
- **No Telemetry:** Zero data collection unless user opts in
- **Local First:** All processing happens on user's computer
- **No Account Required:** Works completely offline
- **Open Source:** Transparent, auditable code

---

## Development Phases

### Phase 1: WiFi-First MVP (3-4 months)
**Goal:** Deliver "The Beautiful Ebook Library for Mac" with wireless transfer as marquee feature

**macOS App:**
- Core Data library with beautiful grid UI (AppKit + SwiftUI)
- Calibre ebook-convert integration (EPUB, MOBI, AZW3, PDF)
- HTTP server with web UI for wireless transfer
- Send to Kindle via email integration
- USB transfer support (fallback/batch transfers)
- Google Books + Open Library metadata
- Watch folders for library monitoring
- Import existing Calibre libraries
- Visual library browser with covers, search, filters
- Drag-and-drop book import

**iOS App:**
- Pure SwiftUI library browser
- HTTP server for wireless transfer (same as macOS)
- Send to Kindle integration
- Share extension for importing books
- iCloud sync with macOS
- Library browsing, search, filters
- Book preview/info

**Launch Criteria:**
- WiFi transfer works reliably (75%+ success rate)
- Conversion success rate >85%
- Startup time <3 seconds
- Library of 5,000 books loads <2 seconds
- Tested with 50+ beta users
- Crash rate <0.5%
- USB transfer as reliable fallback

**Timeline:** 3-4 months (1 developer)

### Phase 2: Intelligence & Polish (2-3 months)
**Goal:** Add smart features and expand device compatibility

**Features:**
- Bonjour auto-discovery for zero-config WiFi
- QR code connection for easy setup
- On-device LLM metadata enhancement (macOS-only)
  - Smart categorization and genre detection
  - Series extraction and organization
  - Mood/theme tagging
- Advanced search with filters
- Multiple library support
- Series management UI
- Batch conversion with queue
- Enhanced error handling and troubleshooting
- Reading statistics (basic)
- Export/backup tools

**Launch Criteria:**
- WiFi reliability >85%
- LLM categorization accuracy >80%
- Conversion success >90%
- User retention >80% at 30 days

**Timeline:** 2-3 months

### Phase 3: Advanced Features (3+ months)
**Goal:** Serve power users and build community

**Features:**
- OPDS protocol support (reading app ecosystem)
- WebDAV server option
- Reading goals and challenges
- Collections/shelves with smart filters
- Advanced reading statistics
- Custom metadata fields
- Bulk metadata editing
- Plugin/extension API (if demand exists)
- Social features (optional - GoodReads integration)
- Advanced sync options

**Launch Criteria:**
- Feature-complete for 90% of Calibre use cases
- Active community contributions (GitHub)
- Documentation complete
- Plugin ecosystem emerging (if API built)

**Timeline:** Ongoing/iterative

---

## Business Model Considerations

### Open Source Model (Primary)
**License:** GPL v3 (required for Calibre integration)

**Free Forever:**
- All features available to everyone
- No artificial limitations
- Community-driven development
- Transparent, auditable code

**Revenue Options (Optional):**
1. **Donations/Sponsorships:**
   - GitHub Sponsors
   - Patreon for ongoing support
   - One-time donations (Buy Me a Coffee)

2. **Professional Services:**
   - Custom enterprise deployments
   - Priority support contracts
   - Custom feature development

3. **Cloud Services (Optional Premium):**
   - Cloud conversion API for iOS (if demand exists)
   - Cloud sync/backup service
   - Remote library access
   - Pay-as-you-go or subscription

**Why Open Source Works:**
- **Legal:** GPL compliance for Calibre integration
- **Trust:** Transparent ebook management (privacy-sensitive)
- **Community:** Device support contributions
- **Marketing:** "Open source alternative to Calibre"
- **Mission:** Aligns with "Beautiful Library" ethos

### Passive Income Reality Check
- Open source projects rarely generate significant passive income
- This is a passion project first, potential revenue second
- If it solves your pain point, it's already successful
- Community growth and adoption are the primary metrics

---

## Risk Assessment

### Technical Risks
**Risk:** Format conversion quality issues
**Mitigation:** Use proven libraries (epub.js, Pandoc), extensive testing

**Risk:** Device compatibility fragmentation
**Mitigation:** Start with top 3 devices (Kindle, Kobo, generic), expand gradually

**Risk:** Performance with large libraries
**Mitigation:** Database indexing, lazy loading, virtual scrolling

### Market Risks
**Risk:** Calibre is free and feature-rich
**Mitigation:** Compete on simplicity and reliability, not features

**Risk:** Small niche market
**Mitigation:** Target frustrated Calibre users first (proven demand)

**Risk:** Low willingness to pay
**Mitigation:** Freemium model reduces friction, free tier builds trust

### Legal Risks
**Risk:** DRM-related issues
**Mitigation:** Never include DRM removal, clear TOS

**Risk:** Metadata source licensing
**Mitigation:** Use only public APIs (Google Books, Open Library)

---

## Open Questions for User Feedback

1. **Library Import:** Should we automatically import Calibre libraries, or require manual setup?

2. **File Management:** Is "watch folders" (non-destructive) more important than "managed library" (organized)?

3. **Pricing:** Would you prefer subscription ($2.99/month) or one-time purchase ($29.99)?

4. **Mobile Apps:** Should we build iOS/Android apps, or focus on desktop first?

5. **Reading Features:** Do you want built-in reading, or just organization/transfer?

6. **Cloud Sync:** Is syncing libraries across computers important, or do you use one primary computer?

---

## Next Steps

### For Product Development
1. Create clickable prototype of library interface
2. Build proof-of-concept format converter
3. Test device detection with 5-10 popular e-readers
4. User research: Interview 20 frustrated Calibre users
5. Technical spike: Database performance with 10,000+ books

### For Validation
1. Share PRD with Calibre user communities (Reddit, forums)
2. Create landing page describing the vision
3. Collect email signups from interested users (target: 500+)
4. Survey potential users on pricing preferences
5. Build beta waitlist

### For You (Passive Income Goal)
1. Decide: Build yourself, hire developers, or partner?
2. Calculate: Development cost vs. potential revenue
3. Consider: Start with paid tool or build audience first?
4. Alternative: Create complementary tools (Calibre plugins that solve specific pain points)

---

## Appendix: Competitive Analysis

### Calibre
**Strengths:** Free, comprehensive, established user base, active development
**Weaknesses:** Complex UI, poor performance, rigid file management, steep learning curve

**Our Advantage:** Simplicity, speed, flexibility

### Alfa Ebooks Manager
**Strengths:** Better UI than Calibre, Windows-focused
**Weaknesses:** Windows only, less powerful conversion, smaller community

**Our Advantage:** Cross-platform, proven conversion tech

### Kavita / Komga
**Strengths:** Modern web UI, self-hosted
**Weaknesses:** Server setup required, comic-focused, less ebook features

**Our Advantage:** No server setup, ebook-first focus

### Adobe Digital Editions
**Strengths:** Official Adobe tool, DRM support
**Weaknesses:** Outdated, limited formats, poor organization

**Our Advantage:** Modern UI, better organization, format flexibility

---

**Document Version:** 1.0  
**Last Updated:** October 2025  
**Next Review:** After user feedback collection