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
    enum Mode: String { case packages, apps }
    @AppStorage("unmanagedMode") private var mode: Mode = .packages

    var body: some View {
        Group {
            switch mode {
            case .packages: UnmanagedPackagesView()
            case .apps: UnmanagedAppsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $mode) {
                    Text("Packages").tag(Mode.packages)
                    Text("Apps").tag(Mode.apps)
                }
                .pickerStyle(.segmented)
                .help("Packages and taps missing from the Brewfile, or apps installed outside Homebrew")
            }
        }
    }
}

/// Packages, taps and App Store apps that are installed but not in the Brewfile.
struct UnmanagedPackagesView: View {
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

// MARK: - Apps outside Homebrew

/// Apps in /Applications installed by hand, with the cask Homebrew could take them over with.
struct UnmanagedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection = Set<String>()
    @State private var pendingAdopt: UnmanagedApp?
    @State private var pendingReinstall: UnmanagedApp?

    var body: some View {
        let items = model.unmanagedApps
        let selected = items.filter { selection.contains($0.id) }
        let single = selected.count == 1 ? selected.first : nil
        Group {
            if !model.appsLoaded {
                ProgressView("Looking for apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("All apps are managed", systemImage: "checkmark.seal", description: Text("Every app in Applications comes from Homebrew, the App Store or macOS."))
            } else {
                Table(items, selection: $selection) {
                    TableColumn("App") { item in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.app.url.path))
                                .resizable()
                                .frame(width: 18, height: 18)
                            Text(item.app.name).fontWeight(.medium)
                        }
                        .help(item.app.url.path)
                    }
                    .width(min: 140, ideal: 220)
                    TableColumn("Version") { item in
                        Text(item.app.version ?? "").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(min: 50, ideal: 90, max: 140)
                    TableColumn("Homebrew Cask") { item in
                        if let cask = item.cask {
                            Text(cask.token).font(.body.monospaced())
                        } else {
                            Text("no cask found").foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 120, ideal: 200)
                    TableColumn("Cask Version") { item in
                        if let cask = item.cask {
                            HStack(spacing: 4) {
                                Text(cask.version?.split(separator: ",").first.map(String.init) ?? "")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                if !item.canAdopt {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                        .help("The installed version differs from the cask, so Homebrew won't adopt the app as it is.")
                                }
                            }
                        }
                    }
                    .width(min: 70, ideal: 110, max: 160)
                    TableColumn("Description") { item in
                        Text(item.cask?.desc ?? "").foregroundStyle(.secondary).help(item.cask?.desc ?? "")
                    }
                    .width(min: 120, ideal: 260)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let chosen = items.filter { ids.contains($0.id) }
                    if chosen.count == 1, let item = chosen.first {
                        if item.cask != nil {
                            Button("Adopt with Homebrew…") { pendingAdopt = item }
                            Button("Reinstall with Homebrew…") { pendingReinstall = item }
                            Divider()
                        }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.app.url]) }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text("Apps from the App Store and apps that come with macOS are not listed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
            }
        }
        .task { await model.refreshApps() }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    pendingAdopt = single
                } label: {
                    Label("Adopt with Homebrew", systemImage: "arrow.down.app")
                }
                .disabled(single?.cask == nil || model.isBusy)
                .help("Let Homebrew manage the selected app (brew install --cask --adopt)")

                Button {
                    Task { await model.refreshApps() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.loadingApps)
                .help("Scan Applications again")
            }
        }
        .confirmationDialog(
            "Adopt \(pendingAdopt?.app.name ?? "") with Homebrew?",
            isPresented: Binding(get: { pendingAdopt != nil }, set: { if !$0 { pendingAdopt = nil } }),
            presenting: pendingAdopt
        ) { item in
            Button("Adopt and Add to Brewfile") { model.adopt(item, addToBrewfile: true) }
            Button("Adopt Only") { model.adopt(item, addToBrewfile: false) }
        } message: { item in
            if item.canAdopt {
                Text("Homebrew downloads the cask \(item.cask?.token ?? "") and takes over the existing app without replacing it. From then on you can update it with Homebrew.")
            } else {
                Text("The installed version (\(item.app.version ?? "?")) differs from the cask (\(item.cask?.version ?? "?")), so Homebrew will most likely refuse to adopt it. Update the app first, or use Reinstall with Homebrew.")
            }
        }
        .confirmationDialog(
            "Reinstall \(pendingReinstall?.app.name ?? "") with Homebrew?",
            isPresented: Binding(get: { pendingReinstall != nil }, set: { if !$0 { pendingReinstall = nil } }),
            presenting: pendingReinstall
        ) { item in
            Button("Reinstall and Add to Brewfile", role: .destructive) { model.reinstallWithHomebrew(item, addToBrewfile: true) }
            Button("Reinstall Only", role: .destructive) { model.reinstallWithHomebrew(item, addToBrewfile: false) }
        } message: { item in
            Text("Homebrew replaces the app in Applications with version \(item.cask?.version ?? "?") from the cask \(item.cask?.token ?? ""). Your settings and data are kept.")
        }
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

        var searchScope: PackageSearch.Scope {
            switch self {
            case .all: .all
            case .formulae: .formulae
            case .casks: .casks
            }
        }
    }

    typealias SearchResult = PackageSearchResult

    var body: some View {
        HSplitView {
            List(results, selection: $selection) { result in
                HStack {
                    Image(systemName: result.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
                    Text(result.name)
                    Spacer()
                    if model.isInstalled(result) {
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
        // A package requested from the menu bar (or BREWGUI_SEARCH) – also when the page is already open.
        .task(id: "\(model.allCasks.count)|\(model.pendingSearchQuery ?? "")") {
            guard let name = model.pendingSearchQuery, !model.allCasks.isEmpty else { return }
            query = name
            selection = SearchResult(kind: model.allCasks.contains(name) ? .cask : .brew, name: name)
            model.pendingSearchQuery = nil
        }
    }

    private var results: [SearchResult] {
        model.search(query, scope: scope.searchScope)
    }
}
