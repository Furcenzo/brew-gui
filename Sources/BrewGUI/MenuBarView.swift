// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import BrewCore
import SwiftUI

/// Template image for the menu bar: a mug with foam and a checklist cut out of the glass (like the app icon).
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 1.5, width: 9.5, height: 11), xRadius: 2, yRadius: 2).fill()
            let handle = NSBezierPath(roundedRect: NSRect(x: 11, y: 4, width: 4.6, height: 6), xRadius: 2.3, yRadius: 2.3)
            handle.lineWidth = 1.6
            handle.stroke()
            for (x, y, r) in [(3.8, 12.6, 2.2), (6.6, 14.0, 2.6), (9.6, 13.4, 2.3), (11.4, 12.2, 1.6)] {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            for y in [3.0, 5.8, 8.6] {
                NSBezierPath(roundedRect: NSRect(x: 4.4, y: y, width: 5.6, height: 1.4), xRadius: 0.7, yRadius: 0.7).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// The status item: the mug, with the number of available updates next to it.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let count = model.outdated.count
        if count > 0 {
            Label {
                Text(verbatim: "\(count)")
            } icon: {
                Image(nsImage: MenuBarIcon.image)
            }
            .labelStyle(.titleAndIcon)
        } else {
            Image(nsImage: MenuBarIcon.image)
        }
    }
}

/// The panel that opens from the menu bar icon: status, quick update, search and Homebrew apps.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var query: String
    @FocusState private var searchFocused: Bool

    init(query: String = "") {
        _query = State(initialValue: query)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            header
            TextField("Search packages and apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if trimmedQuery.isEmpty {
                        overview
                    } else {
                        searchResults
                    }
                }
                .padding(8)
            }
            .frame(height: 360)
            Divider()
            footer
        }
        .frame(width: 340)
        .onAppear { searchFocused = true }
    }

    // MARK: Header and footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Brew GUI").font(.headline)
                status.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if model.isBusy || model.loadingOutdated {
                ProgressView().controlSize(.small)
            }
            Button {
                model.brewUpdate()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.isBusy)
            .help("Download the latest package information (brew update)")
        }
        .padding(12)
    }

    @ViewBuilder private var status: some View {
        if let job = model.currentJob, job.isRunning {
            Text(verbatim: job.title)
        } else if !model.outdatedLoaded {
            Text("Checking for outdated packages…")
        } else if model.outdated.isEmpty {
            Text("Everything is up to date")
        } else {
            Text("Updates available: \(model.outdated.count)")
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Brew GUI") { showMainWindow() }
            Spacer()
            Button {
                closePanel()
                NSApp.activate()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings…")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Brew GUI")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Content

    @ViewBuilder private var overview: some View {
        if !model.outdated.isEmpty {
            SectionTitle("Updates") {
                Button("Upgrade All") { model.upgradeAll() }
                    .buttonStyle(.borderless)
                    .disabled(model.isBusy)
            }
            ForEach(model.outdated.prefix(6)) { package in
                MenuRow {
                    Image(systemName: package.isCask ? EntryKind.cask.symbol : EntryKind.brew.symbol)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                } title: {
                    Text(package.name)
                } detail: {
                    Text(verbatim: "\(package.installedVersion) → \(package.currentVersion)")
                } action: {
                    showMainWindow(.outdated)
                }
            }
            if model.outdated.count > 6 {
                Button("Show All Updates") { showMainWindow(.outdated) }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        SectionTitle("Apps")
        if model.caskApps.isEmpty {
            Text("No apps installed with Homebrew yet.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        ForEach(model.caskApps) { app in
            appRow(app)
        }
    }

    @ViewBuilder private var searchResults: some View {
        let apps = model.caskApps.filter {
            $0.name.localizedCaseInsensitiveContains(trimmedQuery) || $0.token.localizedCaseInsensitiveContains(trimmedQuery)
        }
        if !apps.isEmpty {
            SectionTitle("Apps")
            ForEach(apps) { app in appRow(app) }
        }
        SectionTitle("Packages")
        let results = model.search(trimmedQuery, limit: 8)
        if results.isEmpty {
            Text("No packages found")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        ForEach(results) { result in
            packageRow(result)
        }
    }

    private func appRow(_ app: CaskApp) -> some View {
        MenuRow {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .frame(width: 20, height: 20)
        } title: {
            Text(app.name)
        } detail: {
            EmptyView()
        } action: {
            closePanel()
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
        }
        .help(app.url.path)
    }

    private func packageRow(_ result: PackageSearchResult) -> some View {
        MenuRow {
            Image(systemName: result.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        } title: {
            Text(result.name)
        } detail: {
            if model.isInstalled(result) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Installed")
            } else {
                Menu("Install") {
                    Button("Install") { model.install(kind: result.kind, name: result.name) }
                    if !model.brewfile.contains(kind: result.kind, name: result.name) {
                        Button("Install and Add to Brewfile") {
                            model.installAndAddToBrewfile(kind: result.kind, name: result.name)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .disabled(model.isBusy)
            }
        } action: {
            model.pendingSearchQuery = result.name
            showMainWindow(.search)
        }
        .help("Show in Brew GUI")
    }

    // MARK: Actions

    private func showMainWindow(_ page: SidebarItem? = nil) {
        closePanel()
        if let page { model.sidebarSelection = page }
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApp.activate()
    }

    /// The menu bar panel stays open after a click; close it when the action leads elsewhere.
    private func closePanel() {
        NSApp.keyWindow?.close()
    }
}

/// Small grey section heading with an optional accessory on the right.
private struct SectionTitle<Accessory: View>: View {
    let title: LocalizedStringKey
    let accessory: Accessory

    init(_ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            accessory.font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }
}

/// A clickable row that highlights on hover, like a menu item.
private struct MenuRow<Icon: View, Title: View, Detail: View>: View {
    @ViewBuilder let icon: Icon
    @ViewBuilder let title: Title
    @ViewBuilder let detail: Detail
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            icon
            title.lineLimit(1)
            Spacer(minLength: 8)
            detail.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(perform: action)
    }
}
