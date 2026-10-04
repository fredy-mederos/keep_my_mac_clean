import Foundation

/// A throwaway fake home folder for tests. Deleted when the test ends.
final class TestHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kmmc-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates a file with `bytes` of data, creating parent folders as needed.
    @discardableResult
    func file(_ relative: String, bytes: Int = 16, contents: String? = nil) throws -> URL {
        let file = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = contents.map { Data($0.utf8) } ?? Data(repeating: 7, count: bytes)
        try data.write(to: file)
        return file
    }

    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let folder = url.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relative).path)
    }

    func path(_ relative: String) -> URL {
        url.appendingPathComponent(relative)
    }
}
