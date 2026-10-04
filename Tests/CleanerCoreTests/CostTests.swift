import Foundation
import Testing
@testable import CleanerCore

@Suite struct ProjectFactsTests {
    @Test func readsWrapperVersionsFromProjects() throws {
        let home = try TestHome()
        try home.file("dev/a/settings.gradle.kts")
        try home.file("dev/a/gradle/wrapper/gradle-wrapper.properties",
                      contents: "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        try home.file("dev/b/build.gradle")
        try home.file("dev/b/gradle/wrapper/gradle-wrapper.properties",
                      contents: "distributionUrl=https\\://services.gradle.org/distributions/gradle-9.0-rc-1-all.zip\n")
        try home.file("dev/flutter_app/pubspec.yaml")
        try home.file("dev/flutter_app/android/settings.gradle")
        try home.file("dev/flutter_app/android/gradle/wrapper/gradle-wrapper.properties",
                      contents: "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-all.zip\n")

        let projects = ["a", "b", "flutter_app"].map { home.path("dev/\($0)") }
        #expect(ProjectFacts.wrapperUsage(in: projects) == ["8.13": 2, "9.0-rc-1": 1])
        #expect(ProjectFacts.gradleRoots(in: projects).count == 3)
        #expect(ProjectFacts.flutterProjects(in: projects).map(\.lastPathComponent) == ["flutter_app"])
    }

    @Test func findsCompileSdkLevels() throws {
        let home = try TestHome()
        try home.file("dev/a/settings.gradle.kts")
        try home.file("dev/a/app/build.gradle.kts", contents: "android {\n    compileSdk = 35\n}\n")
        try home.file("dev/b/settings.gradle")
        try home.file("dev/b/app/build.gradle", contents: "android { compileSdkVersion 34 }\n")
        try home.file("dev/c/settings.gradle.kts")
        try home.file("dev/c/gradle/libs.versions.toml", contents: "[versions]\ncompileSdk = \"36\"\n")
        let projects = ["a", "b", "c"].map { home.path("dev/\($0)") }
        #expect(ProjectFacts.compileSdkLevels(in: projects) == [34, 35, 36])
    }

    @Test func findsPodfilesUsingTheGitSpecsRepo() throws {
        let home = try TestHome()
        try home.file("dev/old/Podfile", contents: "source 'https://github.com/CocoaPods/Specs.git'\npod 'Alamofire'\n")
        try home.file("dev/new/Podfile", contents: "pod 'Alamofire'\n")
        try home.file("dev/flutter/ios/Podfile", contents: "source 'https://github.com/CocoaPods/Specs.git'\n")
        let projects = ["old", "new", "flutter"].map { home.path("dev/\($0)") }
        #expect(Set(ProjectFacts.podfilesUsingSpecsRepo(in: projects).map { $0.deletingLastPathComponent().lastPathComponent }) == ["old", "ios"])
    }
}

@Suite struct CostTextTests {
    /// A fake home with something for most scanners.
    func populatedHome() throws -> TestHome {
        let home = try TestHome()
        try home.file("dev/app/settings.gradle")
        try home.file("dev/app/build/out.bin", bytes: 2_000_000)
        try home.file("dev/app/gradle/wrapper/gradle-wrapper.properties",
                      contents: "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip\n")
        try home.file(".gradle/caches/modules-2/lib.jar", bytes: 2_000_000)
        try home.file(".gradle/wrapper/dists/gradle-8.13-bin/x/gradle.zip", bytes: 2_000_000)
        try home.file(".gradle/wrapper/dists/gradle-7.6-bin/x/gradle.zip", bytes: 2_000_000)
        try home.file(".android/avd/Pixel_8.avd/userdata.img", bytes: 2_000_000)
        try home.file(".android/avd/Pixel_8.avd/config.ini", contents: "avd.ini.displayname=Pixel 8\n")
        try home.file(".cocoapods/repos/cocoapods/.git/config", contents: "url = https://github.com/CocoaPods/Specs.git\n")
        try home.file(".cocoapods/repos/cocoapods/Specs/x.json", bytes: 2_000_000)
        try home.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone15,2 26.5 (23F77)/Symbols/x", bytes: 2_000_000)
        try home.file("Library/Developer/Xcode/iOS DeviceSupport/iPhone17,3 27.2 (24C55)/Symbols/x", bytes: 2_000_000)
        try home.file("Library/Caches/JetBrains/Toolbox/backup/x", bytes: 2_000_000)
        try home.file("Downloads/Installer.dmg", bytes: 11_000_000)
        return home
    }

    func items(in home: TestHome) -> [CleanupItem] {
        let context = ScanContext(home: home.url, projectLocations: [home.path("dev")], runsSystemCommands: false)
        return ScanEngine.scanners.flatMap { ScanEngine.scan($0, context: context).items }
    }

    @Test func everyItemExplainsItselfAndNoPlaceholderLeaks() throws {
        let home = try populatedHome()
        let items = items(in: home)
        #expect(items.count >= 8)
        for item in items {
            #expect(item.reason != nil, "\(item.id) has no reason")
            #expect(item.cost != nil, "\(item.id) has no cost")
            for text in [item.reason, item.cost, item.afterCleaning].compactMap({ $0 }) {
                #expect(!text.contains("{size}"), "\(item.id): \(text)")
            }
            if item.safety == .review {
                #expect(item.costLevel != nil, "\(item.id) is Review without a cost level")
            }
        }
    }

    @Test func usesProjectFactsAndMeasuredSizes() throws {
        let home = try populatedHome()
        let byID = Dictionary(uniqueKeysWithValues: items(in: home).map { ($0.id, $0) })

        let used = try #require(byID["gradle.wrapper:gradle-8.13-bin"])
        #expect(used.reason == "Gradle 8.13 is used by 1 project in your folders.")
        #expect(used.cost == "~2 MB re-download the next time you build those projects")
        #expect(byID["gradle.wrapper:gradle-7.6-bin"]?.reason == "No project in your folders uses Gradle 7.6.")

        #expect(byID["android.avd:Pixel_8"]?.costLevel == .dataLoss)
        #expect(byID["ide.toolbox.backup"]?.costLevel == .loseOption)
        #expect(byID["packages.cocoapods-specs:cocoapods"]?.reason?.contains("None of your Podfiles use it") == true)

        let older = try #require(byID.values.first { $0.title.hasPrefix("iOS 26.5") })
        #expect(older.reason == "Symbols for iOS 26.5 from iPhone15,2. Your newest device runs iOS 27.2.")
        #expect(older.costLevel == .redownload)

        let installer = try #require(byID.values.first { $0.title == "Installer.dmg" })
        #expect(installer.costLevel == nil)
        #expect(installer.cost == "Recoverable from the Trash until you empty it")
    }

    @Test func largeFileSearchNeverEntersPicturesOrMusic() throws {
        let home = try TestHome()
        try home.file("Pictures/huge.mov", bytes: 3_000_000)
        try home.file("Music/huge.wav", bytes: 3_000_000)
        try home.file("Movies/huge.mov", bytes: 3_000_000)
        try home.file("Documents/Pictures/inside-a-project.mov", bytes: 3_000_000)
        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false, largeFileMinimumSize: 2_000_000)
        let paths = LargeFilesScanner().largeFiles(context).map { $0.detail ?? "" }
        #expect(paths.count == 2)
        #expect(paths.allSatisfy { !$0.hasSuffix("~/Pictures") && !$0.hasSuffix("~/Music") })
    }

    @Test func costLevelsAreOrdered() {
        #expect(CostLevel.rebuild < .redownload)
        #expect(CostLevel.loseOption < .dataLoss)
        #expect(CostLevel.allCases.max() == .dataLoss)
    }
}
