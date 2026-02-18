//
// SidebarView.swift
// Folio
//
// The SidebarView provides navigation for the library, organizing content
// into logical sections: Library (all books, recent), Browse (authors, series, tags),
// Kindle Devices, and Formats.
//
// Key Responsibilities:
// - Display book counts via badges
// - Handle sidebar selection state
// - Show Kindle devices with sync status
// - Dynamically list formats present in library
//
// Usage:
//   SidebarView(
//       libraryService: libraryService,
//       selection: $selectedSidebarItem,
//       kindleDevices: Array(kindleDevices)
//   )
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var libraryService: LibraryService
    @Binding var selection: SidebarItem?
    var kindleDevices: [KindleDevice]

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Books", systemImage: "books.vertical")
                    .badge(libraryService.books.count)
                    .tag(SidebarItem.allBooks)

                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarItem.recentlyAdded)

                Label("Recently Opened", systemImage: "book")
                    .tag(SidebarItem.recentlyOpened)
            }

            Section("Browse") {
                Label("Authors", systemImage: "person.2")
                    .badge(libraryService.authors.count)
                    .tag(SidebarItem.authors)

                Label("Series", systemImage: "text.book.closed")
                    .badge(libraryService.series.count)
                    .tag(SidebarItem.series)

                Label("Tags", systemImage: "tag")
                    .badge(libraryService.tags.count)
                    .tag(SidebarItem.tags)
            }

            if !kindleDevices.isEmpty {
                Section("Kindle Devices") {
                    ForEach(kindleDevices, id: \.objectID) { device in
                        HStack {
                            Label(device.name ?? "Kindle", systemImage: "flame")
                            if device.isDefault {
                                Spacer()
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                        }
                        .badge((device.syncedBooks as? Set<Book>)?.count ?? 0)
                        .tag(SidebarItem.kindleDevice(device))
                    }
                }
            }

            if !libraryService.statistics.formatCounts.isEmpty {
                Section("Formats") {
                    ForEach(Array(libraryService.statistics.formatCounts.keys.sorted()), id: \.self) { format in
                        Label(format.uppercased(), systemImage: formatIcon(for: format))
                            .badge(libraryService.statistics.formatCounts[format] ?? 0)
                            .tag(SidebarItem.format(format))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Folio")
    }

    private func formatIcon(for format: String) -> String {
        switch format.lowercased() {
        case "epub": return "doc.richtext"
        case "pdf": return "doc.text"
        case "mobi", "azw3": return "doc.plaintext"
        case "cbz", "cbr": return "photo.on.rectangle"
        default: return "doc"
        }
    }
}

#Preview {
    SidebarView(
        libraryService: LibraryService.shared,
        selection: .constant(.allBooks),
        kindleDevices: []
    )
}
