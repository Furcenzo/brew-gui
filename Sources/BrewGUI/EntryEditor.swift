// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

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
                Picker("Type", selection: $kind) {
                    ForEach(EntryKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.symbol).tag(kind)
                    }
                }
                TextField(kind == .mas ? "App Name" : "Name", text: $name, prompt: Text(placeholder))
                    .font(.body.monospaced())
                if !suggestions.isEmpty {
                    LabeledContent("Suggestions") {
                        FlowSuggestions(items: suggestions) { name = $0 }
                    }
                }
                if kind == .mas {
                    TextField("App Store ID", text: $masID, prompt: Text("e.g. 497799835"))
                        .font(.body.monospaced())
                } else {
                    TextField("Options", text: $options, prompt: Text(optionsPlaceholder))
                        .font(.body.monospaced())
                }
                TextField("Comment", text: $comment, prompt: Text("optional"))
                if isNew, kind.isManaged {
                    Toggle("Install Right Away", isOn: $installNow)
                }
                LabeledContent("Line") {
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
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { commit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || (kind == .mas && !masID.allSatisfy(\.isNumber)))
            }
            .padding()
        }
        .frame(width: 520)
        .onAppear(perform: load)
    }

    private var placeholder: LocalizedStringKey {
        switch kind {
        case .tap: "user/repo"
        case .brew: "e.g. ripgrep or user/tap/formula"
        case .cask: "e.g. visual-studio-code"
        case .mas: "e.g. Xcode"
        case .vscode: "e.g. ms-python.python"
        default: "package name"
        }
    }

    private var optionsPlaceholder: LocalizedStringKey {
        switch kind {
        case .brew: #"e.g. args: ["HEAD"], restart_service: :changed"#
        case .cask: #"e.g. args: { appdir: "~/Applications" }"#
        case .tap: "e.g. \"https://github.com/user/homebrew-repo\""
        default: "optional Ruby arguments"
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
        if isDuplicate { return String(localized: "This entry is already in the Brewfile.") }
        if kind == .brew, !model.allFormulae.isEmpty, !trimmedName.contains("/"), !model.allFormulae.contains(trimmedName) {
            return String(localized: "No formula with this name exists in Homebrew (or it is an alias).")
        }
        if kind == .cask, !model.allCasks.isEmpty, !trimmedName.contains("/"), !model.allCasks.contains(trimmedName) {
            return String(localized: "No cask with this name exists in Homebrew.")
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
