import Foundation

/// Typ záznamu v Brewfile (kľúčové slovo na začiatku riadku).
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
        case .vscode: "VS Code rozšírenia"
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

    /// Poradie, v akom `brew bundle dump` zapisuje typy.
    public var sortOrder: Int { Self.allCases.firstIndex(of: self) ?? 99 }

    /// Typy, ktoré Brew GUI vie inštalovať / kontrolovať priamo.
    public var isManaged: Bool { [.tap, .brew, .cask, .mas].contains(self) }
}

/// Jeden záznam typu `brew "name", args: [...] # komentár`.
public struct BrewfileEntry: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: EntryKind
    public var name: String
    /// Ruby argumenty za názvom, bez úvodnej čiarky (napr. `id: 497799835`).
    public var options: String
    /// Komentár na konci riadku (bez `#`).
    public var comment: String?

    /// Pôvodný text riadku a hodnoty polí v čase načítania – kvôli zachovaniu formátovania.
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

    /// Kľúč na hľadanie duplicít.
    public var identityKey: String { "\(kind.rawValue):\(name.lowercased())" }

    /// Krátky názov bez tap prefixu (`user/tap/foo` → `foo`).
    public var shortName: String {
        guard kind == .brew || kind == .cask else { return name }
        return name.split(separator: "/").last.map(String.init) ?? name
    }

    /// App Store ID pre `mas` záznamy (`id: 123`).
    public var masID: String? {
        guard kind == .mas else { return nil }
        guard let range = options.range(of: #"id:\s*(\d+)"#, options: .regularExpression) else { return nil }
        return options[range].filter(\.isNumber)
    }

    /// Riadok tak, ako bude zapísaný do súboru.
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

    /// Rozparsuje jeden riadok. Vráti `nil`, ak nejde o známy záznam.
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
        // Niečo iné než argumenty (napr. `if OS.mac?`) – radšej necháme riadok ako surový text.
        if !options.isEmpty, !code.trimmingCharacters(in: .whitespaces).hasPrefix(",") { return nil }

        var entry = BrewfileEntry(kind: kind, name: name, options: options, comment: comment)
        entry.original = (line, entry.fields)
        return entry
    }

    /// Rozdelí text na kód a komentár (`#` mimo úvodzoviek).
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

/// Celý Brewfile – zachováva komentáre, prázdne riadky aj neznámy Ruby kód.
public struct Brewfile: Hashable, Sendable {
    public enum Line: Hashable, Sendable {
        case entry(BrewfileEntry)
        case raw(String)
    }

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
            BrewfileEntry.parse(line: raw).map(Line.entry) ?? .raw(raw)
        }
    }

    public var text: String {
        let body = lines.map { line -> String in
            switch line {
            case .entry(let entry): entry.line
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

    /// ID záznamov, ktoré sú duplicitné (druhý a ďalší výskyt).
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

    /// Pridá záznam za posledný záznam rovnakého typu, inak na koniec.
    public mutating func add(_ entry: BrewfileEntry) {
        if let index = lines.lastIndex(where: { if case .entry(let e) = $0 { e.kind == entry.kind } else { false } }) {
            lines.insert(.entry(entry), at: index + 1)
        } else if let index = lines.lastIndex(where: { if case .entry(let e) = $0 { e.kind.sortOrder < entry.kind.sortOrder } else { false } }) {
            lines.insert(.entry(entry), at: index + 1)
        } else if let index = lines.firstIndex(where: { if case .entry = $0 { true } else { false } }) {
            lines.insert(.entry(entry), at: index)
        } else {
            lines.append(.entry(entry))
        }
    }

    /// Zoradí záznamy podľa typu a názvu. Komentáre tesne nad záznamom sa presunú s ním,
    /// ostatný Ruby kód ostane navrchu, medzi typmi sa vloží prázdny riadok.
    public mutating func sort(removeDuplicates: Bool = false) {
        var header: [Line] = []
        var blocks: [(entry: BrewfileEntry, comments: [String])] = []
        var pendingComments: [String] = []

        for line in lines {
            switch line {
            case .entry(let entry):
                blocks.append((entry, pendingComments))
                pendingComments = []
            case .raw(let raw):
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    // Komentáre pred prvým záznamom sú hlavička súboru a ostávajú navrchu.
                    if blocks.isEmpty { header.append(.raw(raw)) } else { pendingComments.append(raw) }
                } else if trimmed.isEmpty {
                    // Komentár oddelený prázdnym riadkom nepatrí k záznamu.
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
        lines = result
    }
}
