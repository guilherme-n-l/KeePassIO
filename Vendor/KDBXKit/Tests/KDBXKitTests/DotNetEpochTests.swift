//
// SPDX-License-Identifier: BSD-2-Clause
//

import Foundation
import Testing

@testable import KDBXKit

/// KDBX 4 stores times as seconds since 0001-01-01T00:00:00Z (proleptic
/// Gregorian, as in .NET). These values are what KeePass and KeePassXC
/// write, so a mismatch shifts every timestamp shared with them.
struct DotNetEpochTests {
    @Test func epochMatchesDotNet() {
        // .NET: DateTime.UnixEpoch.Ticks / 10_000_000 == 62_135_596_800
        #expect(Date.dotNetEpoch.timeIntervalSince1970 == -62_135_596_800)
    }

    @Test(arguments: [
        // 2025-06-01T00:00:00Z
        (Int64(63_884_332_800), 1_748_736_000.0),
        // 1970-01-01T00:00:00Z
        (Int64(62_135_596_800), 0.0),
        // 2000-02-29T12:34:56Z
        (Int64(63_087_424_496), 951_827_696.0),
    ])
    func knownTimestamps(dotNetSeconds: Int64, unixSeconds: Double) {
        let date = Date(secondsSinceDotNetEpoch: dotNetSeconds)
        #expect(date.timeIntervalSince1970 == unixSeconds)
        #expect(date.secondsSinceDotNetEpoch == dotNetSeconds)
    }
}
