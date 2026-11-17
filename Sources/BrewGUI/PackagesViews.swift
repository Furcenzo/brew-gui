// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

// MARK: - Aktualizácie

struct OutdatedView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\OutdatedPackage.name)]

    var body: some View {
        @Bindable var model = model
        let rows = model.outdated.sorted(using: sortOrder)
        Group {
            if !model.outdatedLoaded {
                ProgressView("Zisťujem zastarané balíky…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("Všetko je aktuálne", systemImage: "checkmark.seal")
                } description: {
                    Text("Pre najnovšie informácie spustite brew update.")
                } actions: {
                    Button("brew update") { model.brewUpdate() }.disabled(model.isBusy)
                }
            } else {
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Typ") { row in
                        KindLabel(kind: row.isCask ? .cask : .brew)
                    }
                    .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Názov", value: \.name) { row in
                        HStack(spacing: 4) {
                            Text(row.name).fontWeight(.medium)
                            if row.pinned == true { Image(systemName: "pin.fill").foregroundStyle(.secondary).help("Pinned") }
                        }
                    }
                    TableColumn("Nainštalovaná", value: \.installedVersion) { row in
                        Text(row.installedVersion).monospacedDigit().foregroundStyle(.secondary)
                    }
                    TableColumn("Nová", value: \.currentVersion) { row in
                        Text(row.currentVersion).monospacedDigit().foregroundStyle(.orange)
                    }
                    TableColumn("V Brewfile") { row in
                        if model.brewfile.contains(kind: row.isCask ? .cask : .brew, name: row.name) {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Text("závislosť / mimo").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 80, ideal: 110)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Upgradovať") { model.upgrade(model.outdated.filter { ids.contains($0.id) }) }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $model.greedyOutdated) {
                    Label("Aj samoaktualizujúce sa casks", systemImage: "sparkles")
                }
                .help("--greedy: zahrnúť casks, ktoré sa aktualizujú samé")
                .onChange(of: model.greedyOutdated) { Task { await model.refreshOutdated() } }

                Button {
                    model.brewUpdate()
                } label: {
                    Label("brew update", systemImage: "arrow.clockwise")
                }
                .help("Stiahnuť najnovšie informácie o balíkoch (brew update)")

                Button {
                    model.upgrade(model.outdated.filter { selection.contains($0.id) })
                } label: {
                    Label("Upgradovať vybrané", systemImage: "arrow.up")
                }
                .disabled(selection.isEmpty)

                Button {
                    model.upgradeAll()
                } label: {
                    Label("Upgradovať všetko", systemImage: "arrow.up.circle")
                }
                .disabled(model.outdated.isEmpty)
            }
        }
        .disabled(model.isBusy)
    }
}

// MARK: - Mimo Brewfile

struct UnmanagedView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var pendingUninstall: [UnmanagedItem] = []

    var body: some View {
        let items = model.unmanaged
        Group {
            if items.isEmpty {
                ContentUnavailableView("Všetko je v Brewfile", systemImage: "checkmark.seal", description: Text("Každý balík nainštalovaný na požiadanie je zapísaný v Brewfile."))
            } else {
                Table(items, selection: $selection) {
                    TableColumn("Typ") { item in KindLabel(kind: item.kind) }
                        .width(min: 70, ideal: 90, max: 110)
                    TableColumn("Názov") { item in Text(item.name).fontWeight(.medium) }
                    TableColumn("Popis") { item in Text(item.desc ?? "").foregroundStyle(.secondary) }
                    TableColumn("Verzia") { item in Text(item.version ?? "").monospacedDigit().foregroundStyle(.secondary) }
                        .width(min: 50, ideal: 80, max: 140)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let chosen = items.filter { ids.contains($0.id) }
                    Button("Pridať do Brewfile") { add(chosen) }
                    Button("Odinštalovať…", role: .destructive) { pendingUninstall = chosen }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    add(items.filter { selection.contains($0.id) })
                } label: {
                    Label("Pridať do Brewfile", systemImage: "text.badge.plus")
                }
                .disabled(selection.isEmpty)
                .help("Zapísať vybrané do Brewfile")

                Button(role: .destructive) {
                    pendingUninstall = items.filter { selection.contains($0.id) }
                } label: {
                    Label("Odinštalovať", systemImage: "trash")
                }
                .disabled(selection.isEmpty || model.isBusy)
            }
        }
        .confirmationDialog(
            "Odinštalovať \(pendingUninstall.count == 1 ? pendingUninstall[0].name : "\(pendingUninstall.count) položiek")?",
            isPresented: Binding(get: { !pendingUninstall.isEmpty }, set: { if !$0 { pendingUninstall = [] } })
        ) {
            Button("Odinštalovať", role: .destructive) {
                for item in pendingUninstall { model.uninstall(kind: item.kind, name: item.masID ?? item.name) }
                selection.removeAll()
            }
        } message: {
            Text(pendingUninstall.map(\.name).joined(separator: ", "))
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

// MARK: - Hľadanie

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var selection: SearchResult?

    enum Scope: String, CaseIterable { case all = "Všetko", formulae = "Formulae", casks = "Casks" }

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
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Nainštalované")
                    }
                    if model.brewfile.contains(kind: result.kind, name: result.name) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary).help("V Brewfile")
                    }
                }
                .tag(result)
            }
            .frame(minWidth: 240, idealWidth: 300)
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Hľadať v Homebrew", systemImage: "magnifyingglass", description: Text("\(model.allFormulae.count) formulae a \(model.allCasks.count) casks"))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }

            Group {
                if let selection {
                    PackageInfoView(kind: selection.kind, name: selection.name)
                        .id(selection.id)
                } else {
                    ContentUnavailableView("Vyberte balík", systemImage: "shippingbox")
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Názov balíka")
        .searchScopes($scope) {
            ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
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
            // Presné zhody a prefixy navrch bez ohľadu na typ.
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
