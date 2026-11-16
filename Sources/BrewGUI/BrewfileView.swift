import BrewCore
import SwiftUI

struct EntryRow: Identifiable {
    let entry: BrewfileEntry
    let status: EntryStatus
    let desc: String
    let isDuplicate: Bool
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
        .searchable(text: $search, placement: .toolbar, prompt: "Filtrovať")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .sheet(item: $editing) { target in
            EntryEditor(target: target)
        }
        .confirmationDialog(
            "Odinštalovať \(pendingUninstall?.name ?? "")?",
            isPresented: Binding(get: { pendingUninstall != nil }, set: { if !$0 { pendingUninstall = nil } }),
            presenting: pendingUninstall
        ) { entry in
            Button("Odinštalovať", role: .destructive) { model.uninstall(kind: entry.kind, name: entry.kind == .mas ? (entry.masID ?? entry.name) : entry.name) }
            Button("Odinštalovať a odstrániť z Brewfile", role: .destructive) {
                model.uninstall(kind: entry.kind, name: entry.kind == .mas ? (entry.masID ?? entry.name) : entry.name)
                model.remove(ids: [entry.id])
            }
        } message: { entry in
            Text("Spustí sa `brew uninstall` pre \(entry.kind.title.lowercased()) \(entry.name). Záznam v Brewfile ostane, kým ho neodstránite.")
        }
        .onChange(of: kindFilter) { selection.removeAll() }
    }

    // MARK: Tabuľka

    private var rows: [EntryRow] {
        let duplicates = model.brewfile.duplicateIDs
        var rows = model.brewfile.entries.enumerated().map { index, entry in
            EntryRow(
                entry: entry,
                status: model.status(of: entry),
                desc: model.installed.description(of: entry) ?? "",
                isDuplicate: duplicates.contains(entry.id),
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
                Label("Brewfile je prázdny", systemImage: "doc")
            } description: {
                Text(model.fileURL.path(percentEncoded: false))
            } actions: {
                Button("Pridať položku") { editing = .new(kindFilter ?? .brew) }
                Button("Otvoriť iný súbor…") { model.openPanel() }
            }
        } else if rows.isEmpty, missingOnly, search.isEmpty {
            ContentUnavailableView("Všetko je nainštalované", systemImage: "checkmark.seal", description: Text("Každá položka z Brewfile je na tomto Macu."))
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("", value: \.statusOrder) { row in
                    StatusBadge(status: row.status)
                }
                .width(22)
                TableColumn("Typ", value: \.kindOrder) { row in
                    KindLabel(kind: row.entry.kind)
                }
                .width(min: 70, ideal: 90, max: 120)
                TableColumn("Názov", value: \.name) { row in
                    HStack(spacing: 4) {
                        Text(row.name).fontWeight(.medium)
                        if row.isDuplicate {
                            Text("duplicita")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .background(.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .width(min: 120, ideal: 190)
                TableColumn("Popis", value: \.desc) { row in
                    Text(row.desc).foregroundStyle(.secondary).help(row.desc)
                }
                .width(min: 120, ideal: 280)
                TableColumn("Verzia", value: \.version) { row in
                    Text(row.version).monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 50, ideal: 80, max: 140)
                TableColumn("Možnosti / komentár") { row in
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
            Button("Upraviť…") { editing = .edit(entry) }
            Divider()
            if entry.kind.isManaged {
                let status = model.status(of: entry)
                if status == .missing {
                    Button("Nainštalovať") { model.install(entry) }
                } else if status.isInstalled {
                    if case .outdated = status, entry.kind == .brew || entry.kind == .cask {
                        Button("Upgradovať") {
                            model.run("Upgrade \(entry.name)", ["upgrade", entry.kind == .cask ? "--cask" : "--formula", entry.name])
                        }
                    }
                    Button("Odinštalovať…") { pendingUninstall = entry }
                }
            }
            Button("Kopírovať riadok") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.line, forType: .string)
            }
            Divider()
        } else if !entries.isEmpty {
            let missing = entries.filter { model.status(of: $0) == .missing }
            if !missing.isEmpty {
                Button("Nainštalovať chýbajúce (\(missing.count))") { missing.forEach(model.install) }
            }
        }
        if !entries.isEmpty {
            Button("Odstrániť z Brewfile", role: .destructive) {
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

    // MARK: Inspektor

    @ViewBuilder private var inspector: some View {
        if selection.count == 1, let id = selection.first, let entry = model.brewfile.entry(id: id) {
            EntryInspector(entry: entry, onEdit: { editing = .edit(entry) }, onUninstall: { pendingUninstall = entry })
        } else if selection.count > 1 {
            ContentUnavailableView("Vybraných \(selection.count) položiek", systemImage: "square.stack")
        } else {
            BrewfileSummary()
        }
    }

    // MARK: Panel nástrojov

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("Zobrazenie", selection: $mode) {
                Label("Tabuľka", systemImage: "tablecells").tag(Mode.table)
                Label("Text", systemImage: "text.alignleft").tag(Mode.text)
            }
            .pickerStyle(.segmented)
            .help("Prepnúť medzi tabuľkou a textovým editorom")
        }
        ToolbarItemGroup {
            Button {
                editing = .new(kindFilter ?? .brew)
            } label: {
                Label("Pridať", systemImage: "plus")
            }
            .help("Pridať položku do Brewfile")
            .keyboardShortcut("n")

            Button(role: .destructive) {
                removeSelected()
            } label: {
                Label("Odstrániť", systemImage: "minus")
            }
            .disabled(selection.isEmpty || mode == .text)
            .help("Odstrániť vybrané z Brewfile")

            Menu {
                Button("Zoradiť podľa typu a názvu") { model.brewfile.sort() }
                Button("Zoradiť a odstrániť duplicity") { model.brewfile.sort(removeDuplicates: true) }
                    .disabled(model.brewfile.duplicateIDs.isEmpty)
            } label: {
                Label("Zoradiť", systemImage: "arrow.up.arrow.down")
            }
            .help("Usporiadať riadky v súbore")
        }
        ToolbarItemGroup {
            Button {
                undoManager?.undo()
            } label: {
                Label("Späť", systemImage: "arrow.uturn.backward")
            }
            .disabled(mode == .text)
            .help("Vrátiť poslednú úpravu (⌘Z). Zmeny sa ukladajú automaticky.")

            Button {
                showInspector.toggle()
            } label: {
                Label("Detail", systemImage: "sidebar.trailing")
            }
            .help("Zobraziť / skryť detail")
        }
    }
}

// MARK: - Detail položky

struct EntryInspector: View {
    @Environment(AppModel.self) private var model
    let entry: BrewfileEntry
    let onEdit: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        if entry.kind == .brew || entry.kind == .cask {
            PackageInfoView(kind: entry.kind, name: entry.name, showsBrewfileButton: false)
                .safeAreaInset(edge: .top) { header }
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
                Button("Upraviť…", action: onEdit)
                if entry.kind == .tap || entry.kind == .mas {
                    let status = model.status(of: entry)
                    if status == .missing {
                        Button("Nainštalovať") { model.install(entry) }
                    } else if status.isInstalled {
                        Button("Odinštalovať…", action: onUninstall)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding()
        .background(.background)
    }
}

/// Prehľad v inšpektore, keď nie je nič vybrané.
struct BrewfileSummary: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let entries = model.brewfile.entries
        let statuses = entries.map(model.status(of:))
        Form {
            Section("Súbor") {
                LabeledContent("Cesta", value: model.fileURL.path(percentEncoded: false))
                LabeledContent("Položiek", value: "\(entries.count)")
                if model.isDirty {
                    LabeledContent("Stav", value: "Neuložené zmeny")
                }
            }
            Section("Stav na tomto Macu") {
                LabeledContent("Nainštalované", value: "\(statuses.filter(\.isInstalled).count)")
                LabeledContent("Chýbajúce", value: "\(statuses.filter { $0 == .missing }.count)")
                LabeledContent("Zastarané", value: "\(statuses.filter { if case .outdated = $0 { true } else { false } }.count)")
                LabeledContent("Duplicity", value: "\(model.brewfile.duplicateIDs.count)")
            }
            Section {
                Button("Otvoriť iný Brewfile…") { model.openPanel() }
                Button("Zobraziť vo Finderi") { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL]) }
                Button("Otvoriť zálohy") {
                    try? FileManager.default.createDirectory(at: model.backupsDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(model.backupsDirectory)
                }
            }
        }
        .formStyle(.grouped)
    }
}
