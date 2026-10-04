import Foundation
import Testing
@testable import CleanerCore

@Suite struct DockerTests {
    static let systemDF = """
    {"Active":"2","Reclaimable":"1.2GB (45%)","Size":"2.7GB","TotalCount":"5","Type":"Images"}
    {"Active":"1","Reclaimable":"23kB (10%)","Size":"230kB","TotalCount":"3","Type":"Containers"}
    {"Active":"0","Reclaimable":"512.3MB (100%)","Size":"512.3MB","TotalCount":"2","Type":"Local Volumes"}
    {"Active":"0","Reclaimable":"4.1GB","Size":"4.1GB","TotalCount":"80","Type":"Build Cache"}
    """

    @Test(arguments: [
        ("1.2GB (45%)", Int64(1_200_000_000)),
        ("512.3MB", Int64(512_300_000)),
        ("23kB (10%)", Int64(23_000)),
        ("0B", Int64(0)),
        ("garbage", Int64(0)),
    ])
    func parsesDockerSizes(text: String, bytes: Int64) {
        #expect(DockerScanner.bytes(fromDockerSize: text) == bytes)
    }

    @Test func turnsSystemDFIntoItems() {
        let items = DockerScanner.items(fromSystemDF: Self.systemDF, docker: "/usr/local/bin/docker")
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        #expect(byID["docker.build-cache"]?.safety == .safe)
        #expect(byID["docker.build-cache"]?.size == 4_100_000_000)
        #expect(byID["docker.images"]?.detail == "3 of 5 images aren't used by any container")
        #expect(byID["docker.volumes"]?.safety == .review)
        #expect(byID["docker.images"]?.action == .command(executable: "/usr/local/bin/docker", arguments: ["image", "prune", "--all", "--force"]))
    }
}

@Suite struct AndroidSDKTests {
    @Test func groupsOlderPlatformsAndKeepsNewest() throws {
        let home = try TestHome()
        for api in ["android-28", "android-34", "android-36", "android-37.2"] {
            try home.file("Library/Android/sdk/platforms/\(api)/android.jar", bytes: 1_000_000)
        }
        try home.file("Library/Android/sdk/build-tools/37.0.0/aapt", bytes: 1_000_000)   // only one: nothing to group

        let context = ScanContext(home: home.url, projectLocations: [], runsSystemCommands: false)
        let items = AndroidScanner().items(in: context)
        let platforms = try #require(items.first { $0.id == "android.platforms.older" })
        #expect(platforms.title == "Older SDK platforms (3 versions)")
        #expect(platforms.detail == "28, 34, 36 · keeps 37.2")
        guard case .removePaths(let urls) = platforms.action else { Issue.record("expected paths"); return }
        #expect(urls.map(\.lastPathComponent) == ["android-28", "android-34", "android-36"])
        #expect(!items.contains { $0.id == "android.build-tools.older" })
    }
}

@Suite struct InactiveItemTests {
    @Test func picksOnlySafeItemsUnusedSinceCutoff() {
        let now = Date()
        func item(_ id: String, daysAgo: Double?, safety: Safety = .safe) -> CleanupItem {
            CleanupItem(
                id: id, title: id, size: 1, safety: safety, action: .removePaths([]),
                lastUsed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
            )
        }
        let category = CleanupCategory(id: "c", title: "c", symbol: "x", items: [
            item("old", daysAgo: 200),
            item("recent", daysAgo: 3),
            item("unknown", daysAgo: nil),
            item("old-review", daysAgo: 200, safety: .review),
        ])
        let cutoff = now.addingTimeInterval(-90 * 86_400)
        #expect(category.inactiveItems(notUsedSince: cutoff).map(\.id) == ["old"])
    }
}
