import AppKit
import BrewCore
import SwiftUI

struct SyncView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("bundleUpgrade") private var upgradeOnInstall = false
    @State private var preview: CleanupPreview?
    @State private var loadingPreview = false
    @State private var showCleanupSheet = false

    enum PendingAction: Identifiable {
        case check, install, cleanup
        var id: Self { self }
    }

    var body: some View {
        let entries = model.brewfile.entries
        let missing = model.missingEntries
        Form {
            Section {
                LabeledContent("Brewfile", value: model.fileURL.path(percentEncoded: false))
                LabeledContent("Položiek", value: "\(entries.count)")
                LabeledContent("Chýba na tomto Macu", value: "\(missing.count)")
                LabeledContent("Nainštalované mimo Brewfile", value: "\(model.unmanaged.count)")
            } header: {
                Text("Stav")
            } footer: {
                if model.isDirty {
                    Label("Brewfile má neuložené zmeny – pred synchronizáciou sa uloží.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }

            Section("Brewfile → Mac") {
                actionRow(
                    title: "Skontrolovať",
                    detail: "brew bundle check – zistí, či je všetko z Brewfile nainštalované.",
                    button: "Skontrolovať"
                ) { perform(.check) }

                actionRow(
                    title: "Nainštalovať chýbajúce",
                    detail: "brew bundle install – doinštaluje taps, formulae, casks aj App Store aplikácie.",
                    button: "Inštalovať",
                    prominent: true
                ) { perform(.install) }
                Toggle("Pri inštalácii aj upgradovať zastarané balíky", isOn: $upgradeOnInstall)

                if !missing.isEmpty {
                    DisclosureGroup("Chýbajúce položky (\(missing.count))") {
                        ForEach(missing) { entry in
                            HStack {
                                KindLabel(kind: entry.kind).frame(width: 100, alignment: .leading)
                                Text(entry.name).font(.body.monospaced())
                                Spacer()
                                if entry.kind.isManaged {
                                    Button("Nainštalovať") { model.install(entry) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }
            }

            Section("Mac → Brewfile") {
                actionRow(
                    title: "Upratať podľa Brewfile",
                    detail: "brew bundle cleanup – odinštaluje všetko, čo v Brewfile nie je. Najprv ukáže náhľad.",
                    button: loadingPreview ? "Načítavam…" : "Náhľad…",
                    role: .destructive
                ) { perform(.cleanup) }

                actionRow(
                    title: "Exportovať aktuálny stav",
                    detail: "brew bundle dump – zapíše všetko nainštalované do nového súboru.",
                    button: "Exportovať…"
                ) { dump() }

                actionRow(
                    title: "Pridať nainštalované do Brewfile",
                    detail: "Zoznam balíkov, ktoré máte nainštalované, ale v Brewfile chýbajú.",
                    button: "Zobraziť"
                ) { model.sidebarSelection = .unmanaged }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isBusy)
        .sheet(isPresented: $showCleanupSheet) {
            CleanupSheet(preview: preview ?? CleanupPreview()) {
                model.bundleCleanup()
            }
        }
    }

    private func actionRow(
        title: String,
        detail: String,
        button: String,
        prominent: Bool = false,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if prominent {
                Button(button, role: role, action: action).buttonStyle(.borderedProminent)
            } else {
                Button(button, role: role, action: action)
            }
        }
    }

    private func perform(_ action: PendingAction) {
        if model.isDirty { model.save() }
        guard !model.isDirty else { return }
        switch action {
        case .check:
            model.bundleCheck()
            model.consoleExpanded = true
        case .install:
            model.bundleInstall(upgrade: upgradeOnInstall)
            model.consoleExpanded = true
        case .cleanup:
            loadingPreview = true
            Task {
                preview = await model.cleanupPreview()
                loadingPreview = false
                if preview != nil { showCleanupSheet = true }
            }
        }
    }

    private func dump() {
        let panel = NSSavePanel()
        panel.title = "Exportovať aktuálny stav"
        panel.nameFieldStringValue = "Brewfile.dump"
        panel.directoryURL = model.fileURL.deletingLastPathComponent()
        panel.showsHiddenFiles = true
        let describe = NSButton(checkboxWithTitle: "Pridať popisy balíkov ako komentáre", target: nil, action: nil)
        describe.state = .on
        panel.accessoryView = describe
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL == model.fileURL.standardizedFileURL {
            model.errorMessage = "Export by prepísal otvorený Brewfile. Zvoľte iný názov súboru."
            return
        }
        model.bundleDump(to: url, describe: describe.state == .on)
        model.consoleExpanded = true
    }
}

struct CleanupSheet: View {
    @Environment(\.dismiss) private var dismiss
    let preview: CleanupPreview
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upratanie podľa Brewfile").font(.title2.bold())
            if preview.isEmpty {
                ContentUnavailableView("Nie je čo upratovať", systemImage: "sparkles", description: Text("Všetko nainštalované je v Brewfile."))
                    .frame(height: 200)
            } else {
                Text("Nasledujúce sa odinštaluje / odstráni. Toto sa nedá vrátiť späť (balíky sa dajú neskôr znovu nainštalovať).")
                    .foregroundStyle(.secondary)
                List {
                    section("Casks", preview.casks)
                    section("Formulae", preview.formulae)
                    section("Taps", preview.taps)
                    section("brew cleanup", preview.other)
                }
                .frame(minHeight: 260)
            }
            HStack {
                Spacer()
                Button("Zrušiť", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !preview.isEmpty {
                    Button("Odinštalovať", role: .destructive) {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding()
        .frame(width: 520)
    }

    @ViewBuilder private func section(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            Section("\(title) (\(items.count))") {
                ForEach(items, id: \.self) { Text($0).font(.callout.monospaced()) }
            }
        }
    }
}
