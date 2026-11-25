// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import CoreServices
import Foundation

/// When an app was last opened and when it was put on this Mac, as recorded by Spotlight.
public struct AppUsage: Sendable, Hashable {
    /// `kMDItemLastUsedDate` – `nil` when macOS has no record of the app being opened.
    public var lastUsed: Date?
    /// `kMDItemDateAdded` – also changes when the app is replaced, e.g. by `brew upgrade`.
    public var added: Date?

    public init(lastUsed: Date? = nil, added: Date? = nil) {
        self.lastUsed = lastUsed
        self.added = added
    }

    /// The last sign of use: when the app was opened, or – without that record – when it was put on the Mac.
    /// (Replacing the app bundle, e.g. by `brew upgrade`, can drop the "last opened" record; such an app then
    /// counts from the update. The date added alone isn't used otherwise, because every upgrade changes it.)
    public var lastActivity: Date? { lastUsed ?? added }

    /// Reads the Spotlight metadata of the app bundle.
    public static func read(_ url: URL) -> AppUsage {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return AppUsage() }
        return AppUsage(
            lastUsed: MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date,
            added: MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        )
    }
}

/// Where an app on the Mac comes from, i.e. how Brew GUI can remove it.
public enum AppSource: Sendable, Hashable {
    case cask(token: String)
    case appStore(id: String, name: String)
    case other
}

/// Apps that have not been opened for a while – candidates for stashing or uninstalling.
public enum UnusedApps {
    public static let dayOptions = [30, 90, 180, 365]
    public static let defaultDays = 90

    /// Whether the app hasn't been used for at least `days` days.
    public static func isUnused(_ usage: AppUsage, days: Int, now: Date = Date()) -> Bool {
        guard let last = usage.lastActivity else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    /// Where the app comes from: an installed cask (by its app files), the App Store (by name), or elsewhere.
    public static func source(of app: InstalledApp, caskApps: [CaskApp], masApps: [MasApp]) -> AppSource {
        if let cask = caskApps.first(where: { $0.url.path.lowercased() == app.url.path.lowercased() }) {
            return .cask(token: cask.token)
        }
        if app.isFromAppStore, let mas = masApps.first(where: { $0.name.localizedCaseInsensitiveCompare(app.name) == .orderedSame }) {
            return .appStore(id: mas.id, name: mas.name)
        }
        return .other
    }

    /// Unused apps sorted from the longest unused (never opened first). Apple's own apps are left out.
    public static func filter(
        _ apps: [InstalledApp], usage: [String: AppUsage], days: Int, now: Date = Date()
    ) -> [InstalledApp] {
        apps.filter { !$0.isAppleSystemApp && isUnused(usage[$0.id] ?? AppUsage(), days: days, now: now) }
            .sorted { a, b in
                switch (usage[a.id]?.lastActivity, usage[b.id]?.lastActivity) {
                case (nil, nil): a.name.localizedStandardCompare(b.name) == .orderedAscending
                case (nil, _): true
                case (_, nil): false
                case let (x?, y?): x < y
                }
            }
    }
}
