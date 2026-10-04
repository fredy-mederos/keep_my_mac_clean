import Foundation
import Testing
@testable import CleanerCore

@Suite struct SimulatorTests {
    @Test func unavailableSimulatorsAreDeletedByID() throws {
        let home = try TestHome()
        try home.file("Library/Developer/CoreSimulator/Devices/BBB/data/x", bytes: 1_000_000)
        try home.file("Library/Developer/CoreSimulator/Devices/AAA/data/x", bytes: 1_000_000)
        let devices = [
            SimulatorDevice(udid: "BBB", name: "iPhone Air", isAvailable: false, runtimeIdentifier: "iOS-26-5"),
            SimulatorDevice(udid: "AAA", name: "iPhone 17e", isAvailable: false, runtimeIdentifier: "iOS-26-5"),
            SimulatorDevice(udid: "CCC", name: "iPhone 17", isAvailable: true, runtimeIdentifier: "iOS-27-0"),
        ]
        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false)
        let item = try #require(XcodeScanner.unavailableSimulatorsItem(devices, context: context))
        // `simctl delete unavailable` skips simulators whose runtime was removed, so name each one.
        #expect(item.action == .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "AAA", "BBB"]))
        #expect(item.detail == "2 simulators whose iOS version is no longer installed")
        #expect(item.size >= 2_000_000)
    }

    @Test func nothingToDoWhenAllAreAvailable() {
        let devices = [SimulatorDevice(udid: "CCC", name: "iPhone 17", isAvailable: true, runtimeIdentifier: "iOS-27-0")]
        let context = ScanContext(home: URL(fileURLWithPath: "/tmp"), projectLocations: [], runsSystemCommands: false)
        #expect(XcodeScanner.unavailableSimulatorsItem(devices, context: context) == nil)
    }
}
