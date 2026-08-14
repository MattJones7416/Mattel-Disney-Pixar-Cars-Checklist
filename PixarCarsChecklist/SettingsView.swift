import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var backupManager: BackupManager

    @AppStorage("devModeEnabled") private var devModeEnabled: Bool = false
    @AppStorage("devCatalogURL") private var devCatalogURL: String = ""

    @State private var showingBackupAlert = false
    @State private var showingRestorePicker = false
    @State private var backupFile: IdentifiableURL?
    @State private var restoreFile: URL?
    @State private var isProcessing = false
    @State private var operationStatus: (isSuccess: Bool, message: String)?
    @State private var showingResetConfirmation = false
    @State private var isRefreshingCatalog = false

    var body: some View {
        NavigationStack {
            Form {
                dataManagementSection
                developerSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .modifier(MacFormStyling())

        // File importer
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [UTType.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                restoreFile = urls.first
            case .failure(let error):
                operationStatus = (false, "Import failed: \(error.localizedDescription)")
            }
        }

        // Create backup alert
        .alert("Create Backup?", isPresented: $showingBackupAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Create") { createBackup() }
        }

        // Restore backup alert (presented when restoreFile is set)
        .alert(
            "Restore Backup?",
            isPresented: Binding(
                get: { restoreFile != nil },
                set: { if !$0 { restoreFile = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) { restoreBackup() }
        } message: {
            Text("""
                 This will restore your collection status, wishlist, photos and notes.
                 Any new cars added since your backup will be preserved.
                 """)
        }

        // Reset confirmation
        .confirmationDialog("Reset All Data?",
                            isPresented: $showingResetConfirmation) {
            Button("Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all your cars, photos, and notes and reload the bundled catalogue. This cannot be undone.")
        }

        // Share/export sheet
        .sheet(item: $backupFile) { file in
            ShareSheet(activityItems: [file.url])
                .onDisappear {
                    operationStatus = (true, "Backup created successfully")
                }
        }

        // Status toast
        .alert(
            operationStatus?.message ?? "",
            isPresented: Binding(
                get: { operationStatus != nil },
                set: { if !$0 { operationStatus = nil } }
            )
        ) { Button("OK") {} }

        // Busy overlay
        .overlay {
            if isProcessing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var dataManagementSection: some View {
        Section("Data Management") {
            if !devModeEnabled {
                Button {
                    guard !isProcessing && !isRefreshingCatalog else { return }
                    isRefreshingCatalog = true
                    Task {
                        let ok = await dataManager.refreshCatalogNow()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (ok, ok ? "Catalog refreshed" : "Refresh failed")
                        }
                    }
                } label: {
                    if isRefreshingCatalog {
                        HStack { ProgressView(); Text("Refreshing Catalog…") }
                    } else {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isProcessing || isRefreshingCatalog)
            } else {
                Text("Use Developer Mode below to refresh from your custom URL or toggle off to restore default.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Button {
                showingBackupAlert = true
            } label: { Label("Create Backup", systemImage: "arrow.up.doc") }
            .disabled(isProcessing)

            Button {
                showingRestorePicker = true
            } label: { Label("Restore Backup", systemImage: "arrow.down.doc") }
            .disabled(isProcessing)

            Button(role: .destructive) {
                showingResetConfirmation = true
            } label: { Label("Reset All Data", systemImage: "trash") }
        }
    }

    @ViewBuilder
    private var developerSection: some View {
        Section("Developer Mode") {
            Toggle(isOn: Binding(get: { devModeEnabled }, set: { newValue in
                if newValue {
                    // Taking a snapshot before entering Developer Mode
                    dataManager.createDeveloperSnapshot()
                    devModeEnabled = true
                } else {
                    // Leaving Developer Mode: restore snapshot and revert to default catalog
                    devModeEnabled = false
                    isRefreshingCatalog = true
                    Task {
                        await dataManager.restoreFromDeveloperSnapshot()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (true, "Restored your collection and default catalog")
                        }
                    }
                }
            })) {
                Text("Enable Developer Mode")
            }
            .disabled(isProcessing || isRefreshingCatalog)

            if devModeEnabled {
                TextField("Custom Catalog JSON URL", text: $devCatalogURL)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.URL)

                Button {
                    guard !isProcessing && !isRefreshingCatalog else { return }
                    isRefreshingCatalog = true
                    Task {
                        let ok = await dataManager.refreshCatalogNow()
                        await MainActor.run {
                            isRefreshingCatalog = false
                            operationStatus = (ok, ok ? "Catalog refreshed from custom URL" : "Refresh failed")
                        }
                    }
                } label: {
                    if isRefreshingCatalog {
                        HStack { ProgressView(); Text("Refreshing Catalog…") }
                    } else {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isProcessing || isRefreshingCatalog || devCatalogURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("About Developer Mode")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text("Developer Mode is a safe sandbox for previewing catalogue changes. Any edits you make while it is on — including notes, photos, unboxed state, favourites, wishlist, and quantities — are temporary. When you turn Developer Mode off, your collection returns to its previous state.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Label("Version 1.0", systemImage: "info.circle")
            Label("Pixar Cars Checklist", systemImage: "car.side.fill")
            Text("An unofficial collector project. Not affiliated with, endorsed by, or sponsored by Mattel, Disney, or Pixar.")
                .font(.footnote)
                .foregroundColor(.secondary)
            Link("Catalogue source", destination: URL(string: "https://dpcarswiki.com/Special:VehicleDatabase")!)
            Link("Data licence (CC BY-SA 4.0)", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
        }
    }

    // MARK: - Actions

    private func createBackup() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            do {
                let file = try await backupManager.createBackup(context: modelContext)
                backupFile = IdentifiableURL(url: file)
            } catch {
                operationStatus = (false, "Backup failed: \(error.localizedDescription)")
            }
        }
    }

    private func restoreBackup() {
        guard let file = restoreFile else { return }
        isProcessing = true
        Task {
            defer {
                isProcessing = false
                restoreFile = nil
            }
            do {
                try await backupManager.restoreBackup(from: file, context: modelContext)
                operationStatus = (true, """
                Restore completed successfully.
                Your collection status, wishlist, photos and notes were restored.
                """)
                await MainActor.run {
                    dataManager.enforceStableIDs()          // optional but safe
                    dataManager.reloadFromPersistentStore()
                }
            } catch {
                operationStatus = (false, "Restore failed: \(error.localizedDescription)")
            }
        }
    }

    private func resetAllData() {
        isProcessing = true
        Task {
            defer { isProcessing = false }
            let success = await dataManager.resetAndReloadData()
            operationStatus = (success, success ? "Data reset successfully" : "Reset failed")
        }
    }
}

// MARK: - Platform styling (keeps #if out of the main body)

private struct MacFormStyling: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS) || targetEnvironment(macCatalyst)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 24)
            .background(Color.white)
        #else
        content
        #endif
    }
}

// MARK: - ShareSheet

#if os(iOS)
import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#else
import AppKit
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let activityItems: [Any]

    var body: some View {
        VStack(spacing: 16) {
            Text("Backup Created").font(.headline)

            if let url = activityItems.first as? URL {
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Copy Path") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(url.path, forType: .string)
                    }
                }
            }
            Button("Close") { dismiss() }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}
#endif

// Helper
struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
