//
//  WiFiTransferView.swift
//  Folio
//
//  WiFi Transfer popover with clear IP address display for e-readers
//

import SwiftUI
import FolioCore

struct WiFiTransferView: View {
    @StateObject private var transferServer: HTTPTransferServer
    @StateObject private var bonjourService = BonjourService()
    @State private var qrCodeImage: NSImage?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingDeviceHelp = false
    @State private var showingQRCode = false
    @State private var copiedToClipboard = false

    let libraryService: LibraryService

    init(libraryService: LibraryService) {
        self.libraryService = libraryService
        _transferServer = StateObject(wrappedValue: HTTPTransferServer())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                Divider()

                if transferServer.isRunning {
                    runningServerView
                } else {
                    stoppedServerView
                }

                // Active downloads
                if transferServer.activeDownloads > 0 {
                    activeDownloadsView
                }

                Divider()

                // Quick start instructions
                quickStartInstructions

                // Device-specific help (collapsible)
                deviceHelpSection
            }
            .padding(20)
        }
        .frame(width: 400, height: 650)
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "wifi")
                .font(.title2)
                .foregroundColor(transferServer.isRunning ? .green : .secondary)

            Text("WiFi Transfer")
                .font(.headline)

            Spacer()

            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(transferServer.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(transferServer.isRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundColor(transferServer.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (transferServer.isRunning ? Color.green : Color.gray).opacity(0.15)
        )
        .clipShape(Capsule())
    }

    // MARK: - Running Server View

    private var runningServerView: some View {
        VStack(spacing: 20) {
            // Prominent IP Address Display (for e-readers)
            if let url = transferServer.serverURL {
                VStack(spacing: 12) {
                    Text("Type this address in your e-reader's browser:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    // Large, prominent URL
                    HStack(spacing: 8) {
                        Text(url)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)

                        Button(action: copyToClipboard) {
                            Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.clipboard")
                                .foregroundColor(copiedToClipboard ? .green : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 2)
                            )
                    )
                }
            }

            // QR Code toggle for phones
            VStack(spacing: 8) {
                Button(action: { showingQRCode.toggle() }) {
                    HStack {
                        Image(systemName: "qrcode")
                        Text(showingQRCode ? "Hide QR Code" : "Show QR Code (for phones)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if showingQRCode, let qrImage = qrCodeImage {
                    VStack(spacing: 6) {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 1)

                        Text("Scan with your phone's camera")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Book count
            HStack(spacing: 4) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption)
                Text("\(libraryService.books.count) book\(libraryService.books.count == 1 ? "" : "s") available")
                    .font(.caption)
            }
            .foregroundColor(.secondary)

            // Stop button
            Button(action: stopServer) {
                Label("Stop Server", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private var stoppedServerView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Server is not running")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: startServer) {
                Label("Start Server", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(height: 180)
    }

    private var activeDownloadsView: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.7)

            Text("\(transferServer.activeDownloads) active download\(transferServer.activeDownloads == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Quick Start Instructions

    private var quickStartInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Quick Start", systemImage: "bolt.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                quickStep(number: 1, text: "Make sure your e-reader is on the same WiFi network as this Mac")
                quickStep(number: 2, text: "Open the browser on your e-reader")
                quickStep(number: 3, text: "Type the address shown above exactly as displayed")
                quickStep(number: 4, text: "Tap any book to download it to your device")
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func quickStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .frame(width: 16)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Device Help Section

    private var deviceHelpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { showingDeviceHelp.toggle() }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                    Text("Device-Specific Instructions")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showingDeviceHelp ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if showingDeviceHelp {
                VStack(alignment: .leading, spacing: 14) {
                    // Kindle
                    deviceCard(
                        icon: "flame.fill",
                        iconColor: .orange,
                        name: "Kindle Paperwhite / Kindle",
                        browserPath: "Settings → Experimental Browser (or Web Browser)",
                        tips: [
                            "The Experimental Browser is in the main menu (three dots icon)",
                            "Type the URL carefully - Kindle keyboards can be tricky",
                            "MOBI and AZW3 files work best; EPUB needs conversion first",
                            "Downloaded books appear in your library automatically"
                        ]
                    )

                    // Kobo
                    deviceCard(
                        icon: "book.closed.fill",
                        iconColor: .blue,
                        name: "Kobo",
                        browserPath: "More → Beta Features → Web Browser",
                        tips: [
                            "Kobo natively supports EPUB - no conversion needed!",
                            "Books download directly to your library",
                            "PDF files also work well on Kobo"
                        ]
                    )

                    // USB Alternative
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "cable.connector")
                                .foregroundColor(.green)
                            Text("Alternative: USB Transfer")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }

                        Text("Connect your e-reader via USB cable. It appears as a drive in Finder. Drag books to the 'documents' or 'books' folder on your device.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func deviceCard(icon: String, iconColor: Color, name: String, browserPath: String, tips: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                Text(name)
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            HStack(alignment: .top, spacing: 4) {
                Text("Browser:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(browserPath)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            ForEach(tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(tip)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(iconColor.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func startServer() {
        do {
            transferServer.setBookProvider(libraryService)
            try transferServer.start()

            if let port = transferServer.port as UInt16? {
                try bonjourService.startAdvertising(port: port)
                bonjourService.updateTXTRecord(["books": "\(libraryService.books.count)"])
            }

            if let url = transferServer.serverURL {
                qrCodeImage = QRCodeGenerator.shared.generate(from: url, size: 200)
            }

        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func stopServer() {
        transferServer.stop()
        bonjourService.stopAdvertising()
        qrCodeImage = nil
    }

    private func copyToClipboard() {
        guard let url = transferServer.serverURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)

        copiedToClipboard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedToClipboard = false
        }
    }
}

// MARK: - WiFi Transfer Button

struct WiFiTransferButton: View {
    @State private var isShowingPopover = false
    let libraryService: LibraryService

    var body: some View {
        Button(action: { isShowingPopover.toggle() }) {
            Label("WiFi Transfer", systemImage: "wifi")
        }
        .help("Transfer books to e-readers via WiFi")
        .popover(isPresented: $isShowingPopover, arrowEdge: .bottom) {
            WiFiTransferView(libraryService: libraryService)
        }
    }
}

// MARK: - Preview

#Preview {
    WiFiTransferView(libraryService: LibraryService.shared)
        .frame(width: 400, height: 650)
}
