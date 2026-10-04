import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    /// Folders that contain projects. Found automatically on first launch, editable in Settings.
    public var projectLocations: [String] = []
    public var hasDiscoveredProjects = false
    public var notifyOnLowSpace = true
    public var lowSpaceThresholdGB = 20

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field is optional so older settings files keep loading as new fields are added.
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        projectLocations = try container.decodeIfPresent([String].self, forKey: .projectLocations) ?? defaults.projectLocations
        hasDiscoveredProjects = try container.decodeIfPresent(Bool.self, forKey: .hasDiscoveredProjects) ?? defaults.hasDiscoveredProjects
        notifyOnLowSpace = try container.decodeIfPresent(Bool.self, forKey: .notifyOnLowSpace) ?? defaults.notifyOnLowSpace
        lowSpaceThresholdGB = try container.decodeIfPresent(Int.self, forKey: .lowSpaceThresholdGB) ?? defaults.lowSpaceThresholdGB
    }

    public var lowSpaceThresholdBytes: Int64 { Int64(lowSpaceThresholdGB) * 1_000_000_000 }
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
