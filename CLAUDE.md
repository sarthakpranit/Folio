# Working with Claude on Folio
**Best Practices for AI-Assisted Development**

This document provides guidelines for effectively using Claude (or other AI assistants) when developing Folio. Following these practices will help maintain code quality, project consistency, and development velocity.

---

## Table of Contents

1. [Project Context](#project-context)
2. [Session Management](#session-management)
3. [Code Development](#code-development)
4. [Documentation](#documentation)
5. [Testing](#testing)
6. [Architecture Decisions](#architecture-decisions)
7. [Common Workflows](#common-workflows)
8. [What to Ask Claude](#what-to-ask-claude)
9. [What NOT to Ask Claude](#what-not-to-ask-claude)
10. [Quality Checklist](#quality-checklist)

---

## Project Context

### Always Start With Context

When starting a new Claude session, provide essential context:

```
I'm working on Folio, a native macOS/iOS ebook manager.
Current phase: [Phase 1/2/3]
Working on: [specific feature/component]
Last completed: [previous milestone]
```

Or simply use the **`/resume`** command to load context automatically.

### Core Project Principles

Always keep these in mind when asking Claude for help:

1. **Value Proposition:** "The Beautiful Ebook Library for Mac"
2. **WiFi-First:** Wireless transfer is the marquee feature
3. **Simplicity:** Fight feature creep, prioritize UX over features
4. **Native:** Use platform-appropriate technologies (AppKit on macOS, SwiftUI on iOS)
5. **Performance:** Meet targets (<3s startup, <100ms search)
6. **Open Source:** GPL v3, transparent, community-driven

---

## Session Management

### Starting a Session

**Option 1: Use `/resume` command**
```
/resume
```
Claude will read `session-state.md` and provide context on where you left off.

**Option 2: Manual context**
```
I'm resuming work on Folio. Last session I completed [X].
Today I want to work on [Y]. Can you help me get started?
```

### During a Session

**Update progress periodically:**
```
I just completed the LibraryService implementation.
What should I tackle next according to release-plan.md?
```

**Ask for clarification:**
```
The technical-requirements.md mentions using NSFetchedResultsController.
Can you show me how to implement this for the book grid view?
```

### Ending a Session

**Always use `/update-session`** to log progress:
```
/update-session
```

Claude will ask questions to capture:
- What you completed
- Current work in progress
- Any blockers
- Next steps
- Important decisions

This maintains continuity between sessions and prevents context loss.

---

## Code Development

### Requesting Code

**DO:**
```
✅ "Implement the CalibreConversionService.convert() method
   according to technical-requirements.md section 1.3"

✅ "Create unit tests for LibraryService.searchBooks() that
   verify <100ms performance with 5,000 books"

✅ "Refactor BookGridCell to use async image loading with
   Kingfisher, ensuring smooth scrolling"
```

**DON'T:**
```
❌ "Write code for ebook management" (too vague)
❌ "Make it faster" (no context)
❌ "Add all the features" (scope creep)
```

### Code Review

**Ask Claude to review your code:**
```
Here's my implementation of HTTPTransferServer.
Please review for:
1. Performance issues
2. Memory leaks (retain cycles)
3. Error handling completeness
4. SwiftUI/AppKit best practices
5. Alignment with technical-requirements.md
```

### Implementation Guidance

**Reference the technical docs:**
```
I'm implementing the Core Data model from
technical-requirements.md section 1.1. Should I use
NSManagedObject subclasses or @FetchRequest?
```

**Ask about trade-offs:**
```
For image caching, should I use Kingfisher or SDWebImage?
What are the pros/cons for our use case (5,000+ book covers)?
```

---

## Documentation

### Generating Documentation

**DO:**
```
✅ "Generate DocC documentation for LibraryService public API"
✅ "Write inline comments for CalibreConversionService.swift
   explaining the progress parsing logic"
✅ "Create a troubleshooting guide for common WiFi transfer issues"
```

**DON'T:**
```
❌ Don't ask to update PRD/technical docs without reason
❌ Don't generate redundant docs (code should be self-documenting)
```

### Keeping Docs Synchronized

After implementing a feature:
```
I just completed WiFi transfer. Should I update:
1. release-plan.md (mark tasks complete)?
2. session-state.md (log completion)?
3. README.md (update progress)?
```

---

## Testing

### Writing Tests

**Unit Tests:**
```
Write unit tests for searchBooks() that cover:
1. Empty query returns all books
2. Partial match returns correct results
3. Performance <100ms for 5,000 books
4. Special characters handled correctly
5. Case-insensitive matching
```

**Integration Tests:**
```
Create integration test for end-to-end import workflow:
1. User drops EPUB onto app
2. Metadata fetches from Google Books
3. Cover image downloads
4. Book appears in grid
Verify entire flow completes in <10 seconds.
```

### Test Strategy

**Ask about testing approaches:**
```
For testing WiFi transfer, should I:
1. Mock the HTTP server?
2. Run actual server on localhost?
3. Use XCTest network stubbing?
What's best for reliability and maintainability?
```

---

## Architecture Decisions

### Making Decisions

**DO consult Claude for:**
- Architecture patterns (MVVM, MVC, etc.)
- Technology choices (which library to use)
- Performance optimization strategies
- Platform-specific best practices

**Example:**
```
For the book grid on macOS, should I use:
1. NSCollectionView (AppKit) for performance
2. LazyVGrid (SwiftUI) for modern code
3. Hybrid approach

Constraints:
- Need 60fps scrolling with 5,000 books
- Want modern maintainable code
- Target macOS 13+
```

### Document Decisions

After making a decision with Claude's help:
```
We decided to use NSCollectionView for macOS grid
because SwiftUI can't achieve 60fps with large collections.
Please help me add this to session-state.md decision log.
```

---

## Common Workflows

### Implementing a Feature

**Step 1: Understand requirements**
```
I'm starting work on Send to Kindle feature.
Show me the relevant sections from:
1. release-plan.md (tasks)
2. technical-requirements.md (specs)
```

**Step 2: Plan implementation**
```
Based on requirements, break down Send to Kindle into subtasks:
1. Email configuration UI
2. Keychain storage for credentials
3. SMTP email sending
4. Kindle email validation
What order should I implement these?
```

**Step 3: Implement**
```
Let's start with Keychain storage. Show me how to:
1. Save email password securely
2. Retrieve password for sending
3. Handle Keychain errors gracefully
```

**Step 4: Test**
```
Create tests for KeychainService that verify:
1. Save and retrieve work correctly
2. Handles missing entries gracefully
3. Thread-safe (can be called from background)
```

**Step 5: Document**
```
Update session-state.md to mark Send to Kindle as completed,
and add note about Keychain implementation approach.
```

### Debugging an Issue

**Provide context:**
```
Issue: App crashes when importing 100 books at once
Crash log: [paste crash log]
Suspected cause: Memory pressure from loading all covers
Current implementation: [paste relevant code]

Help me debug this.
```

**Ask for solutions:**
```
To fix the memory issue, should I:
1. Lazy load covers (only visible items)
2. Use background thread for import
3. Batch imports (10 books at a time)
4. Reduce cover image quality
Which approach aligns best with our architecture?
```

---

## What to Ask Claude

### ✅ Good Questions

**Architecture & Design:**
- "What's the best way to structure the Core Data model for many-to-many relationships?"
- "Should I use Combine or async/await for networking in this case?"
- "How do I handle background processing without blocking the UI?"

**Implementation Help:**
- "Show me how to implement Bonjour service discovery"
- "How do I parse ebook-convert progress output?"
- "What's the correct way to use NSFetchedResultsController with SwiftUI?"

**Best Practices:**
- "Am I handling errors correctly in this code?"
- "Is this the idiomatic Swift way to do [X]?"
- "How can I optimize this search algorithm?"

**Project-Specific:**
- "What's next according to release-plan.md?"
- "Does this implementation match technical-requirements.md?"
- "Should this feature be in Phase 1 or Phase 2?"

### ❌ Questions to Avoid

**Too Vague:**
- "Make my app better" (no context)
- "Add features" (which features?)
- "Fix the bug" (which bug? what's the symptom?)

**Outside Project Scope:**
- "Should I add blockchain to this?" (scope creep)
- "Can you redesign the entire architecture?" (without good reason)
- "Let's add 50 new features" (violates simplicity principle)

**Better Done Yourself:**
- "Write my entire app" (you should drive)
- "Make all decisions for me" (maintain ownership)
- "Do all the work" (Claude assists, you build)

---

## Quality Checklist

Before committing code reviewed/generated with Claude, verify:

### Code Quality

- [ ] Follows Swift style guidelines
- [ ] Properly documented (DocC comments for public APIs)
- [ ] No force unwraps (`!`) without clear justification
- [ ] Error handling is comprehensive
- [ ] No retain cycles (weak/unowned used appropriately)
- [ ] Thread-safe where needed
- [ ] Performance meets targets (profile if uncertain)

### Project Alignment

- [ ] Implements requirements from technical-requirements.md
- [ ] Matches architecture decisions in session-state.md
- [ ] Doesn't introduce scope creep
- [ ] Maintains "Beautiful Library" UX focus
- [ ] Uses platform-appropriate technologies

### Testing

- [ ] Unit tests written for business logic
- [ ] Integration tests for critical flows
- [ ] Performance tests for speed-sensitive code
- [ ] All tests pass
- [ ] Edge cases covered

### Documentation

- [ ] Inline comments for complex logic
- [ ] DocC documentation for public APIs
- [ ] README updated if user-facing changes
- [ ] session-state.md updated with progress

---

## Advanced Techniques

### Multi-Step Planning

For complex features, ask Claude to create a detailed plan first:

```
I need to implement WiFi transfer HTTP server.
Before writing code, create a detailed implementation plan:

1. List all components needed
2. Identify external dependencies
3. Sequence implementation order
4. Estimate time for each step
5. Highlight potential risks
6. Suggest testing strategy

Then we'll implement step by step.
```

### Incremental Refinement

Don't expect perfect code on first try. Iterate:

```
Round 1: "Create basic LibraryService implementation"
Round 2: "Add error handling to LibraryService"
Round 3: "Optimize LibraryService for large libraries"
Round 4: "Add comprehensive tests"
```

### Code Review Checklist

Ask Claude to review against specific criteria:

```
Review this code for:
1. Swift style guide compliance
2. Memory management (retain cycles, leaks)
3. Thread safety
4. Error handling completeness
5. Performance considerations
6. SwiftUI best practices
7. Alignment with our architecture
Provide specific suggestions for improvement.
```

---

## Session State Management

### Maintaining Context

**Key Files to Reference:**
- `session-state.md` - Current progress and context
- `release-plan.md` - What to build next
- `technical-requirements.md` - How to build it
- `prd.md` - Why we're building it

**In every session:**
1. Start with `/resume` or provide context
2. Reference technical docs when asking questions
3. Update session-state.md when completing milestones
4. End with `/update-session` to log progress

### Decision Log

When you make an important decision with Claude:

```
Decision: Use AppKit for macOS grid view
Rationale: SwiftUI can't achieve 60fps with 5,000 items
Trade-offs: More code, but necessary for performance
Alternatives considered: SwiftUI LazyVGrid, Hybrid approach

Add this to session-state.md decision log.
```

---

## Troubleshooting

### When Claude Gives Incorrect Information

**Claude can hallucinate or be outdated. Always verify:**

1. Check official Apple documentation
2. Test the code yourself
3. Search GitHub/Stack Overflow for real examples
4. Ask Claude to explain its reasoning

**If code doesn't work:**
```
This code gives error [X].
Here's the error message: [paste error]
Can you explain what's wrong and how to fix it?
```

### When You're Stuck

**Ask for debugging help:**
```
I'm stuck on [X]. I've tried:
1. [Attempt 1] - didn't work because [reason]
2. [Attempt 2] - failed with [error]
3. [Attempt 3] - partially works but [issue]

What am I missing?
```

### When You Disagree with Claude

**Claude is a tool, not gospel. You're the decision maker.**

```
You suggested [X], but I think [Y] is better because [reasons].
Am I overlooking something, or is [Y] a valid alternative?
```

---

## Project-Specific Patterns

### Folio Conventions

**File Organization:**
```swift
// Models
FolioCore/Sources/Models/Book.swift

// Services (business logic)
FolioCore/Sources/Services/LibraryService.swift

// Views (UI)
Folio-macOS/Views/BookGridView.swift
Folio-iOS/Views/LibraryView.swift

// Utilities
FolioCore/Sources/Utilities/Extensions/String+Formatting.swift
```

**Naming Conventions:**
```swift
// Services: [Feature]Service
class LibraryService
class MetadataService
class ConversionService

// Views: [Component]View or [Component]ViewController
struct BookGridView: View
class BookGridViewController: NSViewController

// Models: Clear, descriptive names
class Book
class Author
struct BookMetadata
```

**Code Style:**
```swift
// Use clear, descriptive names
func importBooks(from directoryURL: URL) async throws -> Int

// Prefer async/await over completion handlers
func fetchMetadata(for book: Book) async throws -> BookMetadata

// Use guard for early returns
guard let url = book.fileURL else { return }

// Document public APIs
/// Converts an ebook from one format to another
/// - Parameters:
///   - inputURL: Source file location
///   - outputFormat: Target format (mobi, epub, pdf, azw3)
/// - Returns: URL of converted file
func convert(_ inputURL: URL, to outputFormat: String) async throws -> URL
```

---

## Example Sessions

### Session 1: Starting a New Feature

```
User: /resume

Claude: [loads context from session-state.md]
"You last worked on Core Data model.
Next in release-plan.md is LibraryService implementation.
Ready to start?"

User: "Yes, let's implement LibraryService.addBook(from:)"

Claude: [provides implementation based on technical-requirements.md]

User: "Good! Now add error handling for invalid files"

Claude: [adds comprehensive error handling]

User: "Perfect. Create unit tests for this method"

Claude: [creates tests]

User: "/update-session"

Claude: [captures progress, updates session-state.md]
```

### Session 2: Debugging

```
User: "App crashes when searching with empty query.
Here's the crash log: [paste]"

Claude: "The issue is in searchBooks().
You're force-unwrapping a nil predicate.
Here's the fix: [shows fix]"

User: "That worked! Add a test to prevent regression?"

Claude: [creates test for empty query case]
```

### Session 3: Architecture Decision

```
User: "For WiFi transfer, should I use Swifter or Vapor?
We need lightweight HTTP server for Phase 1."

Claude: [compares options with pros/cons]

User: "Let's go with Swifter for simplicity.
Add this decision to session-state.md?"

Claude: [updates decision log with rationale]
```

---

## Final Thoughts

### Claude is a Powerful Tool, But YOU Are the Developer

**Use Claude to:**
- ✅ Speed up implementation
- ✅ Learn best practices
- ✅ Get unstuck quickly
- ✅ Maintain documentation
- ✅ Review code quality

**Don't use Claude to:**
- ❌ Avoid learning fundamentals
- ❌ Make decisions without understanding
- ❌ Blindly copy-paste without comprehension
- ❌ Abdicate responsibility for quality

### Maintain Ownership

You're building Folio, not Claude.

- Understand every line of code
- Make final decisions on architecture
- Own the vision and direction
- Take pride in your work

### Keep Learning

Use Claude as a learning tool:
- Ask "Why?" when you don't understand
- Request explanations, not just code
- Build mental models of how things work
- Gradually rely on Claude less as you gain expertise

---

## Quick Reference

### Essential Commands

- `/resume` - Start session with context
- `/update-session` - End session and log progress

### Key Files

- `prd.md` - Product vision and requirements
- `technical-requirements.md` - Implementation specs
- `release-plan.md` - What to build next
- `session-state.md` - Current progress and decisions
- `CLAUDE.md` - This file (best practices)

### Good Session Flow

1. `/resume` to load context
2. Work on features with Claude's help
3. Test and verify implementation
4. Update documentation
5. `/update-session` to log progress

---

**Happy building! May your code be elegant, your tests comprehensive, and your ebooks beautifully organized.** 📚✨
