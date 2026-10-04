import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    /// Folders that contain projects. Found automatically on first launch, editable in Settings.
    public var projectLocations: [String] = []
    public var hasDiscoveredProjects = false
    public var notifyOnLowSpace = true
    public var lowSpaceThresholdGB = 20
    /// Projects (and their DerivedData) unused for this long can be selected in one click.
    public var inactiveAfterMonths = 3
    /// Your own files at least this big show up under Large files and downloads.
    public var largeFileThresholdMB = 500
    /// Let Apple's on-device model write the suggestions for your own files (macOS 26+).
    public var smartSuggestions = false
    /// A notification once a week saying how free space changed and what grew.
    public var weeklySummary = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field is optional so older settings files keep loading as new fields are added.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        projectLocations = try container.decodeIfPresent([String].self, forKey: .projectLocations) ?? defaults.projectLocations
        hasDiscoveredProjects = try container.decodeIfPresent(Bool.self, forKey: .hasDiscoveredProjects) ?? defaults.hasDiscoveredProjects
        notifyOnLowSpace = try container.decodeIfPresent(Bool.self, forKey: .notifyOnLowSpace) ?? defaults.notifyOnLowSpace
        lowSpaceThresholdGB = try container.decodeIfPresent(Int.self, forKey: .lowSpaceThresholdGB) ?? defaults.lowSpaceThresholdGB
        inactiveAfterMonths = try container.decodeIfPresent(Int.self, forKey: .inactiveAfterMonths) ?? defaults.inactiveAfterMonths
        largeFileThresholdMB = try container.decodeIfPresent(Int.self, forKey: .largeFileThresholdMB) ?? defaults.largeFileThresholdMB
        smartSuggestions = try container.decodeIfPresent(Bool.self, forKey: .smartSuggestions) ?? defaults.smartSuggestions
        weeklySummary = try container.decodeIfPresent(Bool.self, forKey: .weeklySummary) ?? defaults.weeklySummary
    }

    public var lowSpaceThresholdBytes: Int64 { Int64(lowSpaceThresholdGB) * 1_000_000_000 }
    public var largeFileThresholdBytes: Int64 { Int64(largeFileThresholdMB) * 1_000_000 }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SettingsStore.defaultURL) {
        self.fileURL = fileURL
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KeepMyMacClean/settings.json")
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: .atomic)
    }
}
