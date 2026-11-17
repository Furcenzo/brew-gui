// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

struct EntryRow: Identifiable {
    let entry: BrewfileEntry
    let status: EntryStatus
    let desc: String
    let isDuplicate: Bool
    let warning: String?
    let fileOrder: Int

    var id: UUID { entry.id }
    var name: String { entry.name }
    var kindOrder: Int { entry.kind.sortOrder }
    var statusOrder: Int { status.sortOrder }
    var version: String { status.installedVersion ?? "" }
    var note: String { [entry.options, entry.comment.map { "# " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: "  ") }
}

struct BrewfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let kindFilter: EntryKind?
    let missingOnly: Bool

    enum Mode: String { case table, text }
    @AppStorage("brewfileMode") private var mode: Mode = .table
    @State private var selection = Set<UUID>()
    @State private var sortOrder: [KeyPathComparator<EntryRow>] = []
    @State private var search = ""
    @State private var editing: EditorTarget?
    @State private var pendingUninstall: BrewfileEntry?
    @AppStorage("showInspector") private var showInspector = true

    var body: some View {
        Group {
            switch mode {
            case .table: table
            case .text: textEditor
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .sheet(item: $editing) { target in
            EntryEditor(target: target)
        }
        .confirmationDialog(
            "Uninstall \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            presenting: pendingUninstall
        ) { entry in
            let target = entry.kind == .mas ? (entry.masID ?? entry.name) : entry.name
            Button("Uninstall and Remove from Brewfile", role: .destructive) {
                model.uninstall(kind: entry.kind, name: target) { succeeded in
                    if succeeded { model.remove(ids: [entry.id]) }
                }
            }
            Button("Uninstall, Keep in Brewfile", role: .destructive) { model.uninstall(kind: entry.kind, name: target) }
        } message: { entry in
            Text("This runs `brew uninstall` for \(entry.kind.title.lowercased()) \(entry.name). If you keep the Brewfile entry, `brew bundle install` will install it again.")
        }
        .onChange(of: kindFilter) { selection.removeAll() }
        .task(id: model.brewfile.entries.count) {
            guard let name = model.debugSelectEntry,
                  let entry = model.brewfile.entries.first(where: { $0.name == name }) else { return }
            selection = [entry.id]
            model.debugSelectEntry = nil
        }
    }

    // MARK: Table

    private var rows: [EntryRow] {
        let duplicates = model.brewfile.duplicateIDs
        var rows = model.brewfile.entries.enumerated().map { index, entry in
            EntryRow(
                entry: entry,
                status: model.status(of: entry),
                desc: model.installed.description(of: entry) ?? "",
                isDuplicate: duplicates.contains(entry.id),
                warning: model.installed.lifecycleWarning(of: entry),
                fileOrder: index
            )
        }
        if let kindFilter { rows = rows.filter { $0.entry.kind == kindFilter } }
        if missingOnly { rows = rows.filter { $0.status == .missing } }
        if !search.isEmpty {
            rows = rows.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.desc.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search) }
        }
        if !sortOrder.isEmpty { rows.sort(using: sortOrder) }
        return rows
    }

    @ViewBuilder private var table: some View {
        let rows = rows
        if model.brewfile.entries.isEmpty {
            ContentUnavailableView {
                Label("The Brewfile is empty", systemImage: "doc")
            } description: {
                Text(model.filePath)
            } actions: {
                Button("Add Entry") { editing = .new(kindFilter ?? .brew) }
                Button("Open Another File…") { model.openPanel() }
            }
        } else if rows.isEmpty, missingOnly, search.isEmpty {
            ContentUnavailableView("Everything is installed", systemImage: "checkmark.seal", description: Text("Every Brewfile entry is on this Mac."))
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn(Text(verbatim: ""), value: \.statusOrder) { row in
                    StatusBadge(status: row.status)
                }
                .width(22)
                TableColumn("Type", value: \.kindOrder) { row in
                    KindLabel(kind: row.entry.kind)
                }
                .width(min: 70, ideal: 90, max: 120)
                TableColumn("Name", value: \.name) { row in
                    HStack(spacing: 4) {
                        Text(row.name).fontWeight(.medium)
                        if row.isDuplicate {
                            Text("duplicate")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                        if let warning = row.warning {
                            Text("unsupported")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.red.opacity(0.18), in: Capsule())
                                .foregroundStyle(.red)
                                .help(warning)
                        }
                    }
                }
                .width(min: 120, ideal: 190)
                TableColumn("Description", value: \.desc) { row in
                    Text(row.desc).foregroundStyle(.secondary).help(row.desc)
                }
                .width(min: 120, ideal: 280)
                TableColumn("Version", value: \.version) { row in
                    Text(row.version).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 80, max: 140)
                TableColumn("Options / Comment") { row in
                    Text(row.note).font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 160)
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                contextMenu(for: ids)
            } primaryAction: { ids in
                if let id = ids.first, ids.count == 1, let entry = model.brewfile.entry(id: id) { editing = .edit(entry) }
            }
            .onDeleteCommand { removeSelected() }
        }
    }

    @ViewBuilder private func contextMenu(for ids: Set<UUID>) -> some View {
        let entries = ids.compactMap { model.brewfile.entry(id: $0) }
        if entries.count == 1, let entry = entries.first {
            Button("Edit…") { editing = .edit(entry) }
            Divider()
            if entry.kind.isManaged {
                let status = model.status(of: entry)
                if status == .missing {
                    Button("Install") { model.install(entry) }
                } else if status.isInstalled {
                    if case .outdated = status, entry.kind == .brew || entry.kind == .cask {
                        Button("Upgrade") {
                            model.run("Upgrade \(entry.name)", ["upgrade", entry.kind == .cask ? "--cask" : "--formula", entry.name])
                        }
                    }
                    Button("Uninstall…") { pendingUninstall = entry }
                }
            }
            Button("Copy Line") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.line, forType: .string)
            }
            Divider()
        } else if !entries.isEmpty {
            let missing = entries.filter { model.status(of: $0) == .missing }
            if !missing.isEmpty {
                Button("Install Missing (\(missing.count))") { missing.forEach { model.install($0) } }
            }
        }
        if !entries.isEmpty {
            Button("Remove from Brewfile", role: .destructive) {
                model.remove(ids: ids)
                selection.subtract(ids)
            }
        }
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        model.remove(ids: selection)
        selection.removeAll()
    }

    // MARK: Text

    private var textEditor: some View {
        @Bindable var model = model
        return TextEditor(text: Binding(
            get: { model.brewfile.text },
            set: { model.setTextFromEditor($0) }
        ))
        .font(.system(.body, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if selection.count == 1, let id = selection.first, let entry = model.brewfile.entry(id: id) {
            EntryInspector(entry: entry, onEdit: { editing = .edit(entry) }, onUninstall: { pendingUninstall = entry })
        } else if selection.count > 1 {
            ContentUnavailableView("Selected entries: \(selection.count)", systemImage: "square.stack")
        } else {
            BrewfileSummary()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("View", selection: $mode) {
                Label("Table", systemImage: "tablecells").tag(Mode.table)
                Label("Text", systemImage: "text.alignleft").tag(Mode.text)
            }
            .pickerStyle(.segmented)
            .help("Switch between the table and the text editor")
        }
        ToolbarItemGroup {
            Button {
                editing = .new(kindFilter ?? .brew)
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add an entry to the Brewfile")
            .keyboardShortcut("n")

            Button(role: .destructive) {
                removeSelected()
            } label: {
                Label("Remove", systemImage: "minus")
            }
            .disabled(selection.isEmpty || mode == .text)
            .help("Remove the selected entries from the Brewfile")

            Menu {
                Button("Sort by Type and Name") { model.brewfile.sort() }
                Button("Sort and Remove Duplicates") { model.brewfile.sort(removeDuplicates: true) }
                    .disabled(model.brewfile.duplicateIDs.isEmpty)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Reorder the lines in the file")
        }
        ToolbarItemGroup {
            Button {
                undoManager?.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(mode == .text)
            .help("Undo the last change (⌘Z). Changes are saved automatically.")

            Button {
                showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show / hide details")
        }
    }
}

// MARK: - Entry details

struct EntryInspector: View {
    @Environment(AppModel.self) private var model
    let entry: BrewfileEntry
    let onEdit: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        if entry.kind == .brew || entry.kind == .cask {
            // Stacked rather than as a safe-area inset: the inset left a large gap above the package details.
            VStack(spacing: 0) {
                header
                Divider()
                PackageInfoView(kind: entry.kind, name: entry.name, showsBrewfileButton: false)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                Spacer()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                KindLabel(kind: entry.kind)
                Spacer()
                StatusBadge(status: model.status(of: entry))
            }
            Text(entry.line)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Edit…", action: onEdit)
                if entry.kind == .tap || entry.kind == .mas {
                    let status = model.status(of: entry)
                    if status == .missing {
                        Button("Install") { model.install(entry) }
                    } else if status.isInstalled {
                        Button("Uninstall…", action: onUninstall)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding()
        .background(.background)
    }
}

/// Overview shown in the inspector when nothing is selected.
struct BrewfileSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.brewfile.entries
        let statuses = entries.map(model.status(of:))
        Form {
            Section("File") {
                LabeledContent("Path", value: model.filePath)
                LabeledContent("Entries", value: "\(entries.count)")
                if model.isDirty {
                    LabeledContent("Status", value: String(localized: "Unsaved changes"))
                }
            }
            Section("Status on This Mac") {
                LabeledContent("Installed", value: "\(statuses.filter(\.isInstalled).count)")
                LabeledContent("Missing", value: "\(statuses.filter { $0 == .missing }.count)")
                LabeledContent("Outdated", value: "\(statuses.filter { if case .outdated = $0 { true } else { false } }.count)")
                LabeledContent("Duplicates", value: "\(model.brewfile.duplicateIDs.count)")
                LabeledContent("Unsupported", value: "\(entries.filter { model.installed.lifecycleWarning(of: $0) != nil }.count)")
            }
            Section {
                Button("Open Another Brewfile…") { model.openPanel() }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL]) }
                Button("Open Backups") {
                    try? FileManager.default.createDirectory(at: model.backupsDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.backupsDirectory)
                }
            }
        }
        .formStyle(.grouped)
    }
}
