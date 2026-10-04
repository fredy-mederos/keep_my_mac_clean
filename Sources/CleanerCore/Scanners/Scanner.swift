import Foundation

public struct ScanContext: Sendable {
    public var home: URL
    public var projectLocations: [URL]
    /// Folders where installed apps live (used to tell which IDE version is current).
    public var applicationFolders: [URL]
    /// Whether scanners may ask tools like `xcrun simctl` (off in tests that use a fake home).
    public var runsSystemCommands: Bool

    public init(home: URL, projectLocations: [URL], applicationFolders: [URL]? = nil, runsSystemCommands: Bool = true) {
        self.home = home
        self.projectLocations = projectLocations
        self.applicationFolders = applicationFolders ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        self.runsSystemCommands = runsSystemCommands
    }

    func path(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }
}

/// A deferred measurement. Scanners list what exists quickly and return probes;
/// the engine runs the probes in parallel because sizing can take a while
/// (a legacy CocoaPods specs repo alone holds ~1.7 million files).
public struct ItemProbe: Sendable {
    let run: @Sendable () -> [CleanupItem]

    public init(_ run: @escaping @Sendable () -> [CleanupItem]) {
        self.run = run
    }

    static func one(_ make: @escaping @Sendable () -> CleanupItem?) -> ItemProbe {
        ItemProbe { make().map { [$0] } ?? [] }
    }
}

public protocol CleanupScanner: Sendable {
    var categoryID: String { get }
    var title: String { get }
    var symbol: String { get }
    /// Lists what to measure. Keep this quick; heavy work belongs inside the probes.
    func probes(in context: ScanContext) -> [ItemProbe]
}

extension CleanupScanner {
    /// All items, measured one after another. Handy for tests.
    public func items(in context: ScanContext) -> [CleanupItem] {
        probes(in: context).flatMap { $0.run() }
    }
}

public struct ScanSnapshot: Sendable {
    /// Categories with at least one item, in scanner order, items sorted by size.
    public var categories: [CleanupCategory]
    /// Measurements still running.
    public var pending: Int
}

public enum ScanEngine {
    public static let scanners: [any CleanupScanner] = [
        ProjectsScanner(),
        XcodeScanner(),
        AndroidScanner(),
        PackageCachesScanner(),
        IDEScanner(),
        DockerScanner(),
    ]

    /// Items smaller than this are noise in the list.
    static let minimumItemSize: Int64 = 1_000_000

    /// Scans with one scanner, sequentially.
    public static func scan(_ scanner: any CleanupScanner, context: ScanContext) -> CleanupCategory {
        category(for: scanner, items: scanner.items(in: context))
    }

    /// Scans with all scanners and streams progress as each measurement finishes.
    public static func run(
        _ scanners: [any CleanupScanner] = ScanEngine.scanners,
        context: ScanContext,
        maxConcurrentProbes: Int = 6
    ) -> AsyncStream<ScanSnapshot> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                // 1. Every scanner lists its probes (fast, in parallel).
                let listed = await withTaskGroup(of: (Int, [ItemProbe]).self) { group in
                    for (index, scanner) in scanners.enumerated() {
                        group.addTask { (index, scanner.probes(in: context)) }
                    }
                    var result: [(Int, [ItemProbe])] = []
                    for await entry in group { result.append(entry) }
                    return result
                }
                let work = listed.flatMap { index, probes in probes.map { (index, $0) } }

                // 2. Measure with bounded parallelism, publishing after each result.
                var itemsByScanner = Array(repeating: [CleanupItem](), count: scanners.count)
                var pending = work.count
                func snapshot() -> ScanSnapshot {
                    let categories = scanners.indices.compactMap { index -> CleanupCategory? in
                        let category = category(for: scanners[index], items: itemsByScanner[index])
                        return category.items.isEmpty ? nil : category
                    }
                    return ScanSnapshot(categories: categories, pending: pending)
                }
                continuation.yield(snapshot())

                await withTaskGroup(of: (Int, [CleanupItem]).self) { group in
                    var next = 0
                    func startNext() {
                        guard next < work.count, !Task.isCancelled else { return }
                        let (index, probe) = work[next]
                        next += 1
                        group.addTask { (index, probe.run()) }
                    }
                    for _ in 0..<maxConcurrentProbes { startNext() }
                    for await (index, items) in group {
                        itemsByScanner[index] += items
                        pending -= 1
                        continuation.yield(snapshot())
                        startNext()
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func category(for scanner: any CleanupScanner, items: [CleanupItem]) -> CleanupCategory {
        CleanupCategory(
            id: scanner.categoryID,
            title: scanner.title,
            symbol: scanner.symbol,
            items: items.filter { $0.size >= minimumItemSize }.sorted { $0.size > $1.size }
        )
    }
}

extension CleanupItem {
    /// Convenience for the common "delete these folders" item. Returns nil when nothing exists.
    static func folders(
        id: String,
        title: String,
        detail: String? = nil,
        urls: [URL],
        safety: Safety,
        note: String?,
        revealURL: URL? = nil,
        blockers: [Blocker] = [],
        lastUsed: Date? = nil
    ) -> CleanupItem? {
        let existing = urls.filter(FileInfo.exists)
        guard !existing.isEmpty else { return nil }
        return CleanupItem(
            id: id,
            title: title,
            detail: detail,
            size: DirectorySize.allocatedSize(of: existing),
            safety: safety,
            action: .removePaths(existing),
            note: note,
            revealURL: revealURL ?? existing.first,
            blockers: blockers,
            lastUsed: lastUsed
        )
    }
}
