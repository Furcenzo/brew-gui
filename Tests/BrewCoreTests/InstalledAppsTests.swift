// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

struct InstalledAppsTests {
    /// Casks shaped like `brew info --json=v2 --cask` output.
    private func casks(_ json: String) throws -> [CaskInfo] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(InfoResponse.self, from: Data(#"{"formulae": [], "casks": \#(json)}"#.utf8)).casks
    }

    private let sample = #"""
    [
      {"token": "visual-studio-code", "full_token": "visual-studio-code", "version": "1.146.0", "auto_updates": true,
       "artifacts": [{"uninstall": [{"quit": "com.microsoft.VSCode"}]},
                     {"app": ["Visual Studio Code.app"], "target": "/Applications/Visual Studio Code.app"},
                     {"binary": ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]}]},
      {"token": "battle-net", "full_token": "battle-net", "version": "2.0",
       "artifacts": [{"installer": [{"manual": "Battle.net-Setup.app"}]},
                     {"uninstall": [{"delete": ["/Applications/Battle.net.app"], "signal": [["TERM", 1]]}]}]},
      {"token": "karabiner-elements", "full_token": "karabiner-elements", "version": "16.3.0",
       "artifacts": [{"pkg": ["Karabiner-Elements.pkg"]},
                     {"zap": [{"trash": ["~/Library/Preferences/org.pqrs.Karabiner-EventViewer.plist"]}]}]},
      {"token": "keka", "full_token": "keka", "version": "1.4.8,1234",
       "artifacts": [{"app": ["Keka.app"]}]}
    ]
    """#

    private func app(_ name: String, version: String? = nil, bundleID: String? = nil, appStore: Bool = false) -> InstalledApp {
        InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), bundleID: bundleID, version: version, isFromAppStore: appStore)
    }

    @Test func tokenCandidates() {
        #expect(CaskTokenGuess.candidates(forAppNamed: "Visual Studio Code") == ["visual-studio-code", "visual-studio-code-app"])
        #expect(CaskTokenGuess.candidates(forAppNamed: "Battle.net") == ["battlenet", "battle-net", "battlenet-app"])
        #expect(CaskTokenGuess.candidates(forAppNamed: "Notepad++").first == "notepad-plus-plus")
        #expect(CaskTokenGuess.candidates(forAppNamed: "Tailscale").contains("tailscale-app"))
        #expect(CaskTokenGuess.candidates(forAppNamed: "").isEmpty)
    }

    @Test func artifactStringsCollectAppNames() throws {
        let list = try casks(sample)
        #expect(list[0].appFileNames == ["visual studio code.app"])
        #expect(list[1].appFileNames == ["battle.net-setup.app", "battle.net.app"])
        #expect(list[2].appFileNames.isEmpty)
    }

    @Test func filterSkipsManagedApps() throws {
        let installed = try casks(sample)
        let apps = [
            app("Visual Studio Code"),                       // app artifact of an installed cask
            app("Battle.net"),                               // only in the cask's uninstall paths
            app("Karabiner-Elements"),                       // .pkg cask, matched by token
            app("Safari", bundleID: "com.apple.Safari"),     // comes with macOS
            app("Keynote", bundleID: "com.apple.iWork.Keynote", appStore: true),
            app("Karabiner-EventViewer", bundleID: "org.pqrs.Karabiner-EventViewer"),  // bundle ID in zap paths
            app("Karabiner-Event", bundleID: "org.pqrs.Karabiner-Event"),              // only a prefix of it
            app("Firefox"),
        ]
        #expect(UnmanagedApps.filter(apps, installedCasks: installed).map(\.name) == ["Karabiner-Event", "Firefox"])
    }

    @Test func filterUsesInstallerPackage() throws {
        let installed = try casks(#"[{"token": "foo", "full_token": "foo", "artifacts": [{"uninstall": [{"pkgutil": "com.example.foo-suite"}]}]}]"#)
        let helper = app("Foo Helper", bundleID: "com.example.helper")
        #expect(UnmanagedApps.filter([helper], installedCasks: installed).count == 1)
        #expect(UnmanagedApps.filter([helper], installedCasks: installed, packageIDs: [helper.id: ["com.example.foo-suite"]]).isEmpty)
        #expect(UnmanagedApps.parsePackageIDs("volume: /\npath: /Applications/X.app\n\npkgid: com.example.foo-suite\npkg-version: 1.0\n")
                == ["com.example.foo-suite"])
    }

    @Test func bundleIDMentions() {
        #expect(UnmanagedApps.mentions("~/library/preferences/com.foo.app.plist", bundleID: "com.foo.App"))
        #expect(UnmanagedApps.mentions("com.foo.app", bundleID: "com.foo.App"))
        #expect(!UnmanagedApps.mentions("com.foo.apphelper", bundleID: "com.foo.App"))
        #expect(!UnmanagedApps.mentions("anything", bundleID: "NoDots"))
    }

    @Test func suggestionsRequireMatchingApp() throws {
        let available = try casks(sample)
        let apps = [app("Keka", version: "1.4.8"), app("Visual Studio Code"), app("Karabiner-Elements")]
        let found = UnmanagedApps.suggestions(for: apps, casks: available)
        #expect(found[apps[0].id]?.token == "keka")
        #expect(found[apps[1].id]?.token == "visual-studio-code")
        #expect(found[apps[2].id] == nil)  // the cask doesn't reference Karabiner-Elements.app
    }

    @Test func adoptNeedsSameVersionUnlessAutoUpdating() throws {
        let list = try casks(sample)
        #expect(UnmanagedApps.canAdopt(app("Keka", version: "1.4.8"), as: list[3]))
        #expect(!UnmanagedApps.canAdopt(app("Keka", version: "1.4.7"), as: list[3]))
        #expect(UnmanagedApps.canAdopt(app("Visual Studio Code", version: "1.0"), as: list[0]))
    }
}
