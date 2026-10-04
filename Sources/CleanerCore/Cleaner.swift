import Foundation

/// Last line of defence before anything is deleted: only paths deep inside the home folder,
/// and never the well-known folders themselves.
public enum PathGuard {
    public enum Violation: Error, LocalizedError, Equatable {
        case outsideHome(String)
        case tooShallow(String)
        case protected(String)

        public var errorDescription: String? {
            switch self {
            case .outsideHome(let path): "Refused to delete \(path): it is outside your home folder."
            case .tooShallow(let path): "Refused to delete \(path): it is a top-level folder."
            case .protected(let path): "Refused to delete \(path): it is a protected folder."
            }
        }
    }

    static let protectedRelativePaths: Set<String> = [
        "Library/Caches", "Library/Application Support", "Library/Developer", "Library/Logs",
        "Library/Preferences", "Library/Containers", "Library/Group Containers", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Mail", "Library/Messages", "Library/Keychains", "Library/Android",
        "Library/pnpm", "Library/Developer/Xcode", "Library/Developer/CoreSimulator",
        "Documents/projects", ".gradle/caches", ".gradle/wrapper", ".android/avd",
    ]

    public static func validate(_ url: URL, home: URL) throws {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { throw Violation.outsideHome(path) }
        let relative = String(path.dropFirst(homePath.count + 1))
        guard relative.split(separator: "/").count >= 2 else { throw Violation.tooShallow(path) }
        guard !protectedRelativePaths.contains(relative) else { throw Violation.protected(path) }
    }
}

public struct CleanupOutcome: Sendable {
    public var item: CleanupItem
    public var error: String?
    public var succeeded: Bool { error == nil }
}

public struct Cleaner: Sendable {
    public var home: URL
    /// How files are moved to the Trash. Replaced in tests so they never touch the real Trash.
    public var trash: @Sendable (URL) throws -> Void

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.home = home
        self.trash = trash
    }

    /// Cleans one item. Blocking: call it off the main thread.
    public func clean(_ item: CleanupItem) -> CleanupOutcome {
        do {
            switch item.action {
            case .removePaths(let urls):
                // Validate everything first so an item is never half-deleted because of a bad path.
                for url in urls { try PathGuard.validate(url, home: home) }
                var failures: [String] = []
                for url in urls where FileInfo.exists(url) || isSymlink(url) {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        failures.append(url.lastPathComponent)
                    }
                }
                if !failures.isEmpty {
                    return CleanupOutcome(item: item, error: "Couldn't remove everything in \(failures.joined(separator: ", ")).")
                }
            case .moveToTrash(let urls):
                for url in urls { try PathGuard.validate(url, home: home) }
                var failures: [String] = []
                for url in urls where FileInfo.exists(url) {
                    do {
                        try trash(url)
                    } catch {
                        failures.append(url.lastPathComponent)
                    }
                }
                if !failures.isEmpty {
                    return CleanupOutcome(item: item, error: "Couldn't move \(failures.joined(separator: ", ")) to the Trash.")
                }
            case .command(let executable, let arguments):
                let output = try CommandRunner.run(executable, arguments, timeout: 600)
                if output.status != 0 {
                    let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    return CleanupOutcome(item: item, error: message.isEmpty ? "The command failed (\(output.status))." : message)
                }
            }
            return CleanupOutcome(item: item, error: nil)
        } catch {
            return CleanupOutcome(item: item, error: error.localizedDescription)
        }
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }
}
