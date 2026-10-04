import Foundation

/// Download caches of package managers. All of them re-download on demand.
public struct PackageCachesScanner: CleanupScanner {
    public let categoryID = "packages"
    public let title = "Package manager caches"
    public let symbol = "shippingbox"

    public init() {}

    struct Spec: Sendable {
        var id: String
        var title: String
        var paths: [String]
        var safety: Safety
        var note: String
    }

    static let specs: [Spec] = [
        Spec(id: "npm", title: "npm cache", paths: [".npm/_cacache", ".npm/_npx", ".npm/_logs"], safety: .safe,
             note: "npm downloads packages again when needed."),
        Spec(id: "pnpm", title: "pnpm store", paths: ["Library/pnpm/store"], safety: .safe,
             note: "pnpm downloads packages again when needed. Projects keep their linked copies, so slightly less space may be freed."),
        Spec(id: "yarn", title: "Yarn cache", paths: ["Library/Caches/Yarn", ".yarn/berry/cache"], safety: .safe,
             note: "Yarn downloads packages again when needed."),
        Spec(id: "bun", title: "Bun cache", paths: [".bun/install/cache"], safety: .safe,
             note: "Bun downloads packages again when needed."),
        Spec(id: "pip", title: "pip cache", paths: ["Library/Caches/pip"], safety: .safe,
             note: "pip downloads packages again when needed."),
        Spec(id: "swiftpm", title: "Swift Package Manager cache", paths: ["Library/Caches/org.swift.swiftpm"], safety: .safe,
             note: "Xcode and SwiftPM fetch packages again when needed."),
        Spec(id: "cocoapods", title: "CocoaPods cache", paths: ["Library/Caches/CocoaPods"], safety: .safe,
             note: "pod install downloads pods again when needed."),
        Spec(id: "homebrew", title: "Homebrew downloads", paths: ["Library/Caches/Homebrew"], safety: .safe,
             note: "Old bottles and installers. Homebrew downloads again if it needs them."),
        Spec(id: "node-gyp", title: "node-gyp headers", paths: ["Library/Caches/node-gyp"], safety: .safe,
             note: "Downloaded again when a native module builds."),
        Spec(id: "go", title: "Go build cache", paths: ["Library/Caches/go-build"], safety: .safe,
             note: "Go rebuilds it as you compile."),
        Spec(id: "cargo", title: "Cargo downloads", paths: [".cargo/registry/cache"], safety: .safe,
             note: "Cargo downloads crates again when needed."),
        Spec(id: "pub", title: "Dart and Flutter packages", paths: [".pub-cache/hosted"], safety: .review,
             note: "flutter pub get downloads them again, which can take a while for big projects."),
        Spec(id: "playwright", title: "Playwright browsers", paths: ["Library/Caches/ms-playwright", "Library/Caches/ms-playwright-go"], safety: .review,
             note: "Run `npx playwright install` to download the browsers again."),
        Spec(id: "maven", title: "Maven repository", paths: [".m2/repository"], safety: .review,
             note: "Maven and Gradle download these libraries again when needed."),
    ]

    public func probes(in context: ScanContext) -> [ItemProbe] {
        let caches: [ItemProbe] = Self.specs.map { spec in
            .one {
                let urls = spec.paths.map(context.path)
                return CleanupItem.folders(
                    id: "packages.\(spec.id)",
                    title: spec.title,
                    detail: urls.filter(FileInfo.exists).map { PathFormat.abbreviated($0, home: context.home) }.joined(separator: ", "),
                    urls: urls,
                    safety: spec.safety,
                    note: spec.note
                )
            }
        }
        return caches + cocoaPodsSpecRepos(context)
    }

    /// The old full git clone of github.com/CocoaPods/Specs. CocoaPods uses its CDN since 1.8.
    /// Private spec repos are left alone.
    func cocoaPodsSpecRepos(_ context: ScanContext) -> [ItemProbe] {
        FileInfo.subdirectories(of: context.path(".cocoapods/repos")).compactMap { repo in
            guard let config = try? String(contentsOf: repo.appendingPathComponent(".git/config"), encoding: .utf8),
                  config.contains("CocoaPods/Specs")
            else { return nil }
            return .one { CleanupItem.folders(
                id: "packages.cocoapods-specs:\(repo.lastPathComponent)",
                title: "CocoaPods specs (legacy git copy)",
                detail: PathFormat.abbreviated(repo, home: context.home),
                urls: [repo],
                safety: .review,
                note: "CocoaPods uses its CDN since version 1.8. Only needed if a Podfile has `source 'https://github.com/CocoaPods/Specs.git'`."
            ) }
        }
    }
}
