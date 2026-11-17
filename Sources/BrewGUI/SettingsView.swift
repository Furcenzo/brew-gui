// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import BrewCore
import SwiftUI

/// Brew GUI → Settings… (⌘,)
struct SettingsView: View {
    @AppStorage(AutoUpdatePolicy.enabledKey) private var autoUpdate = true
    @AppStorage(AutoUpdatePolicy.intervalKey) private var minutes = AutoUpdatePolicy.defaultMinutes

    var body: some View {
        Form {
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
    }
}
