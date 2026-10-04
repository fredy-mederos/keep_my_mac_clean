import Foundation
import Testing
@testable import CleanerCore

@Suite struct LargeFilesTests {
    @Test func findsBigFilesButSkipsSystemHiddenAndBuildFolders() throws {
        let home = try TestHome()
        try home.file("Movies/trip.mov", bytes: 3_000_000)
        try home.file("Documents/small.txt", bytes: 1_000)
        try home.file("Documents/app/node_modules/huge.bin", bytes: 3_000_000)   // build output: other category
        try home.file("Documents/.hidden/huge.bin", bytes: 3_000_000)
        try home.file("Library/Caches/huge.bin", bytes: 3_000_000)
        try home.file("Desktop/Old.app/Contents/big.bin", bytes: 3_000_000)       // bundle
        try home.file("Downloads/top-level.bin", bytes: 3_000_000)                // handled by the Downloads probe
        try home.file("Downloads/folder/nested.bin", bytes: 3_000_000)

        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false, largeFileMinimumSize: 2_000_000)
        let titles = Set(LargeFilesScanner().largeFiles(context).map(\.title))
        #expect(titles == ["trip.mov", "nested.bin"])
    }

    @Test func classifiesAndSuggests() throws {
        let home = try TestHome()
        let zip = try home.file("Downloads/Assets.zip")
        try home.folder("Downloads/Assets")
        #expect(LargeFilesScanner.FileKind.of(zip) == .archive)
        #expect(LargeFilesScanner.isExtracted(zip))
        #expect(LargeFilesScanner.suggestion(for: zip, kind: .archive).contains("already extracted"))
        #expect(LargeFilesScanner.FileKind.of(URL(fileURLWithPath: "/x/Setup.DMG")) == .installer)
        #expect(LargeFilesScanner.FileKind.of(URL(fileURLWithPath: "/x/app-release.aab")) == .appBuild)
        #expect(LargeFilesScanner.FileKind.of(URL(fileURLWithPath: "/x/notes.md")) == .other)
    }

    @Test func downloadRules() {
        let now = Date()
        let old = now.addingTimeInterval(-60 * 86_400)
        let recent = now.addingTimeInterval(-2 * 86_400)
        func list(_ kind: LargeFilesScanner.FileKind, _ size: Int64, _ added: Date?) -> Bool {
            LargeFilesScanner.shouldList(kind: kind, size: size, added: added, largeFileMinimumSize: 500_000_000, now: now)
        }
        #expect(list(.installer, 20_000_000, recent))          // installers whatever their age
        #expect(!list(.installer, 2_000_000, recent))          // too small to bother
        #expect(list(.other, 200_000_000, old))                // forgotten medium download
        #expect(!list(.other, 200_000_000, recent))            // recent medium download
        #expect(list(.video, 900_000_000, recent))             // big is always listed
    }

    @Test func downloadsProbeListsTopLevelFilesOnly() throws {
        let home = try TestHome()
        try home.file("Downloads/Installer.dmg", bytes: 11_000_000)
        try home.file("Downloads/tiny.pdf", bytes: 10_000)
        try home.file("Downloads/folder/Inner.dmg", bytes: 11_000_000)
        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false)
        let items = LargeFilesScanner().downloads(context)
        #expect(items.map(\.title) == ["Installer.dmg"])
        #expect(items.first?.safety == .personal)
        #expect(items.first?.dateKind == .added)
        #expect(items.first?.action.movesToTrash == true)
    }
}

@Suite struct TrashTests {
    @Test func movesFilesWithTheInjectedTrash() throws {
        let home = try TestHome()
        let file = try home.file("Downloads/Installer.dmg")
        let fakeTrash = try home.folder("FakeTrash")
        let cleaner = Cleaner(home: home.url) { url in
            try FileManager.default.moveItem(at: url, to: fakeTrash.appendingPathComponent(url.lastPathComponent))
        }
        let item = CleanupItem(id: "f", title: "f", size: 1, safety: .personal, action: .moveToTrash([file]))
        #expect(cleaner.clean(item).succeeded)
        #expect(!home.exists("Downloads/Installer.dmg"))
        #expect(home.exists("FakeTrash/Installer.dmg"))
    }

    @Test func trashStillRespectsThePathGuard() throws {
        let home = try TestHome()
        let cleaner = Cleaner(home: home.url) { _ in Issue.record("should not be called") }
        let item = CleanupItem(id: "f", title: "f", size: 1, safety: .personal, action: .moveToTrash([home.path("Downloads")]))
        #expect(!cleaner.clean(item).succeeded)
    }
}

@Suite struct HistoryTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let gb: Int64 = 1_000_000_000

    func sample(hours: Double, availableGB: Double) -> SpaceSample {
        SpaceSample(date: start.addingTimeInterval(hours * 3600), available: Int64(availableGB * 1e9), total: 494 * gb)
    }

    @Test func recordsAtMostEveryHalfHour() {
        var history = SpaceHistory()
        let first = history.record(sample(hours: 0, availableGB: 30))
        let tooSoon = history.record(sample(hours: 0.2, availableGB: 29))
        let later = history.record(sample(hours: 0.6, availableGB: 29))
        #expect(first && !tooSoon && later)
        #expect(history.samples.count == 2)
    }

    @Test func trendIgnoresCleanupJumps() throws {
        var history = SpaceHistory()
        // Losing 2 GB a day for 4 days, with a 20 GB cleanup in the middle.
        var available = 40.0
        for hour in stride(from: 0.0, through: 96.0, by: 6.0) {
            if hour == 48 { available += 20 }
            history.record(sample(hours: hour, availableGB: available))
            available -= 0.5
        }
        let trend = try #require(history.trend(now: start.addingTimeInterval(96 * 3600)))
        #expect(abs(trend.bytesPerDay - 2e9) < 0.1e9)
        let days = try #require(trend.daysUntilFull)
        #expect(days > 25 && days < 27)   // ~52 GB left at 2 GB/day
    }

    @Test func noTrendWithoutEnoughHistory() {
        var history = SpaceHistory()
        history.record(sample(hours: 0, availableGB: 30))
        history.record(sample(hours: 1, availableGB: 29))
        history.record(sample(hours: 2, availableGB: 28))
        #expect(history.trend(now: start.addingTimeInterval(2 * 3600)) == nil)
    }

    @Test func stableDiskHasNoDaysUntilFull() throws {
        var history = SpaceHistory()
        for hour in stride(from: 0.0, through: 48.0, by: 6.0) {
            history.record(sample(hours: hour, availableGB: hour.truncatingRemainder(dividingBy: 12) == 0 ? 30 : 30.05))
        }
        let trend = try #require(history.trend(now: start.addingTimeInterval(48 * 3600)))
        #expect(trend.daysUntilFull == nil)
    }

    @Test func growthComparesWithAboutAWeekAgo() throws {
        var history = SpaceHistory()
        let day: TimeInterval = 86_400
        history.record(scan: ScanRecord(date: start, categorySizes: ["xcode": 10 * gb]))
        history.record(scan: ScanRecord(date: start.addingTimeInterval(6 * day), categorySizes: ["xcode": 14 * gb]))
        let now = start.addingTimeInterval(7 * day)
        let growth = try #require(history.growth(of: "xcode", currentSize: 16 * gb, now: now))
        #expect(growth.bytes == 6 * gb)
        #expect(growth.since == start)
        #expect(history.growth(of: "missing", currentSize: 1, now: now) == nil)
    }

    @Test func keepsOneScanPerDay() {
        var history = SpaceHistory()
        history.record(scan: ScanRecord(date: start, categorySizes: ["a": 1]))
        history.record(scan: ScanRecord(date: start.addingTimeInterval(3600), categorySizes: ["a": 2]))
        #expect(history.scans.count == 1)
        #expect(history.scans.first?.categorySizes["a"] == 2)
    }

    @Test func storeRoundTrips() throws {
        let home = try TestHome()
        let store = HistoryStore(fileURL: home.path("history.json"))
        var history = SpaceHistory()
        history.record(sample(hours: 0, availableGB: 30))
        history.record(scan: ScanRecord(date: start, categorySizes: ["a": 5]))
        try store.save(history)
        #expect(store.load() == history)
    }
}
