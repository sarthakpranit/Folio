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

/// Manages toast-style notifications for user feedback
@MainActor
class ToastNotificationManager: ObservableObject {
    static let shared = ToastNotificationManager()

    @Published var isShowing = false
    @Published var title: String = ""
    @Published var message: String = ""
    @Published var isError: Bool = false

    private var dismissTask: Task<Void, Never>?

    func show(title: String, message: String, isError: Bool = false) {
        self.title = title
        self.message = message
        self.isError = isError
        self.isShowing = true

        // Auto-dismiss after delay
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: isError ? 4_000_000_000 : 3_000_000_000)
            if !Task.isCancelled {
                self.isShowing = false
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        isShowing = false
    }
}
