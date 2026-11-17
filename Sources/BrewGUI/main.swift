// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import AppKit
import BrewCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier == nil {
            // `swift run` has no bundle to take the icon from – use the one from the source tree.
            let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/AppIcon.icns")
            NSApp.applicationIconImage = NSImage(contentsOf: icon)
        }
        if Self.wasLaunchedAtLogin && AppModel.showsMenuBarIcon {
            // Started by "Open at login": live only in the menu bar until the user opens the window.
            model.hideWindowAtLaunch = true
            NSApp.setActivationPolicy(.accessory)
            for window in NSApp.windows where window.isVisible && window.canBecomeMain { window.close() }
        } else {
            // Also turns a process started via `swift run` (no bundle) into a regular app with a Dock icon.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        scheduleDebugSnapshot()
        model.autoUpdateOnLaunch()
    }

    /// `brew:ripgrep:15.1.0:15.2.0,cask:visual-studio-code:1.145.0:1.146.0` → packages for the Updates list.
    private static func sampleOutdated(_ spec: String) -> [OutdatedPackage] {
        spec.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":").map(String.init)
            guard parts.count == 4 else { return nil }
            let json = ["name": parts[1], "installed_versions": [parts[2]], "current_version": parts[3]] as [String: Any]
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  var package = try? decoder.decode(OutdatedPackage.self, from: data) else { return nil }
            package.isCask = parts[0] == "cask"
            return package
        }
    }

    /// macOS marks the launch of a login item in the "open application" Apple event.
    /// BREWGUI_LAUNCHED_AT_LOGIN=1 simulates it for testing.
    private static var wasLaunchedAtLogin: Bool {
        if ProcessInfo.processInfo.environment["BREWGUI_LAUNCHED_AT_LOGIN"] == "1" { return true }
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidResignActive(_ notification: Notification) {
        model.appDidResignActive()
    }

    /// Debugging: `BREWGUI_SNAPSHOT=/path.png [BREWGUI_PAGE=sync|outdated|unmanaged|apps|search|missing]`
    /// saves an image of the window once loaded (no screen recording permission needed) and quits the app.
    /// Used by scripts/screenshots.sh together with BREWGUI_APPEARANCE=light|dark, BREWGUI_WINDOW_SIZE=1200x750,
    /// BREWGUI_SELECT=<entry name> (Brewfile inspector) and BREWGUI_SEARCH=<package> (Search page).
    /// BREWGUI_PAGE=menubar captures the menu bar panel instead (BREWGUI_MENUBAR_QUERY types into its search field).
    private func scheduleDebugSnapshot() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BREWGUI_SNAPSHOT"] else { return }
        switch env["BREWGUI_APPEARANCE"] {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: break
        }
        model.debugSelectEntry = env["BREWGUI_SELECT"]
        model.debugAppsFromBrewfile = env["BREWGUI_APPS_FROM_BREWFILE"] == "1"
        if let sample = env["BREWGUI_SAMPLE_OUTDATED"] {
            model.debugOutdated = Self.sampleOutdated(sample)
        }
        model.debugDisplayPath = env["BREWGUI_DISPLAY_PATH"]
        if let query = env["BREWGUI_SEARCH"] {
            model.pendingSearchQuery = query
            model.sidebarSelection = .search
        }
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
        var captureWindow: NSWindow?
        if env["BREWGUI_PAGE"] == "menubar" {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 520),
                                styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.contentView = NSHostingView(rootView: MenuBarContent(query: env["BREWGUI_MENUBAR_QUERY"] ?? "")
                .environment(model)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12)))
            panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
            panel.center()
            panel.orderFrontRegardless()
            captureWindow = panel
        }
        Task { @MainActor in
            if let size = env["BREWGUI_WINDOW_SIZE"]?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
                try? await Task.sleep(for: .milliseconds(300))
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.setContentSize(NSSize(width: size[0], height: size[1]))
                    window.center()
                }
            }
            try? await Task.sleep(for: .seconds(Double(env["BREWGUI_DELAY"] ?? "5") ?? 5))
            // Look like the active window (coloured traffic lights) in the image.
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            guard let view = captureWindow?.contentView ?? NSApp.windows.first(where: { $0.isVisible })?.contentView?.superview,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            exit(0)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.checkExternalChanges()
        model.refreshOnActivation()
        model.autoUpdateOnActivation()
    }

    /// With the menu bar icon, closing the window keeps Brew GUI running there (without a Dock icon).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard AppModel.showsMenuBarIcon else { return true }
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        return true
    }

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
    @AppStorage(AppModel.showMenuBarIconKey) private var showMenuBarIcon = true

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

        Settings {
            SettingsView()
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarContent()
                .environment(delegate.model)
        } label: {
            MenuBarLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
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
