import Foundation

public struct SkippedFolder: Sendable, Hashable {
    public var url: URL
    public var reason: String
}

/// Second opinion from git on build folders found by the artifact rules: a folder only counts as safe
/// when git ignores it and none of its files are tracked.
public enum GitIgnoreCheck {
    public struct Result: Sendable, Equatable {
        /// False when the project isn't in a git repository (or git isn't available).
        public var isRepository: Bool
        /// Ignored by git with no tracked files inside: safe to delete.
        public var ignored: [URL]
        public var skipped: [SkippedFolder]
    }

    public static func check(_ folders: [URL], in project: URL) -> Result {
        let git = "/usr/bin/git"
        guard !folders.isEmpty,
              let inside = try? CommandRunner.run(git, ["-C", project.path, "rev-parse", "--is-inside-work-tree"], timeout: 5),
              inside.status == 0, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        else {
            return Result(isRepository: false, ignored: [], skipped: [])
        }

        let base = project.standardizedFileURL.path
        let relative = folders.map { folder -> String in
            let path = folder.standardizedFileURL.path
            return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
        }

        // Prints the paths git ignores. Exit status 1 just means none are ignored.
        var ignoredPaths = Set<String>()
        if let output = try? CommandRunner.run(git, ["-C", project.path, "check-ignore", "--"] + relative, timeout: 10),
           output.status == 0 || output.status == 1 {
            ignoredPaths = Set(output.stdout.split(whereSeparator: \.isNewline).map { normalized(String($0)) })
        }

        // Files git tracks inside these folders, even if a .gitignore pattern matches them.
        var trackedFiles: [String] = []
        if let output = try? CommandRunner.run(git, ["-C", project.path, "ls-files", "-z", "--"] + relative, timeout: 10),
           output.status == 0 {
            trackedFiles = output.stdout.split(separator: "\0").map(String.init)
        }

        // Some .gitignore files ignore a folder's contents (`*.dll`, `*.nupkg`) rather than the folder itself.
        // That's the same to git, so a folder counts as ignored when none of its files would show as untracked.
        func trackedCount(_ path: String) -> Int {
            trackedFiles.filter { $0 == path || $0.hasPrefix(path + "/") }.count
        }
        let notIgnoredByName = relative.filter { !ignoredPaths.contains(normalized($0)) && trackedCount($0) == 0 }
        var visibleFiles: [String] = []
        if !notIgnoredByName.isEmpty,
           let output = try? CommandRunner.run(git, ["-C", project.path, "ls-files", "-z", "--others", "--exclude-standard", "--"] + notIgnoredByName, timeout: 15),
           output.status == 0 {
            visibleFiles = output.stdout.split(separator: "\0").map(String.init)
        }

        var ignored: [URL] = []
        var skipped: [SkippedFolder] = []
        for (folder, path) in zip(folders, relative) {
            let tracked = trackedCount(path)
            let visible = visibleFiles.contains { $0 == path || $0.hasPrefix(path + "/") }
            if tracked > 0 {
                skipped.append(SkippedFolder(url: folder, reason: tracked == 1 ? "1 file tracked in git" : "\(tracked) files tracked in git"))
            } else if ignoredPaths.contains(normalized(path)) || !visible {
                ignored.append(folder)
            } else {
                skipped.append(SkippedFolder(url: folder, reason: "not ignored by git"))
            }
        }
        return Result(isRepository: true, ignored: ignored, skipped: skipped)
    }

    private static func normalized(_ path: String) -> String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
