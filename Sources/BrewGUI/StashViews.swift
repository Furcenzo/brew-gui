// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

// MARK: - Stashed

/// Packages kept in the Brewfile as `# stash:` comments – not installed, ignored by `brew bundle`.
struct StashedView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<UUID>()

    var body: some View {
        let entries = model.brewfile.stashedEntries
        let selected = entries.filter { selection.contains($0.id) }
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing is stashed", systemImage: "archivebox")
                } description: {
                    Text("Stash a package you don't need right now: Brew GUI uninstalls it and keeps it in the Brewfile as a comment, so brew bundle doesn't install it again. Right-click an entry in the Brewfile, or use Unused Apps.")
                }
            } else {
                Table(entries, selection: $selection) {
                    TableColumn("Type") { entry in KindLabel(kind: entry.kind) }
                        .width(min: 70, ideal: 90, max: 120)
                    TableColumn("Name") { entry in Text(entry.name).fontWeight(.medium) }
                        .width(min: 120, ideal: 200)
                    TableColumn("Options / Comment") { entry in
                        Text([entry.options, entry.comment.map { "# " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: "  "))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 160)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    let chosen = entries.filter { ids.contains($0.id) }
                    Button("Install") { install(chosen) }
                    Button("Move Back Without Installing") { model.brewfile.unstash(ids: ids); selection.subtract(ids) }
                    Divider()
                    Button("Remove from Brewfile", role: .destructive) { model.removeStashed(ids: ids); selection.subtract(ids) }
                } primaryAction: { ids in
                    install(entries.filter { ids.contains($0.id) })
                }
                .onDeleteCommand {
                    model.removeStashed(ids: selection)
                    selection.removeAll()
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text("Stashed lines start with # stash: in the Brewfile. brew bundle dump rewrites the file; Export Current State in Brew GUI puts them back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    install(selected)
                } label: {
                    Label("Install", systemImage: "arrow.down.circle")
                }
                .disabled(selected.isEmpty || model.isBusy)
                .help("Install the selected packages and make them regular Brewfile entries again")

                Button(role: .destructive) {
                    model.removeStashed(ids: selection)
                    selection.removeAll()
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .disabled(selected.isEmpty)
                .help("Remove the selected lines from the Brewfile")
            }
        }
    }

    private func install(_ entries: [BrewfileEntry]) {
        entries.forEach(model.unstashAndInstall)
        selection.removeAll()
    }
}

// MARK: - Unused apps

/// Apps that haven't been opened for a while, to stash or uninstall.
struct UnusedAppsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("showKeptUnusedApps") private var showKept = false
    @State private var selection: String?
    @State private var pendingStash: UnusedApp?
    @State private var pendingUninstall: UnusedApp?

    var body: some View {
        @Bindable var model = model
        let items = model.unusedApps(days: model.unusedDays, includeKept: showKept)
        let selected = items.first { $0.id == selection }
        Group {
            if !model.usageLoaded {
                ProgressView("Looking for apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("No unused apps", systemImage: "checkmark.seal", description: Text("Every app was opened in the last \(model.unusedDays) days."))
            } else {
                Table(items, selection: $selection) {
                    TableColumn("App") { item in
                        HStack(spacing: 6) {
                            Image(nsImage: FileManager.default.fileExists(atPath: item.app.url.path)
                                ? NSWorkspace.shared.icon(forFile: item.app.url.path)
                                : NSWorkspace.shared.icon(for: .applicationBundle))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(item.app.name).fontWeight(.medium)
                            if item.isKept {
                                Text("kept")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .background(.secondary.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .help(item.app.url.path)
                    }
                    .width(min: 140, ideal: 220)
                    TableColumn("Last Opened") { item in
                        if let date = item.usage.lastUsed {
                            Text(date, format: .dateTime.day().month().year()).monospacedDigit()
                        } else {
                            Text("never").foregroundStyle(.secondary)
                                .help("macOS has no record of this app being opened since it was installed or last updated.")
                        }
                    }
                    .width(min: 90, ideal: 120, max: 160)
                    TableColumn("Installed or Updated") { item in
                        if let date = item.usage.added {
                            Text(date, format: .dateTime.day().month().year()).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 90, ideal: 130, max: 170)
                    TableColumn("Source") { item in sourceLabel(item) }
                        .width(min: 120, ideal: 200)
                    TableColumn("In Brewfile") { item in
                        if let entry = model.brewfileEntry(for: item) {
                            if model.brewfile.entries.contains(where: { $0.id == entry.id }) {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            } else if model.brewfile.isStashed(kind: entry.kind, name: entry.name) {
                                Text("stashed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .width(min: 70, ideal: 90)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let item = items.first(where: { $0.id == id }) {
                        contextMenu(for: item)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text("Based on when macOS last saw the app opened; apps without that record count from when they were installed or updated. Apps that come with macOS are not listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        }
        .task { await model.refreshUsage() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Not Opened For", selection: $model.unusedDays) {
                    ForEach(UnusedApps.dayOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .help("How long an app has to go unopened to be listed")
            }
            ToolbarItemGroup {
                Button {
                    pendingStash = selected
                } label: {
                    Label("Stash", systemImage: "archivebox")
                }
                .disabled(selected.map { $0.source == .other } ?? true || model.isBusy)
                .help("Uninstall the app and keep it in the Brewfile as stashed")

                Button(role: .destructive) {
                    pendingUninstall = selected
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .disabled(selected.map { $0.source == .other } ?? true || model.isBusy)
                .help("Uninstall the app and remove it from the Brewfile")

                Toggle(isOn: $showKept) {
                    Label("Show Kept Apps", systemImage: "eye")
                }
                .help("Also list the apps you chose to keep")

                Button {
                    Task { await model.refreshUsage() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.loadingUsage)
                .help("Scan Applications again")
            }
        }
        .confirmationDialog(
            "Stash \(pendingStash?.app.name ?? "")?",
            isPresented: Binding(get: { pendingStash != nil }, set: { if !$0 { pendingStash = nil } }),
            presenting: pendingStash
        ) { item in
            Button("Uninstall and Stash", role: .destructive) {
                if let entry = model.brewfileEntry(for: item) { model.stash(entry) }
            }
        } message: { _ in
            Text("Brew GUI uninstalls the app and keeps it in the Brewfile as a comment (# stash:), so brew bundle doesn't install it again. You can install it later from Stashed.")
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall?.app.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            presenting: pendingUninstall
        ) { item in
            Button("Uninstall and Remove from Brewfile", role: .destructive) { model.uninstallUnused(item) }
        } message: { _ in
            Text("The app is uninstalled and removed from the Brewfile, including a stashed line.")
        }
    }

    @ViewBuilder private func sourceLabel(_ item: UnusedApp) -> some View {
        switch item.source {
        case .cask(let token):
            Label { Text(verbatim: token).font(.body.monospaced()) } icon: { Image(systemName: EntryKind.cask.symbol) }
                .foregroundStyle(.secondary)
        case .appStore:
            Label("App Store", systemImage: EntryKind.mas.symbol).foregroundStyle(.secondary)
        case .other:
            Text("outside Homebrew").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func contextMenu(for item: UnusedApp) -> some View {
        Button("Open") { NSWorkspace.shared.openApplication(at: item.app.url, configuration: .init()) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.app.url]) }
        if item.source != .other {
            Divider()
            Button("Stash…") { pendingStash = item }
            Button("Uninstall…", role: .destructive) { pendingUninstall = item }
        }
        Divider()
        if item.isKept {
            Button("Don't Keep") { model.setKept(item, false) }
        } else {
            Button("Keep") { model.setKept(item, true) }
                .help("Don't suggest this app any more")
        }
    }
}
