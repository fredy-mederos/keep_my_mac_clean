import Foundation

/// Leftover settings and caches of IDE versions you no longer run (Android Studio, IntelliJ...),
/// plus JetBrains Toolbox and VS Code caches.
public struct IDEScanner: CleanupScanner {
    public let categoryID = "ides"
    public let title = "IDEs"
    public let symbol = "chevron.left.forwardslash.chevron.right"

    public init() {}

    static let vendors = ["Google", "JetBrains"]
    static let dataRoots = ["Library/Caches", "Library/Application Support", "Library/Logs"]

    static let productNames: [String: String] = [
        "AndroidStudio": "Android Studio",
        "AndroidStudioPreview": "Android Studio Preview",
        "IntelliJIdea": "IntelliJ IDEA",
        "IdeaIC": "IntelliJ IDEA CE",
        "WebStorm": "WebStorm", "PyCharm": "PyCharm", "PyCharmCE": "PyCharm CE",
        "GoLand": "GoLand", "CLion": "CLion", "Rider": "Rider", "RustRover": "RustRover",
        "DataGrip": "DataGrip", "RubyMine": "RubyMine", "PhpStorm": "PhpStorm", "AppCode": "AppCode",
        "Fleet": "Fleet",
    ]

    public struct IDEDataFolder: Sendable, Hashable {
        public var product: String
        public var version: String

        /// "AndroidStudio2026.1.3" → (AndroidStudio, 2026.1.3).
        public static func parse(_ name: String) -> IDEDataFolder? {
            guard let match = name.wholeMatch(of: /([A-Za-z]+)(\d{4}(?:\.\d+)*)/) else { return nil }
            return IDEDataFolder(product: String(match.1), version: String(match.2))
        }

        public var name: String { product + version }
        public var displayName: String { "\(IDEScanner.productNames[product] ?? product) \(version)" }
    }

    /// Data folder names of installed IDEs, read from each app's product-info.json.
    static func installedDataFolders(in applicationFolders: [URL]) -> Set<String> {
        var names = Set<String>()
        var apps: [URL] = []
        for folder in applicationFolders {
            for child in FileInfo.subdirectories(of: folder) {
                if child.pathExtension == "app" {
                    apps.append(child)
                } else {
                    // e.g. ~/Applications/JetBrains Toolbox/*.app
                    apps += FileInfo.subdirectories(of: child).filter { $0.pathExtension == "app" }
                }
            }
        }
        for app in apps {
            let info = app.appendingPathComponent("Contents/Resources/product-info.json")
            guard let data = try? Data(contentsOf: info),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = json["dataDirectoryName"] as? String
            else { continue }
            names.insert(name)
        }
        return names
    }

    /// Which versions are old: anything not installed. If no version of a product is installed,
    /// keep the newest one to stay on the safe side.
    public static func oldVersions(found: Set<IDEDataFolder>, installed: Set<String>) -> [IDEDataFolder: String?] {
        var result: [IDEDataFolder: String?] = [:]
        for (_, versions) in Dictionary(grouping: found, by: \.product) {
            let installedVersions = versions.filter { installed.contains($0.name) }
            let current = installedVersions.isEmpty
                ? versions.max { Version.isOrderedBefore($0.version, $1.version) }.map { [$0] } ?? []
                : Array(installedVersions)
            let newestCurrent = current.max { Version.isOrderedBefore($0.version, $1.version) }?.version
            for version in versions where !current.contains(version) {
                result[version] = newestCurrent
            }
        }
        return result
    }

    public func probes(in context: ScanContext) -> [ItemProbe] {
        var foldersByVersion: [IDEDataFolder: [URL]] = [:]
        for root in Self.dataRoots {
            for vendor in Self.vendors {
                for dir in FileInfo.subdirectories(of: context.path("\(root)/\(vendor)")) {
                    if let parsed = IDEDataFolder.parse(dir.lastPathComponent) {
                        foldersByVersion[parsed, default: []].append(dir)
                    }
                }
            }
        }

        let installed = Self.installedDataFolders(in: context.applicationFolders)
        let old = Self.oldVersions(found: Set(foldersByVersion.keys), installed: installed)

        var probes: [ItemProbe] = old.map { version, current in
            let urls = foldersByVersion[version] ?? []
            return .one { CleanupItem.folders(
                id: "ide.old:\(version.name)",
                title: "\(version.displayName) leftovers",
                detail: current.map { "You now use \($0)" } ?? "Settings, caches and logs",
                urls: urls,
                safety: .review,
                reason: current.map { "Data from \(version.displayName). You now use \($0), which imported its settings when you upgraded." }
                    ?? "Settings, caches and logs of \(version.displayName), a version you no longer run.",
                cost: "You lose that version's own settings, plugins and local history if you ever go back to it",
                costLevel: .loseOption,
                afterCleaning: "Your current version keeps working with its own settings.",
                lastUsed: urls.compactMap(FileInfo.modificationDate).max()
            ) }
        }

        probes.append(.one { CleanupItem.folders(
            id: "ide.toolbox.downloads", title: "JetBrains Toolbox downloads", detail: "~/Library/Caches/JetBrains/Toolbox/download",
            urls: [context.path("Library/Caches/JetBrains/Toolbox/download")], safety: .safe,
            reason: "Installers JetBrains Toolbox already used.",
            cost: "Nothing: the IDEs are already installed",
            costLevel: nil
        ) })
        probes.append(.one { CleanupItem.folders(
            id: "ide.toolbox.backup", title: "JetBrains Toolbox rollback backups", detail: "~/Library/Caches/JetBrains/Toolbox/backup",
            urls: [context.path("Library/Caches/JetBrains/Toolbox/backup")], safety: .review,
            reason: "Copies of previous IDE versions JetBrains Toolbox keeps for rollbacks.",
            cost: "You can't roll back an IDE update from Toolbox",
            costLevel: .loseOption,
            afterCleaning: "Toolbox keeps a new backup the next time it updates an IDE."
        ) })

        for (app, folder) in [("VS Code", "Code"), ("VS Code Insiders", "Code - Insiders")] {
            let base = context.path("Library/Application Support/\(folder)")
            probes.append(.one { CleanupItem.folders(
                id: "ide.vscode:\(folder)", title: "\(app) caches", detail: PathFormat.abbreviated(base, home: context.home),
                urls: ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache"].map { base.appendingPathComponent($0) },
                safety: .safe,
                reason: "Caches \(app) rebuilds on its own.",
                cost: "\(app) starts a little slower once",
                costLevel: .rebuild,
                afterCleaning: "\(app) recreates these on launch.",
                revealURL: base,
                blockers: [.vsCode]
            ) })
        }
        return probes
    }
}
