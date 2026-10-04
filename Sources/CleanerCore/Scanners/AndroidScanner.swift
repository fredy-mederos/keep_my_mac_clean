import Foundation

/// Gradle caches, Android SDK leftovers and emulators.
public struct AndroidScanner: CleanupScanner {
    public let categoryID = "android"
    public let title = "Android and Gradle"
    public let symbol = "wrench.and.screwdriver"

    public init() {}

    public func probes(in context: ScanContext) -> [ItemProbe] {
        let projects = context.allProjects()
        return gradle(context, projects: projects) + androidHome(context) + sdk(context, projects: projects)
    }

    // MARK: Gradle

    static let gradleBlockers: [Blocker] = [.gradleDaemon, .androidStudio]

    /// "gradle-8.13-bin" → "8.13".
    static func wrapperVersion(fromDistribution name: String) -> String? {
        name.wholeMatch(of: /gradle-(.+)-(?:bin|all)/).map { String($0.1) }
    }

    func gradle(_ context: ScanContext, projects: [URL]) -> [ItemProbe] {
        let gradleHome = context.path(".gradle")
        let caches = gradleHome.appendingPathComponent("caches")
        let distributions = FileInfo.subdirectories(of: gradleHome.appendingPathComponent("wrapper/dists"))
        let wrapperVersions = Set(distributions.compactMap { Self.wrapperVersion(fromDistribution: $0.lastPathComponent) })
        let gradleProjectCount = ProjectFacts.gradleRoots(in: projects).count
        let wrapperUsage = ProjectFacts.wrapperUsage(in: projects)

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
                    reason: gradleProjectCount > 0
                        ? "Every library downloaded for your \(ProjectFacts.count(gradleProjectCount, "Gradle project"))."
                        : "Libraries Gradle downloaded for past builds.",
                    cost: "{size} re-download on the next build (needs network, can take several minutes)",
                    costLevel: .redownload,
                    afterCleaning: "Each project downloads the libraries it needs on its next build.",
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
                    reason: inUse
                        ? "Generated scripts and file hashes for Gradle \(name)."
                        : "Generated files for Gradle \(name), which no installed wrapper uses anymore.",
                    cost: inUse ? "Next build regenerates them" : "Nothing: no installed Gradle uses them",
                    costLevel: inUse ? .rebuild : nil,
                    afterCleaning: "Recreated the next time a build runs on Gradle \(name).",
                    blockers: Self.gradleBlockers
                ) })
            }
        }

        probes.append(.one { [buildCaches] in CleanupItem.folders(
            id: "gradle.build-cache", title: "Gradle build cache", detail: "~/.gradle/caches",
            urls: buildCaches, safety: .safe,
            reason: "Task outputs Gradle reuses between builds and branches.",
            cost: "The next build of each project is slower",
            costLevel: .rebuild,
            afterCleaning: "Gradle fills it again as you build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { [transforms] in CleanupItem.folders(
            id: "gradle.transforms", title: "Gradle transforms cache", detail: "~/.gradle/caches",
            urls: transforms, safety: .safe,
            reason: "Processed copies of dependencies (dexed, desugared, jetified).",
            cost: "The next build reprocesses dependencies",
            costLevel: .rebuild,
            afterCleaning: "Recreated on the next build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { [other] in CleanupItem.folders(
            id: "gradle.other", title: "Other Gradle caches", detail: "jars, Kotlin DSL",
            urls: other, safety: .safe,
            reason: "Compiled build scripts and generated jars.",
            cost: "The next build recompiles build scripts",
            costLevel: .rebuild,
            afterCleaning: "Recreated on the next build.",
            revealURL: caches, blockers: Self.gradleBlockers
        ) })
        probes.append(.one { CleanupItem.folders(
            id: "gradle.daemon", title: "Gradle daemon logs", detail: "~/.gradle/daemon",
            urls: [gradleHome.appendingPathComponent("daemon")], safety: .safe,
            reason: "Log files from past Gradle daemons.",
            cost: "Nothing: they're only old logs",
            costLevel: nil,
            blockers: [.gradleDaemon]
        ) })

        let newestWrapper = wrapperVersions.max(by: Version.isOrderedBefore)
        for dist in distributions {
            let version = Self.wrapperVersion(fromDistribution: dist.lastPathComponent) ?? dist.lastPathComponent
            let users = wrapperUsage[version] ?? 0
            probes.append(.one { CleanupItem.folders(
                id: "gradle.wrapper:\(dist.lastPathComponent)",
                title: "Gradle \(version) distribution",
                detail: users > 0
                    ? "Used by \(ProjectFacts.count(users, "project"))"
                    : (version == newestWrapper ? "Newest installed, no project uses it" : "No project uses it"),
                urls: [dist],
                safety: .review,
                reason: users > 0
                    ? "Gradle \(version) is used by \(ProjectFacts.count(users, "project")) in your folders."
                    : "No project in your folders uses Gradle \(version).",
                cost: users > 0 ? "{size} re-download the next time you build those projects" : "{size} re-download only if a project needs it",
                costLevel: .redownload,
                afterCleaning: "./gradlew downloads this version again when a project asks for it.",
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
            reason: "SDK metadata the Android tools downloaded.",
            cost: "A small re-download the next time the SDK Manager runs",
            costLevel: .redownload,
            afterCleaning: "Recreated when needed."
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
                reason: "The \(displayName) emulator with the apps, data and snapshots inside it.",
                cost: "Its installed apps, data and snapshots are gone for good",
                costLevel: .dataLoss,
                afterCleaning: "You can create a fresh emulator in Android Studio → Device Manager.",
                revealURL: avd,
                blockers: [.androidEmulator],
                lastUsed: FileInfo.modificationDate(avd)
            ) })
        }
        return probes
    }

    /// One review item with every version except the newest. Folder names like "35.0.1" or "android-36".
    static func olderVersionsProbe(
        in folder: URL,
        label: String,
        reason: @escaping @Sendable (_ older: [String], _ newest: String) -> String,
        cost: String,
        afterCleaning: String
    ) -> ItemProbe? {
        let versions = FileInfo.subdirectories(of: folder).sorted { Version.isOrderedBefore(sdkVersion($0), sdkVersion($1)) }
        guard let newest = versions.last, versions.count > 1 else { return nil }
        let older = Array(versions.dropLast())
        let olderNames = older.map(sdkVersion)
        let newestName = sdkVersion(newest)
        return .one { CleanupItem.folders(
            id: "android.\(folder.lastPathComponent).older",
            title: "Older \(label) (\(older.count) version\(older.count == 1 ? "" : "s"))",
            detail: "\(olderNames.joined(separator: ", ")) · keeps \(newestName)",
            urls: older,
            safety: .review,
            reason: reason(olderNames, newestName),
            cost: cost,
            costLevel: .redownload,
            afterCleaning: afterCleaning,
            revealURL: folder,
            blockers: [.androidStudio, .gradleDaemon]
        ) }
    }

    /// "android-36" → "36", "35.0.1" → "35.0.1".
    static func sdkVersion(_ url: URL) -> String {
        url.lastPathComponent.replacingOccurrences(of: "android-", with: "")
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

    func sdk(_ context: ScanContext, projects: [URL]) -> [ItemProbe] {
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
                        reason: used
                            ? "Android system image an emulator boots from."
                            : "Android system image that none of your emulators use.",
                        cost: used
                            ? "{size} re-download, and the emulator using it won't start until then"
                            : "{size} re-download if you create an emulator with it",
                        costLevel: .redownload,
                        afterCleaning: "Reinstall it from Android Studio → SDK Manager.",
                        blockers: [.androidEmulator, .androidStudio]
                    ) })
                }
            }
        }

        // NDKs are big, so one item per version.
        let ndks = FileInfo.subdirectories(of: sdk.appendingPathComponent("ndk"))
        let newestNDK = ndks.map(\.lastPathComponent).max(by: Version.isOrderedBefore)
        for ndk in ndks where ndk.lastPathComponent != newestNDK {
            probes.append(.one { CleanupItem.folders(
                id: "android.ndk:\(ndk.lastPathComponent)",
                title: "NDK \(ndk.lastPathComponent)",
                detail: "Newer NDK installed: \(newestNDK ?? "")",
                urls: [ndk],
                safety: .review,
                reason: "NDK \(ndk.lastPathComponent); NDK \(newestNDK ?? "") is also installed.",
                cost: "{size} re-download if a project pins this NDK version",
                costLevel: .redownload,
                afterCleaning: "Gradle or the SDK Manager installs it again when a project asks for it.",
                blockers: [.androidStudio, .gradleDaemon]
            ) })
        }

        // Small per version, so older versions are grouped into one item each.
        let compileLevels = ProjectFacts.compileSdkLevels(in: projects).sorted()
        if let probe = Self.olderVersionsProbe(
            in: sdk.appendingPathComponent("platforms"),
            label: "SDK platforms",
            reason: { older, newest in
                let inUse = older.filter { version in compileLevels.contains { String($0) == version } }
                if compileLevels.isEmpty {
                    return "SDK platforms older than API \(newest)."
                }
                if inUse.isEmpty {
                    return "None of your projects compile against these older API levels."
                }
                if inUse.count == older.count {
                    return "Your projects still compile against all of these API levels."
                }
                return "Your projects still compile against \(inUse.count) of these \(older.count) API levels (\(inUse.joined(separator: ", ")))."
            },
            cost: "{size} re-download; a project compiling against one of these downloads it on its next build",
            afterCleaning: "The Android Gradle plugin or the SDK Manager downloads a platform again when a project needs it."
        ) { probes.append(probe) }
        if let probe = Self.olderVersionsProbe(
            in: sdk.appendingPathComponent("build-tools"),
            label: "build tools",
            reason: { older, newest in "\(older.count) build tools versions older than \(newest), the one recent Android Gradle plugins use." },
            cost: "Re-downloaded automatically if a project asks for one",
            afterCleaning: "The Android Gradle plugin downloads a specific version again if a project asks for it."
        ) { probes.append(probe) }
        if let probe = Self.olderVersionsProbe(
            in: sdk.appendingPathComponent("sources"),
            label: "SDK sources",
            reason: { older, _ in "Android source code for API \(older.joined(separator: ", ")), only used to browse framework code in the IDE." },
            cost: "{size} re-download to browse those sources again",
            afterCleaning: "Download them again from the SDK Manager."
        ) { probes.append(probe) }
        return probes
    }
}
