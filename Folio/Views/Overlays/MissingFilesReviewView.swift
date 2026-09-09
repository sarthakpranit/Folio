//
// MissingFilesReviewView.swift
// Folio
//
// Presented after a library scan finds books whose files it could not locate.
//
// A scan never deletes on its own (#81). Every book listed here still has all
// of its metadata — tags, series, summary, cover, Kindle links. The user keeps
// them or removes them from the library; the files on disk are never touched.
//

import SwiftUI
import CoreData

struct MissingFilesReviewView: View {
    let books: [Book]
    /// Called with the books the user chose to remove (possibly empty).
    let onResolve: ([Book]) -> Void

    @State private var selectedForRemoval: Set<NSManagedObjectID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Some books can’t find their files")
                .font(.title3.weight(.semibold))

            Text("Folio couldn’t locate the files for these books after the last scan — they may have been moved, renamed, or deleted outside Folio. Their details are still here. Check any you want to remove from the library. Files on disk are never touched.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(books, id: \.objectID) { book in
                    Toggle(isOn: binding(for: book)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title ?? "Untitled")
                            if let path = book.fileURL?.path {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 160)

            HStack {
                Button(selectedForRemoval.isEmpty ? "Select All" : "Select None") {
                    if selectedForRemoval.isEmpty {
                        selectedForRemoval = Set(books.map(\.objectID))
                    } else {
                        selectedForRemoval.removeAll()
                    }
                }

                Spacer()

                Button("Keep All") { onResolve([]) }

                Button("Remove Checked") {
                    onResolve(books.filter { selectedForRemoval.contains($0.objectID) })
                }
                .disabled(selectedForRemoval.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 400)
    }

    private func binding(for book: Book) -> Binding<Bool> {
        Binding(
            get: { selectedForRemoval.contains(book.objectID) },
            set: { isOn in
                if isOn {
                    selectedForRemoval.insert(book.objectID)
                } else {
                    selectedForRemoval.remove(book.objectID)
                }
            }
        )
    }
}
