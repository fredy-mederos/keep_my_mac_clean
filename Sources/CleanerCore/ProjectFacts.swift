import Foundation

/// Cheap facts about your projects, used to explain what cleaning an item costs
/// ("Gradle 8.13 is used by 5 of your projects", "your projects compile against API 35 and 36").
enum ProjectFacts {
    static let gradleFiles = ["settings.gradle.kts", "settings.gradle", "build.gradle.kts", "build.gradle"]

    /// Folders that hold Gradle builds: the project itself, or `android/` in Flutter and React Native projects.
    static func gradleRoots(in projects: [URL]) -> [URL] {
        projects.flatMap { project in
            [project, project.appendingPathComponent("android")].filter { root in
                gradleFiles.contains { FileInfo.exists(root.appendingPathComponent($0)) }
            }
        }
    }

    /// The Gradle version a project's wrapper downloads, from `gradle/wrapper/gradle-wrapper.properties`.
    static func wrapperVersion(ofGradleRoot root: URL) -> String? {
        let properties = root.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")
        guard let text = try? String(contentsOf: properties, encoding: .utf8),
              let match = text.firstMatch(of: /distributionUrl=.*gradle-([0-9][^-\/]*(?:-rc-\d+)?)-(?:bin|all)\.zip/)
        else { return nil }
        return String(match.1)
    }

    /// How many Gradle builds use each wrapper version.
    static func wrapperUsage(in projects: [URL]) -> [String: Int] {
        var usage: [String: Int] = [:]
        for root in gradleRoots(in: projects) {
            if let version = wrapperVersion(ofGradleRoot: root) { usage[version, default: 0] += 1 }
        }
        return usage
    }

    /// API levels your projects compile against, read from build files and the version catalog.
    /// Best effort: values hidden behind constants in buildSrc aren't found.
    static func compileSdkLevels(in projects: [URL]) -> Set<Int> {
        var levels = Set<Int>()
        for root in gradleRoots(in: projects) {
            var files = [root.appendingPathComponent("gradle/libs.versions.toml")]
            for folder in [root] + FileInfo.subdirectories(of: root) where !folder.lastPathComponent.hasPrefix(".") {
                files += ["build.gradle.kts", "build.gradle"].map { folder.appendingPathComponent($0) }
            }
            for file in files {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for match in text.matches(of: /compileSdk(?:Version)?\s*[=(]?\s*"?(\d{2})\b/) {
                    if let level = Int(match.1) { levels.insert(level) }
                }
            }
        }
        return levels
    }

    /// Podfiles that still point at the git copy of the CocoaPods specs.
    static func podfilesUsingSpecsRepo(in projects: [URL]) -> [URL] {
        projects.flatMap { project in
            [project, project.appendingPathComponent("ios")].map { $0.appendingPathComponent("Podfile") }
        }
        .filter { podfile in
            guard let text = try? String(contentsOf: podfile, encoding: .utf8) else { return false }
            return text.contains("github.com/CocoaPods/Specs")
        }
    }

    static func flutterProjects(in projects: [URL]) -> [URL] {
        projects.filter { FileInfo.exists($0.appendingPathComponent("pubspec.yaml")) }
    }

    /// "1 of your projects", "3 of your projects".
    static func count(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
