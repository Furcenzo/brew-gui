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
                        "Homebrew sa nenašiel",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Brew GUI hľadá brew v /opt/homebrew/bin a /usr/local/bin.")
                    )
                } else {
                    detail
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConsoleView()
            }
        }
        .navigationTitle(model.fileURL.lastPathComponent + (model.isDirty ? " — upravené" : ""))
        .navigationSubtitle(model.fileURL.deletingLastPathComponent().path(percentEncoded: false))
        .task { await model.refreshAll() }
        .alert("Chyba", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Brewfile sa zmenil na disku", isPresented: $model.externalChangeDetected) {
            Button("Načítať zo súboru", role: .destructive) { model.reloadFile() }
            Button("Prepísať mojimi úpravami", role: .cancel) { model.save() }
        } message: {
            Text("Súbor upravil iný program, ale máte tu ešte neuložené zmeny. Načítaním zo súboru o ne prídete.")
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
                Label("Všetky položky", systemImage: "doc.text")
                    .badge(entries.count)
                    .tag(SidebarItem.brewfile(nil))
                ForEach(kinds, id: \.self) { kind in
                    Label(kind.pluralTitle, systemImage: kind.symbol)
                        .badge(entries.filter { $0.kind == kind }.count)
                        .tag(SidebarItem.brewfile(kind))
                }
                Label("Chýbajúce", systemImage: "exclamationmark.circle")
                    .badge(model.missingEntries.count)
                    .tag(SidebarItem.missing)
            }
            Section("Systém") {
                Label("Synchronizácia", systemImage: "arrow.triangle.2.circlepath")
                    .tag(SidebarItem.sync)
                Label("Aktualizácie", systemImage: "arrow.up.circle")
                    .badge(model.outdated.count)
                    .tag(SidebarItem.outdated)
                Label("Mimo Brewfile", systemImage: "tray")
                    .badge(model.unmanaged.count)
                    .tag(SidebarItem.unmanaged)
                Label("Hľadať balíky", systemImage: "magnifyingglass")
                    .tag(SidebarItem.search)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.loadingInstalled || model.loadingOutdated {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Načítavam stav…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Spoločné prvky

struct StatusBadge: View {
    let status: EntryStatus

    var body: some View {
        switch status {
        case .installed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Nainštalované")
        case .outdated(_, let latest):
            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.orange).help("Zastarané – nová verzia \(latest ?? "?")")
        case .missing:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Nenainštalované")
        case .unknown:
            Image(systemName: "questionmark.circle").foregroundStyle(.secondary).help("Stav neznámy")
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
