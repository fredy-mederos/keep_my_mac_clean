import Foundation

/// Reclaimable Docker data, as reported by `docker system df`. Cleaned with Docker's own prune commands.
/// Shows nothing when Docker isn't installed or its daemon isn't running.
public struct DockerScanner: CleanupScanner {
    public let categoryID = "docker"
    public let title = "Docker"
    public let symbol = "square.stack.3d.down.right"

    public init() {}

    static func dockerExecutable(home: URL) -> String? {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            home.appendingPathComponent(".docker/bin/docker").path,
            home.appendingPathComponent(".orbstack/bin/docker").path,
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func probes(in context: ScanContext) -> [ItemProbe] {
        guard context.runsSystemCommands, let docker = Self.dockerExecutable(home: context.home) else { return [] }
        return [ItemProbe {
            guard let output = try? CommandRunner.run(docker, ["system", "df", "--format", "{{json .}}"], timeout: 20),
                  output.status == 0
            else { return [] }
            return Self.items(fromSystemDF: output.stdout, docker: docker)
        }]
    }

    struct DFRow: Decodable, Equatable {
        var type: String
        var totalCount: String
        var active: String
        var reclaimable: String

        enum CodingKeys: String, CodingKey {
            case type = "Type", totalCount = "TotalCount", active = "Active", reclaimable = "Reclaimable"
        }
    }

    static func parse(systemDF output: String) -> [DFRow] {
        output.split(whereSeparator: \.isNewline).compactMap {
            try? JSONDecoder().decode(DFRow.self, from: Data($0.utf8))
        }
    }

    /// Docker prints decimal sizes like "1.2GB (45%)", "512.3MB", "23kB", "0B".
    static func bytes(fromDockerSize text: String) -> Int64 {
        guard let match = text.firstMatch(of: /([0-9.]+)\s*([kKMGT]?B)/), let value = Double(match.1) else { return 0 }
        let multiplier: Double = switch match.2.uppercased() {
        case "KB": 1e3
        case "MB": 1e6
        case "GB": 1e9
        case "TB": 1e12
        default: 1
        }
        return Int64((value * multiplier).rounded())
    }

    static func items(fromSystemDF output: String, docker: String) -> [CleanupItem] {
        parse(systemDF: output).compactMap { row in
            let size = bytes(fromDockerSize: row.reclaimable)
            let total = Int(row.totalCount) ?? 0
            let active = Int(row.active) ?? 0
            switch row.type {
            case "Build Cache":
                return CleanupItem(
                    id: "docker.build-cache", title: "Docker build cache", detail: "Layers cached by docker build",
                    size: size, safety: .safe,
                    action: .command(executable: docker, arguments: ["builder", "prune", "--all", "--force"]),
                    reason: "Layers cached by docker build to speed up rebuilds.",
                    cost: "The next docker build of each image is slower",
                    costLevel: .rebuild,
                    afterCleaning: "Removed with `docker builder prune`. Docker caches layers again as you build."
                )
            case "Images":
                return CleanupItem(
                    id: "docker.images", title: "Unused Docker images",
                    detail: "\(max(total - active, 0)) of \(total) images aren't used by any container",
                    size: size, safety: .review,
                    action: .command(executable: docker, arguments: ["image", "prune", "--all", "--force"]),
                    reason: "\(max(total - active, 0)) images that no container, running or stopped, uses.",
                    cost: "Pulled again from the registry or rebuilt when you need them",
                    costLevel: .redownload,
                    afterCleaning: "Removed with `docker image prune --all`."
                )
            case "Containers":
                return CleanupItem(
                    id: "docker.containers", title: "Stopped Docker containers",
                    detail: "\(max(total - active, 0)) stopped containers",
                    size: size, safety: .review,
                    action: .command(executable: docker, arguments: ["container", "prune", "--force"]),
                    reason: "Containers that exited and aren't running.",
                    cost: "Anything written inside these containers (not in a volume) is lost",
                    costLevel: .dataLoss,
                    afterCleaning: "Removed with `docker container prune`. Start new containers from their images."
                )
            case "Local Volumes":
                return CleanupItem(
                    id: "docker.volumes", title: "Unused Docker volumes",
                    detail: "\(max(total - active, 0)) volumes not attached to a container",
                    size: size, safety: .review,
                    action: .command(executable: docker, arguments: ["volume", "prune", "--all", "--force"]),
                    reason: "Volumes no container is attached to. They often hold databases and uploads.",
                    cost: "Their data (databases, uploads…) can't be recovered",
                    costLevel: .dataLoss,
                    afterCleaning: "Removed with `docker volume prune --all`."
                )
            default:
                return nil
            }
        }
    }
}
