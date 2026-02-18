//
// BrowseListViews.swift
// Folio
//
// List views for browsing the library by different categories:
// Authors, Series, and Tags. Each view shows a list of items
// that can be selected to filter the main book display.
//
// Components:
// - AuthorListView: Browse all authors in the library
// - SeriesListView: Browse all book series
// - TagListView: Browse all tags with color indicators
// - EmptyLibraryView: Shown when library has no books
//

import SwiftUI

// MARK: - Empty Library View

struct EmptyLibraryView: View {
    let libraryService: LibraryService

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical")
                .font(.system(size: 72))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("Your Library is Empty")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Import your ebooks to get started.\nDrag and drop files or click the button below.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            FileImportButton(libraryService: libraryService)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            VStack(spacing: 4) {
                Text("Supported formats:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("EPUB, MOBI, AZW3, PDF, CBZ, CBR, FB2, TXT, RTF")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(60)
    }
}

// MARK: - Author List View

struct AuthorListView: View {
    let authors: [Author]
    @Binding var selection: SidebarItem?

    var body: some View {
        if authors.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "person.2")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No authors yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Import books to see authors here")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(authors, id: \.objectID) { author in
                Button {
                    selection = .author(author)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(author.name ?? "Unknown")
                                .font(.headline)
                            if let books = author.books as? Set<Book> {
                                Text("\(books.count) book(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Series List View

struct SeriesListView: View {
    let series: [Series]
    @Binding var selection: SidebarItem?

    var body: some View {
        if series.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No series yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Add books to series to see them here")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(series, id: \.objectID) { s in
                Button {
                    selection = .singleSeries(s)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(s.name ?? "Unknown")
                                .font(.headline)
                            if let books = s.books as? Set<Book> {
                                Text("\(books.count) book(s)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tag List View

struct TagListView: View {
    let tags: [Tag]
    @Binding var selection: SidebarItem?

    var body: some View {
        if tags.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "tag")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("No tags yet")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Text("Add tags to books to organize them")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        } else {
            List(tags, id: \.objectID) { tag in
                Button {
                    selection = .tag(tag)
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(hex: tag.color ?? "#007AFF") ?? .accentColor)
                            .frame(width: 12, height: 12)

                        Text(tag.name ?? "Unknown")
                            .font(.headline)

                        Spacer()

                        if let books = tag.books as? Set<Book> {
                            Text("\(books.count)")
                                .foregroundColor(.secondary)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
