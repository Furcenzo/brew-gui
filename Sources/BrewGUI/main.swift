// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When started via `swift run` the process has no bundle – turn it into a regular app with a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        scheduleDebugSnapshot()
    }

    /// Debugging: `BREWGUI_SNAPSHOT=/path.png [BREWGUI_PAGE=sync|outdated|unmanaged|search|missing]`
    /// saves an image of the window once loaded (no screen recording permission needed) and quits the app.
    private func scheduleDebugSnapshot() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BREWGUI_SNAPSHOT"] else { return }
        if let file = env["BREWGUI_FILE"] { model.loadFile(URL(fileURLWithPath: file)) }
        if let name = env["BREWGUI_DEBUG_ADD"] {
            // simulate an edit: add an entry, optionally ⌘Z after 2 s
            model.addToBrewfile(kind: .brew, name: name)
            if env["BREWGUI_DEBUG_UNDO"] != nil {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    model.undoManager?.undo()
                }
            }
        }
        switch env["BREWGUI_PAGE"] {
        case "sync": model.sidebarSelection = .sync
        case "outdated": model.sidebarSelection = .outdated
        case "unmanaged": model.sidebarSelection = .unmanaged
        case "apps":
            UserDefaults.standard.set("apps", forKey: "unmanagedMode")
            model.sidebarSelection = .unmanaged
        case "search": model.sidebarSelection = .search
        case "missing": model.sidebarSelection = .missing
        case "casks": model.sidebarSelection = .brewfile(.cask)
        case "check":
            // read-only: brew bundle check
            model.sidebarSelection = .sync
            model.bundleCheck()
            model.consoleExpanded = true
        default: break
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Double(env["BREWGUI_DELAY"] ?? "5") ?? 5))
            guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.checkExternalChanges()
        model.refreshOnActivation()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.isBusy {
            let alert = NSAlert()
            alert.messageText = String(localized: "Brew is still working")
            alert.informativeText = String(localized: "Quitting the app will interrupt the running operation.")
            alert.addButton(withTitle: String(localized: "Wait"))
            alert.addButton(withTitle: String(localized: "Quit"))
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        // Changes are saved automatically; anything not saved yet (the last fraction of a second) is saved without asking.
        guard model.isDirty else { return .terminateNow }
        if model.externalChangeDetected {
            let alert = NSAlert()
            alert.messageText = String(localized: "Another program changed the Brewfile")
            alert.informativeText = String(localized: "You have changes that haven't been saved yet. Overwrite the file on disk with them?")
            alert.addButton(withTitle: String(localized: "Overwrite"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.addButton(withTitle: String(localized: "Keep File on Disk"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: return .terminateCancel
            default: return .terminateNow
            }
        }
        model.save()
        return model.isDirty ? .terminateCancel : .terminateNow
    }
}

struct BrewGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Brew GUI", id: "main") {
            ContentView()
                .environment(delegate.model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 800)
        .commands {
            AppCommands(model: delegate.model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Brewfile…") { model.openPanel() }
                .keyboardShortcut("o")
            Button("Reload from File") { model.reloadFile() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Brewfile") { model.save() }
                .keyboardShortcut("s")
        }
        CommandMenu("Brew") {
            Button("Refresh Status") { Task { await model.refreshAll() } }
                .keyboardShortcut("r")
            Button("brew update") { model.brewUpdate() }
                .disabled(model.isBusy)
            Divider()
            Button("Check Brewfile") { model.bundleCheck() }
            Button(model.consoleExpanded ? "Hide Console" : "Show Console") { model.consoleExpanded.toggle() }
                .keyboardShortcut("j")
        }
    }
}

BrewGUIApp.main()
