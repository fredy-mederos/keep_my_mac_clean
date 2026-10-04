import Foundation

/// Build outputs inside your own projects (`build/`, `node_modules/`, `.gradle/`, `.dart_tool/`...).
/// One item per project so you can choose which projects to clean.
public struct ProjectsScanner: CleanupScanner {
    public let categoryID = "projects"
    public let title = "Project build folders"
    public let symbol = "folder.badge.gearshape"

    public init() {}

    public func probes(in context: ScanContext) -> [ItemProbe] {
        ProjectDiscovery.projects(inLocations: context.projectLocations).map { project in
            .one {
                let artifacts = ProjectArtifacts.findArtifacts(in: project)
                guard !artifacts.isEmpty else { return nil }
                let kinds = Set(artifacts.map { ProjectArtifacts.displayName(forFolder: $0.lastPathComponent) })
                    .sorted()
                    .joined(separator: ", ")
                let count = artifacts.count == 1 ? "1 folder" : "\(artifacts.count) folders"
                let location = PathFormat.abbreviated(project, home: context.home)
                return CleanupItem(
                    id: "project:\(project.path)",
                    title: project.lastPathComponent,
                    detail: "\(count): \(kinds)",
                    size: DirectorySize.allocatedSize(of: artifacts),
                    safety: .safe,
                    action: .removePaths(artifacts),
                    note: "\(location)\n\nBuild tools recreate these. The next build or install of this project will take longer.",
                    revealURL: project,
                    lastUsed: ProjectArtifacts.lastActivity(of: project)
                )
            }
        }
    }
}
