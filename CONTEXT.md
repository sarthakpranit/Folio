# Folio — Domain Glossary

The shared vocabulary for Folio. Definitions only — no implementation detail, no architecture. For where the code is going, see [`docs/architecture-target.md`](docs/architecture-target.md).

When a term here conflicts with how code or a conversation uses a word, the glossary wins or the glossary is wrong — resolve it, don't let both stand.

---

### Book

A single ebook file the user owns, with its metadata (title, authors, ISBN, cover, published date, file size, format, …). One file, one Book. `Dune.epub` and `Dune.mobi` are **two** Books.

### Format

The file type of a Book: `epub`, `mobi`, `azw3`, `pdf`, `cbz`, `cbr`, `fb2`, `rtf`. The canonical list of supported formats has one home (`FolioCore/SupportedFormats`). `txt` is **not** a supported Folio format.

### BookGroup

What the user actually sees in the library — one work, regardless of how many files back it. `Dune.epub` + `Dune.mobi` collapse into one BookGroup showing two format badges. Every book-facing UI surface works with BookGroups, never raw Books.

### Grouping

The rule that turns Books into BookGroups: match by **ISBN** first; fall back to **normalised title** (lowercased, leading article stripped) when ISBN is absent. A Book with neither is its own group.

### primaryBook

The one Book in a BookGroup chosen to represent it visually (cover, metadata) and by default. Chosen by **format priority** — the format Folio considers best for display/metadata among the group's files.

### Author, Series, Tag

Relationship entities a Book can be browsed by. A Book has many Authors and many Tags; it belongs to at most one Series (with a series index). "Series" here is the reading order of related works, not a UI concept.

### Collection

A user-made grouping of Books, like a playlist. **Modelled in Core Data, not surfaced in the UI** — intentional, not abandoned. A contributor will find the entity; it is dormant, awaiting a decision to activate.

### KindleDevice

A saved Kindle destination: a name and an `@kindle.com` email address, optionally marked default. A Book can be associated with several KindleDevices (the record of what has been sent where).

### Library folder

The single user-chosen directory Folio watches. Its access is held across launches by a security-scoped bookmark. Files added or removed there are picked up by a Scan.

### Import

Bringing a Book into the library from a user action — a drag-and-drop, a file-picker selection, or a folder chosen for its contents. Produces new Book records.

### Scan

Folio's own sweep of the Library folder, comparing what's on disk to what's in the library. Distinct from Import: the user doesn't pick files, Folio reconciles.

### Reconciliation

The Scan's decision-making: new files → Import; a Book whose file is gone but a matching file exists elsewhere in the folder → update its path (a **relocation**); a Book whose file cannot be found at all → mark **missing** (never silently deleted).

### Orphan

A Book whose backing file can no longer be located. Surfaced to the user as missing; its metadata, tags, series, and Kindle associations are preserved.

### Transfer (WiFi transfer)

Sending Books to another device over the local network: Folio runs a small HTTP server, the other device opens the URL (or scans the QR code), and downloads. Bonjour advertises the server so devices can discover it. The marquee feature.

### Send to Kindle

Emailing a Book to a KindleDevice's `@kindle.com` address over SMTP. Amazon converts and delivers it. Distinct from Transfer — email, not local network.

### Conversion

Turning a Book from one Format into another, by invoking Calibre's `ebook-convert`. Calibre is an **external, optional** dependency: if it is absent, Conversion (and on-the-fly Kindle Conversion during Transfer) is unavailable, and nothing else is affected.

### Metadata provider

An external source of Book metadata: Open Library and Google Books. Providers are tried in order; the first with a good-enough result wins, or results are merged.

### Confidence

A provider's 0–1 score for how well a metadata result matches what was asked. A high-Confidence match (e.g. an ISBN lookup) may be applied automatically; a low-Confidence match (e.g. a fuzzy title guess from a filename) is offered to the user, not applied silently.

### Provenance

Where a Book's current metadata came from — a filename guess, a Metadata provider, `ebook-meta`, or the user's own edit. The user should be able to tell entered metadata from fetched metadata.

### Security-scoped bookmark

The macOS mechanism that lets a sandboxed app keep access to a user-chosen file or folder across launches. Folio stores one per Book (for the file) and one for the Library folder. Resolving and refreshing them has one home.
