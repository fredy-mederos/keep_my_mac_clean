import Foundation

/// Build outputs inside your own projects (`build/`, `node_modules/`, `.gradle/`, `.dart_tool/`...).
/// One item per project so you can choose which projects to clean.
public struct ProjectsScanner: CleanupScanner {
    public let categoryID = "projects"
    public let title = "Project build folders"
    public let symbol = "folder.badge.gearshape"

    public init() {}

    /// Folders that come back through a package install rather than a local build.
    static let downloadedArtifacts: Set<String> = ["node_modules", "Pods", ".dart_tool"]

    public func probes(in context: ScanContext) -> [ItemProbe] {
        context.allProjects().map { project in
            .one {
                let artifacts = ProjectArtifacts.findArtifacts(in: project)
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
                    safety: .safe,
                    action: .removePaths(artifacts),
                    reason: "Build outputs (\(kinds)) in \(location). Your source files aren't touched.",
                    cost: downloads.isEmpty
                        ? "Next build of this project starts from scratch"
                        : "Next install re-downloads \(downloads.joined(separator: ", "))",
                    costLevel: downloads.isEmpty ? .rebuild : .redownload,
                    afterCleaning: "Build tools recreate these the next time you build or install dependencies.",
                    revealURL: project,
                    lastUsed: ProjectArtifacts.lastActivity(of: project)
                )
            }
        }
    }
}
