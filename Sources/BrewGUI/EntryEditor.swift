import BrewCore
import SwiftUI

enum EditorTarget: Identifiable {
    case new(EntryKind)
    case edit(BrewfileEntry)

    var id: String {
        switch self {
        case .new(let kind): "new-\(kind.rawValue)"
        case .edit(let entry): entry.id.uuidString
        }
    }
}

struct EntryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget

    @State private var kind: EntryKind = .brew
    @State private var name = ""
    @State private var options = ""
    @State private var comment = ""
    @State private var masID = ""
    @State private var installNow = false
    @State private var loaded = false

    private var isNew: Bool { if case .new = target { true } else { false } }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("Typ", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                TextField(kind == .mas ? "Názov aplikácie" : "Názov", text: $name, prompt: Text(placeholder))
                    .font(.body.monospaced())
                if !suggestions.isEmpty {
                    LabeledContent("Návrhy") {
                        FlowSuggestions(items: suggestions) { name = $0 }
                    }
                }
                if kind == .mas {
                    TextField("App Store ID", text: $masID, prompt: Text("napr. 497799835"))
                        .font(.body.monospaced())
                } else {
                    TextField("Možnosti", text: $options, prompt: Text(optionsPlaceholder))
                        .font(.body.monospaced())
                }
                TextField("Komentár", text: $comment, prompt: Text("voliteľné"))
                if isNew, kind.isManaged {
                    Toggle("Hneď aj nainštalovať", isOn: $installNow)
                }
                LabeledContent("Riadok") {
                    Text(previewEntry.line)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Zrušiť", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Pridať" : "Uložiť") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || (kind == .mas && !masID.allSatisfy(\.isNumber)))
            }
            .padding()
        }
        .frame(width: 520)
        .onAppear(perform: load)
    }

    private var placeholder: String {
        switch kind {
        case .tap: "user/repo"
        case .brew: "napr. ripgrep alebo user/tap/formula"
        case .cask: "napr. visual-studio-code"
        case .mas: "napr. Xcode"
        case .vscode: "napr. ms-python.python"
        default: "názov balíka"
        }
    }

    private var optionsPlaceholder: String {
        switch kind {
        case .brew: #"napr. args: ["HEAD"], restart_service: :changed"#
        case .cask: #"napr. args: { appdir: "~/Applications" }"#
        case .tap: "napr. \"https://github.com/user/homebrew-repo\""
        default: "voliteľné Ruby argumenty"
        }
    }

    private var suggestions: [String] {
        let query = trimmedName.lowercased()
        guard query.count >= 2, kind == .brew || kind == .cask else { return [] }
        let pool = kind == .brew ? model.allFormulae : model.allCasks
        if pool.contains(query) { return [] }
        let prefix = pool.filter { $0.hasPrefix(query) }
        let contains = prefix.count < 8 ? pool.filter { !$0.hasPrefix(query) && $0.contains(query) } : []
        return Array((prefix + contains).prefix(8))
    }

    private var warning: String? {
        guard !trimmedName.isEmpty else { return nil }
        let key = previewEntry.identityKey
        let isDuplicate = model.brewfile.entries.contains { $0.identityKey == key && $0.id != existingID }
        if isDuplicate { return "Táto položka už v Brewfile je." }
        if kind == .brew, !model.allFormulae.isEmpty, !trimmedName.contains("/"), !model.allFormulae.contains(trimmedName) {
            return "Formula s týmto názvom v Homebrew neexistuje (alebo ide o alias)."
        }
        if kind == .cask, !model.allCasks.isEmpty, !trimmedName.contains("/"), !model.allCasks.contains(trimmedName) {
            return "Cask s týmto názvom v Homebrew neexistuje."
        }
        return nil
    }

    private var existingID: UUID? {
        if case .edit(let entry) = target { entry.id } else { nil }
    }

    private var previewEntry: BrewfileEntry {
        var entry: BrewfileEntry
        if case .edit(let existing) = target { entry = existing } else { entry = BrewfileEntry(kind: kind, name: "") }
        entry.kind = kind
        entry.name = trimmedName
        entry.options = kind == .mas ? (masID.isEmpty ? "" : "id: \(masID)") : options.trimmingCharacters(in: .whitespaces)
        let trimmedComment = comment.trimmingCharacters(in: .whitespaces)
        entry.comment = trimmedComment.isEmpty ? nil : trimmedComment
        return entry
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new(let kind):
            self.kind = kind
        case .edit(let entry):
            kind = entry.kind
            name = entry.name
            comment = entry.comment ?? ""
            if entry.kind == .mas, let id = entry.masID {
                masID = id
            } else {
                options = entry.options
            }
        }
    }

    private func commit() {
        let entry = previewEntry
        if isNew {
            model.add(entry)
            if installNow { model.install(entry) }
        } else {
            model.update(entry)
        }
        dismiss()
    }
}

/// Malé tlačidlá s návrhmi názvov.
struct FlowSuggestions: View {
    let items: [String]
    let onPick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items, id: \.self) { item in
                    Button(item) { onPick(item) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}
