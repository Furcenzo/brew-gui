// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

/// Package details from `brew info --json=v2` with actions.
struct PackageInfoView: View {
    @Environment(AppModel.self) private var model
    let kind: EntryKind
    let name: String
    var showsBrewfileButton = true

    @State private var info: PackageInfo?
    @State private var error: String?
    @State private var confirmUninstall = false
    @State private var confirmInstall = false

    private var inBrewfile: Bool { model.brewfile.contains(kind: kind, name: name) }

    var body: some View {
        Group {
            if let info {
                content(info)
            } else if let error {
                ContentUnavailableView("No information", systemImage: "questionmark.square.dashed", description: Text(error))
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
        .confirmationDialog("Uninstall \(name)?", isPresented: $confirmUninstall) {
            if inBrewfile {
                Button("Uninstall and Remove from Brewfile", role: .destructive) {
                    model.uninstallAndRemoveFromBrewfile(kind: kind, name: name)
                }
                Button("Uninstall, Keep in Brewfile", role: .destructive) { model.uninstall(kind: kind, name: name) }
            } else {
                Button("Uninstall", role: .destructive) { model.uninstall(kind: kind, name: name) }
            }
        } message: {
            if inBrewfile {
                Text("\(name) is listed in the Brewfile. If you keep it there, `brew bundle install` will install it again.")
            }
        }
        .confirmationDialog("Add \(name) to the Brewfile too?", isPresented: $confirmInstall) {
            Button("Install and Add to Brewfile") { model.installAndAddToBrewfile(kind: kind, name: name) }
            Button("Install Only") { model.install(kind: kind, name: name) }
        } message: {
            Text("It will be added once the installation succeeds.")
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

                if let warning = info.lifecycleWarning {
                    Label(warning, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                actions(info)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    row("Type", info.kind.title)
                    row("Latest Version", info.latestVersion ?? "—")
                    row("Installed Version", info.installedVersion ?? String(localized: "no"))
                    if let tap = info.tap { row("Tap", tap) }
                    if case .formula(let f) = info {
                        if let license = f.license { row("License", license) }
                        if f.kegOnly == true { row("Keg-only", String(localized: "yes")) }
                        if f.pinned == true { row("Pinned", String(localized: "yes")) }
                    }
                    if case .cask(let c) = info, c.autoUpdates == true {
                        row("Updates", String(localized: "the app updates itself"))
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
                        Text("Dependencies").font(.headline)
                        Text(deps.joined(separator: ", "))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if let caveats = info.caveats?.trimmingCharacters(in: .whitespacesAndNewlines), !caveats.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Caveats").font(.headline)
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
        let installed = info.installedVersion != nil
        let outdated: Bool = switch info {
        case .formula(let f): f.outdated == true
        case .cask(let c): c.outdated == true
        }
        return HStack {
            if installed {
                if outdated {
                    Button("Upgrade") {
                        model.run("Upgrade \(name)", ["upgrade", info.kind == .cask ? "--cask" : "--formula", name])
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("Uninstall…") { confirmUninstall = true }
            } else {
                Button("Install") {
                    if inBrewfile { model.install(kind: kind, name: name) } else { confirmInstall = true }
                }
                    .buttonStyle(.borderedProminent)
            }
            if showsBrewfileButton {
                if inBrewfile {
                    Label("In Brewfile", systemImage: "checkmark").foregroundStyle(.secondary)
                } else {
                    Button("Add to Brewfile") { model.addToBrewfile(kind: info.kind, name: name) }
                }
            }
        }
        .controlSize(.regular)
        .disabled(model.isBusy)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}
