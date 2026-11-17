// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

// MARK: - Updates

struct OutdatedView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\OutdatedPackage.name)]

    var body: some View {
        @Bindable var model = model
        let rows = model.outdated.sorted(using: sortOrder)
        Group {
            if !model.outdatedLoaded {
                ProgressView("Checking for outdated packages…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("Everything is up to date", systemImage: "checkmark.seal")
                } description: {
                    Text("Run brew update for the latest information.")
                } actions: {
                    Button("brew update") { model.brewUpdate() }.disabled(model.isBusy)
                }
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Type") { row in
                        KindLabel(kind: row.isCask ? .cask : .brew)
                    }
                    .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Name", value: \.name) { row in
                        HStack(spacing: 4) {
                            Text(row.name).fontWeight(.medium)
                            if row.pinned == true { Image(systemName: "pin.fill").foregroundStyle(.secondary).help("Pinned") }
                        }
                    }
                    TableColumn("Installed Version", value: \.installedVersion) { row in
                        Text(row.installedVersion).monospacedDigit().foregroundStyle(.secondary)
                    }
                    TableColumn("New Version", value: \.currentVersion) { row in
                        Text(row.currentVersion).monospacedDigit().foregroundStyle(.orange)
                    }
                    TableColumn("In Brewfile") { row in
                        if model.brewfile.contains(kind: row.isCask ? .cask : .brew, name: row.name) {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Text("dependency / outside").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 80, ideal: 110)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Upgrade") { model.upgrade(model.outdated.filter { ids.contains($0.id) }) }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.greedyOutdated) {
                    Label("Include Self-Updating Casks", systemImage: "sparkles")
                }
                .help("--greedy: include casks that update themselves")
                .onChange(of: model.greedyOutdated) { Task { await model.refreshOutdated() } }

                Button {
                    model.brewUpdate()
                } label: {
                    Label("brew update", systemImage: "arrow.clockwise")
                }
                .help("Download the latest package information (brew update)")

                Button {
                    model.upgrade(model.outdated.filter { selection.contains($0.id) })
                } label: {
                    Label("Upgrade Selected", systemImage: "arrow.up")
                }
                .disabled(selection.isEmpty)

                Button {
                    model.upgradeAll()
                } label: {
                    Label("Upgrade All", systemImage: "arrow.up.circle")
                }
                .disabled(model.outdated.isEmpty)
            }
        }
        .disabled(model.isBusy)
    }
}

// MARK: - Not in Brewfile

struct UnmanagedView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var pendingUninstall: [UnmanagedItem] = []

    var body: some View {
        let items = model.unmanaged
        Group {
            if items.isEmpty {
                ContentUnavailableView("Everything is in the Brewfile", systemImage: "checkmark.seal", description: Text("Every package installed on request is listed in the Brewfile."))
            } else {
                Table(items, selection: $selection) {
                    TableColumn("Type") { item in KindLabel(kind: item.kind) }
                        .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Name") { item in Text(item.name).fontWeight(.medium) }
                    TableColumn("Description") { item in Text(item.desc ?? "").foregroundStyle(.secondary) }
                    TableColumn("Version") { item in Text(item.version ?? "").monospacedDigit().foregroundStyle(.secondary) }
                        .width(min: 50, ideal: 80, max: 140)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let chosen = items.filter { ids.contains($0.id) }
                    Button("Add to Brewfile") { add(chosen) }
                    Button("Uninstall…", role: .destructive) { pendingUninstall = chosen }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    add(items.filter { selection.contains($0.id) })
                } label: {
                    Label("Add to Brewfile", systemImage: "text.badge.plus")
                }
                .disabled(selection.isEmpty)
                .help("Write the selected items to the Brewfile")

                Button(role: .destructive) {
                    pendingUninstall = items.filter { selection.contains($0.id) }
                } label: {
                    Label("Uninstall", systemImage: "trash")
                }
                .disabled(selection.isEmpty || model.isBusy)
            }
        }
        .confirmationDialog(
            uninstallTitle,
            isPresented: Binding(get: { !pendingUninstall.isEmpty }, set: { if !$0 { pendingUninstall = [] } })
        ) {
            Button("Uninstall", role: .destructive) {
                for item in pendingUninstall { model.uninstall(kind: item.kind, name: item.masID ?? item.name) }
                selection.removeAll()
            }
        } message: {
            Text(pendingUninstall.map(\.name).joined(separator: ", "))
        }
    }

    private var uninstallTitle: Text {
        if pendingUninstall.count == 1 {
            Text("Uninstall \(pendingUninstall[0].name)?")
        } else {
            Text("Uninstall selected items (\(pendingUninstall.count))?")
        }
    }

    private func add(_ items: [UnmanagedItem]) {
        for item in items {
            if item.kind == .mas, let id = item.masID {
                model.add(BrewfileEntry(kind: .mas, name: item.name, options: "id: \(id)"))
            } else {
                model.addToBrewfile(kind: item.kind, name: item.name)
            }
        }
        selection.removeAll()
    }
}

// MARK: - Search

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var selection: SearchResult?
    @FocusState private var searchFocused: Bool

    enum Scope: String, CaseIterable {
        case all, formulae, casks

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .formulae: "Formulae"
            case .casks: "Casks"
            }
        }
    }

    struct SearchResult: Hashable, Identifiable {
        var kind: EntryKind
        var name: String
        var id: String { "\(kind.rawValue):\(name)" }
    }

    var body: some View {
        HSplitView {
            List(results, selection: $selection) { result in
                HStack {
                    Image(systemName: result.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
                    Text(result.name)
                    Spacer()
                    if isInstalled(result) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Installed")
                    }
                    if model.brewfile.contains(kind: result.kind, name: result.name) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary).help("In Brewfile")
                    }
                }
                .tag(result)
            }
            .frame(minWidth: 240, idealWidth: 300)
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search Homebrew", systemImage: "magnifyingglass", description: Text("\(model.allFormulae.count) formulae and \(model.allCasks.count) casks"))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            Group {
                if let selection {
                    PackageInfoView(kind: selection.kind, name: selection.name)
                        .id(selection.id)
                } else {
                    ContentUnavailableView("Select a package", systemImage: "shippingbox")
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Package name")
        .searchFocused($searchFocused)
        .searchScopes($scope) {
            ForEach(Scope.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        // Focus the search field when the page opens, so you can start typing right away.
        .task { searchFocused = true }
    }

    private var results: [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        func match(_ names: [String], _ kind: EntryKind) -> [SearchResult] {
            let exact = names.filter { $0 == q }
            let prefix = names.filter { $0 != q && $0.hasPrefix(q) }
            let contains = names.filter { !$0.hasPrefix(q) && $0.contains(q) }
            return (exact + prefix + contains).map { SearchResult(kind: kind, name: $0) }
        }
        var out: [SearchResult] = []
        if scope != .casks { out += match(model.allFormulae, .brew) }
        if scope != .formulae { out += match(model.allCasks, .cask) }
        if scope == .all {
            // Exact matches and prefixes first, regardless of type.
            out.sort { rank($0.name, q) < rank($1.name, q) }
        }
        return Array(out.prefix(300))
    }

    private func rank(_ name: String, _ q: String) -> Int {
        name == q ? 0 : name.hasPrefix(q) ? 1 : 2
    }

    private func isInstalled(_ result: SearchResult) -> Bool {
        switch result.kind {
        case .brew: model.installed.formula(named: result.name)?.installedVersion != nil
        case .cask: model.installed.cask(named: result.name)?.installed != nil
        default: false
        }
    }
}
