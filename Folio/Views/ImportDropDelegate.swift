//
//  ImportDropDelegate.swift
//  Folio
//
//  Handles drag and drop import of ebook files
//

import SwiftUI
import UniformTypeIdentifiers

/// Drop delegate for importing ebooks via drag and drop
struct ImportDropDelegate: DropDelegate {
    let libraryService: LibraryService
    @Binding var isTargeted: Bool
    var onImportComplete: ((ImportResult) -> Void)?

    /// Supported file types for import
    static let supportedTypes: [UTType] = [
        .epub,
        .pdf,
        UTType(filenameExtension: "mobi") ?? .data,
        UTType(filenameExtension: "azw3") ?? .data,
        UTType(filenameExtension: "cbz") ?? .data,
        UTType(filenameExtension: "cbr") ?? .data,
        UTType(filenameExtension: "fb2") ?? .data,
        .plainText,
        .rtf,
        .folder
    ]

    func validateDrop(info: DropInfo) -> Bool {
        // Accept if any item has a supported type
        return info.hasItemsConforming(to: Self.supportedTypes) ||
               info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        // Get file URLs from drop
        let providers = info.itemProviders(for: [.fileURL])

        guard !providers.isEmpty else { return false }

        Task {
            var urls: [URL] = []

            for provider in providers {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }

            if !urls.isEmpty {
                let result = await libraryService.importBooks(from: urls)
                await MainActor.run {
                    onImportComplete?(result)
                }
            }
        }

        return true
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Drop Overlay View

struct DropOverlayView: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            ZStack {
                Color.accentColor.opacity(0.1)

                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Drop ebooks to import")
                        .font(.title2)
                        .foregroundColor(.primary)

                    Text("EPUB, MOBI, PDF, and more")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(radius: 10)
                )
            }
            .transition(.opacity)
        }
    }
}

// MARK: - File Import Button

struct FileImportButton: View {
    let libraryService: LibraryService
    @State private var showingFilePicker = false
    @State private var importResult: ImportResult?
    @State private var showingResult = false

    var body: some View {
        Button(action: { showingFilePicker = true }) {
            Label("Import Books", systemImage: "plus")
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: ImportDropDelegate.supportedTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    let importResult = await libraryService.importBooks(from: urls)
                    await MainActor.run {
                        self.importResult = importResult
                        self.showingResult = true
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
        .alert("Import Complete", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text(result.summary)
            }
        }
    }
}
