import Foundation

public struct SpaceSample: Codable, Sendable, Equatable {
    public var date: Date
    public var available: Int64
    public var total: Int64

    public init(date: Date, available: Int64, total: Int64) {
        self.date = date
        self.available = available
        self.total = total
    }
}

/// Category and item sizes at the end of a full scan, to show what keeps growing.
public struct ScanRecord: Codable, Sendable, Equatable {
    public var date: Date
    public var categorySizes: [String: Int64]
    /// Sizes of the bigger items (at least `ScanRecord.minimumItemSize`), by item ID.
    public var itemSizes: [String: Int64]

    /// Smaller items aren't stored, to keep the history file small.
    public static let minimumItemSize: Int64 = 50_000_000

    public init(date: Date, categorySizes: [String: Int64], itemSizes: [String: Int64] = [:]) {
        self.date = date
        self.categorySizes = categorySizes
        self.itemSizes = itemSizes
    }

    public init(date: Date, categories: [CleanupCategory]) {
        self.init(
            date: date,
            categorySizes: Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.totalSize) }),
            itemSizes: Dictionary(
                categories.flatMap(\.items).filter { $0.size >= Self.minimumItemSize }.map { ($0.id, $0.size) },
                uniquingKeysWith: max
            )
        )
    }

    public init(from decoder: Decoder) throws {
        // Records written before item sizes existed have none.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(Date.self, forKey: .date)
        categorySizes = try container.decode([String: Int64].self, forKey: .categorySizes)
        itemSizes = try container.decodeIfPresent([String: Int64].self, forKey: .itemSizes) ?? [:]
    }
}

public struct SpaceTrend: Sendable, Equatable {
    /// Positive when the disk is filling up.
    public var bytesPerDay: Double
    /// Time covered by the samples used.
    public var span: TimeInterval
    /// Only when filling up meaningfully.
    public var daysUntilFull: Double?
}

public struct CategoryGrowth: Sendable, Equatable {
    public var bytes: Int64
    public var since: Date
}

/// Free space over time. Kept for 90 days in Application Support.
public struct SpaceHistory: Codable, Sendable, Equatable {
    public var samples: [SpaceSample] = []
    public var scans: [ScanRecord] = []
    public var lastFillingAlert: Date?
    public var lastWeeklySummary: Date?

    public static let sampleInterval: TimeInterval = 30 * 60
    public static let retention: TimeInterval = 90 * 86_400
    /// A rise in free space bigger than this between two samples is a cleanup, not the normal trend.
    public static let cleanupJump: Int64 = 1_000_000_000
    /// Below this the trend counts as stable.
    public static let meaningfulRate: Double = 100_000_000

    public init() {}

    /// Adds the sample if the previous one is old enough. Returns whether it was added.
    @discardableResult
    public mutating func record(_ sample: SpaceSample) -> Bool {
        if let last = samples.last, sample.date.timeIntervalSince(last.date) < Self.sampleInterval {
            return false
        }
        samples.append(sample)
        prune(now: sample.date)
        return true
    }

    /// Keeps one record per calendar day: a later scan on the same day replaces the earlier one.
    public mutating func record(scan: ScanRecord, calendar: Calendar = .current) {
        scans.removeAll { calendar.isDate($0.date, inSameDayAs: scan.date) }
        scans.append(scan)
        scans.sort { $0.date < $1.date }
        prune(now: scan.date)
    }

    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        samples.removeAll { $0.date < cutoff }
        scans.removeAll { $0.date < cutoff }
    }

    /// How fast free space is shrinking over the last `window`, ignoring jumps up from cleanups
    /// (otherwise cleaning 20 GB would make it look like the disk is emptying itself).
    public func trend(now: Date = Date(), window: TimeInterval = 7 * 86_400) -> SpaceTrend? {
        let recent = samples.filter { $0.date >= now.addingTimeInterval(-window) }.sorted { $0.date < $1.date }
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return nil }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= 12 * 3600 else { return nil }

        // Intervals containing a cleanup are left out entirely, both their change and their time.
        var net: Int64 = 0
        var measured: TimeInterval = 0
        for (previous, next) in zip(recent, recent.dropFirst()) {
            let delta = next.available - previous.available
            if delta > Self.cleanupJump { continue }
            net += delta
            measured += next.date.timeIntervalSince(previous.date)
        }
        guard measured > 0 else { return nil }
        let bytesPerDay = Double(-net) / (measured / 86_400)
        let daysUntilFull = bytesPerDay >= Self.meaningfulRate ? Double(last.available) / bytesPerDay : nil
        return SpaceTrend(bytesPerDay: bytesPerDay, span: span, daysUntilFull: daysUntilFull)
    }

    /// Growth of a category compared with the scan closest to a week ago (at least a day old).
    public func growth(of categoryID: String, currentSize: Int64, now: Date = Date()) -> CategoryGrowth? {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let candidates = scans.filter { now.timeIntervalSince($0.date) >= 86_400 && $0.categorySizes[categoryID] != nil }
        guard let baseline = candidates.min(by: {
            abs($0.date.timeIntervalSince(weekAgo)) < abs($1.date.timeIntervalSince(weekAgo))
        }), let oldSize = baseline.categorySizes[categoryID] else { return nil }
        return CategoryGrowth(bytes: currentSize - oldSize, since: baseline.date)
    }

    /// Samples from the last `window`, for the sparkline.
    public func recentSamples(now: Date = Date(), window: TimeInterval = 7 * 86_400) -> [SpaceSample] {
        samples.filter { $0.date >= now.addingTimeInterval(-window) }
    }
}

public struct HistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = HistoryStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        SettingsStore.defaultURL.deletingLastPathComponent().appendingPathComponent("history.json")
    }

    public func load() -> SpaceHistory {
        guard let data = try? Data(contentsOf: fileURL) else { return SpaceHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SpaceHistory.self, from: data)) ?? SpaceHistory()
    }

    public func save(_ history: SpaceHistory) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: fileURL, options: .atomic)
    }
}
