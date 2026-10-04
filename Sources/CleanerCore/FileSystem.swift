import Foundation

/// Fast on-disk size calculation using `fts` (the same walker `du` uses).
public enum DirectorySize {
    /// Allocated bytes of a file or folder tree. Hard links are counted once. Never follows symlinks
    /// and never crosses into another volume.
    public static func allocatedSize(of url: URL) -> Int64 {
        allocatedSize(of: [url])
    }

    public static func allocatedSize(of urls: [URL]) -> Int64 {
        let paths = urls.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return 0 }

        var cPaths: [UnsafeMutablePointer<CChar>?] = paths.map { strdup($0) }
        cPaths.append(nil)
        defer { cPaths.forEach { free($0) } }

        guard let fts = fts_open(&cPaths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return 0 }
        defer { fts_close(fts) }

        var total: Int64 = 0
        var seenHardLinks = Set<HardLinkKey>()
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D, FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                if info != FTS_D, stat.st_nlink > 1 {
                    let key = HardLinkKey(device: Int64(stat.st_dev), inode: UInt64(stat.st_ino))
                    if !seenHardLinks.insert(key).inserted { continue }
                }
                total += Int64(stat.st_blocks) * 512
            default:
                continue
            }
        }
        return total
    }

    private struct HardLinkKey: Hashable {
        let device: Int64
        let inode: UInt64
    }
}

enum FileInfo {
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Child folders (not files, not symlinks), including hidden ones.
    static func subdirectories(of url: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) else {
            return []
        }
        return children.filter { child in
            guard let values = try? child.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func childNames(of url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
    }

    static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}

/// Numeric comparison of dotted version strings ("2026.1.10" > "2026.1.9", "8.13" > "8.9").
public enum Version {
    public static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }

    public static func isOrderedBefore(_ a: String, _ b: String) -> Bool {
        let lhs = components(a)
        let rhs = components(b)
        for index in 0..<max(lhs.count, rhs.count) {
            let l = index < lhs.count ? lhs[index] : 0
            let r = index < rhs.count ? rhs[index] : 0
            if l != r { return l < r }
        }
        return a < b
    }
}
