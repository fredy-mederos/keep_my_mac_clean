import Foundation

public struct DiskSpace: Sendable, Equatable {
    public var total: Int64
    /// Free space as Finder reports it (includes purgeable space macOS can reclaim on demand).
    public var available: Int64

    public init(total: Int64, available: Int64) {
        self.total = total
        self.available = available
    }

    public var used: Int64 { max(total - available, 0) }
    public var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    public static func read(volume: URL = URL(fileURLWithPath: "/")) throws -> DiskSpace {
        let values = try volume.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ])
        let total = Int64(values.volumeTotalCapacity ?? 0)
        var available = values.volumeAvailableCapacityForImportantUsage ?? 0
        if available <= 0 { available = Int64(values.volumeAvailableCapacity ?? 0) }
        return DiskSpace(total: total, available: available)
    }
}
