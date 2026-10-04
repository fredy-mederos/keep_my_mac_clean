import Foundation

/// How much judgment an item needs before cleaning it.
public enum Safety: String, Sendable, Codable, Hashable {
    /// Regenerated automatically by the owning tool. The only cost is a slower next build or a re-download.
    case safe
    /// Probably not needed, but you may want to keep some of it (old OS symbols, old IDE versions, downloaded deps).
    case review
}

/// What cleaning an item actually does.
public enum CleanupAction: Sendable, Hashable {
    /// Permanently remove these files or folders.
    case removePaths([URL])
    /// Run a tool's own cleanup command (preferred when one exists, e.g. `xcrun simctl delete unavailable`).
    case command(executable: String, arguments: [String])
}

/// Something that should not be running while an item is cleaned (Xcode, Android Studio, the Gradle daemon...).
public struct Blocker: Sendable, Hashable {
    public var name: String
    public var bundleIDs: [String]
    /// Matched with `pgrep -f` for things that are not regular apps.
    public var processPattern: String?

    public init(name: String, bundleIDs: [String] = [], processPattern: String? = nil) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.processPattern = processPattern
    }

    public static let xcode = Blocker(name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"])
    public static let simulator = Blocker(name: "Simulator", bundleIDs: ["com.apple.iphonesimulator"])
    public static let androidStudio = Blocker(name: "Android Studio", bundleIDs: ["com.google.android.studio", "com.google.android.studio-EAP"])
    public static let gradleDaemon = Blocker(name: "Gradle daemon", processPattern: "GradleDaemon")
    public static let androidEmulator = Blocker(name: "Android Emulator", processPattern: "qemu-system")
    public static let vsCode = Blocker(name: "VS Code", bundleIDs: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"])
}

public struct CleanupItem: Identifiable, Sendable, Hashable {
    /// Stable across scans (usually derived from the path) so selections survive a rescan.
    public let id: String
    public var title: String
    /// Short secondary line, e.g. the project path or "Newest for this device".
    public var detail: String?
    /// Bytes on disk.
    public var size: Int64
    public var safety: Safety
    public var action: CleanupAction
    /// What happens after cleaning ("Xcode rebuilds this on the next build").
    public var note: String?
    /// Where "Reveal in Finder" goes.
    public var revealURL: URL?
    public var blockers: [Blocker]
    public var lastUsed: Date?

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        size: Int64,
        safety: Safety,
        action: CleanupAction,
        note: String? = nil,
        revealURL: URL? = nil,
        blockers: [Blocker] = [],
        lastUsed: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.size = size
        self.safety = safety
        self.action = action
        self.note = note
        self.revealURL = revealURL
        self.blockers = blockers
        self.lastUsed = lastUsed
    }
}

public struct CleanupCategory: Identifiable, Sendable {
    public let id: String
    public var title: String
    /// SF Symbol name.
    public var symbol: String
    public var items: [CleanupItem]

    public init(id: String, title: String, symbol: String, items: [CleanupItem]) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.items = items
    }

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    public func size(of safety: Safety) -> Int64 {
        items.filter { $0.safety == safety }.reduce(0) { $0 + $1.size }
    }

    /// Safe items not used since `date`, e.g. build folders of projects untouched for months.
    public func inactiveItems(notUsedSince date: Date) -> [CleanupItem] {
        items.filter { item in
            guard item.safety == .safe, let lastUsed = item.lastUsed else { return false }
            return lastUsed < date
        }
    }
}
