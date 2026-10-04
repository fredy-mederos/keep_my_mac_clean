import Foundation

/// Xcode build data, device symbols, archives and simulators.
public struct XcodeScanner: CleanupScanner {
    public let categoryID = "xcode"
    public let title = "Xcode and simulators"
    public let symbol = "hammer"

    public init() {}

    public func probes(in context: ScanContext) -> [ItemProbe] {
        var probes: [ItemProbe] = []
        probes += derivedData(context)
        probes += deviceSupport(context)
        probes += archives(context)
        probes.append(.one { CleanupItem.folders(
            id: "xcode.previews",
            title: "SwiftUI preview data",
            urls: [context.path("Library/Developer/Xcode/UserData/Previews")],
            safety: .safe,
            reason: "Simulators and build data Xcode made for SwiftUI previews.",
            cost: "Previews take longer to show the first time",
            costLevel: .rebuild,
            afterCleaning: "Xcode recreates preview data when you open a preview.",
            blockers: [.xcode]
        ) })
        probes.append(.one { CleanupItem.folders(
            id: "xcode.simulator-caches",
            title: "Simulator caches",
            urls: [context.path("Library/Developer/CoreSimulator/Caches")],
            safety: .safe,
            reason: "Caches simulators build at launch, such as the shared dyld cache.",
            cost: "Simulators start slower once",
            costLevel: .rebuild,
            afterCleaning: "Simulators rebuild these caches on their next launch.",
            blockers: [.simulator]
        ) })
        if context.runsSystemCommands {
            probes.append(ItemProbe { simulators(context) })
        }
        return probes
    }

    // MARK: DerivedData

    static let sharedDerivedDataFolders: Set<String> = [
        "ModuleCache.noindex", "SymbolCache.noindex", "SDKExplicitPrecompiledModules",
        "SDKStatCaches.noindex", "CompilationCache.noindex",
    ]

    func derivedData(_ context: ScanContext) -> [ItemProbe] {
        let root = context.path("Library/Developer/Xcode/DerivedData")
        var probes: [ItemProbe] = []
        var shared: [URL] = []
        for dir in FileInfo.subdirectories(of: root) {
            if Self.sharedDerivedDataFolders.contains(dir.lastPathComponent) {
                shared.append(dir)
                continue
            }
            let info = FileInfo.plist(at: dir.appendingPathComponent("info.plist"))
            let workspace = (info?["WorkspacePath"] as? String).map { URL(fileURLWithPath: $0) }
            let title = workspace?.deletingPathExtension().lastPathComponent ?? Self.projectName(fromDerivedDataFolder: dir.lastPathComponent)
            let detail: String
            let projectIsGone = workspace.map { !FileInfo.exists($0) } ?? false
            if let workspace {
                detail = projectIsGone
                    ? "Project no longer exists"
                    : PathFormat.abbreviated(workspace.deletingLastPathComponent(), home: context.home)
            } else {
                detail = "Build data"
            }
            let lastUsed = info?["LastAccessedDate"] as? Date ?? FileInfo.modificationDate(dir)
            probes.append(.one { CleanupItem.folders(
                id: "xcode.derived:\(dir.path)",
                title: "\(title) build data",
                detail: detail,
                urls: [dir],
                safety: .safe,
                reason: projectIsGone
                    ? "Build data for \(title), whose project folder no longer exists."
                    : "Build products and the index for \(title). Xcode recreates everything here.",
                cost: projectIsGone ? "Nothing: no project uses it anymore" : "Next build of \(title) is a full rebuild",
                costLevel: projectIsGone ? nil : .rebuild,
                afterCleaning: "Xcode rebuilds and re-indexes the project the next time you build it.",
                blockers: [.xcode],
                lastUsed: lastUsed
            ) })
        }
        probes.append(.one { [shared] in CleanupItem.folders(
            id: "xcode.derived.shared",
            title: "Shared module caches",
            detail: "DerivedData",
            urls: shared,
            safety: .safe,
            reason: "Precompiled system and package modules shared by all your Xcode projects.",
            cost: "The first build of each project is slower",
            costLevel: .rebuild,
            afterCleaning: "Xcode rebuilds the modules it needs as you build.",
            revealURL: root,
            blockers: [.xcode]
        ) })
        return probes
    }

    /// "Auto1-bzdndobdkrngxicisfqqxbehazjk" → "Auto1".
    static func projectName(fromDerivedDataFolder name: String) -> String {
        guard let dash = name.lastIndex(of: "-") else { return name }
        let suffix = name[name.index(after: dash)...]
        if suffix.count == 28, suffix.allSatisfy({ $0.isLowercase && $0.isLetter }) {
            return String(name[..<dash])
        }
        return name
    }

    // MARK: Device support

    public struct DeviceSupportEntry: Sendable, Equatable {
        public var folderName: String
        public var platform: String
        public var model: String?
        public var version: String
        public var build: String

        /// Apple beta builds end in a lowercase letter after a long build number (24A5380h).
        public var isBeta: Bool {
            build.wholeMatch(of: /\d+[A-Z]\d{4,}[a-z]/) != nil
        }

        public var deviceKey: String { model ?? platform }

        /// Parses "iPhone15,2 27.0 (24A5380h)" or the older "17.0 (21A329) arm64e".
        public static func parse(folderName: String, platform: String) -> DeviceSupportEntry? {
            guard let match = folderName.wholeMatch(of: /(?:(\S+) )?(\d+(?:\.\d+)*) \(([0-9A-Za-z]+)\)(?: .*)?/) else {
                return nil
            }
            return DeviceSupportEntry(
                folderName: folderName,
                platform: platform,
                model: match.1.map(String.init),
                version: String(match.2),
                build: String(match.3)
            )
        }
    }

    /// Folder names of the newest entry for each device.
    public static func newestPerDevice(_ entries: [DeviceSupportEntry]) -> Set<String> {
        let grouped = Dictionary(grouping: entries, by: \.deviceKey)
        return Set(grouped.values.compactMap { group in
            group.max { a, b in
                if a.version != b.version { return Version.isOrderedBefore(a.version, b.version) }
                return a.build < b.build
            }?.folderName
        })
    }

    func deviceSupport(_ context: ScanContext) -> [ItemProbe] {
        let platforms = ["iOS", "watchOS", "tvOS", "visionOS", "macOS"]
        var probes: [ItemProbe] = []
        for platform in platforms {
            let root = context.path("Library/Developer/Xcode/\(platform) DeviceSupport")
            let folders = FileInfo.subdirectories(of: root)
            let entries = folders.compactMap { DeviceSupportEntry.parse(folderName: $0.lastPathComponent, platform: platform) }
            let newestPerDevice = Self.newestPerDevice(entries)
            let newestVersion = entries.map(\.version).max(by: Version.isOrderedBefore)
            for folder in folders {
                let entry = entries.first { $0.folderName == folder.lastPathComponent }
                let title = entry.map { "\(platform) \($0.version)\($0.isBeta ? " beta" : "") (\($0.build))" } ?? folder.lastPathComponent
                var detailParts: [String] = []
                if let model = entry?.model { detailParts.append(model) }
                if let entry {
                    if !newestPerDevice.contains(entry.folderName) {
                        detailParts.append("a newer version exists for this device")
                    } else if let newestVersion, Version.isOrderedBefore(entry.version, newestVersion) {
                        detailParts.append("older than \(platform) \(newestVersion)")
                    } else {
                        detailParts.append("newest")
                    }
                }
                let detail = detailParts.isEmpty ? "\(platform) device symbols" : detailParts.joined(separator: " · ")
                let device = entry?.model ?? "a device"
                let version = entry.map { "\(platform) \($0.version)" } ?? platform
                let reason: String
                if let entry, !newestPerDevice.contains(entry.folderName) {
                    reason = "Symbols for an older \(platform) on \(device); a newer version for that device is also here."
                } else if let newestVersion, let entry, Version.isOrderedBefore(entry.version, newestVersion) {
                    reason = "Symbols for \(version) from \(device). Your newest device runs \(platform) \(newestVersion)."
                } else {
                    reason = "Symbols Xcode needs to debug apps on \(device) running \(version)."
                }
                probes.append(.one { CleanupItem.folders(
                    id: "xcode.devicesupport:\(folder.path)",
                    title: title,
                    detail: detail,
                    urls: [folder],
                    safety: .review,
                    reason: reason,
                    cost: "{size} copied again from the device the next time you debug on \(version)",
                    costLevel: .redownload,
                    afterCleaning: "Xcode copies the symbols again when you connect a device running \(version). It takes a few minutes and needs that device.",
                    blockers: [.xcode],
                    lastUsed: FileInfo.modificationDate(folder)
                ) })
            }
        }
        return probes
    }

    // MARK: Archives

    func archives(_ context: ScanContext) -> [ItemProbe] {
        let root = context.path("Library/Developer/Xcode/Archives")
        var probes: [ItemProbe] = []
        for dateFolder in FileInfo.subdirectories(of: root) {
            for archive in FileInfo.subdirectories(of: dateFolder) where archive.pathExtension == "xcarchive" {
                probes.append(.one {
                    let info = FileInfo.plist(at: archive.appendingPathComponent("Info.plist"))
                    let name = info?["Name"] as? String ?? archive.deletingPathExtension().lastPathComponent
                    let appProperties = info?["ApplicationProperties"] as? [String: Any]
                    let version = appProperties?["CFBundleShortVersionString"] as? String
                    let build = [name, version].compactMap { $0 }.joined(separator: " ")
                    return CleanupItem.folders(
                        id: "xcode.archive:\(archive.path)",
                        title: build,
                        detail: "Archive from \(dateFolder.lastPathComponent)",
                        urls: [archive],
                        safety: .review,
                        reason: "Archive of \(build): the signed app and its debug symbols (dSYMs).",
                        cost: "Its dSYMs are gone: crashes from this build can't be symbolicated unless they're uploaded elsewhere",
                        costLevel: .dataLoss,
                        afterCleaning: "You can't re-export or re-upload this exact build. Rebuilding the same code gives different symbols.",
                        lastUsed: info?["CreationDate"] as? Date
                    )
                })
            }
        }
        return probes
    }

    // MARK: Simulators

    func simulators(_ context: ScanContext) -> [CleanupItem] {
        var items: [CleanupItem] = []
        let devices = SimulatorDevices.load()

        let unavailable = devices.filter { !$0.isAvailable }
        if !unavailable.isEmpty {
            let folders = unavailable.map { context.path("Library/Developer/CoreSimulator/Devices/\($0.udid)") }
            items.append(CleanupItem(
                id: "xcode.simulators.unavailable",
                title: "Unavailable simulators",
                detail: "\(unavailable.count) simulators whose iOS version is no longer installed",
                size: DirectorySize.allocatedSize(of: folders),
                safety: .safe,
                action: .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "delete", "unavailable"]),
                reason: "Their iOS runtime is no longer installed, so they can't run.",
                cost: "Nothing: they can't be used anymore",
                costLevel: nil,
                afterCleaning: "Removed with `xcrun simctl delete unavailable`.",
                revealURL: context.path("Library/Developer/CoreSimulator/Devices"),
                blockers: [.simulator]
            ))
        }

        for runtime in SimulatorRuntime.load() where runtime.deletable {
            let users = devices.filter { $0.isAvailable && $0.runtimeIdentifier == runtime.runtimeIdentifier }.count
            let name = "\(runtime.platformName) \(runtime.version)"
            let size = "~\(ByteFormat.short(runtime.sizeBytes))"
            items.append(CleanupItem(
                id: "xcode.runtime:\(runtime.identifier)",
                title: "\(runtime.platformName) \(runtime.version) simulator runtime",
                detail: users == 0 ? "No simulators use it" : "\(users) simulator\(users == 1 ? "" : "s") use it",
                size: runtime.sizeBytes,
                safety: .review,
                action: .command(executable: "/usr/bin/xcrun", arguments: ["simctl", "runtime", "delete", runtime.identifier]),
                reason: users == 0
                    ? "\(name) runtime that none of your simulators use."
                    : "\(name) runtime used by \(ProjectFacts.count(users, "simulator")).",
                cost: users == 0
                    ? "\(size) re-download from Apple if you need \(name) again"
                    : "\(size) re-download from Apple, and \(ProjectFacts.count(users, "simulator")) stop working until then",
                costLevel: .redownload,
                afterCleaning: "Download it again in Xcode → Settings → Components to test on \(name).",
                blockers: [.simulator, .xcode]
            ))
        }
        return items
    }
}

struct SimulatorDevice: Sendable {
    var udid: String
    var name: String
    var isAvailable: Bool
    var runtimeIdentifier: String
}

enum SimulatorDevices {
    static func load() -> [SimulatorDevice] {
        guard let output = try? CommandRunner.run("/usr/bin/xcrun", ["simctl", "list", "devices", "-j"], timeout: 30),
              output.status == 0
        else { return [] }
        return parse(json: Data(output.stdout.utf8))
    }

    static func parse(json: Data) -> [SimulatorDevice] {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]]
        else { return [] }
        return byRuntime.flatMap { runtime, devices in
            devices.compactMap { device in
                guard let udid = device["udid"] as? String else { return nil }
                return SimulatorDevice(
                    udid: udid,
                    name: device["name"] as? String ?? udid,
                    isAvailable: device["isAvailable"] as? Bool ?? true,
                    runtimeIdentifier: runtime
                )
            }
        }
    }
}

struct SimulatorRuntime: Sendable {
    var identifier: String
    var runtimeIdentifier: String
    var platformIdentifier: String
    var version: String
    var sizeBytes: Int64
    var deletable: Bool

    var platformName: String {
        switch platformIdentifier {
        case let id where id.contains("iphone"): "iOS"
        case let id where id.contains("watch"): "watchOS"
        case let id where id.contains("appletv"): "tvOS"
        case let id where id.contains("xr"): "visionOS"
        default: "Simulator"
        }
    }

    static func load() -> [SimulatorRuntime] {
        guard let output = try? CommandRunner.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 30),
              output.status == 0
        else { return [] }
        return parse(json: Data(output.stdout.utf8))
    }

    static func parse(json: Data) -> [SimulatorRuntime] {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: [String: Any]] else { return [] }
        return root.values.compactMap { entry in
            guard let identifier = entry["identifier"] as? String else { return nil }
            return SimulatorRuntime(
                identifier: identifier,
                runtimeIdentifier: entry["runtimeIdentifier"] as? String ?? "",
                platformIdentifier: entry["platformIdentifier"] as? String ?? "",
                version: entry["version"] as? String ?? "",
                sizeBytes: (entry["sizeBytes"] as? NSNumber)?.int64Value ?? 0,
                deletable: entry["deletable"] as? Bool ?? false
            )
        }
        .sorted { Version.isOrderedBefore($0.version, $1.version) }
    }
}
