# Folio

**The Beautiful Ebook Library for Mac**

Manage your ebooks with a gorgeous interface and transfer wirelessly to your devices. No cables, no complexity.

[![Status](https://img.shields.io/badge/status-Phase%201%20Complete-brightgreen.svg)]()
[![License](https://img.shields.io/badge/license-GPL%20v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)]()

---

## The Problem

Calibre is powerful but overwhelming. You just want to organize your ebooks and send them to your Kindle—without fighting complicated software.

## The Solution

**Folio:** Beautiful native macOS app that does the essentials perfectly.

- 🎨 Beautiful grid-based library interface
- 📡 WiFi transfer to any device via browser
- 📧 Send to Kindle via email with format conversion
- 🧠 Automatic covers and metadata from Google Books
- 📚 Smart grouping of same book in multiple formats
- 🔒 Private, open source, completely free

---

## Features

### Implemented (Phase 1)

| Feature | Status |
|---------|--------|
| **Book Management** | ✅ |
| Import EPUB, MOBI, PDF, AZW3, CBZ/CBR | ✅ |
| Drag & drop import | ✅ |
| Grid view with cover images | ✅ |
| Sort by title, author, date added, file size | ✅ |
| Multi-select with Cmd+A support | ✅ |
| Same book format grouping (EPUB + MOBI = 1 item) | ✅ |
| **Metadata** | ✅ |
| Auto-fetch from Google Books API | ✅ |
| Cover images, authors, series, tags | ✅ |
| Detailed book info view | ✅ |
| **Organization** | ✅ |
| Browse by Author, Series, Tags, Format | ✅ |
| Search across library | ✅ |
| Recently Added / Recently Opened views | ✅ |
| **Wireless Transfer** | ✅ |
| Built-in HTTP server | ✅ |
| Mobile-friendly web interface | ✅ |
| Download books to any device via browser | ✅ |
| **Kindle Integration** | ✅ |
| Send to Kindle via email | ✅ |
| Multiple Kindle device support | ✅ |
| SMTP email configuration | ✅ |
| Auto-select best format (MOBI > AZW3 > EPUB) | ✅ |
| **Format Conversion** | ✅ |
| Convert between EPUB, MOBI, PDF, AZW3 | ✅ |
| Powered by Calibre ebook-convert | ✅ |

### Planned (Phase 2+)

- iOS app with sync
- USB transfer support
- Bonjour device discovery
- Collections and smart folders
- Reading progress sync

---

## Key Use Cases

### Library Books → Kindle
Download from Libby/OverDrive → Import to Folio → One-click "Send to Kindle" → Reading in 60 seconds

### Public Domain Books → Any Device
Download EPUBs → Folio organizes with covers → Transfer wirelessly via browser → Done

### Format Conversion
Have an EPUB, need MOBI? Folio converts automatically when sending to Kindle.

### Multiple Formats, One View
Have the same book in EPUB and MOBI? Folio groups them as one item, showing all format badges.

---

## Requirements

- macOS 13.0 or later
- [Calibre](https://calibre-ebook.com/) (for format conversion)
- For Send to Kindle: Gmail or SMTP email account

---

## Building from Source

```bash
git clone https://github.com/sarthakpranit/Folio.git
cd Folio
open Folio.xcodeproj
```

Build and run with Xcode 15+.

---

## Notes

- Works with **DRM-free ebooks only** (library books, public domain, personal files)
- Uses Calibre's conversion engine (proven quality)
- GPL v3 licensed

---

<p align="center">
⭐ Star to follow progress • Made with ❤️ for readers
</p>
