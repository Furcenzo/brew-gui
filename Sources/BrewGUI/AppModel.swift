// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import BrewCore
import Observation
import OSLog
import SwiftUI

/// A single running brew operation with live output.
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
    case stashed
    case sync
    case outdated
    case unmanaged
    case unused
    case search
}

@MainActor @Observable
final class AppModel {
    static let defaultFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Brewfile")

    let client: BrewClient?

    // Brewfile
    private(set) var fileURL: URL
    /// Every change is registered with Undo (⌘Z) and saved automatically after a short delay.
    var brewfile = Brewfile() {
        didSet { brewfileDidChange(from: oldValue) }
    }
    private(set) var savedText = ""
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var trackChanges = true
    @ObservationIgnored private var registerUndo = true
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    /// The file already backed up in this session (the backup is the state before the first save).
    @ObservationIgnored private var backedUpFile: URL?
    @ObservationIgnored private var lastStateRefresh = Date.distantPast
    @ObservationIgnored private let log = Logger(subsystem: "io.github.furcenzo.brewgui", category: "state")
    var isDirty: Bool { brewfile.text != savedText }
    var externalChangeDetected = false

    // System state
    private(set) var installed = InstalledState()
    private(set) var installedLoaded = false
    private(set) var loadingInstalled = false
    private(set) var outdated: [OutdatedPackage] = []
    private(set) var outdatedLoaded = false
    private(set) var loadingOutdated = false
    var greedyOutdated = false
    private(set) var allFormulae: [String] = []
    private(set) var allCasks: [String] = []
    /// Apps installed by Homebrew casks (menu bar list).
    private(set) var caskApps: [CaskApp] = []

    // Apps not managed by Homebrew or the App Store
    private(set) var unmanagedApps: [UnmanagedApp] = []
    private(set) var appsLoaded = false
    private(set) var loadingApps = false
    @ObservationIgnored private var caskInfoCache: [String: CaskInfo] = [:]

    // Apps not opened for a while
    private(set) var appUsage: [InstalledApp: AppUsage] = [:]
    private(set) var usageLoaded = false
    private(set) var loadingUsage = false
    static let unusedDaysKey = "unusedAppsDays"
    static let keptAppsKey = "keptUnusedApps"
    /// Apps the user chose to keep – not suggested any more (paths).
    private(set) var keptApps: Set<String> = Set(UserDefaults.standard.stringArray(forKey: AppModel.keptAppsKey) ?? [])

    // Jobs
    private(set) var jobs: [Job] = []
    var currentJob: Job? { jobs.last }
    var isBusy: Bool { jobs.contains { $0.isRunning } }
    var consoleExpanded = false

    // UI
    var sidebarSelection: SidebarItem? = .brewfile(nil)
    var errorMessage: String?

    static let showMenuBarIconKey = "showMenuBarIcon"
    static var showsMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: showMenuBarIconKey) == nil || UserDefaults.standard.bool(forKey: showMenuBarIconKey)
    }

    /// Started by "Open at login": the main window closes as soon as it appears (see ContentView).
    var hideWindowAtLaunch = false

    /// A package to show on the Search page (from the menu bar or BREWGUI_SEARCH); picked up once by SearchView.
    var pendingSearchQuery: String?

    // Debugging (scripts/screenshots.sh): picked up once by BrewfileView
    var debugSelectEntry: String?
    /// Shown instead of `brew outdated` (BREWGUI_SAMPLE_OUTDATED).
    @ObservationIgnored var debugOutdated: [OutdatedPackage]?
    /// Only list the apps of casks that are in the open Brewfile (BREWGUI_APPS_FROM_BREWFILE).
    @ObservationIgnored var debugAppsFromBrewfile = false
    /// Shown instead of the apps in Applications on the Unused Apps page (BREWGUI_SAMPLE_UNUSED).
    @ObservationIgnored var debugUnused: [(app: InstalledApp, usage: AppUsage, source: AppSource)]?
    /// Shown instead of the real path of the Brewfile (BREWGUI_DISPLAY_PATH, e.g. `~/Brewfile` for screenshots).
    var debugDisplayPath: String?

    /// Path of the open Brewfile as shown in the UI.
    var filePath: String { debugDisplayPath ?? fileURL.path(percentEncoded: false) }

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

    /// Older versions used the bundle ID `local.brewgui`. If the new defaults domain doesn't exist yet,
    /// copy the old one into it once (last Brewfile, view mode, window size…).
    private static func migrateLegacyDefaults() {
        let legacyID = "local.brewgui"
        guard let currentID = Bundle.main.bundleIdentifier, currentID != legacyID else { return }
        let defaults = UserDefaults.standard
        guard defaults.persistentDomain(forName: currentID) == nil,
              let legacy = defaults.persistentDomain(forName: legacyID), !legacy.isEmpty
        else { return }
        defaults.setPersistentDomain(legacy, forName: currentID)
    }

    // MARK: - File

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
        // Autosave would overwrite unsaved external changes – wait for the user's decision instead.
        guard !externalChangeDetected else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.isDirty else { return }
            self.save()
        }
    }

    /// A change from the text editor – the editor handles undo itself.
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

    /// Before the first save in a session, copies the original file to ~/Library/Application Support/BrewGUI/Backups.
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

    /// Called when the app is activated – detects whether the file was changed externally.
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

    // MARK: - Editing

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

    /// Removes every Brewfile entry for the package (including duplicates).
    func removeFromBrewfile(kind: EntryKind, name: String) {
        let key = BrewfileEntry(kind: kind, name: name).identityKey
        let ids = Set(brewfile.entries.filter { $0.identityKey == key }.map(\.id))
        if !ids.isEmpty { brewfile.remove(ids: ids) }
    }

    // MARK: - State

    func refreshAll() async {
        async let a: Void = refreshInstalled()
        async let b: Void = refreshOutdated()
        async let c: Void = loadNames()
        _ = await (a, b, c)
    }

    /// Called when switching to the app – picks up changes made outside it (e.g. `brew install` in Terminal).
    /// Skipped while an operation is running (it refreshes when it finishes) and runs at most once every 10 s.
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
            let casks = installed.casks
            let apps = await Task.detached { CaskApp.find(in: casks) }.value
            caskApps = debugAppsFromBrewfile ? apps.filter { brewfile.contains(kind: .cask, name: $0.token) } : apps
        } catch {
            errorMessage = error.localizedDescription
        }
        if appsLoaded { await refreshApps() }
    }

    /// Scans /Applications and ~/Applications for apps that Homebrew, the App Store or macOS don't manage,
    /// and looks up a matching cask for each of them.
    func refreshApps() async {
        guard let client, !loadingApps else { return }
        if !installedLoaded { await refreshInstalled() }
        guard installedLoaded else { return }
        loadingApps = true
        defer { loadingApps = false }
        // Debugging: BREWGUI_APPS_DIRS=/dir1:/dir2 scans other folders instead of the Applications folders.
        let directories = ProcessInfo.processInfo.environment["BREWGUI_APPS_DIRS"]
            .map { $0.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) } }
            ?? InstalledApp.standardDirectories
        let found = await Task.detached { InstalledApp.scan(directories) }.value
        var apps = UnmanagedApps.filter(found, installedCasks: installed.casks)
        // Helper apps installed by a cask's .pkg (e.g. Karabiner-EventViewer) are recognised by the package ID.
        var packageIDs: [String: [String]] = [:]
        for app in apps {
            let output = try? await ProcessRunner.capture(
                executable: URL(fileURLWithPath: "/usr/sbin/pkgutil"), arguments: ["--file-info", app.url.path],
                environment: ProcessInfo.processInfo.environment, allowFailure: true)
            packageIDs[app.id] = UnmanagedApps.parsePackageIDs(output ?? "")
        }
        apps = UnmanagedApps.filter(apps, installedCasks: installed.casks, packageIDs: packageIDs)
        await loadNames()
        let known = Set(allCasks)
        var missing: [String] = []
        for app in apps {
            for token in CaskTokenGuess.candidates(forAppNamed: app.name)
            where known.contains(token) && caskInfoCache[token] == nil && !missing.contains(token) {
                missing.append(token)
            }
        }
        for cask in await client.casks(missing) { caskInfoCache[cask.token] = cask }
        let suggestions = UnmanagedApps.suggestions(for: apps, casks: Array(caskInfoCache.values))
        unmanagedApps = apps.map { UnmanagedApp(app: $0, cask: suggestions[$0.id]) }
        appsLoaded = true
    }

    /// Scans the Applications folders and reads when each app was last opened (Spotlight).
    func refreshUsage() async {
        guard !loadingUsage else { return }
        if !installedLoaded { await refreshInstalled() }
        loadingUsage = true
        defer { loadingUsage = false }
        if let debugUnused {
            appUsage = Dictionary(uniqueKeysWithValues: debugUnused.map { ($0.app, $0.usage) })
            usageLoaded = true
            return
        }
        let directories = ProcessInfo.processInfo.environment["BREWGUI_APPS_DIRS"]
            .map { $0.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) } }
            ?? InstalledApp.standardDirectories
        appUsage = await Task.detached {
            let apps = InstalledApp.scan(directories)
            return Dictionary(uniqueKeysWithValues: apps.map { ($0, AppUsage.read($0.url)) })
        }.value
        usageLoaded = true
    }

    /// How many days without opening make an app unused (Unused Apps page).
    var unusedDays: Int = {
        let days = UserDefaults.standard.integer(forKey: AppModel.unusedDaysKey)
        return days > 0 ? days : UnusedApps.defaultDays
    }() {
        didSet { UserDefaults.standard.set(unusedDays, forKey: Self.unusedDaysKey) }
    }

    /// Apps not opened for `unusedDays` days, with where they come from.
    func unusedApps(days: Int, includeKept: Bool) -> [UnusedApp] {
        guard usageLoaded else { return [] }
        let usage = Dictionary(uniqueKeysWithValues: appUsage.map { ($0.key.id, $0.value) })
        let masApps = installed.masApps.map { Array($0.values) } ?? []
        return UnusedApps.filter(Array(appUsage.keys), usage: usage, days: days)
            .filter { includeKept || !keptApps.contains($0.id) }
            .map { app in
                UnusedApp(app: app, usage: usage[app.id] ?? AppUsage(),
                          source: debugUnused?.first { $0.app == app }?.source
                              ?? UnusedApps.source(of: app, caskApps: caskApps, masApps: masApps),
                          isKept: keptApps.contains(app.id))
            }
    }

    func setKept(_ app: UnusedApp, _ kept: Bool) {
        if kept { keptApps.insert(app.id) } else { keptApps.remove(app.id) }
        UserDefaults.standard.set(keptApps.sorted(), forKey: Self.keptAppsKey)
    }

    func refreshOutdated() async {
        guard let client, !loadingOutdated else { return }
        loadingOutdated = true
        defer { loadingOutdated = false }
        do {
            let packages = try await client.outdated(greedy: greedyOutdated)
            outdated = debugOutdated ?? packages
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

    func search(_ query: String, scope: PackageSearch.Scope = .all, limit: Int = 300) -> [PackageSearchResult] {
        PackageSearch.results(for: query, formulae: allFormulae, casks: allCasks, scope: scope, limit: limit)
    }

    func isInstalled(_ result: PackageSearchResult) -> Bool {
        switch result.kind {
        case .brew: installed.formula(named: result.name)?.installedVersion != nil
        case .cask: installed.cask(named: result.name)?.installed != nil
        default: false
        }
    }

    func status(of entry: BrewfileEntry) -> EntryStatus {
        installedLoaded ? installed.status(of: entry) : .unknown
    }

    var missingEntries: [BrewfileEntry] {
        guard installedLoaded else { return [] }
        return brewfile.entries.filter { status(of: $0) == .missing }
    }

    /// Packages installed on request, taps and apps that are not in the Brewfile.
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

    // MARK: - Running brew commands

    /// Script for `sudo -A` – the user enters the password in a system dialog.
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

    /// Runs `brew <args>` with live output in the console; refreshes the state when finished.
    @discardableResult
    /// `revealOnFailure: false` keeps the console collapsed when the command fails (used for background jobs).
    func run(
        _ title: String, _ args: [String], refresh: Bool = true, revealOnFailure: Bool = true,
        onFinish: (@MainActor (Bool) -> Void)? = nil
    ) -> Job? {
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
            if job.state != .succeeded && revealOnFailure { self?.consoleExpanded = true }
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

    // MARK: - Operations

    /// `onFinish` is called with `true` when the operation succeeded.
    func install(_ entry: BrewfileEntry, onFinish: (@MainActor (Bool) -> Void)? = nil) {
        switch entry.kind {
        case .tap: run("Tap \(entry.name)", ["tap", entry.name], onFinish: onFinish)
        case .brew: run(String(localized: "Installing \(entry.name)"), ["install", "--formula", entry.name], onFinish: onFinish)
        case .cask: run(String(localized: "Installing \(entry.name)"), ["install", "--cask", entry.name], onFinish: onFinish)
        case .mas:
            if let id = entry.masID { runMas(String(localized: "Installing \(entry.name)"), ["install", id], onFinish: onFinish) }
        default: break
        }
    }

    func install(kind: EntryKind, name: String) {
        install(BrewfileEntry(kind: kind, name: name))
    }

    /// Installs the package and, once the installation succeeds, adds it to the Brewfile.
    func installAndAddToBrewfile(kind: EntryKind, name: String) {
        install(BrewfileEntry(kind: kind, name: name)) { [weak self] succeeded in
            if succeeded { self?.addToBrewfile(kind: kind, name: name) }
        }
    }

    /// `onFinish` is called with `true` when the operation succeeded.
    func uninstall(kind: EntryKind, name: String, onFinish: (@MainActor (Bool) -> Void)? = nil) {
        switch kind {
        case .tap: run("Untap \(name)", ["untap", name], onFinish: onFinish)
        case .brew: run(String(localized: "Uninstalling \(name)"), ["uninstall", "--formula", name], onFinish: onFinish)
        case .cask: run(String(localized: "Uninstalling \(name)"), ["uninstall", "--cask", name], onFinish: onFinish)
        case .mas: runMas(String(localized: "Uninstalling \(name)"), ["uninstall", name], onFinish: onFinish)
        default: break
        }
    }

    /// Lets Homebrew take over an app installed by hand (`brew install --cask --adopt`), without replacing it.
    func adopt(_ item: UnmanagedApp, addToBrewfile: Bool) {
        guard let cask = item.cask else { return }
        run(String(localized: "Adopting \(item.app.name)"), ["install", "--cask", "--adopt", cask.token]) { [weak self] succeeded in
            if succeeded && addToBrewfile { self?.addToBrewfile(kind: .cask, name: cask.token) }
        }
    }

    /// Replaces an app installed by hand with the cask's version (`brew install --cask --force`).
    func reinstallWithHomebrew(_ item: UnmanagedApp, addToBrewfile: Bool) {
        guard let cask = item.cask else { return }
        run(String(localized: "Reinstalling \(item.app.name)"), ["install", "--cask", "--force", cask.token]) { [weak self] succeeded in
            if succeeded && addToBrewfile { self?.addToBrewfile(kind: .cask, name: cask.token) }
        }
    }

    /// Uninstalls the package and, once that succeeds, removes it from the Brewfile.
    func uninstallAndRemoveFromBrewfile(kind: EntryKind, name: String) {
        uninstall(kind: kind, name: name) { [weak self] succeeded in
            if succeeded { self?.removeFromBrewfile(kind: kind, name: name) }
        }
    }

    // MARK: - Stash

    /// The name `uninstall(kind:name:)` expects (`mas` uninstalls by App Store ID).
    private func uninstallName(of entry: BrewfileEntry) -> String {
        entry.kind == .mas ? (entry.masID ?? entry.name) : entry.name
    }

    private func isInstalled(_ entry: BrewfileEntry) -> Bool {
        status(of: entry).isInstalled
    }

    /// Uninstalls the package (if it is installed) and keeps it in the Brewfile as a stashed line.
    func stash(_ entry: BrewfileEntry) {
        guard isInstalled(entry) else {
            brewfile.stash(entry)
            return
        }
        uninstall(kind: entry.kind, name: uninstallName(of: entry)) { [weak self] succeeded in
            if succeeded { self?.brewfile.stash(entry) }
        }
    }

    /// Makes a stashed entry active again and installs it.
    func unstashAndInstall(_ entry: BrewfileEntry) {
        install(entry) { [weak self] succeeded in
            if succeeded { self?.brewfile.unstash(ids: [entry.id]) }
        }
    }

    func removeStashed(ids: Set<UUID>) {
        brewfile.removeStashed(ids: ids)
    }

    /// The Brewfile entry for an unused app (existing one if listed, otherwise a new one).
    func brewfileEntry(for item: UnusedApp) -> BrewfileEntry? {
        switch item.source {
        case .cask(let token):
            return brewfile.entries.first { $0.kind == .cask && ($0.name.lowercased() == token.lowercased() || $0.shortName.lowercased() == token.lowercased()) }
                ?? BrewfileEntry(kind: .cask, name: token)
        case .appStore(let id, let name):
            return brewfile.entries.first { $0.masID == id } ?? BrewfileEntry(kind: .mas, name: name, options: "id: \(id)")
        case .other:
            return nil
        }
    }

    /// Uninstalls an unused app and removes it from the Brewfile (active and stashed lines).
    func uninstallUnused(_ item: UnusedApp) {
        guard let entry = brewfileEntry(for: item) else { return }
        uninstall(kind: entry.kind, name: uninstallName(of: entry)) { [weak self] succeeded in
            guard succeeded, let self else { return }
            let key = entry.identityKey
            let ids = Set(brewfile.entries.filter { $0.identityKey == key || (entry.masID != nil && $0.masID == entry.masID) }.map(\.id))
            if !ids.isEmpty { brewfile.remove(ids: ids) }
            let stashed = Set(brewfile.stashedEntries.filter { $0.identityKey == key || (entry.masID != nil && $0.masID == entry.masID) }.map(\.id))
            if !stashed.isEmpty { brewfile.removeStashed(ids: stashed) }
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
        lastBrewUpdate = Date()
        run("brew update", ["update"])
    }

    // MARK: - Automatic brew update

    @ObservationIgnored private var lastBrewUpdate: Date?
    @ObservationIgnored private var inactiveSince: Date?

    // bool(forKey:)/integer(forKey:) also understand values given as text (e.g. `-autoUpdateMinutes 5` on the command line).
    private var autoUpdateEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: AutoUpdatePolicy.enabledKey) == nil || defaults.bool(forKey: AutoUpdatePolicy.enabledKey)
    }

    private var autoUpdateInterval: TimeInterval {
        let defaults = UserDefaults.standard
        let minutes = defaults.object(forKey: AutoUpdatePolicy.intervalKey) == nil
            ? AutoUpdatePolicy.defaultMinutes : defaults.integer(forKey: AutoUpdatePolicy.intervalKey)
        return TimeInterval(minutes) * 60
    }

    /// At launch: always fetch the latest package information, so the Updates list is current.
    func autoUpdateOnLaunch() {
        guard autoUpdateEnabled else { return }
        autoBrewUpdate(reason: "launch")
    }

    func appDidResignActive() {
        inactiveSince = Date()
    }

    /// When the user comes back after the app was in the background for the configured time.
    func autoUpdateOnActivation() {
        defer { inactiveSince = nil }
        guard autoUpdateEnabled, AutoUpdatePolicy.shouldUpdateOnActivation(
            now: Date(), inactiveSince: inactiveSince, lastUpdate: lastBrewUpdate, interval: autoUpdateInterval
        ) else { return }
        autoBrewUpdate(reason: "activation")
    }

    private func autoBrewUpdate(reason: String) {
        // Another brew command holds Homebrew's lock; the next activation will try again.
        guard client != nil, !isBusy else { return }
        log.notice("Automatic brew update (\(reason, privacy: .public))")
        lastBrewUpdate = Date()
        run(String(localized: "brew update (automatic)"), ["update"], revealOnFailure: false)
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
        // `brew bundle dump` rewrites the whole file – put the stashed lines back when it is the open Brewfile.
        let isOpenFile = url.standardizedFileURL.resolvingSymlinksInPath() == fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let before = brewfile
        if isOpenFile, isDirty { save() }
        run(String(localized: "Exporting State to \(url.lastPathComponent)"), args, refresh: false) { [weak self] succeeded in
            guard isOpenFile, let self else { return }
            loadFile(fileURL)
            if succeeded, !before.stashedEntries.isEmpty {
                brewfile.restoreStash(from: before)
                save()
            }
        }
    }

    /// `mas` uses the same mechanism – it runs as an external command with the `brew` environment.
    private func runMas(_ title: String, _ args: [String], onFinish: (@MainActor (Bool) -> Void)? = nil) {
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
            if job.state != .succeeded { self?.consoleExpanded = true }
            onFinish?(job.state == .succeeded)
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

/// An app installed by hand, with the cask Homebrew could manage it with (if there is one).
struct UnmanagedApp: Identifiable, Hashable {
    var app: InstalledApp
    var cask: CaskInfo?
    var id: String { app.id }
    var canAdopt: Bool { cask.map { UnmanagedApps.canAdopt(app, as: $0) } ?? false }
}

/// An app that hasn't been opened for a while.
struct UnusedApp: Identifiable, Hashable {
    var app: InstalledApp
    var usage: AppUsage
    var source: AppSource
    var isKept: Bool
    var id: String { app.id }
}

struct UnmanagedItem: Identifiable, Hashable {
    var kind: EntryKind
    var name: String
    var desc: String?
    var version: String?
    var masID: String? = nil
    var id: String { "\(kind.rawValue):\(masID ?? name)" }
}
