// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

@Suite struct AppUsageTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
    func app(_ name: String, bundleID: String? = nil, appStore: Bool = false) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: bundleID, isFromAppStore: appStore)
    }

    @Test func lastActivityPrefersLastOpened() {
        #expect(AppUsage(lastUsed: daysAgo(200), added: daysAgo(3)).lastActivity == daysAgo(200))
        #expect(AppUsage(lastUsed: daysAgo(3), added: daysAgo(200)).lastActivity == daysAgo(3))
        #expect(AppUsage(lastUsed: nil, added: daysAgo(10)).lastActivity == daysAgo(10))
        #expect(AppUsage().lastActivity == nil)
    }

    @Test func unusedAfterThreshold() {
        #expect(UnusedApps.isUnused(AppUsage(lastUsed: daysAgo(91)), days: 90, now: now))
        #expect(!UnusedApps.isUnused(AppUsage(lastUsed: daysAgo(89)), days: 90, now: now))
        #expect(UnusedApps.isUnused(AppUsage(), days: 90, now: now))
    }

    @Test func filterSortsAndSkipsAppleApps() {
        let apps = [app("Recent"), app("Old"), app("Never"), app("Older"), app("Safari", bundleID: "com.apple.Safari")]
        let usage: [String: AppUsage] = [
            apps[0].id: AppUsage(lastUsed: daysAgo(5)),
            apps[1].id: AppUsage(lastUsed: daysAgo(100)),
            apps[3].id: AppUsage(lastUsed: daysAgo(300)),
        ]
        let result = UnusedApps.filter(apps, usage: usage, days: 90, now: now)
        #expect(result.map(\.name) == ["Never", "Older", "Old"])
    }

    @Test func sourceOfApp() {
        let caskApps = [CaskApp(token: "dockdoor", url: URL(fileURLWithPath: "/Applications/DockDoor.app"))]
        let mas = [MasApp(id: "904280696", name: "Things 3", version: "3.20")]
        #expect(UnusedApps.source(of: app("DockDoor"), caskApps: caskApps, masApps: mas) == .cask(token: "dockdoor"))
        #expect(UnusedApps.source(of: app("Things 3", appStore: true), caskApps: caskApps, masApps: mas)
            == .appStore(id: "904280696", name: "Things 3"))
        #expect(UnusedApps.source(of: app("Things 3"), caskApps: caskApps, masApps: mas) == .other)
    }
}
