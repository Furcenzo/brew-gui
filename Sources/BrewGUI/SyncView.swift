// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import BrewCore
import SwiftUI

struct SyncView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("bundleUpgrade") private var upgradeOnInstall = false
    @State private var preview: CleanupPreview?
    @State private var loadingPreview = false
    @State private var showCleanupSheet = false

    enum PendingAction: Identifiable {
        case check, install, cleanup
        var id: Self { self }
    }

    var body: some View {
        let entries = model.brewfile.entries
        let missing = model.missingEntries
        Form {
            Section {
                LabeledContent("Brewfile", value: model.fileURL.path(percentEncoded: false))
                LabeledContent("Entries", value: "\(entries.count)")
                LabeledContent("Missing on This Mac", value: "\(missing.count)")
                LabeledContent("Installed Outside the Brewfile", value: "\(model.unmanaged.count)")
            } header: {
                Text("Status")
            } footer: {
                if model.externalChangeDetected {
                    Label("Another program changed the Brewfile – it will be overwritten with your changes before syncing.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Brewfile → Mac") {
                actionRow(
                    title: "Check",
                    detail: "brew bundle check – finds out whether everything in the Brewfile is installed.",
                    button: "Check"
                ) { perform(.check) }

                actionRow(
                    title: "Install Missing",
                    detail: "brew bundle install – installs missing taps, formulae, casks and App Store apps.",
                    button: "Install",
                    prominent: true
                ) { perform(.install) }
                Toggle("Also upgrade outdated packages when installing", isOn: $upgradeOnInstall)

                if !missing.isEmpty {
                    DisclosureGroup("Missing Entries (\(missing.count))") {
                        ForEach(missing) { entry in
                            HStack {
                                KindLabel(kind: entry.kind).frame(width: 100, alignment: .leading)
                                Text(entry.name).font(.body.monospaced())
                                Spacer()
                                if entry.kind.isManaged {
                                    Button("Install") { model.install(entry) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }

            Section("Mac → Brewfile") {
                actionRow(
                    title: "Clean Up to Match Brewfile",
                    detail: "brew bundle cleanup – uninstalls everything that isn't in the Brewfile. Shows a preview first.",
                    button: loadingPreview ? "Loading…" : "Preview…",
                    role: .destructive
                ) { perform(.cleanup) }

                actionRow(
                    title: "Export Current State",
                    detail: "brew bundle dump – writes everything installed to a new file.",
                    button: "Export…"
                ) { dump() }

                actionRow(
                    title: "Add Installed Packages to Brewfile",
                    detail: "A list of packages you have installed that are missing from the Brewfile.",
                    button: "Show"
                ) { model.sidebarSelection = .unmanaged }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isBusy)
        .sheet(isPresented: $showCleanupSheet) {
            CleanupSheet(preview: preview ?? CleanupPreview()) {
                model.bundleCleanup()
            }
        }
    }

    private func actionRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        button: LocalizedStringKey,
        prominent: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if prominent {
                Button(button, role: role, action: action).buttonStyle(.borderedProminent)
            } else {
                Button(button, role: role, action: action)
            }
        }
    }

    private func perform(_ action: PendingAction) {
        if model.isDirty { model.save() }
        guard !model.isDirty else { return }
        switch action {
        case .check:
            model.bundleCheck()
            model.consoleExpanded = true
        case .install:
            model.bundleInstall(upgrade: upgradeOnInstall)
            model.consoleExpanded = true
        case .cleanup:
            loadingPreview = true
            Task {
                preview = await model.cleanupPreview()
                loadingPreview = false
                if preview != nil { showCleanupSheet = true }
            }
        }
    }

    private func dump() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Current State")
        panel.nameFieldStringValue = "Brewfile.dump"
        panel.directoryURL = model.fileURL.deletingLastPathComponent()
        panel.showsHiddenFiles = true
        let describe = NSButton(checkboxWithTitle: String(localized: "Add package descriptions as comments"), target: nil, action: nil)
        describe.state = .on
        panel.accessoryView = describe
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL == model.fileURL.standardizedFileURL {
            model.errorMessage = String(localized: "The export would overwrite the open Brewfile. Choose a different file name.")
            return
        }
        model.bundleDump(to: url, describe: describe.state == .on)
        model.consoleExpanded = true
    }
}

struct CleanupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: CleanupPreview
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brewfile Cleanup").font(.title2.bold())
            if preview.isEmpty {
                ContentUnavailableView("Nothing to clean up", systemImage: "sparkles", description: Text("Everything installed is in the Brewfile."))
                    .frame(height: 200)
            } else {
                Text("The following will be uninstalled / removed. This can't be undone (packages can be reinstalled later).")
                    .foregroundStyle(.secondary)
                List {
                    section("Casks", preview.casks)
                    section("Formulae", preview.formulae)
                    section("Taps", preview.taps)
                    section("brew cleanup", preview.other)
                }
                .frame(minHeight: 260)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !preview.isEmpty {
                    Button("Uninstall", role: .destructive) {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding()
        .frame(width: 520)
    }

    @ViewBuilder private func section(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))" as String) {
                ForEach(items, id: \.self) { Text($0).font(.callout.monospaced()) }
            }
        }
    }
}
