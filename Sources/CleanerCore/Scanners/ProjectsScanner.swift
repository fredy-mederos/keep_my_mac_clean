import Foundation

/// Build outputs inside your own projects (`build/`, `node_modules/`, `.gradle/`, `.dart_tool/`...).
/// One item per project so you can choose which projects to clean.
///
/// A folder is only offered as Safe when it passes two checks: it matches an artifact rule
/// (`ProjectArtifacts`), and git ignores it with nothing tracked inside (`GitIgnoreCheck`).
/// Folders git doesn't ignore are left out; projects outside git become Review.
public struct ProjectsScanner: CleanupScanner {
    public let categoryID = "projects"
    public let title = "Project build folders"
    public let symbol = "folder.badge.gearshape"

    public init() {}

    /// Folders that come back through a package install rather than a local build.
    static let downloadedArtifacts: Set<String> = [
        "node_modules", "Pods", ".dart_tool", "bundle", "packages", "deps", ".venv", "venv",
    ]

    public func probes(in context: ScanContext) -> [ItemProbe] {
        context.allProjects().map { project in
            .one {
                let found = ProjectArtifacts.findArtifacts(in: project)
                guard !found.isEmpty else { return nil }
                let git = context.runsSystemCommands
                    ? GitIgnoreCheck.check(found, in: project)
                    : GitIgnoreCheck.Result(isRepository: false, ignored: [], skipped: [])
                let artifacts = git.isRepository ? git.ignored : found
                guard !artifacts.isEmpty else { return nil }

                let names = Set(artifacts.map(\.lastPathComponent))
                let kinds = names.map(ProjectArtifacts.displayName(forFolder:)).sorted().joined(separator: ", ")
                let count = artifacts.count == 1 ? "1 folder" : "\(artifacts.count) folders"
                let location = PathFormat.abbreviated(project, home: context.home)
                let downloads = names.intersection(Self.downloadedArtifacts).sorted()
                return CleanupItem(
                    id: "project:\(project.path)",
                    title: project.lastPathComponent,
                    detail: "\(count): \(kinds)",
                    size: DirectorySize.allocatedSize(of: artifacts),
                    safety: git.isRepository ? .safe : .review,
                    action: .removePaths(artifacts),
                    reason: git.isRepository
                        ? "Build outputs (\(kinds)) in \(location), all ignored by git. Your source files aren't touched."
                        : "Build outputs (\(kinds)) in \(location). It isn't a git repository, so git couldn't confirm they're ignored.",
                    cost: (downloads.isEmpty
                        ? "Next build of this project starts from scratch"
                        : "Next install re-downloads \(downloads.map(ProjectArtifacts.displayName(forFolder:)).joined(separator: ", "))")
                        + (names.contains(".playwright-cli") ? "; old Playwright session logs and screenshots are gone" : ""),
                    costLevel: downloads.isEmpty ? .rebuild : .redownload,
                    afterCleaning: "Build tools recreate these the next time you build or install dependencies.",
                    revealURL: project,
                    lastUsed: ProjectArtifacts.lastActivity(of: project),
                    project: ProjectProfiler.profile(of: project, runsGit: context.runsSystemCommands),
                    checkedWithGit: git.isRepository,
                    skipped: git.skipped
                )
            }
        }
    }
}
