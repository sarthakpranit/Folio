//
//  BookMetadataEditView.swift
//  Folio
//
//  Edit view for manually modifying book metadata.
//  Allows users to update title, authors, series, publisher, ISBN, and summary.
//

import SwiftUI
import CoreData

struct BookMetadataEditView: View {
    let book: Book
    let libraryService: LibraryService
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var authorNames: String = ""
    @State private var seriesName: String = ""
    @State private var seriesIndex: String = ""
    @State private var publisher: String = ""
    @State private var isbn: String = ""
    @State private var summary: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    basicInfoSection
                    seriesSection
                    detailsSection
                    descriptionSection
                    if let error = errorMessage {
                        errorView(error)
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(minWidth: 450, idealWidth: 500, minHeight: 550)
        .onAppear { loadBookData() }
    }

    private var header: some View {
        HStack {
            Text("Edit Metadata")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic Info")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Authors (comma-separated)", text: $authorNames)
                    .textFieldStyle(.roundedBorder)
                Text("Separate multiple authors with commas")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Series")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                TextField("Series Name", text: $seriesName)
                    .textFieldStyle(.roundedBorder)
                TextField("#", text: $seriesIndex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publisher").font(.caption).foregroundColor(.secondary)
                    TextField("Publisher", text: $publisher).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("ISBN").font(.caption).foregroundColor(.secondary)
                    TextField("ISBN", text: $isbn).textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            TextEditor(text: $summary)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(message).foregroundColor(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(action: saveMetadata) {
                if isSaving { ProgressView().scaleEffect(0.7) }
                else { Text("Save") }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || title.isEmpty)
        }
        .padding()
    }

    private func loadBookData() {
        title = book.title ?? ""
        if let authors = book.authors as? Set<Author> {
            authorNames = authors.compactMap { $0.name }.sorted().joined(separator: ", ")
        }
        if let series = book.series {
            seriesName = series.name ?? ""
            if book.seriesIndex > 0 { seriesIndex = String(Int(book.seriesIndex)) }
        }
        publisher = book.publisher ?? ""
        isbn = book.isbn13 ?? book.isbn ?? ""
        summary = book.summary ?? ""
    }

    private func saveMetadata() {
        isSaving = true
        errorMessage = nil
        do {
            let authorList = authorNames.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let repository = BookRepository(context: viewContext)

            try repository.update(book, title: title.isEmpty ? nil : title, authorNames: authorList.isEmpty ? nil : authorList, summary: summary.isEmpty ? nil : summary)
            book.publisher = publisher.isEmpty ? nil : publisher

            if !isbn.isEmpty {
                if isbn.count == 13 { book.isbn13 = isbn }
                else if isbn.count == 10 { book.isbn = isbn }
                else { book.isbn13 = isbn }
            }

            if !seriesName.isEmpty {
                let series = repository.findOrCreateSeries(name: seriesName)
                book.series = series
                if let index = Double(seriesIndex) { book.seriesIndex = index }
            } else {
                book.series = nil
                book.seriesIndex = 0
            }

            try viewContext.save()
            libraryService.refresh()
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            isSaving = false
        }
    }
}
