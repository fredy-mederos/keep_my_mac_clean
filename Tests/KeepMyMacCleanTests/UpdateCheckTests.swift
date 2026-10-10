import Foundation
import Testing
@testable import KeepMyMacClean

// UpdateCheck.swift is the same file in GitTree and Vibe Notepad, so these cover their update checks too.

@Suite struct VersionNumberTests {
    @Test func olderVersionsComeFirst() {
        #expect(VersionNumber.isVersion("0.8", olderThan: "0.10"))
        #expect(VersionNumber.isVersion("0.9.2", olderThan: "0.10.0"))
        #expect(VersionNumber.isVersion("1.0", olderThan: "1.0.1"))
        #expect(VersionNumber.isVersion("0.4", olderThan: "v0.5.0"))
    }

    @Test func sameOrNewerIsNotOlder() {
        #expect(!VersionNumber.isVersion("1.0", olderThan: "1.0.0"))
        #expect(!VersionNumber.isVersion("1.0.0", olderThan: "1.0"))
        #expect(!VersionNumber.isVersion("2.3.4", olderThan: "2.3.4"))
        #expect(!VersionNumber.isVersion("1.1", olderThan: "1.0.9"))
        #expect(!VersionNumber.isVersion("0.10.0", olderThan: "0.9.2"))
    }

    @Test func ignoresWhatFollowsTheNumbers() {
        #expect(!VersionNumber.isVersion("1.2.0-beta", olderThan: "1.2.0"))
        #expect(VersionNumber.isVersion("1.2.0-beta.3", olderThan: "1.2.1"))
    }

    @Test func buildsWithoutAVersionAreNotChecked() {
        #expect(!VersionNumber.isValid("–"))
        #expect(!VersionNumber.isValid(""))
        #expect(VersionNumber.isValid("0.4"))
        #expect(VersionNumber.fromTag("v1.5.0") == "1.5.0")
        #expect(VersionNumber.fromTag("1.5.0") == "1.5.0")
    }
}

@Suite struct ReleaseFeedTests {
    let feed = ReleaseFeed(repository: "acme/app", diskImageName: "App.dmg")

    @Test func readsTheAPIAndPrefersTheNamedDiskImage() throws {
        let json = """
        {"tag_name": "v0.5.0", "html_url": "https://github.com/acme/app/releases/tag/v0.5.0",
         "published_at": "2026-10-12T09:30:00Z", "draft": false, "prerelease": false, "body": "Notes",
         "assets": [{"name": "Other.dmg", "browser_download_url": "https://github.com/acme/app/releases/download/v0.5.0/Other.dmg"},
                    {"name": "App.dmg", "browser_download_url": "https://github.com/acme/app/releases/download/v0.5.0/App.dmg"}]}
        """
        let release = try feed.release(fromAPI: Data(json.utf8))
        #expect(release.version == "0.5.0")
        #expect(release.pageURL.absoluteString == "https://github.com/acme/app/releases/tag/v0.5.0")
        #expect(release.downloadURL?.lastPathComponent == "App.dmg")
        #expect(release.publishedAt == Date(timeIntervalSince1970: 1_791_797_400))
    }

    @Test func aReleaseWithoutADiskImageLinksToItsPage() throws {
        let json = #"{"tag_name": "0.6.0", "html_url": "https://github.com/acme/app/releases/tag/0.6.0", "published_at": null, "assets": []}"#
        let release = try feed.release(fromAPI: Data(json.utf8))
        #expect(release.version == "0.6.0")
        #expect(release.downloadURL == nil)
        #expect(release.publishedAt == nil)
    }

    @Test func theWebsitesLatestLinkNamesTheVersion() {
        let release = feed.release(fromPage: URL(string: "https://github.com/acme/app/releases/tag/v1.4.2")!)
        #expect(release?.version == "1.4.2")
        #expect(release?.downloadURL == nil)
        // Without releases, the link goes to the list of releases.
        #expect(feed.release(fromPage: URL(string: "https://github.com/acme/app/releases")!) == nil)
    }

    @Test func releasesSurviveBeingSaved() throws {
        let release = Release(version: "0.5.0", pageURL: URL(string: "https://github.com/acme/app/releases/tag/v0.5.0")!,
                              downloadURL: nil, publishedAt: Date(timeIntervalSince1970: 1_791_797_400))
        let data = try JSONEncoder().encode(release)
        #expect(try JSONDecoder().decode(Release.self, from: data) == release)
    }
}
