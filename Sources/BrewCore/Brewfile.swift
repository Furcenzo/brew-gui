// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

/// Kind of a Brewfile entry (the keyword at the start of the line).
public enum EntryKind: String, CaseIterable, Sendable, Hashable, Codable {
    case tap, brew, cask, mas, vscode, go, cargo, uv, npm, krew, flatpak, whalebrew, winget

    public var title: String {
        switch self {
        case .tap: "Tap"
        case .brew: "Formula"
        case .cask: "Cask"
        case .mas: "App Store"
        case .vscode: "VS Code"
        case .go: "Go"
        case .cargo: "Cargo"
        case .uv: "uv"
        case .npm: "npm"
        case .krew: "Krew"
        case .flatpak: "Flatpak"
        case .whalebrew: "Whalebrew"
        case .winget: "WinGet"
        }
    }

    public var pluralTitle: String {
        switch self {
        case .tap: "Taps"
        case .brew: "Formulae"
        case .cask: "Casks"
        case .mas: "App Store"
        case .vscode: String(localized: "VS Code Extensions")
        default: title
        }
    }

    public var symbol: String {
        switch self {
        case .tap: "spigot"
        case .brew: "terminal"
        case .cask: "macwindow"
        case .mas: "bag"
        case .vscode: "chevron.left.forwardslash.chevron.right"
        default: "shippingbox"
        }
    }

    /// The order in which `brew bundle dump` writes the kinds.
    public var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    /// Kinds that Brew GUI can install / check directly.
    public var isManaged: Bool { [.tap, .brew, .cask, .mas].contains(self) }
}

/// A single entry such as `brew "name", args: [...] # comment`.
public struct BrewfileEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: EntryKind
    public var name: String
    /// Ruby arguments after the name, without the leading comma (e.g. `id: 497799835`).
    public var options: String
    /// Comment at the end of the line (without `#`).
    public var comment: String?

    /// Original line text and field values at load time – used to preserve formatting.
    fileprivate var original: (line: String, fields: Fields)?

    fileprivate struct Fields: Hashable {
        var kind: EntryKind
        var name: String
        var options: String
        var comment: String?
    }

    fileprivate var fields: Fields { Fields(kind: kind, name: name, options: options, comment: comment) }

    public init(id: UUID = UUID(), kind: EntryKind, name: String, options: String = "", comment: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.options = options
        self.comment = comment
    }

    /// Key used to find duplicates.
    public var identityKey: String { "\(kind.rawValue):\(name.lowercased())" }

    /// Short name without the tap prefix (`user/tap/foo` → `foo`).
    public var shortName: String {
        guard kind == .brew || kind == .cask else { return name }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    /// App Store ID for `mas` entries (`id: 123`).
    public var masID: String? {
        guard kind == .mas else { return nil }
        guard let range = options.range(of: #"id:\s*(\d+)"#, options: .regularExpression) else { return nil }
        return options[range].filter(\.isNumber)
    }

    /// The line as it will be written to the file.
    public var line: String {
        if let original, original.fields == fields { return original.line }
        var result = "\(kind.rawValue) \"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        let opts = options.trimmingCharacters(in: .whitespaces)
        if !opts.isEmpty { result += ", \(opts)" }
        if let comment = comment?.trimmingCharacters(in: .whitespaces), !comment.isEmpty { result += " # \(comment)" }
        return result
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.fields == rhs.fields && lhs.original?.line == rhs.original?.line
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(fields)
    }

    /// Parses a single line. Returns `nil` if it isn't a known entry.
    public static func parse(line: String) -> BrewfileEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        guard let kind = EntryKind(rawValue: String(trimmed[..<separator])) else { return nil }

        var rest = trimmed[separator...].drop(while: { $0 == " " || $0 == "\t" })
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        rest = rest.dropFirst()

        var name = ""
        var escaped = false
        var closed = false
        while let ch = rest.first {
            rest = rest.dropFirst()
            if escaped { name.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == quote { closed = true; break }
            name.append(ch)
        }
        guard closed, !name.isEmpty else { return nil }

        let (code, comment) = splitComment(String(rest))
        var options = code.trimmingCharacters(in: .whitespaces)
        if options.hasPrefix(",") { options.removeFirst() }
        options = options.trimmingCharacters(in: .whitespaces)
        // Something other than arguments (e.g. `if OS.mac?`) – keep the line as raw text to be safe.
        if !options.isEmpty, !code.trimmingCharacters(in: .whitespaces).hasPrefix(",") { return nil }

        var entry = BrewfileEntry(kind: kind, name: name, options: options, comment: comment)
        entry.original = (line, entry.fields)
        return entry
    }

    /// Splits text into code and comment (`#` outside quotes).
    static func splitComment(_ text: String) -> (code: String, comment: String?) {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let ch = text[index]
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "#" {
                let comment = text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
                return (String(text[..<index]), comment)
            }
        }
        return (text, nil)
    }
}

/// A whole Brewfile – preserves comments, blank lines and unknown Ruby code.
///
/// Stashed entries are packages kept in the Brewfile but not installed. They are comment lines
/// (`# stash: cask "foo"`), so `brew bundle install` and `brew bundle cleanup` ignore them. Brew GUI
/// recognises them anywhere in the file and adds new ones to a block at the end, under `stashHeader`.
public struct Brewfile: Hashable, Sendable {
    public enum Line: Hashable, Sendable {
        case entry(BrewfileEntry)
        /// A stashed entry; `prefix` is the comment marker as written (`# stash: `).
        case stashed(BrewfileEntry, prefix: String)
        case raw(String)
    }

    public static let stashPrefix = "# stash: "
    public static let stashHeader = "# Stashed by Brew GUI – kept in the Brewfile, not installed (brew bundle ignores these lines)"

    public var lines: [Line]
    public var trailingNewline: Bool

    public init(lines: [Line] = [], trailingNewline: Bool = true) {
        self.lines = lines
        self.trailingNewline = trailingNewline
    }

    public init(parsing text: String) {
        var parts = text.components(separatedBy: "\n")
        trailingNewline = text.hasSuffix("\n")
        if trailingNewline { parts.removeLast() }
        lines = parts.map { raw in
            if let entry = BrewfileEntry.parse(line: raw) { return .entry(entry) }
            if let (prefix, entry) = Self.parseStashed(raw) { return .stashed(entry, prefix: prefix) }
            return .raw(raw)
        }
    }

    /// `# stash: cask "foo"` → the marker and the entry.
    static func parseStashed(_ raw: String) -> (prefix: String, entry: BrewfileEntry)? {
        guard let range = raw.range(of: #"^\s*#\s*stash:\s*"#, options: [.regularExpression, .caseInsensitive]),
              let entry = BrewfileEntry.parse(line: String(raw[range.upperBound...]))
        else { return nil }
        return (String(raw[range]), entry)
    }

    static func isStashHeader(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespaces).hasPrefix("# Stashed by Brew GUI")
    }

    public var text: String {
        let body = lines.map { line -> String in
            switch line {
            case .entry(let entry): entry.line
            case .stashed(let entry, let prefix): prefix + entry.line
            case .raw(let raw): raw
            }
        }.joined(separator: "\n")
        return trailingNewline && !lines.isEmpty ? body + "\n" : body
    }

    public var entries: [BrewfileEntry] {
        lines.compactMap { if case .entry(let entry) = $0 { entry } else { nil } }
    }

    public func entry(id: UUID) -> BrewfileEntry? {
        entries.first { $0.id == id }
    }

    public func contains(kind: EntryKind, name: String) -> Bool {
        let key = BrewfileEntry(kind: kind, name: name).identityKey
        return entries.contains { $0.identityKey == key }
    }

    /// IDs of duplicate entries (second and later occurrences).
    public var duplicateIDs: Set<UUID> {
        var seen = Set<String>()
        var duplicates = Set<UUID>()
        for entry in entries where !seen.insert(entry.identityKey).inserted {
            duplicates.insert(entry.id)
        }
        return duplicates
    }

    public mutating func update(_ entry: BrewfileEntry) {
        guard let index = lines.firstIndex(where: { if case .entry(let e) = $0 { e.id == entry.id } else { false } }) else { return }
        lines[index] = .entry(entry)
    }

    public mutating func remove(ids: Set<UUID>) {
        lines.removeAll { if case .entry(let e) = $0 { ids.contains(e.id) } else { false } }
    }

    /// Adds an entry after the last entry of the same kind, otherwise at the end.
    public mutating func add(_ entry: BrewfileEntry) {
        if let index = lines.lastIndex(where: { if case .entry(let e) = $0 { e.kind == entry.kind } else { false } }) {
            lines.insert(.entry(entry), at: index + 1)
        } else if let index = lines.lastIndex(where: { if case .entry(let e) = $0 { e.kind.sortOrder < entry.kind.sortOrder } else { false } }) {
            lines.insert(.entry(entry), at: index + 1)
        } else if let index = lines.firstIndex(where: { if case .entry = $0 { true } else { false } }) {
            lines.insert(.entry(entry), at: index)
        } else if let index = lines.firstIndex(where: { if case .raw(let raw) = $0 { Self.isStashHeader(raw) } else { false } }) {
            lines.insert(.entry(entry), at: index)
        } else {
            lines.append(.entry(entry))
        }
    }

    // MARK: Stash

    public var stashedEntries: [BrewfileEntry] {
        lines.compactMap { if case .stashed(let entry, _) = $0 { entry } else { nil } }
    }

    public func stashedEntry(id: UUID) -> BrewfileEntry? {
        stashedEntries.first { $0.id == id }
    }

    public func isStashed(kind: EntryKind, name: String) -> Bool {
        let key = BrewfileEntry(kind: kind, name: name).identityKey
        return stashedEntries.contains { $0.identityKey == key }
    }

    /// Moves the entries (and their duplicates) to the stash.
    public mutating func stash(ids: Set<UUID>) {
        let chosen = entries.filter { ids.contains($0.id) }
        let keys = Set(chosen.map(\.identityKey))
        lines.removeAll { if case .entry(let e) = $0 { keys.contains(e.identityKey) } else { false } }
        for entry in chosen { stash(entry) }
    }

    /// Adds a stashed line for the package (unless it is stashed already) and removes it from the active entries.
    public mutating func stash(_ entry: BrewfileEntry) {
        let key = entry.identityKey
        lines.removeAll { if case .entry(let e) = $0 { e.identityKey == key } else { false } }
        guard !stashedEntries.contains(where: { $0.identityKey == key }) else { return }
        let line = Line.stashed(entry, prefix: Self.stashPrefix)
        if let index = lines.lastIndex(where: { if case .stashed = $0 { true } else { false } }) {
            lines.insert(line, at: index + 1)
        } else if let index = lines.lastIndex(where: { if case .raw(let raw) = $0 { Self.isStashHeader(raw) } else { false } }) {
            lines.insert(line, at: index + 1)
        } else {
            while lines.last == .raw("") { lines.removeLast() }
            if !lines.isEmpty { lines.append(.raw("")) }
            lines += [.raw(Self.stashHeader), line]
            if !trailingNewline { trailingNewline = true }
        }
    }

    /// Turns stashed lines back into entries (they are not installed by this).
    public mutating func unstash(ids: Set<UUID>) {
        let chosen = stashedEntries.filter { ids.contains($0.id) }
        removeStashed(ids: ids)
        for entry in chosen where !contains(kind: entry.kind, name: entry.name) { add(entry) }
    }

    public mutating func removeStashed(ids: Set<UUID>) {
        lines.removeAll { if case .stashed(let e, _) = $0 { ids.contains(e.id) } else { false } }
        removeEmptyStashHeader()
    }

    /// Puts back stashed lines of `other` that this file lacks – `brew bundle dump` rewrites the whole file.
    public mutating func restoreStash(from other: Brewfile) {
        for entry in other.stashedEntries where !contains(kind: entry.kind, name: entry.name) {
            stash(entry)
        }
    }

    private mutating func removeEmptyStashHeader() {
        guard stashedEntries.isEmpty,
              let index = lines.firstIndex(where: { if case .raw(let raw) = $0 { Self.isStashHeader(raw) } else { false } })
        else { return }
        lines.remove(at: index)
        if index == lines.count { while lines.last == .raw("") { lines.removeLast() } }
    }

    /// Sorts entries by kind and name. Comments directly above an entry move with it,
    /// other Ruby code stays at the top, and a blank line separates the kinds.
    public mutating func sort(removeDuplicates: Bool = false) {
        var header: [Line] = []
        var blocks: [(entry: BrewfileEntry, comments: [String])] = []
        var pendingComments: [String] = []
        var stashed: [Line] = []

        for line in lines {
            switch line {
            case .entry(let entry):
                blocks.append((entry, pendingComments))
                pendingComments = []
            case .stashed:
                stashed.append(line)
            case .raw(let raw):
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if Self.isStashHeader(raw) {
                    continue
                } else if trimmed.hasPrefix("#") {
                    // Comments before the first entry are the file header and stay at the top.
                    if blocks.isEmpty { header.append(.raw(raw)) } else { pendingComments.append(raw) }
                } else if trimmed.isEmpty {
                    // A comment separated by a blank line doesn't belong to the entry.
                    if blocks.isEmpty { header += pendingComments.map(Line.raw) }
                    pendingComments = []
                    if blocks.isEmpty, !header.isEmpty, header.last != .raw("") { header.append(.raw("")) }
                } else {
                    header += pendingComments.map(Line.raw)
                    pendingComments = []
                    header.append(.raw(raw))
                }
            }
        }
        let trailingComments = pendingComments

        if removeDuplicates {
            var seen = Set<String>()
            blocks = blocks.filter { seen.insert($0.entry.identityKey).inserted }
        }

        blocks.sort { a, b in
            if a.entry.kind != b.entry.kind { return a.entry.kind.sortOrder < b.entry.kind.sortOrder }
            return a.entry.name.localizedStandardCompare(b.entry.name) == .orderedAscending
        }

        while header.last == .raw("") { header.removeLast() }
        var result = header
        var lastKind: EntryKind?
        for block in blocks {
            if let lastKind, lastKind != block.entry.kind { result.append(.raw("")) }
            else if lastKind == nil, !result.isEmpty { result.append(.raw("")) }
            result += block.comments.map(Line.raw)
            result.append(.entry(block.entry))
            lastKind = block.entry.kind
        }
        if !trailingComments.isEmpty {
            result.append(.raw(""))
            result += trailingComments.map(Line.raw)
        }
        if !stashed.isEmpty {
            func key(_ line: Line) -> BrewfileEntry? { if case .stashed(let e, _) = line { e } else { nil } }
            stashed.sort { a, b in
                guard let a = key(a), let b = key(b) else { return false }
                if a.kind != b.kind { return a.kind.sortOrder < b.kind.sortOrder }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            if removeDuplicates {
                var seen = Set<String>()
                stashed = stashed.filter { key($0).map { seen.insert($0.identityKey).inserted } ?? true }
            }
            if !result.isEmpty { result.append(.raw("")) }
            result.append(.raw(Self.stashHeader))
            result += stashed
        }
        lines = result
    }
}
