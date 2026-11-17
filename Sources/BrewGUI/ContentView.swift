// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            Group {
                if model.client == nil {
                    ContentUnavailableView(
                        "Homebrew not found",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Brew GUI looks for brew in /opt/homebrew/bin and /usr/local/bin.")
                    )
                } else {
                    detail
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConsoleView()
            }
        }
        .navigationTitle(model.isDirty ? String(localized: "\(model.fileURL.lastPathComponent) — edited") : model.fileURL.lastPathComponent)
        .navigationSubtitle((model.filePath as NSString).deletingLastPathComponent + "/")
        .task { await model.refreshAll() }
        .alert("Error", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("The Brewfile changed on disk", isPresented: $model.externalChangeDetected) {
            Button("Load from File", role: .destructive) { model.reloadFile() }
            Button("Overwrite with My Changes", role: .cancel) { model.save() }
        } message: {
            Text("Another program modified the file, but you still have unsaved changes here. Loading from the file will discard them.")
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager.map(ObjectIdentifier.init)) { model.undoManager = undoManager }
    }

    @ViewBuilder private var detail: some View {
        switch model.sidebarSelection ?? .brewfile(nil) {
        case .brewfile(let kind): BrewfileView(kindFilter: kind, missingOnly: false)
        case .missing: BrewfileView(kindFilter: nil, missingOnly: true)
        case .sync: SyncView()
        case .outdated: OutdatedView()
        case .unmanaged: UnmanagedView()
        case .search: SearchView()
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let entries = model.brewfile.entries
        let kinds = EntryKind.allCases.filter { kind in entries.contains { $0.kind == kind } }

        List(selection: $model.sidebarSelection) {
            Section("Brewfile") {
                Label("All Entries", systemImage: "doc.text")
                    .badge(entries.count)
                    .tag(SidebarItem.brewfile(nil))
                ForEach(kinds, id: \.self) { kind in
                    Label(kind.pluralTitle, systemImage: kind.symbol)
                        .badge(entries.filter { $0.kind == kind }.count)
                        .tag(SidebarItem.brewfile(kind))
                }
                Label("Missing", systemImage: "exclamationmark.circle")
                    .badge(model.missingEntries.count)
                    .tag(SidebarItem.missing)
            }
            Section("System") {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarItem.sync)
                Label("Updates", systemImage: "arrow.up.circle")
                    .badge(model.outdated.count)
                    .tag(SidebarItem.outdated)
                Label("Not in Brewfile", systemImage: "tray")
                    .badge(model.unmanaged.count)
                    .tag(SidebarItem.unmanaged)
                Label("Search Packages", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.loadingInstalled || model.loadingOutdated {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading status…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Shared components

struct StatusBadge: View {
    let status: EntryStatus

    var body: some View {
        switch status {
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
        case .outdated(_, let latest):
            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange).help("Outdated – new version \(latest ?? "?")")
        case .missing:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Not installed")
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Status unknown")
        }
    }
}

struct KindLabel: View {
    let kind: EntryKind

    var body: some View {
        Label(kind.title, systemImage: kind.symbol)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
    }
}
