//
// SortOption.swift
// Folio
//
// Defines the available sorting options for the book library.
// Each option provides an icon for UI display and generates
// the appropriate NSSortDescriptor for Core Data queries.
//
// Sorting Philosophy:
// - Title: Alphabetical using sortTitle (strips "The", "A", "An")
// - Author: By first author's sortName (Last, First)
// - Date Added: Newest first by default
// - Recently Opened: Most recent first, shows reading activity
// - File Size: Largest first, helps find large files
//

import Foundation
import CoreData

enum SortOption: String, CaseIterable, Identifiable {
    case title = "Title"
    case author = "Author"
    case dateAdded = "Date Added"
    case recentlyOpened = "Recently Opened"
    case fileSize = "File Size"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .title: return "textformat"
        case .author: return "person"
        case .dateAdded: return "calendar.badge.plus"
        case .recentlyOpened: return "clock"
        case .fileSize: return "doc"
        }
    }

    /// Default sort direction for each option (used when first selecting the option)
    var defaultAscending: Bool {
        switch self {
        case .title, .author: return true       // A→Z
        case .dateAdded, .recentlyOpened: return false  // newest first
        case .fileSize: return false             // largest first
        }
    }

    func sortDescriptor(ascending: Bool = true) -> NSSortDescriptor {
        switch self {
        case .title:
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .author:
            // Note: Core Data can't sort by to-many relationship directly.
            // In-memory sorting in ContentView.sortBooks() handles this properly.
            // This fallback sorts by sortTitle for fetch request contexts.
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .dateAdded:
            return NSSortDescriptor(keyPath: \Book.dateAdded, ascending: ascending)
        case .recentlyOpened:
            return NSSortDescriptor(keyPath: \Book.lastOpened, ascending: ascending)
        case .fileSize:
            return NSSortDescriptor(keyPath: \Book.fileSize, ascending: ascending)
        }
    }
}
