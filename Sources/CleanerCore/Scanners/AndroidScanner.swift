import Foundation

/// Gradle caches, Android SDK leftovers and emulators.
public struct AndroidScanner: CleanupScanner {
    public let categoryID = "android"
    public let title = "Android and Gradle"
    public let symbol = "wrench.and.screwdriver"

    public init() {}

    public func probes(in context: ScanContext) -> [ItemProbe] {
        gradle(context) + androidHome(context) + sdk(context)
    }

    // MARK: Gradle

    static let gradleBlockers: [Blocker] = [.gradleDaemon, .androidStudio]

    /// "gradle-8.13-bin" → "8.13".
    static func wrapperVersion(fromDistribution name: String) -> String? {
        name.wholeMatch(of: /gradle-(.+)-(?:bin|all)/).map { String($0.1) }
    }

    func gradle(_ context: ScanContext) -> [ItemProbe] {
        let gradleHome = context.path(".gradle")
        let caches = gradleHome.appendingPathComponent("caches")
        let distributions = FileInfo.subdirectories(of: gradleHome.appendingPathComponent("wrapper/dists"))
        let wrapperVersions = Set(distributions.compactMap { Self.wrapperVersion(fromDistribution: $0.lastPathComponent) })

        var probes: [ItemProbe] = []
        var buildCaches: [URL] = []
        var transforms: [URL] = []
        var other: [URL] = []

        for dir in FileInfo.subdirectories(of: caches) {
            let name = dir.lastPathComponent
            if name.hasPrefix("build-cache") {
                buildCaches.append(dir)
            } else if name.hasPrefix("transforms") {
                transforms.append(dir)
            } else if name.hasPrefix("jars-") || name == "kotlin-dsl" {
                other.append(dir)
            } else if name == "modules-2" {
                probes.append(.one { CleanupItem.folders(
                    id: "gradle.modules",
                    title: "Downloaded Gradle dependencies",
                    detail: "~/.gradle/caches/modules-2",
                    urls: [dir],
                    safety: .review,
                    note: "Every library your projects use. Gradle downloads them again on the next build, which can take a while.",
                    blockers: Self.gradleBlockers
                ) })
            } else if name.first?.isNumber == true {
                let inUse = wrapperVersions.contains(name)
                probes.append(.one { CleanupItem.folders(
                    id: "gradle.version:\(name)",
                    title: "Gradle \(name) caches",
                    detail: inUse ? "Gradle \(name) is installed" : "No installed Gradle uses this version",
                    urls: [dir],
                    safety: .safe,
                    note: "Generated scripts and file hashes for this Gradle version. Recreated on the next build.",
                    blockers: Self.gradleBlockers
                ) })
            }
        }

        probes.append(.one { [buildCaches] in CleanupItem.folders(
            id: "gradle.build-cache", title: "Gradle build cache", detail: "~/.gradle/caches",
            urls: buildCaches, safety: .safe,
            note: "Reusable task outputs. Gradle fills it again as you build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { [transforms] in CleanupItem.folders(
            id: "gradle.transforms", title: "Gradle transforms cache", detail: "~/.gradle/caches",
            urls: transforms, safety: .safe,
            note: "Processed copies of dependencies (dexed, jetified...). Recreated on the next build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { [other] in CleanupItem.folders(
            id: "gradle.other", title: "Other Gradle caches", detail: "jars, Kotlin DSL",
            urls: other, safety: .safe,
            note: "Recreated on the next build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { CleanupItem.folders(
            id: "gradle.daemon", title: "Gradle daemon logs", detail: "~/.gradle/daemon",
            urls: [gradleHome.appendingPathComponent("daemon")], safety: .safe,
            note: "Log files from past Gradle daemons.",
            blockers: [.gradleDaemon]
        ) })

        let newestWrapper = wrapperVersions.max(by: Version.isOrderedBefore)
        for dist in distributions {
            let version = Self.wrapperVersion(fromDistribution: dist.lastPathComponent) ?? dist.lastPathComponent
            probes.append(.one { CleanupItem.folders(
                id: "gradle.wrapper:\(dist.lastPathComponent)",
                title: "Gradle \(version) distribution",
                detail: version == newestWrapper ? "Newest installed" : "A newer Gradle is installed",
                urls: [dist],
                safety: .review,
                note: "./gradlew downloads it again if a project still uses this version.",
                blockers: Self.gradleBlockers,
                lastUsed: FileInfo.modificationDate(dist)
            ) })
        }
        return probes
    }

    // MARK: ~/.android

    func androidHome(_ context: ScanContext) -> [ItemProbe] {
        var probes: [ItemProbe] = [.one { CleanupItem.folders(
            id: "android.cache", title: "Android tools cache", detail: "~/.android/cache",
            urls: [context.path(".android/cache")], safety: .safe,
            note: "Downloaded SDK metadata. Recreated when needed."
        ) }]

        let avdRoot = context.path(".android/avd")
        for avd in FileInfo.subdirectories(of: avdRoot) where avd.pathExtension == "avd" {
            let name = avd.deletingPathExtension().lastPathComponent
            let config = avd.appendingPathComponent("config.ini")
            let displayName = Self.iniValue("avd.ini.displayname", in: config) ?? name.replacingOccurrences(of: "_", with: " ")
            probes.append(.one { CleanupItem.folders(
                id: "android.avd:\(name)",
                title: "Emulator: \(displayName)",
                detail: Self.iniValue("image.sysdir.1", in: config),
                urls: [avd, avdRoot.appendingPathComponent("\(name).ini")],
                safety: .review,
                note: "Deletes this virtual device and its data. You can create it again in Device Manager.",
                revealURL: avd,
                blockers: [.androidEmulator],
                lastUsed: FileInfo.modificationDate(avd)
            ) })
        }
        return probes
    }

    static func iniValue(_ key: String, in file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == key { return parts[1] }
        }
        return nil
    }

    // MARK: Android SDK

    func sdk(_ context: ScanContext) -> [ItemProbe] {
        let sdk = context.path("Library/Android/sdk")
        var probes: [ItemProbe] = []

        // System images used by an emulator are marked so they're easy to keep.
        let usedImages = Set(FileInfo.subdirectories(of: context.path(".android/avd")).compactMap {
            Self.iniValue("image.sysdir.1", in: $0.appendingPathComponent("config.ini"))?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        })
        for api in FileInfo.subdirectories(of: sdk.appendingPathComponent("system-images")) {
            for tag in FileInfo.subdirectories(of: api) {
                for abi in FileInfo.subdirectories(of: tag) {
                    let relative = "system-images/\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                    let used = usedImages.contains(relative)
                    probes.append(.one { CleanupItem.folders(
                        id: "android.sysimage:\(relative)",
                        title: "System image \(api.lastPathComponent) (\(tag.lastPathComponent))",
                        detail: used ? "Used by an emulator" : "No emulator uses it",
                        urls: [abi],
                        safety: .review,
                        note: "Reinstall from Android Studio → SDK Manager if you need it again.",
                        blockers: [.androidEmulator, .androidStudio]
                    ) })
                }
            }
        }

        // NDKs are big, so one item per version. Build tools are small, so older versions are grouped.
        let ndks = FileInfo.subdirectories(of: sdk.appendingPathComponent("ndk"))
        let newestNDK = ndks.map(\.lastPathComponent).max(by: Version.isOrderedBefore)
        for ndk in ndks where ndk.lastPathComponent != newestNDK {
            probes.append(.one { CleanupItem.folders(
                id: "android.ndk:\(ndk.lastPathComponent)",
                title: "NDK \(ndk.lastPathComponent)",
                detail: "Newer NDK installed: \(newestNDK ?? "")",
                urls: [ndk],
                safety: .review,
                note: "Projects pinned to this version will ask to reinstall it from the SDK Manager.",
                blockers: [.androidStudio, .gradleDaemon]
            ) })
        }

        let buildTools = FileInfo.subdirectories(of: sdk.appendingPathComponent("build-tools"))
        let newestBuildTools = buildTools.map(\.lastPathComponent).max(by: Version.isOrderedBefore)
        let olderBuildTools = buildTools
            .filter { $0.lastPathComponent != newestBuildTools }
            .sorted { Version.isOrderedBefore($0.lastPathComponent, $1.lastPathComponent) }
        if !olderBuildTools.isEmpty {
            probes.append(.one { CleanupItem.folders(
                id: "android.build-tools.older",
                title: "Older build tools (\(olderBuildTools.count) versions)",
                detail: "\(olderBuildTools.map(\.lastPathComponent).joined(separator: ", ")) · keeps \(newestBuildTools ?? "")",
                urls: olderBuildTools,
                safety: .review,
                note: "The Android Gradle plugin downloads a specific version again if a project asks for it.",
                revealURL: sdk.appendingPathComponent("build-tools"),
                blockers: [.androidStudio, .gradleDaemon]
            ) })
        }
        return probes
    }
}
