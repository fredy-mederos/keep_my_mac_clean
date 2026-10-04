import CoreServices
import Foundation

/// Your own big files and forgotten downloads, with a suggestion for each.
/// These are never deleted: cleaning moves them to the Trash.
public struct LargeFilesScanner: CleanupScanner {
    public let categoryID = "files"
    public let title = "Large files and downloads"
    public let symbol = "doc.on.doc"

    public init() {}

    public func probes(in context: ScanContext) -> [ItemProbe] {
        [
            ItemProbe { largeFiles(context) },
            ItemProbe { downloads(context) },
        ]
    }

    // MARK: Kinds and suggestions

    public enum FileKind: String, Sendable {
        case installer, application, archive, appBuild, video, virtualMachine, model, other

        static let extensions: [FileKind: Set<String>] = [
            .installer: ["dmg", "pkg", "mpkg", "xip", "iso"],
            .application: ["app"],
            .archive: ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"],
            .appBuild: ["apk", "aab", "ipa", "apks"],
            .video: ["mov", "mp4", "m4v", "mkv", "avi", "webm"],
            .virtualMachine: ["vmdk", "vdi", "qcow2", "vhd", "vhdx", "utm"],
            .model: ["gguf", "safetensors", "onnx", "ckpt", "mlmodel", "pt"],
        ]

        public static func of(_ url: URL) -> FileKind {
            let ext = url.pathExtension.lowercased()
            return extensions.first { $0.value.contains(ext) }?.key ?? .other
        }

        public var label: String {
            switch self {
            case .installer: "Installer"
            case .application: "App"
            case .archive: "Archive"
            case .appBuild: "App build"
            case .video: "Video"
            case .virtualMachine: "Virtual machine disk"
            case .model: "ML model"
            case .other: "File"
            }
        }
    }

    /// "Archive.zip" next to a folder "Archive" was already extracted.
    static func isExtracted(_ archive: URL) -> Bool {
        var base = archive.deletingPathExtension()
        if base.pathExtension == "tar" { base = base.deletingPathExtension() }
        return FileInfo.isDirectory(base)
    }

    public static func suggestion(for url: URL, kind: FileKind) -> String {
        switch kind {
        case .installer: "Installer. Once the app is installed you don't need it anymore."
        case .application: "App left in a downloads folder. Move it to Applications or remove it."
        case .archive:
            isExtracted(url)
                ? "Archive that's already extracted next to it, so the archive itself is probably not needed."
                : "Archive. Remove it if you've already extracted it or no longer need it."
        case .appBuild: "App build. You can build or download it again."
        case .video: "Video. Consider moving it to an external drive or cloud storage."
        case .virtualMachine: "Virtual machine disk. Remove it if you no longer use that VM."
        case .model: "Machine learning model. You can download it again when you need it."
        case .other: "Large file. Move it to the Trash if you no longer need it."
        }
    }

    static let trashCost = "Recoverable from the Trash until you empty it"
    static let trashAfterCleaning = "Moved to the Trash. The space comes back when you empty the Trash."

    // MARK: Large files anywhere in home

    /// Folders never searched for large files: system data, build outputs (covered elsewhere) and bundles.
    static let skippedFolderNames: Set<String> = [
        "Library", "Applications", "node_modules", "Pods", "DerivedData", "build", "Carthage", "target",
    ]
    /// Top-level home folders never searched. Pictures and Music are excluded because entering them makes
    /// macOS ask for Photos and media access.
    static let skippedHomeFolders: Set<String> = ["Library", "Applications", "Pictures", "Music"]
    static let skippedPackageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "xcarchive", "xcodeproj", "xcworkspace",
        "bundle", "framework", "xcframework", "dSYM", "logicx", "fcpbundle", "imovielibrary",
    ]

    /// Files of at least `minimumSize` under `roots`. Hidden folders, skipped names and bundles aren't entered.
    /// - Parameter skipFilesDirectlyIn: folders whose top-level files are reported by another probe.
    static func findLargeFiles(in roots: [URL], minimumSize: Int64, skipFilesDirectlyIn: Set<String> = []) -> [(url: URL, size: Int64)] {
        let paths = roots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return [] }
        var cPaths: [UnsafeMutablePointer<CChar>?] = paths.map { strdup($0) }
        cPaths.append(nil)
        defer { cPaths.forEach { free($0) } }
        guard let fts = fts_open(&cPaths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return [] }
        defer { fts_close(fts) }

        // Compare resolved paths: /var and /private/var are the same folder, for example.
        let skippedParents = Set(skipFilesDirectlyIn.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path })
        var found: [(URL, Int64)] = []
        while let entry = fts_read(fts) {
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let url = URL(fileURLWithPath: path)
            switch info {
            case FTS_D:
                guard entry.pointee.fts_level > 0 else { continue }
                let name = url.lastPathComponent
                if name.hasPrefix(".") || skippedFolderNames.contains(name)
                    || skippedPackageExtensions.contains(url.pathExtension)
                    || skippedPackageExtensions.contains(url.pathExtension.lowercased())
                    // SDKs like Flutter's: their big files belong to the toolchain, not to you.
                    || (entry.pointee.fts_level <= 3 && ProjectDiscovery.isToolchain(url)) {
                    fts_set(fts, entry, FTS_SKIP)
                }
            case FTS_F:
                guard let stat = entry.pointee.fts_statp?.pointee else { continue }
                let size = Int64(stat.st_blocks) * 512
                guard size >= minimumSize, !url.lastPathComponent.hasPrefix(".") else { continue }
                if skippedParents.contains(url.deletingLastPathComponent().resolvingSymlinksInPath().path) { continue }
                found.append((url, size))
            default:
                continue
            }
        }
        return found
    }

    func largeFiles(_ context: ScanContext) -> [CleanupItem] {
        let roots = FileInfo.subdirectories(of: context.home).filter {
            let name = $0.lastPathComponent
            return !name.hasPrefix(".") && !Self.skippedFolderNames.contains(name) && !Self.skippedHomeFolders.contains(name)
                && !ProjectDiscovery.isToolchain($0)
        }
        let downloads = context.path("Downloads").standardizedFileURL.path
        return Self.findLargeFiles(in: roots, minimumSize: context.largeFileMinimumSize, skipFilesDirectlyIn: [downloads])
            .map { file in
                let kind = FileKind.of(file.url)
                let opened = FileDates.lastOpened(file.url)
                return CleanupItem(
                    id: "file:\(file.url.path)",
                    title: file.url.lastPathComponent,
                    detail: "\(kind.label) · \(PathFormat.abbreviated(file.url.deletingLastPathComponent(), home: context.home))",
                    size: file.size,
                    safety: .personal,
                    action: .moveToTrash([file.url]),
                    reason: Self.suggestion(for: file.url, kind: kind),
                    cost: Self.trashCost,
                    afterCleaning: Self.trashAfterCleaning,
                    revealURL: file.url,
                    lastUsed: opened ?? FileInfo.modificationDate(file.url),
                    dateKind: opened == nil ? .modified : .opened
                )
            }
    }

    // MARK: Downloads

    static let downloadKeepSize: Int64 = 10_000_000
    static let staleDownloadSize: Int64 = 100_000_000
    static let staleDownloadAge: TimeInterval = 30 * 86_400

    /// Whether a top-level Downloads entry is worth listing: installers and archives of any age,
    /// anything big, and medium files you downloaded more than a month ago.
    static func shouldList(kind: FileKind, size: Int64, added: Date?, largeFileMinimumSize: Int64, now: Date = Date()) -> Bool {
        switch kind {
        case .installer, .application, .archive, .appBuild:
            return size >= downloadKeepSize
        default:
            if size >= largeFileMinimumSize { return true }
            guard size >= staleDownloadSize, let added else { return false }
            return now.timeIntervalSince(added) > staleDownloadAge
        }
    }

    func downloads(_ context: ScanContext) -> [CleanupItem] {
        let downloads = context.path("Downloads")
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .addedToDirectoryDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: downloads, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return nil }
            // Plain folders are left to the large-file search so items never overlap.
            if values.isDirectory == true, values.isPackage != true { return nil }
            let kind = FileKind.of(url)
            let size = DirectorySize.allocatedSize(of: url)
            let added = values.addedToDirectoryDate
            guard Self.shouldList(kind: kind, size: size, added: added, largeFileMinimumSize: context.largeFileMinimumSize) else {
                return nil
            }
            return CleanupItem(
                id: "file:\(url.path)",
                title: url.lastPathComponent,
                detail: "\(kind.label) · ~/Downloads",
                size: size,
                safety: .personal,
                action: .moveToTrash([url]),
                reason: Self.suggestion(for: url, kind: kind),
                cost: Self.trashCost,
                afterCleaning: Self.trashAfterCleaning,
                revealURL: url,
                lastUsed: added ?? FileInfo.modificationDate(url),
                dateKind: .added
            )
        }
    }
}

enum FileDates {
    /// When the file was last opened, as recorded by Spotlight.
    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
