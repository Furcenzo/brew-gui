import BrewCore
import SwiftUI

/// Detail balíka z `brew info --json=v2` s akciami.
struct PackageInfoView: View {
    @Environment(AppModel.self) private var model
    let kind: EntryKind
    let name: String
    var showsBrewfileButton = true

    @State private var info: PackageInfo?
    @State private var error: String?
    @State private var confirmUninstall = false

    var body: some View {
        Group {
            if let info {
                content(info)
            } else if let error {
                ContentUnavailableView("Bez informácií", systemImage: "questionmark.square.dashed", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(kind.rawValue):\(name):\(model.jobs.filter { !$0.isRunning }.count)") {
            do {
                let loaded = try await model.info(kind: kind, name: name)
                info = loaded
                error = nil
            } catch {
                if info == nil { self.error = error.localizedDescription }
            }
        }
        .onChange(of: name) {
            info = nil
            error = nil
        }
        .confirmationDialog("Odinštalovať \(name)?", isPresented: $confirmUninstall) {
            Button("Odinštalovať", role: .destructive) { model.uninstall(kind: kind, name: name) }
        }
    }

    private func content(_ info: PackageInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.displayName).font(.title2.bold())
                    Text(info.token).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    if let desc = info.desc {
                        Text(desc).padding(.top, 2)
                    }
                }

                actions(info)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Typ", info.kind.title)
                    row("Najnovšia", info.latestVersion ?? "—")
                    row("Nainštalovaná", info.installedVersion ?? "nie")
                    if let tap = info.tap { row("Tap", tap) }
                    if case .formula(let f) = info {
                        if let license = f.license { row("Licencia", license) }
                        if f.kegOnly == true { row("Keg-only", "áno") }
                        if f.pinned == true { row("Pinned", "áno") }
                    }
                    if case .cask(let c) = info, c.autoUpdates == true {
                        row("Aktualizácie", "aplikácia sa aktualizuje sama")
                    }
                }
                .font(.callout)

                if let homepage = info.homepage {
                    Link(destination: homepage) {
                        Label(homepage.host() ?? homepage.absoluteString, systemImage: "safari")
                    }
                }

                if case .formula(let f) = info, let deps = f.dependencies, !deps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Závislosti").font(.headline)
                        Text(deps.joined(separator: ", "))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let caveats = info.caveats?.trimmingCharacters(in: .whitespacesAndNewlines), !caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upozornenia").font(.headline)
                        Text(caveats)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actions(_ info: PackageInfo) -> some View {
        let inBrewfile = model.brewfile.contains(kind: info.kind, name: name)
        let installed = info.installedVersion != nil
        let outdated: Bool = switch info {
        case .formula(let f): f.outdated == true
        case .cask(let c): c.outdated == true
        }
        return HStack {
            if installed {
                if outdated {
                    Button("Upgradovať") {
                        model.run("Upgrade \(name)", ["upgrade", info.kind == .cask ? "--cask" : "--formula", name])
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Odinštalovať…") { confirmUninstall = true }
            } else {
                Button("Nainštalovať") { model.install(kind: info.kind, name: name) }
                    .buttonStyle(.borderedProminent)
            }
            if showsBrewfileButton {
                if inBrewfile {
                    Label("V Brewfile", systemImage: "checkmark").foregroundStyle(.secondary)
                } else {
                    Button("Pridať do Brewfile") { model.addToBrewfile(kind: info.kind, name: name) }
                }
            }
        }
        .controlSize(.regular)
        .disabled(model.isBusy)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
