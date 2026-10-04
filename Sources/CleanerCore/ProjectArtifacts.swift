import Foundation

/// A folder inside a project that a build tool regenerates.
/// It only counts when a matching build file sits next to it, so a hand-made `build/` folder is never touched.
public struct ArtifactRule: Sendable {
    public let folderName: String
    public let tool: String
    let matchesSiblings: @Sendable (Set<String>) -> Bool

    init(_ folderName: String, tool: String, whenSiblingsMatch: @escaping @Sendable (Set<String>) -> Bool) {
        self.folderName = folderName
        self.tool = tool
        self.matchesSiblings = whenSiblingsMatch
    }

    init(_ folderName: String, tool: String, nextToAnyOf files: Set<String>) {
        self.init(folderName, tool: tool) { !$0.isDisjoint(with: files) }
    }
}

public enum ProjectArtifacts {
    static let gradleFiles: Set<String> = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]

    public static let rules: [ArtifactRule] = [
        ArtifactRule("build", tool: "Gradle / Flutter", nextToAnyOf: gradleFiles.union(["pubspec.yaml"])),
        ArtifactRule(".gradle", tool: "Gradle", nextToAnyOf: gradleFiles),
        ArtifactRule(".cxx", tool: "Android NDK", nextToAnyOf: gradleFiles),
        ArtifactRule(".externalNativeBuild", tool: "Android NDK", nextToAnyOf: gradleFiles),
        ArtifactRule(".kotlin", tool: "Kotlin", nextToAnyOf: gradleFiles),
        ArtifactRule("node_modules", tool: "npm", nextToAnyOf: ["package.json"]),
        ArtifactRule(".next", tool: "Next.js", nextToAnyOf: ["package.json"]),
        ArtifactRule(".nuxt", tool: "Nuxt", nextToAnyOf: ["package.json"]),
        ArtifactRule(".turbo", tool: "Turborepo", nextToAnyOf: ["package.json"]),
        ArtifactRule(".parcel-cache", tool: "Parcel", nextToAnyOf: ["package.json"]),
        ArtifactRule(".svelte-kit", tool: "SvelteKit", nextToAnyOf: ["package.json"]),
        ArtifactRule(".angular", tool: "Angular", nextToAnyOf: ["angular.json"]),
        ArtifactRule(".dart_tool", tool: "Dart", nextToAnyOf: ["pubspec.yaml"]),
        ArtifactRule("Pods", tool: "CocoaPods", nextToAnyOf: ["Podfile"]),
        ArtifactRule(".build", tool: "SwiftPM", nextToAnyOf: ["Package.swift"]),
        ArtifactRule("DerivedData", tool: "Xcode") { siblings in
            siblings.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
        },
        ArtifactRule("target", tool: "Cargo / Maven", nextToAnyOf: ["Cargo.toml", "pom.xml"]),
        // Unity regenerates these from Assets/.
        ArtifactRule("Library", tool: "Unity") { $0.contains("Assets") && $0.contains("ProjectSettings") },
        ArtifactRule("Temp", tool: "Unity") { $0.contains("Assets") && $0.contains("ProjectSettings") },
        ArtifactRule("obj", tool: "Unity") { $0.contains("Assets") && $0.contains("ProjectSettings") },
    ]

    private static let rulesByName: [String: [ArtifactRule]] = Dictionary(grouping: rules, by: \.folderName)

    /// Folders never worth descending into when looking for artifacts.
    static let neverDescend: Set<String> = [".git", ".svn", ".hg", ".idea", ".vscode", "node_modules", "Pods"]

    /// Artifact folders inside a project. Matching folders are not descended into, so nested
    /// `node_modules` are counted once as part of their parent.
    public static func findArtifacts(in project: URL, maxDepth: Int = 8) -> [URL] {
        var artifacts: [URL] = []
        var queue: [(url: URL, depth: Int)] = [(project.standardizedFileURL, 0)]
        var index = 0
        while index < queue.count {
            let (dir, depth) = queue[index]
            index += 1
            let siblings = Set(FileInfo.childNames(of: dir))
            for child in FileInfo.subdirectories(of: dir) {
                let name = child.lastPathComponent
                if let candidates = rulesByName[name], candidates.contains(where: { $0.matchesSiblings(siblings) }) {
                    artifacts.append(child)
                    continue
                }
                if name.hasPrefix(".") || neverDescend.contains(name) || ProjectDiscovery.isToolchain(child) { continue }
                if depth + 1 < maxDepth {
                    queue.append((child, depth + 1))
                }
            }
        }
        return artifacts
    }

    /// How an artifact folder is shown in the list. Unity's generic names get a prefix so
    /// "Library" isn't mistaken for ~/Library.
    public static func displayName(forFolder name: String) -> String {
        switch name {
        case "Library", "Temp", "obj": "Unity \(name)"
        default: name
        }
    }

    /// When the project was last worked on: git activity if available, otherwise the folder's own date.
    public static func lastActivity(of project: URL) -> Date? {
        for marker in [".git/index", ".git/HEAD", ".git/logs/HEAD"] {
            if let date = FileInfo.modificationDate(project.appendingPathComponent(marker)) { return date }
        }
        return FileInfo.modificationDate(project)
    }
}
