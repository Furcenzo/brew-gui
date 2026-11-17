// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

/// Volá skutočný `brew` – spúšťa sa len s `BREWGUI_INTEGRATION=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BREWGUI_INTEGRATION"] == "1"))
struct IntegrationTests {
    @Test func deprecatedCaskHasWarning() async throws {
        let client = try #require(BrewClient.locate())
        let official = try await client.info(kind: .cask, name: "whisky")
        #expect(official.lifecycleWarning?.hasPrefix("Nepodporované") == true)
        let fork = try await client.info(kind: .cask, name: "frankea/whisky/whisky")
        #expect(fork.token == "frankea/whisky/whisky")
        #expect(fork.lifecycleWarning == nil)
        print("whisky:", official.lifecycleWarning ?? "-")
    }

    @Test func installedStateResolvesTapQualifiedCask() async throws {
        let client = try #require(BrewClient.locate())
        let state = try await client.installedState()
        let fork = BrewfileEntry(kind: .cask, name: "frankea/whisky/whisky")
        let official = BrewfileEntry(kind: .cask, name: "whisky")
        print("fork:", state.status(of: fork), "official:", state.status(of: official))
        #expect(state.status(of: fork).isInstalled)
    }
}
