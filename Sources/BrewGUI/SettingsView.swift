// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import ServiceManagement
import SwiftUI

/// Brew GUI → Settings… (⌘,)
struct SettingsView: View {
    @AppStorage(AutoUpdatePolicy.enabledKey) private var autoUpdate = true
    @AppStorage(AutoUpdatePolicy.intervalKey) private var minutes = AutoUpdatePolicy.defaultMinutes
    @AppStorage(AppModel.showMenuBarIconKey) private var showMenuBarIcon = true
    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { loginItemStatus == .enabled }, set: setOpenAtLogin))
                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("Allow Brew GUI in System Settings → General → Login Items.")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginItemError {
                    Text(loginItemError).foregroundStyle(.red)
                }
                Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
            } footer: {
                Text("Quick update, package search and your Homebrew apps from the menu bar. With the icon, Brew GUI keeps running there when you close its window.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Check for package updates automatically", isOn: $autoUpdate)
                Picker("When returning to the app after", selection: $minutes) {
                    ForEach(AutoUpdatePolicy.minuteChoices, id: \.self) { value in
                        Text("\(value) min").tag(value)
                    }
                }
                .disabled(!autoUpdate)
            } footer: {
                Text("Runs brew update when Brew GUI starts, and again when you come back to it after it has been in the background for the selected time. New versions then show up under Updates.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        // The user may change it in System Settings while this window is open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    /// Registers this copy of the app as a login item (System Settings → General → Login Items).
    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = String(localized: "Couldn't change the login item: \(error.localizedDescription)")
        }
        loginItemStatus = SMAppService.mainApp.status
    }
}
