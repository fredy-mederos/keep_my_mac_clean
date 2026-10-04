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
        var reason: String
        var cost: String
        var afterCleaning: String
    }

    static let specs: [Spec] = [
        Spec(id: "npm", title: "npm cache", paths: [".npm/_cacache", ".npm/_npx", ".npm/_logs"], safety: .safe,
             reason: "Copies of packages npm downloaded before. Your projects keep their own node_modules.",
             cost: "Packages are re-downloaded the next time a project installs them",
             afterCleaning: "npm fills the cache again as you install packages."),
        Spec(id: "pnpm", title: "pnpm store", paths: ["Library/pnpm/store"], safety: .safe,
             reason: "pnpm's shared package store. Projects link to it, so slightly less space may be freed.",
             cost: "Packages are re-downloaded the next time a project installs them",
             afterCleaning: "pnpm fills the store again as you install packages."),
        Spec(id: "yarn", title: "Yarn cache", paths: ["Library/Caches/Yarn", ".yarn/berry/cache"], safety: .safe,
             reason: "Packages Yarn downloaded before.",
             cost: "Packages are re-downloaded the next time a project installs them",
             afterCleaning: "Yarn fills the cache again as you install packages."),
        Spec(id: "bun", title: "Bun cache", paths: [".bun/install/cache"], safety: .safe,
             reason: "Packages Bun downloaded before.",
             cost: "Packages are re-downloaded the next time a project installs them",
             afterCleaning: "Bun fills the cache again as you install packages."),
        Spec(id: "pip", title: "pip cache", paths: ["Library/Caches/pip"], safety: .safe,
             reason: "Python wheels pip downloaded or built before.",
             cost: "Packages are re-downloaded the next time you install them",
             afterCleaning: "pip fills the cache again as you install packages."),
        Spec(id: "swiftpm", title: "Swift Package Manager cache", paths: ["Library/Caches/org.swift.swiftpm"], safety: .safe,
             reason: "Git clones of Swift packages that Xcode and SwiftPM fetched.",
             cost: "Packages are fetched again on the next package resolve",
             afterCleaning: "Xcode or SwiftPM clones packages again when a project resolves them."),
        Spec(id: "cocoapods", title: "CocoaPods cache", paths: ["Library/Caches/CocoaPods"], safety: .safe,
             reason: "Pod downloads CocoaPods keeps to speed up pod install.",
             cost: "Pods are re-downloaded on the next pod install",
             afterCleaning: "pod install fills the cache again."),
        Spec(id: "homebrew", title: "Homebrew downloads", paths: ["Library/Caches/Homebrew"], safety: .safe,
             reason: "Bottles and installers Homebrew already installed.",
             cost: "Re-downloaded only if you reinstall something",
             afterCleaning: "Homebrew downloads again when it needs a file."),
        Spec(id: "node-gyp", title: "node-gyp headers", paths: ["Library/Caches/node-gyp"], safety: .safe,
             reason: "Node.js headers used to compile native npm modules.",
             cost: "Re-downloaded the next time a native module builds",
             afterCleaning: "Downloaded again when needed."),
        Spec(id: "go", title: "Go build cache", paths: ["Library/Caches/go-build"], safety: .safe,
             reason: "Compiled Go packages reused between builds.",
             cost: "The next Go build is slower",
             afterCleaning: "Go rebuilds the cache as you compile."),
        Spec(id: "cargo", title: "Cargo downloads", paths: [".cargo/registry/cache"], safety: .safe,
             reason: "Crate archives Cargo downloaded before.",
             cost: "Crates are re-downloaded the next time a project builds",
             afterCleaning: "Cargo downloads crates again when needed."),
        Spec(id: "maven", title: "Maven repository", paths: [".m2/repository"], safety: .review,
             reason: "Libraries Maven (and Gradle builds that use mavenLocal) downloaded or installed locally.",
             cost: "{size} re-download; artifacts you installed locally with mvn install must be rebuilt",
             afterCleaning: "Maven downloads what each build needs again."),
        Spec(id: "playwright", title: "Playwright browsers", paths: ["Library/Caches/ms-playwright", "Library/Caches/ms-playwright-go"], safety: .review,
             reason: "Chromium, Firefox and WebKit builds Playwright downloaded for tests.",
             cost: "{size} re-download before your browser tests can run again",
             afterCleaning: "Run `npx playwright install` to download the browsers again."),
    ]

    public func probes(in context: ScanContext) -> [ItemProbe] {
        let projects = context.allProjects()
        var probes: [ItemProbe] = Self.specs.map { spec in
            .one {
                let urls = spec.paths.map(context.path)
                return CleanupItem.folders(
                    id: "packages.\(spec.id)",
                    title: spec.title,
                    detail: urls.filter(FileInfo.exists).map { PathFormat.abbreviated($0, home: context.home) }.joined(separator: ", "),
                    urls: urls,
                    safety: spec.safety,
                    reason: spec.reason,
                    cost: spec.cost,
                    costLevel: .redownload,
                    afterCleaning: spec.afterCleaning
                )
            }
        }
        let flutterCount = ProjectFacts.flutterProjects(in: projects).count
        probes.append(.one { CleanupItem.folders(
            id: "packages.pub",
            title: "Dart and Flutter packages",
            detail: "~/.pub-cache/hosted",
            urls: [context.path(".pub-cache/hosted")],
            safety: .review,
            reason: flutterCount > 0
                ? "Packages for your \(ProjectFacts.count(flutterCount, "Flutter project")), shared between them."
                : "Dart and Flutter packages downloaded by pub.",
            cost: "{size} re-download on the next flutter pub get, which can take a while",
            costLevel: .redownload,
            afterCleaning: "flutter pub get downloads what each project needs again."
        ) })
        probes += cocoaPodsSpecRepos(context, projects: projects)
        return probes
    }

    /// The old full git clone of github.com/CocoaPods/Specs. CocoaPods uses its CDN since 1.8.
    /// Private spec repos are left alone.
    func cocoaPodsSpecRepos(_ context: ScanContext, projects: [URL]) -> [ItemProbe] {
        let podfiles = ProjectFacts.podfilesUsingSpecsRepo(in: projects)
        return FileInfo.subdirectories(of: context.path(".cocoapods/repos")).compactMap { repo in
            guard let config = try? String(contentsOf: repo.appendingPathComponent(".git/config"), encoding: .utf8),
                  config.contains("CocoaPods/Specs")
            else { return nil }
            return .one { CleanupItem.folders(
                id: "packages.cocoapods-specs:\(repo.lastPathComponent)",
                title: "CocoaPods specs (legacy git copy)",
                detail: podfiles.isEmpty ? "No Podfile of yours uses it" : "\(ProjectFacts.count(podfiles.count, "Podfile")) still use it",
                urls: [repo],
                safety: .review,
                reason: podfiles.isEmpty
                    ? "Full git copy of the CocoaPods specs. None of your Podfiles use it; CocoaPods uses its CDN since 1.8."
                    : "Full git copy of the CocoaPods specs. \(ProjectFacts.count(podfiles.count, "Podfile")) in your projects still point at it.",
                cost: podfiles.isEmpty
                    ? "Re-cloned ({size}, slow) only if a Podfile asks for it"
                    : "The next pod install in those projects re-clones it ({size}, slow)",
                costLevel: .redownload,
                afterCleaning: "Podfiles without a git `source` line keep working through the CDN."
            ) }
        }
    }
}
