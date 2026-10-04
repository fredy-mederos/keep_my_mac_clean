import Foundation

public struct ItemChange: Sendable, Equatable {
    public var id: String
    public var title: String
    public var bytes: Int64
}

public struct CategoryChange: Sendable, Equatable {
    public var id: String
    public var title: String
    public var bytes: Int64
    /// The item in this category that grew the most.
    public var topItem: ItemChange?
}

/// Everything the weekly summary says, computed from the history. A language model may reword it,
/// but every number comes from here.
public struct DigestFacts: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var freeAtStart: Int64
    public var freeNow: Int64
    /// Free space that came back through cleanups during the period.
    public var cleaned: Int64
    public var trend: SpaceTrend?
    /// Whether an older scan exists to compare categories with.
    public var hasBaseline: Bool
    /// Categories that changed by at least 100 MB, biggest change first.
    public var changes: [CategoryChange]
    public var safeTotal: Int64
    public var reviewTotal: Int64

    public var netChange: Int64 { freeNow - freeAtStart }
    public var days: Double { end.timeIntervalSince(start) / 86_400 }
    public var isFullWeek: Bool { days >= 6.5 }
    public var periodLabel: String { isFullWeek ? "this week" : "in the last \(Int(days.rounded())) days" }

    /// The one thing worth acting on: the item that grew the most.
    public var biggestGrower: ItemChange? {
        changes.compactMap(\.topItem).filter { $0.bytes > 0 }.max { $0.bytes < $1.bytes }
    }
}

public enum Digest {
    /// Less history than this isn't worth summarizing.
    public static let minimumPeriod: TimeInterval = 2 * 86_400
    static let window: TimeInterval = 7 * 86_400
    static let minimumChange: Int64 = 100_000_000
    static let notable: Int64 = 500_000_000

    public static func facts(history: SpaceHistory, categories: [CleanupCategory], now: Date = Date()) -> DigestFacts? {
        let samples = history.samples
            .filter { $0.date >= now.addingTimeInterval(-window) && $0.date <= now }
            .sorted { $0.date < $1.date }
        guard let first = samples.first, let last = samples.last,
              last.date.timeIntervalSince(first.date) >= minimumPeriod
        else { return nil }

        var cleaned: Int64 = 0
        for (previous, next) in zip(samples, samples.dropFirst()) {
            let delta = next.available - previous.available
            if delta > SpaceHistory.cleanupJump { cleaned += delta }
        }

        // Compare with the oldest scan in the period that is at least a day old.
        let baseline = history.scans
            .filter { $0.date >= first.date.addingTimeInterval(-86_400) && now.timeIntervalSince($0.date) >= 86_400 }
            .min { $0.date < $1.date }

        var changes: [CategoryChange] = []
        if let baseline {
            for category in categories {
                guard let before = baseline.categorySizes[category.id] else { continue }
                let delta = category.totalSize - before
                guard abs(delta) >= minimumChange else { continue }
                // Without item sizes (records from older versions) every item would look new, so name none.
                let topItem = baseline.itemSizes.isEmpty ? nil : category.items
                    .map { ItemChange(id: $0.id, title: $0.title, bytes: $0.size - (baseline.itemSizes[$0.id] ?? 0)) }
                    .filter { $0.bytes >= minimumChange }
                    .max { $0.bytes < $1.bytes }
                changes.append(CategoryChange(id: category.id, title: category.title, bytes: delta, topItem: delta > 0 ? topItem : nil))
            }
            changes.sort { abs($0.bytes) > abs($1.bytes) }
        }

        return DigestFacts(
            start: first.date,
            end: last.date,
            freeAtStart: first.available,
            freeNow: last.available,
            cleaned: cleaned,
            trend: history.trend(now: now),
            hasBaseline: baseline != nil,
            changes: changes,
            safeTotal: categories.reduce(0) { $0 + $1.size(of: .safe) },
            reviewTotal: categories.reduce(0) { $0 + $1.size(of: .review) }
        )
    }

    /// The summary without any model: always available, and the fallback.
    public static func plainSummary(_ facts: DigestFacts) -> (headline: String, body: String) {
        let net = facts.netChange
        let headline: String
        if net <= -notable {
            headline = "Free space down \(ByteFormat.short(-net)) \(facts.periodLabel)"
        } else if net >= notable {
            headline = "Free space up \(ByteFormat.short(net)) \(facts.periodLabel)"
        } else {
            headline = "Free space steady \(facts.periodLabel)"
        }

        var sentences: [String] = []
        let growers = facts.changes.filter { $0.bytes > 0 }.prefix(2)
        if !growers.isEmpty {
            let parts = growers.map { change in
                "\(change.title) grew \(ByteFormat.short(change.bytes))"
                    + (change.topItem.map { ", mostly \($0.title)" } ?? "")
            }
            sentences.append(parts.joined(separator: ". ") + ".")
        } else if facts.hasBaseline {
            sentences.append("Nothing the app tracks grew much.")
        }
        if facts.cleaned >= notable {
            sentences.append("You cleaned up \(ByteFormat.short(facts.cleaned)).")
        }
        if let days = facts.trend?.daysUntilFull, days < 60 {
            sentences.append("At this pace the disk is full in about \(max(Int(days), 1)) days.")
        }
        return (headline, sentences.joined(separator: " "))
    }
}
