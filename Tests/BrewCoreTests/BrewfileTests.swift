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
        // ostatné riadky ostanú bez zmeny
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
}
