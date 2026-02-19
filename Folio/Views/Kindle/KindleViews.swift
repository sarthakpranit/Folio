//
// KindleViews.swift
// Folio
//
// Views for managing Kindle devices and sending books to Kindle.
//
// Components:
// - AddKindleDeviceView: Form for adding a new Kindle device
// - KindleSettingsView: Settings for SMTP and device management
// - KindleDeviceRow: Row view for a single device
// - SendToKindleView: Sheet for sending a book to Kindle
//
// Key Responsibilities:
// - Configure SMTP email settings for Send to Kindle
// - Manage Kindle device list (add, delete, set default)
// - Handle book sending with progress and error feedback
//

import SwiftUI
import CoreData
import FolioCore

// MARK: - Add Kindle Device View

struct AddKindleDeviceView: View {
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss

    @State private var deviceName = ""
    @State private var kindleEmail = ""
    @State private var isDefault = false
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Kindle Device")
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

            Divider()

            Form {
                Section {
                    TextField("Device Name", text: $deviceName, prompt: Text("e.g., My Kindle Paperwhite"))

                    TextField("Kindle Email", text: $kindleEmail, prompt: Text("yourname@kindle.com"))

                    Toggle("Set as Default Device", isOn: $isDefault)
                }

                Section {
                    Text("Your Kindle email can be found in Amazon Account → Devices → Kindle Settings. Make sure to add your sender email to the approved senders list.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let error = validationError {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text(error)
                        }
                        .foregroundColor(.orange)
                    }
                }
            }
            .formStyle(.grouped)

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Device") {
                    addDevice()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(deviceName.isEmpty || kindleEmail.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }

    private func addDevice() {
        // Validate email
        let email = kindleEmail.lowercased().trimmingCharacters(in: .whitespaces)
        guard email.hasSuffix("@kindle.com") || email.hasSuffix("@free.kindle.com") else {
            validationError = "Invalid Kindle email. Must end with @kindle.com or @free.kindle.com"
            return
        }

        // Create device
        let device = KindleDevice(context: viewContext)
        device.id = UUID()
        device.name = deviceName.trimmingCharacters(in: .whitespaces)
        device.email = email
        device.dateAdded = Date()
        device.isDefault = isDefault

        // If this is default, unset other defaults
        if isDefault {
            let request = KindleDevice.fetchRequest()
            request.predicate = NSPredicate(format: "isDefault == YES AND self != %@", device)
            if let others = try? viewContext.fetch(request) {
                for other in others {
                    other.isDefault = false
                }
            }
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            validationError = "Failed to save device: \(error.localizedDescription)"
        }
    }
}

// MARK: - Kindle Settings View

struct KindleSettingsView: View {
    let viewContext: NSManagedObjectContext
    let kindleDevices: [KindleDevice]
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirmation = false
    @State private var deviceToDelete: KindleDevice?

    // SMTP Configuration
    @State private var selectedProvider: SMTPProvider = .gmail
    @State private var smtpHost: String = ""
    @State private var smtpPort: String = "587"
    @State private var smtpUsername: String = ""
    @State private var smtpPassword: String = ""
    @State private var useTLS: Bool = true
    @State private var isSavingSMTP = false
    @State private var smtpSaveError: String?
    @State private var smtpSaveSuccess = false
    @State private var isConfigured = false

    enum SMTPProvider: String, CaseIterable {
        case gmail = "Gmail"
        case outlook = "Outlook / Hotmail"
        case icloud = "iCloud"
        case custom = "Custom SMTP"

        var host: String {
            switch self {
            case .gmail: return "smtp.gmail.com"
            case .outlook: return "smtp.office365.com"
            case .icloud: return "smtp.mail.me.com"
            case .custom: return ""
            }
        }

        var port: Int {
            switch self {
            case .gmail, .outlook, .icloud: return 587
            case .custom: return 587
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Kindle Settings")
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

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // SMTP Configuration Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.accentColor)
                            Text("Email Settings (for Send to Kindle)")
                                .font(.headline)

                            Spacer()

                            if isConfigured {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("Configured")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }

                        Text("Configure your email account to send books to your Kindle. For Gmail, you'll need an App Password.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Provider picker
                        Picker("Email Provider", selection: $selectedProvider) {
                            ForEach(SMTPProvider.allCases, id: \.self) { provider in
                                Text(provider.rawValue).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedProvider) { newValue in
                            if newValue != .custom {
                                smtpHost = newValue.host
                                smtpPort = String(newValue.port)
                            }
                        }

                        // SMTP fields
                        if selectedProvider == .custom {
                            HStack {
                                TextField("SMTP Host", text: $smtpHost)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Port", text: $smtpPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }

                        TextField("Email Address", text: $smtpUsername)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Password / App Password", text: $smtpPassword)
                            .textFieldStyle(.roundedBorder)

                        if selectedProvider == .gmail {
                            Link(destination: URL(string: "https://myaccount.google.com/apppasswords")!) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.square")
                                    Text("Create Gmail App Password")
                                }
                                .font(.caption)
                            }
                        }

                        Toggle("Use TLS (recommended)", isOn: $useTLS)
                            .font(.subheadline)

                        if let error = smtpSaveError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        if smtpSaveSuccess {
                            Text("Email settings saved successfully!")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        HStack {
                            Button("Save Email Settings") {
                                saveSMTPConfiguration()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(smtpUsername.isEmpty || smtpPassword.isEmpty || isSavingSMTP)

                            if isSavingSMTP {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Kindle Devices Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("Kindle Devices")
                                .font(.headline)
                        }

                        if kindleDevices.isEmpty {
                            VStack(spacing: 8) {
                                Text("No Kindle devices added yet.")
                                    .foregroundColor(.secondary)
                                Text("Add your Kindle's email address to send books.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ForEach(kindleDevices, id: \.objectID) { device in
                                KindleDeviceRow(device: device, viewContext: viewContext) {
                                    deviceToDelete = device
                                    showingDeleteConfirmation = true
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550, height: 550)
        .onAppear {
            loadExistingSMTPConfiguration()
        }
        .alert("Delete Device?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let device = deviceToDelete {
                    viewContext.delete(device)
                    try? viewContext.save()
                }
            }
        } message: {
            Text("This will remove the device from Folio. Books already on the device will not be affected.")
        }
    }

    private func loadExistingSMTPConfiguration() {
        Task {
            let sendService = SendToKindleService.shared
            isConfigured = await sendService.isConfigured

            if let config = await sendService.getSMTPConfiguration() {
                await MainActor.run {
                    smtpHost = config.host
                    smtpPort = String(config.port)
                    smtpUsername = config.username
                    useTLS = config.useTLS

                    // Determine which provider matches
                    if config.host == SMTPProvider.gmail.host {
                        selectedProvider = .gmail
                    } else if config.host == SMTPProvider.outlook.host {
                        selectedProvider = .outlook
                    } else if config.host == SMTPProvider.icloud.host {
                        selectedProvider = .icloud
                    } else {
                        selectedProvider = .custom
                    }
                }
            }
        }
    }

    private func saveSMTPConfiguration() {
        smtpSaveError = nil
        smtpSaveSuccess = false
        isSavingSMTP = true

        let host = selectedProvider == .custom ? smtpHost : selectedProvider.host
        let port = Int(smtpPort) ?? 587

        Task {
            do {
                let config = SendToKindleService.SMTPConfiguration(
                    host: host,
                    port: port,
                    username: smtpUsername,
                    useTLS: useTLS
                )

                try await SendToKindleService.shared.configure(smtp: config, password: smtpPassword)

                await MainActor.run {
                    isSavingSMTP = false
                    smtpSaveSuccess = true
                    isConfigured = true

                    // Clear success message after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        smtpSaveSuccess = false
                    }
                }
            } catch {
                await MainActor.run {
                    isSavingSMTP = false
                    smtpSaveError = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Kindle Device Row

struct KindleDeviceRow: View {
    @ObservedObject var device: KindleDevice
    let viewContext: NSManagedObjectContext
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name ?? "Kindle")
                        .font(.headline)
                    if device.isDefault {
                        Text("Default")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .foregroundColor(.accentColor)
                            .clipShape(Capsule())
                    }
                }

                Text(device.email ?? "No email")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let syncedBooks = device.syncedBooks as? Set<Book> {
                    Text("\(syncedBooks.count) book(s) synced")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                if !device.isDefault {
                    Button {
                        setAsDefault()
                    } label: {
                        Label("Set as Default", systemImage: "star")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Device", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.vertical, 4)
    }

    private func setAsDefault() {
        // Unset other defaults
        let request = KindleDevice.fetchRequest()
        request.predicate = NSPredicate(format: "isDefault == YES")
        if let others = try? viewContext.fetch(request) {
            for other in others {
                other.isDefault = false
            }
        }

        device.isDefault = true
        try? viewContext.save()
    }
}

// MARK: - Send to Kindle View

struct SendToKindleView: View {
    let book: Book
    let kindleDevices: [KindleDevice]
    let viewContext: NSManagedObjectContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDevice: KindleDevice?
    @State private var isSending = false
    @State private var sendResult: String?
    @State private var sendSuccess = false

    /// Checks if the book's format is compatible with Kindle Send to Kindle service
    private var isKindleCompatible: Bool {
        guard let formatString = book.format,
              let format = EbookFormat(rawValue: formatString.lowercased()) else {
            return false
        }
        return format.kindleCompatible
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Send to Kindle")
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

            Divider()

            VStack(spacing: 20) {
                // Book info
                HStack(spacing: 16) {
                    if let coverData = book.coverImageData,
                       let nsImage = NSImage(data: coverData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 60, height: 80)
                            .overlay {
                                Image(systemName: "book.closed")
                                    .foregroundColor(.secondary)
                            }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title ?? "Untitled")
                            .font(.headline)
                            .lineLimit(2)

                        HStack(spacing: 4) {
                            Text(book.format?.uppercased() ?? "")
                                .font(.caption)
                                .foregroundColor(isKindleCompatible ? .secondary : .orange)

                            if !isKindleCompatible {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }

                        Text(ByteCountFormatter.string(fromByteCount: book.fileSize, countStyle: .file))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Format compatibility warning
                if !isKindleCompatible {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Incompatible Format")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Kindle no longer supports \(book.format?.uppercased() ?? "this format"). Supported formats: EPUB, AZW3, KFX, PDF, TXT.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                // Device selection
                if kindleDevices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("No Kindle devices configured")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Picker("Send to", selection: $selectedDevice) {
                        ForEach(kindleDevices, id: \.objectID) { device in
                            Text(device.name ?? "Kindle").tag(device as KindleDevice?)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                // Result message
                if let result = sendResult {
                    HStack {
                        Image(systemName: sendSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(sendSuccess ? .green : .orange)
                        Text(result)
                    }
                    .padding()
                    .background(sendSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSending {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }

                Button("Send") {
                    Task {
                        await sendBook()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedDevice == nil || isSending || !isKindleCompatible)
            }
            .padding()
        }
        .frame(width: 400, height: 400)
        .onAppear {
            selectedDevice = kindleDevices.first(where: { $0.isDefault }) ?? kindleDevices.first
        }
    }

    private func sendBook() async {
        guard let device = selectedDevice,
              let kindleEmail = device.email,
              let fileURL = book.fileURL else { return }

        isSending = true
        sendResult = nil

        let sendService = SendToKindleService.shared

        do {
            let result = try await sendService.send(
                fileURL: fileURL,
                to: kindleEmail,
                bookTitle: book.title ?? "Untitled"
            )

            await MainActor.run {
                sendSuccess = result.success
                sendResult = result.message

                if result.success {
                    // Mark as synced
                    book.addToKindleDevices(device)
                    device.lastSyncDate = Date()
                    try? viewContext.save()
                }
            }
        } catch let error as SendToKindleError {
            await MainActor.run {
                sendSuccess = false
                switch error {
                case .fileTooLarge(let size):
                    sendResult = "File too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Maximum is 50 MB."
                case .invalidKindleEmail(let email):
                    sendResult = "Invalid Kindle email: \(email)"
                case .smtpConfigMissing:
                    sendResult = "SMTP email not configured. Please set up email in settings."
                case .smtpAuthFailed:
                    sendResult = "SMTP authentication failed. Check your email credentials."
                case .sendFailed(let message):
                    sendResult = "Send failed: \(message)"
                }
            }
        } catch {
            await MainActor.run {
                sendSuccess = false
                sendResult = "Error: \(error.localizedDescription)"
            }
        }

        isSending = false
    }
}
