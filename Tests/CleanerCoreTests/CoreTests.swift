import Foundation
import Testing
@testable import CleanerCore

@Suite struct FormattingTests {
    @Test(arguments: [
        (Int64(0), "0 KB"),
        (Int64(512_000_000), "512 MB"),
        (Int64(999_600_000), "1.0 GB"),
        (Int64(9_400_000_000), "9.4 GB"),
        (Int64(11_035_521_024), "11 GB"),
        (Int64(494_384_795_648), "494 GB"),
        (Int64(1_200_000_000_000), "1.2 TB"),
    ])
    func shortFormat(bytes: Int64, expected: String) {
        #expect(ByteFormat.short(bytes) == expected)
    }

    @Test func abbreviatesHome() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(PathFormat.abbreviated(URL(fileURLWithPath: "/Users/me/Documents/x"), home: home) == "~/Documents/x")
        #expect(PathFormat.abbreviated(URL(fileURLWithPath: "/opt/x"), home: home) == "/opt/x")
    }
}

@Suite struct VersionTests {
    @Test func comparesNumerically() {
        #expect(Version.isOrderedBefore("8.9", "8.13"))
        #expect(Version.isOrderedBefore("2026.1.4", "2026.2.1"))
        #expect(!Version.isOrderedBefore("27.2", "27.0"))
        #expect(Version.isOrderedBefore("27", "27.0.1"))
    }
}

@Suite struct DirectorySizeTests {
    @Test func countsFilesInTree() throws {
        let home = try TestHome()
        try home.file("a/one.bin", bytes: 100_000)
        try home.file("a/b/two.bin", bytes: 200_000)
        let size = DirectorySize.allocatedSize(of: home.path("a"))
        #expect(size >= 300_000)
        #expect(size < 400_000)
    }

    @Test func countsHardLinksOnce() throws {
        let home = try TestHome()
        let original = try home.file("a/one.bin", bytes: 500_000)
        try FileManager.default.linkItem(at: original, to: home.path("a/link.bin"))
        let size = DirectorySize.allocatedSize(of: home.path("a"))
        #expect(size < 600_000)
    }

    @Test func missingPathIsZero() {
        #expect(DirectorySize.allocatedSize(of: URL(fileURLWithPath: "/nope/\(UUID())")) == 0)
    }
}

@Suite struct ProjectDiscoveryTests {
    @Test func findsProjectsAndRemembersTheirLocations() throws {
        let home = try TestHome()
        try home.file("Documents/projects/auto1/android-app/settings.gradle.kts")
        try home.file("Documents/projects/web-tool/package.json")
        try home.file("AndroidStudioProjects/vivecars/build.gradle")
        try home.file("solo/Package.swift")
        try home.file("Library/Whatever/package.json")         // Library is skipped
        try home.file(".hidden/thing/package.json")             // hidden folders are skipped
        try home.file("Documents/notes/readme.txt")             // not a project

        let projects = ProjectDiscovery.findProjects(in: [home.url], maxDepth: 6, rootsCanBeProjects: false)
        let names = Set(projects.map(\.lastPathComponent))
        #expect(names == ["android-app", "web-tool", "vivecars", "solo"])

        let locations = ProjectDiscovery.locations(for: projects, home: home.url).map {
            PathFormat.abbreviated($0, home: home.url)
        }
        #expect(locations == ["~/AndroidStudioProjects", "~/Documents/projects", "~/solo"])
    }

    @Test func stopsAtProjectRoot() throws {
        let home = try TestHome()
        try home.file("code/mono/package.json")
        try home.file("code/mono/packages/inner/package.json")
        let projects = ProjectDiscovery.findProjects(in: [home.path("code")], maxDepth: 5)
        #expect(projects.map(\.lastPathComponent) == ["mono"])
    }

    @Test func skipsFlutterSDK() throws {
        let home = try TestHome()
        try home.file("flutter/bin/flutter")
        try home.file("flutter/packages/flutter/pubspec.yaml")
        try home.file("apps/real/pubspec.yaml")
        let projects = ProjectDiscovery.findProjects(in: [home.url], maxDepth: 6, rootsCanBeProjects: false)
        #expect(projects.map(\.lastPathComponent) == ["real"])
    }

    @Test func collapsesNestedLocations() {
        let collapsed = ProjectDiscovery.collapse(["/a/b/c", "/a/b", "/x", "/a/bc", "/a/b"])
        #expect(collapsed == ["/a/b", "/a/bc", "/x"])
    }
}

@Suite struct ProjectArtifactTests {
    @Test func findsOnlyRealBuildOutputs() throws {
        let home = try TestHome()
        let root = "p"
        try home.file("\(root)/settings.gradle")
        try home.file("\(root)/build/out.bin")
        try home.file("\(root)/.gradle/state.bin")
        try home.file("\(root)/app/build.gradle.kts")
        try home.file("\(root)/app/build/intermediates/x.bin")
        try home.file("\(root)/docs/build/keep-me.md")            // no build file next to it
        try home.file("\(root)/web/package.json")
        try home.file("\(root)/web/node_modules/a/package.json")
        try home.file("\(root)/web/node_modules/a/node_modules/b/package.json")
        try home.file("\(root)/.git/objects/blob")

        // Relative to the project; compare components since temp paths may be reported via /private/var or /var.
        let artifacts = ProjectArtifacts.findArtifacts(in: home.path(root)).map {
            $0.pathComponents.drop { $0 != root }.dropFirst().joined(separator: "/")
        }
        #expect(Set(artifacts) == ["build", ".gradle", "app/build", "web/node_modules"])
    }

    @Test func projectsScannerMakesOneItemPerProject() throws {
        let home = try TestHome()
        try home.file("dev/one/package.json")
        try home.file("dev/one/node_modules/x.js", bytes: 2_000_000)
        try home.file("dev/two/package.json")                     // nothing to clean

        let context = ScanContext(home: home.url, projectLocations: [home.path("dev")], runsSystemCommands: false)
        let category = ScanEngine.scan(ProjectsScanner(), context: context)
        #expect(category.items.map(\.title) == ["one"])
        #expect(category.items.first?.safety == .safe)
    }
}

@Suite struct XcodeTests {
    @Test func parsesDeviceSupportFolders() {
        let entry = XcodeScanner.DeviceSupportEntry.parse(folderName: "iPhone15,2 27.0 (24A5380h)", platform: "iOS")
        #expect(entry?.model == "iPhone15,2")
        #expect(entry?.version == "27.0")
        #expect(entry?.build == "24A5380h")
        #expect(entry?.isBeta == true)

        let old = XcodeScanner.DeviceSupportEntry.parse(folderName: "17.0 (21A329) arm64e", platform: "iOS")
        #expect(old?.model == nil)
        #expect(old?.version == "17.0")
        #expect(old?.isBeta == false)
    }

    @Test func keepsNewestPerDevice() {
        let names = [
            "iPad15,5 27.0 (24A5370h)", "iPad15,5 27.0 (24A5424a)", "iPhone17,3 26.5 (23F77)",
            "iPhone17,3 27.2 (24B5089g)", "iPhone15,2 27.0 (24A5380h)",
        ]
        let entries = names.compactMap { XcodeScanner.DeviceSupportEntry.parse(folderName: $0, platform: "iOS") }
        #expect(XcodeScanner.newestPerDevice(entries) == [
            "iPad15,5 27.0 (24A5424a)", "iPhone17,3 27.2 (24B5089g)", "iPhone15,2 27.0 (24A5380h)",
        ])
    }

    @Test func namesDerivedDataFolders() {
        #expect(XcodeScanner.projectName(fromDerivedDataFolder: "Auto1-bzdndobdkrngxicisfqqxbehazjk") == "Auto1")
        #expect(XcodeScanner.projectName(fromDerivedDataFolder: "My-App") == "My-App")
    }

    @Test func scansDerivedDataWithWorkspaceNames() throws {
        let home = try TestHome()
        let dd = "Library/Developer/Xcode/DerivedData"
        try home.file("\(dd)/Auto1-bzdndobdkrngxicisfqqxbehazjk/Build/x.o", bytes: 2_000_000)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/gone/Auto1.xcworkspace"], format: .xml, options: 0)
        try plist.write(to: home.path("\(dd)/Auto1-bzdndobdkrngxicisfqqxbehazjk/info.plist"))
        try home.file("\(dd)/ModuleCache.noindex/m.pcm", bytes: 2_000_000)

        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false)
        let titles = ScanEngine.scan(XcodeScanner(), context: context).items.map(\.title)
        #expect(Set(titles) == ["Auto1 build data", "Shared module caches"])
    }

    @Test func parsesSimulatorJSON() {
        let json = """
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
          {"udid": "A", "name": "iPhone 17", "isAvailable": false},
          {"udid": "B", "name": "iPhone 17e", "isAvailable": true}
        ]}}
        """
        let devices = SimulatorDevices.parse(json: Data(json.utf8))
        #expect(devices.count == 2)
        #expect(devices.filter { !$0.isAvailable }.map(\.udid) == ["A"])

        let runtimes = SimulatorRuntime.parse(json: Data("""
        {"X": {"identifier": "X", "version": "18.6", "sizeBytes": 8838255185, "deletable": true,
               "platformIdentifier": "com.apple.platform.iphonesimulator",
               "runtimeIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-18-6"}}
        """.utf8))
        #expect(runtimes.first?.platformName == "iOS")
        #expect(runtimes.first?.sizeBytes == 8_838_255_185)
    }
}

@Suite struct IDETests {
    @Test func parsesDataFolderNames() {
        #expect(IDEScanner.IDEDataFolder.parse("AndroidStudio2026.1.3") == .init(product: "AndroidStudio", version: "2026.1.3"))
        #expect(IDEScanner.IDEDataFolder.parse("IntelliJIdea2026.1") == .init(product: "IntelliJIdea", version: "2026.1"))
        #expect(IDEScanner.IDEDataFolder.parse("Toolbox") == nil)
    }

    @Test func oldVersionsAreTheOnesNotInstalled() {
        let found: Set<IDEScanner.IDEDataFolder> = [
            .init(product: "AndroidStudio", version: "2026.1.3"),
            .init(product: "AndroidStudio", version: "2026.1.4"),
            .init(product: "AndroidStudio", version: "2026.2.1"),
            .init(product: "WebStorm", version: "2025.3"),
            .init(product: "WebStorm", version: "2026.1"),
        ]
        let old = IDEScanner.oldVersions(found: found, installed: ["AndroidStudio2026.2.1"])
        // Installed Android Studio is current; WebStorm isn't installed, so only its newest is kept.
        #expect(Set(old.keys.map(\.name)) == ["AndroidStudio2026.1.3", "AndroidStudio2026.1.4", "WebStorm2025.3"])
        #expect(old[.init(product: "AndroidStudio", version: "2026.1.3")] == "2026.2.1")
    }
}

@Suite struct AndroidTests {
    @Test func readsWrapperVersions() {
        #expect(AndroidScanner.wrapperVersion(fromDistribution: "gradle-8.13-bin") == "8.13")
        #expect(AndroidScanner.wrapperVersion(fromDistribution: "gradle-9.0-rc-1-all") == "9.0-rc-1")
    }

    @Test func scansGradleCaches() throws {
        let home = try TestHome()
        try home.file(".gradle/caches/build-cache-1/a", bytes: 2_000_000)
        try home.file(".gradle/caches/modules-2/files-2.1/lib.jar", bytes: 2_000_000)
        try home.file(".gradle/caches/7.6/kotlin-dsl/x", bytes: 2_000_000)
        try home.file(".gradle/caches/8.13/kotlin-dsl/x", bytes: 2_000_000)
        try home.folder(".gradle/wrapper/dists/gradle-8.13-bin/hash")
        try home.file(".gradle/wrapper/dists/gradle-8.13-bin/hash/gradle.zip", bytes: 2_000_000)

        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false)
        let items = ScanEngine.scan(AndroidScanner(), context: context).items
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["gradle.build-cache"]?.safety == .safe)
        #expect(byID["gradle.modules"]?.safety == .review)
        #expect(byID["gradle.version:7.6"]?.detail == "No installed Gradle uses this version")
        #expect(byID["gradle.version:8.13"]?.detail == "Gradle 8.13 is installed")
        #expect(byID["gradle.wrapper:gradle-8.13-bin"]?.detail == "Newest installed, no project uses it")
    }
}

@Suite struct CleanerTests {
    @Test func guardRejectsDangerousPaths() {
        let home = URL(fileURLWithPath: "/Users/me")
        func check(_ path: String) -> PathGuard.Violation? {
            do {
                try PathGuard.validate(URL(fileURLWithPath: path), home: home)
                return nil
            } catch {
                return error as? PathGuard.Violation
            }
        }
        #expect(check("/Users/me") == .outsideHome("/Users/me"))
        #expect(check("/") == .outsideHome("/"))
        #expect(check("/Users/meanwhile/x/y") == .outsideHome("/Users/meanwhile/x/y"))
        #expect(check("/Users/me/Documents") == .tooShallow("/Users/me/Documents"))
        #expect(check("/Users/me/Library/Caches") == .protected("/Users/me/Library/Caches"))
        #expect(check("/Users/me/Library/Developer/Xcode/DerivedData/../../..") == .tooShallow("/Users/me/Library"))
        #expect(check("/Users/me/Library/Developer/Xcode/DerivedData/App-abc") == nil)
        #expect(check("/Users/me/.npm/_cacache") == nil)
    }

    @Test func removesOnlyTheItemsPaths() throws {
        let home = try TestHome()
        try home.file("dev/p/package.json")
        try home.file("dev/p/node_modules/x.js")
        try home.file("dev/p/src/index.js")
        let item = CleanupItem(
            id: "t", title: "t", size: 1, safety: .safe,
            action: .removePaths([home.path("dev/p/node_modules")])
        )
        let outcome = Cleaner(home: home.url).clean(item)
        #expect(outcome.succeeded)
        #expect(!home.exists("dev/p/node_modules"))
        #expect(home.exists("dev/p/src/index.js"))
        #expect(home.exists("dev/p/package.json"))
    }

    @Test func refusesWholeItemIfAnyPathIsUnsafe() throws {
        let home = try TestHome()
        try home.file("dev/p/node_modules/x.js")
        let item = CleanupItem(
            id: "t", title: "t", size: 1, safety: .safe,
            action: .removePaths([home.path("dev/p/node_modules"), home.path("Documents")])
        )
        let outcome = Cleaner(home: home.url).clean(item)
        #expect(!outcome.succeeded)
        #expect(home.exists("dev/p/node_modules/x.js"))
    }
}

@Suite struct SettingsTests {
    @Test func roundTripsAndToleratesMissingFields() throws {
        let home = try TestHome()
        let store = SettingsStore(fileURL: home.path("settings.json"))
        #expect(store.load() == AppSettings())

        var settings = AppSettings()
        settings.projectLocations = ["/a", "/b"]
        settings.lowSpaceThresholdGB = 30
        try store.save(settings)
        #expect(store.load() == settings)

        try home.file("old.json", contents: #"{"projectLocations": ["/x"]}"#)
        let old = SettingsStore(fileURL: home.path("old.json")).load()
        #expect(old.projectLocations == ["/x"])
        #expect(old.lowSpaceThresholdGB == 20)
    }
}
