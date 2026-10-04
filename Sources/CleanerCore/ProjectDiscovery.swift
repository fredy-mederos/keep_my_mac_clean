import Foundation

/// Finds code projects and the folders that hold them.
///
/// First launch walks the home folder to find projects, then saves their parent folders
/// ("locations", e.g. `~/Documents/projects`) so later scans only walk those.
public enum ProjectDiscovery {
    static let markerFiles: Set<String> = [
        "settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts",
        "Package.swift", "Podfile", "package.json", "pubspec.yaml",
        "Cargo.toml", "pom.xml", "go.mod", "mix.exs", "Gemfile", "pyproject.toml",
    ]
    static let markerExtensions: Set<String> = ["xcodeproj", "xcworkspace", "sln", "csproj"]

    /// Never descend into these while looking for projects.
    static let skippedFolders: Set<String> = [
        "Library", "Applications", "Movies", "Music", "Pictures", "Public",
        "node_modules", "Pods", "build", "DerivedData", "Carthage", "vendor", "venv",
    ]

    public static func isProjectRoot(_ url: URL) -> Bool {
        let names = FileInfo.childNames(of: url)
        if names.contains(where: { markerFiles.contains($0) || markerExtensions.contains(($0 as NSString).pathExtension) }) {
            return true
        }
        // Unity projects.
        return names.contains("Assets") && names.contains("ProjectSettings")
    }

    /// Toolchains that look like projects but aren't yours to clean (e.g. the Flutter SDK).
    static func isToolchain(_ url: URL) -> Bool {
        FileInfo.exists(url.appendingPathComponent("bin/flutter"))
    }

    /// Breadth-first walk that stops at the first project root on each branch.
    /// - Parameter rootsCanBeProjects: false when walking the home folder itself.
    public static func findProjects(in roots: [URL], maxDepth: Int, rootsCanBeProjects: Bool = true) -> [URL] {
        var projects: [URL] = []
        var visited = Set<String>()

        for root in roots {
            var queue: [(url: URL, depth: Int)] = [(root.standardizedFileURL, 0)]
            var index = 0
            while index < queue.count {
                let (dir, depth) = queue[index]
                index += 1
                guard visited.insert(dir.path).inserted else { continue }
                if isToolchain(dir) { continue }
                if depth > 0 || rootsCanBeProjects, isProjectRoot(dir) {
                    projects.append(dir)
                    continue
                }
                guard depth < maxDepth else { continue }
                for child in FileInfo.subdirectories(of: dir) {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") || skippedFolders.contains(name) { continue }
                    if markerExtensions.contains(child.pathExtension) || child.pathExtension == "app" { continue }
                    queue.append((child, depth + 1))
                }
            }
        }
        return projects
    }

    /// Turns project paths into the folders worth remembering.
    ///
    /// A project's location is its ancestor two levels below home (`~/Documents/projects/auto1/app` →
    /// `~/Documents/projects`), or its parent if it is shallower. Projects sitting directly in home are
    /// their own location. Nested locations collapse into their ancestor.
    public static func locations(for projects: [URL], home: URL) -> [URL] {
        let homeComponents = home.standardizedFileURL.pathComponents
        let candidates: [String] = projects.map { project in
            let components = project.standardizedFileURL.pathComponents
            guard components.count > homeComponents.count,
                  Array(components.prefix(homeComponents.count)) == homeComponents
            else {
                return project.standardizedFileURL.deletingLastPathComponent().path
            }
            let depth = components.count - homeComponents.count
            let locationDepth = min(2, depth - 1)
            if locationDepth == 0 { return project.standardizedFileURL.path }
            return NSString.path(withComponents: Array(components.prefix(homeComponents.count + locationDepth)))
        }
        return collapse(candidates).map { URL(fileURLWithPath: $0) }
    }

    /// Removes duplicates and paths already covered by an ancestor in the list.
    public static func collapse(_ paths: [String]) -> [String] {
        var kept: [String] = []
        for path in Set(paths).sorted(by: { $0.count < $1.count }) {
            if !kept.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                kept.append(path)
            }
        }
        return kept.sorted()
    }

    /// First-launch discovery: walk home and return the project locations to remember.
    public static func discoverLocations(home: URL) -> [URL] {
        let projects = findProjects(in: [home], maxDepth: 6, rootsCanBeProjects: false)
        return locations(for: projects, home: home)
    }

    /// Regular scans: projects inside the remembered locations.
    public static func projects(inLocations locations: [URL]) -> [URL] {
        findProjects(in: locations.filter(FileInfo.isDirectory), maxDepth: 5)
    }
}
