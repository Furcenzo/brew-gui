// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

/// An app bundle found in /Applications or ~/Applications.
public struct InstalledApp: Sendable, Hashable, Identifiable {
    public var url: URL
    public var bundleID: String?
    public var version: String?
    /// Installed from the Mac App Store (has a receipt), including iPhone/iPad apps.
    public var isFromAppStore: Bool

    public init(url: URL, bundleID: String? = nil, version: String? = nil, isFromAppStore: Bool = false) {
        self.url = url
        self.bundleID = bundleID
        self.version = version
        self.isFromAppStore = isFromAppStore
    }

    public var id: String { url.path }
    public var fileName: String { url.lastPathComponent }
    public var name: String { url.deletingPathExtension().lastPathComponent }

    /// Apple's own apps that come with macOS (Safari…) – not something Homebrew manages.
    public var isAppleSystemApp: Bool { !isFromAppStore && bundleID?.hasPrefix("com.apple.") == true }

    public static var standardDirectories: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
    }

    /// Top-level `.app` bundles in the given directories, sorted by name.
    public static func scan(_ directories: [URL] = standardDirectories) -> [InstalledApp] {
        let fm = FileManager.default
        var apps: [InstalledApp] = []
        for directory in directories {
            guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            // Hidden helper apps (".Karabiner-VirtualHIDDevice-Manager.app") aren't meant to be opened by hand.
            for url in items where url.pathExtension.lowercased() == "app" && !url.lastPathComponent.hasPrefix(".") {
                let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
                let receipt = url.appendingPathComponent("Contents/_MASReceipt/receipt").path
                let wrapped = url.appendingPathComponent("Wrapper/iTunesMetadata.plist").path
                apps.append(InstalledApp(
                    url: url,
                    bundleID: info?["CFBundleIdentifier"] as? String,
                    version: (info?["CFBundleShortVersionString"] ?? info?["CFBundleVersion"]) as? String,
                    isFromAppStore: fm.fileExists(atPath: receipt) || fm.fileExists(atPath: wrapped)
                ))
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Likely cask tokens for an app name, following Homebrew's token rules
/// ("Visual Studio Code" → `visual-studio-code`, "Notepad++" → `notepad-plus-plus`).
public enum CaskTokenGuess {
    public static func candidates(forAppNamed name: String) -> [String] {
        func token(_ dots: String) -> String {
            var text = name.lowercased()
                .replacingOccurrences(of: "+", with: "-plus-")
                .replacingOccurrences(of: "@", with: "-at-")
                .replacingOccurrences(of: ".", with: dots)
            text = String(text.compactMap { char -> Character? in
                if char.isASCII && (char.isLetter || char.isNumber) { return char }
                return char == " " || char == "_" || char == "-" ? "-" : nil
            })
            while text.contains("--") { text = text.replacingOccurrences(of: "--", with: "-") }
            return text.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        var result: [String] = []
        for candidate in [token(""), token("-"), token("") + "-app"] where !candidate.isEmpty && !result.contains(candidate) {
            result.append(candidate)
        }
        return result.filter { $0 != "-app" }
    }
}

/// Finds apps that neither Homebrew, the App Store nor macOS itself manage, and matching casks for them.
public enum UnmanagedApps {
    /// Apps that aren't from the App Store, aren't Apple system apps and don't belong to an installed cask.
    /// An app belongs to a cask when the cask references the app's file name or bundle ID (`app`, `uninstall`
    /// and `zap` artifacts), the ID of the .pkg that installed it (`packageIDs`, from `pkgutil --file-info`),
    /// or when the cask's token matches the app name (casks installed from a .pkg).
    public static func filter(
        _ apps: [InstalledApp], installedCasks: [CaskInfo], packageIDs: [String: [String]] = [:]
    ) -> [InstalledApp] {
        let managedFiles = installedCasks.reduce(into: Set<String>()) { $0.formUnion($1.appFileNames) }
        let installedTokens = Set(installedCasks.flatMap { [$0.token.lowercased(), $0.fullToken.lowercased()] })
        let artifactStrings = installedCasks.flatMap { $0.artifacts?.values ?? [] }.map { $0.lowercased() }
        return apps.filter { app in
            !app.isFromAppStore
                && !app.isAppleSystemApp
                && !managedFiles.contains(app.fileName.lowercased())
                && !CaskTokenGuess.candidates(forAppNamed: app.name).contains(where: installedTokens.contains)
                && !([app.bundleID].compactMap { $0 } + (packageIDs[app.id] ?? [])).contains { id in
                    artifactStrings.contains { mentions($0, bundleID: id) }
                }
        }
    }

    /// Package IDs from `pkgutil --file-info` output (`pkgid: org.pqrs.Karabiner-Elements`).
    public static func parsePackageIDs(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("pkgid: ") ? String(line.dropFirst("pkgid: ".count)).trimmingCharacters(in: .whitespaces) : nil
        }
    }

    /// Whether `text` contains the bundle ID as a whole (`~/Library/Preferences/com.foo.App.plist` mentions
    /// `com.foo.App`, `com.foo.AppHelper` doesn't).
    static func mentions(_ text: String, bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        guard id.contains("."), !id.isEmpty else { return false }
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: id, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            let isBoundary: (Character?) -> Bool = { char in
                guard let char else { return true }
                return !(char.isLetter || char.isNumber || char == "-" || char == "_")
            }
            if isBoundary(before) && isBoundary(after) { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    /// For each app (by `id`), the first candidate cask that references the app's file name.
    public static func suggestions(for apps: [InstalledApp], casks: [CaskInfo]) -> [String: CaskInfo] {
        let byToken = Dictionary(casks.map { ($0.token.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var result: [String: CaskInfo] = [:]
        for app in apps {
            let file = app.fileName.lowercased()
            let match = CaskTokenGuess.candidates(forAppNamed: app.name)
                .compactMap { byToken[$0] }
                .first { $0.appFileNames.contains(file) }
            if let match { result[app.id] = match }
        }
        return result
    }

    /// Homebrew adopts an existing app only if it is identical to the cask's version, unless the cask updates itself.
    public static func canAdopt(_ app: InstalledApp, as cask: CaskInfo) -> Bool {
        if cask.autoUpdates == true { return true }
        guard let installed = app.version, let caskVersion = cask.version?.split(separator: ",").first else { return false }
        return installed == String(caskVersion)
    }
}
