// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Testing
@testable import BrewCore

@Suite struct BrewfileTests {
    let sample = """
    # Môj Brewfile
    tap "hashicorp/tap"
    brew "git"
    brew "hashicorp/tap/terraform", args: ["HEAD"] # najnovšie
    cask_args appdir: "/Applications"
    cask 'ghostty'
    mas "Xcode", id: 497799835
    brew "foo" if OS.mac?

    # Collaboration platform for API development
    cask "postman"
    cask "postman"
    """ + "\n"

    @Test func roundTripIsExact() {
        let file = Brewfile(parsing: sample)
        #expect(file.text == sample)
        let noNewline = String(sample.dropLast())
        #expect(Brewfile(parsing: noNewline).text == noNewline)
    }

    @Test func parsesEntries() {
        let entries = Brewfile(parsing: sample).entries
        #expect(entries.map(\.kind) == [.tap, .brew, .brew, .cask, .mas, .cask, .cask])
        let terraform = entries[2]
        #expect(terraform.name == "hashicorp/tap/terraform")
        #expect(terraform.shortName == "terraform")
        #expect(terraform.options == #"args: ["HEAD"]"#)
        #expect(terraform.comment == "najnovšie")
        #expect(entries[3].name == "ghostty")
        #expect(entries[4].masID == "497799835")
    }

    @Test func rubyConditionStaysRaw() {
        #expect(BrewfileEntry.parse(line: #"brew "foo" if OS.mac?"#) == nil)
        #expect(BrewfileEntry.parse(line: "cask_args appdir: \"/Applications\"") == nil)
    }

    @Test func editedEntryIsReRendered() {
        var file = Brewfile(parsing: sample)
        var git = file.entries[1]
        git.comment = "verzovanie"
        file.update(git)
        #expect(file.text.contains("brew \"git\" # verzovanie\n"))
        // the other lines stay unchanged
        #expect(file.text.contains("cask 'ghostty'\n"))
    }

    @Test func detectsDuplicates() {
        let file = Brewfile(parsing: sample)
        #expect(file.duplicateIDs.count == 1)
        #expect(file.duplicateIDs.contains(file.entries[6].id))
    }

    @Test func addPlacesAfterSameKind() {
        var file = Brewfile(parsing: "tap \"a/b\"\nbrew \"git\"\ncask \"x\"\n")
        file.add(BrewfileEntry(kind: .brew, name: "jq"))
        file.add(BrewfileEntry(kind: .mas, name: "Xcode", options: "id: 1"))
        #expect(file.text == "tap \"a/b\"\nbrew \"git\"\nbrew \"jq\"\ncask \"x\"\nmas \"Xcode\", id: 1\n")
    }

    @Test func sortGroupsAndKeepsComments() {
        var file = Brewfile(parsing: sample)
        file.sort(removeDuplicates: true)
        #expect(file.text == """
        # Môj Brewfile
        cask_args appdir: "/Applications"
        brew "foo" if OS.mac?

        tap "hashicorp/tap"

        brew "git"
        brew "hashicorp/tap/terraform", args: ["HEAD"] # najnovšie

        cask 'ghostty'
        # Collaboration platform for API development
        cask "postman"

        mas "Xcode", id: 497799835

        """)
    }

    @Test func cleanupPreviewParsing() {
        let preview = CleanupPreview(parsing: """
        Would uninstall casks:
        sikarugir
        whisky
        Would uninstall formulae:
        aria2
        Would untap:
        frankea/whisky
        Would `brew cleanup`:
        Would remove: /x (5MB)
        Run `brew bundle cleanup --force` to make these changes.
        """)
        #expect(preview.casks == ["sikarugir", "whisky"])
        #expect(preview.formulae == ["aria2"])
        #expect(preview.taps == ["frankea/whisky"])
        #expect(preview.other == ["Would remove: /x (5MB)"])
    }

    // MARK: Stash

    @Test func parsesStashedLinesAnywhere() {
        let text = """
        brew "git"
        #stash: cask "dockdoor" # replaced by WinTab
        cask "raycast"
        # stash: mas "Things 3", id: 904280696
        # just a comment
        """ + "\n"
        let file = Brewfile(parsing: text)
        #expect(file.text == text)
        #expect(file.entries.map(\.name) == ["git", "raycast"])
        #expect(file.stashedEntries.map(\.name) == ["dockdoor", "Things 3"])
        #expect(file.stashedEntries[0].comment == "replaced by WinTab")
        #expect(file.stashedEntries[1].masID == "904280696")
        #expect(file.isStashed(kind: .cask, name: "DockDoor"))
        #expect(!file.contains(kind: .cask, name: "dockdoor"))
    }

    @Test func stashMovesEntryToBlockAtEnd() {
        var file = Brewfile(parsing: "brew \"git\"\ncask \"dockdoor\"\ncask \"dockdoor\"\ncask \"raycast\"\n\n")
        let id = file.entries[1].id
        file.stash(ids: [id])
        #expect(file.text == """
        brew "git"
        cask "raycast"

        \(Brewfile.stashHeader)
        # stash: cask "dockdoor"

        """)
        let raycast = file.entries[1].id
        file.stash(ids: [raycast])
        #expect(file.stashedEntries.map(\.name) == ["dockdoor", "raycast"])
        #expect(file.text.hasSuffix("# stash: cask \"dockdoor\"\n# stash: cask \"raycast\"\n"))
    }

    @Test func unstashRestoresEntryAndDropsEmptyHeader() {
        var file = Brewfile(parsing: "brew \"git\"\ncask \"raycast\"\n")
        file.stash(BrewfileEntry(kind: .cask, name: "dockdoor"))
        file.unstash(ids: Set(file.stashedEntries.map(\.id)))
        #expect(file.text == "brew \"git\"\ncask \"raycast\"\ncask \"dockdoor\"\n")
        #expect(file.stashedEntries.isEmpty)
    }

    @Test func addGoesBeforeStashBlockInEmptyFile() {
        var file = Brewfile()
        file.stash(BrewfileEntry(kind: .cask, name: "dockdoor"))
        file.add(BrewfileEntry(kind: .brew, name: "git"))
        #expect(file.entries.map(\.name) == ["git"])
        #expect(file.text.hasPrefix("brew \"git\"\n"))
    }

    @Test func removeStashed() {
        var file = Brewfile(parsing: "brew \"git\"\n")
        file.stash(BrewfileEntry(kind: .cask, name: "dockdoor"))
        file.removeStashed(ids: Set(file.stashedEntries.map(\.id)))
        #expect(file.text == "brew \"git\"\n")
    }

    @Test func sortKeepsStashBlockAtEnd() {
        var file = Brewfile(parsing: """
        # stash: cask "zed"
        cask "raycast"
        # stash: brew "wget"
        brew "git"
        """ + "\n")
        file.sort()
        #expect(file.text == """
        brew "git"

        cask "raycast"

        \(Brewfile.stashHeader)
        # stash: brew "wget"
        # stash: cask "zed"

        """)
    }

    @Test func restoreStashAfterDump() {
        var old = Brewfile(parsing: "cask \"raycast\"\n")
        old.stash(BrewfileEntry(kind: .cask, name: "dockdoor"))
        old.stash(BrewfileEntry(kind: .cask, name: "zed"))
        // `brew bundle dump` wrote the installed packages only; zed was installed again meanwhile.
        var dumped = Brewfile(parsing: "cask \"raycast\"\ncask \"zed\"\n")
        dumped.restoreStash(from: old)
        #expect(dumped.stashedEntries.map(\.name) == ["dockdoor"])
        #expect(dumped.entries.map(\.name) == ["raycast", "zed"])
    }
}
