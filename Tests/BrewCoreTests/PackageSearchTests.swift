// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

struct PackageSearchTests {
    private let formulae = ["git", "git-delta", "lazygit", "ripgrep"]
    private let casks = ["github", "git-credential-manager", "iina"]

    @Test func exactThenPrefixThenContains() {
        let names = PackageSearch.results(for: "git", formulae: formulae, casks: casks).map(\.name)
        #expect(names == ["git", "git-delta", "github", "git-credential-manager", "lazygit"])
    }

    @Test func scopeAndLimit() {
        #expect(PackageSearch.results(for: "git", formulae: formulae, casks: casks, scope: .casks).map(\.kind) == [.cask, .cask])
        #expect(PackageSearch.results(for: "git", formulae: formulae, casks: casks, limit: 2).count == 2)
        #expect(PackageSearch.results(for: "  ", formulae: formulae, casks: casks).isEmpty)
    }

    @Test func caskAppsOfInstalledCasks() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"""
        {"formulae": [], "casks": [
          {"token": "iina", "full_token": "iina", "installed": "1.5.1",
           "artifacts": [{"app": ["IINA.app"]}, {"zap": [{"trash": ["~/Library/Preferences/com.colliderli.iina.plist"]}]}]},
          {"token": "firefox", "full_token": "firefox", "artifacts": [{"app": ["Firefox.app"]}]},
          {"token": "helper", "full_token": "helper", "installed": "1",
           "artifacts": [{"app": [".Hidden Helper.app"]}, {"uninstall": [{"delete": "/Applications/Gone.app"}]}]}
        ]}
        """#
        let casks = try decoder.decode(InfoResponse.self, from: Data(json.utf8)).casks
        let present: Set<String> = ["/Applications/IINA.app", "/Applications/Firefox.app", "/Applications/.Hidden Helper.app"]
        let apps = CaskApp.find(in: casks, directories: [URL(fileURLWithPath: "/Applications")]) { present.contains($0.path) }
        // Firefox isn't installed via Homebrew, hidden helpers are skipped, missing files are ignored.
        #expect(apps.map(\.name) == ["IINA"])
        #expect(apps.first?.token == "iina")
    }
}
