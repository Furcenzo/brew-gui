// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Furcenzo

import Foundation
import Testing
@testable import BrewCore

struct AutoUpdatePolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let interval: TimeInterval = 15 * 60

    private func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    @Test func updatesAfterLongEnoughInBackground() {
        #expect(AutoUpdatePolicy.shouldUpdateOnActivation(now: now, inactiveSince: minutesAgo(15), lastUpdate: minutesAgo(40), interval: interval))
        #expect(AutoUpdatePolicy.shouldUpdateOnActivation(now: now, inactiveSince: minutesAgo(20), lastUpdate: nil, interval: interval))
    }

    @Test func waitsWhenBackgroundTooShort() {
        #expect(!AutoUpdatePolicy.shouldUpdateOnActivation(now: now, inactiveSince: minutesAgo(14), lastUpdate: minutesAgo(60), interval: interval))
        #expect(!AutoUpdatePolicy.shouldUpdateOnActivation(now: now, inactiveSince: nil, lastUpdate: nil, interval: interval))
    }

    @Test func waitsWhenUpdatedRecently() {
        // e.g. the user ran brew update by hand 5 minutes ago
        #expect(!AutoUpdatePolicy.shouldUpdateOnActivation(now: now, inactiveSince: minutesAgo(30), lastUpdate: minutesAgo(5), interval: interval))
    }
}
