// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import BrewCore
import Observation
import OSLog
import SwiftUI

/// Jedna spustená brew operácia s priebežným výstupom.
@MainActor @Observable
final class Job: Identifiable {
    enum State: Equatable { case running, succeeded, failed(Int32), cancelled }

    let id = UUID()
    let title: String
    let command: String
    var lines: [String] = []
    var state: State = .running
    let started = Date()
    @ObservationIgnored var task: Task<Void, Never>?

    init(title: String, command: String) {
        self.title = title
        self.command = command
    }

    var isRunning: Bool { state == .running }
    var lastLine: String { lines.last ?? command }
}

enum SidebarItem: Hashable {
    case brewfile(EntryKind?)
    case missing
    case sync
    case outdated
    case unmanaged
    case search
}

@MainActor @Observable
final class AppModel {
    static let defaultFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Brewfile")

    let client: BrewClient?

    // Brewfile
    private(set) var fileURL: URL
    /// Každá zmena sa zaregistruje do Undo (⌘Z) a po chvíľke sa automaticky uloží.
    var brewfile = Brewfile() {
        didSet { brewfileDidChange(from: oldValue) }
    }
    private(set) var savedText = ""
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var trackChanges = true
    @ObservationIgnored private var registerUndo = true
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    /// Súbor, ktorý sme v tejto session už zálohovali (záloha = stav pred prvým uložením).
    @ObservationIgnored private var backedUpFile: URL?
    @ObservationIgnored private var lastStateRefresh = Date.distantPast
    @ObservationIgnored private let log = Logger(subsystem: "io.github.furcenzo.brewgui", category: "state")
    var isDirty: Bool { brewfile.text != savedText }
    var externalChangeDetected = false

    // Stav systému
    private(set) var installed = InstalledState()
    private(set) var installedLoaded = false
    private(set) var loadingInstalled = false
    private(set) var outdated: [OutdatedPackage] = []
    private(set) var outdatedLoaded = false
    private(set) var loadingOutdated = false
    var greedyOutdated = false
    private(set) var allFormulae: [String] = []
    private(set) var allCasks: [String] = []

    // Úlohy
    private(set) var jobs: [Job] = []
    var currentJob: Job? { jobs.last }
    var isBusy: Bool { jobs.contains { $0.isRunning } }
    var consoleExpanded = false

    // UI
    var sidebarSelection: SidebarItem? = .brewfile(nil)
    var errorMessage: String?

    init() {
        Self.migrateLegacyDefaults()
        client = BrewClient.locate()
        let stored = UserDefaults.standard.string(forKey: "lastBrewfile").map { URL(fileURLWithPath: $0) }
        if let stored, FileManager.default.fileExists(atPath: stored.path) {
            fileURL = stored
        } else {
            fileURL = Self.defaultFile
        }
        loadFile(fileURL)
    }

    /// Staršie verzie mali bundle id `local.brewgui`. Ak nová doména nastavení ešte neexistuje,
    /// jednorazovo do nej skopírujeme starú (posledný Brewfile, režim zobrazenia, veľkosť okna…).
    private static func migrateLegacyDefaults() {
        let legacyID = "local.brewgui"
        guard let currentID = Bundle.main.bundleIdentifier, currentID != legacyID else { return }
        let defaults = UserDefaults.standard
        guard defaults.persistentDomain(forName: currentID) == nil,
              let legacy = defaults.persistentDomain(forName: legacyID), !legacy.isEmpty
        else { return }
        defaults.setPersistentDomain(legacy, forName: currentID)
    }

    // MARK: - Súbor

    func loadFile(_ url: URL) {
        do {
            let text = FileManager.default.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : ""
            autosaveTask?.cancel()
            if url != fileURL { backedUpFile = nil }
            fileURL = url
            trackChanges = false
            brewfile = Brewfile(parsing: text)
            trackChanges = true
            savedText = brewfile.text
            undoManager?.removeAllActions()
            externalChangeDetected = false
            UserDefaults.standard.set(url.path, forKey: "lastBrewfile")
        } catch {
            errorMessage = String(localized: "Couldn't load the Brewfile: \(error.localizedDescription)")
        }
    }

    func reloadFile() { loadFile(fileURL) }

    private func brewfileDidChange(from old: Brewfile) {
        guard trackChanges, old.text != brewfile.text else { return }
        if registerUndo, let undoManager {
            undoManager.registerUndo(withTarget: self) { model in
                MainActor.assumeIsolated { model.brewfile = old }
            }
            undoManager.setActionName(String(localized: "Brewfile Edit"))
        }
        // Zmeny zvonku, ktoré ešte nie sú uložené, by sme autosave-om prepísali – vtedy čakáme na rozhodnutie.
        guard !externalChangeDetected else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.isDirty else { return }
            self.save()
        }
    }

    /// Zmena z textového editora – undo rieši samotný editor.
    func setTextFromEditor(_ text: String) {
        registerUndo = false
        brewfile = Brewfile(parsing: text)
        registerUndo = true
    }

    func save() {
        autosaveTask?.cancel()
        do {
            if backedUpFile != fileURL {
                try backupCurrentFile()
                backedUpFile = fileURL
            }
            try brewfile.text.write(to: fileURL, atomically: true, encoding: .utf8)
            savedText = brewfile.text
            externalChangeDetected = false
        } catch {
            errorMessage = String(localized: "Couldn't save the Brewfile: \(error.localizedDescription)")
        }
    }

    /// Pred prvým uložením v session odloží pôvodný súbor do ~/Library/Application Support/BrewGUI/Backups.
    private func backupCurrentFile() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let dir = URL.applicationSupportDirectory.appendingPathComponent("BrewGUI/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        let stamp = formatter.string(from: Date())
        let target = dir.appendingPathComponent("\(fileURL.lastPathComponent)-\(stamp)")
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: fileURL, to: target)
        }
    }

    var backupsDirectory: URL { URL.applicationSupportDirectory.appendingPathComponent("BrewGUI/Backups", isDirectory: true) }

    /// Volané pri aktivácii aplikácie – zistí, či niekto súbor zmenil zvonku.
    func checkExternalChanges() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8), text != savedText else { return }
        if isDirty {
            externalChangeDetected = true
        } else {
            loadFile(fileURL)
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Open Brewfile")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = fileURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { loadFile(url) }
    }

    // MARK: - Úpravy

    func add(_ entry: BrewfileEntry) {
        brewfile.add(entry)
    }

    func update(_ entry: BrewfileEntry) {
        brewfile.update(entry)
    }

    func remove(ids: Set<UUID>) {
        brewfile.remove(ids: ids)
    }

    func addToBrewfile(kind: EntryKind, name: String) {
        guard !brewfile.contains(kind: kind, name: name) else { return }
        brewfile.add(BrewfileEntry(kind: kind, name: name))
    }

    // MARK: - Stav

    func refreshAll() async {
        async let a: Void = refreshInstalled()
        async let b: Void = refreshOutdated()
        async let c: Void = loadNames()
        _ = await (a, b, c)
    }

    /// Volané pri prepnutí do aplikácie – zachytí zmeny urobené mimo nej (napr. `brew install` v Termináli).
    /// Počas bežiacej operácie sa neobnovuje (urobí sa po jej skončení) a najviac raz za 10 s.
    func refreshOnActivation() {
        guard client != nil, !isBusy, Date().timeIntervalSince(lastStateRefresh) > 10 else { return }
        log.notice("Refreshing status after app activation")
        Task {
            await refreshInstalled()
            await refreshOutdated()
        }
    }

    func refreshInstalled() async {
        guard let client, !loadingInstalled else { return }
        loadingInstalled = true
        lastStateRefresh = Date()
        defer { loadingInstalled = false }
        do {
            installed = try await client.installedState()
            installedLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshOutdated() async {
        guard let client, !loadingOutdated else { return }
        loadingOutdated = true
        defer { loadingOutdated = false }
        do {
            outdated = try await client.outdated(greedy: greedyOutdated)
            outdatedLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadNames() async {
        guard let client, allFormulae.isEmpty else { return }
        if let names = try? await client.allNames() {
            allFormulae = names.formulae
            allCasks = names.casks
        }
    }

    func status(of entry: BrewfileEntry) -> EntryStatus {
        installedLoaded ? installed.status(of: entry) : .unknown
    }

    var missingEntries: [BrewfileEntry] {
        guard installedLoaded else { return [] }
        return brewfile.entries.filter { status(of: $0) == .missing }
    }

    /// Nainštalované balíky (na požiadanie), tapy a appky, ktoré v Brewfile nie sú.
    var unmanaged: [UnmanagedItem] {
        guard installedLoaded else { return [] }
        let entries = brewfile.entries
        func listed(_ kind: EntryKind, _ names: [String]) -> Bool {
            let keys = Set(names.map { $0.lowercased() })
            return entries.contains { $0.kind == kind && (keys.contains($0.name.lowercased()) || keys.contains($0.shortName.lowercased())) }
        }
        var items: [UnmanagedItem] = []
        for tap in installed.taps.sorted() where !listed(.tap, [tap]) {
            items.append(UnmanagedItem(kind: .tap, name: tap, desc: nil, version: nil))
        }
        for f in installed.formulae where f.isInstalledOnRequest {
            let names = [f.name, f.fullName] + (f.aliases ?? []) + (f.oldnames ?? [])
            if !listed(.brew, names) {
                items.append(UnmanagedItem(kind: .brew, name: f.fullName, desc: f.desc, version: f.installedVersion))
            }
        }
        for c in installed.casks {
            if !listed(.cask, [c.token, c.fullToken] + (c.oldTokens ?? [])) {
                items.append(UnmanagedItem(kind: .cask, name: c.fullToken, desc: c.desc, version: c.installed))
            }
        }
        if let mas = installed.masApps {
            let ids = Set(entries.compactMap(\.masID))
            for app in mas.values.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) where !ids.contains(app.id) {
                items.append(UnmanagedItem(kind: .mas, name: app.name, desc: "App Store ID \(app.id)", version: app.version, masID: app.id))
            }
        }
        return items
    }

    // MARK: - Spúšťanie brew príkazov

    /// Skript pre `sudo -A` – heslo zadá používateľ do systémového dialógu.
    @ObservationIgnored private lazy var askpassURL: URL? = {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("BrewGUI", isDirectory: true)
        let url = dir.appendingPathComponent("askpass.sh")
        let prompt = String(localized: "Homebrew needs an administrator password to finish the installation:")
            .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "’")
        let script = """
        #!/bin/sh
        exec /usr/bin/osascript -e 'text returned of (display dialog "\(prompt)" with title "Brew GUI" default answer "" with hidden answer with icon caution)'
        """
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            return url
        } catch {
            return nil
        }
    }()

    /// Spustí `brew <args>` so živým výstupom v konzole; po dokončení obnoví stav.
    @discardableResult
    func run(_ title: String, _ args: [String], refresh: Bool = true, onFinish: (@MainActor (Bool) -> Void)? = nil) -> Job? {
        guard let client else {
            errorMessage = String(localized: "Homebrew not found.")
            return nil
        }
        let job = Job(title: title, command: "brew " + args.map(shellQuote).joined(separator: " "))
        jobs.append(job)
        if jobs.count > 30 { jobs.removeFirst(jobs.count - 30) }
        job.lines.append("$ " + job.command)

        let stream = client.stream(args, askpass: askpassURL)
        job.task = Task { [weak self] in
            do {
                for try await event in stream {
                    switch event {
                    case .output(let line): job.lines.append(line)
                    case .exit(let code): job.state = code == 0 ? .succeeded : .failed(code)
                    }
                }
                if Task.isCancelled { job.state = .cancelled }
            } catch {
                job.lines.append(String(localized: "Error: \(error.localizedDescription)"))
                job.state = Task.isCancelled ? .cancelled : .failed(-1)
            }
            if job.state == .running { job.state = .cancelled }
            if job.state != .succeeded { self?.consoleExpanded = true }
            onFinish?(job.state == .succeeded)
            if refresh {
                await self?.refreshInstalled()
                await self?.refreshOutdated()
            }
        }
        return job
    }

    func cancel(_ job: Job) {
        job.task?.cancel()
    }

    func clearFinishedJobs() {
        jobs.removeAll { !$0.isRunning }
    }

    private func shellQuote(_ arg: String) -> String {
        arg.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=@:+".contains($0) }) ? arg : "'\(arg.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // MARK: - Konkrétne operácie

    func install(_ entry: BrewfileEntry) {
        switch entry.kind {
        case .tap: run("Tap \(entry.name)", ["tap", entry.name])
        case .brew: run(String(localized: "Installing \(entry.name)"), ["install", "--formula", entry.name])
        case .cask: run(String(localized: "Installing \(entry.name)"), ["install", "--cask", entry.name])
        case .mas:
            if let id = entry.masID { runMas(String(localized: "Installing \(entry.name)"), ["install", id]) }
        default: break
        }
    }

    func install(kind: EntryKind, name: String) {
        install(BrewfileEntry(kind: kind, name: name))
    }

    func uninstall(kind: EntryKind, name: String) {
        switch kind {
        case .tap: run("Untap \(name)", ["untap", name])
        case .brew: run(String(localized: "Uninstalling \(name)"), ["uninstall", "--formula", name])
        case .cask: run(String(localized: "Uninstalling \(name)"), ["uninstall", "--cask", name])
        case .mas: runMas(String(localized: "Uninstalling \(name)"), ["uninstall", name])
        default: break
        }
    }

    func upgrade(_ packages: [OutdatedPackage]) {
        let formulae = packages.filter { !$0.isCask }.map(\.name)
        let casks = packages.filter(\.isCask).map(\.name)
        if !formulae.isEmpty { run("Upgrade (\(formulae.count) formulae)", ["upgrade", "--formula"] + formulae) }
        if !casks.isEmpty { run("Upgrade (\(casks.count) casks)", ["upgrade", "--cask"] + (greedyOutdated ? ["--greedy"] : []) + casks) }
    }

    func upgradeAll() {
        run(String(localized: "Upgrading Everything"), ["upgrade"] + (greedyOutdated ? ["--greedy"] : []))
    }

    func brewUpdate() {
        run("brew update", ["update"])
    }

    func bundleCheck() {
        run(String(localized: "Checking Brewfile"), ["bundle", "check", "--verbose", "--file=\(fileURL.path)"], refresh: false)
    }

    func bundleInstall(upgrade: Bool) {
        var args = ["bundle", "install", "--file=\(fileURL.path)"]
        if !upgrade { args.append("--no-upgrade") }
        run(String(localized: "Installing from Brewfile"), args)
    }

    func bundleCleanup() {
        run(String(localized: "Brewfile Cleanup"), ["bundle", "cleanup", "--force", "--file=\(fileURL.path)"])
    }

    func bundleDump(to url: URL, describe: Bool) {
        var args = ["bundle", "dump", "--force", "--file=\(url.path)"]
        if describe { args.append("--describe") }
        run(String(localized: "Exporting State to \(url.lastPathComponent)"), args, refresh: false)
    }

    /// `mas` beží cez rovnaký mechanizmus – spúšťame ho cez `brew` prostredie ako externý príkaz.
    private func runMas(_ title: String, _ args: [String]) {
        guard let client else { return }
        let mas = client.brewURL.deletingLastPathComponent().appendingPathComponent("mas")
        guard FileManager.default.isExecutableFile(atPath: mas.path) else {
            errorMessage = String(localized: "Managing App Store apps requires `mas` (brew install mas).")
            return
        }
        let job = Job(title: title, command: "mas " + args.joined(separator: " "))
        jobs.append(job)
        job.lines.append("$ " + job.command)
        let stream = ProcessRunner.stream(executable: mas, arguments: args, environment: client.environment(quiet: true))
        job.task = Task { [weak self] in
            do {
                for try await event in stream {
                    switch event {
                    case .output(let line): job.lines.append(line)
                    case .exit(let code): job.state = code == 0 ? .succeeded : .failed(code)
                    }
                }
            } catch {
                job.lines.append(String(localized: "Error: \(error.localizedDescription)"))
                job.state = .failed(-1)
            }
            if job.state == .running { job.state = .cancelled }
            await self?.refreshInstalled()
        }
    }

    func cleanupPreview() async -> CleanupPreview? {
        guard let client else { return nil }
        do {
            return try await client.cleanupPreview(file: fileURL)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func info(kind: EntryKind, name: String) async throws -> PackageInfo {
        guard let client else { throw CommandError(command: "brew", status: -1, stderr: String(localized: "Homebrew not found.")) }
        return try await client.info(kind: kind, name: name)
    }
}

struct UnmanagedItem: Identifiable, Hashable {
    var kind: EntryKind
    var name: String
    var desc: String?
    var version: String?
    var masID: String? = nil
    var id: String { "\(kind.rawValue):\(masID ?? name)" }
}
