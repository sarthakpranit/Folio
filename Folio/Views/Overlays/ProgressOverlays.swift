//
// ProgressOverlays.swift
// Folio
//
// Progress indicators and overlays shown during long-running operations
// like book import and format conversion.
//
// Components:
// - ImportProgressBar: Top bar showing import progress with book name
// - ConversionProgressOverlay: Modal overlay for format conversion
//

import SwiftUI

// MARK: - Import Progress Bar

/// A progress bar shown at the top of the window during book import
struct ImportProgressBar: View {
    let progress: Double
    let currentBook: String
    let current: Int
    let total: Int

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.2))

                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)

            // Info bar
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.7)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Importing \(current) of \(total)")
                        .font(.caption)
                        .fontWeight(.medium)

                    Text(currentBook)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

// MARK: - Conversion Progress Overlay

struct ConversionProgressOverlay: View {
    let progress: Double
    let status: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text("Converting...")
                        .font(.headline)
                }
                .progressViewStyle(.linear)
                .frame(width: 300)

                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(40)
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(radius: 20)
        }
    }
}

#Preview("Import Progress") {
    ImportProgressBar(
        progress: 0.45,
        currentBook: "The Great Gatsby.epub",
        current: 5,
        total: 12
    )
}

#Preview("Conversion Overlay") {
    ConversionProgressOverlay(
        progress: 0.67,
        status: "Converting to MOBI..."
    )
}
