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
// - Author: Currently uses sortTitle (future: author.sortName)
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

    func sortDescriptor(ascending: Bool = true) -> NSSortDescriptor {
        switch self {
        case .title:
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .author:
            return NSSortDescriptor(keyPath: \Book.sortTitle, ascending: ascending)
        case .dateAdded:
            return NSSortDescriptor(keyPath: \Book.dateAdded, ascending: !ascending)
        case .recentlyOpened:
            return NSSortDescriptor(keyPath: \Book.lastOpened, ascending: !ascending)
        case .fileSize:
            return NSSortDescriptor(keyPath: \Book.fileSize, ascending: !ascending)
        }
    }
}
