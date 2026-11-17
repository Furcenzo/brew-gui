// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation

/// When to run `brew update` automatically: always at launch, and when the user comes back to the app
/// after it has been in the background for a while – not immediately, so the user notices the result
/// while working with Brew GUI.
public enum AutoUpdatePolicy {
    public static let enabledKey = "autoUpdateEnabled"
    public static let intervalKey = "autoUpdateMinutes"
    public static let defaultMinutes = 15
    public static let minuteChoices = [5, 15, 30, 60]

    /// On activation: the app was inactive for at least `interval` and the last update is at least `interval` old.
    public static func shouldUpdateOnActivation(now: Date, inactiveSince: Date?, lastUpdate: Date?, interval: TimeInterval) -> Bool {
        guard let inactiveSince, now.timeIntervalSince(inactiveSince) >= interval else { return false }
        guard let lastUpdate else { return true }
        return now.timeIntervalSince(lastUpdate) >= interval
    }
}
