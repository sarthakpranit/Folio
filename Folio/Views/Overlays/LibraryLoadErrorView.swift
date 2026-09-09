//
// LibraryLoadErrorView.swift
// Folio
//
// Shown in place of the library when the Core Data store will not open (#39).
//
// Recovery-first (decision #4): the store file on disk is left completely
// untouched. The user is told what happened, given a way to back the file up,
// and can quit. No automatic reset, no silent fall-through to an empty library.
//

import SwiftUI
import AppKit

/// Full-window recovery screen displayed instead of `ContentView` while
/// `PersistenceController.loadFailure` is set.
struct LibraryLoadErrorView: View {
    let failure: StoreLoadFailure

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Folio couldn’t open your library")
                .font(.title2.weight(.semibold))

            Text("Your library file has not been changed. Reveal it in Finder to make a backup copy, then quit and reopen Folio.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)

            GroupBox {
                Text(failure.message)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(maxWidth: 420)

            HStack(spacing: 12) {
                if failure.storeURL != nil {
                    Button("Reveal Library File in Finder", action: revealInFinder)
                }
                Button("Quit Folio") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 400)
    }

    private func revealInFinder() {
        guard let url = failure.storeURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
