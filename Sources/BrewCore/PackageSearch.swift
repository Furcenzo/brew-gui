// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

/// A formula or cask found by `PackageSearch`.
public struct PackageSearchResult: Hashable, Identifiable, Sendable {
    public var kind: EntryKind
    public var name: String
    public var id: String { "\(kind.rawValue):\(name)" }

    public init(kind: EntryKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// Searches the names from `brew formulae` / `brew casks`: exact matches first, then prefixes, then substrings.
public enum PackageSearch {
    public enum Scope: Sendable { case all, formulae, casks }

    public static func results(
        for query: String, formulae: [String], casks: [String], scope: Scope = .all, limit: Int = 300
    ) -> [PackageSearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        func match(_ names: [String], _ kind: EntryKind) -> [PackageSearchResult] {
            let exact = names.filter { $0 == q }
            let prefix = names.filter { $0 != q && $0.hasPrefix(q) }
            let contains = names.filter { !$0.hasPrefix(q) && $0.contains(q) }
            return (exact + prefix + contains).map { PackageSearchResult(kind: kind, name: $0) }
        }
        var out: [PackageSearchResult] = []
        if scope != .casks { out += match(formulae, .brew) }
        if scope != .formulae { out += match(casks, .cask) }
        if scope == .all {
            // Exact matches and prefixes first, regardless of type (a stable sort keeps the order within a rank).
            let ranked = out.enumerated().sorted { lhs, rhs in
                let (l, r) = (rank(lhs.element.name, q), rank(rhs.element.name, q))
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            out = ranked.map(\.element)
        }
        return Array(out.prefix(limit))
    }

    private static func rank(_ name: String, _ q: String) -> Int {
        name == q ? 0 : name.hasPrefix(q) ? 1 : 2
    }
}

/// An app installed by a Homebrew cask, e.g. for launching it from the menu bar.
public struct CaskApp: Hashable, Identifiable, Sendable {
    public var token: String
    public var url: URL
    public var name: String { url.deletingPathExtension().lastPathComponent }
    public var id: String { url.path }

    public init(token: String, url: URL) {
        self.token = token
        self.url = url
    }

    /// Apps of the installed casks that exist in the given folders, sorted by name.
    public static func find(
        in casks: [CaskInfo], directories: [URL] = InstalledApp.standardDirectories,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [CaskApp] {
        var seen = Set<String>()
        var apps: [CaskApp] = []
        for cask in casks where cask.installed != nil {
            // Original spelling of the file name (appFileNames is lowercased for matching).
            let files = (cask.artifacts?.values ?? [])
                .map { ($0 as NSString).lastPathComponent }
                .filter { $0.lowercased().hasSuffix(".app") && !$0.hasPrefix(".") }
            for file in files {
                for directory in directories {
                    let url = directory.appendingPathComponent(file)
                    if exists(url), seen.insert(url.path.lowercased()).inserted {
                        apps.append(CaskApp(token: cask.token, url: url))
                    }
                }
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
