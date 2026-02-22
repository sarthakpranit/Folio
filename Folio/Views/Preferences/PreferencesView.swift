//
//  PreferencesView.swift
//  Folio
//
//  General preferences for the Folio app.
//  Includes library settings, import behavior, and appearance options.
//

import SwiftUI

struct PreferencesView: View {
    // MARK: - Appearance Settings
    @AppStorage("gridItemMinSize") private var gridItemMinSize: Double = 150
    @AppStorage("defaultViewMode") private var defaultViewMode: String = "grid"

    // MARK: - Import Settings
    @AppStorage("autoFetchMetadata") private var autoFetchMetadata: Bool = true
    @AppStorage("duplicateStrategy") private var duplicateStrategy: String = "skip"

    // MARK: - Metadata Settings
    @AppStorage("preferredMetadataSource") private var preferredMetadataSource: String = "googleBooks"

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            importTab
                .tabItem {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
        }
        .frame(width: 450, height: 350)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker("Default View Mode", selection: $defaultViewMode) {
                    Text("Grid").tag("grid")
                    Text("Table").tag("table")
                }
                .pickerStyle(.segmented)

                Text("Choose how books are displayed by default")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Display")
            }

            Section {
                Picker("Preferred Metadata Source", selection: $preferredMetadataSource) {
                    Text("Google Books").tag("googleBooks")
                    Text("Open Library").tag("openLibrary")
                }

                Text("This source will be tried first when fetching metadata")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Metadata")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Import Tab

    private var importTab: some View {
        Form {
            Section {
                Toggle("Automatically fetch metadata on import", isOn: $autoFetchMetadata)

                Text("When enabled, Folio will search for book metadata when importing new files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Metadata")
            }

            Section {
                Picker("When importing duplicates", selection: $duplicateStrategy) {
                    Text("Skip").tag("skip")
                    Text("Replace existing").tag("replace")
                    Text("Keep both").tag("keepBoth")
                }

                VStack(alignment: .leading, spacing: 4) {
                    duplicateStrategyDescription
                }
            } header: {
                Text("Duplicate Handling")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var duplicateStrategyDescription: some View {
        Group {
            switch duplicateStrategy {
            case "skip":
                Text("Duplicate files will be ignored during import")
            case "replace":
                Text("Existing books will be replaced with the new file")
            case "keepBoth":
                Text("Both versions will be kept in your library")
            default:
                Text("Choose how to handle duplicate imports")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Grid Item Size")
                        Spacer()
                        Text("\(Int(gridItemMinSize))px")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $gridItemMinSize, in: 100...300, step: 25) {
                        Text("Size")
                    }

                    HStack {
                        Text("Smaller")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Larger")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Grid View")
            }

            Section {
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Actions

    private func resetToDefaults() {
        gridItemMinSize = 150
        defaultViewMode = "grid"
        autoFetchMetadata = true
        duplicateStrategy = "skip"
        preferredMetadataSource = "googleBooks"
    }
}

#Preview {
    PreferencesView()
}
