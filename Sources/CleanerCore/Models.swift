import Foundation

/// How much judgment an item needs before cleaning it.
public enum Safety: String, Sendable, Codable, Hashable {
    /// Regenerated automatically by the owning tool. The only cost is a slower next build or a re-download.
    case safe
    /// Probably not needed, but you may want to keep some of it (old OS symbols, old IDE versions, downloaded deps).
    case review
    /// Your own files (large videos, installers, downloads). Only ever moved to the Trash.
    case personal
}

/// What cleaning an item actually does.
public enum CleanupAction: Sendable, Hashable {
    /// Permanently remove these files or folders.
    case removePaths([URL])
    /// Run a tool's own cleanup command (preferred when one exists, e.g. `xcrun simctl delete unavailable`).
    case command(executable: String, arguments: [String])
    /// Move to the Trash so you can still change your mind. Used for your own files.
    case moveToTrash([URL])

    public var movesToTrash: Bool {
        if case .moveToTrash = self { return true }
        return false
    }
}

/// What cleaning an item costs you, from cheapest to most serious.
public enum CostLevel: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Recreated locally; the next build is slower.
    case rebuild
    /// Fetched again from the network when needed.
    case redownload
    /// No data is lost, but you lose a possibility (rolling back, re-exporting a build, an old IDE's settings).
    case loseOption
    /// The contents can't be recovered.
    case dataLoss

    public static func < (lhs: CostLevel, rhs: CostLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .rebuild: "Rebuild"
        case .redownload: "Re-download"
        case .loseOption: "Lose an option"
        case .dataLoss: "Data loss"
        }
    }
}

/// What `CleanupItem.lastUsed` means for this item, for display ("used 2 days ago", "added 3 months ago").
public enum DateKind: String, Sendable, Hashable {
    case used, opened, added, modified

    public var label: String {
        switch self {
        case .used: "used"
        case .opened: "opened"
        case .added: "added"
        case .modified: "changed"
        }
    }
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
    /// Why it's listed, and for Review items why it needs a look. One sentence.
    public var reason: String?
    /// What you pay if you clean it ("~8.8 GB re-download from Apple").
    public var cost: String?
    public var costLevel: CostLevel?
    /// What happens after cleaning ("Xcode copies them again when you connect the device").
    public var afterCleaning: String?
    /// Where "Reveal in Finder" goes.
    public var revealURL: URL?
    public var blockers: [Blocker]
    public var lastUsed: Date?
    public var dateKind: DateKind

    public init(
        id: String,
        title: String,
        detail: String? = nil,
        size: Int64,
        safety: Safety,
        action: CleanupAction,
        reason: String? = nil,
        cost: String? = nil,
        costLevel: CostLevel? = nil,
        afterCleaning: String? = nil,
        revealURL: URL? = nil,
        blockers: [Blocker] = [],
        lastUsed: Date? = nil,
        dateKind: DateKind = .used
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.size = size
        self.safety = safety
        self.action = action
        self.reason = reason
        self.cost = cost
        self.costLevel = costLevel
        self.afterCleaning = afterCleaning
        self.revealURL = revealURL
        self.blockers = blockers
        self.lastUsed = lastUsed
        self.dateKind = dateKind
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
