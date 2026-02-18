//
// ToastView.swift
// Folio
//
// A beautiful, animated toast notification component following Apple HIG.
// Displays success or error messages with smooth slide-up animation
// and a dismissible close button.
//
// Design:
// - Uses ultraThinMaterial for native macOS frosted glass effect
// - Green checkmark for success, orange warning for errors
// - Subtle shadow for depth
// - Spring animation for natural feel
//
// Usage:
//   ToastView(manager: ToastNotificationManager.shared)
//       .frame(maxWidth: .infinity, maxHeight: .infinity)
//

import SwiftUI

struct ToastView: View {
    @ObservedObject var manager: ToastNotificationManager

    var body: some View {
        if manager.isShowing {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: manager.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(manager.isError ? .orange : .green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.title)
                            .font(.headline)
                        Text(manager.message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        manager.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3), value: manager.isShowing)
        }
    }
}
