import Foundation
import Testing
@testable import CleanerCore

@Suite struct DigestTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let gb: Int64 = 1_000_000_000
    let day: TimeInterval = 86_400

    func item(_ id: String, _ title: String, _ size: Int64) -> CleanupItem {
        CleanupItem(id: id, title: title, size: size, safety: .safe, action: .removePaths([]))
    }

    /// A week losing 1.3 GB a day, with a 20 GB cleanup on day 3 and Xcode data growing.
    func week() -> (SpaceHistory, [CleanupCategory], Date) {
        var history = SpaceHistory()
        var available = 41.0
        for hour in stride(from: 0.0, through: 168.0, by: 6.0) {
            if hour == 72 { available += 20 }
            history.record(SpaceSample(date: start.addingTimeInterval(hour * 3600), available: Int64(available * 1e9), total: 494 * gb))
            available -= 1.3 / 4
        }
        history.record(scan: ScanRecord(
            date: start,
            categorySizes: ["xcode": 40_300_000_000, "files": 1 * gb, "packages": 14 * gb],
            itemSizes: ["dd": 10 * gb, "runtime": 9 * gb, "rest": 21_300_000_000, "npm": 14 * gb]
        ))
        let categories = [
            CleanupCategory(id: "xcode", title: "Xcode and simulators", symbol: "", items: [
                item("dd", "Auto1 build data", 15_800_000_000), item("runtime", "iOS 18.6 runtime", 9 * gb), item("rest", "Other", 21_300_000_000),
            ]),
            CleanupCategory(id: "files", title: "Large files and downloads", symbol: "", items: [item("apk", "app.apk", 2_200_000_000)]),
            CleanupCategory(id: "packages", title: "Package manager caches", symbol: "", items: [item("npm", "npm cache", 14_050_000_000)]),
        ]
        return (history, categories, start.addingTimeInterval(168 * 3600))
    }

    @Test func computesTheWeek() throws {
        let (history, categories, now) = week()
        let facts = try #require(Digest.facts(history: history, categories: categories, now: now))
        #expect(facts.isFullWeek)
        #expect(facts.periodLabel == "this week")
        #expect(abs(Double(facts.cleaned) - 19.675e9) < 0.01e9)          // 20 GB jump minus that interval's loss
        #expect(facts.changes.map(\.id) == ["xcode", "files"])           // packages changed < 100 MB
        #expect(facts.changes.first?.topItem?.title == "Auto1 build data")
        #expect(facts.biggestGrower?.id == "dd")
        #expect(facts.biggestGrower?.bytes == 5_800_000_000)
    }

    @Test func plainSummaryReadsWell() throws {
        let (history, categories, now) = week()
        let facts = try #require(Digest.facts(history: history, categories: categories, now: now))
        let summary = Digest.plainSummary(facts)
        #expect(summary.headline == "Free space up 11 GB this week")
        #expect(summary.body.hasPrefix("Xcode and simulators grew 5.8 GB, mostly Auto1 build data. Large files and downloads grew 1.2 GB, mostly app.apk."))
        #expect(summary.body.contains("You cleaned up 20 GB."))
    }

    @Test func needsTwoDaysOfHistory() {
        var history = SpaceHistory()
        for hour in stride(from: 0.0, through: 30.0, by: 6.0) {
            history.record(SpaceSample(date: start.addingTimeInterval(hour * 3600), available: 30 * gb, total: 494 * gb))
        }
        #expect(Digest.facts(history: history, categories: [], now: start.addingTimeInterval(30 * 3600)) == nil)
    }

    @Test func shortPeriodsSayHowLong() throws {
        var history = SpaceHistory()
        for hour in stride(from: 0.0, through: 72.0, by: 6.0) {
            history.record(SpaceSample(date: start.addingTimeInterval(hour * 3600), available: Int64((40 - hour / 24) * 1e9), total: 494 * gb))
        }
        let facts = try #require(Digest.facts(history: history, categories: [], now: start.addingTimeInterval(72 * 3600)))
        #expect(!facts.hasBaseline)
        #expect(Digest.plainSummary(facts).headline == "Free space down 3.0 GB in the last 3 days")
    }

    @Test func noItemBlamedWhenTheOldScanHasNoItemSizes() throws {
        var (history, categories, now) = week()
        history.scans = [ScanRecord(date: start, categorySizes: ["xcode": 40 * gb])]
        let facts = try #require(Digest.facts(history: history, categories: categories, now: now))
        #expect(facts.changes.first?.id == "xcode")
        #expect(facts.biggestGrower == nil)
        categories = []
        #expect(Digest.facts(history: history, categories: categories, now: now)?.changes.isEmpty == true)
    }

    @Test func oldScanRecordsStillLoad() throws {
        let json = #"{"date": "2026-10-01T10:00:00Z", "categorySizes": {"xcode": 5}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(ScanRecord.self, from: Data(json.utf8))
        #expect(record.categorySizes == ["xcode": 5])
        #expect(record.itemSizes.isEmpty)
    }
}
