import AppKit

public enum BlockerCheck {
    /// The blockers among `blockers` that are running right now.
    @MainActor
    public static func running(_ blockers: some Sequence<Blocker>) -> [Blocker] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Set(blockers).filter { blocker in
            if blocker.bundleIDs.contains(where: runningBundleIDs.contains) { return true }
            if let pattern = blocker.processPattern {
                return (try? CommandRunner.run("/usr/bin/pgrep", ["-f", pattern], timeout: 5))?.status == 0
            }
            return false
        }
        .sorted { $0.name < $1.name }
    }
}
