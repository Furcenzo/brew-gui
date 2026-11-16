import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pri spustení cez `swift run` nemá proces bundle – urobíme z neho riadnu aplikáciu s ikonou v Docku.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        scheduleDebugSnapshot()
    }

    /// Ladenie: `BREWGUI_SNAPSHOT=/cesta.png [BREWGUI_PAGE=sync|outdated|unmanaged|search|missing]`
    /// uloží po načítaní obrázok okna (bez potreby povolenia na nahrávanie obrazovky) a ukončí appku.
    private func scheduleDebugSnapshot() {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BREWGUI_SNAPSHOT"] else { return }
        switch env["BREWGUI_PAGE"] {
        case "sync": model.sidebarSelection = .sync
        case "outdated": model.sidebarSelection = .outdated
        case "unmanaged": model.sidebarSelection = .unmanaged
        case "search": model.sidebarSelection = .search
        case "missing": model.sidebarSelection = .missing
        case "casks": model.sidebarSelection = .brewfile(.cask)
        case "check":
            // len na čítanie: brew bundle check
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.isBusy {
            let alert = NSAlert()
            alert.messageText = "Brew ešte pracuje"
            alert.informativeText = "Ukončením aplikácie sa prebiehajúca operácia preruší."
            alert.addButton(withTitle: "Počkať")
            alert.addButton(withTitle: "Ukončiť")
            if alert.runModal() == .alertFirstButtonReturn { return .terminateCancel }
        }
        guard model.isDirty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Uložiť zmeny v Brewfile?"
        alert.informativeText = model.fileURL.path
        alert.addButton(withTitle: "Uložiť")
        alert.addButton(withTitle: "Zrušiť")
        alert.addButton(withTitle: "Neukladať")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.save()
            return model.isDirty ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateCancel
        default:
            return .terminateNow
        }
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
            Button("Otvoriť Brewfile…") { model.openPanel() }
                .keyboardShortcut("o")
            Button("Znovu načítať zo súboru") { model.reloadFile() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .saveItem) {
            Button("Uložiť Brewfile") { model.save() }
                .keyboardShortcut("s")
        }
        CommandMenu("Brew") {
            Button("Obnoviť stav") { Task { await model.refreshAll() } }
                .keyboardShortcut("r")
            Button("brew update") { model.brewUpdate() }
                .disabled(model.isBusy)
            Divider()
            Button("Skontrolovať Brewfile") { model.bundleCheck() }
            Button(model.consoleExpanded ? "Skryť konzolu" : "Zobraziť konzolu") { model.consoleExpanded.toggle() }
                .keyboardShortcut("j")
        }
    }
}

BrewGUIApp.main()
