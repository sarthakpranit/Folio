//
// ToastNotificationManager.swift
// Folio
//
// A lightweight toast notification system for user feedback.
// Provides non-intrusive, auto-dismissing notifications for success
// and error states with a clean, native macOS appearance.
//
// Key Features:
// - Singleton pattern for app-wide access
// - Auto-dismissal with configurable timing (3s success, 4s error)
// - Cancellable dismiss tasks for rapid updates
// - SwiftUI-ready with @Published properties
//
// Usage:
//   ToastNotificationManager.shared.show(
//       title: "Import Complete",
//       message: "Added 5 books",
//       isError: false
//   )
//

import SwiftUI
import Combine
import AppKit

/// Manages toast-style notifications for user feedback
@MainActor
class ToastNotificationManager: ObservableObject {
    static let shared = ToastNotificationManager()

    @Published var isShowing = false
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var isError: Bool = false
    @Published var isProgress: Bool = false

    private var dismissTask: Task<Void, Never>?

    func show(title: String, message: String, isError: Bool = false) {
        self.title = title
        self.message = message
        self.isError = isError
        self.isProgress = false
        self.isShowing = true

        dismissTask?.cancel()

        // Keep errors visible until explicitly dismissed so users can inspect/copy details.
        guard !isError else {
            return
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                self.isShowing = false
            }
        }
    }

    func showProgress(title: String, message: String) {
        self.title = title
        self.message = message
        self.isError = false
        self.isProgress = true
        self.isShowing = true

        // Progress toasts stay visible until replaced by success/error toast or dismissed.
        dismissTask?.cancel()
    }

    func dismiss() {
        dismissTask?.cancel()
        isShowing = false
    }

    func copyCurrentToast() {
        let content = [title, message]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard !content.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}
