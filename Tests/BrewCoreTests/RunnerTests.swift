// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

@Suite struct RunnerTests {
    @Test func streamsLinesAndExitCode() async throws {
        let stream = ProcessRunner.stream(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", #"printf 'jeden\ndva\n'; printf '\033[1mtučné\033[0m\n'; echo chyba >&2; printf 'bez konca'; exit 3"#],
            environment: [:]
        )
        var lines: [String] = []
        var code: Int32?
        for try await event in stream {
            switch event {
            case .output(let line): lines.append(line)
            case .exit(let c): code = c
            }
        }
        #expect(lines == ["jeden", "dva", "tučné", "chyba", "bez konca"])
        #expect(code == 3)
    }

    @Test func captureThrowsWithStderr() async {
        await #expect(throws: CommandError.self) {
            _ = try await ProcessRunner.capture(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo zle >&2; exit 1"], environment: [:])
        }
        let out = try? await ProcessRunner.capture(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo ok"], environment: [:])
        #expect(out == "ok\n")
    }

    @Test func parsesMasList() {
        let apps = MasApp.parseList("""
        682658836  GarageBand  (10.4.14)
        497799835  Xcode       (27.2)
        1295203466 Microsoft Remote Desktop (10.9.10)
        """)
        #expect(apps["682658836"] == MasApp(id: "682658836", name: "GarageBand", version: "10.4.14"))
        #expect(apps["1295203466"]?.name == "Microsoft Remote Desktop")
        #expect(apps.count == 3)
    }
}

@Suite struct InstalledStateTests {
    @Test func qualifiedNamesMatchExactly() {
        let index = ["whisky": 1, "frankea/whisky/whisky": 2, "git": 3]
        #expect(InstalledState.lookup("frankea/whisky/whisky", in: index) == 2)
        #expect(InstalledState.lookup("other/tap/whisky", in: index) == nil)
        #expect(InstalledState.lookup("homebrew/core/git", in: index) == 3)
        #expect(InstalledState.lookup("Whisky", in: index) == 1)
    }

    @Test func deprecationText() {
        #expect(Deprecation.warning(deprecated: false, reason: nil, disabled: nil, disableReason: nil, replacement: nil) == nil)
        #expect(Deprecation.warning(deprecated: true, reason: "unmaintained", disabled: false, disableReason: nil, replacement: "foo")
                == "Deprecated: the project is no longer maintained. Replacement: foo")
        #expect(Deprecation.warning(deprecated: true, reason: nil, disabled: true, disableReason: "repo_archived", replacement: nil)
                == "Disabled in Homebrew: the repository is archived")
    }
}
